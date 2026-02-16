import base64

from fastapi.testclient import TestClient

from server.main import app


def test_asr_final_includes_segment_id(monkeypatch):
    """
    Offline canonical merge groundwork:
    ensure realtime ASR final events include a deterministic segment_id.
    """
    from server.api import ws_live_listener as ws_module
    from server.services.transcript_ids import generate_segment_id

    async def fake_stream_asr(_pcm_stream, sample_rate=16000, source=None):
        yield {
            "type": "asr_final",
            "text": "Hello world",
            "t0": 1.0,
            "t1": 2.0,
            "confidence": 0.9,
            "source": source or "mic",
        }

    monkeypatch.setattr(ws_module, "stream_asr", fake_stream_asr)
    monkeypatch.setenv("ECHOPANEL_DIARIZATION", "0")

    client = TestClient(app)
    with client.websocket_connect("/ws/live-listener") as websocket:
        websocket.receive_json()  # connected
        websocket.send_json({"type": "start", "session_id": "test_seg_id", "attempt_id": "attempt-1"})
        websocket.receive_json()  # streaming

        silent_frame = bytes(640)
        websocket.send_json(
            {
                "type": "audio",
                "source": "mic",
                "data": base64.b64encode(silent_frame).decode("utf-8"),
            }
        )

        msg = websocket.receive_json()
        assert msg["type"] == "asr_final"
        assert "segment_id" in msg
        assert msg["attempt_id"] == "attempt-1"
        assert msg["segment_id"] == generate_segment_id("mic", 1.0, 2.0, "Hello world")

        websocket.send_json({"type": "stop", "session_id": "test_seg_id"})
        # Drain until final_summary (ensures graceful shutdown)
        for _ in range(12):
            if websocket.receive_json().get("type") == "final_summary":
                break
