import asyncio

import pytest

from server.api.ws_live_listener import put_audio
from server.services.concurrency_controller import get_concurrency_controller, reset_concurrency_controller


@pytest.mark.asyncio
async def test_put_audio_does_not_fill_concurrency_controller_queues():
    """
    Regression test:
    `put_audio()` must reflect the actual ingest queue used by `_asr_loop()`.
    A previous integration attempt enqueued into ConcurrencyController queues
    that were never drained, causing false sustained overload and source drops.
    """
    reset_concurrency_controller()
    controller = get_concurrency_controller()

    q = asyncio.Queue(maxsize=48)
    chunk = b"\x00\x00" * 320  # ~20ms PCM16 @ 16kHz (small but non-empty)

    for _ in range(300):
        await put_audio(q, chunk, state=None, source="system", websocket=None)

    metrics = controller.get_metrics()
    assert metrics.queue_depths.get("system", 0) == 0
    assert metrics.queue_depths.get("mic", 0) == 0

