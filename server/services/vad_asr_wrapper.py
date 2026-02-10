"""
VAD ASR Wrapper (v0.1)

Wraps any ASR provider with Voice Activity Detection (VAD) pre-filtering.
Silence is detected and skipped before being sent to the ASR model,
saving compute and improving latency.

Features:
    - Silero VAD integration (lazy-loaded)
    - Configurable silence threshold and minimum speech duration
    - Statistics tracking (silence ratio, frames skipped)
    - Drop-in wrapper for any ASRProvider

Usage:
    from server.services.vad_asr_wrapper import VADASRWrapper
    from server.services.provider_faster_whisper import FasterWhisperProvider
    
    # Wrap any provider
    base_provider = FasterWhisperProvider(config)
    provider = VADASRWrapper(
        base_provider,
        threshold=0.5,
        min_speech_duration_ms=250,
    )
    
    # Use normally
    async for segment in provider.transcribe_stream(pcm_stream):
        print(segment.text)
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import AsyncIterator, Optional, Dict, Any, List

import numpy as np

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, AudioSource

logger = logging.getLogger(__name__)

# Silero VAD lazy loading
_vad_model = None
_vad_utils = None

def _load_vad_model():
    """Lazy load Silero VAD model."""
    global _vad_model, _vad_utils
    if _vad_model is None:
        try:
            import torch
            model, utils = torch.hub.load(
                repo_or_dir="snakers4/silero-vad",
                model="silero_vad",
                force_reload=False,
                onnx=False,
            )
            _vad_model = model
            _vad_utils = utils
            logger.info("Silero VAD model loaded")
        except Exception as e:
            logger.warning(f"Failed to load Silero VAD: {e}")
            raise
    return _vad_model, _vad_utils


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
    
    This wrapper intercepts the audio stream, detects silence using Silero VAD,
    and only sends speech segments to the underlying ASR provider.
    """

    def __init__(
        self,
        provider: ASRProvider,
        threshold: float = 0.5,
        min_speech_duration_ms: int = 250,
        min_silence_duration_ms: int = 100,
        sample_rate: int = 16000,
    ):
        """Initialize VAD wrapper.
        
        Args:
            provider: The underlying ASR provider to wrap
            threshold: VAD threshold (0.0-1.0), higher = more strict
            min_speech_duration_ms: Minimum speech duration to process
            min_silence_duration_ms: Minimum silence to split segments
            sample_rate: Expected sample rate (must be 8000 or 16000 for Silero)
        """
        super().__init__(provider.config)
        self._provider = provider
        self._threshold = threshold
        self._min_speech_duration_ms = min_speech_duration_ms
        self._min_silence_duration_ms = min_silence_duration_ms
        self._sample_rate = sample_rate
        self._stats = VADStats()
        self._vad_available = False
        
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
        """Check if VAD is available, try to load if not."""
        if self._vad_available:
            return True
        
        try:
            _load_vad_model()
            self._vad_available = True
            return True
        except Exception as e:
            logger.warning(f"VAD not available, falling back to passthrough: {e}")
            return False
    
    def _pcm_to_float(self, pcm_bytes: bytes) -> np.ndarray:
        """Convert PCM16 bytes to float32 numpy array [-1.0, 1.0]."""
        # Convert bytes to int16 array
        audio_int16 = np.frombuffer(pcm_bytes, dtype=np.int16)
        # Normalize to float32 [-1.0, 1.0]
        return audio_int16.astype(np.float32) / 32768.0
    
    def _has_speech(self, audio_float: np.ndarray) -> bool:
        """Check if audio contains speech using Silero VAD.
        
        Args:
            audio_float: Float32 audio samples in [-1.0, 1.0]
        
        Returns:
            True if speech detected, False otherwise
        """
        if not self._check_vad_available():
            # VAD not available, assume speech
            return True
        
        try:
            model, utils = _load_vad_model()
            (get_speech_timestamps, _, _, _, _) = utils
            
            # Convert to torch tensor
            import torch
            audio_tensor = torch.from_numpy(audio_float)
            
            # Get speech timestamps
            speech_timestamps = get_speech_timestamps(
                audio_tensor,
                model,
                sampling_rate=self._sample_rate,
                threshold=self._threshold,
                min_speech_duration_ms=self._min_speech_duration_ms,
                min_silence_duration_ms=self._min_silence_duration_ms,
            )
            
            return len(speech_timestamps) > 0
            
        except Exception as e:
            logger.warning(f"VAD detection failed: {e}")
            # Fall back to processing (don't drop on error)
            return True
    
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
                t1 = (processed_samples + chunk_samples) / sample_rate
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
    ):
        self._provider = provider
        self._vad_enabled = vad_enabled
        self._vad_threshold = vad_threshold
        self._wrapper: Optional[VADASRWrapper] = None
        
        if vad_enabled:
            self._wrapper = VADASRWrapper(
                provider,
                threshold=vad_threshold,
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
