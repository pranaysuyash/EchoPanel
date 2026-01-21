from dataclasses import dataclass
from typing import AsyncIterator


@dataclass
class ASRPartial:
    t0: float
    t1: float
    text: str
    stable: bool = False


@dataclass
class ASRFinal:
    t0: float
    t1: float
    text: str
    stable: bool = True


async def stream_asr(pcm_stream: AsyncIterator[bytes]) -> AsyncIterator[ASRPartial | ASRFinal]:
    """
    TODO: Hook into antigravity streaming ASR engine.
    """
    async for _chunk in pcm_stream:
        continue
