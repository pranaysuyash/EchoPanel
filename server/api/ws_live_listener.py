import asyncio
import base64
import json
import logging
import os
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator, Dict, Optional, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from server.services.analysis_stream import extract_cards, extract_entities, generate_rolling_summary
from server.services.asr_stream import stream_asr
from server.services.diarization import diarize_pcm, merge_transcript_with_speakers

router = APIRouter()
logger = logging.getLogger(__name__)
DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"
QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", "48"))
DEBUG_AUDIO_DUMP = os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP", "0") == "1"
DEBUG_AUDIO_DUMP_DIR = Path(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_DIR", "/tmp/echopanel_audio_dump"))


@dataclass
class SessionState:
    session_id: Optional[str] = None
    started: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)  # General tasks (for future use)
    asr_tasks: list[asyncio.Task] = field(default_factory=list)
    analysis_tasks: list[asyncio.Task] = field(default_factory=list)
    transcript: list[dict] = field(default_factory=list)
    pcm_buffer: bytearray = field(default_factory=bytearray)
    diarization_enabled: bool = False
    diarization_max_bytes: int = 0
    bytes_received: int = 0
    active_sources: Set[str] = field(default_factory=set)
    # Map source -> Queue
    queues: Dict[str, asyncio.Queue] = field(default_factory=dict)
    last_log: float = 0.0
    send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    sample_rate: int = 16000
    dropped_frames: int = 0
    started_sources: Set[str] = field(default_factory=set)
    closed: bool = False
    # P1 fix: track if backpressure warning was sent
    backpressure_warned: bool = False
    # P2-13: Audio debug dump file handles
    debug_dump_files: Dict[str, Any] = field(default_factory=dict)


async def ws_send(state: SessionState, websocket: WebSocket, event: dict) -> None:
    """Send event to websocket, safely handling closed connections."""
    if state.closed:
        return
    async with state.send_lock:
        try:
            await websocket.send_text(json.dumps(event))
        except RuntimeError:
            # Connection closed during send
            state.closed = True


def _init_audio_dump(state: SessionState, source: str) -> None:
    """Initialize audio dump file for a source (P2-13)."""
    if not DEBUG_AUDIO_DUMP or source in state.debug_dump_files:
        return
    
    try:
        DEBUG_AUDIO_DUMP_DIR.mkdir(parents=True, exist_ok=True)
        timestamp = int(time.time())
        session_id = state.session_id or "unknown"
        filename = f"{session_id}_{source}_{timestamp}.pcm"
        filepath = DEBUG_AUDIO_DUMP_DIR / filename
        
        file_handle = open(filepath, "wb")
        state.debug_dump_files[source] = file_handle
        logger.info(f"Audio dump enabled for {source}: {filepath}")
    except Exception as e:
        logger.error(f"Failed to initialize audio dump for {source}: {e}")


def _write_audio_dump(state: SessionState, source: str, chunk: bytes) -> None:
    """Write audio chunk to dump file (P2-13)."""
    if not DEBUG_AUDIO_DUMP or source not in state.debug_dump_files:
        return
    
    try:
        state.debug_dump_files[source].write(chunk)
        state.debug_dump_files[source].flush()
    except Exception as e:
        logger.error(f"Failed to write audio dump for {source}: {e}")


def _close_audio_dumps(state: SessionState) -> None:
    """Close all audio dump files (P2-13)."""
    if not DEBUG_AUDIO_DUMP:
        return
    
    for source, file_handle in state.debug_dump_files.items():
        try:
            file_handle.close()
            logger.info(f"Closed audio dump for {source}")
        except Exception as e:
            logger.error(f"Failed to close audio dump for {source}: {e}")
    
    state.debug_dump_files.clear()


def get_queue(state: SessionState, source: str) -> asyncio.Queue:
    if source not in state.queues:
        state.queues[source] = asyncio.Queue(maxsize=QUEUE_MAX)
        state.active_sources.add(source)
    return state.queues[source]


async def put_audio(
    q: asyncio.Queue,
    chunk: bytes,
    state: Optional["SessionState"] = None,
    source: str = "",
    websocket: Optional[WebSocket] = None,
) -> None:
    """Enqueue audio chunk, dropping oldest if queue is full.
    
    P1 fix (BP-1): Now logs drops and can send backpressure warning to client.
    """
    if not chunk:
        return
    try:
        q.put_nowait(chunk)
    except asyncio.QueueFull:
        # Drop oldest to avoid lag spiral
        _ = q.get_nowait()
        q.put_nowait(chunk)
        if state is not None:
            state.dropped_frames = getattr(state, 'dropped_frames', 0) + 1
            # Always log drops (not just DEBUG) for observability
            logger.warning(f"Backpressure: dropped frame for {source}, total={state.dropped_frames}")
            # P1 fix: Send backpressure warning to client (throttled)
            if websocket is not None and not state.backpressure_warned:
                state.backpressure_warned = True
                asyncio.create_task(ws_send(state, websocket, {
                    "type": "status",
                    "state": "backpressure",
                    "message": f"Audio queue full, dropping frames (source={source})",
                    "dropped_frames": state.dropped_frames,
                }))


async def _pcm_stream(queue: asyncio.Queue) -> AsyncIterator[bytes]:
    """Drain audio queue until EOF (None sentinel)."""
    while True:
        chunk = await queue.get()
        if chunk is None:
            return
        yield chunk


async def _asr_loop(websocket: WebSocket, state: SessionState, queue: asyncio.Queue, source: str) -> None:
    logger.debug(f"starting ASR loop for source={source}")
    try:
        async for event in stream_asr(_pcm_stream(queue), sample_rate=state.sample_rate, source=source):
            logger.debug(f"yielding event: {event}")
            await ws_send(state, websocket, event)
            if event.get("type") == "asr_final":
                # Add source if missing (stream_asr does it, but double check)
                if "source" not in event:
                    event["source"] = source
                state.transcript.append(event)
    except Exception as e:
        logger.error(f"error in ASR loop ({source}): {e}")


async def _analysis_loop(websocket: WebSocket, state: SessionState) -> None:
    try:
        while True:
            await asyncio.sleep(12)
            snapshot = list(state.transcript)
            entities = await asyncio.to_thread(extract_entities, snapshot)
            await ws_send(state, websocket, {"type": "entities_update", **entities})

            await asyncio.sleep(28)
            snapshot = list(state.transcript)
            cards = await asyncio.to_thread(extract_cards, snapshot)
            await ws_send(state, websocket, {
                "type": "cards_update",
                "actions": cards.get("actions", []),
                "decisions": cards.get("decisions", []),
                "risks": cards.get("risks", []),
                "window": {"t0": 0.0, "t1": 600.0},
            })
    except asyncio.CancelledError:
        return


@router.websocket("/ws/live-listener")
async def ws_live_listener(websocket: WebSocket) -> None:
    await websocket.accept()
    state = SessionState()
    # No single pcm_queue anymore, dynamic via state.queues

    diarization_enabled = os.getenv("ECHOPANEL_DIARIZATION", "0") == "1"
    diarization_max_seconds = int(os.getenv("ECHOPANEL_DIARIZATION_MAX_SECONDS", "1800"))
    state.diarization_enabled = diarization_enabled
    state.diarization_max_bytes = diarization_max_seconds * 16000 * 2

    await ws_send(state, websocket, {"type": "status", "state": "streaming", "message": "Connected"})
    if DEBUG:
        print("ws_live_listener: connected")

    try:
        while True:
            try:
                message = await websocket.receive()
                if DEBUG:
                    print(f"ws_live_listener: received message: {message}")
            except RuntimeError:
                if DEBUG:
                    print("ws_live_listener: RuntimeError in receive")
                break

            # Handle Text (JSON) Messages
            if "text" in message and message["text"] is not None:
                try:
                    payload: Dict[str, Any] = json.loads(message["text"])
                    msg_type = payload.get("type")
                    if DEBUG:
                        print(f"ws_live_listener: processing message type: {msg_type}")

                    if msg_type == "start":
                        state.session_id = payload.get("session_id")
                        sample_rate = payload.get("sample_rate", 16000)
                        encoding = payload.get("format", "pcm_s16le")
                        channels = payload.get("channels", 1)
                        
                        # Validate format
                        if sample_rate != 16000 or encoding != "pcm_s16le" or channels != 1:
                            await ws_send(state, websocket, {
                                "type": "error",
                                "message": f"Unsupported audio format: {sample_rate}Hz {encoding} {channels}ch. Expected 16000Hz pcm_s16le mono."
                            })
                            await websocket.close()
                            return
                        
                        state.sample_rate = sample_rate
                        state.started = True
                        await ws_send(state, websocket, {"type": "status", "state": "streaming", "message": "Streaming"})
                        if DEBUG:
                            print(f"ws_live_listener: start session_id={state.session_id}")
                        state.analysis_tasks.append(asyncio.create_task(_analysis_loop(websocket, state)))

                    elif msg_type == "audio":
                        # B1 Fix: Handle source-tagged audio frames
                        if DEBUG:
                            print(f"ws_live_listener: received audio, source={payload.get('source', 'system')}, data len={len(payload.get('data', ''))}")
                        if state.started:
                            b64_data = payload.get("data", "")
                            source = payload.get("source", "system")
                            chunk = base64.b64decode(b64_data)
                            
                            q = get_queue(state, source)
                            if source not in state.started_sources:
                                state.started_sources.add(source)
                                # P2-13: Initialize audio dump for new source
                                _init_audio_dump(state, source)
                                if DEBUG:
                                    print(f"ws_live_listener: starting ASR task for source={source}")
                                state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                            
                            # P2-13: Write audio to dump file
                            _write_audio_dump(state, source, chunk)
                            
                            await put_audio(q, chunk, state=state, source=source, websocket=websocket)
                            
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
                        
                        # Wait for ASR to flush finals FIRST (P1-2 fix)
                        # This ensures all transcriptions are in state.transcript
                        # before we run final NLP
                        try:
                            await asyncio.wait_for(
                                asyncio.gather(*state.asr_tasks, return_exceptions=True),
                                timeout=float(os.getenv("ECHOPANEL_ASR_FLUSH_TIMEOUT", "8")),
                            )
                        except asyncio.TimeoutError:
                            # P1 fix (SF-1): Surface timeout as warning to user
                            logger.warning("ASR flush timed out, transcript may be incomplete")
                            await ws_send(state, websocket, {
                                "type": "status",
                                "state": "warning",
                                "message": "ASR processing timed out, some speech may be missing",
                            })
                        
                        # THEN stop analysis tasks
                        for t in state.analysis_tasks:
                            t.cancel()
                        await asyncio.gather(*state.analysis_tasks, return_exceptions=True)
                        
                        # Run diarization if enabled (disabled for now due to multi-source issues)
                        diarization_segments: list[dict] = []
                        # if state.diarization_enabled and state.pcm_buffer:
                        #     diarization_segments = await asyncio.to_thread(
                        #         diarize_pcm, bytes(state.pcm_buffer), 16000
                        #     )
                        
                        # Snapshot transcript once for deterministic finalization
                        # (prevents race if any late events append during to_thread calls)
                        # P1 fix (TO-1): Sort by timestamp for deterministic ordering across sources
                        transcript_snapshot = sorted(state.transcript, key=lambda s: s.get("t0", 0.0))
                        
                        # Merge transcript with speaker labels (run off event loop if non-trivial)
                        labeled_transcript = await asyncio.to_thread(
                            merge_transcript_with_speakers, transcript_snapshot, diarization_segments
                        )
                        
                        # Generate rolling summary as markdown (run off event loop)
                        summary_md = await asyncio.to_thread(generate_rolling_summary, transcript_snapshot)
                        
                        # Extract final cards and entities (run off event loop)
                        cards = await asyncio.to_thread(extract_cards, transcript_snapshot)
                        entities = await asyncio.to_thread(extract_entities, transcript_snapshot)
                        
                        await ws_send(
                            state,
                            websocket,
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
                        await websocket.close()
                        return

                except json.JSONDecodeError:
                    if DEBUG:
                        print("ws_live_listener: invalid JSON in text message")

            # Handle Binary Messages (Legacy/Fallback)
            if "bytes" in message and message["bytes"] is not None and state.started:
                chunk = message["bytes"]
                source = "system" # Default for binary
                
                q = get_queue(state, source)
                if source not in state.started_sources:
                    state.started_sources.add(source)
                    if DEBUG:
                        print(f"ws_live_listener: starting ASR task for source={source}")
                    state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                
                await put_audio(q, chunk, state=state, source=source, websocket=websocket)
                
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
        # P2-13: Close audio dump files
        _close_audio_dumps(state)
        
        for q in state.queues.values():
            await q.put(None)
        all_tasks = state.tasks + state.asr_tasks + state.analysis_tasks
        for task in all_tasks:
            task.cancel()
        await asyncio.gather(*all_tasks, return_exceptions=True)
        # Log session metrics for observability
        if state.dropped_frames > 0:
            logger.info(f"Session {state.session_id} complete: dropped_frames={state.dropped_frames}")
