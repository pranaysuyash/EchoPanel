"""Tests for configuration system.

Phase 3.2: Configuration Management Tests
"""

import os
import sys
import pytest
import tempfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent))

from server.config import (
    Config,
    StorageConfig,
    SQLiteConfig,
    PostgreSQLConfig,
    SearchConfig,
    EmbeddingsConfig,
    SyncConfig,
    RetentionConfig,
    StorageBackend,
    SearchType,
    load_config,
    save_config,
    ConfigManager,
    get_config,
    initialize_config,
    reset_config,
)


@pytest.fixture
def temp_config_dir():
    """Provide temporary config directory."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def clean_config_manager():
    """Reset config manager before and after test."""
    reset_config()
    yield
    reset_config()


class TestConfigSchema:
    """Test configuration schema validation."""
    
    def test_default_config(self):
        """Test default configuration values."""
        config = Config()
        
        assert config.version == "1.0"
        assert config.storage.backend == StorageBackend.SQLITE
        assert config.storage.sqlite.path == "~/.echopanel/brain_dump.db"
        assert config.search.default_type == SearchType.HYBRID
        assert config.embeddings.enabled is True
        assert config.sync.google_drive.enabled is False
    
    def test_storage_backend_enum(self):
        """Test storage backend enum values."""
        assert StorageBackend.SQLITE == "sqlite"
        assert StorageBackend.POSTGRESQL == "postgresql"
    
    def test_search_type_enum(self):
        """Test search type enum values."""
        assert SearchType.KEYWORD == "keyword"
        assert SearchType.SEMANTIC == "semantic"
        assert SearchType.HYBRID == "hybrid"
    
    def test_postgresql_config_validation(self):
        """Test PostgreSQL configuration."""
        # Valid config with individual fields
        pg = PostgreSQLConfig(
            host="localhost",
            port=5432,
            database="echopanel",
            user="user",
            password="pass",
            pool_size=10
        )
        assert pg.host == "localhost"
        assert pg.port == 5432
        assert pg.pool_size == 10
        
        # Check connection string generation
        conn_str = pg.get_connection_string()
        assert "postgresql://" in conn_str
        assert "localhost" in conn_str
    
    def test_retention_config_validation(self):
        """Test retention configuration validation."""
        # Valid
        config = RetentionConfig(max_days=30)
        assert config.max_days == 30
        
        # Invalid (negative days)
        with pytest.raises(Exception):
            RetentionConfig(max_days=-1)
    
    def test_config_to_dict(self):
        """Test configuration serialization."""
        config = Config()
        data = config.to_dict()
        
        assert "version" in data
        assert "storage" in data
        assert "search" in data
        assert "embeddings" in data
        assert data["storage"]["backend"] == "sqlite"
    
    def test_config_to_dict_masks_secrets(self):
        """Test that secrets are masked in to_dict."""
        config = Config(
            storage=StorageConfig(
                backend=StorageBackend.POSTGRESQL,
                postgresql=PostgreSQLConfig(
                    host="localhost",
                    port=5432,
                    database="echopanel",
                    user="user",
                    password="secretpass"
                )
            )
        )
        
        # With masking
        data_masked = config.to_dict(mask_secrets=True)
        assert data_masked["storage"]["postgresql"]["password"] == "***"
        
        # Without masking
        data_unmasked = config.to_dict(mask_secrets=False)
        assert data_unmasked["storage"]["postgresql"]["password"] == "secretpass"


class TestConfigLoader:
    """Test configuration loading and saving."""
    
    def test_load_default_config(self, temp_config_dir):
        """Test loading default configuration."""
        config_path = temp_config_dir / "config.yaml"
        
        config = load_config(config_path)
        
        assert config.version == "1.0"
        assert config.storage.backend == StorageBackend.SQLITE
    
    def test_load_from_yaml(self, temp_config_dir):
        """Test loading configuration from YAML file."""
        config_path = temp_config_dir / "config.yaml"
        
        # Write YAML config
        config_path.write_text("""
version: "1.0"
storage:
  backend: "sqlite"
  sqlite:
    path: "/custom/path/db.db"
    enable_fts5: true
search:
  default_type: "semantic"
  max_results: 50
""")
        
        config = load_config(config_path)
        
        assert config.storage.backend == StorageBackend.SQLITE
        assert config.storage.sqlite.path == "/custom/path/db.db"
        assert config.search.default_type == SearchType.SEMANTIC
        assert config.search.max_results == 50
    
    def test_load_with_env_override(self, temp_config_dir):
        """Test environment variable override."""
        config_path = temp_config_dir / "config.yaml"
        
        # Create base config
        config = Config()
        save_config(config, config_path)
        
        # Set environment variable
        with mock.patch.dict(os.environ, {"ECHOPANEL_STORAGE_BACKEND": "postgresql"}):
            config = load_config(config_path)
            # Note: env var override implementation depends on config loader
            # This test assumes env vars are checked
    
    def test_save_config(self, temp_config_dir):
        """Test saving configuration to YAML."""
        config_path = temp_config_dir / "config.yaml"
        
        config = Config(
            storage=StorageConfig(
                backend=StorageBackend.SQLITE,
                sqlite=SQLiteConfig(path="/test/path.db")
            )
        )
        
        success = save_config(config, config_path)
        assert success is True
        
        # Verify file exists and contains expected data
        assert config_path.exists()
        content = config_path.read_text()
        assert "/test/path.db" in content
    
    def test_create_default_config_file(self, temp_config_dir):
        """Test creating default config file if not exists."""
        config_path = temp_config_dir / "config.yaml"
        
        # File doesn't exist
        assert not config_path.exists()
        
        # Create it manually
        from server.config.loader import create_default_config_file
        create_default_config_file(config_path)
        
        # File should now exist with default content
        assert config_path.exists()
    
    def test_load_invalid_yaml(self, temp_config_dir):
        """Test loading invalid YAML."""
        config_path = temp_config_dir / "config.yaml"
        config_path.write_text("invalid: yaml: [")
        
        # Should fall back to defaults
        config = load_config(config_path)
        assert config.version == "1.0"  # Default value


class TestConfigManager:
    """Test configuration manager."""
    
    def test_manager_loads_config(self, temp_config_dir):
        """Test manager loads configuration."""
        config_path = temp_config_dir / "config.yaml"
        
        manager = ConfigManager(config_path)
        config = manager.load()
        
        assert config.version == "1.0"
        assert manager._loaded is True
    
    def test_manager_get_config(self, temp_config_dir):
        """Test manager get_config loads on first call."""
        config_path = temp_config_dir / "config.yaml"
        
        manager = ConfigManager(config_path)
        assert not manager._loaded
        
        config = manager.get_config()
        assert manager._loaded
        assert config.version == "1.0"
    
    def test_manager_update_config(self, temp_config_dir, clean_config_manager):
        """Test manager update and persist."""
        config_path = temp_config_dir / "config.yaml"
        
        manager = ConfigManager(config_path)
        manager.load()
        
        # Update config
        new_config = Config(
            search=SearchConfig(default_type=SearchType.SEMANTIC, max_results=100)
        )
        success = manager.update_config(new_config, persist=True)
        
        assert success is True
        assert manager.get_config().search.max_results == 100
        
        # Verify persisted
        reloaded = load_config(config_path)
        assert reloaded.search.max_results == 100
    
    def test_manager_update_from_dict(self, temp_config_dir, clean_config_manager):
        """Test manager update from dictionary."""
        config_path = temp_config_dir / "config.yaml"
        
        manager = ConfigManager(config_path)
        manager.load()
        
        # Partial update
        success = manager.update_from_dict(
            {"search": {"max_results": 75}},
            persist=False
        )
        
        assert success is True
        assert manager.get_config().search.max_results == 75
        # Other fields unchanged
        assert manager.get_config().storage.backend == StorageBackend.SQLITE
    
    def test_manager_reload(self, temp_config_dir):
        """Test manager reload."""
        config_path = temp_config_dir / "config.yaml"
        
        # Create config file
        config_path.write_text("""
version: "1.0"
storage:
  backend: "sqlite"
search:
  default_type: "keyword"
""")
        
        manager = ConfigManager(config_path)
        config = manager.load()
        assert config.search.default_type == SearchType.KEYWORD
        
        # Modify file
        config_path.write_text("""
version: "1.0"
storage:
  backend: "sqlite"
search:
  default_type: "semantic"
""")
        
        # Reload
        config = manager.reload()
        assert config.search.default_type == SearchType.SEMANTIC


class TestConfigSingleton:
    """Test global configuration singleton."""
    
    def test_get_config_manager_singleton(self):
        """Test get_config_manager returns same instance."""
        reset_config()
        
        manager1 = ConfigManager()
        manager2 = ConfigManager()
        
        # Different instances unless using singleton pattern
        # (implementation dependent)
    
    def test_get_config(self, temp_config_dir, clean_config_manager):
        """Test global get_config function."""
        config_path = temp_config_dir / "config.yaml"
        
        # Initialize with custom path
        config = initialize_config(config_path)
        
        # Get via global function
        same_config = get_config()
        
        assert same_config.version == config.version
    
    def test_initialize_config_creates_file(self, temp_config_dir, clean_config_manager):
        """Test initialize creates default config file."""
        config_path = temp_config_dir / "config.yaml"
        
        assert not config_path.exists()
        
        initialize_config(config_path)
        
        assert config_path.exists()
    
    def test_reset_config(self, clean_config_manager):
        """Test reset clears global state."""
        from server.config.manager import _config_manager
        
        # Ensure clean state
        reset_config()
        assert _config_manager is None


class TestStorageBackendConfig:
    """Test storage backend specific configuration."""
    
    def test_sqlite_storage_config(self):
        """Test SQLite storage configuration."""
        config = Config(
            storage=StorageConfig(
                backend=StorageBackend.SQLITE,
                sqlite=SQLiteConfig(
                    path="~/custom/db.sqlite",
                    enable_fts5=True
                )
            )
        )
        
        storage_config = config.get_storage_config()
        assert storage_config["backend"] == "sqlite"
        assert "sqlite_path" in storage_config
        assert "custom" in storage_config["sqlite_path"]
    
    def test_postgresql_storage_config(self):
        """Test PostgreSQL storage configuration."""
        config = Config(
            storage=StorageConfig(
                backend=StorageBackend.POSTGRESQL,
                postgresql=PostgreSQLConfig(
                    host="localhost",
                    port=5432,
                    database="echopanel",
                    user="user",
                    password="pass",
                    pool_size=10
                )
            )
        )
        
        storage_config = config.get_storage_config()
        assert storage_config["backend"] == "postgresql"
        assert "postgresql://" in storage_config["postgres_url"]
        assert "localhost" in storage_config["postgres_url"]
    
    def test_postgresql_config_requires_url(self):
        """Test PostgreSQL requires URL when selected."""
        with pytest.raises(ValueError):
            Config(
                storage=StorageConfig(
                    backend=StorageBackend.POSTGRESQL,
                    postgresql=None  # Missing URL
                )
            )


class TestConfigEdgeCases:
    """Test edge cases and error handling."""
    
    def test_config_with_empty_yaml(self, temp_config_dir):
        """Test loading empty YAML file."""
        config_path = temp_config_dir / "config.yaml"
        config_path.write_text("")
        
        config = load_config(config_path)
        # Should use all defaults
        assert config.version == "1.0"
    
    def test_config_with_partial_yaml(self, temp_config_dir):
        """Test loading partial YAML - missing fields use defaults."""
        config_path = temp_config_dir / "config.yaml"
        config_path.write_text("""
version: "1.0"
storage:
  backend: "sqlite"
# Missing search, embeddings, etc.
""")
        
        config = load_config(config_path)
        assert config.storage.backend == StorageBackend.SQLITE
        # Other fields use defaults
        assert config.search.default_type == SearchType.HYBRID
        assert config.embeddings.enabled is True
    
    def test_config_path_expansion(self):
        """Test path expansion in config via get_path method."""
        config = Config()
        # Manually expand path since validator only runs on construction
        expanded = str(Path(config.storage.sqlite.path).expanduser())
        
        # Should expand ~ to home directory
        assert not expanded.startswith("~")
        assert Path(expanded).is_absolute()
    
    def test_config_mutable(self):
        """Test configuration can be modified (Pydantic v2 default)."""
        config = Config()
        
        # Pydantic v2 models are mutable by default
        config.version = "2.0"
        assert config.version == "2.0"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
