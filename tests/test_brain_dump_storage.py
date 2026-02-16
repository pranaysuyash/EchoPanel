"""Tests for Brain Dump storage adapters."""

import asyncio
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest

from server.db import (
    get_storage_adapter,
    Session,
    TranscriptSegment,
    AudioSource,
    SearchFilters,
    StorageConfig
)


@pytest.fixture
async def sqlite_adapter():
    """Create a temporary SQLite adapter for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        config = StorageConfig(
            backend="sqlite",
            sqlite_path=str(Path(tmpdir) / "test.db")
        )
        adapter = get_storage_adapter(config)
        await adapter.initialize()
        yield adapter
        await adapter.close()


@pytest.mark.asyncio
async def test_create_and_get_session(sqlite_adapter):
    """Test creating and retrieving a session."""
    adapter = sqlite_adapter
    
    # Create session
    session = Session(
        title="Test Meeting",
        source_app="zoom",
        tags=["test", "meeting"],
        is_pinned=True
    )
    
    created = await adapter.create_session(session)
    assert created.id == session.id
    assert created.title == "Test Meeting"
    
    # Get session
    retrieved = await adapter.get_session(session.id)
    assert retrieved is not None
    assert retrieved.id == session.id
    assert retrieved.title == "Test Meeting"
    assert retrieved.source_app == "zoom"
    assert retrieved.tags == ["test", "meeting"]
    assert retrieved.is_pinned is True


@pytest.mark.asyncio
async def test_list_sessions(sqlite_adapter):
    """Test listing sessions."""
    adapter = sqlite_adapter
    
    # Create multiple sessions
    for i in range(5):
        session = Session(
            title=f"Session {i}",
            is_pinned=(i == 0)  # Pin first session
        )
        await adapter.create_session(session)
    
    # List all
    all_sessions = await adapter.list_sessions(limit=10)
    assert len(all_sessions) == 5
    
    # List pinned only
    pinned = await adapter.list_sessions(pinned_only=True)
    assert len(pinned) == 1
    assert pinned[0].is_pinned is True
    
    # Test pagination
    page1 = await adapter.list_sessions(limit=2, offset=0)
    assert len(page1) == 2
    
    page2 = await adapter.list_sessions(limit=2, offset=2)
    assert len(page2) == 2


@pytest.mark.asyncio
async def test_end_session(sqlite_adapter):
    """Test ending a session."""
    adapter = sqlite_adapter
    
    session = Session(title="Ongoing Meeting")
    await adapter.create_session(session)
    
    # End session
    ended = await adapter.end_session(session.id)
    assert ended is not None
    assert ended.ended_at is not None
    
    # Verify
    retrieved = await adapter.get_session(session.id)
    assert retrieved.ended_at is not None


@pytest.mark.asyncio
async def test_save_and_get_segment(sqlite_adapter):
    """Test saving and retrieving a segment."""
    adapter = sqlite_adapter
    
    # Create session first
    session = Session(title="Test Session")
    await adapter.create_session(session)
    
    # Create segment
    segment = TranscriptSegment(
        session_id=session.id,
        text="Hello, this is a test",
        source=AudioSource.SYSTEM,
        speaker_id="speaker_1",
        confidence=0.95,
        relative_time=5.0
    )
    
    saved = await adapter.save_segment(segment)
    assert saved.id == segment.id
    
    # Get segment
    retrieved = await adapter.get_segment(segment.id)
    assert retrieved is not None
    assert retrieved.text == "Hello, this is a test"
    assert retrieved.source == AudioSource.SYSTEM
    assert retrieved.confidence == 0.95


@pytest.mark.asyncio
async def test_get_segments_by_session(sqlite_adapter):
    """Test getting segments for a session."""
    adapter = sqlite_adapter
    
    # Create session
    session = Session(title="Test Session")
    await adapter.create_session(session)
    
    # Create multiple segments
    segments = []
    for i in range(10):
        segment = TranscriptSegment(
            session_id=session.id,
            text=f"Segment {i}",
            relative_time=float(i),
            timestamp=datetime.utcnow() + timedelta(seconds=i)
        )
        segments.append(segment)
        await adapter.save_segment(segment)
    
    # Get all segments
    retrieved = await adapter.get_segments_by_session(session.id)
    assert len(retrieved) == 10
    
    # Verify order
    for i, seg in enumerate(retrieved):
        assert seg.text == f"Segment {i}"


@pytest.mark.asyncio
async def test_batch_save_segments(sqlite_adapter):
    """Test batch saving segments."""
    adapter = sqlite_adapter
    
    # Create session
    session = Session(title="Test Session")
    await adapter.create_session(session)
    
    # Create segments
    segments = [
        TranscriptSegment(
            session_id=session.id,
            text=f"Batch segment {i}",
            relative_time=float(i)
        )
        for i in range(100)
    ]
    
    # Batch save
    saved = await adapter.save_segments(segments)
    assert len(saved) == 100
    
    # Verify
    retrieved = await adapter.get_segments_by_session(session.id)
    assert len(retrieved) == 100


@pytest.mark.asyncio
async def test_search_keyword(sqlite_adapter):
    """Test keyword search."""
    adapter = sqlite_adapter
    
    # Create session
    session = Session(title="Product Meeting")
    await adapter.create_session(session)
    
    # Create segments with specific text
    segments = [
        TranscriptSegment(session_id=session.id, text="Let's discuss the roadmap"),
        TranscriptSegment(session_id=session.id, text="The API needs improvements"),
        TranscriptSegment(session_id=session.id, text="We should prioritize mobile"),
        TranscriptSegment(session_id=session.id, text="Backend scaling is important"),
    ]
    
    for seg in segments:
        await adapter.save_segment(seg)
    
    # Search
    results = await adapter.search("roadmap")
    assert len(results) >= 1
    assert any("roadmap" in r.segment.text.lower() for r in results)
    
    # Search with filters
    results = await adapter.search("API")
    assert len(results) >= 1


@pytest.mark.asyncio
async def test_delete_session(sqlite_adapter):
    """Test deleting a session (cascades to segments)."""
    adapter = sqlite_adapter
    
    # Create session with segments
    session = Session(title="To Be Deleted")
    await adapter.create_session(session)
    
    for i in range(5):
        segment = TranscriptSegment(
            session_id=session.id,
            text=f"Segment {i}"
        )
        await adapter.save_segment(segment)
    
    # Delete
    deleted = await adapter.delete_session(session.id)
    assert deleted is True
    
    # Verify session deleted
    retrieved = await adapter.get_session(session.id)
    assert retrieved is None
    
    # Verify segments deleted (cascade)
    segments = await adapter.get_segments_by_session(session.id)
    assert len(segments) == 0


@pytest.mark.asyncio
async def test_get_stats(sqlite_adapter):
    """Test getting storage statistics."""
    adapter = sqlite_adapter
    
    # Initially empty
    stats = await adapter.get_stats()
    assert stats["backend"] == "sqlite"
    assert stats["session_count"] == 0
    assert stats["segment_count"] == 0
    
    # Add data
    session = Session(title="Test")
    await adapter.create_session(session)
    
    for i in range(10):
        segment = TranscriptSegment(session_id=session.id, text=f"Seg {i}")
        await adapter.save_segment(segment)
    
    # Check stats again
    stats = await adapter.get_stats()
    assert stats["session_count"] == 1
    assert stats["segment_count"] == 10


@pytest.mark.asyncio
async def test_health_check(sqlite_adapter):
    """Test health check."""
    adapter = sqlite_adapter
    
    healthy = await adapter.health_check()
    assert healthy is True


@pytest.mark.asyncio
async def test_delete_old_sessions(sqlite_adapter):
    """Test deleting old sessions."""
    adapter = sqlite_adapter
    
    # Create old session (more than 90 days ago)
    old_session = Session(
        title="Old Session",
        started_at=datetime.utcnow() - timedelta(days=100)
    )
    await adapter.create_session(old_session)
    
    # Create recent session
    recent_session = Session(title="Recent Session")
    await adapter.create_session(recent_session)
    
    # Create pinned old session (should not be deleted)
    pinned_old = Session(
        title="Pinned Old",
        started_at=datetime.utcnow() - timedelta(days=100),
        is_pinned=True
    )
    await adapter.create_session(pinned_old)
    
    # Delete old sessions
    deleted = await adapter.delete_old_sessions(days=90)
    assert deleted == 1  # Only the unpinned old one
    
    # Verify
    assert await adapter.get_session(old_session.id) is None
    assert await adapter.get_session(recent_session.id) is not None
    assert await adapter.get_session(pinned_old.id) is not None  # Pinned preserved


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
