from __future__ import annotations

import os
from typing import Any, Optional

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


def _get_pipeline() -> Optional["Pipeline"]:
    global _PIPELINE
    if Pipeline is None:
        return None
    if _PIPELINE is None:
        token = os.getenv("ECHOPANEL_HF_TOKEN")
        if not token:
            return None
        _PIPELINE = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", use_auth_token=token)
        if torch is not None and torch.backends.mps.is_available():
            _PIPELINE.to(torch.device("mps"))
    return _PIPELINE


def diarize_pcm(pcm_bytes: bytes, sample_rate: int = 16000) -> list[dict[str, Any]]:
    """
    Run speaker diarization on PCM16 mono audio. Requires pyannote + torch + numpy.
    Returns a list of segments with t0, t1, and speaker label.
    """
    if np is None or torch is None:
        return []
    pipeline = _get_pipeline()
    if pipeline is None:
        return []

    audio = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
    waveform = torch.from_numpy(audio).unsqueeze(0)
    diarization = pipeline({"waveform": waveform, "sample_rate": sample_rate})

    segments: list[dict[str, Any]] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        segments.append({"t0": float(turn.start), "t1": float(turn.end), "speaker": str(speaker)})
    return segments
