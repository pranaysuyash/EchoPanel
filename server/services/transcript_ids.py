"""
Transcript segment ID helpers.

These IDs are intended to be stable across reprocessing so offline canonical
transcript generation can map back to earlier realtime artifacts.
"""

from __future__ import annotations

import hashlib
import re
from typing import Optional


_WS_RE = re.compile(r"\s+")


def normalize_segment_text(text: str) -> str:
    # Keep this intentionally simple and deterministic:
    # - trim
    # - lowercase
    # - collapse whitespace
    return _WS_RE.sub(" ", (text or "").strip().lower())


def generate_segment_id(source: Optional[str], t0: float, t1: float, text: str) -> str:
    """
    Content-addressable segment ID for stability across reprocessing.

    Scheme:
      sha256(f"{source}|{t0:.3f}|{t1:.3f}|{normalized_text}") truncated to 16 bytes.
    """
    src = (source or "system").strip().lower() or "system"
    normalized_text = normalize_segment_text(text)
    content = f"{src}|{t0:.3f}|{t1:.3f}|{normalized_text}"
    digest = hashlib.sha256(content.encode("utf-8")).digest()
    return f"seg_{digest[:16].hex()}"

