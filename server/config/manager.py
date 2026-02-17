"""Configuration manager with global instance.

Provides singleton access to configuration throughout the application.
"""

import logging
from pathlib import Path
from typing import Optional

from .schema import Config
from .loader import load_config, save_config, create_default_config_file

logger = logging.getLogger(__name__)


class ConfigManager:
    """Manages application configuration.
    
    Provides:
    - Singleton access to configuration
    - Hot-reload capability
    - Validation
    - Persistence
    
    Usage:
        manager = ConfigManager()
        config = manager.get_config()
        
        # Update config
        manager.update_config(new_config)
        
        # Reload from file
        manager.reload()
    """
    
    def __init__(self, config_path: Optional[Path] = None):
        """Initialize configuration manager.
        
        Args:
            config_path: Path to config file (defaults to ~/.echopanel/config.yaml)
        """
        self.config_path = config_path
        self._config: Optional[Config] = None
        self._loaded = False
    
    def load(self) -> Config:
        """Load configuration from all sources.
        
        Returns:
            Configuration object
        """
        self._config = load_config(self.config_path)
        self._loaded = True
        
        # Log which storage backend is being used
        logger.info(
            f"Configuration loaded: storage={self._config.storage.backend}, "
            f"search={self._config.search.default_type}, "
            f"embeddings={self._config.embeddings.enabled}"
        )
        
        return self._config
    
    def get_config(self) -> Config:
        """Get current configuration.
        
        Loads configuration on first call if not already loaded.
        
        Returns:
            Configuration object
        """
        if not self._loaded or self._config is None:
            return self.load()
        return self._config
    
    def reload(self) -> Config:
        """Reload configuration from file.
        
        Returns:
            Updated configuration object
        """
        logger.info("Reloading configuration...")
        return self.load()
    
    def update_config(self, config: Config, persist: bool = True) -> bool:
        """Update configuration.
        
        Args:
            config: New configuration
            persist: Whether to save to file
            
        Returns:
            True if successful
        """
        self._config = config
        
        if persist:
            return save_config(config, self.config_path)
        
        return True
    
    def update_from_dict(self, updates: dict, persist: bool = True) -> bool:
        """Update configuration from dictionary.
        
        Args:
            updates: Dictionary with configuration updates
            persist: Whether to save to file
            
        Returns:
            True if successful
        """
        try:
            current = self.get_config()
            current_dict = current.to_dict(mask_secrets=False)
            
            # Deep merge updates
            from .loader import deep_merge
            merged = deep_merge(current_dict, updates)
            
            # Create new config
            new_config = Config(**merged)
            return self.update_config(new_config, persist)
            
        except Exception as e:
            logger.error(f"Failed to update configuration: {e}")
            return False
    
    def get_storage_adapter_config(self) -> dict:
        """Get storage adapter configuration.
        
        Returns:
            Dictionary with backend and connection info
        """
        config = self.get_config()
        return config.get_storage_config()


# Global singleton instance
_config_manager: Optional[ConfigManager] = None


def get_config_manager() -> ConfigManager:
    """Get the global configuration manager.
    
    Returns:
        ConfigManager singleton
    """
    global _config_manager
    if _config_manager is None:
        _config_manager = ConfigManager()
    return _config_manager


def get_config() -> Config:
    """Get the global configuration.
    
    Convenience function that gets config from global manager.
    
    Returns:
        Configuration object
    """
    return get_config_manager().get_config()


def initialize_config(config_path: Optional[Path] = None) -> Config:
    """Initialize configuration system.
    
    Creates default config file if it doesn't exist and loads configuration.
    
    Args:
        config_path: Optional custom config path
        
    Returns:
        Configuration object
    """
    global _config_manager
    
    # Create default config file if needed
    create_default_config_file(config_path)
    
    # Initialize manager
    _config_manager = ConfigManager(config_path)
    
    # Load and return
    return _config_manager.load()


def reset_config() -> None:
    """Reset global configuration (mainly for testing)."""
    global _config_manager
    _config_manager = None
