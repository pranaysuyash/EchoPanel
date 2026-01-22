import asyncio
import base64
import json
import os
import time
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from server.services.analysis_stream import extract_cards, extract_entities, generate_rolling_summary
from server.services.asr_stream import stream_asr
from server.services.diarization import diarize_pcm, merge_transcript_with_speakers

router = APIRouter()
DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"


@dataclass
class SessionState:
    session_id: Optional[str] = None
    started: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)
    transcript: list[dict] = field(default_factory=list)
    pcm_buffer: bytearray = field(default_factory=bytearray)
    diarization_enabled: bool = False
    diarization_max_bytes: int = 0
    bytes_received: int = 0
    active_sources: Set[str] = field(default_factory=set)
    # Map source -> Queue
    queues: Dict[str, asyncio.Queue] = field(default_factory=dict)
    last_log: float = 0.0


async def _pcm_stream(queue: asyncio.Queue[Optional[bytes]]):
    while True:
        chunk = await queue.get()
        if chunk is None:
            break
        yield chunk


async def _asr_loop(websocket: WebSocket, state: SessionState, queue: asyncio.Queue, source: str) -> None:
    if DEBUG:
        print(f"ws_live_listener: starting ASR loop for source={source}")
    try:
        async for event in stream_asr(_pcm_stream(queue), source=source):
            await websocket.send_text(json.dumps(event))
            if event.get("type") == "asr_final":
                # Add source if missing (stream_asr does it, but double check)
                if "source" not in event:
                    event["source"] = source
                state.transcript.append(event)
    except Exception as e:
        if DEBUG:
            print(f"ws_live_listener: error in ASR loop ({source}): {e}")


async def _analysis_loop(websocket: WebSocket, state: SessionState) -> None:
    while True:
        await asyncio.sleep(12)
        entities = extract_entities(state.transcript)
        await websocket.send_text(json.dumps({"type": "entities_update", **entities}))

        await asyncio.sleep(28)
        cards = extract_cards(state.transcript)
        await websocket.send_text(
            json.dumps(
                {
                    "type": "cards_update",
                    "actions": cards["actions"],
                    "decisions": cards["decisions"],
                    "risks": cards["risks"],
                    "window": {"t0": 0.0, "t1": 600.0},
                }
            )
        )


@router.websocket("/ws/live-listener")
async def ws_live_listener(websocket: WebSocket) -> None:
    await websocket.accept()
    state = SessionState()
    # No single pcm_queue anymore, dynamic via state.queues

    diarization_enabled = os.getenv("ECHOPANEL_DIARIZATION", "0") == "1"
    diarization_max_seconds = int(os.getenv("ECHOPANEL_DIARIZATION_MAX_SECONDS", "1800"))
    state.diarization_enabled = diarization_enabled
    state.diarization_max_bytes = diarization_max_seconds * 16000 * 2

    await websocket.send_text(json.dumps({"type": "status", "state": "streaming", "message": "Connected"}))
    if DEBUG:
        print("ws_live_listener: connected")

    try:
        while True:
            try:
                message = await websocket.receive()
            except RuntimeError:
                break

            # Handle Text (JSON) Messages
            if "text" in message and message["text"] is not None:
                payload: Dict[str, Any] = json.loads(message["text"])
                msg_type = payload.get("type")

                if msg_type == "start":
                    state.session_id = payload.get("session_id")
                    state.started = True
                    await websocket.send_text(json.dumps({"type": "status", "state": "streaming", "message": "Streaming"}))
                    if DEBUG:
                        print(f"ws_live_listener: start session_id={state.session_id}")
                    state.tasks.append(asyncio.create_task(_analysis_loop(websocket, state)))

                elif msg_type == "audio":
                    # B1 Fix: Handle source-tagged audio frames
                    if state.started:
                        b64_data = payload.get("data", "")
                        source = payload.get("source", "system")
                        chunk = base64.b64decode(b64_data)
                        
                        if source not in state.queues:
                            state.queues[source] = asyncio.Queue()
                            state.active_sources.add(source)
                            state.tasks.append(asyncio.create_task(_asr_loop(websocket, state, state.queues[source], source)))
                        
                        await state.queues[source].put(chunk)
                        
                        if state.diarization_enabled:
                            state.pcm_buffer.extend(chunk)
                            if state.diarization_max_bytes > 0 and len(state.pcm_buffer) > state.diarization_max_bytes:
                                overflow = len(state.pcm_buffer) - state.diarization_max_bytes
                                if overflow > 0:
                                    del state.pcm_buffer[:overflow]

                elif msg_type == "stop":
                    # Signal EOF to all queues
                    for q in state.queues.values():
                        await q.put(None)
                        
                    if DEBUG:
                        print("ws_live_listener: stop")
                    
                    # Run diarization if enabled
                    diarization_segments = []
                    if state.diarization_enabled and state.pcm_buffer:
                        diarization_segments = await asyncio.to_thread(
                            diarize_pcm, bytes(state.pcm_buffer), 16000
                        )
                    
                    # Merge transcript with speaker labels
                    labeled_transcript = merge_transcript_with_speakers(
                        state.transcript, diarization_segments
                    )
                    
                    # Generate rolling summary as markdown
                    summary_md = generate_rolling_summary(state.transcript)
                    
                    # Extract final cards and entities
                    cards = extract_cards(state.transcript)
                    entities = extract_entities(state.transcript)
                    
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "final_summary",
                                "markdown": summary_md,
                                "json": {
                                    "session_id": state.session_id or payload.get("session_id"),
                                    "transcript": labeled_transcript,
                                    "actions": cards["actions"],
                                    "decisions": cards["decisions"],
                                    "risks": cards["risks"],
                                    "entities": entities,
                                    "diarization": diarization_segments, # H8 Fix: Include raw diarization
                                },
                            }
                        )
                    )
                    await websocket.close()
                    return

            # Handle Binary Messages (Legacy/Fallback)
            if "bytes" in message and message["bytes"] is not None and state.started:
                chunk = message["bytes"]
                source = "system" # Default for binary
                
                if source not in state.queues:
                    state.queues[source] = asyncio.Queue()
                    state.active_sources.add(source)
                    state.tasks.append(asyncio.create_task(_asr_loop(websocket, state, state.queues[source], source)))
                
                await state.queues[source].put(chunk)
                
                if state.diarization_enabled:
                    state.pcm_buffer.extend(chunk)
                    if state.diarization_max_bytes > 0 and len(state.pcm_buffer) > state.diarization_max_bytes:
                        overflow = len(state.pcm_buffer) - state.diarization_max_bytes
                        if overflow > 0:
                            del state.pcm_buffer[:overflow]
                
                if DEBUG:
                    state.bytes_received += len(chunk)
                    now = time.time()
                    if now - state.last_log > 2:
                        state.last_log = now
                        print(f"ws_live_listener: received {state.bytes_received} bytes (binary)")

    except WebSocketDisconnect:
        if DEBUG:
            print("ws_live_listener: disconnect")
        return
    finally:
        for q in state.queues.values():
            await q.put(None)
        for task in state.tasks:
            task.cancel()
        await asyncio.gather(*state.tasks, return_exceptions=True)
