import asyncio
import json
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()


@dataclass
class SessionState:
    session_id: Optional[str] = None
    started: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)


async def _send_periodic_entities(websocket: WebSocket) -> None:
    while True:
        await asyncio.sleep(12)
        await websocket.send_text(
            json.dumps(
                {
                    "type": "entities_update",
                    "people": [{"name": "Alex", "last_seen": 12.0, "confidence": 0.77}],
                    "orgs": [{"name": "EchoPanel", "last_seen": 12.0, "confidence": 0.88}],
                    "dates": [{"name": "Friday", "last_seen": 12.0, "confidence": 0.71}],
                    "projects": [{"name": "v0.1", "last_seen": 12.0, "confidence": 0.69}],
                    "topics": [{"name": "ScreenCaptureKit", "last_seen": 12.0, "confidence": 0.74}],
                }
            )
        )


async def _send_periodic_cards(websocket: WebSocket) -> None:
    while True:
        await asyncio.sleep(40)
        await websocket.send_text(
            json.dumps(
                {
                    "type": "cards_update",
                    "actions": [
                        {
                            "text": "Send revised proposal",
                            "owner": "Pranay",
                            "due": "2026-01-23",
                            "confidence": 0.82,
                            "evidence": [{"t0": 0.0, "t1": 1.2, "quote": "I'll send the revised proposal by Tuesday."}],
                        }
                    ],
                    "decisions": [
                        {
                            "text": "Ship v0.1 on Friday",
                            "confidence": 0.74,
                            "evidence": [{"t0": 0.0, "t1": 1.2, "quote": "We should ship by Friday."}],
                        }
                    ],
                    "risks": [
                        {
                            "text": "Backend unavailable during peak hours",
                            "confidence": 0.61,
                            "evidence": [{"t0": 0.0, "t1": 1.2, "quote": "We might have outages."}],
                        }
                    ],
                    "window": {"t0": 0.0, "t1": 600.0},
                }
            )
        )


async def _send_demo_asr(websocket: WebSocket) -> None:
    i = 0
    while True:
        await asyncio.sleep(5)
        i += 1
        await websocket.send_text(
            json.dumps(
                {
                    "type": "asr_partial",
                    "t0": float(i * 5),
                    "t1": float(i * 5 + 2),
                    "text": "placeholder transcript",
                    "stable": False,
                    "confidence": 0.6,
                }
            )
        )
        await asyncio.sleep(2)
        await websocket.send_text(
            json.dumps(
                {
                    "type": "asr_final",
                    "t0": float(i * 5),
                    "t1": float(i * 5 + 2),
                    "text": "Placeholder transcript.",
                    "stable": True,
                    "confidence": 0.9,
                }
            )
        )


@router.websocket("/ws/live-listener")
async def ws_live_listener(websocket: WebSocket) -> None:
    await websocket.accept()
    state = SessionState()

    await websocket.send_text(json.dumps({"type": "status", "state": "streaming", "message": "Connected"}))

    try:
        while True:
            message = await websocket.receive()
            if "text" in message and message["text"] is not None:
                payload: Dict[str, Any] = json.loads(message["text"])
                msg_type = payload.get("type")

                if msg_type == "start":
                    state.session_id = payload.get("session_id")
                    state.started = True
                    await websocket.send_text(json.dumps({"type": "status", "state": "streaming", "message": "Streaming"}))

                    state.tasks.append(asyncio.create_task(_send_periodic_entities(websocket)))
                    state.tasks.append(asyncio.create_task(_send_periodic_cards(websocket)))
                    state.tasks.append(asyncio.create_task(_send_demo_asr(websocket)))

                elif msg_type == "stop":
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "final_summary",
                                "markdown": "# Summary\n- Placeholder summary",
                                "json": {
                                    "session_id": state.session_id or payload.get("session_id"),
                                    "actions": [],
                                    "decisions": [],
                                    "risks": [],
                                    "entities": {},
                                },
                            }
                        )
                    )
                    await websocket.close()
                    return

            if "bytes" in message and message["bytes"] is not None:
                # Binary PCM frames (v0.1): accepted, but the stub does not decode audio.
                continue

    except WebSocketDisconnect:
        return
    finally:
        for task in state.tasks:
            task.cancel()
        await asyncio.gather(*state.tasks, return_exceptions=True)

