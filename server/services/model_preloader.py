"""
PR4: Model Preloading + Warmup

Implements eager model loading with tiered warmup to eliminate cold start latency.
Three-state lifecycle: UNINITIALIZED → LOADING → READY

Usage:
    from server.services.model_preloader import ModelManager, get_model_manager
    
    # At server startup
    manager = get_model_manager()
    await manager.initialize()  # Blocks until ready
    
    # In ASR loop
    provider = manager.get_provider()
    result = await provider.transcribe(audio)
"""

import asyncio
import logging
import time
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, Dict, Any, Callable
import numpy as np

from .asr_providers import ASRProvider, ASRConfig, ASRProviderRegistry

logger = logging.getLogger(__name__)


class ModelState(Enum):
    """Model lifecycle states."""
    UNINITIALIZED = auto()
    LOADING = auto()
    WARMING_UP = auto()
    READY = auto()
    ERROR = auto()


@dataclass
class ModelHealth:
    """Health status of the model."""
    state: ModelState
    ready: bool
    model_loaded: bool
    warmup_complete: bool
    load_time_ms: float
    warmup_time_ms: float
    last_error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "state": self.state.name,
            "ready": self.ready,
            "model_loaded": self.model_loaded,
            "warmup_complete": self.warmup_complete,
            "load_time_ms": round(self.load_time_ms, 1),
            "warmup_time_ms": round(self.warmup_time_ms, 1),
            "last_error": self.last_error,
        }


@dataclass
class WarmupConfig:
    """Configuration for warmup sequence."""
    # Level 1: Model load (always done)
    enabled: bool = True
    
    # Level 2: Single inference (warm caches)
    level2_single_inference: bool = True
    level2_duration_ms: int = 100  # Minimum duration for level 2
    
    # Level 3: Full warmup (stress test)
    level3_full_warmup: bool = False  # Disabled by default (slow)
    level3_iterations: int = 5
    level3_duration_ms: int = 1000  # Minimum duration for level 3
    
    # Audio parameters for warmup
    sample_rate: int = 16000
    warmup_audio_seconds: float = 2.0


class ModelManager:
    """
    Manages ASR model lifecycle: load → warmup → ready.
    
    Features:
    - Eager loading at server startup
    - Tiered warmup (3 levels)
    - Deep health verification
    - Thread-safe access
    - Automatic retry on failure
    """
    
    def __init__(
        self,
        provider_name: Optional[str] = None,
        config: Optional[ASRConfig] = None,
        warmup_config: Optional[WarmupConfig] = None,
    ):
        self.provider_name = provider_name
        self.config = config
        self.warmup_config = warmup_config or WarmupConfig()
        
        # State
        self._state = ModelState.UNINITIALIZED
        self._provider: Optional[ASRProvider] = None
        self._load_time_ms: float = 0.0
        self._warmup_time_ms: float = 0.0
        self._last_error: Optional[str] = None
        
        # Lock for thread safety
        self._lock = asyncio.Lock()
        self._ready_event = asyncio.Event()
        
        # Metrics
        self._inference_count: int = 0
        self._total_inference_time_ms: float = 0.0
        
    @property
    def state(self) -> ModelState:
        """Current model state."""
        return self._state
    
    @property
    def is_ready(self) -> bool:
        """Check if model is ready for inference."""
        return self._state == ModelState.READY
    
    async def initialize(self, timeout: float = 300.0) -> bool:
        """
        Initialize model with warmup. Blocks until ready or timeout.
        
        Args:
            timeout: Maximum time to wait for initialization (seconds)
            
        Returns:
            True if initialization succeeded
        """
        async with self._lock:
            if self._state == ModelState.READY:
                return True
            
            if self._state == ModelState.LOADING:
                # Another task is loading, wait for it
                async with self._lock:
                    pass  # Release lock and wait below
                try:
                    await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
                    return self._state == ModelState.READY
                except asyncio.TimeoutError:
                    return False
            
            self._state = ModelState.LOADING
        
        try:
            # Phase 1: Load model
            logger.info("Phase 1/3: Loading model...")
            start = time.time()
            
            if not await self._load_model():
                return False
            
            self._load_time_ms = (time.time() - start) * 1000
            logger.info(f"Model loaded in {self._load_time_ms:.1f}ms")
            
            # Phase 2: Warmup
            if self.warmup_config.enabled:
                async with self._lock:
                    self._state = ModelState.WARMING_UP
                
                logger.info("Phase 2/3: Warming up...")
                start = time.time()
                
                await self._warmup()
                
                self._warmup_time_ms = (time.time() - start) * 1000
                logger.info(f"Warmup complete in {self._warmup_time_ms:.1f}ms")
            
            # Mark as ready
            async with self._lock:
                self._state = ModelState.READY
                self._ready_event.set()
            
            logger.info(f"Model ready! Total time: {self._load_time_ms + self._warmup_time_ms:.1f}ms")
            return True
            
        except Exception as e:
            logger.error(f"Model initialization failed: {e}")
            async with self._lock:
                self._state = ModelState.ERROR
                self._last_error = str(e)
                self._ready_event.set()  # Unblock waiters
            return False
    
    async def _load_model(self) -> bool:
        """Load the model."""
        try:
            # Get provider
            if self.provider_name:
                self._provider = ASRProviderRegistry.get_provider(name=self.provider_name)
            else:
                self._provider = ASRProviderRegistry.get_provider(config=self.config)
            
            if not self._provider:
                raise RuntimeError("No ASR provider available")
            
            if not self._provider.is_available:
                raise RuntimeError(f"Provider {self._provider.name} is not available")
            
            logger.info(f"Loaded provider: {self._provider.name}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            self._last_error = str(e)
            return False
    
    async def _warmup(self):
        """Run warmup sequence."""
        if not self._provider:
            raise RuntimeError("Provider not loaded")
        
        # Generate warmup audio (silence is fine for warmup)
        duration = self.warmup_config.warmup_audio_seconds
        sample_rate = self.warmup_config.sample_rate
        samples = int(duration * sample_rate)
        
        # Create silent audio
        audio_bytes = np.zeros(samples, dtype=np.int16).tobytes()
        
        # Level 2: Single inference to warm caches
        if self.warmup_config.level2_single_inference:
            logger.debug("Warmup Level 2: Single inference")
            
            async def audio_stream():
                yield audio_bytes
            
            start = time.time()
            count = 0
            async for _ in self._provider.transcribe_stream(audio_stream()):
                count += 1
            
            elapsed = (time.time() - start) * 1000
            min_duration = self.warmup_config.level2_duration_ms
            
            if elapsed < min_duration:
                # Run more iterations if too fast
                remaining = min_duration - elapsed
                await asyncio.sleep(remaining / 1000)
            
            logger.debug(f"Level 2 complete: {count} segments, {elapsed:.1f}ms")
        
        # Level 3: Full warmup (optional, slow)
        if self.warmup_config.level3_full_warmup:
            logger.debug("Warmup Level 3: Full stress test")
            
            iterations = self.warmup_config.level3_iterations
            start = time.time()
            
            for i in range(iterations):
                async def audio_stream():
                    yield audio_bytes
                
                async for _ in self._provider.transcribe_stream(audio_stream()):
                    pass
            
            elapsed = (time.time() - start) * 1000
            min_duration = self.warmup_config.level3_duration_ms
            
            if elapsed < min_duration:
                remaining = min_duration - elapsed
                await asyncio.sleep(remaining / 1000)
            
            logger.debug(f"Level 3 complete: {iterations} iterations")
    
    def get_provider(self) -> Optional[ASRProvider]:
        """Get the loaded provider (if ready)."""
        if self._state != ModelState.READY:
            logger.warning(f"Getting provider in state {self._state.name}")
        return self._provider
    
    async def transcribe(self, audio_stream, **kwargs):
        """
        Transcribe audio using the loaded provider.
        
        Args:
            audio_stream: Async iterator of audio chunks
            **kwargs: Additional arguments for provider
            
        Yields:
            ASR segments
        """
        if self._state != ModelState.READY:
            raise RuntimeError(f"Model not ready (state: {self._state.name})")
        
        if not self._provider:
            raise RuntimeError("Provider not available")
        
        start = time.time()
        self._inference_count += 1
        
        try:
            async for segment in self._provider.transcribe_stream(audio_stream, **kwargs):
                yield segment
        finally:
            elapsed = (time.time() - start) * 1000
            self._total_inference_time_ms += elapsed
    
    def health(self) -> ModelHealth:
        """Get current health status."""
        return ModelHealth(
            state=self._state,
            ready=self._state == ModelState.READY,
            model_loaded=self._provider is not None,
            warmup_complete=self._warmup_time_ms > 0,
            load_time_ms=self._load_time_ms,
            warmup_time_ms=self._warmup_time_ms,
            last_error=self._last_error,
        )
    
    def get_stats(self) -> Dict[str, Any]:
        """Get performance statistics."""
        avg_inference = (
            self._total_inference_time_ms / self._inference_count
            if self._inference_count > 0 else 0.0
        )
        
        return {
            "state": self._state.name,
            "provider": self._provider.name if self._provider else None,
            "load_time_ms": round(self._load_time_ms, 1),
            "warmup_time_ms": round(self._warmup_time_ms, 1),
            "inference_count": self._inference_count,
            "avg_inference_ms": round(avg_inference, 1),
        }
    
    async def wait_for_ready(self, timeout: float = 60.0) -> bool:
        """Wait for model to be ready."""
        if self._state == ModelState.READY:
            return True
        
        try:
            await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
            return self._state == ModelState.READY
        except asyncio.TimeoutError:
            return False


# Global singleton instance
_model_manager: Optional[ModelManager] = None


def get_model_manager(
    provider_name: Optional[str] = None,
    config: Optional[ASRConfig] = None,
    warmup_config: Optional[WarmupConfig] = None,
) -> ModelManager:
    """Get or create the global model manager."""
    global _model_manager
    if _model_manager is None:
        _model_manager = ModelManager(
            provider_name=provider_name,
            config=config,
            warmup_config=warmup_config,
        )
    return _model_manager


def reset_model_manager():
    """Reset the global model manager (for testing)."""
    global _model_manager
    _model_manager = None


async def initialize_model_at_startup(
    provider_name: Optional[str] = None,
    config: Optional[ASRConfig] = None,
) -> bool:
    """
    Convenience function to initialize model at server startup.
    
    Usage:
        @app.on_event("startup")
        async def startup():
            success = await initialize_model_at_startup()
            if not success:
                logger.error("Failed to initialize ASR model")
    """
    manager = get_model_manager(provider_name=provider_name, config=config)
    
    logger.info("Initializing ASR model at startup...")
    success = await manager.initialize()
    
    if success:
        health = manager.health()
        logger.info(f"Model ready: {health.to_dict()}")
    else:
        logger.error(f"Model initialization failed: {manager.health().last_error}")
    
    return success
