"""Brain Dump database storage module."""

from .models import (
    Session,
    TranscriptSegment,
    AudioSource,
    SyncStatus,
    SearchFilters,
    SearchResult,
    StorageConfig
)
from .storage_adapter import StorageAdapter, StorageError
from .adapters import SQLiteAdapter

# Optional adapters
try:
    from .adapters import PostgreSQLAdapter
except ImportError:
    PostgreSQLAdapter = None

try:
    from .adapters import GoogleDriveAdapter
except ImportError:
    GoogleDriveAdapter = None


def get_storage_adapter(config: StorageConfig) -> StorageAdapter:
    """Factory function to get appropriate storage adapter.
    
    Args:
        config: Storage configuration
        
    Returns:
        StorageAdapter instance
        
    Raises:
        ValueError: If backend is not supported
        ImportError: If optional backend dependencies are not installed
    """
    if config.backend == "sqlite":
        return SQLiteAdapter(config)
    
    elif config.backend == "postgresql":
        if PostgreSQLAdapter is None:
            raise ImportError(
                "PostgreSQL support requires 'asyncpg' and 'pgvector'. "
                "Install with: pip install echopanel[postgres]"
            )
        return PostgreSQLAdapter(config)
    
    elif config.backend == "google_drive":
        if GoogleDriveAdapter is None:
            raise ImportError(
                "Google Drive support requires 'google-api-python-client'. "
                "Install with: pip install echopanel[gdrive]"
            )
        return GoogleDriveAdapter(config)
    
    else:
        raise ValueError(f"Unknown storage backend: {config.backend}")


__all__ = [
    # Models
    "Session",
    "TranscriptSegment", 
    "AudioSource",
    "SyncStatus",
    "SearchFilters",
    "SearchResult",
    "StorageConfig",
    # Base
    "StorageAdapter",
    "StorageError",
    # Adapters
    "SQLiteAdapter",
    "PostgreSQLAdapter",
    "GoogleDriveAdapter",
    # Factory
    "get_storage_adapter"
]
