from __future__ import annotations

from collections.abc import AsyncIterator


async def stream_analysis(_transcript_events: AsyncIterator[dict]) -> AsyncIterator[dict]:
    """
    Placeholder for periodic analysis integration.

    Yields:
    - {"type":"entities_update", ...}
    - {"type":"cards_update", ...}
    """

    async for _event in _transcript_events:
        # TODO(v0.1): Aggregate transcript and periodically yield updates.
        if False:
            yield {}

