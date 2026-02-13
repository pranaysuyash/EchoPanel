"""
ASR Provider Abstraction Layer (v0.3)

Defines the abstract interface for ASR providers, enabling swappable backends
(local Whisper, cloud APIs, etc.) without changing the WebSocket handler.

New in v0.3:
    - Health metrics support (realtime_factor, inference latency)
    - Session lifecycle hooks (start_session, stop_session)
    - Enhanced ASRSegment with metadata
    - Provider capability reporting
"""

from __future__ import annotations

import logging
import os
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import AsyncIterator, Optional, List, Dict, Any, cast

logger = logging.getLogger(__name__)


class AudioSource(Enum):
    """Audio source identifier for multi-source capture."""
    SYSTEM = "system"
    MICROPHONE = "mic"


@dataclass
class ASRSegment:
    """A transcribed segment from the ASR provider."""
    text: str
    t0: float       # Start time in seconds
    t1: float       # End time in seconds
    confidence: float
    is_final: bool
    source: Optional[AudioSource] = None
    language: Optional[str] = None
    speaker: Optional[str] = None  # For future diarization
    
    # Additional metadata (v0.3)
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ASRConfig:
    """Configuration for an ASR provider."""
    model_name: str = "base"
    device: str = "auto"
    compute_type: str = "int8"
    language: Optional[str] = None  # None = auto-detect
    chunk_seconds: int = 4
    vad_enabled: bool = False
    
    # Additional config (v0.3)
    max_buffer_seconds: int = 30  # Max audio buffer before forced flush
    streaming_delay_ms: int = 500  # For streaming providers


@dataclass
class ASRHealth:
    """Health metrics for an ASR provider (v0.3).
    
    These metrics help the degrade ladder make decisions about
    when to adjust configuration for optimal performance.
    """
    # Performance metrics
    realtime_factor: float = 0.0       # inference_time / audio_time (< 1.0 is good)
    avg_infer_ms: float = 0.0          # Average inference latency in milliseconds
    p95_infer_ms: float = 0.0          # 95th percentile inference latency
    p99_infer_ms: float = 0.0          # 99th percentile inference latency
    
    # Queue/backpressure metrics
    backlog_estimate: int = 0          # Estimated queued chunks waiting
    dropped_chunks: int = 0            # Total chunks dropped due to backpressure
    
    # Model state
    model_resident: bool = False       # True if model is loaded and hot
    model_loaded_at: Optional[float] = None  # Unix timestamp when model was loaded
    
    # Error state
    last_error: Optional[str] = None   # Last error message
    consecutive_errors: int = 0        # Count of consecutive errors
    
    # Session state
    session_active: bool = False       # True if session is running
    session_duration_s: float = 0.0    # Duration of current session
    chunks_processed: int = 0          # Total chunks processed this session
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "realtime_factor": round(self.realtime_factor, 3),
            "avg_infer_ms": round(self.avg_infer_ms, 1),
            "p95_infer_ms": round(self.p95_infer_ms, 1),
            "p99_infer_ms": round(self.p99_infer_ms, 1),
            "backlog_estimate": self.backlog_estimate,
            "dropped_chunks": self.dropped_chunks,
            "model_resident": self.model_resident,
            "model_loaded_at": self.model_loaded_at,
            "last_error": self.last_error,
            "consecutive_errors": self.consecutive_errors,
            "session_active": self.session_active,
            "session_duration_s": round(self.session_duration_s, 1),
            "chunks_processed": self.chunks_processed,
        }
    
    @property
    def is_healthy(self) -> bool:
        """Check if provider is performing within acceptable limits."""
        return (
            self.realtime_factor < 1.0 and
            self.consecutive_errors == 0 and
            self.backlog_estimate < 5
        )
    
    @property
    def status(self) -> str:
        """Get human-readable status."""
        if self.consecutive_errors > 3:
            return "error"
        elif self.realtime_factor > 1.2:
            return "critical"
        elif self.realtime_factor > 1.0:
            return "degraded"
        elif self.realtime_factor > 0.8:
            return "warning"
        else:
            return "healthy"


@dataclass
class ProviderCapabilities:
    """Capabilities reported by an ASR provider (v0.3).
    
    Used for automatic provider selection and UI indication.
    """
    supports_streaming: bool = False       # True if supports real-time streaming
    supports_batch: bool = True            # True if supports batch transcription
    supports_gpu: bool = False             # True if can use GPU acceleration
    supports_metal: bool = False           # True if supports Apple Metal
    supports_cuda: bool = False            # True if supports NVIDIA CUDA
    supports_vad: bool = False             # True if has built-in VAD
    supports_diarization: bool = False     # True if supports speaker diarization
    supports_multilanguage: bool = False   # True if supports multiple languages
    
    # Resource requirements
    min_ram_gb: float = 4.0
    recommended_ram_gb: float = 8.0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "supports_streaming": self.supports_streaming,
            "supports_batch": self.supports_batch,
            "supports_gpu": self.supports_gpu,
            "supports_metal": self.supports_metal,
            "supports_cuda": self.supports_cuda,
            "supports_vad": self.supports_vad,
            "supports_diarization": self.supports_diarization,
            "supports_multilanguage": self.supports_multilanguage,
            "min_ram_gb": self.min_ram_gb,
            "recommended_ram_gb": self.recommended_ram_gb,
        }


class ASRProvider(ABC):
    """Abstract base class for ASR providers (v0.3).
    
    New providers should implement:
        - name (property)
        - is_available (property)
        - transcribe_stream (method)
        - health (method) - optional but recommended
        - capabilities (property) - optional but recommended
        - start_session / stop_session - optional for providers that need lifecycle
    """

    def __init__(self, config: ASRConfig):
        self.config = config
        self._debug = os.getenv("ECHOPANEL_DEBUG", "0") == "1"
        self._health = ASRHealth()
        self._session_start_time: Optional[float] = None

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable name of the provider."""
        pass

    @property
    @abstractmethod
    def is_available(self) -> bool:
        """Check if this provider is available (dependencies installed, API keys set, etc.)."""
        pass

    @property
    def capabilities(self) -> ProviderCapabilities:
        """Report provider capabilities. Override to advertise features."""
        return ProviderCapabilities()

    @abstractmethod
    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """
        Transcribe a stream of PCM audio bytes.

        Args:
            pcm_stream: Async iterator of raw PCM16 audio chunks
            sample_rate: Audio sample rate (default 16000)
            source: Optional audio source tag (system/mic)

        Yields:
            ASRSegment objects for partial and final transcriptions
        """
        # Makes this an async generator for type checkers (never runs)
        if False:
            yield cast(ASRSegment, None)
        raise NotImplementedError

    async def start_session(self, session_id: str) -> bool:
        """Start a new transcription session (v0.3).
        
        Called before transcribe_stream to allow providers to initialize
        resources. Optional for providers that don't need session lifecycle.
        
        Args:
            session_id: Unique identifier for this session
        
        Returns:
            True if session started successfully
        """
        self._session_start_time = time.time()
        self._health.session_active = True
        self._health.session_duration_s = 0.0
        self._health.chunks_processed = 0
        return True

    async def stop_session(self) -> None:
        """Stop the current transcription session (v0.3).
        
        Called after transcribe_stream completes to allow cleanup.
        Must complete in bounded time (< 5 seconds).
        """
        self._health.session_active = False
        if self._session_start_time:
            self._health.session_duration_s = time.time() - self._session_start_time
            self._session_start_time = None

    async def health(self) -> ASRHealth:
        """Get current health metrics (v0.3).
        
        Override to provide real metrics from the provider.
        Default implementation returns cached health state.
        
        Returns:
            ASRHealth with current performance metrics
        """
        # Update session duration if active
        if self._session_start_time:
            self._health.session_duration_s = time.time() - self._session_start_time
        return self._health

    async def flush(self, source: Optional[AudioSource] = None) -> List[ASRSegment]:
        """Force flush any buffered audio and return final segments (v0.3).
        
        Optional for providers that buffer audio internally.
        
        Args:
            source: Optional source to flush (for multi-source providers)
        
        Returns:
            List of final ASRSegments from buffered audio
        """
        return []

    async def unload(self) -> None:
        """Release provider-held resources.
        
        Providers that keep model/process state should override this to free memory
        and stop background work. Default implementation is a no-op.
        """
        self._health.model_resident = False
        self._health.model_loaded_at = None

    def log(self, msg: str) -> None:
        """Debug logging helper."""
        logger.debug(f"[{self.name}] {msg}")
    
    def _update_health(self, **kwargs) -> None:
        """Update health metrics (internal helper)."""
        for key, value in kwargs.items():
            if hasattr(self._health, key):
                setattr(self._health, key, value)


class ASRProviderRegistry:
    """Registry for managing ASR providers."""

    _providers: dict[str, type[ASRProvider]] = {}
    _instances: dict[str, ASRProvider] = {}
    _lock: "threading.Lock | None" = None  # Lazy init to avoid import at module level

    @classmethod
    def _get_lock(cls) -> "threading.Lock":
        """Get or create the registry lock (thread-safe lazy init)."""
        if cls._lock is None:
            import threading
            cls._lock = threading.Lock()
        return cls._lock

    @classmethod
    def register(cls, name: str, provider_class: type[ASRProvider]) -> None:
        """Register a provider class."""
        cls._providers[name] = provider_class

    @classmethod
    def _cfg_key(cls, name: str, cfg: ASRConfig) -> str:
        return f"{name}|{cfg.model_name}|{cfg.device}|{cfg.compute_type}|{cfg.language}|{int(cfg.vad_enabled)}|{cfg.chunk_seconds}"

    @classmethod
    def get_provider(cls, name: Optional[str] = None, config: Optional[ASRConfig] = None) -> Optional[ASRProvider]:
        """Get or create a provider instance (thread-safe)."""
        if name is None:
            name = os.getenv("ECHOPANEL_ASR_PROVIDER", "faster_whisper")
        
        if name not in cls._providers:
            return None
        
        cfg = config or ASRConfig()
        key = cls._cfg_key(name, cfg)

        # Thread-safe instance creation (P0 fix: RC-1)
        with cls._get_lock():
            if key not in cls._instances:
                cls._instances[key] = cls._providers[name](cfg)
            return cls._instances[key]

    @classmethod
    def available_providers(cls) -> List[str]:
        """List all registered providers that are available."""
        result = []
        for name, provider_class in cls._providers.items():
            try:
                instance = provider_class(ASRConfig())
                if instance.is_available:
                    result.append(name)
            except Exception:
                pass
        return result
    
    @classmethod
    def get_provider_info(cls) -> Dict[str, Dict[str, Any]]:
        """Get detailed information about all registered providers (v0.3).
        
        Returns:
            Dict mapping provider name to info dict with availability and capabilities.
        """
        result = {}
        for name, provider_class in cls._providers.items():
            try:
                instance = provider_class(ASRConfig())
                result[name] = {
                    "available": instance.is_available,
                    "capabilities": instance.capabilities.to_dict(),
                }
            except Exception as e:
                result[name] = {
                    "available": False,
                    "error": str(e),
                }
        return result

    @classmethod
    def evict_provider_instance(cls, provider: ASRProvider) -> int:
        """Evict a provider instance from the cache.
        
        Returns:
            Number of cache entries removed.
        """
        removed = 0
        with cls._get_lock():
            keys_to_remove = [key for key, value in cls._instances.items() if value is provider]
            for key in keys_to_remove:
                cls._instances.pop(key, None)
                removed += 1
        return removed
