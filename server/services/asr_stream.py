from dataclasses import dataclass
from typing import Iterator

@dataclass
class AsrPartial:
    text: str
    t0: float
    t1: float
    stable: bool
    confidence: float

class AsrStreamService:
    """Placeholder streaming ASR service."""

    def stream(self, pcm_frames: Iterator[bytes]) -> Iterator[AsrPartial]:
        for _frame in pcm_frames:
            yield AsrPartial(text="", t0=0.0, t1=0.0, stable=False, confidence=0.0)
