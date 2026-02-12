"""
Speaker Diarization (v0.2)

Provides batch speaker diarization at session end using pyannote.audio.
Segments are merged by speaker for cleaner output.
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from typing import Any, List, Optional

logger = logging.getLogger(__name__)

try:
    import numpy as np
except Exception:  # pragma: no cover - optional dependency
    np = None

try:
    import torch
except Exception:  # pragma: no cover - optional dependency
    torch = None

try:
    from pyannote.audio import Pipeline
except Exception:  # pragma: no cover - optional dependency
    Pipeline = None

_PIPELINE: Optional["Pipeline"] = None


@dataclass
class SpeakerSegment:
    """A diarization segment with speaker label."""
    t0: float
    t1: float
    speaker: str


def is_diarization_available() -> bool:
    """Check if diarization dependencies are available."""
    if np is None or torch is None or Pipeline is None:
        return False
    token = os.getenv("ECHOPANEL_HF_TOKEN")
    return bool(token)


async def prewarm_diarization_pipeline(timeout_seconds: float = 120.0) -> bool:
    """
    Preload the diarization pipeline so first real usage has lower latency.

    Returns:
        True when pipeline is loaded and resident, False otherwise.
    """
    if not is_diarization_available():
        logger.info("Skipping diarization prewarm: dependencies or token unavailable")
        return False

    try:
        pipeline = await asyncio.wait_for(asyncio.to_thread(_get_pipeline), timeout=timeout_seconds)
    except asyncio.TimeoutError:
        logger.warning("Diarization prewarm timed out after %.1fs", timeout_seconds)
        return False
    except Exception as exc:  # pragma: no cover - defensive guard
        logger.error("Diarization prewarm failed: %s", exc)
        return False

    if pipeline is None:
        logger.warning("Diarization prewarm finished without a pipeline instance")
        return False

    logger.info("Diarization pipeline prewarmed successfully")
    return True


def _get_pipeline() -> Optional["Pipeline"]:
    global _PIPELINE
    if Pipeline is None:
        return None
    if _PIPELINE is None:
        token = os.getenv("ECHOPANEL_HF_TOKEN")
        if not token:
            logger.debug("ECHOPANEL_HF_TOKEN not set, diarization unavailable")
            return None
        
        logger.debug("Loading pyannote/speaker-diarization-3.1...")
        
        try:
            _PIPELINE = Pipeline.from_pretrained(
                "pyannote/speaker-diarization-3.1",
                use_auth_token=token
            )
            # Use MPS on Apple Silicon if available
            if torch is not None and torch.backends.mps.is_available():
                _PIPELINE.to(torch.device("mps"))
                logger.debug("Diarization using MPS device")
            elif torch is not None and torch.cuda.is_available():
                _PIPELINE.to(torch.device("cuda"))
                logger.debug("Diarization using CUDA device")
            else:
                logger.debug("Diarization using CPU device")
        except Exception as e:
            logger.error(f"Failed to load diarization pipeline: {e}")
            return None
    
    return _PIPELINE


def _merge_adjacent_segments(segments: List[SpeakerSegment], gap_threshold: float = 0.5) -> List[SpeakerSegment]:
    """
    Merge adjacent segments from the same speaker.
    
    Args:
        segments: List of speaker segments
        gap_threshold: Maximum gap (seconds) to merge across
    
    Returns:
        Merged segments
    """
    if not segments:
        return []
    
    # Sort by start time
    sorted_segments = sorted(segments, key=lambda s: s.t0)
    merged = [sorted_segments[0]]
    
    for seg in sorted_segments[1:]:
        last = merged[-1]
        # Merge if same speaker and gap is small enough
        if seg.speaker == last.speaker and (seg.t0 - last.t1) <= gap_threshold:
            merged[-1] = SpeakerSegment(
                t0=last.t0,
                t1=max(last.t1, seg.t1),
                speaker=last.speaker
            )
        else:
            merged.append(seg)
    
    return merged


def _assign_speaker_names(segments: List[SpeakerSegment]) -> List[SpeakerSegment]:
    """
    Convert speaker IDs (SPEAKER_00, SPEAKER_01) to friendly names.
    """
    speaker_order = {}
    speaker_count = 0
    
    for seg in sorted(segments, key=lambda s: s.t0):
        if seg.speaker not in speaker_order:
            speaker_count += 1
            speaker_order[seg.speaker] = f"Speaker {speaker_count}"
    
    return [
        SpeakerSegment(t0=seg.t0, t1=seg.t1, speaker=speaker_order.get(seg.speaker, seg.speaker))
        for seg in segments
    ]


def diarize_pcm(pcm_bytes: bytes, sample_rate: int = 16000) -> List[dict[str, Any]]:
    """
    Run speaker diarization on PCM16 mono audio.
    
    Requires pyannote.audio + torch + numpy + HuggingFace token.
    Returns a list of segments with t0, t1, and speaker label.
    """
    if np is None or torch is None:
        logger.debug("numpy or torch not available, skipping diarization")
        return []
    
    pipeline = _get_pipeline()
    if pipeline is None:
        return []

    logger.debug(f"Processing {len(pcm_bytes)} bytes for diarization")

    try:
        audio = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        waveform = torch.from_numpy(audio).unsqueeze(0)
        
        diarization = pipeline({"waveform": waveform, "sample_rate": sample_rate})

        segments: List[SpeakerSegment] = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append(SpeakerSegment(
                t0=float(turn.start),
                t1=float(turn.end),
                speaker=str(speaker)
            ))
        
        logger.debug(f"Diarization found {len(segments)} raw segments")
        
        # Merge adjacent segments from same speaker
        merged = _merge_adjacent_segments(segments)
        
        # Assign friendly speaker names
        named = _assign_speaker_names(merged)
        
        logger.debug(f"Diarization produced {len(named)} segments after merging")
        
        return [{"t0": s.t0, "t1": s.t1, "speaker": s.speaker} for s in named]
    
    except Exception as e:
        logger.error(f"Error during diarization processing: {e}")
        return []


def merge_transcript_with_speakers(
    transcript: List[dict],
    speaker_segments: List[dict]
) -> List[dict]:
    """
    Merge transcript segments with speaker labels based on time overlap.
    
    Each transcript segment gets a 'speaker' field based on which speaker
    segment it overlaps most with.
    """
    if not speaker_segments:
        return transcript
    
    result = []
    for seg in transcript:
        t0 = seg.get("t0", 0.0)
        t1 = seg.get("t1", 0.0)
        mid = (t0 + t1) / 2.0
        
        # Find the speaker segment that contains the midpoint
        speaker = None
        for spk_seg in speaker_segments:
            if spk_seg["t0"] <= mid <= spk_seg["t1"]:
                speaker = spk_seg["speaker"]
                break
        
        merged = dict(seg)
        if speaker:
            merged["speaker"] = speaker
        result.append(merged)
    
    return result
