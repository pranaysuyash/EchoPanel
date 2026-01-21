from __future__ import annotations

import asyncio
import os
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


def _get_model() -> Optional["WhisperModel"]:
    global _MODEL
    if WhisperModel is None:
        return None
    if _MODEL is None:
        model_size = os.getenv("ECHOPANEL_WHISPER_MODEL", "base")
        device = os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto")
        compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8_float16")
        _MODEL = WhisperModel(model_size, device=device, compute_type=compute_type)
    return _MODEL


async def stream_asr(pcm_stream: AsyncIterator[bytes], sample_rate: int = 16000) -> AsyncIterator[dict]:
    """
    Streaming ASR pipeline.

    If faster-whisper is available, it emits final segments from buffered audio.
    Otherwise, it emits a lightweight placeholder based on audio activity.
    """

    bytes_per_sample = 2
    chunk_seconds = 5
    chunk_bytes = sample_rate * chunk_seconds * bytes_per_sample
    buffer = bytearray()
    samples_seen = 0

    async for chunk in pcm_stream:
        buffer.extend(chunk)
        samples_seen += len(chunk) // bytes_per_sample

        if len(buffer) < chunk_bytes:
            continue

        t1 = samples_seen / sample_rate
        t0 = max(0.0, t1 - chunk_seconds)
        audio_bytes = bytes(buffer)
        buffer.clear()

        model = _get_model()
        if model is None or np is None:
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

        def _transcribe():
            segments, _info = model.transcribe(audio, language="en", vad_filter=True)
            return list(segments)

        segments = await asyncio.to_thread(_transcribe)
        for segment in segments:
            text = segment.text.strip()
            if not text:
                continue
            yield {
                "type": "asr_final",
                "t0": segment.start,
                "t1": segment.end,
                "text": text,
                "stable": True,
                "confidence": 0.8,
            }
