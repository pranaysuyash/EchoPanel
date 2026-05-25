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
import inspect
import logging
import os
import sys
import time
from dataclasses import dataclass
from enum import Enum, auto
from pathlib import Path
from typing import Optional, Dict, Any
import numpy as np

from .asr_providers import ASRProvider, ASRConfig, ASRProviderRegistry

logger = logging.getLogger(__name__)

def _get_process_rss_mb() -> Optional[float]:
    """Best-effort process RSS in MB (used for health endpoints/observability)."""
    try:
        import psutil  # optional dependency

        rss = psutil.Process(os.getpid()).memory_info().rss
        return float(rss) / (1024 * 1024)
    except Exception:
        # Fallback: ru_maxrss is max RSS (not current RSS), units differ by platform.
        try:
            import resource  # stdlib

            rss = float(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
            if sys.platform == "darwin":
                return rss / (1024 * 1024)  # bytes → MB
            return rss / 1024  # KB → MB (Linux)
        except Exception:
            return None


class ModelState(Enum):
    """Model lifecycle states."""
    UNINITIALIZED = auto()
    LOADING = auto()
    WARMING_UP = auto()
    UNLOADING = auto()
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
    process_rss_mb: Optional[float] = None
    
    # Background download state
    download_in_progress: bool = False
    download_target_model: Optional[str] = None
    download_progress_pct: Optional[float] = None  # 0-100
    download_error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "state": self.state.name,
            "ready": self.ready,
            "model_loaded": self.model_loaded,
            "warmup_complete": self.warmup_complete,
            "load_time_ms": round(self.load_time_ms, 1),
            "warmup_time_ms": round(self.warmup_time_ms, 1),
            "last_error": self.last_error,
            "process_rss_mb": round(self.process_rss_mb, 1) if self.process_rss_mb is not None else None,
            "download_in_progress": self.download_in_progress,
            "download_target_model": self.download_target_model,
            "download_progress_pct": round(self.download_progress_pct, 1) if self.download_progress_pct is not None else None,
            "download_error": self.download_error,
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
    - Background model download with hot-swap
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
        
        # Background download state
        self._download_in_progress = False
        self._download_target_model: Optional[str] = None
        self._download_progress_pct: Optional[float] = None
        self._download_error: Optional[str] = None
        self._download_task: Optional[asyncio.Task] = None
        
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
        should_wait_for_existing_load = False
        async with self._lock:
            if self._state == ModelState.READY:
                return True

            if self._state in {ModelState.LOADING, ModelState.WARMING_UP}:
                should_wait_for_existing_load = True
            elif self._state == ModelState.UNLOADING:
                logger.warning("Model initialization requested while unloading")
                return False

            if should_wait_for_existing_load:
                pass
            else:
                self._ready_event.clear()
                self._last_error = None
                self._load_time_ms = 0.0
                self._warmup_time_ms = 0.0
                self._state = ModelState.LOADING

        if should_wait_for_existing_load:
            try:
                await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
                return self._state == ModelState.READY
            except asyncio.TimeoutError:
                return False
        
        try:
            # Phase 1: Load model
            logger.info("Phase 1/3: Loading model...")
            start = time.time()
            
            if not await self._load_model():
                async with self._lock:
                    self._state = ModelState.ERROR
                    self._ready_event.set()
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
        """Load the model, trying fallback if primary fails."""
        try:
            # Get provider - pass config if available so the right model is used
            if self.provider_name and self.config:
                self._provider = ASRProviderRegistry.get_provider(name=self.provider_name, config=self.config)
            elif self.provider_name:
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
            
            # Try fallback: attempt to find an available provider/model combo
            try:
                logger.info("Trying fallback provider/model...")
                fallback = self._try_fallback_provider()
                if fallback:
                    self._provider = fallback
                    logger.info(f"Fallback loaded: {fallback.name}")
                    return True
                logger.warning("No fallback provider available")
            except Exception as fallback_err:
                logger.error(f"Fallback also failed: {fallback_err}")
            
            return False
    
    def _try_fallback_provider(self) -> Optional[ASRProvider]:
        """Try to find an available provider/model combination as fallback."""
        import os
        
        # Read desired model from env
        desired_model = os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en")
        
        # For whisper_cpp: try smaller models if the configured one doesn't exist
        if os.getenv("ECHOPANEL_ASR_PROVIDER") == "whisper_cpp":
            fallback_models = ["base.en", "small.en", "tiny.en", "base", "small", "tiny"]
            
            for model in fallback_models:
                if model == desired_model:
                    continue  # Skip the one that already failed
                
                # Check if model file exists
                model_dir = Path(os.getenv("WHISPER_CPP_MODEL_DIR", "~/.cache/whisper")).expanduser()
                ggml_file = f"ggml-{model}.bin"
                if not (model_dir / ggml_file).exists():
                    logger.info(f"Fallback: model {model} not found, skipping")
                    continue
                
                # Try creating provider with this model
                try:
                    fallback_config = ASRConfig(
                        model_name=model,
                        device="gpu",
                        compute_type="q5_0",
                        chunk_seconds=2,
                    )
                    provider = ASRProviderRegistry.get_provider(name="whisper_cpp", config=fallback_config)
                    if provider and provider.is_available:
                        logger.info(f"Fallback: using whisper_cpp/{model}")
                        os.environ["ECHOPANEL_WHISPER_MODEL"] = model
                        return provider
                except Exception as e:
                    logger.info(f"Fallback whisper_cpp/{model} failed: {e}")
                    continue
        
        # Last resort: try faster_whisper provider
        try:
            fallback_config = ASRConfig(
                model_name="base.en",
                device="cpu",
                compute_type="int8",
                chunk_seconds=2,
            )
            provider = ASRProviderRegistry.get_provider(name="faster_whisper", config=fallback_config)
            if provider and provider.is_available:
                logger.info("Fallback: using faster_whisper/base.en")
                os.environ["ECHOPANEL_ASR_PROVIDER"] = "faster_whisper"
                os.environ["ECHOPANEL_WHISPER_MODEL"] = "base.en"
                return provider
        except Exception as e:
            logger.info(f"Fallback faster_whisper failed: {e}")
        
        return None
    
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

    async def _run_provider_hook(self, provider: ASRProvider, hook_name: str, timeout: float) -> None:
        hook = getattr(provider, hook_name, None)
        if not callable(hook):
            return
        maybe_awaitable = hook()
        if inspect.isawaitable(maybe_awaitable):
            await asyncio.wait_for(maybe_awaitable, timeout=timeout)

    def _reset_runtime_state_locked(self) -> None:
        self._provider = None
        self._load_time_ms = 0.0
        self._warmup_time_ms = 0.0
        self._inference_count = 0
        self._total_inference_time_ms = 0.0
        self._ready_event.clear()

    async def unload(self, timeout: float = 10.0) -> bool:
        """Unload the active provider and reset manager state."""
        async with self._lock:
            provider = self._provider
            if provider is None and self._state == ModelState.UNINITIALIZED:
                self._reset_runtime_state_locked()
                self._last_error = None
                return True
            self._state = ModelState.UNLOADING
            self._last_error = None
            self._ready_event.clear()

        try:
            if provider is not None:
                await self._run_provider_hook(provider, "stop_session", timeout=timeout)
                await self._run_provider_hook(provider, "unload", timeout=timeout)
                removed = ASRProviderRegistry.evict_provider_instance(provider)
                if removed:
                    logger.info("Evicted %d cached ASR provider instance(s)", removed)

            async with self._lock:
                self._reset_runtime_state_locked()
                self._state = ModelState.UNINITIALIZED
                self._last_error = None
            return True
        except Exception as e:
            logger.error(f"Model unload failed: {e}")
            async with self._lock:
                self._state = ModelState.ERROR
                self._last_error = str(e)
                self._ready_event.set()
            return False
    
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
            process_rss_mb=_get_process_rss_mb(),
            download_in_progress=self._download_in_progress,
            download_target_model=self._download_target_model,
            download_progress_pct=self._download_progress_pct,
            download_error=self._download_error,
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


async def shutdown_model_manager(timeout: float = 10.0) -> bool:
    """Unload and reset the global model manager."""
    global _model_manager
    if _model_manager is None:
        return True
    success = await _model_manager.unload(timeout=timeout)
    if success:
        _model_manager = None
    return success


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
    
    # Kick off background model download for the capability-optimal model
    # so we can hot-swap when it's ready without blocking startup.
    asyncio.ensure_future(_background_model_download(manager))
    
    return success


async def _background_model_download(manager: ModelManager) -> None:
    """
    Download the capability-optimal model in the background and hot-swap when ready.

    Flow:
    1. Detect machine capabilities (RAM, GPU)
    2. Determine optimal model for this machine
    3. If optimal model is already loaded, nothing to do
    4. If optimal model exists on disk but isn't loaded, hot-swap to it
    5. If optimal model doesn't exist, download it, then hot-swap
    6. If download fails, keep the current model running — no disruption
    """
    import os
    import subprocess
    from pathlib import Path

    try:
        current_model = os.getenv("ECHOPANEL_WHISPER_MODEL", "")
        current_provider = os.getenv("ECHOPANEL_ASR_PROVIDER", "")

        # Only relevant for whisper_cpp (the primary Apple Silicon provider)
        if current_provider != "whisper_cpp":
            logger.info("Background download: skipping (provider=%s, not whisper_cpp)", current_provider)
            return

        # Detect RAM for capability-based model selection
        ram_gb = _detect_ram_gb()
        has_mps = _detect_mps()

        # Determine optimal model based on capabilities
        optimal_model = _pick_optimal_model(ram_gb, has_mps)

        # If we're already running the optimal model, nothing to do
        if current_model == optimal_model:
            logger.info("Background download: already running optimal model %s", optimal_model)
            return

        # Set download state
        async with manager._lock:
            manager._download_in_progress = True
            manager._download_target_model = optimal_model
            manager._download_progress_pct = 0.0
            manager._download_error = None

        model_dir = Path(os.getenv("WHISPER_CPP_MODEL_DIR", "~/.cache/whisper")).expanduser()
        ggml_file = f"ggml-{optimal_model}.bin"
        model_path = model_dir / ggml_file

        # If optimal model already exists on disk, just hot-swap (no download)
        if model_path.exists():
            logger.info(
                "Background download: optimal model %s already on disk (%.0f MB), hot-swapping...",
                optimal_model, model_path.stat().st_size / (1024 * 1024)
            )
            await _hot_swap_model(manager, optimal_model)
            return

        # Download the model
        logger.info("Background download: fetching %s (%s) — current: %s", optimal_model, ggml_file, current_model)
        model_dir.mkdir(parents=True, exist_ok=True)

        url = f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{ggml_file}"

        # Use curl with progress tracking
        process = await asyncio.create_subprocess_exec(
            "curl", "-L", "--progress-bar", "-o", str(model_path), url,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        # Monitor download progress via file size
        expected_size_mb = _expected_model_size_mb(optimal_model)
        last_reported_pct = 0

        while process.returncode is None:
            await asyncio.sleep(1)
            if model_path.exists():
                downloaded_mb = model_path.stat().st_size / (1024 * 1024)
                if expected_size_mb > 0:
                    pct = min(100.0, (downloaded_mb / expected_size_mb) * 100)
                else:
                    pct = 0.0

                async with manager._lock:
                    manager._download_progress_pct = pct

                # Log every 10%
                if pct - last_reported_pct >= 10:
                    logger.info(
                        "Background download: %s — %.0f%% (%.0f / %.0f MB)",
                        optimal_model, pct, downloaded_mb, expected_size_mb
                    )
                    last_reported_pct = pct

        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            err_msg = stderr.decode().strip() if stderr else "unknown error"
            logger.error("Background download failed: %s", err_msg)
            async with manager._lock:
                manager._download_error = f"Download failed: {err_msg}"
                manager._download_progress_pct = None
            if model_path.exists():
                model_path.unlink()
            return

        logger.info("Background download: %s downloaded successfully", optimal_model)

        # Hot-swap to the new model
        await _hot_swap_model(manager, optimal_model)

    except asyncio.CancelledError:
        logger.info("Background download: cancelled")
    except Exception as e:
        logger.error("Background download error: %s", e)
        async with manager._lock:
            manager._download_error = str(e)
            manager._download_in_progress = False
            manager._download_progress_pct = None


async def _hot_swap_model(manager: ModelManager, model_name: str) -> None:
    """Unload current model and reload with the given model, preserving provider."""
    import os

    try:
        logger.info("Hot-swap: unloading current model...")
        await manager.unload()

        # Update env vars
        os.environ["ECHOPANEL_WHISPER_MODEL"] = model_name

        # Create new config for the target model
        new_config = ASRConfig(
            model_name=model_name,
            device="gpu",
            compute_type="q5_0",
            chunk_seconds=2,
        )
        manager.provider_name = "whisper_cpp"
        manager.config = new_config

        # Reload
        logger.info("Hot-swap: loading %s...", model_name)
        success = await manager.initialize()

        async with manager._lock:
            manager._download_in_progress = False
            manager._download_progress_pct = None

        if success:
            logger.info("Hot-swap complete: now using %s", model_name)
        else:
            logger.error("Hot-swap failed for %s, reverting...", model_name)
            manager._download_error = f"Hot-swap to {model_name} failed"
            # Revert env var and reload previous
            os.environ["ECHOPANEL_WHISPER_MODEL"] = os.getenv("ECHOPANEL_WHISPER_MODEL", model_name)
            await manager.initialize()

    except Exception as e:
        logger.error("Hot-swap error: %s", e)
        async with manager._lock:
            manager._download_error = str(e)
            manager._download_in_progress = False
            manager._download_progress_pct = None


def _detect_ram_gb() -> float:
    """Detect total RAM in GB."""
    try:
        import psutil
        return psutil.virtual_memory().total / (1024 ** 3)
    except ImportError:
        pass
    try:
        import subprocess
        result = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True)
        return int(result.stdout.strip()) / (1024 ** 3)
    except Exception:
        return 0.0


def _detect_mps() -> bool:
    """Detect Metal Performance Shaders (Apple Silicon GPU)."""
    try:
        import torch
        return torch.backends.mps.is_available()
    except Exception:
        return platform.system() == "Darwin" and platform.machine() == "arm64"


def _pick_optimal_model(ram_gb: float, has_mps: bool) -> str:
    """
    Pick the optimal whisper.cpp model based on machine capabilities.

    Returns the model name (e.g. 'medium.en', 'small.en').
    """
    if not has_mps:
        # No GPU — stick with smaller models even on high RAM
        if ram_gb >= 32:
            return "small.en"
        elif ram_gb >= 16:
            return "small.en"
        elif ram_gb >= 8:
            return "base.en"
        return "base.en"

    # Apple Silicon with GPU — can use larger models
    if ram_gb >= 64:
        return "large-v3-turbo"
    elif ram_gb >= 32:
        return "medium.en"
    elif ram_gb >= 16:
        return "small.en"
    elif ram_gb >= 8:
        return "base.en"
    return "base.en"


def _expected_model_size_mb(model_name: str) -> float:
    """Return approximate GGML model size in MB for progress tracking."""
    sizes = {
        "tiny": 75, "tiny.en": 75,
        "base": 142, "base.en": 142,
        "small": 466, "small.en": 466,
        "medium": 1500, "medium.en": 1500,
        "large-v1": 3000, "large-v2": 3000,
        "large-v3": 3100, "large-v3-turbo": 1600,
    }
    return sizes.get(model_name, 0)


class ProcessInfo:
    """Minimal wrapper for process info cross-platform."""
    @property
    def physicalMemory(self) -> int:
        import os
        try:
            # macOS
            import subprocess
            result = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True)
            return int(result.stdout.strip())
        except Exception:
            return 0
