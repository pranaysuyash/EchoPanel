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
    assert retrieved.confidence == 0.95


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
    ]
    
    for seg in segments:
        await adapter.save_segment(seg)
    
    # Search
    results = await adapter.search("roadmap")
    assert len(results) >= 1


@pytest.mark.asyncio
async def test_get_stats(sqlite_adapter):
    """Test getting storage statistics."""
    adapter = sqlite_adapter
    
    stats = await adapter.get_stats()
    assert stats["backend"] == "sqlite"


@pytest.mark.asyncio
async def test_health_check(sqlite_adapter):
    """Test health check."""
    adapter = sqlite_adapter
    
    healthy = await adapter.health_check()
    assert healthy is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
