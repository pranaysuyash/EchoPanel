"""Data models for Brain Dump storage."""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import List, Optional, Dict, Any
from uuid import UUID, uuid4
import json


class AudioSource(Enum):
    """Source of audio capture."""
    SYSTEM = "system"           # System audio (Zoom, browser, etc.)
    MICROPHONE = "microphone"   # Raw microphone input
    VOICE_NOTE = "voice_note"   # Intentional voice notes


class SyncStatus(Enum):
    """Sync status for cloud backup."""
    LOCAL = "local"
    SYNCED = "synced"
    PENDING = "pending"
    ERROR = "error"


@dataclass
class Session:
    """A recording session (meeting, lecture, etc.)."""
    
    id: UUID = field(default_factory=uuid4)
    started_at: datetime = field(default_factory=datetime.utcnow)
    ended_at: Optional[datetime] = None
    title: Optional[str] = None
    source_app: Optional[str] = None  # "zoom", "chrome", "voice_note"
    tags: List[str] = field(default_factory=list)
    is_pinned: bool = False
    audio_file_path: Optional[str] = None
    
    # Sync metadata
    last_modified: datetime = field(default_factory=datetime.utcnow)
    sync_status: SyncStatus = SyncStatus.LOCAL
    
    # Additional metadata
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "id": str(self.id),
            "started_at": self.started_at.isoformat(),
            "ended_at": self.ended_at.isoformat() if self.ended_at else None,
            "title": self.title,
            "source_app": self.source_app,
            "tags": self.tags,
            "is_pinned": self.is_pinned,
            "audio_path": self.audio_file_path,
            "last_modified": self.last_modified.isoformat(),
            "sync_status": self.sync_status.value,
            "metadata": self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Session":
        """Create from dictionary."""
        return cls(
            id=UUID(data["id"]),
            started_at=datetime.fromisoformat(data["started_at"]),
            ended_at=datetime.fromisoformat(data["ended_at"]) if data.get("ended_at") else None,
            title=data.get("title"),
            source_app=data.get("source_app"),
            tags=data.get("tags", []),
            is_pinned=data.get("is_pinned", False),
            audio_file_path=data.get("audio_path"),
            last_modified=datetime.fromisoformat(data.get("last_modified", data["started_at"])),
            sync_status=SyncStatus(data.get("sync_status", "local")),
            metadata=data.get("metadata", {})
        )


@dataclass
class TranscriptSegment:
    """A single transcript segment from ASR."""
    
    id: UUID = field(default_factory=uuid4)
    session_id: UUID = field(default_factory=uuid4)
    timestamp: datetime = field(default_factory=datetime.utcnow)
    relative_time: float = 0.0  # Seconds from session start
    source: AudioSource = AudioSource.SYSTEM
    speaker_id: Optional[str] = None
    text: str = ""
    confidence: float = 1.0
    
    # For context retrieval
    prev_segment_id: Optional[UUID] = None
    next_segment_id: Optional[UUID] = None
    
    # For semantic search (optional, populated later)
    embedding: Optional[List[float]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "id": str(self.id),
            "session_id": str(self.session_id),
            "timestamp": self.timestamp.isoformat(),
            "relative_time": self.relative_time,
            "source": self.source.value,
            "speaker_id": self.speaker_id,
            "text": self.text,
            "confidence": self.confidence,
            "prev_segment_id": str(self.prev_segment_id) if self.prev_segment_id else None,
            "next_segment_id": str(self.next_segment_id) if self.next_segment_id else None,
            # Note: embedding not included in dict (stored separately)
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TranscriptSegment":
        """Create from dictionary."""
        return cls(
            id=UUID(data["id"]),
            session_id=UUID(data["session_id"]),
            timestamp=datetime.fromisoformat(data["timestamp"]),
            relative_time=data.get("relative_time", 0.0),
            source=AudioSource(data.get("source", "system")),
            speaker_id=data.get("speaker_id"),
            text=data["text"],
            confidence=data.get("confidence", 1.0),
            prev_segment_id=UUID(data["prev_segment_id"]) if data.get("prev_segment_id") else None,
            next_segment_id=UUID(data["next_segment_id"]) if data.get("next_segment_id") else None
        )


@dataclass
class SearchFilters:
    """Filters for search queries."""
    
    time_range_start: Optional[datetime] = None
    time_range_end: Optional[datetime] = None
    source_filter: Optional[List[AudioSource]] = None
    speaker_filter: Optional[List[str]] = None
    session_ids: Optional[List[UUID]] = None
    tags: Optional[List[str]] = None
    min_confidence: float = 0.0


@dataclass
class SearchResult:
    """Result from brain dump search."""
    
    segment: TranscriptSegment
    session: Optional[Session] = None
    relevance_score: float = 1.0
    context_before: List[TranscriptSegment] = field(default_factory=list)
    context_after: List[TranscriptSegment] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "segment": self.segment.to_dict(),
            "session": self.session.to_dict() if self.session else None,
            "relevance_score": self.relevance_score,
            "context_before": [s.to_dict() for s in self.context_before],
            "context_after": [s.to_dict() for s in self.context_after]
        }


@dataclass
class StorageConfig:
    """Configuration for storage backend."""
    
    backend: str = "sqlite"  # "sqlite", "postgresql", "google_drive"
    
    # SQLite options
    sqlite_path: str = "~/.echopanel/brain_dump.db"
    
    # PostgreSQL options
    postgres_url: Optional[str] = None
    
    # Google Drive options
    google_drive_enabled: bool = False
    google_drive_sync_mode: str = "off"  # "off", "backup", "bidirectional"
    google_drive_encrypt: bool = False
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "StorageConfig":
        """Create from dictionary."""
        return cls(
            backend=data.get("backend", "sqlite"),
            sqlite_path=data.get("sqlite_path", "~/.echopanel/brain_dump.db"),
            postgres_url=data.get("postgres_url"),
            google_drive_enabled=data.get("google_drive_enabled", False),
            google_drive_sync_mode=data.get("google_drive_sync_mode", "off"),
            google_drive_encrypt=data.get("google_drive_encrypt", False)
        )
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "backend": self.backend,
            "sqlite_path": self.sqlite_path,
            "postgres_url": self.postgres_url,
            "google_drive_enabled": self.google_drive_enabled,
            "google_drive_sync_mode": self.google_drive_sync_mode,
            "google_drive_encrypt": self.google_drive_encrypt
        }
