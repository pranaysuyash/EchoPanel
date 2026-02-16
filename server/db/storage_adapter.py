"""Abstract base class for storage adapters."""

from abc import ABC, abstractmethod
from typing import List, Optional
from uuid import UUID

from .models import (
    Session, 
    TranscriptSegment, 
    SearchFilters, 
    SearchResult,
    StorageConfig
)


class StorageAdapter(ABC):
    """Abstract base class for transcript storage backends.
    
    Implementations:
    - SQLiteAdapter: Default local storage
    - PostgreSQLAdapter: Power user option with pgvector
    - GoogleDriveAdapter: Cloud backup/sync
    """
    
    def __init__(self, config: StorageConfig):
        self.config = config
    
    @abstractmethod
    async def initialize(self) -> None:
        """Initialize the storage backend (create tables, etc.)."""
        pass
    
    @abstractmethod
    async def close(self) -> None:
        """Close connections and cleanup."""
        pass
    
    # Session operations
    
    @abstractmethod
    async def create_session(self, session: Session) -> Session:
        """Create a new recording session."""
        pass
    
    @abstractmethod
    async def get_session(self, session_id: UUID) -> Optional[Session]:
        """Get a session by ID."""
        pass
    
    @abstractmethod
    async def update_session(self, session: Session) -> Session:
        """Update an existing session."""
        pass
    
    @abstractmethod
    async def end_session(self, session_id: UUID) -> Optional[Session]:
        """Mark a session as ended (set ended_at)."""
        pass
    
    @abstractmethod
    async def list_sessions(
        self, 
        limit: int = 100, 
        offset: int = 0,
        pinned_only: bool = False
    ) -> List[Session]:
        """List sessions, most recent first."""
        pass
    
    @abstractmethod
    async def delete_session(self, session_id: UUID) -> bool:
        """Delete a session and all its segments. Returns True if deleted."""
        pass
    
    # Segment operations
    
    @abstractmethod
    async def save_segment(self, segment: TranscriptSegment) -> TranscriptSegment:
        """Save a transcript segment."""
        pass
    
    @abstractmethod
    async def save_segments(self, segments: List[TranscriptSegment]) -> List[TranscriptSegment]:
        """Save multiple segments (batch insert)."""
        pass
    
    @abstractmethod
    async def get_segment(self, segment_id: UUID) -> Optional[TranscriptSegment]:
        """Get a segment by ID."""
        pass
    
    @abstractmethod
    async def get_segments_by_session(
        self, 
        session_id: UUID,
        limit: int = 1000,
        offset: int = 0
    ) -> List[TranscriptSegment]:
        """Get all segments for a session, ordered by timestamp."""
        pass
    
    @abstractmethod
    async def get_segment_context(
        self,
        segment_id: UUID,
        context_size: int = 3
    ) -> tuple[List[TranscriptSegment], TranscriptSegment, List[TranscriptSegment]]:
        """Get a segment with surrounding context.
        
        Returns: (context_before, segment, context_after)
        """
        pass
    
    # Search operations
    
    @abstractmethod
    async def search(
        self, 
        query: str, 
        filters: Optional[SearchFilters] = None,
        limit: int = 20,
        offset: int = 0
    ) -> List[SearchResult]:
        """Full-text search with filters.
        
        Args:
            query: Search query string
            filters: Optional search filters
            limit: Max results to return
            offset: Pagination offset
            
        Returns:
            List of search results with relevance scores
        """
        pass
    
    @abstractmethod
    async def semantic_search(
        self,
        query_embedding: List[float],
        filters: Optional[SearchFilters] = None,
        limit: int = 20
    ) -> List[SearchResult]:
        """Vector similarity search (requires embeddings).
        
        Args:
            query_embedding: Vector embedding of query
            filters: Optional search filters
            limit: Max results to return
            
        Returns:
            List of search results sorted by similarity
        """
        pass
    
    # Statistics and maintenance
    
    @abstractmethod
    async def get_stats(self) -> dict:
        """Get storage statistics.
        
        Returns:
            Dict with counts, sizes, etc.
        """
        pass
    
    @abstractmethod
    async def compact(self) -> None:
        """Compact/optimize the database."""
        pass
    
    @abstractmethod
    async def delete_old_sessions(self, days: int = 90) -> int:
        """Delete sessions older than N days (except pinned).
        
        Returns:
            Number of sessions deleted
        """
        pass
    
    # Health check
    
    @abstractmethod
    async def health_check(self) -> bool:
        """Check if storage is healthy/accessible."""
        pass


class StorageError(Exception):
    """Base exception for storage operations."""
    pass


class StorageNotInitializedError(StorageError):
    """Raised when storage is not initialized."""
    pass


class StorageConnectionError(StorageError):
    """Raised when connection to storage fails."""
    pass


class StorageQueryError(StorageError):
    """Raised when a query fails."""
    pass
