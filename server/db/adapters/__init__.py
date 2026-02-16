"""Storage adapter implementations."""

from .sqlite_adapter import SQLiteAdapter

try:
    from .postgres_adapter import PostgreSQLAdapter
except ImportError:
    PostgreSQLAdapter = None

try:
    from .google_drive_adapter import GoogleDriveAdapter
except ImportError:
    GoogleDriveAdapter = None

__all__ = [
    "SQLiteAdapter",
    "PostgreSQLAdapter",
    "GoogleDriveAdapter"
]
