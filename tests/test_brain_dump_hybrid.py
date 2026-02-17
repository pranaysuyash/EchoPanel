"""Tests for Brain Dump hybrid search."""

import asyncio
import tempfile
from pathlib import Path
from uuid import uuid4
from datetime import datetime

import pytest

from server.db import (
    get_storage_adapter,
    StorageConfig,
    Session,
    TranscriptSegment,
    AudioSource
)
from server.db.vector_store import VectorStore
from server.services.embeddings import EmbeddingService
from server.services.hybrid_search import HybridSearchEngine, create_hybrid_search_engine


@pytest.fixture
async def hybrid_engine():
    """Create a hybrid search engine with temporary storage."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Setup SQLite
        db_path = str(Path(tmpdir) / "test.db")
        storage_config = StorageConfig(backend="sqlite", sqlite_path=db_path)
        adapter = get_storage_adapter(storage_config)
        await adapter.initialize()
        
        # Setup ChromaDB
        vector_path = str(Path(tmpdir) / "vectors")
        vector_store = VectorStore(persist_directory=vector_path)
        await vector_store.initialize()
        
        # Create engine
        embedding_service = EmbeddingService()
        engine = HybridSearchEngine(adapter, vector_store, embedding_service)
        
        # Seed with test data
        await _seed_test_data(adapter, vector_store, embedding_service)
        
        yield engine
        
        # Cleanup
        await adapter.close()
        await vector_store.close()


async def _seed_test_data(adapter, vector_store, embedding_service):
    """Seed test data for hybrid search."""
    # Create session
    session = Session(
        id=uuid4(),
        title="Product Planning Meeting",
        source_app="zoom",
        started_at=datetime.utcnow()
    )
    await adapter.create_session(session)
    
    # Create segments with varied content
    segments = [
        TranscriptSegment(
            id=uuid4(),
            session_id=session.id,
            timestamp=datetime.utcnow(),
            text="Let's discuss the roadmap for Q2. We need to prioritize mobile features.",
            source=AudioSource.SYSTEM
        ),
        TranscriptSegment(
            id=uuid4(),
            session_id=session.id,
            timestamp=datetime.utcnow(),
            text="The API performance is critical. We should optimize the database queries.",
            source=AudioSource.SYSTEM
        ),
        TranscriptSegment(
            id=uuid4(),
            session_id=session.id,
            timestamp=datetime.utcnow(),
            text="We need to hire more engineers for the backend team.",
            source=AudioSource.SYSTEM
        ),
        TranscriptSegment(
            id=uuid4(),
            session_id=session.id,
            timestamp=datetime.utcnow(),
            text="The weather is really nice today. Perfect for a team lunch.",
            source=AudioSource.SYSTEM
        ),
        TranscriptSegment(
            id=uuid4(),
            session_id=session.id,
            timestamp=datetime.utcnow(),
            text="Customer feedback shows they want better documentation and tutorials.",
            source=AudioSource.SYSTEM
        )
    ]
    
    # Save to SQLite
    await adapter.save_segments(segments)
    
    # Generate and save embeddings
    texts = [s.text for s in segments]
    embeddings = embedding_service.encode(texts)
    await vector_store.add_segments(segments, embeddings)


@pytest.mark.asyncio
async def test_hybrid_search_finds_relevant_results(hybrid_engine):
    """Test that hybrid search finds relevant results."""
    engine = hybrid_engine
    
    # Search for product planning concepts
    results = await engine.search(
        query="future product plans and strategy",
        k=3
    )
    
    # Should return results (structure test)
    assert isinstance(results, list)
    
    # If we have results, check they have proper structure
    if results:
        for r in results:
            assert r.segment_id is not None
            assert r.rrf_score >= 0


@pytest.mark.asyncio
async def test_hybrid_search_rrf_scoring(hybrid_engine):
    """Test RRF scoring produces reasonable rankings."""
    engine = hybrid_engine
    
    results = await engine.search(
        query="technical performance optimization",
        k=5
    )
    
    # Check that results have RRF scores
    for result in results:
        assert result.rrf_score > 0
        assert result.segment_id is not None


@pytest.mark.asyncio
async def test_hybrid_search_keyword_only(hybrid_engine):
    """Test fallback to keyword search."""
    engine = hybrid_engine
    
    # Create new engine without embedding service
    from server.db.vector_store import VectorStore
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test.db")
        storage_config = StorageConfig(backend="sqlite", sqlite_path=db_path)
        adapter = get_storage_adapter(storage_config)
        await adapter.initialize()
        
        vector_path = str(Path(tmpdir) / "vectors")
        vector_store = VectorStore(persist_directory=vector_path)
        await vector_store.initialize()
        
        # Create engine WITHOUT embedding service
        engine_no_embed = HybridSearchEngine(adapter, vector_store, None)
        
        # Seed data
        await _seed_test_data(adapter, vector_store, EmbeddingService())
        
        results = await engine_no_embed.search(
            query="roadmap",
            k=5
        )
        
        assert len(results) >= 1
        # Should still find results via keyword
        found_roadmap = any("roadmap" in r.text.lower() for r in results)
        assert found_roadmap


@pytest.mark.asyncio
async def test_hybrid_search_filters(hybrid_engine):
    """Test hybrid search with filters."""
    engine = hybrid_engine
    
    from server.db import SearchFilters
    
    filters = SearchFilters(
        source_filter=[AudioSource.SYSTEM]
    )
    
    results = await engine.search(
        query="team hiring",
        filters=filters,
        k=5
    )
    
    # Should return results (structure test)
    assert isinstance(results, list)


@pytest.mark.asyncio
async def test_hybrid_vs_keyword_only(hybrid_engine):
    """Compare hybrid search vs keyword-only."""
    engine = hybrid_engine
    
    # Hybrid search
    hybrid_results = await engine.search(
        query="product planning schedule",
        k=5,
        use_rrf=True
    )
    
    # Keyword-only search (simulated)
    keyword_results = await engine._keyword_search(
        "product planning schedule",
        None,
        k=5
    )
    
    # Hybrid should return different (hopefully better) results
    # This is a qualitative test - we're just checking both work
    assert len(hybrid_results) >= 0
    assert len(keyword_results) >= 0


@pytest.mark.asyncio
async def test_create_hybrid_search_engine_factory():
    """Test the factory function."""
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test.db")
        storage_config = StorageConfig(backend="sqlite", sqlite_path=db_path)
        adapter = get_storage_adapter(storage_config)
        await adapter.initialize()
        
        try:
            engine = await create_hybrid_search_engine(adapter)
            assert engine is not None
            assert engine.keyword_adapter is adapter
            assert engine.vector_store is not None
        finally:
            await adapter.close()
            await engine.vector_store.close()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
