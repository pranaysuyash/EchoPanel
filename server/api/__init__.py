"""API routes for EchoPanel server."""

from .brain_dump_query import router as brain_dump_router
from .config import router as config_router

__all__ = [
    "brain_dump_router",
    "config_router",
]
