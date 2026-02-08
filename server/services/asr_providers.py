"""
ASR Provider Abstraction Layer (v0.2)

Defines the abstract interface for ASR providers, enabling swappable backends
(local Whisper, cloud APIs, etc.) without changing the WebSocket handler.
"""

from __future__ import annotations

import logging
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import AsyncIterator, Optional, List, cast

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


@dataclass
class ASRConfig:
    """Configuration for an ASR provider."""
    model_name: str = "large-v3-turbo"
    device: str = "auto"
    compute_type: str = "int8"
    language: Optional[str] = None  # None = auto-detect
    chunk_seconds: int = 4
    vad_enabled: bool = False


class ASRProvider(ABC):
    """Abstract base class for ASR providers."""

    def __init__(self, config: ASRConfig):
        self.config = config
        self._debug = os.getenv("ECHOPANEL_DEBUG", "0") == "1"

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

    def log(self, msg: str) -> None:
        """Debug logging helper."""
        logger.debug(f"[{self.name}] {msg}")


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
