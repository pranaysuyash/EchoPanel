import pytest

from server.services import diarization


@pytest.mark.asyncio
async def test_prewarm_skips_when_unavailable(monkeypatch):
    monkeypatch.setattr(diarization, "is_diarization_available", lambda: False)

    called = False

    def _fake_get_pipeline():
        nonlocal called
        called = True
        return object()

    monkeypatch.setattr(diarization, "_get_pipeline", _fake_get_pipeline)
    ready = await diarization.prewarm_diarization_pipeline(timeout_seconds=0.05)

    assert ready is False
    assert called is False


@pytest.mark.asyncio
async def test_prewarm_returns_true_when_pipeline_loads(monkeypatch):
    monkeypatch.setattr(diarization, "is_diarization_available", lambda: True)
    monkeypatch.setattr(diarization, "_get_pipeline", lambda: object())

    ready = await diarization.prewarm_diarization_pipeline(timeout_seconds=0.2)
    assert ready is True


@pytest.mark.asyncio
async def test_prewarm_times_out(monkeypatch):
    monkeypatch.setattr(diarization, "is_diarization_available", lambda: True)

    def _slow_get_pipeline():
        import time

        time.sleep(0.1)
        return object()

    monkeypatch.setattr(diarization, "_get_pipeline", _slow_get_pipeline)

    ready = await diarization.prewarm_diarization_pipeline(timeout_seconds=0.01)
    assert ready is False
