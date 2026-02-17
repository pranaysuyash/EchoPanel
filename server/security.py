"""Centralized authentication and security utilities.

Provides unified token extraction, validation, and auth enforcement
across HTTP and WebSocket endpoints.
"""

import hmac
import os
from typing import Optional

from fastapi import HTTPException, Request, WebSocket


AUTH_TOKEN_ENV = "ECHOPANEL_WS_AUTH_TOKEN"


def extract_http_token(request: Request) -> str:
    """Extract auth token from HTTP request.
    
    Checks in priority order:
    1. Authorization: Bearer <token> header
    2. X-EchoPanel-Token header
    3. token query parameter (legacy)
    """
    # Check Authorization header first (most secure)
    auth_header = request.headers.get("authorization", "").strip()
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()

    # Check custom header
    header_token = request.headers.get("x-echopanel-token", "").strip()
    if header_token:
        return header_token

    # Check query param (least secure, legacy)
    query_token = request.query_params.get("token", "").strip()
    if query_token:
        return query_token

    return ""


def extract_ws_token(websocket: WebSocket) -> str:
    """Extract auth token from WebSocket connection.
    
    Checks in priority order:
    1. Authorization: Bearer <token> header
    2. X-EchoPanel-Token header
    3. token query parameter (legacy)
    """
    # Check Authorization header first (most secure)
    auth_header = websocket.headers.get("authorization", "").strip()
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()

    # Check custom header
    header_token = websocket.headers.get("x-echopanel-token", "")
    if header_token:
        return header_token.strip()

    # Check query param (least secure, legacy)
    query_token = websocket.query_params.get("token")
    if query_token:
        return query_token.strip()

    return ""


def is_authorized(provided_token: str) -> bool:
    """Check if provided token matches configured auth token.
    
    Returns True if:
    - Token matches (timing-safe comparison)
    - No auth token is configured (permissive mode for development)
    
    Returns False otherwise.
    """
    required_token = os.getenv(AUTH_TOKEN_ENV, "").strip()
    if not required_token:
        return True

    if not provided_token:
        return False

    # Timing-safe comparison to prevent timing attacks
    return hmac.compare_digest(provided_token, required_token)


def require_http_auth(request: Request) -> None:
    """Enforce HTTP authentication, raising 401 if not authorized."""
    provided_token = extract_http_token(request)
    if not is_authorized(provided_token):
        raise HTTPException(status_code=401, detail="Unauthorized")


async def require_ws_auth(websocket: WebSocket) -> None:
    """Enforce WebSocket authentication, closing connection if not authorized."""
    provided_token = extract_ws_token(websocket)
    if not is_authorized(provided_token):
        await websocket.close(code=4001, reason="Unauthorized")
        return


def get_configured_token() -> Optional[str]:
    """Get the configured auth token (may be None/empty in development)."""
    return os.getenv(AUTH_TOKEN_ENV, "").strip() or None


def is_auth_required() -> bool:
    """Check if authentication is currently enabled/required."""
    return bool(get_configured_token())
