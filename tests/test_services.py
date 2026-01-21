import pytest

from server.services.analysis_stream import stream_analysis
from server.services.asr_stream import stream_asr


async def _empty_async_iter():
    if False:
        yield None


@pytest.mark.asyncio
async def test_stream_asr_is_async_generator() -> None:
    results = []
    async for item in stream_asr(_empty_async_iter()):
        results.append(item)
    assert results == []


@pytest.mark.asyncio
async def test_stream_analysis_is_async_generator() -> None:
    results = []
    async for item in stream_analysis(_empty_async_iter()):
        results.append(item)
    assert results == []

