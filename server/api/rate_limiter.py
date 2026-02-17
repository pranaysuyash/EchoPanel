"""Rate limiting middleware for API endpoints."""

import asyncio
import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Dict, Optional

logger = logging.getLogger(__name__)


@dataclass
class RateLimitConfig:
    """Configuration for rate limiting."""
    requests_per_minute: int = 60
    requests_per_hour: int = 1000
    burst_size: int = 10


@dataclass
class RateLimitState:
    """State for a single client's rate limiting."""
    minute_tokens: float = field(default=0.0)
    hour_tokens: float = field(default=0.0)
    last_minute_update: float = field(default_factory=time.time)
    last_hour_update: float = field(default_factory=time.time)
    requests_minute: int = 0
    requests_hour: int = 0


class RateLimiter:
    """Token bucket rate limiter for API endpoints.
    
    Usage:
        limiter = RateLimiter()
        
        @app.get("/endpoint")
        async def endpoint(request: Request):
            client_id = request.client.host
            if not await limiter.acquire(client_id):
                raise HTTPException(429, "Rate limit exceeded")
            # ... handle request
    """
    
    def __init__(self, config: Optional[RateLimitConfig] = None):
        self.config = config or RateLimitConfig()
        self._clients: Dict[str, RateLimitState] = defaultdict(RateLimitState)
        self._lock = asyncio.Lock()
        
        # Cleanup task
        self._cleanup_task: Optional[asyncio.Task] = None
        self._running = False
    
    async def start(self) -> None:
        """Start the rate limiter and cleanup task."""
        self._running = True
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
        logger.info(f"Rate limiter started: {self.config.requests_per_minute}/min, {self.config.requests_per_hour}/hour")
    
    async def stop(self) -> None:
        """Stop the rate limiter."""
        self._running = False
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
    
    async def acquire(self, client_id: str) -> bool:
        """Try to acquire a rate limit token for a client.
        
        Args:
            client_id: Unique identifier for the client (e.g., IP address, user ID)
            
        Returns:
            True if request is allowed, False if rate limited
        """
        async with self._lock:
            state = self._clients[client_id]
            now = time.time()
            
            # Refill tokens based on elapsed time
            minute_elapsed = now - state.last_minute_update
            hour_elapsed = now - state.last_hour_update
            
            # Add tokens (refill rate = limit per minute/hour)
            state.minute_tokens = min(
                self.config.requests_per_minute,
                state.minute_tokens + minute_elapsed * (self.config.requests_per_minute / 60.0)
            )
            state.hour_tokens = min(
                self.config.requests_per_hour,
                state.hour_tokens + hour_elapsed * (self.config.requests_per_hour / 3600.0)
            )
            
            state.last_minute_update = now
            state.last_hour_update = now
            
            # Check if we have tokens available
            if state.minute_tokens < 1.0:
                logger.warning(f"Rate limit exceeded (minute): {client_id}")
                return False
            
            if state.hour_tokens < 1.0:
                logger.warning(f"Rate limit exceeded (hour): {client_id}")
                return False
            
            # Consume tokens
            state.minute_tokens -= 1.0
            state.hour_tokens -= 1.0
            state.requests_minute += 1
            state.requests_hour += 1
            
            return True
    
    def get_remaining(self, client_id: str) -> Dict[str, int]:
        """Get remaining requests for a client.
        
        Args:
            client_id: Unique identifier for the client
            
        Returns:
            Dict with 'minute' and 'hour' remaining requests
        """
        state = self._clients.get(client_id)
        if not state:
            return {"minute": self.config.requests_per_minute, "hour": self.config.requests_per_hour}
        
        return {
            "minute": int(state.minute_tokens),
            "hour": int(state.hour_tokens)
        }
    
    async def _cleanup_loop(self) -> None:
        """Periodically cleanup old client entries."""
        while self._running:
            try:
                await asyncio.sleep(300)  # Cleanup every 5 minutes
                
                async with self._lock:
                    now = time.time()
                    # Remove clients with no activity in the last hour
                    to_remove = [
                        client_id for client_id, state in self._clients.items()
                        if now - state.last_hour_update > 3600
                    ]
                    for client_id in to_remove:
                        del self._clients[client_id]
                    
                    if to_remove:
                        logger.debug(f"Cleaned up {len(to_remove)} inactive rate limit entries")
                        
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in rate limiter cleanup: {e}")


# Global rate limiter instance
_rate_limiter: Optional[RateLimiter] = None


def get_rate_limiter() -> RateLimiter:
    """Get the global rate limiter instance."""
    global _rate_limiter
    if _rate_limiter is None:
        _rate_limiter = RateLimiter()
    return _rate_limiter


async def initialize_rate_limiter(config: Optional[RateLimitConfig] = None) -> RateLimiter:
    """Initialize the global rate limiter."""
    global _rate_limiter
    _rate_limiter = RateLimiter(config)
    await _rate_limiter.start()
    return _rate_limiter


async def shutdown_rate_limiter() -> None:
    """Shutdown the global rate limiter."""
    global _rate_limiter
    if _rate_limiter:
        await _rate_limiter.stop()
        _rate_limiter = None
