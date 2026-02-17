"""Configuration loader for YAML files and environment variables.

Loads configuration from:
1. Default values (lowest priority)
2. Config file (~/.echopanel/config.yaml)
3. Environment variables (highest priority)
"""

import os
import logging
from pathlib import Path
from typing import Optional, Any

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

from .schema import Config

logger = logging.getLogger(__name__)

# Default config file location
DEFAULT_CONFIG_PATH = Path.home() / ".echopanel" / "config.yaml"

# Environment variable prefix
ENV_PREFIX = "ECHOPANEL_"


def load_yaml_file(path: Path) -> Optional[dict]:
    """Load YAML configuration file.
    
    Args:
        path: Path to YAML file
        
    Returns:
        Dictionary with config values, or None if file doesn't exist
    """
    if not YAML_AVAILABLE:
        logger.warning("PyYAML not installed, cannot load config file")
        return None
    
    if not path.exists():
        logger.debug(f"Config file not found: {path}")
        return None
    
    try:
        with open(path, 'r') as f:
            data = yaml.safe_load(f)
            if data is None:
                return {}
            return data
    except Exception as e:
        logger.error(f"Failed to load config file {path}: {e}")
        return None


def save_yaml_file(config: Config, path: Optional[Path] = None) -> bool:
    """Save configuration to YAML file.
    
    Args:
        config: Configuration to save
        path: Path to save to (defaults to ~/.echopanel/config.yaml)
        
    Returns:
        True if saved successfully
    """
    if not YAML_AVAILABLE:
        logger.error("PyYAML not installed, cannot save config file")
        return False
    
    path = path or DEFAULT_CONFIG_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    
    try:
        with open(path, 'w') as f:
            yaml.dump(config.to_dict(mask_secrets=False), f, default_flow_style=False)
        logger.info(f"Configuration saved to {path}")
        return True
    except Exception as e:
        logger.error(f"Failed to save config file {path}: {e}")
        return False


def load_from_env() -> dict:
    """Load configuration from environment variables.
    
    Environment variables are expected to be in the format:
        ECHOPANEL_SECTION_SUBSECTION_KEY=value
    
    For example:
        ECHOPANEL_STORAGE_BACKEND=postgresql
        ECHOPANEL_POSTGRES_HOST=localhost
        ECHOPANEL_SEARCH_MAX_RESULTS=50
    
    Returns:
        Nested dictionary with config values
    """
    config = {}
    
    for key, value in os.environ.items():
        if not key.startswith(ENV_PREFIX):
            continue
        
        # Remove prefix and split by underscore
        # ECHOPANEL_STORAGE_BACKEND -> storage.backend
        # ECHOPANEL_POSTGRES_HOST -> storage.postgresql.host
        parts = key[len(ENV_PREFIX):].lower().split('_')
        
        # Build nested dict
        current = config
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Set value with type conversion
        final_key = parts[-1]
        current[final_key] = _convert_value(value)
    
    return config


def _convert_value(value: str) -> Any:
    """Convert string value to appropriate type.
    
    Args:
        value: String value from environment
        
    Returns:
        Converted value (bool, int, float, or string)
    """
    # Boolean conversion
    lower = value.lower()
    if lower in ('true', '1', 'yes', 'on'):
        return True
    if lower in ('false', '0', 'no', 'off'):
        return False
    
    # Integer conversion
    try:
        return int(value)
    except ValueError:
        pass
    
    # Float conversion
    try:
        return float(value)
    except ValueError:
        pass
    
    # String (default)
    return value


def deep_merge(base: dict, override: dict) -> dict:
    """Deep merge two dictionaries.
    
    Args:
        base: Base dictionary
        override: Dictionary with values to override
        
    Returns:
        Merged dictionary
    """
    result = base.copy()
    
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    
    return result


def load_config(
    config_path: Optional[Path] = None,
    use_env: bool = True
) -> Config:
    """Load configuration from all sources.
    
    Priority (highest to lowest):
    1. Environment variables
    2. Config file
    3. Default values
    
    Args:
        config_path: Path to config file (defaults to ~/.echopanel/config.yaml)
        use_env: Whether to load from environment variables
        
    Returns:
        Configuration object
    """
    config_path = config_path or DEFAULT_CONFIG_PATH
    
    # Start with empty dict (will use Pydantic defaults)
    config_data = {}
    
    # Load from file
    file_data = load_yaml_file(config_path)
    if file_data:
        logger.debug(f"Loaded configuration from {config_path}")
        config_data = deep_merge(config_data, file_data)
    
    # Load from environment (highest priority)
    if use_env:
        env_data = load_from_env()
        if env_data:
            logger.debug("Loaded configuration from environment variables")
            config_data = deep_merge(config_data, env_data)
    
    # Create config object
    try:
        config = Config(**config_data)
        return config
    except Exception as e:
        logger.error(f"Failed to parse configuration: {e}")
        logger.warning("Using default configuration")
        return Config()


def save_config(config: Config, config_path: Optional[Path] = None) -> bool:
    """Save configuration to file.
    
    Args:
        config: Configuration to save
        config_path: Path to save to (defaults to ~/.echopanel/config.yaml)
        
    Returns:
        True if saved successfully
    """
    return save_yaml_file(config, config_path)


def create_default_config_file(path: Optional[Path] = None) -> bool:
    """Create a default configuration file.
    
    Args:
        path: Path to create (defaults to ~/.echopanel/config.yaml)
        
    Returns:
        True if created successfully
    """
    path = path or DEFAULT_CONFIG_PATH
    
    if path.exists():
        logger.debug(f"Config file already exists: {path}")
        return True
    
    config = Config()
    return save_config(config, path)
