"""
ASR Streaming Pipeline (v0.2)

Provides the high-level streaming ASR interface using the provider abstraction.
This file is the main entry point for the WebSocket handler.
"""

from __future__ import annotations

import logging
import os
from typing import AsyncIterator, Optional

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource

# Import providers to trigger registration
from . import provider_faster_whisper  # noqa: F401
from . import provider_voxtral_realtime  # noqa: F401
from . import provider_whisper_cpp  # noqa: F401

logger = logging.getLogger(__name__)


def _get_default_config() -> ASRConfig:
    """Build ASRConfig from environment variables."""
    return ASRConfig(
        model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en"),
        device=os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto"),
        compute_type=os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8"),
        language=os.getenv("ECHOPANEL_WHISPER_LANGUAGE", "en"),  # Default to English
        chunk_seconds=int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2")),  # PR3: Reduced from 4s
        vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "0") == "1",  # Default OFF for now
    )


async def stream_asr(
    pcm_stream: AsyncIterator[bytes],
    sample_rate: int = 16000,
    source: Optional[str] = None,
) -> AsyncIterator[dict]:
    """
    Streaming ASR pipeline using the registered provider.

    Converts ASRSegment objects to the dict format expected by the WebSocket handler.
    
    Args:
        pcm_stream: Async iterator of raw PCM16 audio chunks
        sample_rate: Audio sample rate (default 16000)
        source: Optional audio source tag ("system" or "mic")
    
    Yields:
        Dict events with type "asr_partial" or "asr_final"
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
