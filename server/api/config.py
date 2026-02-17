"""Configuration API endpoints.

Provides REST API for reading and writing configuration.
"""

import logging
import os
from typing import Optional

from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel, Field

from server.config import (
    get_config,
    get_config_manager,
    Config,
    load_config,
    save_config
)
from server.db import get_storage_adapter, StorageConfig
from server.security import require_http_auth

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/config", tags=["config"])


# Pydantic models for API

class ConfigResponse(BaseModel):
    """Configuration response (with secrets masked)."""
    version: str
    storage: dict
    search: dict
    embeddings: dict
    sync: dict
    retention: dict
    logging: dict


class ConfigUpdateRequest(BaseModel):
    """Configuration update request."""
    storage: Optional[dict] = None
    search: Optional[dict] = None
    embeddings: Optional[dict] = None
    sync: Optional[dict] = None
    retention: Optional[dict] = None
    logging: Optional[dict] = None


class StorageTestRequest(BaseModel):
    """Storage connection test request."""
    backend: str = Field(..., description="Storage backend: sqlite or postgresql")
    sqlite_path: Optional[str] = None
    postgres_url: Optional[str] = None


class StorageTestResponse(BaseModel):
    """Storage connection test response."""
    success: bool
    message: str
    details: Optional[dict] = None


# API Endpoints

@router.get("", response_model=ConfigResponse)
async def get_configuration(request: Request) -> ConfigResponse:
    """Get current configuration (secrets masked).
    
    Returns the current configuration with sensitive values
    like passwords replaced with '***'.
    """
    require_http_auth(request)
    config = get_config()
    data = config.to_dict(mask_secrets=True)
    
    return ConfigResponse(**data)


@router.post("")
async def update_configuration(request: Request, body: ConfigUpdateRequest) -> dict:
    """Update configuration.
    
    Only provided fields are updated. Other fields keep their current values.
    Configuration is validated before saving.
    
    Example:
        POST /config
        {
            "search": {
                "default_type": "semantic",
                "max_results": 50
            }
        }
    """
    require_http_auth(request)
    try:
        manager = get_config_manager()
        
        # Build update dict from request
        updates = {}
        for field in ["storage", "search", "embeddings", "sync", "retention", "logging"]:
            value = getattr(request, field)
            if value is not None:
                updates[field] = value
        
        if not updates:
            raise HTTPException(status_code=400, detail="No updates provided")
        
        # Apply updates
        success = manager.update_from_dict(updates, persist=True)
        
        if not success:
            raise HTTPException(status_code=500, detail="Failed to save configuration")
        
        logger.info(f"Configuration updated: {list(updates.keys())}")
        return {"status": "success", "updated": list(updates.keys())}
        
    except Exception as e:
        logger.error(f"Configuration update failed: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/storage/test", response_model=StorageTestResponse)
async def test_storage_connection(request: Request, body: StorageTestRequest) -> StorageTestResponse:
    """Test storage backend connection.
    
    Tests if the specified storage backend can be connected to.
    Does not modify any data.
    
    Example:
        POST /config/storage/test
        {
            "backend": "postgresql",
            "postgres_url": "postgresql://user:pass@localhost/echopanel"
        }
    """
    require_http_auth(request)
    try:
        if request.backend == "sqlite":
            return await _test_sqlite_connection(request.sqlite_path)
        elif request.backend == "postgresql":
            return await _test_postgresql_connection(request.postgres_url)
        else:
            raise HTTPException(status_code=400, detail=f"Unknown backend: {request.backend}")
            
    except Exception as e:
        logger.error(f"Storage test failed: {e}")
        return StorageTestResponse(
            success=False,
            message=str(e)
        )


async def _test_sqlite_connection(path: Optional[str]) -> StorageTestResponse:
    """Test SQLite connection."""
    from pathlib import Path
    import sqlite3
    
    path = path or "~/.echopanel/brain_dump.db"
    full_path = Path(path).expanduser()
    
    try:
        # Try to create parent directory
        full_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Try to connect
        conn = sqlite3.connect(str(full_path))
        conn.execute("SELECT 1")
        conn.close()
        
        return StorageTestResponse(
            success=True,
            message=f"SQLite connection successful: {full_path}",
            details={
                "path": str(full_path),
                "exists": full_path.exists(),
                "writable": os.access(full_path.parent, os.W_OK)
            }
        )
    except Exception as e:
        return StorageTestResponse(
            success=False,
            message=f"SQLite connection failed: {e}"
        )


async def _test_postgresql_connection(url: Optional[str]) -> StorageTestResponse:
    """Test PostgreSQL connection."""
    if not url:
        return StorageTestResponse(
            success=False,
            message="PostgreSQL URL not provided"
        )
    
    try:
        # Check if asyncpg is available
        try:
            import asyncpg
        except ImportError:
            return StorageTestResponse(
                success=False,
                message="asyncpg not installed. Install with: pip install asyncpg"
            )
        
        # Try to connect
        conn = await asyncpg.connect(url)
        
        # Test query
        result = await conn.fetchrow("SELECT version()")
        version = result[0] if result else "unknown"
        
        # Check pgvector
        try:
            await conn.execute("SELECT 1 FROM pg_extension WHERE extname = 'vector'")
            pgvector_available = True
        except:
            pgvector_available = False
        
        await conn.close()
        
        return StorageTestResponse(
            success=True,
            message=f"PostgreSQL connection successful",
            details={
                "version": version,
                "pgvector_available": pgvector_available
            }
        )
    except Exception as e:
        return StorageTestResponse(
            success=False,
            message=f"PostgreSQL connection failed: {e}"
        )


@router.post("/reload")
async def reload_configuration(request: Request) -> dict:
    """Reload configuration from file.
    
    Useful when config file was manually edited.
    Requires authentication.
    """
    require_http_auth(request)
    try:
        manager = get_config_manager()
        config = manager.reload()
        
        return {
            "status": "success",
            "storage_backend": config.storage.backend,
            "message": "Configuration reloaded"
        }
    except Exception as e:
        logger.error(f"Configuration reload failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/reset")
async def reset_configuration(request: Request) -> dict:
    """Reset configuration to defaults.
    
    WARNING: This will overwrite your current configuration!
    Requires authentication.
    """
    require_http_auth(request)
    try:
        # Create new default config
        default_config = Config()
        
        # Save it
        manager = get_config_manager()
        manager.update_config(default_config, persist=True)
        
        logger.warning("Configuration reset to defaults")
        return {
            "status": "success",
            "message": "Configuration reset to defaults"
        }
    except Exception as e:
        logger.error(f"Configuration reset failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Utility dependency for other routes

def get_storage_adapter_from_config():
    """Get storage adapter based on current configuration."""
    config = get_config()
    storage_config = config.get_storage_config()
    
    # Create temporary adapter for dependency injection
    from server.db import get_storage_adapter as get_adapter
    return get_adapter(StorageConfig(**storage_config))



