import asyncio
import base64
import hmac
import json
import logging
import os
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, AsyncIterator, Dict, Optional, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from server.services.analysis_stream import extract_cards, extract_entities, generate_rolling_summary
from server.services.asr_stream import stream_asr
from server.services.diarization import diarize_pcm, merge_transcript_with_speakers
from server.services.concurrency_controller import (
    get_concurrency_controller,
    BackpressureLevel,
)
from server.services.degrade_ladder import DegradeLadder, DegradeLevel

router = APIRouter()
logger = logging.getLogger(__name__)
DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"
QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", "48"))
DEBUG_AUDIO_DUMP = os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP", "0") == "1"
DEBUG_AUDIO_DUMP_DIR = Path(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_DIR", "/tmp/echopanel_audio_dump"))
DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS = int(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS", "86400"))
DEBUG_AUDIO_DUMP_MAX_FILES = int(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_FILES", "200"))
DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES = int(
    os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES", str(512 * 1024 * 1024))
)
WS_AUTH_TOKEN_ENV = "ECHOPANEL_WS_AUTH_TOKEN"


@dataclass
class SessionState:
    session_id: Optional[str] = None
    attempt_id: Optional[str] = None  # V1: For correlation with client reconnects
    connection_id: Optional[str] = None  # V1: Per-WS connection ID
    started: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)  # General tasks (for future use)
    asr_tasks: list[asyncio.Task] = field(default_factory=list)
    analysis_tasks: list[asyncio.Task] = field(default_factory=list)
    transcript: list[dict] = field(default_factory=list)
    # Source-aware PCM buffers used for session-end diarization.
    pcm_buffers_by_source: Dict[str, bytearray] = field(default_factory=dict)
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
    # PR2: Metrics tracking
    metrics_task: Optional[asyncio.Task] = None
    asr_processing_times: list[float] = field(default_factory=list)  # Track inference times
    asr_last_dropped: int = 0  # For computing dropped_recent
    audio_time_processed: float = 0.0  # Total audio seconds processed
    processing_time_total: float = 0.0  # Total processing time spent
    # V1: Provider info for metrics
    provider_name: str = "unknown"
    model_id: str = "unknown"
    vad_enabled: bool = False
    # TCK-20260211-010: Degrade ladder for adaptive performance
    degrade_ladder: Optional[DegradeLadder] = None


def _normalize_source(source: Optional[str]) -> str:
    raw = (source or "system").strip().lower()
    if raw in {"mic", "microphone"}:
        return "mic"
    if raw == "system":
        return "system"
    return raw or "system"


def _append_diarization_audio(state: SessionState, source: str, chunk: bytes) -> None:
    if not state.diarization_enabled or not chunk:
        return

    source_key = _normalize_source(source)
    pcm_buffer = state.pcm_buffers_by_source.setdefault(source_key, bytearray())
    pcm_buffer.extend(chunk)

    if state.diarization_max_bytes > 0 and len(pcm_buffer) > state.diarization_max_bytes:
        overflow = len(pcm_buffer) - state.diarization_max_bytes
        if overflow > 0:
            del pcm_buffer[:overflow]


async def _run_diarization_per_source(state: SessionState) -> Dict[str, list[dict]]:
    if not state.diarization_enabled:
        return {}

    sources_with_audio = [
        (source, bytes(pcm_buffer))
        for source, pcm_buffer in state.pcm_buffers_by_source.items()
        if pcm_buffer
    ]
    if not sources_with_audio:
        return {}

    async def _run_one(source: str, pcm_bytes: bytes) -> tuple[str, list[dict]]:
        segments = await asyncio.to_thread(diarize_pcm, pcm_bytes, state.sample_rate)
        return source, segments

    results = await asyncio.gather(
        *(_run_one(source, pcm_bytes) for source, pcm_bytes in sources_with_audio),
        return_exceptions=True,
    )

    diarization_by_source: Dict[str, list[dict]] = {}
    for result in results:
        if isinstance(result, Exception):
            logger.error("Diarization failed for a source: %s", result)
            continue
        source, segments = result
        if segments:
            diarization_by_source[source] = segments
    return diarization_by_source


def _merge_transcript_with_source_diarization(
    transcript: list[dict], diarization_by_source: Dict[str, list[dict]]
) -> list[dict]:
    if not diarization_by_source:
        return transcript

    merged_transcript: list[dict] = []
    for seg in transcript:
        source_key = _normalize_source(seg.get("source"))
        speaker_segments = diarization_by_source.get(source_key, [])
        if not speaker_segments:
            merged_transcript.append(dict(seg))
            continue

        labeled = merge_transcript_with_speakers([dict(seg)], speaker_segments)
        merged_transcript.append(labeled[0] if labeled else dict(seg))
    return merged_transcript


def _flatten_diarization_segments(diarization_by_source: Dict[str, list[dict]]) -> list[dict]:
    flattened: list[dict] = []
    for source in sorted(diarization_by_source.keys()):
        for segment in diarization_by_source[source]:
            flattened.append({"source": source, **segment})
    return flattened


def _extract_ws_auth_token(websocket: WebSocket) -> str:
    # Priority: query param -> custom header -> Authorization: Bearer <token>
    query_token = websocket.query_params.get("token")
    if query_token:
        return query_token.strip()

    header_token = websocket.headers.get("x-echopanel-token")
    if header_token:
        return header_token.strip()

    auth_header = websocket.headers.get("authorization", "").strip()
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()
    return ""


def _is_ws_authorized(websocket: WebSocket) -> bool:
    required_token = os.getenv(WS_AUTH_TOKEN_ENV, "").strip()
    if not required_token:
        return True

    provided_token = _extract_ws_auth_token(websocket)
    if not provided_token:
        return False

    return hmac.compare_digest(provided_token, required_token)


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
        _cleanup_audio_dump_dir()
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


def _cleanup_audio_dump_dir(now: Optional[float] = None) -> None:
    """Apply retention limits to debug dump files (age/file-count/total-size)."""
    if not DEBUG_AUDIO_DUMP:
        return

    try:
        DEBUG_AUDIO_DUMP_DIR.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        logger.error(f"Failed to prepare debug dump directory: {e}")
        return

    entries: list[tuple[Path, os.stat_result]] = []
    for path in DEBUG_AUDIO_DUMP_DIR.glob("*.pcm"):
        try:
            entries.append((path, path.stat()))
        except FileNotFoundError:
            continue
        except Exception as e:
            logger.warning(f"Failed to inspect debug dump file {path}: {e}")

    if not entries:
        return

    entries.sort(key=lambda item: item[1].st_mtime)  # oldest first
    cutoff = (now or time.time()) - DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS
    kept_entries: list[tuple[Path, os.stat_result]] = []

    for path, stat_result in entries:
        if DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS > 0 and stat_result.st_mtime < cutoff:
            try:
                path.unlink(missing_ok=True)
                logger.info(f"Removed expired audio dump: {path}")
            except Exception as e:
                logger.warning(f"Failed to remove expired debug dump {path}: {e}")
            continue
        kept_entries.append((path, stat_result))

    if DEBUG_AUDIO_DUMP_MAX_FILES > 0 and len(kept_entries) > DEBUG_AUDIO_DUMP_MAX_FILES:
        over_limit = len(kept_entries) - DEBUG_AUDIO_DUMP_MAX_FILES
        for path, _ in kept_entries[:over_limit]:
            try:
                path.unlink(missing_ok=True)
                logger.info(f"Removed excess audio dump: {path}")
            except Exception as e:
                logger.warning(f"Failed to remove excess debug dump {path}: {e}")
        kept_entries = kept_entries[over_limit:]

    if DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES > 0:
        total_bytes = sum(stat_result.st_size for _, stat_result in kept_entries)
        if total_bytes > DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES:
            for path, stat_result in kept_entries:
                if total_bytes <= DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES:
                    break
                try:
                    path.unlink(missing_ok=True)
                    total_bytes -= stat_result.st_size
                    logger.info(f"Removed oversized audio dump: {path}")
                except Exception as e:
                    logger.warning(f"Failed to remove oversized debug dump {path}: {e}")


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
    """Enqueue audio chunk with backpressure handling.
    
    PR5: Uses ConcurrencyController for production traffic.
    Falls back to direct queue for tests and small queues.
    """
    if not chunk:
        return
    
    # For small queues (tests) or when controller unavailable, use direct queue
    queue_maxsize = getattr(q, 'maxsize', 0)
    if queue_maxsize > 0 and queue_maxsize <= 10:
        # Direct queue path (for tests with small queues)
        try:
            q.put_nowait(chunk)
            if state is not None:
                from server.services.metrics_registry import get_registry
                get_registry().inc_counter("audio_bytes_received", amount=len(chunk), labels={"source": source})
        except asyncio.QueueFull:
            # Drop oldest to avoid lag spiral
            _ = q.get_nowait()
            q.put_nowait(chunk)
            if state is not None:
                state.dropped_frames = getattr(state, 'dropped_frames', 0) + 1
                logger.warning(f"Backpressure: dropped frame for {source}, total={state.dropped_frames}")
                
                from server.services.metrics_registry import get_registry
                get_registry().inc_counter("audio_frames_dropped", labels={"source": source})
                
                # Send backpressure warning to client (throttled)
                if websocket is not None and not state.backpressure_warned:
                    state.backpressure_warned = True
                    asyncio.create_task(ws_send(state, websocket, {
                        "type": "status",
                        "state": "backpressure",
                        "message": f"Audio queue full, dropping frames (source={source})",
                        "dropped_frames": state.dropped_frames,
                    }))
        return
    
    # PR5: Use concurrency controller for production-sized queues
    controller = get_concurrency_controller()
    
    # Check if this source should be dropped under extreme load
    if controller.should_drop_source(source):
        if state is not None:
            state.dropped_frames = getattr(state, 'dropped_frames', 0) + 1
            logger.warning(f"Dropping {source} due to extreme overload")
        return
    
    # Submit chunk (will drop oldest if queue full)
    success, dropped_oldest = await controller.submit_chunk(chunk, source)
    
    # Track dropped frames in state (for tests and backward compat)
    if dropped_oldest and state is not None:
        state.dropped_frames = getattr(state, 'dropped_frames', 0) + 1
    
    if success:
        # Also add to original queue for compatibility
        try:
            q.put_nowait(chunk)
        except asyncio.QueueFull:
            pass
        
        # Track metrics
        if state is not None:
            from server.services.metrics_registry import get_registry
            get_registry().inc_counter("audio_bytes_received", amount=len(chunk), labels={"source": source})
            
            # Send backpressure warning if we dropped frames
            if dropped_oldest and websocket is not None and not state.backpressure_warned:
                state.backpressure_warned = True
                asyncio.create_task(ws_send(state, websocket, {
                    "type": "status",
                    "state": "backpressure",
                    "message": f"Audio queue full, dropping frames (source={source})",
                    "dropped_frames": state.dropped_frames,
                }))
    else:
        # Submission failed (queue full and couldn't make space)
        if state is not None:
            state.dropped_frames = getattr(state, 'dropped_frames', 0) + 1
            logger.warning(f"Backpressure: dropped frame for {source}, total={state.dropped_frames}")
            
            from server.services.metrics_registry import get_registry
            get_registry().inc_counter("audio_frames_dropped", labels={"source": source})


async def _pcm_stream(queue: asyncio.Queue) -> AsyncIterator[bytes]:
    """Drain audio queue until EOF (None sentinel)."""
    while True:
        chunk = await queue.get()
        if chunk is None:
            return
        yield chunk


async def _asr_loop(websocket: WebSocket, state: SessionState, queue: asyncio.Queue, source: str) -> None:
    logger.debug(f"starting ASR loop for source={source}")
    
    # TCK-20260211-010: Track RTF for degrade ladder
    last_chunk_time = None
    chunk_count = 0
    
    try:
        async for event in stream_asr(_pcm_stream(queue), sample_rate=state.sample_rate, source=source):
            logger.debug(f"yielding event: {event}")
            
            # TCK-20260211-010: Calculate RTF for degrade ladder
            chunk_count += 1
            current_time = time.time()
            
            if event.get("type") == "asr_final":
                # Calculate processing time and audio duration
                t0 = event.get("t0", 0)
                t1 = event.get("t1", 0)
                audio_duration = t1 - t0
                
                if last_chunk_time is not None and audio_duration > 0:
                    processing_time = current_time - last_chunk_time
                    rtf = processing_time / audio_duration
                    
                    # Store for metrics
                    state.asr_processing_times.append(processing_time)
                    state.audio_time_processed += audio_duration
                    state.processing_time_total += processing_time
                    
                    # Check degrade ladder if available
                    if state.degrade_ladder and chunk_count % 5 == 0:  # Check every 5 chunks
                        try:
                            new_level, action = await state.degrade_ladder.check(rtf)
                            if action:
                                logger.info(f"Degrade action applied: {action.name}")
                        except Exception as e:
                            logger.error(f"Degrade ladder check failed: {e}")
                
                last_chunk_time = current_time
                
                # Add source if missing (stream_asr does it, but double check)
                if "source" not in event:
                    event["source"] = source
                state.transcript.append(event)
            
            await ws_send(state, websocket, event)
            
    except Exception as e:
        logger.error(f"error in ASR loop ({source}): {e}")
        # TCK-20260211-010: Report error to degrade ladder for potential failover
        if state.degrade_ladder:
            try:
                await state.degrade_ladder.report_provider_error(e)
            except Exception as degrade_err:
                logger.error(f"Failed to report error to degrade ladder: {degrade_err}")


async def _analysis_loop(websocket: WebSocket, state: SessionState) -> None:
    try:
        while True:
            await asyncio.sleep(12)
            snapshot = list(state.transcript)
            # P1: Add timeout to prevent indefinite hang on NLP processing
            try:
                entities = await asyncio.wait_for(
                    asyncio.to_thread(extract_entities, snapshot),
                    timeout=10.0  # 10 second timeout for entity extraction
                )
                await ws_send(state, websocket, {"type": "entities_update", **entities})
            except asyncio.TimeoutError:
                logger.warning("Entity extraction timed out after 10s, skipping this cycle")
                await ws_send(state, websocket, {"type": "status", "state": "warning", "message": "Analysis delayed"})

            await asyncio.sleep(28)
            snapshot = list(state.transcript)
            # P1: Add timeout to prevent indefinite hang on NLP processing
            try:
                cards = await asyncio.wait_for(
                    asyncio.to_thread(extract_cards, snapshot),
                    timeout=15.0  # 15 second timeout for card extraction (more complex)
                )
            except asyncio.TimeoutError:
                logger.warning("Card extraction timed out after 15s, skipping this cycle")
                cards = {"actions": [], "decisions": [], "risks": []}
            
            await ws_send(state, websocket, {
                "type": "cards_update",
                "actions": cards.get("actions", []),
                "decisions": cards.get("decisions", []),
                "risks": cards.get("risks", []),
                "window": {"t0": 0.0, "t1": 600.0},
            })
    except asyncio.CancelledError:
        return


async def _on_degrade_level_change(
    websocket: WebSocket, 
    state: SessionState, 
    old_level: DegradeLevel, 
    new_level: DegradeLevel,
    action
) -> None:
    """Handle degrade level changes and notify client."""
    action_name = action.name if action else "none"
    logger.warning(f"Degrade level changed: {old_level.name} -> {new_level.name} (action: {action_name})")
    
    # Map degrade levels to UI states
    level_to_status = {
        DegradeLevel.NORMAL: ("streaming", "Performance optimal"),
        DegradeLevel.WARNING: ("buffering", "Processing slower than real-time"),
        DegradeLevel.DEGRADE: ("buffering", "Reduced quality for stability"),
        DegradeLevel.EMERGENCY: ("overloaded", "Critical backlog, dropping frames"),
        DegradeLevel.FAILOVER: ("reconnecting", "Switching to fallback provider"),
    }
    
    status, message = level_to_status.get(new_level, ("warning", "Performance issue"))
    
    await ws_send(state, websocket, {
        "type": "status",
        "state": status,
        "message": message,
        "degrade_level": new_level.name,
        "action": action_name,
    })


async def _metrics_loop(websocket: WebSocket, state: SessionState) -> None:
    """Emit metrics every 1 second for health monitoring."""
    try:
        while True:
            await asyncio.sleep(1.0)
            
            if state.closed:
                return
            
            for source, q in state.queues.items():
                queue_depth = q.qsize()
                queue_max = QUEUE_MAX
                fill_ratio = queue_depth / queue_max if queue_max > 0 else 0
                
                # Calculate dropped in last 10s
                dropped_recent = state.dropped_frames - state.asr_last_dropped
                state.asr_last_dropped = state.dropped_frames
                
                # Calculate realtime factor
                # Use last 10 processing times if available
                recent_times = state.asr_processing_times[-10:] if state.asr_processing_times else []
                avg_infer_time = sum(recent_times) / len(recent_times) if recent_times else 0.0
                
                # Realtime factor = processing_time / audio_time
                # Assuming 2s chunks, if avg_infer_time is 0.5s, factor is 0.25 (good)
                # If avg_infer_time is 3s, factor is 1.5 (bad - falling behind)
                chunk_seconds = float(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2"))
                realtime_factor = avg_infer_time / chunk_seconds if chunk_seconds > 0 else 0.0
                
                # Calculate backlog seconds
                backlog_seconds = fill_ratio * chunk_seconds * queue_max if queue_max > 0 else 0.0
                
                # Backpressure warnings
                if fill_ratio > 0.95 and not state.backpressure_warned:
                    state.backpressure_warned = True
                    await ws_send(state, websocket, {
                        "type": "status",
                        "state": "overloaded",
                        "message": f"Audio backlog critical for {source}",
                        "source": source
                    })
                elif fill_ratio > 0.85 and not state.backpressure_warned:
                    await ws_send(state, websocket, {
                        "type": "status",
                        "state": "buffering",
                        "message": f"Processing backlog for {source}",
                        "source": source
                    })
                elif fill_ratio < 0.70:
                    state.backpressure_warned = False
                
                # TCK-20260211-010: Get degrade ladder status if available
                degrade_status = None
                if state.degrade_ladder:
                    try:
                        degrade_status = state.degrade_ladder.get_status()
                    except Exception as e:
                        logger.debug(f"Failed to get degrade ladder status: {e}")
                
                # V1: Emit enhanced metrics with correlation IDs and provider info
                metrics_payload = {
                    "type": "metrics",
                    "session_id": state.session_id,
                    "attempt_id": state.attempt_id,
                    "connection_id": state.connection_id,
                    "source": source,
                    "queue_depth": queue_depth,
                    "queue_max": queue_max,
                    "queue_fill_ratio": round(fill_ratio, 2),
                    "dropped_total": state.dropped_frames,
                    "dropped_recent": dropped_recent,
                    "dropped_chunks_last_10s": dropped_recent,  # V1: Explicit field name
                    "avg_infer_ms": round(avg_infer_time * 1000, 1),
                    "avg_processing_ms": round(avg_infer_time * 1000, 1),  # V1: Alias for consistency
                    "realtime_factor": round(realtime_factor, 2),
                    "backlog_seconds": round(backlog_seconds, 2),  # V1: New metric
                    "provider": state.provider_name,  # V1: Provider name
                    "model_id": state.model_id,  # V1: Model identifier
                    "vad_enabled": state.vad_enabled,  # V1: VAD status
                    "sources_active": list(state.active_sources),  # V1: Active sources list
                    "timestamp": time.time()
                }
                
                # TCK-20260211-010: Add degrade ladder status if available
                if degrade_status:
                    metrics_payload["degrade_level"] = degrade_status.get("level")
                    metrics_payload["degrade_level_num"] = degrade_status.get("level_number")
                    metrics_payload["rtf_avg_10s"] = degrade_status.get("rtf_avg_10s")
                
                await ws_send(state, websocket, metrics_payload)
                
                # V1: Update global metrics registry
                from server.services.metrics_registry import get_registry
                registry = get_registry()
                registry.set_gauge("queue_depth", queue_depth, labels={"source": source})
                registry.observe_histogram("inference_time_ms", avg_infer_time * 1000)
                
    except asyncio.CancelledError:
        return
    except Exception as e:
        logger.error(f"Error in metrics loop: {e}")


@router.websocket("/ws/live-listener")
async def ws_live_listener(websocket: WebSocket) -> None:
    await websocket.accept()

    if not _is_ws_authorized(websocket):
        await websocket.send_text(json.dumps({
            "type": "status",
            "state": "error",
            "message": "Unauthorized websocket connection",
        }))
        await websocket.close(code=1008)
        return

    state = SessionState()
    # No single pcm_queue anymore, dynamic via state.queues

    diarization_enabled = os.getenv("ECHOPANEL_DIARIZATION", "0") == "1"
    diarization_max_seconds = int(os.getenv("ECHOPANEL_DIARIZATION_MAX_SECONDS", "1800"))
    state.diarization_enabled = diarization_enabled
    state.diarization_max_bytes = diarization_max_seconds * 16000 * 2

    # PR2: Don't send streaming status on connect - wait for start message
    # Initial status is "connected" not "streaming"
    await ws_send(state, websocket, {"type": "status", "state": "connected", "message": "Connected, waiting for start"})
    if DEBUG:
        logger.debug("ws_live_listener: connected, waiting for start")

    try:
        while True:
            try:
                message = await websocket.receive()
                if DEBUG:
                    logger.debug(f"ws_live_listener: received message: {message}")
            except RuntimeError:
                if DEBUG:
                    logger.debug("ws_live_listener: RuntimeError in receive")
                break

            # Handle Text (JSON) Messages
            if "text" in message and message["text"] is not None:
                try:
                    payload: Dict[str, Any] = json.loads(message["text"])
                    msg_type = payload.get("type")
                    if DEBUG:
                        logger.debug(f"ws_live_listener: processing message type: {msg_type}")

                    if msg_type == "start":
                        state.session_id = payload.get("session_id")
                        state.attempt_id = payload.get("attempt_id")  # V1: Client attempt ID
                        state.connection_id = payload.get("connection_id") or str(uuid.uuid4())  # V1: Generate if not provided
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
                        
                        # PR5: Acquire session slot (concurrency limiting)
                        controller = get_concurrency_controller()
                        session_acquired = await controller.acquire_session(timeout=5.0)
                        if not session_acquired:
                            await ws_send(state, websocket, {
                                "type": "status",
                                "state": "error",
                                "message": "Server at capacity, please try again later"
                            })
                            await websocket.close()
                            return
                        
                        state.sample_rate = sample_rate
                        state.started = True
                        
                        # V1: Get provider info for metrics
                        from server.services.asr_providers import ASRProviderRegistry
                        from server.services.asr_stream import _get_default_config
                        config = _get_default_config()
                        provider = ASRProviderRegistry.get_provider(config=config)
                        if provider:
                            state.provider_name = provider.name
                            state.model_id = config.model_name
                            state.vad_enabled = config.vad_enabled
                        
                        # TCK-20260211-010: Initialize degrade ladder for adaptive performance
                        if provider:
                            state.degrade_ladder = DegradeLadder(
                                provider=provider,
                                config=config,
                                on_level_change=lambda old, new, action: asyncio.create_task(
                                    _on_degrade_level_change(websocket, state, old, new, action)
                                )
                            )
                            logger.info(f"Degrade ladder initialized at level {state.degrade_ladder.state.level.name}")
                        
                        # V1: Track connection in metrics
                        from server.services.metrics_registry import get_registry
                        get_registry().inc_counter("ws_connections_total")
                        get_registry().set_gauge("active_sessions", 1)  # Simplified - should count actual
                        
                        # PR2: Now ASR is ready, send streaming ACK
                        await ws_send(state, websocket, {
                            "type": "status", 
                            "state": "streaming", 
                            "message": "Streaming",
                            "connection_id": state.connection_id  # V1: Echo back for confirmation
                        })
                        
                        logger.info(f"Session started: session_id={state.session_id}, "
                                  f"attempt_id={state.attempt_id}, connection_id={state.connection_id}, "
                                  f"provider={state.provider_name}, model={state.model_id}")
                        
                        if DEBUG:
                            logger.debug(f"ws_live_listener: start session_id={state.session_id}")
                        state.analysis_tasks.append(asyncio.create_task(_analysis_loop(websocket, state)))
                        # PR2: Start metrics emission task
                        state.metrics_task = asyncio.create_task(_metrics_loop(websocket, state))

                    elif msg_type == "audio":
                        # B1 Fix: Handle source-tagged audio frames
                        if DEBUG:
                            logger.debug(f"ws_live_listener: received audio, source={payload.get('source', 'system')}, data len={len(payload.get('data', ''))}")
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
                                    logger.debug(f"ws_live_listener: starting ASR task for source={source}")
                                state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                            
                            # P2-13: Write audio to dump file
                            _write_audio_dump(state, source, chunk)
                            
                            await put_audio(q, chunk, state=state, source=source, websocket=websocket)
                            _append_diarization_audio(state, source, chunk)

                    elif msg_type == "stop":
                        # Signal EOF to all queues
                        for q in state.queues.values():
                            await q.put(None)
                            
                        if DEBUG:
                            logger.debug("ws_live_listener: stop")
                        
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
                        
                        # THEN stop analysis tasks (P1 fix: add timeout to prevent hanging)
                        for t in state.analysis_tasks:
                            t.cancel()
                        try:
                            await asyncio.wait_for(
                                asyncio.gather(*state.analysis_tasks, return_exceptions=True),
                                timeout=5.0
                            )
                        except asyncio.TimeoutError:
                            logger.warning("Analysis task cancellation timed out, some tasks may be orphaned")
                        
                        # Run session-end diarization per source to avoid mixed-source corruption.
                        diarization_by_source = await _run_diarization_per_source(state)
                        diarization_segments = _flatten_diarization_segments(diarization_by_source)
                        
                        # Snapshot transcript once for deterministic finalization
                        # (prevents race if any late events append during to_thread calls)
                        # P1 fix (TO-1): Sort by timestamp for deterministic ordering across sources
                        transcript_snapshot = sorted(state.transcript, key=lambda s: s.get("t0", 0.0))
                        
                        # Merge transcript with source-specific speaker labels.
                        labeled_transcript = await asyncio.to_thread(
                            _merge_transcript_with_source_diarization, transcript_snapshot, diarization_by_source
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
                        logger.debug("ws_live_listener: invalid JSON in text message")

            # Handle Binary Messages (Legacy/Fallback)
            if "bytes" in message and message["bytes"] is not None and state.started:
                chunk = message["bytes"]
                source = "system" # Default for binary
                
                q = get_queue(state, source)
                if source not in state.started_sources:
                    state.started_sources.add(source)
                    if DEBUG:
                        logger.debug(f"ws_live_listener: starting ASR task for source={source}")
                    state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                
                await put_audio(q, chunk, state=state, source=source, websocket=websocket)
                _append_diarization_audio(state, source, chunk)
                
                if DEBUG:
                    state.bytes_received += len(chunk)
                    now = time.time()
                    if now - state.last_log > 2:
                        state.last_log = now
                        logger.debug(f"ws_live_listener: received {state.bytes_received} bytes (binary)")

    except WebSocketDisconnect:
        if DEBUG:
            logger.debug("ws_live_listener: disconnect")
        return
    finally:
        # PR5: Release session slot
        if state.started:
            controller = get_concurrency_controller()
            controller.release_session()
            logger.debug(f"Released session slot for {state.session_id}")
        
        # P2-13: Close audio dump files
        _close_audio_dumps(state)
        
        # V1: Track disconnect in metrics
        from server.services.metrics_registry import get_registry
        get_registry().inc_counter("ws_disconnects_total")
        
        # PR2: Cancel metrics task
        if state.metrics_task:
            state.metrics_task.cancel()
            try:
                await state.metrics_task
            except asyncio.CancelledError:
                pass
        
        for q in state.queues.values():
            await q.put(None)
        all_tasks = state.tasks + state.asr_tasks + state.analysis_tasks
        for task in all_tasks:
            task.cancel()
        await asyncio.gather(*all_tasks, return_exceptions=True)
        # Log session metrics for observability
        logger.info(f"Session {state.session_id} complete: "
                   f"connection_id={state.connection_id}, "
                   f"dropped_frames={state.dropped_frames}, "
                   f"transcript_segments={len(state.transcript)}, "
                   f"audio_time={state.audio_time_processed:.1f}s")
