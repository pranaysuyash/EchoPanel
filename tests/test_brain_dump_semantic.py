"""Tests for Brain Dump semantic search (embeddings + vector store)."""

import asyncio
import tempfile
from pathlib import Path

import pytest

from server.services.embeddings import EmbeddingService, get_embedding_service, reset_embedding_service
from server.db.vector_store import VectorStore
from server.db import TranscriptSegment, AudioSource


class TestEmbeddingService:
    """Tests for the embedding service."""
    
    @pytest.fixture(autouse=True)
    def reset_service(self):
        """Reset embedding service before each test."""
        reset_embedding_service()
        yield
        reset_embedding_service()
    
    def test_is_available(self):
        """Test that embedding service detects availability."""
        service = EmbeddingService()
        # Should be True since we installed sentence-transformers
        assert service.is_available() is True
    
    def test_model_properties(self):
        """Test model dimension and name."""
        service = EmbeddingService()
        assert service.model_name == "all-MiniLM-L6-v2"
        
        # Dimension is lazy-loaded
        assert service._dimension is None
        dim = service.dimension
        assert dim == 384  # all-MiniLM-L6-v2 has 384 dimensions
        assert service._dimension == 384
    
    def test_encode_single(self):
        """Test encoding a single text."""
        service = EmbeddingService()
        embedding = service.encode_single("This is a test")
        
        assert isinstance(embedding, list)
        assert len(embedding) == 384
        assert all(isinstance(x, float) for x in embedding)
    
    def test_encode_batch(self):
        """Test encoding multiple texts."""
        service = EmbeddingService()
        texts = [
            "First text to embed",
            "Second text to embed",
            "Third text to embed"
        ]
        
        embeddings = service.encode(texts)
        
        assert len(embeddings) == 3
        for emb in embeddings:
            assert len(emb) == 384
    
    def test_similar_texts_have_similar_embeddings(self):
        """Test that semantically similar texts have high similarity."""
        service = EmbeddingService()
        
        texts = [
            "The cat sat on the mat",
            "A cat was sitting on a mat",  # Similar meaning
            "The weather is nice today"     # Different meaning
        ]
        
        embeddings = service.encode(texts)
        
        # Calculate cosine similarity
        def cosine_similarity(a, b):
            import math
            dot = sum(x * y for x, y in zip(a, b))
            norm_a = math.sqrt(sum(x * x for x in a))
            norm_b = math.sqrt(sum(x * x for x in b))
            return dot / (norm_a * norm_b)
        
        sim_similar = cosine_similarity(embeddings[0], embeddings[1])
        sim_different = cosine_similarity(embeddings[0], embeddings[2])
        
        # Similar texts should have higher similarity
        assert sim_similar > sim_different
        assert sim_similar > 0.8  # Should be quite similar
    
    def test_get_embedding_service_singleton(self):
        """Test that get_embedding_service returns singleton."""
        service1 = get_embedding_service()
        service2 = get_embedding_service()
        assert service1 is service2


class TestVectorStore:
    """Tests for the vector store."""
    
    @pytest.fixture
    async def vector_store(self):
        """Create a temporary vector store."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = VectorStore(persist_directory=str(Path(tmpdir) / "vectors"))
            await store.initialize()
            yield store
            await store.close()
    
    @pytest.mark.asyncio
    async def test_initialize(self, vector_store):
        """Test vector store initialization."""
        store = vector_store
        assert store._client is not None
        assert store._collection is not None
    
    @pytest.mark.asyncio
    async def test_add_and_search_segments(self, vector_store):
        """Test adding segments and searching."""
        store = vector_store
        
        # Create test segments
        from uuid import uuid4
        from datetime import datetime
        
        segments = [
            TranscriptSegment(
                id=uuid4(),
                session_id=uuid4(),
                timestamp=datetime.utcnow(),
                text="The product roadmap for Q2 includes API improvements",
                source=AudioSource.SYSTEM
            ),
            TranscriptSegment(
                id=uuid4(),
                session_id=uuid4(),
                timestamp=datetime.utcnow(),
                text="We need to hire more engineers for the backend team",
                source=AudioSource.SYSTEM
            ),
            TranscriptSegment(
                id=uuid4(),
                session_id=uuid4(),
                timestamp=datetime.utcnow(),
                text="The weather is really nice outside today",
                source=AudioSource.SYSTEM
            )
        ]
        
        # Generate embeddings
        service = EmbeddingService()
        embeddings = service.encode([s.text for s in segments])
        
        # Add to store
        await store.add_segments(segments, embeddings)
        
        # Search
        query_embedding = service.encode_single("product planning schedule")
        results = await store.similarity_search(query_embedding, k=2)
        
        assert len(results) == 2
        # First result should be the roadmap segment (most similar)
        assert str(segments[0].id) in [r[0] for r in results]
    
    @pytest.mark.asyncio
    async def test_stats(self, vector_store):
        """Test getting stats."""
        store = vector_store
        
        stats = await store.get_stats()
        assert stats["initialized"] is True
        assert stats["count"] == 0
    
    @pytest.mark.asyncio
    async def test_health_check(self, vector_store):
        """Test health check."""
        store = vector_store
        assert await store.health_check() is True


class TestSemanticIntegration:
    """Integration tests for semantic search end-to-end."""
    
    @pytest.mark.asyncio
    async def test_end_to_end_semantic_search(self):
        """Test complete flow: segments → embeddings → search."""
        from uuid import uuid4
        from datetime import datetime
        
        with tempfile.TemporaryDirectory() as tmpdir:
            # Setup
            store = VectorStore(persist_directory=str(Path(tmpdir) / "vectors"))
            await store.initialize()
            
            try:
                service = EmbeddingService()
                
                # Create meeting transcript segments
                meeting_segments = [
                    TranscriptSegment(
                        id=uuid4(),
                        session_id=uuid4(),
                        timestamp=datetime.utcnow(),
                        text="Let's discuss the roadmap for Q2. We need to prioritize mobile.",
                        source=AudioSource.SYSTEM
                    ),
                    TranscriptSegment(
                        id=uuid4(),
                        session_id=uuid4(),
                        timestamp=datetime.utcnow(),
                        text="The API performance is becoming a bottleneck. We should optimize it.",
                        source=AudioSource.SYSTEM
                    ),
                    TranscriptSegment(
                        id=uuid4(),
                        session_id=uuid4(),
                        timestamp=datetime.utcnow(),
                        text="I had lunch at the new Italian restaurant. It was delicious.",
                        source=AudioSource.SYSTEM
                    )
                ]
                
                # Generate and store embeddings
                texts = [s.text for s in meeting_segments]
                embeddings = service.encode(texts)
                await store.add_segments(meeting_segments, embeddings)
                
                # Search for planning-related content
                query = "future plans and strategy"
                query_embedding = service.encode_single(query)
                results = await store.similarity_search(query_embedding, k=2)
                
                assert len(results) == 2
                result_ids = [r[0] for r in results]
                
                # Should find the roadmap and API segments (both work-related)
                roadmap_id = str(meeting_segments[0].id)
                api_id = str(meeting_segments[1].id)
                lunch_id = str(meeting_segments[2].id)
                
                assert roadmap_id in result_ids or api_id in result_ids
                # Lunch segment should NOT be in top results for work query
                assert lunch_id not in result_ids
                
            finally:
                await store.close()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
