"""
Local Faster-Whisper ASR Provider (v0.3)

Implements the ASRProvider interface using faster-whisper for local transcription.

Fixes applied:
- P0: Fixed chunk loop to process exactly chunk_bytes at a time (prevents runaway growth)
- P0: Added inference lock to serialize model.transcribe calls (prevents concurrency issues)
- P0: Emit only final events (no fake partials)
- P0: Fixed timestamp math to track processed_samples correctly
- P1: Model loaded at first _get_model call (consider moving to startup)
"""

from __future__ import annotations

import asyncio
import os
import platform
import threading
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
        self._infer_lock = threading.Lock()

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
            
            # CTranslate2 does not support MPS. On macOS, fallback to CPU which uses Accelerate.
            # (Validated in model-lab/harness/registry.py#L538-543)
            if device == "auto" and platform.system() == "Darwin":
                device = "cpu"
            elif device == "mps":
                device = "cpu"  # faster-whisper doesn't support MPS directly
            
            compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", self.config.compute_type)
            
            # float16 is not supported on CPU, force int8 (model-lab/harness/registry.py#L546-548)
            if device == "cpu" and compute_type == "float16":
                compute_type = "int8"
                self.log("Forced compute_type='int8' for CPU execution (float16 unsupported)")
            
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
        chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
        buffer = bytearray()
        processed_samples = 0  # samples already transcribed (for timestamp base)
        chunk_count = 0

        self.log(f"Started streaming, chunk_bytes={chunk_bytes} ({chunk_seconds}s)")

        model = self._get_model()
        if model is None or np is None:
            self.log("ASR unavailable: missing faster-whisper or numpy")
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

        async for chunk in pcm_stream:
            buffer.extend(chunk)

            # Process exactly one chunk at a time, leave remainder in buffer
            while len(buffer) >= chunk_bytes:
                chunk_count += 1
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]

                # Timestamps based on processed samples, not incoming bytes
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples

                self.log(f"Processing chunk #{chunk_count}, {len(audio_bytes)} bytes, t={t0:.1f}-{t1:.1f}s")

                audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0

                def _transcribe():
                    with self._infer_lock:
                        segments, info = model.transcribe(
                            audio,
                            vad_filter=self.config.vad_enabled,
                            language=self.config.language,
                        )
                    return list(segments), info

                segments, info = await asyncio.to_thread(_transcribe)
                detected_lang = getattr(info, 'language', None)
                
                self.log(f"Transcribed {len(segments)} segments, language={detected_lang}")

                for segment in segments:
                    text = segment.text.strip()
                    if not text:
                        continue

                    # Compute real confidence from avg_logprob
                    # avg_logprob ranges from ~-2.0 (low) to ~0 (high)
                    avg_logprob = getattr(segment, 'avg_logprob', -0.5)
                    confidence = max(0.0, min(1.0, 1.0 + avg_logprob / 2.0))
                    
                    if self._debug:
                        self.log(f"Segment: '{text[:30]}...' logprob={avg_logprob:.2f} conf={confidence:.2f}")

                    # Emit only final (no fake partials)
                    yield ASRSegment(
                        text=text,
                        t0=t0 + segment.start,
                        t1=t0 + segment.end,
                        confidence=confidence,
                        is_final=True,
                        source=source,
                        language=detected_lang,
                    )

        # Process any remaining buffer at end of stream
        if buffer:
            chunk_count += 1
            audio_bytes = bytes(buffer)
            del buffer[:]

            t0 = processed_samples / sample_rate
            chunk_samples = len(audio_bytes) // bytes_per_sample
            t1 = (processed_samples + chunk_samples) / sample_rate
            processed_samples += chunk_samples

            self.log(f"Processing final chunk #{chunk_count}, {len(audio_bytes)} bytes, t={t0:.1f}-{t1:.1f}s")

            audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0

            def _transcribe():
                with self._infer_lock:
                    segments, info = model.transcribe(
                        audio,
                        vad_filter=self.config.vad_enabled,
                        language=self.config.language,
                    )
                return list(segments), info

            segments, info = await asyncio.to_thread(_transcribe)
            detected_lang = getattr(info, 'language', None)
            
            self.log(f"Transcribed {len(segments)} segments, language={detected_lang}")

            for segment in segments:
                text = segment.text.strip()
                if not text:
                    continue

                avg_logprob = getattr(segment, 'avg_logprob', -0.5)
                confidence = max(0.0, min(1.0, 1.0 + avg_logprob / 2.0))
                
                if self._debug:
                    self.log(f"Segment: '{text[:30]}...' logprob={avg_logprob:.2f} conf={confidence:.2f}")

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
