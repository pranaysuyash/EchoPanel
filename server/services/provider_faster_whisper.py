"""
Local Faster-Whisper ASR Provider (v0.2)

Implements the ASRProvider interface using faster-whisper for local transcription.
"""

from __future__ import annotations

import asyncio
import os
import platform
from typing import AsyncIterator, Optional

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource

try:
    import numpy as np
except Exception:
    np = None

try:
    from faster_whisper import WhisperModel
except Exception:
    WhisperModel = None


class FasterWhisperProvider(ASRProvider):
    """ASR provider using faster-whisper (CTranslate2) for local inference."""

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self._model: Optional["WhisperModel"] = None

    @property
    def name(self) -> str:
        return "faster_whisper"

    @property
    def is_available(self) -> bool:
        return WhisperModel is not None and np is not None

    def _get_model(self) -> Optional["WhisperModel"]:
        if not self.is_available:
            return None
        
        if self._model is None:
            model_name = os.getenv("ECHOPANEL_WHISPER_MODEL", self.config.model_name)
            device = os.getenv("ECHOPANEL_WHISPER_DEVICE", self.config.device)
            
            # CTranslate2 does not support "metal". On macOS, "cpu" uses Accelerate framework.
            if device == "auto" and platform.system() == "Darwin":
                device = "cpu"
            
            compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", self.config.compute_type)
            
            self.log(f"Loading model={model_name} device={device} compute={compute_type}")
            
            try:
                self._model = WhisperModel(model_name, device=device, compute_type=compute_type)
            except Exception as e:
                self.log(f"FATAL ERROR loading model: {e}")
                raise e
        
        return self._model

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """Transcribe audio stream using faster-whisper."""
        
        bytes_per_sample = 2
        chunk_seconds = self.config.chunk_seconds
        chunk_bytes = sample_rate * chunk_seconds * bytes_per_sample
        buffer = bytearray()
        samples_seen = 0
        chunk_count = 0

        self.log(f"Started streaming, chunk_bytes={chunk_bytes} ({chunk_seconds}s)")

        async for chunk in pcm_stream:
            buffer.extend(chunk)
            samples_seen += len(chunk) // bytes_per_sample

            if len(buffer) < chunk_bytes:
                continue

            chunk_count += 1
            t1 = samples_seen / sample_rate
            t0 = max(0.0, t1 - chunk_seconds)
            audio_bytes = bytes(buffer)
            buffer.clear()

            self.log(f"Processing chunk #{chunk_count}, {len(audio_bytes)} bytes, t={t0:.1f}-{t1:.1f}s")

            model = self._get_model()
            if model is None or np is None:
                self.log("Missing model or numpy, emitting placeholder")
                yield ASRSegment(
                    text="Audio detected",
                    t0=t0, t1=t1,
                    confidence=0.3,
                    is_final=False,
                    source=source,
                )
                yield ASRSegment(
                    text="Audio detected.",
                    t0=t0, t1=t1,
                    confidence=0.3,
                    is_final=True,
                    source=source,
                )
                await asyncio.sleep(0)
                continue

            audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0

            def _transcribe():
                segments, info = model.transcribe(
                    audio,
                    vad_filter=self.config.vad_enabled,
                    language=self.config.language,  # None = auto-detect
                )
                return list(segments), info

            segments, info = await asyncio.to_thread(_transcribe)
            detected_lang = getattr(info, 'language', None)
            
            self.log(f"Transcribed {len(segments)} segments, language={detected_lang}")

            for segment in segments:
                text = segment.text.strip()
                if not text:
                    continue

                # Compute real confidence from avg_logprob (Gap 3 fix)
                # avg_logprob ranges from ~-2.0 (low confidence) to ~0 (high confidence)
                # Map to 0-1: confidence = max(0, min(1, 1 + avg_logprob / 2))
                avg_logprob = getattr(segment, 'avg_logprob', -0.5)
                confidence = max(0.0, min(1.0, 1.0 + avg_logprob / 2.0))
                
                # Log confidence for debugging
                if self._debug:
                    self.log(f"Segment: '{text[:30]}...' logprob={avg_logprob:.2f} conf={confidence:.2f}")

                # Emit partial (slightly lower confidence since not final)
                yield ASRSegment(
                    text=text,
                    t0=t0 + segment.start,
                    t1=t0 + segment.end,
                    confidence=confidence * 0.9,  # Partial is slightly less confident
                    is_final=False,
                    source=source,
                    language=detected_lang,
                )
                # Emit final
                yield ASRSegment(
                    text=text,
                    t0=t0 + segment.start,
                    t1=t0 + segment.end,
                    confidence=confidence,
                    is_final=True,
                    source=source,
                    language=detected_lang,
                )


# Register the provider
ASRProviderRegistry.register("faster_whisper", FasterWhisperProvider)
