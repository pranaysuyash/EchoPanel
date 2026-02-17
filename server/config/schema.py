"""Configuration schema using Pydantic.

This module defines the configuration structure with validation.
"""

import os
from enum import Enum
from pathlib import Path
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator


class StorageBackend(str, Enum):
    """Storage backend types."""
    SQLITE = "sqlite"
    POSTGRESQL = "postgresql"


class SearchType(str, Enum):
    """Search types."""
    KEYWORD = "keyword"
    SEMANTIC = "semantic"
    HYBRID = "hybrid"


class SQLiteConfig(BaseModel):
    """SQLite-specific configuration."""
    
    path: str = Field(
        default="~/.echopanel/brain_dump.db",
        description="Path to SQLite database file"
    )
    
    @field_validator("path")
    @classmethod
    def expand_path(cls, v: str) -> str:
        """Expand user home directory."""
        return str(Path(v).expanduser())


class PostgreSQLConfig(BaseModel):
    """PostgreSQL-specific configuration."""
    
    host: str = Field(default="localhost", description="PostgreSQL host")
    port: int = Field(default=5432, description="PostgreSQL port")
    database: str = Field(default="echopanel", description="Database name")
    user: str = Field(default="echopanel", description="Database user")
    password: str = Field(default="", description="Database password")
    pool_size: int = Field(default=10, description="Connection pool size")
    max_overflow: int = Field(default=20, description="Max pool overflow")
    
    def get_connection_string(self) -> str:
        """Generate PostgreSQL connection string."""
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}"


class StorageConfig(BaseModel):
    """Storage backend configuration."""
    
    backend: Literal["sqlite", "postgresql"] = Field(
        default="sqlite",
        description="Storage backend type"
    )
    sqlite: SQLiteConfig = Field(default_factory=SQLiteConfig)
    postgresql: PostgreSQLConfig = Field(default_factory=PostgreSQLConfig)


class SearchConfig(BaseModel):
    """Search configuration."""
    
    default_type: Literal["keyword", "semantic", "hybrid"] = Field(
        default="hybrid",
        description="Default search type"
    )
    semantic_weight: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Weight for semantic vs keyword (0=keyword only, 1=semantic only)"
    )
    max_results: int = Field(
        default=20,
        ge=1,
        le=100,
        description="Maximum search results"
    )


class EmbeddingsConfig(BaseModel):
    """Embedding generation configuration."""
    
    enabled: bool = Field(default=True, description="Enable embeddings")
    model: str = Field(
        default="all-MiniLM-L6-v2",
        description="Sentence-transformers model name"
    )
    batch_size: int = Field(
        default=32,
        ge=1,
        le=256,
        description="Batch size for embedding generation"
    )
    device: Literal["cpu", "cuda", "mps"] = Field(
        default="cpu",
        description="Device for embedding generation"
    )


class GoogleDriveConfig(BaseModel):
    """Google Drive sync configuration."""
    
    enabled: bool = Field(default=False, description="Enable Google Drive sync")
    mode: Literal["backup", "sync"] = Field(
        default="backup",
        description="Sync mode: backup (one-way) or sync (bidirectional)"
    )
    encrypt: bool = Field(
        default=True,
        description="Encrypt data before upload"
    )
    sync_interval_minutes: int = Field(
        default=60,
        ge=5,
        description="Sync interval in minutes"
    )


class SyncConfig(BaseModel):
    """Synchronization configuration."""
    
    google_drive: GoogleDriveConfig = Field(default_factory=GoogleDriveConfig)


class RetentionConfig(BaseModel):
    """Data retention configuration."""
    
    max_days: int = Field(
        default=90,
        ge=0,
        description="Maximum days to keep data (0=keep forever)"
    )
    pinned_forever: bool = Field(
        default=True,
        description="Keep pinned sessions forever"
    )
    audio_retention_days: int = Field(
        default=7,
        ge=0,
        description="Days to keep audio files (0=keep forever)"
    )


class LoggingConfig(BaseModel):
    """Logging configuration."""
    
    level: Literal["debug", "info", "warning", "error"] = Field(
        default="info",
        description="Log level"
    )
    file: Optional[str] = Field(
        default="~/.echopanel/logs/echopanel.log",
        description="Log file path (None for stdout only)"
    )
    max_size_mb: int = Field(default=100, ge=1, description="Max log file size")
    backup_count: int = Field(default=5, ge=0, description="Number of backup files")
    
    @field_validator("file")
    @classmethod
    def expand_log_path(cls, v: Optional[str]) -> Optional[str]:
        """Expand user home directory in log path."""
        if v:
            return str(Path(v).expanduser())
        return v


class Config(BaseModel):
    """Root configuration model."""
    
    version: str = Field(default="1.0", description="Config file version")
    
    storage: StorageConfig = Field(default_factory=StorageConfig)
    search: SearchConfig = Field(default_factory=SearchConfig)
    embeddings: EmbeddingsConfig = Field(default_factory=EmbeddingsConfig)
    sync: SyncConfig = Field(default_factory=SyncConfig)
    retention: RetentionConfig = Field(default_factory=RetentionConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)
    
    def to_dict(self, mask_secrets: bool = True) -> dict:
        """Convert to dictionary.
        
        Args:
            mask_secrets: If True, masks sensitive values like passwords
            
        Returns:
            Configuration as dictionary
        """
        data = self.model_dump()
        
        if mask_secrets:
            # Mask PostgreSQL password
            if data.get("storage", {}).get("postgresql", {}).get("password"):
                data["storage"]["postgresql"]["password"] = "***"
        
        return data
    
    def get_storage_config(self) -> dict:
        """Get storage-specific configuration dictionary."""
        if self.storage.backend == "sqlite":
            return {
                "backend": "sqlite",
                "sqlite_path": self.storage.sqlite.path
            }
        elif self.storage.backend == "postgresql":
            return {
                "backend": "postgresql",
                "postgres_url": self.storage.postgresql.get_connection_string()
            }
        else:
            raise ValueError(f"Unknown storage backend: {self.storage.backend}")
