from __future__ import annotations

from collections.abc import AsyncIterator


async def stream_asr(pcm_stream: AsyncIterator[bytes]) -> AsyncIterator[dict]:
    """
    Placeholder for streaming ASR integration.

    Yields ASR events:
    - {"type":"asr_partial", ...}
    - {"type":"asr_final", ...}
    """

    async for _chunk in pcm_stream:
        # TODO(v0.1): Feed bytes to ASR engine and yield partial/final events.
        if False:
            yield {}

