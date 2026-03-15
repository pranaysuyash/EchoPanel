"""
VAD ASR Wrapper (v0.2)

Wraps any ASR provider with Voice Activity Detection (VAD) pre-filtering.
Silence is detected and skipped before being sent to the ASR model,
saving compute and improving latency.

Features:
    - Pluggable VAD backend: FireRedVAD (SOTA), TEN VAD (lightweight), Silero (fallback)
    - Configurable backend via ECHOPANEL_VAD_BACKEND env var
    - Automatic fallback chain: firered → ten_vad → silero
    - Configurable silence threshold and minimum speech duration
    - Statistics tracking (silence ratio, frames skipped)
    - Drop-in wrapper for any ASRProvider

Usage:
    from server.services.vad_asr_wrapper import VADASRWrapper
    from server.services.provider_faster_whisper import FasterWhisperProvider

    base_provider = FasterWhisperProvider(config)
    provider = VADASRWrapper(base_provider, threshold=0.5, vad_backend="firered")

    async for segment in provider.transcribe_stream(pcm_stream):
        print(segment.text)

VAD Backend Selection (ECHOPANEL_VAD_BACKEND):
    firered  — FireRedVAD (SOTA, Apache 2.0, 100+ langs, streaming+AED) [DEFAULT]
    ten_vad  — TEN VAD (306KB, 48% faster CPU, Apache 2.0, Linux x64 Python binding)
    silero   — Silero VAD (MIT, PyTorch, current fallback)
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import AsyncIterator, Optional, Dict, Any

import numpy as np

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, AudioSource

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# VAD Backend Abstraction
# ---------------------------------------------------------------------------

class _VADBackend:
    """Abstract base for VAD backends. Each backend implements has_speech()."""

    def has_speech(self, audio_float: "np.ndarray", sample_rate: int,
                   threshold: float, min_speech_ms: int, min_silence_ms: int) -> bool:
        raise NotImplementedError


class _SileroVADBackend(_VADBackend):
    """Silero VAD backend (MIT, PyTorch dependency). Fallback backend."""

    _model = None
    _utils = None

    def _load(self):
        if self._model is None:
            import torch
            model, utils = torch.hub.load(
                repo_or_dir="snakers4/silero-vad",
                model="silero_vad",
                force_reload=False,
                onnx=False,
            )
            _SileroVADBackend._model = model
            _SileroVADBackend._utils = utils
            logger.info("[VAD] Silero VAD model loaded")
        return self._model, self._utils

    def has_speech(self, audio_float, sample_rate, threshold,
                   min_speech_ms, min_silence_ms) -> bool:
        try:
            model, utils = self._load()
            (get_speech_timestamps, *_) = utils
            import torch
            audio_tensor = torch.from_numpy(audio_float)
            timestamps = get_speech_timestamps(
                audio_tensor, model,
                sampling_rate=sample_rate,
                threshold=threshold,
                min_speech_duration_ms=min_speech_ms,
                min_silence_duration_ms=min_silence_ms,
            )
            return len(timestamps) > 0
        except Exception as e:
            logger.warning(f"[VAD] Silero detection failed: {e}")
            return True  # fail-open


class _FireRedVADBackend(_VADBackend):
    """FireRedVAD backend (Apache 2.0, SOTA on FLEURS-VAD-102, 100+ languages).

    Requires: pip install -r <FireRedVAD repo>/requirements.txt
    + PYTHONPATH pointing to the FireRedVAD repo root.
    See docs/ASR_MODEL_RESEARCH_2026-02.md §8.1.4 for setup.
    """

    _stream_vad = None
    _loaded = False
    _available = None  # None=unknown, True/False after first attempt

    def _load(self):
        if _FireRedVADBackend._loaded:
            return _FireRedVADBackend._stream_vad
        try:
            from fireredvad import FireRedStreamVad, FireRedStreamVadConfig  # type: ignore
            import os
            model_dir = os.getenv(
                "ECHOPANEL_FIRERED_MODEL_DIR",
                "pretrained_models/FireRedVAD/Stream-VAD",
            )
            vad_config = FireRedStreamVadConfig(
                use_gpu=False,
                smooth_window_size=5,
                speech_threshold=0.4,   # default; overridden per-call via threshold arg
                min_speech_frame=8,
                max_speech_frame=2000,
                min_silence_frame=20,
                chunk_max_frame=30000,
            )
            _FireRedVADBackend._stream_vad = FireRedStreamVad.from_pretrained(model_dir, vad_config)
            _FireRedVADBackend._loaded = True
            _FireRedVADBackend._available = True
            logger.info("[VAD] FireRedVAD Stream-VAD loaded from %s", model_dir)
        except Exception as e:
            _FireRedVADBackend._loaded = True  # don't retry every call
            _FireRedVADBackend._available = False
            logger.warning("[VAD] FireRedVAD unavailable (%s) — will fall back", e)
        return _FireRedVADBackend._stream_vad

    def has_speech(self, audio_float, sample_rate, threshold,
                   min_speech_ms, min_silence_ms) -> bool:
        vad = self._load()
        if vad is None:
            return True  # fail-open if model not loaded
        try:
            import numpy as np
            import io, wave, struct
            # FireRedStreamVad.detect_full expects a wav path; use in-memory bytes via
            # detect_frames for streaming. Fallback: convert float32 to PCM bytes and
            # check if any timestamps returned.
            pcm_int16 = (audio_float * 32768.0).astype(np.int16)
            # Use frame-level detection on the chunk
            frame_results, result = vad.detect_full_from_array(
                pcm_int16, sample_rate=sample_rate
            )
            timestamps = result.get("timestamps", [])
            return len(timestamps) > 0
        except AttributeError:
            # Older API: detect_full(wav_path) only. Use a temp file.
            try:
                import tempfile, soundfile as sf
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    sf.write(tmp.name, audio_float, sample_rate)
                    _, result = vad.detect_full(tmp.name)
                    return len(result.get("timestamps", [])) > 0
            except Exception as e:
                logger.warning("[VAD] FireRedVAD detect failed: %s", e)
                return True
        except Exception as e:
            logger.warning("[VAD] FireRedVAD detect failed: %s", e)
            return True


class _TenVADBackend(_VADBackend):
    """TEN VAD backend (Apache 2.0, 306KB, 48% faster CPU than Silero).

    Python binding: Linux x64 only (pip install ten-vad).
    C/ONNX binary works on macOS — use _SileroVADBackend on macOS until
    Python binding is released.
    """

    _vad = None
    _loaded = False
    _available = None
    _HOP_SIZE = 160  # 10ms @ 16kHz

    def _load(self):
        if _TenVADBackend._loaded:
            return _TenVADBackend._vad
        try:
            import ten_vad  # type: ignore
            _TenVADBackend._vad = ten_vad.TenVad(hop_size=self._HOP_SIZE)
            _TenVADBackend._loaded = True
            _TenVADBackend._available = True
            logger.info("[VAD] TEN VAD loaded (hop_size=%d)", self._HOP_SIZE)
        except Exception as e:
            _TenVADBackend._loaded = True
            _TenVADBackend._available = False
            logger.warning("[VAD] TEN VAD unavailable (%s) — will fall back", e)
        return _TenVADBackend._vad

    def has_speech(self, audio_float, sample_rate, threshold,
                   min_speech_ms, min_silence_ms) -> bool:
        vad = self._load()
        if vad is None:
            return True  # fail-open
        try:
            import numpy as np
            pcm_int16 = (audio_float * 32768.0).astype(np.int16)
            results = []
            for i in range(0, len(pcm_int16) - self._HOP_SIZE + 1, self._HOP_SIZE):
                frame = pcm_int16[i:i + self._HOP_SIZE]
                prob = vad.process(frame)
                results.append(prob > threshold)
            return any(results)
        except Exception as e:
            logger.warning("[VAD] TEN VAD detect failed: %s", e)
            return True


def _build_vad_backend(backend_name: str) -> _VADBackend:
    """Resolve backend name to a VADBackend instance with cascading fallback.

    Priority order when backend_name="firered":
        FireRedVAD → TEN VAD → Silero
    When backend_name="ten_vad":
        TEN VAD → Silero
    When backend_name="silero":
        Silero (no fallback)
    """
    candidates: list
    if backend_name == "firered":
        candidates = [_FireRedVADBackend, _TenVADBackend, _SileroVADBackend]
    elif backend_name == "ten_vad":
        candidates = [_TenVADBackend, _SileroVADBackend]
    else:  # "silero" or unknown
        candidates = [_SileroVADBackend]

    for cls in candidates:
        backend = cls()
        # Eagerly probe availability for firered/ten_vad so we log fallback now
        if cls in (_FireRedVADBackend, _TenVADBackend):
            backend._load()  # triggers availability detection
            if backend.__class__._available:
                logger.info("[VAD] Using %s backend", cls.__name__)
                return backend
            logger.info("[VAD] %s not available, trying next backend", cls.__name__)
        else:
            logger.info("[VAD] Using %s backend", cls.__name__)
            return backend
    return _SileroVADBackend()  # absolute fallback


# Module-level default backend (lazy, set on first SmartVADRouter init)
_default_backend: Optional[_VADBackend] = None


def _get_default_backend() -> _VADBackend:
    """Return the module-level backend, building it once from the env var."""
    global _default_backend
    if _default_backend is None:
        import os
        backend_name = os.getenv("ECHOPANEL_VAD_BACKEND", "firered")
        _default_backend = _build_vad_backend(backend_name)
    return _default_backend


# ---------------------------------------------------------------------------
# Legacy Silero helpers (kept for backward compat if anything calls them directly)
# ---------------------------------------------------------------------------

_vad_model = None  # legacy alias
_vad_utils = None  # legacy alias


def _load_vad_model():
    """Lazy load Silero VAD model (legacy compat — use _SileroVADBackend directly)."""
    backend = _SileroVADBackend()
    model, utils = backend._load()
    global _vad_model, _vad_utils
    _vad_model, _vad_utils = model, utils
    return model, utils



@dataclass
class VADStats:
    """Statistics for VAD processing."""
    total_frames: int = 0
    speech_frames: int = 0
    silence_frames: int = 0
    skipped_chunks: int = 0
    processed_chunks: int = 0
    total_infer_time_saved_ms: float = 0.0
    
    @property
    def silence_ratio(self) -> float:
        if self.total_frames == 0:
            return 0.0
        return self.silence_frames / self.total_frames
    
    @property
    def skip_rate(self) -> float:
        total = self.skipped_chunks + self.processed_chunks
        if total == 0:
            return 0.0
        return self.skipped_chunks / total
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_frames": self.total_frames,
            "speech_frames": self.speech_frames,
            "silence_frames": self.silence_frames,
            "silence_ratio": round(self.silence_ratio, 3),
            "skipped_chunks": self.skipped_chunks,
            "processed_chunks": self.processed_chunks,
            "skip_rate": round(self.skip_rate, 3),
            "infer_time_saved_ms": round(self.total_infer_time_saved_ms, 1),
        }


class VADASRWrapper(ASRProvider):
    """Wraps an ASR provider with VAD pre-filtering.

    Intercepts the audio stream, detects silence using the configured VAD
    backend (FireRedVAD / TEN VAD / Silero), and only sends speech segments
    to the underlying ASR provider.
    """

    def __init__(
        self,
        provider: ASRProvider,
        threshold: float = 0.5,
        min_speech_duration_ms: int = 250,
        min_silence_duration_ms: int = 100,
        sample_rate: int = 16000,
        vad_backend: Optional[str] = None,  # None → uses ECHOPANEL_VAD_BACKEND env var
    ):
        """Initialize VAD wrapper.

        Args:
            provider: The underlying ASR provider to wrap
            threshold: VAD threshold (0.0-1.0), higher = more strict
            min_speech_duration_ms: Minimum speech duration to process
            min_silence_duration_ms: Minimum silence to split segments
            sample_rate: Expected sample rate (must be 8000 or 16000 for Silero)
            vad_backend: "firered", "ten_vad", or "silero". None = env var default.
        """
        super().__init__(provider.config)
        self._provider = provider
        self._threshold = threshold
        self._min_speech_duration_ms = min_speech_duration_ms
        self._min_silence_duration_ms = min_silence_duration_ms
        self._sample_rate = sample_rate
        self._stats = VADStats()
        self._vad_available = False

        if vad_backend is not None:
            self._backend = _build_vad_backend(vad_backend)
        else:
            self._backend = _get_default_backend()

        # Validate sample rate
        if sample_rate not in (8000, 16000):
            logger.warning(f"VAD works best with 8kHz or 16kHz, got {sample_rate}")

    @property
    def name(self) -> str:
        return f"vad_{self._provider.name}"
    
    @property
    def is_available(self) -> bool:
        return self._provider.is_available
    
    def _check_vad_available(self) -> bool:
        """Check if VAD backend is available, try to load if not."""
        if self._vad_available:
            return True
        # For firered/ten_vad the _load() was already triggered in _build_vad_backend.
        # For silero we probe here.
        try:
            if isinstance(self._backend, _SileroVADBackend):
                self._backend._load()
            available = getattr(self._backend.__class__, '_available', True)
            self._vad_available = available if available is not None else True
            return self._vad_available
        except Exception as e:
            logger.warning(f"VAD not available, falling back to passthrough: {e}")
            return False

    def _pcm_to_float(self, pcm_bytes: bytes) -> np.ndarray:
        """Convert PCM16 bytes to float32 numpy array [-1.0, 1.0]."""
        audio_int16 = np.frombuffer(pcm_bytes, dtype=np.int16)
        return audio_int16.astype(np.float32) / 32768.0

    def _has_speech(self, audio_float: np.ndarray) -> bool:
        """Check if audio contains speech using the configured VAD backend."""
        if not self._check_vad_available():
            return True  # fail-open
        try:
            return self._backend.has_speech(
                audio_float,
                self._sample_rate,
                self._threshold,
                self._min_speech_duration_ms,
                self._min_silence_duration_ms,
            )
        except Exception as e:
            logger.warning(f"VAD detection failed: {e}")
            return True  # fail-open

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """Transcribe audio stream with VAD pre-filtering.
        
        Silences are detected and skipped, only speech segments are sent
        to the underlying ASR provider.
        """
        if not self.is_available:
            self.log("ASR provider unavailable")
            yield ASRSegment(
                text="[ASR unavailable]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return
        
        # Check if VAD is available
        vad_enabled = self._check_vad_available()
        if not vad_enabled:
            self.log("VAD not available, passing through to provider")
            async for segment in self._provider.transcribe_stream(pcm_stream, sample_rate, source):
                yield segment
            return
        
        self.log(f"VAD enabled: threshold={self._threshold}, "
                f"min_speech={self._min_speech_duration_ms}ms")
        
        bytes_per_sample = 2
        chunk_seconds = self.config.chunk_seconds
        chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
        buffer = bytearray()
        processed_samples = 0
        
        async for chunk in pcm_stream:
            buffer.extend(chunk)
            
            # Process complete chunks
            while len(buffer) >= chunk_bytes:
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]
                
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                _t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples
                
                # Update stats
                self._stats.total_frames += chunk_samples
                
                # Convert to float for VAD
                audio_float = self._pcm_to_float(audio_bytes)
                
                # Check for speech
                has_speech = await asyncio.get_event_loop().run_in_executor(
                    None, self._has_speech, audio_float
                )
                
                if has_speech:
                    self._stats.speech_frames += chunk_samples
                    self._stats.processed_chunks += 1
                    
                    # Pass to underlying provider
                    # We need to wrap this single chunk as an async iterator
                    async def single_chunk():
                        yield audio_bytes
                    
                    async for segment in self._provider.transcribe_stream(
                        single_chunk(), sample_rate, source
                    ):
                        # Adjust timestamps to be absolute
                        yield ASRSegment(
                            text=segment.text,
                            t0=t0 + segment.t0,
                            t1=t0 + segment.t1,
                            confidence=segment.confidence,
                            is_final=segment.is_final,
                            source=segment.source,
                            language=segment.language,
                            speaker=segment.speaker,
                        )
                else:
                    self._stats.silence_frames += chunk_samples
                    self._stats.skipped_chunks += 1
                    
                    # Estimate inference time saved (assume 500ms per chunk)
                    self._stats.total_infer_time_saved_ms += 500
                    
                    if self._debug and self._stats.skipped_chunks % 10 == 0:
                        self.log(f"VAD: skipped {self._stats.skipped_chunks} silent chunks "
                                f"(ratio: {self._stats.silence_ratio:.2%})")
        
        # Process remaining buffer
        if buffer:
            audio_bytes = bytes(buffer)
            audio_float = self._pcm_to_float(audio_bytes)
            
            has_speech = await asyncio.get_event_loop().run_in_executor(
                None, self._has_speech, audio_float
            )
            
            if has_speech:
                async def single_chunk():
                    yield audio_bytes
                
                t0 = processed_samples / sample_rate
                
                async for segment in self._provider.transcribe_stream(
                    single_chunk(), sample_rate, source
                ):
                    yield ASRSegment(
                        text=segment.text,
                        t0=t0 + segment.t0,
                        t1=t0 + segment.t1,
                        confidence=segment.confidence,
                        is_final=segment.is_final,
                        source=segment.source,
                        language=segment.language,
                        speaker=segment.speaker,
                    )
        
        # Log final stats
        self.log(f"VAD complete: {self._stats.processed_chunks} processed, "
                f"{self._stats.skipped_chunks} skipped, "
                f"silence ratio: {self._stats.silence_ratio:.2%}, "
                f"time saved: {self._stats.total_infer_time_saved_ms/1000:.1f}s")
    
    def get_stats(self) -> Dict[str, Any]:
        """Get VAD processing statistics."""
        return self._stats.to_dict()
    
    async def health(self) -> Dict[str, Any]:
        """Get health metrics including VAD stats."""
        base_health = {}
        if hasattr(self._provider, 'health'):
            base_health = await self._provider.health()
        
        return {
            **base_health,
            "vad": {
                "available": self._vad_available,
                "threshold": self._threshold,
                "stats": self._stats.to_dict(),
            },
        }


class SmartVADRouter:
    """Routes audio to VAD or passthrough based on configuration.
    
    This is a higher-level wrapper that can dynamically enable/disable VAD
    based on degrade ladder state (disable VAD when under heavy load).
    """
    
    def __init__(
        self,
        provider: ASRProvider,
        vad_enabled: bool = True,
        vad_threshold: float = 0.5,
        vad_backend: Optional[str] = None,  # None → uses ECHOPANEL_VAD_BACKEND env var
    ):
        self._provider = provider
        self._vad_enabled = vad_enabled
        self._vad_threshold = vad_threshold
        self._vad_backend = vad_backend
        self._wrapper: Optional[VADASRWrapper] = None

        if vad_enabled:
            self._wrapper = VADASRWrapper(
                provider,
                threshold=vad_threshold,
                vad_backend=vad_backend,
            )

    @property
    def name(self) -> str:
        return self._provider.name
    
    @property
    def is_available(self) -> bool:
        return self._provider.is_available
    
    def set_vad_enabled(self, enabled: bool) -> None:
        """Enable or disable VAD dynamically."""
        if enabled == self._vad_enabled:
            return
        
        self._vad_enabled = enabled
        if enabled and self._wrapper is None:
            self._wrapper = VADASRWrapper(
                self._provider,
                threshold=self._vad_threshold,
                vad_backend=self._vad_backend,
            )
        elif not enabled:
            self._wrapper = None


        logger.info(f"VAD {'enabled' if enabled else 'disabled'}")
    
    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """Route to VAD wrapper or direct to provider."""
        if self._wrapper and self._vad_enabled:
            async for segment in self._wrapper.transcribe_stream(pcm_stream, sample_rate, source):
                yield segment
        else:
            async for segment in self._provider.transcribe_stream(pcm_stream, sample_rate, source):
                yield segment
    
    def get_stats(self) -> Dict[str, Any]:
        """Get statistics from VAD if enabled."""
        if self._wrapper:
            return self._wrapper.get_stats()
        return {"vad_enabled": False}


if __name__ == "__main__":
    # Demo/test mode
    logging.basicConfig(level=logging.INFO)
    
    print("=" * 60)
    print("VAD ASR Wrapper Demo")
    print("=" * 60)
    
    # Create mock provider
    from server.services.asr_providers import ASRConfig
    
    class MockProvider(ASRProvider):
        def __init__(self):
            super().__init__(ASRConfig())
        
        @property
        def name(self) -> str:
            return "mock"
        
        @property
        def is_available(self) -> bool:
            return True
        
        async def transcribe_stream(self, pcm_stream, sample_rate=16000, source=None):
            chunks = 0
            async for chunk in pcm_stream:
                chunks += 1
                yield ASRSegment(
                    text=f"Transcribed chunk {chunks}",
                    t0=chunks * 4,
                    t1=(chunks + 1) * 4,
                    confidence=0.9,
                    is_final=True,
                    source=source,
                )
    
    async def demo():
        # Test with mock audio (half speech, half silence)
        # This would normally be real audio
        print("\nDemo: VAD filtering on synthetic audio")
        print("(In real usage, would filter actual speech vs silence)")
        
        mock_provider = MockProvider()
        wrapper = VADASRWrapper(mock_provider, threshold=0.5)
        
        # Check VAD availability
        print(f"VAD available: {wrapper._check_vad_available()}")
        print(f"Stats: {wrapper.get_stats()}")
    
    asyncio.run(demo())
