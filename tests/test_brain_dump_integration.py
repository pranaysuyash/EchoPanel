"""Integration tests for Brain Dump with WebSocket pipeline."""

import asyncio
import pytest
from datetime import datetime
from uuid import uuid4

from server.services.brain_dump_indexer import BrainDumpIndexer, initialize_indexer, shutdown_indexer
from server.services.brain_dump_integration import (
    BrainDumpWebSocketIntegration,
    initialize_integration,
    shutdown_integration,
    index_transcript_event
)
from server.db import StorageConfig, AudioSource


@pytest.fixture
async def brain_dump_system():
    """Create a fully initialized brain dump system."""
    import tempfile
    from pathlib import Path
    
    # Use temp file instead of in-memory for proper initialization
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test.db")
        config = StorageConfig(backend="sqlite", sqlite_path=db_path)
        
        # Initialize indexer
        indexer = BrainDumpIndexer(config)
        await indexer.start()
        
        # Initialize integration
        integration = initialize_integration(indexer)
        
        yield indexer, integration

        # Cleanup
        await shutdown_indexer()
        await shutdown_integration()


@pytest.mark.asyncio
async def test_end_to_end_session_lifecycle(brain_dump_system):
    """Test complete session lifecycle: start → transcript → end."""
    indexer, integration = brain_dump_system
    connection_id = "test-connection-123"
    
    # Start session
    session_id = await integration.start_session(
        connection_id=connection_id,
        title="Test Meeting",
        source_app="zoom"
    )
    assert session_id is not None
    
    # Add transcript segments
    for i in range(5):
        await integration.on_transcript(
            connection_id=connection_id,
            text=f"This is transcript segment {i}",
            source="system",
            speaker_id=f"speaker_{i % 2}",
            t0=float(i * 5),
            t1=float((i + 1) * 5),
            confidence=0.95
        )
    
    # Flush buffer
    await indexer._flush_buffer()
    
    # End session
    await integration.end_session(connection_id)
    
    # Verify session exists
    session = await indexer.adapter.get_session(session_id)
    assert session is not None
    assert session.title == "Test Meeting"
    assert session.ended_at is not None
    
    # Verify segments were stored
    segments = await indexer.adapter.get_segments_by_session(session_id)
    assert len(segments) == 5


@pytest.mark.asyncio
async def test_voice_note_flow(brain_dump_system):
    """Test voice note creation flow."""
    indexer, integration = brain_dump_system
    
    # Create voice note via indexer
    session_id = await indexer.on_voice_note(
        text="Remember to follow up with Sarah about the API",
        title="Follow-up reminder"
    )
    
    assert session_id is not None
    
    # Verify voice note session
    session = await indexer.adapter.get_session(session_id)
    assert session is not None
    assert session.source_app == "voice_note"
    assert session.ended_at is not None  # Auto-ended


@pytest.mark.asyncio
async def test_search_integration(brain_dump_system):
    """Test search functionality with stored data."""
    indexer, integration = brain_dump_system
    connection_id = "search-test"
    
    # Start session
    await integration.start_session(connection_id, title="Product Meeting")
    
    # Add searchable content
    await integration.on_transcript(
        connection_id=connection_id,
        text="Let's discuss the roadmap for Q2",
        source="system"
    )
    await integration.on_transcript(
        connection_id=connection_id,
        text="The API needs performance improvements",
        source="system"
    )
    await integration.on_transcript(
        connection_id=connection_id,
        text="We should hire more engineers",
        source="system"
    )
    
    # Flush to database
    await indexer._flush_buffer()
    
    # Search
    results = await indexer.adapter.search("roadmap")
    assert len(results) >= 1
    assert any("roadmap" in r.segment.text.lower() for r in results)
    
    # Search for API
    results = await indexer.adapter.search("API")
    assert len(results) >= 1


@pytest.mark.asyncio
async def test_session_pinning(brain_dump_system):
    """Test session pinning functionality."""
    indexer, integration = brain_dump_system
    connection_id = "pin-test"
    
    # Start and pin session
    session_id = await integration.start_session(connection_id, title="Important Meeting")
    await integration.pin_session(connection_id)
    
    # Verify pinned
    session = await indexer.adapter.get_session(session_id)
    assert session.is_pinned is True


@pytest.mark.asyncio
async def test_index_transcript_event_helper(brain_dump_system):
    """Test the index_transcript_event helper function."""
    indexer, integration = brain_dump_system
    connection_id = "helper-test"
    
    # Start session
    await integration.start_session(connection_id, title="Test")
    
    # Use helper
    event = {
        "type": "asr_final",
        "text": "This is a test transcript",
        "t0": 0.0,
        "t1": 5.0,
        "speaker": "Alice",
        "confidence": 0.95
    }
    
    await index_transcript_event(connection_id, event, source="system")
    await indexer._flush_buffer()
    
    # Verify
    results = await indexer.adapter.search("test transcript")
    assert len(results) >= 1


@pytest.mark.asyncio
async def test_multiple_connections(brain_dump_system):
    """Test handling multiple concurrent connections."""
    indexer, integration = brain_dump_system
    
    # Start multiple sessions
    conn_ids = [f"conn-{i}" for i in range(3)]
    session_ids = []
    
    for conn_id in conn_ids:
        sid = await integration.start_session(conn_id, title=f"Meeting {conn_id}")
        session_ids.append(sid)
    
    # Add transcripts to each
    for i, conn_id in enumerate(conn_ids):
        await integration.on_transcript(
            connection_id=conn_id,
            text=f"Content from connection {i}",
            source="system"
        )
    
    await indexer._flush_buffer()
    
    # Verify all sessions exist
    for sid in session_ids:
        session = await indexer.adapter.get_session(sid)
        assert session is not None
    
    # Verify stats
    stats = await indexer.get_stats()
    assert stats["session_count"] == 3
    assert stats["segment_count"] == 3


@pytest.mark.asyncio
async def test_buffer_flush_on_size():
    """Test that buffer flushes when it reaches size limit."""
    import tempfile
    from pathlib import Path
    
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test.db")
        config = StorageConfig(backend="sqlite", sqlite_path=db_path)
        indexer = BrainDumpIndexer(config, buffer_size=3)  # Small buffer
        await indexer.start()
        
        integration = BrainDumpWebSocketIntegration(indexer)
        connection_id = "buffer-test"
        
        # Start session
        await integration.start_session(connection_id, title="Buffer Test")
        
        # Add segments (should trigger auto-flush at 3)
        for i in range(5):
            await integration.on_transcript(
                connection_id=connection_id,
                text=f"Segment {i}",
                source="system"
            )
            await asyncio.sleep(0.01)  # Small delay
        
        # Give time for async flush
        await asyncio.sleep(0.1)
        
        # Manually flush remaining buffer
        await indexer._flush_buffer()
        
        # Verify all segments stored
        session_id = integration.get_session_id(connection_id)
        segments = await indexer.adapter.get_segments_by_session(session_id)
        assert len(segments) == 5
        
        await indexer.stop()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
