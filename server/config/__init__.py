"""Configuration management for EchoPanel.

Provides centralized configuration with:
- Pydantic-based validation
- YAML file persistence
- Environment variable overrides
- Hot-reload support
"""

from .schema import (
    Config,
    StorageConfig,
    SQLiteConfig,
    PostgreSQLConfig,
    SearchConfig,
    EmbeddingsConfig,
    SyncConfig,
    RetentionConfig,
    LoggingConfig,
    GoogleDriveConfig,
    StorageBackend,
    SearchType,
)

from .loader import (
    load_config,
    save_config,
    create_default_config_file,
)

from .manager import (
    ConfigManager,
    get_config_manager,
    get_config,
    initialize_config,
    reset_config,
)

__all__ = [
    # Schema
    "Config",
    "StorageConfig",
    "SQLiteConfig",
    "PostgreSQLConfig",
    "SearchConfig",
    "EmbeddingsConfig",
    "SyncConfig",
    "RetentionConfig",
    "LoggingConfig",
    "GoogleDriveConfig",
    "StorageBackend",
    "SearchType",
    # Loader
    "load_config",
    "save_config",
    "create_default_config_file",
    # Manager
    "ConfigManager",
    "get_config_manager",
    "get_config",
    "initialize_config",
    "reset_config",
]
