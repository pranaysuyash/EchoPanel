from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse
import json
import uuid

app = FastAPI()

@app.get("/")
async def health_check() -> dict:
    return {"status": "ok"}

@app.websocket("/ws/live-listener")
async def ws_live_listener(websocket: WebSocket) -> None:
    await websocket.accept()
    session_id = str(uuid.uuid4())
    await websocket.send_json({"type": "status", "state": "streaming", "message": "Connected"})

    while True:
        message = await websocket.receive()
        if "text" in message:
            payload = json.loads(message["text"])
            if payload.get("type") == "stop":
                await websocket.send_json(
                    {
                        "type": "final_summary",
                        "markdown": "# Summary\n- Placeholder summary",
                        "json": {"actions": [], "decisions": [], "risks": []},
                    }
                )
                await websocket.close()
                break
        if "bytes" in message:
            _ = message["bytes"]
            await websocket.send_json(
                {
                    "type": "asr_partial",
                    "t0": 0.0,
                    "t1": 1.2,
                    "text": "placeholder transcript",
                    "stable": False,
                    "session_id": session_id,
                }
            )

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
