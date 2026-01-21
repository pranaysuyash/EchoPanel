from __future__ import annotations

import asyncio
import os
import platform
from typing import Optional
from collections.abc import AsyncIterator
from typing import Optional

try:
    import numpy as np
except Exception:  # pragma: no cover - optional dependency
    np = None

try:
    from faster_whisper import WhisperModel
except Exception:  # pragma: no cover - optional dependency
    WhisperModel = None

_MODEL: Optional["WhisperModel"] = None
DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"


def _get_model() -> Optional["WhisperModel"]:
    global _MODEL
    if WhisperModel is None:
        return None
    if _MODEL is None:
        # User requested better quality. 'large-v3-turbo' is excellent for multilingual (Hindi/Urdu distinction) 
        # and runs fast on Mac CPU (Accelerate).
        model_size = os.getenv("ECHOPANEL_WHISPER_MODEL", "large-v3-turbo")
        device = os.getenv("ECHOPANEL_WHISPER_DEVICE")
        if device is None:
            # CTranslate2 does not support "metal". On macOS ARM64, "cpu" uses Accelerate framework and is highly optimized.
            device = "cpu" if platform.system() == "Darwin" else "auto"
        compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE")
        if compute_type is None:
            compute_type = "int8" # int8 is optimal for CPU/Accelerate
        if DEBUG:
            print(f"asr_stream: loading model={model_size} device={device} compute={compute_type}")
        
        try:
            _MODEL = WhisperModel(model_size, device=device, compute_type=compute_type)
        except Exception as e:
            print(f"asr_stream: FATAL ERROR loading model: {e}")
            raise e
    return _MODEL


async def stream_asr(pcm_stream: AsyncIterator[bytes], sample_rate: int = 16000) -> AsyncIterator[dict]:
    """
    Streaming ASR pipeline.

    If faster-whisper is available, it emits final segments from buffered audio.
    Otherwise, it emits a lightweight placeholder based on audio activity.
    """

    bytes_per_sample = 2
    chunk_seconds = int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "4"))
    chunk_bytes = sample_rate * chunk_seconds * bytes_per_sample
    buffer = bytearray()
    samples_seen = 0
    chunk_count = 0

    print(f"asr_stream: started, chunk_bytes={chunk_bytes} ({chunk_seconds}s)")

    async for chunk in pcm_stream:
        buffer.extend(chunk)
        samples_seen += len(chunk) // bytes_per_sample
        
        if DEBUG and samples_seen % 16000 == 0:
            print(f"asr_stream: buffer={len(buffer)} bytes, samples_seen={samples_seen}")

        if len(buffer) < chunk_bytes:
            continue

        chunk_count += 1
        t1 = samples_seen / sample_rate
        t0 = max(0.0, t1 - chunk_seconds)
        audio_bytes = bytes(buffer)
        buffer.clear()
        
        print(f"asr_stream: processing chunk #{chunk_count}, {len(audio_bytes)} bytes, t={t0:.1f}-{t1:.1f}s")

        model = _get_model()
        if model is None or np is None:
            print("asr_stream: missing model or numpy, emitting placeholder")
            yield {
                "type": "asr_partial",
                "t0": t0,
                "t1": t1,
                "text": "Audio detected",
                "stable": False,
                "confidence": 0.3,
            }
            yield {
                "type": "asr_final",
                "t0": t0,
                "t1": t1,
                "text": "Audio detected.",
                "stable": True,
                "confidence": 0.3,
            }
            await asyncio.sleep(0)
            continue

        audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        if DEBUG:
            print(f"asr_stream: transcribing {len(audio)} samples")

        def _transcribe():
            # Disable VAD filter so we don't drop music/lyrics
            # Remove language="en" to allow auto-detection (for Hindi etc)
            segments, _info = model.transcribe(audio, vad_filter=False)
            return list(segments)

        segments = await asyncio.to_thread(_transcribe)
        # segments = list(segments) # Already listed above
        
        if DEBUG:
            print(f"asr_stream: transcribed {len(segments)} segments")
        
        for segment in segments:
            text = segment.text.strip()
            if not text:
                continue
            yield {
                "type": "asr_partial",
                "t0": t0 + segment.start,
                "t1": t0 + segment.end,
                "text": text,
                "stable": False,
                "confidence": 0.7,
            }
            yield {
                "type": "asr_final",
                "t0": t0 + segment.start,
                "t1": t0 + segment.end,
                "text": text,
                "stable": True,
                "confidence": 0.8,
            }
