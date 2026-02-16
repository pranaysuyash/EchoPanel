"""
Local Faster-Whisper ASR Provider (v0.4)

Implements the ASRProvider interface using faster-whisper for local transcription.

Fixes applied:
- P0: Fixed chunk loop to process exactly chunk_bytes at a time (prevents runaway growth)
- P0: Added inference lock to serialize model.transcribe calls (prevents concurrency issues)
- P0: Emit only final events (no fake partials)
- P0: Fixed timestamp math to track processed_samples correctly
- P1: Model loaded at first _get_model call (consider moving to startup)

v0.4: Added health metrics and capabilities (PR6)
"""

from __future__ import annotations

import asyncio
import os
import platform
import time
from typing import AsyncIterator, Optional, List

from .asr_providers import (
    ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource,
    ASRHealth, ProviderCapabilities,
)

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
        # NOTE: Removed global _infer_lock - CTranslate2 models are thread-safe
        # Each transcribe_stream call runs independently for true per-session concurrency
        self._infer_times: List[float] = []  # Track inference times for health
        self._model_loaded_at: Optional[float] = None
        self._chunks_processed = 0

    @property
    def name(self) -> str:
        return "faster_whisper"

    @property
    def is_available(self) -> bool:
        return WhisperModel is not None and np is not None
    
    @property
    def capabilities(self) -> ProviderCapabilities:
        """Report provider capabilities."""
        return ProviderCapabilities(
            supports_streaming=False,  # Chunked-batch, not true streaming
            supports_batch=True,
            supports_gpu=True,  # CUDA support
            supports_metal=False,  # CTranslate2 doesn't support MPS
            supports_cuda=True,
            supports_vad=True,  # Has built-in VAD option
            supports_diarization=False,
            supports_multilanguage=True,
            min_ram_gb=2.0,  # base.en needs ~2GB
            recommended_ram_gb=4.0,
        )

    def _get_model(self) -> Optional["WhisperModel"]:
        if not self.is_available:
            return None
        
        if self._model is None:
            model_name = os.getenv("ECHOPANEL_WHISPER_MODEL", self.config.model_name)
            device = os.getenv("ECHOPANEL_WHISPER_DEVICE", self.config.device)
            
            # CTranslate2 does not support MPS/Metal. On macOS, fallback to CPU.
            if device == "auto" and platform.system() == "Darwin":
                device = "cpu"
            elif device in {"mps", "metal"}:
                device = "cpu"
            
            compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", self.config.compute_type)
            
            # float16 variants are not supported on CPU, force int8.
            if device == "cpu" and "float16" in compute_type:
                compute_type = "int8"
                self.log("Forced compute_type='int8' for CPU execution (float16 variant unsupported)")
            
            self.log(f"Loading model={model_name} device={device} compute={compute_type}")
            
            try:
                self._model = WhisperModel(model_name, device=device, compute_type=compute_type)
                self._model_loaded_at = time.time()
                self._health.model_resident = True
                self._health.model_loaded_at = self._model_loaded_at
            except Exception as e:
                self.log(f"FATAL ERROR loading model: {e}")
                self._health.model_resident = False
                self._health.last_error = str(e)
                self._health.consecutive_errors += 1
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
                
                # Debug: check audio content
                audio_min = float(np.min(audio))
                audio_max = float(np.max(audio))
                audio_mean = float(np.mean(np.abs(audio)))
                if audio_mean < 0.001:
                    self.log(f"DEBUG: Audio is SILENT/NEAR-ZERO! min={audio_min:.4f}, max={audio_max:.4f}, mean={audio_mean:.6f}")
                else:
                    self.log(f"DEBUG: Audio OK - min={audio_min:.4f}, max={audio_max:.4f}, mean={audio_mean:.4f}")

                infer_start = time.perf_counter()
                
                def _transcribe():
                    # CTranslate2 models are thread-safe - no lock needed
                    # This allows true per-session concurrency instead of global serialization
                    segments, info = model.transcribe(
                        audio,
                        vad_filter=False,  # Force OFF for testing
                        language=self.config.language,
                    )
                    return list(segments), info

                segments, info = await asyncio.to_thread(_transcribe)
                
                infer_ms = (time.perf_counter() - infer_start) * 1000
                self._infer_times.append(infer_ms)
                self._chunks_processed += 1
                
                # Keep only last 100 measurements
                if len(self._infer_times) > 100:
                    self._infer_times = self._infer_times[-100:]
                detected_lang = getattr(info, 'language', None)
                
                # Calculate RTF (Real-Time Factor) - critical metric for streaming performance
                # RTF = processing_time / audio_time. < 1.0 means faster than real-time (good)
                audio_duration_sec = len(audio_bytes) / (sample_rate * bytes_per_sample)
                rtf = (infer_ms / 1000.0) / audio_duration_sec if audio_duration_sec > 0 else 0.0
                
                # Log with RTF - this is the key metric for diagnosing backpressure
                rtf_status = "OK" if rtf < 1.0 else ("WARN" if rtf < 1.5 else "CRITICAL")
                self.log(f"Transcribed {len(segments)} segments in {infer_ms:.1f}ms, language={detected_lang}, "
                         f"audio={audio_duration_sec:.2f}s, RTF={rtf:.2f} [{rtf_status}]")

                if len(segments) > 0:
                    self.log(f"DEBUG: First segment: text='{segments[0].text}', start={segments[0].start}, end={segments[0].end}")
                else:
                    self.log(f"DEBUG: No segments returned - empty audio?")

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

            # P2 Fix: Skip very small final buffers to prevent hallucination from silence/noise
            min_final_bytes = int(sample_rate * 0.5 * bytes_per_sample)  # 0.5 seconds minimum
            if len(audio_bytes) < min_final_bytes:
                self.log(f"Skipping final chunk: too small ({len(audio_bytes)} bytes < {min_final_bytes} min)")
                return

            audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0

            # P2 Fix: Check for silence/low energy to prevent hallucination
            audio_energy = np.sqrt(np.mean(audio**2))
            if audio_energy < 0.01:  # Very low energy threshold
                self.log(f"Skipping final chunk: low energy ({audio_energy:.4f})")
                return

            def _transcribe():
                # CTranslate2 models are thread-safe - no lock needed
                segments, info = model.transcribe(
                    audio,
                    vad_filter=True,  # P2 Fix: Always use VAD for final chunk
                    language=self.config.language,
                )
                return list(segments), info

            infer_start = time.perf_counter()
            segments, info = await asyncio.to_thread(_transcribe)
            infer_ms = (time.perf_counter() - infer_start) * 1000
            detected_lang = getattr(info, 'language', None)
            
            # Calculate RTF for final chunk
            audio_duration_sec = len(audio_bytes) / (sample_rate * bytes_per_sample)
            rtf = (infer_ms / 1000.0) / audio_duration_sec if audio_duration_sec > 0 else 0.0
            rtf_status = "OK" if rtf < 1.0 else ("WARN" if rtf < 1.5 else "CRITICAL")
            
            self.log(f"Transcribed {len(segments)} segments (final), language={detected_lang}, "
                     f"audio={audio_duration_sec:.2f}s, RTF={rtf:.2f} [{rtf_status}]")

            for segment in segments:
                text = segment.text.strip()
                if not text:
                    continue

                avg_logprob = getattr(segment, 'avg_logprob', -0.5)
                confidence = max(0.0, min(1.0, 1.0 + avg_logprob / 2.0))
                
                # P2 Fix: Filter low-confidence final segments to reduce hallucination
                if confidence < 0.3 and len(text.split()) < 3:
                    self.log(f"Filtering likely hallucination: '{text[:30]}...' conf={confidence:.2f}")
                    continue
                
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


    async def health(self) -> ASRHealth:
        """Get health metrics for faster-whisper provider."""
        health = await super().health()
        
        # Calculate RTF from inference times
        if self._infer_times:
            avg_ms = sum(self._infer_times) / len(self._infer_times)
            sorted_times = sorted(self._infer_times)
            p95_ms = sorted_times[int(len(sorted_times) * 0.95)] if len(sorted_times) > 1 else avg_ms
            p99_ms = sorted_times[int(len(sorted_times) * 0.99)] if len(sorted_times) > 1 else avg_ms
            
            # Assume 4s chunks (configurable)
            chunk_seconds = self.config.chunk_seconds
            rtf = (avg_ms / 1000.0) / chunk_seconds
            
            # Log RTF to help debug
            self.log(f"RTF: {rtf:.2f} (avg_infer={avg_ms:.0f}ms for {chunk_seconds}s chunk, p95={p95_ms:.0f}ms)")
            
            health.realtime_factor = rtf
            health.avg_infer_ms = avg_ms
            health.p95_infer_ms = p95_ms
            health.p99_infer_ms = p99_ms
        
        health.model_resident = self._model is not None
        health.model_loaded_at = self._model_loaded_at
        health.chunks_processed = self._chunks_processed
        
        return health

    async def unload(self) -> None:
        """Release model reference so memory can be reclaimed."""
        self._model = None
        self._model_loaded_at = None
        self._infer_times.clear()
        self._chunks_processed = 0
        await super().unload()


# Register the provider
ASRProviderRegistry.register("faster_whisper", FasterWhisperProvider)
