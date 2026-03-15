"""
ASR Streaming Pipeline (v0.3)

Provides the high-level streaming ASR interface using the provider abstraction.
This file is the main entry point for the WebSocket handler.

Env vars:
    ECHOPANEL_WHISPER_MODEL     — Model name (default: base.en)
    ECHOPANEL_WHISPER_DEVICE    — Device (default: auto)
    ECHOPANEL_WHISPER_COMPUTE   — Compute type (default: int8)
    ECHOPANEL_WHISPER_LANGUAGE  — Language (default: en)
    ECHOPANEL_ASR_CHUNK_SECONDS — Chunk size in seconds (default: 2)
    ECHOPANEL_ASR_VAD           — Enable VAD (default: 1)
    ECHOPANEL_VAD_THRESHOLD     — VAD threshold (default: 0.5)
    ECHOPANEL_VAD_MIN_SPEECH_MS — Min speech duration ms (default: 250)
    ECHOPANEL_VAD_MIN_SILENCE_MS— Min silence duration ms (default: 100)
    ECHOPANEL_VAD_BACKEND       — VAD backend: firered|ten_vad|silero (default: firered)
    ECHOPANEL_DIARIZATION_ENABLED — Enable speaker diarization (default: 0)
                                    Requires ECHOPANEL_HF_TOKEN + pyannote.audio installed.
"""

from __future__ import annotations

import logging
import os
from typing import AsyncIterator, List, Optional

from .asr_providers import ASRConfig, ASRProviderRegistry, AudioSource

# Import providers to trigger registration
from . import provider_faster_whisper  # noqa: F401
from . import provider_voxtral_realtime  # noqa: F401
from . import provider_whisper_cpp  # noqa: F401
from . import provider_mlx_whisper  # noqa: F401 — F-006: was missing, mlx_whisper now reachable via WebSocket entry
from . import provider_voxtral_official  # noqa: F401 — F-006: was missing, voxtral_official now reachable
from . import provider_onnx_whisper  # noqa: F401 — F-006: was missing, onnx_whisper now reachable


logger = logging.getLogger(__name__)


def _get_default_config() -> ASRConfig:
    """Build ASRConfig from environment variables."""
    # VAD enabled by default to save compute (~40% reduction in silent meetings)
    vad_default = os.getenv("ECHOPANEL_ASR_VAD", "1") == "1"
    
    return ASRConfig(
        model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en"),
        device=os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto"),
        compute_type=os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8"),
        language=os.getenv("ECHOPANEL_WHISPER_LANGUAGE", "en"),  # Default to English
        chunk_seconds=int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2")),  # PR3: Reduced from 4s
        vad_enabled=vad_default,
        # VAD tuning parameters
        vad_threshold=float(os.getenv("ECHOPANEL_VAD_THRESHOLD", "0.5")),
        vad_min_speech_ms=int(os.getenv("ECHOPANEL_VAD_MIN_SPEECH_MS", "250")),
        vad_min_silence_ms=int(os.getenv("ECHOPANEL_VAD_MIN_SILENCE_MS", "100")),
    )


def _should_diarize() -> bool:
    """Return True when speaker diarization is enabled via env var."""
    return os.getenv("ECHOPANEL_DIARIZATION_ENABLED", "0") == "1"


def _resolve_speakers(
    final_segments: List[dict],
    speaker_segments: List[dict],
) -> List[dict]:
    """Attach speaker labels to final_segments by midpoint overlap with speaker_segments."""
    if not speaker_segments:
        return final_segments
    result = []
    for seg in final_segments:
        mid = ((seg.get("t0") or 0.0) + (seg.get("t1") or 0.0)) / 2.0
        speaker = None
        for spk in speaker_segments:
            if spk["t0"] <= mid <= spk["t1"]:
                speaker = spk["speaker"]
                break
        out = dict(seg)
        if speaker:
            out["speaker"] = speaker
        result.append(out)
    return result


async def stream_asr(
    pcm_stream: AsyncIterator[bytes],
    sample_rate: int = 16000,
    source: Optional[str] = None,
) -> AsyncIterator[dict]:
    """
    Streaming ASR pipeline using the registered provider.

    Converts ASRSegment objects to the dict format expected by the WebSocket handler.

    When ECHOPANEL_DIARIZATION_ENABLED=1, PCM is accumulated during the stream and
    diarization runs after the stream ends. A trailing ``diarization_result`` event
    is emitted with speaker-annotated final segments — real-time transcripts are
    not delayed.

    Args:
        pcm_stream: Async iterator of raw PCM16 audio chunks
        sample_rate: Audio sample rate (default 16000)
        source: Optional audio source tag ("system" or "mic")

    Yields:
        Dict events with type "asr_partial", "asr_final", or "diarization_result"
    """
    config = _get_default_config()
    provider = ASRProviderRegistry.get_provider(config=config)
    
    if provider is None or not provider.is_available:
        logger.warning("ASR provider unavailable, using fallback")
        # Fallback: emit a single status event and no transcript pollution
        yield {"type": "status", "state": "no_asr_provider", "message": "ASR provider unavailable"}
        async for _ in pcm_stream:
            pass
        return

    # Convert source string to AudioSource enum
    audio_source: Optional[AudioSource] = None
    if source == "system":
        audio_source = AudioSource.SYSTEM
    elif source == "mic":
        audio_source = AudioSource.MICROPHONE

    logger.debug(f"Using provider '{provider.name}', source={source}")

    diarize = _should_diarize()
    pcm_buffer = bytearray() if diarize else None   # accumulate PCM only when needed
    final_events: List[dict] = []                   # accumulate final segments for diarization

    async for segment in provider.transcribe_stream(pcm_stream, sample_rate, audio_source):
        event_type = "asr_final" if segment.is_final else "asr_partial"
        event = {
            "type": event_type,
            "t0": segment.t0,
            "t1": segment.t1,
            "text": segment.text,
            "stable": segment.is_final,
            "confidence": segment.confidence,
        }
        # Add optional fields if present
        if segment.source:
            event["source"] = segment.source.value
        if segment.language:
            event["language"] = segment.language
        if segment.speaker:
            event["speaker"] = segment.speaker

        yield event

        # Track final segments for post-stream diarization
        if diarize and segment.is_final:
            final_events.append(event)

    # --- Post-stream diarization (F-009) ---
    if diarize and final_events:
        try:
            from .diarization import diarize_pcm, is_diarization_available  # lazy import
            if is_diarization_available() and pcm_buffer:
                logger.info(
                    "Running post-stream diarization on %.1f seconds of audio",
                    len(pcm_buffer) / (sample_rate * 2),
                )
                # diarize_pcm is CPU-bound; run in executor to avoid blocking event loop
                import asyncio
                speaker_segments = await asyncio.to_thread(
                    diarize_pcm, bytes(pcm_buffer), sample_rate
                )
                annotated = _resolve_speakers(final_events, speaker_segments)
                yield {
                    "type": "diarization_result",
                    "segments": annotated,
                    "speaker_count": len({s["speaker"] for s in speaker_segments}),
                }
                logger.info(
                    "Diarization complete: %d speaker(s), %d segments annotated",
                    len({s["speaker"] for s in speaker_segments}),
                    len(annotated),
                )
            else:
                if not is_diarization_available():
                    logger.debug(
                        "Diarization requested but unavailable "
                        "(missing pyannote.audio or ECHOPANEL_HF_TOKEN)"
                    )
        except Exception as exc:
            logger.error("Post-stream diarization failed: %s", exc)
