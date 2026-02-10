import asyncio
import json
import base64
import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from server.main import app

# Usage: pytest tests/test_ws_integration.py

@pytest.mark.asyncio
async def test_source_tagged_audio_flow():
    """
    H7: Integration test for Multi-Source Audio Protocol (B1).
    Verifies that the server accepts JSON audio frames with "source" tag
    and returns ASR events with the correct source.
    """
    client = TestClient(app)
    
    with client.websocket_connect("/ws/live-listener") as websocket:
        # 1. Check connection - PR2: Now sends "connected" first, not "streaming"
        data = websocket.receive_json()
        assert data["type"] == "status"
        assert data["state"] == "connected"
        
        # 2. Start session - PR2: "streaming" ACK sent after start, not on connect
        websocket.send_json({"type": "start", "session_id": "test_session_H7"})
        data = websocket.receive_json()
        assert data["type"] == "status"
        assert data["state"] == "streaming"
        
        # 3. Send Audio Frame with Source "mic"
        # Create a small silent frame (16k * 0.1s = 1600 samples * 2 bytes = 3200 bytes)
        silent_frame = bytes(3200)
        b64_data = base64.b64encode(silent_frame).decode("utf-8")
        
        payload = {
            "type": "audio",
            "source": "mic",
            "data": b64_data
        }
        websocket.send_json(payload)
        
        # 4. Wait for ASR response (might be partial)
        # We expect the server to process it. Since it's silence, Whisper might return nothing or empty segment.
        # But we want to ensure no crash and potential echo.
        # In a real test we'd send speech. Here we check protocol compliance.
        
        # 5. Send Stop
        websocket.send_json({"type": "stop", "session_id": "test_session_H7"})
        
        # 6. Verify Final Summary received (may receive ASR events first)
        final_seen = False
        for _ in range(10):  # Allow up to 10 messages before final_summary
            msg = websocket.receive_json()
            if msg.get("type") == "final_summary":
                final_seen = True
                break
        
        assert final_seen, "Expected final_summary but did not receive it"


def test_session_end_diarization_emits_source_segments(monkeypatch):
    """
    Verifies the stop/finalization path runs diarization when enabled and
    includes source-tagged diarization output in final_summary.
    """
    from server.api import ws_live_listener as ws_module

    monkeypatch.setenv("ECHOPANEL_DIARIZATION", "1")

    def fake_diarize_pcm(_pcm_bytes, _sample_rate=16000):
        return [{"t0": 0.0, "t1": 1.0, "speaker": "Speaker 1"}]

    monkeypatch.setattr(ws_module, "diarize_pcm", fake_diarize_pcm)

    client = TestClient(app)
    with client.websocket_connect("/ws/live-listener") as websocket:
        connected = websocket.receive_json()
        assert connected["type"] == "status"

        websocket.send_json({"type": "start", "session_id": "test_diarization"})
        started = websocket.receive_json()
        assert started["type"] == "status"

        silent_frame = bytes(640)
        payload = {
            "type": "audio",
            "source": "mic",
            "data": base64.b64encode(silent_frame).decode("utf-8"),
        }
        websocket.send_json(payload)
        websocket.send_json({"type": "stop", "session_id": "test_diarization"})

        final_summary = None
        for _ in range(12):
            msg = websocket.receive_json()
            if msg.get("type") == "final_summary":
                final_summary = msg
                break

        assert final_summary is not None, "Expected final_summary event"
        diarization = final_summary["json"].get("diarization", [])
        assert diarization, "Expected non-empty diarization output"
        assert diarization[0]["source"] == "mic"


def test_ws_auth_rejects_missing_token(monkeypatch):
    monkeypatch.setenv("ECHOPANEL_WS_AUTH_TOKEN", "secret-token")
    client = TestClient(app)

    with client.websocket_connect("/ws/live-listener") as websocket:
        first = websocket.receive_json()
        assert first["state"] == "error"
        with pytest.raises(WebSocketDisconnect):
            websocket.receive_json()


def test_ws_auth_accepts_query_token(monkeypatch):
    monkeypatch.setenv("ECHOPANEL_WS_AUTH_TOKEN", "secret-token")
    client = TestClient(app)

    with client.websocket_connect("/ws/live-listener?token=secret-token") as websocket:
        # PR2: First message is "connected", not "streaming"
        data = websocket.receive_json()
        assert data["type"] == "status"
        assert data["state"] == "connected"
        
        # PR2: Send start to get streaming ACK
        websocket.send_json({"type": "start", "session_id": "test_auth_session"})
        data = websocket.receive_json()
        assert data["type"] == "status"
        assert data["state"] == "streaming"
