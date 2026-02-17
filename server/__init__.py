"""EchoPanel server - FastAPI backend for Brain Dump."""

from server.config import get_config, initialize_config

__version__ = "0.2.0"

__all__ = [
    "get_config",
    "initialize_config",
]
