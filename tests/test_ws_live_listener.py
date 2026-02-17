import asyncio
import json
import os
import threading
import time

import pytest
import uvicorn
import websockets

from server.main import app


class UvicornTestServer:
    def __init__(self, host: str = "127.0.0.1", port: int = 8765) -> None:
        self.host = host
        self.port = port
        self.config = uvicorn.Config(app, host=host, port=port, log_level="warning")
        self.server = uvicorn.Server(self.config)
        self.thread = threading.Thread(target=self.server.run, daemon=True)

    def start(self) -> None:
        self.thread.start()
        # Give the server a moment to begin initialization
        time.sleep(0.1)
        deadline = time.time() + 10
        while time.time() < deadline:
            if self.server.started:
                return
            time.sleep(0.05)
        raise RuntimeError("Uvicorn server did not start in time")

    def stop(self) -> None:
        self.server.should_exit = True
        self.thread.join(timeout=5)


@pytest.mark.asyncio
async def test_ws_live_listener_start_stop(monkeypatch) -> None:
    # Keep this integration test deterministic even if local ASR is installed.
    monkeypatch.setenv("ECHOPANEL_ASR_FLUSH_TIMEOUT", "1")
    monkeypatch.setenv("ECHOPANEL_DIARIZATION", "0")

    server = UvicornTestServer()
    server.start()

    session_id = "test-session"
    url = f"ws://{server.host}:{server.port}/ws/live-listener"

    try:
        async with websockets.connect(url, max_size=2**24) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "start",
                        "session_id": session_id,
                        "sample_rate": 16000,
                        "format": "pcm_s16le",
                        "channels": 1,
                    }
                )
            )

            await ws.send(os.urandom(640))
            await ws.send(json.dumps({"type": "stop", "session_id": session_id}))

            final_seen = False
            for _ in range(8):
                msg = await asyncio.wait_for(ws.recv(), timeout=3)
                payload = json.loads(msg)
                if payload.get("type") == "final_summary":
                    final_seen = True
                    break
            assert final_seen
    finally:
        server.stop()
