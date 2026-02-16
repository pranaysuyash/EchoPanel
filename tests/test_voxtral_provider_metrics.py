import time


class _StubProcess:
    returncode = None


def test_voxtral_streaming_session_realtime_factor_uses_configured_chunk_seconds():
    # Import locally to keep the test tight and avoid side effects at import time.
    from server.services.provider_voxtral_realtime import StreamingSession

    session = StreamingSession(
        process=_StubProcess(),  # type: ignore[arg-type]
        started_at=time.perf_counter(),
        chunk_seconds=2.0,
        chunks_processed=10,
        total_infer_ms=2000.0,  # 200ms average inference per chunk
    )

    # avg_infer_s = 0.2; chunk_seconds = 2.0 => rtf = 0.1
    assert abs(session.realtime_factor - 0.1) < 1e-9

