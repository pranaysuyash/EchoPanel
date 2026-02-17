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

from server.services.analysis_stream import extract_cards, extract_cards_incremental, extract_entities, extract_entities_incremental, generate_rolling_summary
from server.services.asr_stream import stream_asr
from server.services.diarization import diarize_pcm, merge_transcript_with_speakers
from server.services.transcript_ids import generate_segment_id
from server.services.concurrency_controller import (
    get_concurrency_controller,
    BackpressureLevel,
)
from server.services.degrade_ladder import DegradeLadder, DegradeLevel
from server.services.screen_ocr import get_ocr_handler, OCRFrameHandler
from server.services.brain_dump_integration import (
    get_integration,
    index_transcript_event,
    initialize_integration,
    shutdown_integration
)
from server.api.ws_schemas import (
    parse_websocket_message,
    StartMessage,
    StopMessage,
    AudioMessage,
    VoiceNoteStartMessage,
    VoiceNoteAudioMessage,
    VoiceNoteStopMessage,
    OCRTextMessage,
)

router = APIRouter()
logger = logging.getLogger(__name__)
DEBUG = os.getenv("ECHOPANEL_DEBUG", "0") == "1"
# Time-based queue sizing: max buffered audio seconds (not frame count)
# With 16kHz mono 16-bit: 1 sec = 32000 bytes, 2 sec = 64000 bytes
QUEUE_MAX_SECONDS = float(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX_SECONDS", "2.0"))
SAMPLE_RATE = 16000
BYTES_PER_SAMPLE = 2
# Calculate max bytes: sample_rate * bytes_per_sample * max_seconds
QUEUE_MAX_BYTES = int(SAMPLE_RATE * BYTES_PER_SAMPLE * QUEUE_MAX_SECONDS)
# Legacy: frame count for compatibility (approximate, assumes 20ms frames)
QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", "500"))
MAX_ACTIVE_SOURCES_PER_SESSION = int(os.getenv("ECHOPANEL_MAX_ACTIVE_SOURCES_PER_SESSION", "2"))
DEBUG_AUDIO_DUMP = os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP", "0") == "1"
DEBUG_AUDIO_DUMP_DIR = Path(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_DIR", "/tmp/echopanel_audio_dump"))
DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS = int(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_AGE_SECONDS", "86400"))
DEBUG_AUDIO_DUMP_MAX_FILES = int(os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_FILES", "200"))
DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES = int(
    os.getenv("ECHOPANEL_DEBUG_AUDIO_DUMP_MAX_TOTAL_BYTES", str(512 * 1024 * 1024))
)

# Import auth utilities from shared security module
from server.security import extract_ws_token, is_authorized

# TCK-20260213-074: Dual-lane pipeline configuration
# Lane A (Realtime): Bounded queue, may drop to stay live
# Lane B (Recording): Lossless, never drops, write to disk for post-processing
RECORDING_LANE_ENABLED = os.getenv("ECHOPANEL_RECORDING_LANE", "1") == "1"
RECORDING_LANE_DIR = Path(os.getenv("ECHOPANEL_RECORDING_DIR", "/tmp/echopanel_recordings"))
RECORDING_LANE_FORMAT = os.getenv("ECHOPANEL_RECORDING_FORMAT", "wav")  # wav, pcm, or both
RECORDING_LANE_MAX_AGE_SECONDS = int(os.getenv("ECHOPANEL_RECORDING_MAX_AGE", "604800"))  # 7 days
RECORDING_LANE_MAX_TOTAL_BYTES = int(os.getenv("ECHOPANEL_RECORDING_MAX_BYTES", str(10 * 1024 * 1024 * 1024)))  # 10GB


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
    transcript_lock: asyncio.Lock = field(default_factory=asyncio.Lock)  # Protect transcript mutations
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
    # PR6: Per-source processing samples (processing_time_s, audio_duration_s) for accurate RTF in metrics.
    asr_samples_by_source: Dict[str, list[tuple[float, float]]] = field(default_factory=dict)
    asr_last_dropped: int = 0  # For computing dropped_recent
    audio_time_processed: float = 0.0  # Total audio seconds processed
    processing_time_total: float = 0.0  # Total processing time spent
    # V1: Provider info for metrics
    provider_name: str = "unknown"
    model_id: str = "unknown"
    vad_enabled: bool = False
    # PR3: Hold the ASRConfig used for this session so metrics can query provider.health().
    asr_config: Any = None
    # U8 groundwork: staged client feature flags (no behavioral change yet)
    client_clock_drift_compensation_enabled: bool = False
    client_vad_enabled: bool = False
    client_clock_drift_telemetry_enabled: bool = False
    client_vad_telemetry_enabled: bool = False
    # U8 groundwork telemetry: ASR timeline spread across active sources
    asr_last_t1_by_source: Dict[str, float] = field(default_factory=dict)
    source_clock_spread_ms: float = 0.0
    max_source_clock_spread_ms: float = 0.0
    # TCK-20260211-010: Degrade ladder for adaptive performance
    degrade_ladder: Optional[DegradeLadder] = None
    # INT-010 incremental analysis state
    last_entity_analysis_t1: float = 0.0
    last_card_analysis_t1: float = 0.0
    current_entities: Dict[str, Any] = field(default_factory=dict)
    current_cards: Dict[str, Any] = field(default_factory=dict)
    # TCK-20260213-074: Dual-lane pipeline - Recording lane (lossless)
    recording_files: Dict[str, Any] = field(default_factory=dict)  # source -> file handles
    recording_paths: Dict[str, Path] = field(default_factory=dict)  # source -> file paths
    recording_bytes_written: Dict[str, int] = field(default_factory=dict)  # source -> bytes
    # VNI: Voice note support
    voice_note_buffer: bytearray = field(default_factory=bytearray)  # Buffer for voice note audio
    voice_note_started: bool = False  # Whether voice note session is active
    voice_note_asr_task: Optional[asyncio.Task] = None  # ASR task for voice note


def _normalize_source(source: Optional[str]) -> str:
    raw = (source or "system").strip().lower()
    if raw in {"mic", "microphone"}:
        return "mic"
    if raw == "system":
        return "system"
    return raw or "system"


def _extract_client_features(payload: Dict[str, Any]) -> Dict[str, bool]:
    features = payload.get("client_features")
    if not isinstance(features, dict):
        return {
            "clock_drift_compensation_enabled": False,
            "client_vad_enabled": False,
            "clock_drift_telemetry_enabled": False,
            "client_vad_telemetry_enabled": False,
        }

    return {
        "clock_drift_compensation_enabled": bool(features.get("clock_drift_compensation_enabled", False)),
        "client_vad_enabled": bool(features.get("client_vad_enabled", False)),
        "clock_drift_telemetry_enabled": bool(features.get("clock_drift_telemetry_enabled", False)),
        "client_vad_telemetry_enabled": bool(features.get("client_vad_telemetry_enabled", False)),
    }


def _debug_ws_message_summary(message: Dict[str, Any]) -> str:
    """Return a privacy-safe summary of a raw Starlette websocket receive() message."""
    if "text" in message and message["text"] is not None:
        text = message["text"]
        if not isinstance(text, str):
            return "text(non-str)"
        # Try to parse JSON to avoid logging base64 audio payloads.
        try:
            payload = json.loads(text)
            if isinstance(payload, dict):
                msg_type = payload.get("type", "unknown")
                source = payload.get("source")
                data_len = None
                if msg_type == "audio":
                    raw = payload.get("data", "")
                    if isinstance(raw, str):
                        data_len = len(raw)
                parts = [f"text json type={msg_type}"]
                if source:
                    parts.append(f"source={source}")
                if data_len is not None:
                    parts.append(f"b64_len={data_len}")
                return " ".join(parts)
        except Exception:
            pass
        # Fallback: only log length.
        return f"text len={len(text)}"

    if "bytes" in message and message["bytes"] is not None:
        blob = message["bytes"]
        if not isinstance(blob, (bytes, bytearray)):
            return "bytes(non-bytes)"
        b = bytes(blob)
        # Optional v1 header: b"EP" + version + source + payload.
        if len(b) >= 4 and b[0:2] == b"EP":
            version = b[2]
            source = b[3]
            src = "system" if source == 0 else ("mic" if source == 1 else str(source))
            return f"bytes len={len(b)} header=EP v={version} source={src} payload_len={max(0, len(b) - 4)}"
        return f"bytes len={len(b)}"

    return "unknown"


async def _reject_new_source(websocket: WebSocket, state: SessionState, source: str) -> None:
    await ws_send(
        state,
        websocket,
        {
            "type": "status",
            "state": "warning",
            "message": f"Too many active sources (max {MAX_ACTIVE_SOURCES_PER_SESSION}). Ignoring source '{source}'.",
        },
    )


def _update_source_clock_spread(state: SessionState) -> None:
    if len(state.asr_last_t1_by_source) < 2:
        state.source_clock_spread_ms = 0.0
        return

    t1_values = list(state.asr_last_t1_by_source.values())
    spread_seconds = max(t1_values) - min(t1_values)
    spread_ms = max(0.0, spread_seconds * 1000.0)
    state.source_clock_spread_ms = spread_ms
    if spread_ms > state.max_source_clock_spread_ms:
        state.max_source_clock_spread_ms = spread_ms


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


def _compute_recent_rtf(samples: list[tuple[float, float]]) -> float:
    """
    Compute realtime factor (RTF) from recent samples.

    RTF = processing_time / audio_duration. Lower is better (< 1.0 means faster than real-time).
    """
    if not samples:
        return 0.0
    total_processing = 0.0
    total_audio = 0.0
    for processing_s, audio_s in samples:
        if processing_s > 0:
            total_processing += processing_s
        if audio_s > 0:
            total_audio += audio_s
    if total_audio <= 0:
        return 0.0
    return total_processing / total_audio


def _health_to_payload(value: Any) -> Optional[Dict[str, Any]]:
    """Best-effort conversion of provider health into a JSON-serializable dict."""
    if value is None:
        return None
    if isinstance(value, dict):
        return value
    to_dict = getattr(value, "to_dict", None)
    if callable(to_dict):
        try:
            payload = to_dict()
            return payload if isinstance(payload, dict) else None
        except Exception:
            return None
    return None


async def ws_send(state: SessionState, websocket: WebSocket, event: dict) -> None:
    """Send event to websocket, safely handling closed connections.
    
    NOTE: state.closed check is inside the lock to prevent race conditions where
    the connection is closed between the check and the actual send operation.
    """
    # V1: Inject correlation IDs for safer client-side state validation.
    # Keep this additive and do not mutate the caller's dict.
    payload = event
    if state.session_id and "session_id" not in payload:
        payload = dict(payload)
        payload["session_id"] = state.session_id
    if state.attempt_id and "attempt_id" not in payload:
        if payload is event:
            payload = dict(payload)
        payload["attempt_id"] = state.attempt_id
    if state.connection_id and "connection_id" not in payload:
        if payload is event:
            payload = dict(payload)
        payload["connection_id"] = state.connection_id
    
    async with state.send_lock:
        # Check state.closed inside the lock to prevent race conditions
        if state.closed:
            return
        try:
            await websocket.send_text(json.dumps(payload))
        except (RuntimeError, WebSocketDisconnect):
            # Connection closed during send (normal race when clients disconnect abruptly).
            state.closed = True
        except Exception as e:
            # Be conservative: treat send failures as a closed connection.
            state.closed = True
            logger.debug("ws_send failed (marking session closed): %s", e)


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
        # Set restrictive permissions (owner read/write only)
        os.chmod(filepath, 0o600)
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


# =============================================================================
# TCK-20260213-074: DUAL-LANE PIPELINE - Recording Lane (Lossless)
# =============================================================================
# Lane A (Realtime): Bounded queue, may drop to stay live (low latency captions)
# Lane B (Recording): Lossless file write, never drops, for post-processing
# =============================================================================

def _cleanup_recording_dir(now: Optional[float] = None) -> None:
    """Apply retention limits to recording files (age/total-size)."""
    if not RECORDING_LANE_ENABLED:
        return

    try:
        RECORDING_LANE_DIR.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        logger.error(f"Failed to prepare recording directory: {e}")
        return

    # Get all recording files (wav, pcm)
    entries: list[tuple[Path, os.stat_result]] = []
    for pattern in ("*.wav", "*.pcm"):
        for path in RECORDING_LANE_DIR.glob(pattern):
            try:
                entries.append((path, path.stat()))
            except FileNotFoundError:
                continue
            except Exception as e:
                logger.warning(f"Failed to inspect recording file {path}: {e}")

    if not entries:
        return

    entries.sort(key=lambda item: item[1].st_mtime)  # oldest first
    cutoff = (now or time.time()) - RECORDING_LANE_MAX_AGE_SECONDS
    kept_entries: list[tuple[Path, os.stat_result]] = []

    # First pass: remove expired files
    for path, stat_result in entries:
        if RECORDING_LANE_MAX_AGE_SECONDS > 0 and stat_result.st_mtime < cutoff:
            try:
                path.unlink(missing_ok=True)
                logger.info(f"Removed expired recording: {path}")
            except Exception as e:
                logger.warning(f"Failed to remove expired recording {path}: {e}")
            continue
        kept_entries.append((path, stat_result))

    # Second pass: remove oldest files if over total size limit
    if RECORDING_LANE_MAX_TOTAL_BYTES > 0:
        total_bytes = sum(stat_result.st_size for _, stat_result in kept_entries)
        if total_bytes > RECORDING_LANE_MAX_TOTAL_BYTES:
            for path, stat_result in kept_entries:
                if total_bytes <= RECORDING_LANE_MAX_TOTAL_BYTES:
                    break
                try:
                    path.unlink(missing_ok=True)
                    total_bytes -= stat_result.st_size
                    logger.info(f"Removed recording to free space: {path}")
                except Exception as e:
                    logger.warning(f"Failed to remove recording {path}: {e}")


def _write_wav_header(f, sample_rate: int, num_samples: int) -> None:
    """Write a standard WAV file header.
    
    WAV format:
    - RIFF header (12 bytes)
    - fmt chunk (24 bytes)
    - data chunk header (8 bytes)
    """
    import struct
    
    # Calculate sizes
    bits_per_sample = 16
    byte_rate = sample_rate * 2  # 16-bit mono
    data_size = num_samples * 2  # 16-bit samples
    riff_size = 36 + data_size  # 44 bytes header - 8 (RIFF size field)
    
    # RIFF header
    f.write(b'RIFF')
    f.write(struct.pack('<I', riff_size))
    f.write(b'WAVE')
    
    # fmt chunk
    f.write(b'fmt ')
    f.write(struct.pack('<I', 16))  # Subchunk1Size (16 for PCM)
    f.write(struct.pack('<H', 1))   # AudioFormat (1 = PCM)
    f.write(struct.pack('<H', 1))   # NumChannels (1 = mono)
    f.write(struct.pack('<I', sample_rate))
    f.write(struct.pack('<I', byte_rate))
    f.write(struct.pack('<H', 2))   # BlockAlign (2 bytes per sample)
    f.write(struct.pack('<H', bits_per_sample))
    
    # data chunk header
    f.write(b'data')
    f.write(struct.pack('<I', data_size))


def _init_recording_lane(state: SessionState, source: str, sample_rate: int = 16000) -> None:
    """Initialize recording lane files for a source (TCK-20260213-074).
    
    Creates WAV and/or PCM files depending on RECORDING_LANE_FORMAT.
    WAV is preferred for easy playback, PCM is raw for processing.
    """
    if not RECORDING_LANE_ENABLED:
        return
    
    if source in state.recording_files:
        return  # Already initialized
    
    try:
        RECORDING_LANE_DIR.mkdir(parents=True, exist_ok=True)
        _cleanup_recording_dir()
        
        timestamp = int(time.time())
        session_id = state.session_id or "unknown"
        base_name = f"{session_id}_{source}_{timestamp}"
        
        files = {}
        paths = {}
        
        if RECORDING_LANE_FORMAT in ("wav", "both"):
            wav_path = RECORDING_LANE_DIR / f"{base_name}.wav"
            # Open for read/write, we'll update the header at the end
            wav_file = open(wav_path, "w+b")
            # Set restrictive permissions (owner read/write only)
            os.chmod(wav_path, 0o600)
            # Write placeholder header (will be updated on close)
            _write_wav_header(wav_file, sample_rate, 0)
            files['wav'] = wav_file
            paths['wav'] = wav_path
            logger.info(f"Recording lane (WAV) initialized: {wav_path}")

        if RECORDING_LANE_FORMAT in ("pcm", "both"):
            pcm_path = RECORDING_LANE_DIR / f"{base_name}.pcm"
            pcm_file = open(pcm_path, "wb")
            # Set restrictive permissions (owner read/write only)
            os.chmod(pcm_path, 0o600)
            files['pcm'] = pcm_file
            paths['pcm'] = pcm_path
            logger.info(f"Recording lane (PCM) initialized: {pcm_path}")
        
        state.recording_files[source] = files
        state.recording_paths[source] = paths
        state.recording_bytes_written[source] = 0
        
    except Exception as e:
        logger.error(f"Failed to initialize recording lane for {source}: {e}")


def _write_recording_lane(state: SessionState, source: str, chunk: bytes) -> None:
    """Write audio chunk to recording lane files (lossless, never drops).
    
    This is Lane B of the dual-lane pipeline - always write to disk regardless
    of realtime lane backpressure. This ensures we never lose audio even if
    ASR is falling behind.
    """
    if not RECORDING_LANE_ENABLED:
        return
    
    if source not in state.recording_files:
        return
    
    try:
        files = state.recording_files[source]
        
        # Write to WAV file (after the 44-byte header)
        if 'wav' in files:
            wav_file = files['wav']
            wav_file.write(chunk)
        
        # Write to PCM file
        if 'pcm' in files:
            pcm_file = files['pcm']
            pcm_file.write(chunk)
        
        # Track bytes written
        state.recording_bytes_written[source] = state.recording_bytes_written.get(source, 0) + len(chunk)
        
    except Exception as e:
        logger.error(f"Failed to write to recording lane for {source}: {e}")


def _finalize_recording_lane(state: SessionState, source: str, sample_rate: int = 16000) -> Optional[Path]:
    """Finalize recording files and return the primary path.
    
    For WAV files, updates the header with correct sizes.
    Returns the path to the WAV file (or PCM if WAV not available).
    """
    if source not in state.recording_files:
        return None
    
    files = state.recording_files.get(source, {})
    paths = state.recording_paths.get(source, {})
    bytes_written = state.recording_bytes_written.get(source, 0)
    
    primary_path = None
    
    try:
        # Finalize WAV: update header with actual sizes
        if 'wav' in files:
            wav_file = files['wav']
            try:
                # Calculate actual number of samples
                num_samples = bytes_written // 2  # 16-bit samples
                
                # Seek to beginning and rewrite header
                wav_file.seek(0)
                _write_wav_header(wav_file, sample_rate, num_samples)
                wav_file.close()
                
                wav_path = paths.get('wav')
                if wav_path:
                    primary_path = wav_path
                    duration_sec = num_samples / sample_rate
                    logger.info(f"Recording lane finalized: {wav_path} ({duration_sec:.1f}s, {bytes_written} bytes)")
            except Exception as e:
                logger.error(f"Failed to finalize WAV for {source}: {e}")
                try:
                    wav_file.close()
                except:
                    pass
        
        # Finalize PCM: just close
        if 'pcm' in files:
            pcm_file = files['pcm']
            try:
                pcm_file.close()
                pcm_path = paths.get('pcm')
                if pcm_path and not primary_path:
                    primary_path = pcm_path
            except Exception as e:
                logger.error(f"Failed to close PCM for {source}: {e}")
        
    finally:
        # Clean up state
        state.recording_files.pop(source, None)
        state.recording_paths.pop(source, None)
        state.recording_bytes_written.pop(source, None)
    
    return primary_path


def _close_all_recording_lanes(state: SessionState, sample_rate: int = 16000) -> Dict[str, Optional[Path]]:
    """Finalize all recording lanes and return paths by source."""
    results = {}
    for source in list(state.recording_files.keys()):
        results[source] = _finalize_recording_lane(state, source, sample_rate)
    return results


def get_queue(state: SessionState, source: str) -> asyncio.Queue:
    if source not in state.queues:
        state.queues[source] = asyncio.Queue(maxsize=QUEUE_MAX)
        state.active_sources.add(source)
    return state.queues[source]


def _queue_bytes(q: asyncio.Queue) -> int:
    """Estimate total bytes in queue by summing chunk sizes."""
    # Access the underlying queue data structure
    # asyncio.Queue stores items in a collections.deque
    if hasattr(q, '_queue'):
        return sum(len(item) for item in q._queue if item is not None)
    return 0


async def put_audio(
    q: asyncio.Queue,
    chunk: bytes,
    state: Optional["SessionState"] = None,
    source: str = "",
    websocket: Optional[WebSocket] = None,
) -> None:
    """Enqueue audio chunk with byte-based backpressure handling (Dual-Lane Pipeline).
    
    LANE A (Realtime): Bounded queue with time-based limits for low-latency ASR.
    - QUEUE_MAX_SECONDS (default 2.0s) max buffered audio per source
    - Drops oldest chunks to stay "live" when processing falls behind
    
    LANE B (Recording): Lossless file write, never drops, for post-processing.
    - Writes all audio to disk regardless of realtime lane backpressure
    - Ensures no audio is lost even if ASR is overloaded
    
    NOTE:
    This function must reflect the *actual* ingest queue used by `_asr_loop()`.
    A previous integration attempt enqueued into an additional controller-owned
    queue that was never drained, which caused false sustained "overloaded"
    signals and `Dropping system due to extreme overload` even under normal
    realtime streaming.
    """
    if not chunk:
        return

    # Track metrics
    if state is not None:
        from server.services.metrics_registry import get_registry
        get_registry().inc_counter("audio_bytes_received", amount=len(chunk), labels={"source": source})
    
    # TCK-20260213-074: LANE B (Recording) - Write to disk BEFORE any dropping
    # This ensures lossless capture regardless of realtime lane backpressure
    if state is not None and RECORDING_LANE_ENABLED:
        _write_recording_lane(state, source, chunk)

    # Byte-based backpressure: ensure we don't exceed QUEUE_MAX_BYTES
    # This gives predictable max latency (e.g., 2 seconds) regardless of frame size
    current_bytes = _queue_bytes(q)
    chunk_bytes = len(chunk)
    
    # Drop oldest chunks until we have room for the new chunk
    dropped_count = 0
    dropped_bytes = 0
    while current_bytes + chunk_bytes > QUEUE_MAX_BYTES and not q.empty():
        try:
            old_chunk = q.get_nowait()
            if old_chunk is not None:
                old_size = len(old_chunk)
                current_bytes -= old_size
                dropped_bytes += old_size
                dropped_count += 1
        except asyncio.QueueEmpty:
            break
    
    # Try to enqueue the new chunk (should succeed now unless queue is weird)
    try:
        q.put_nowait(chunk)
    except asyncio.QueueFull:
        # Shouldn't happen with byte-based management, but handle gracefully
        dropped_count += 1
        dropped_bytes += chunk_bytes
        logger.warning(f"Queue full even after dropping - discarding new chunk for {source}")

    # Log backpressure events
    if dropped_count > 0 and state is not None:
        state.dropped_frames = getattr(state, "dropped_frames", 0) + dropped_count
        # Estimate dropped time: bytes / bytes_per_second
        dropped_sec = dropped_bytes / (SAMPLE_RATE * BYTES_PER_SAMPLE)
        
        logger.warning(
            "Backpressure: dropped %d frames (%d bytes, ~%.2fs) for %s "
            "(max=%d bytes = %.1fs), total_dropped=%d",
            dropped_count, dropped_bytes, dropped_sec,
            source, QUEUE_MAX_BYTES, QUEUE_MAX_SECONDS,
            state.dropped_frames,
        )

        from server.services.metrics_registry import get_registry
        get_registry().inc_counter("audio_frames_dropped", amount=dropped_count, labels={"source": source})
        get_registry().inc_counter("audio_bytes_dropped", amount=dropped_bytes, labels={"source": source})

        # Send backpressure warning to client (throttled)
        if websocket is not None and not state.backpressure_warned:
            state.backpressure_warned = True
            asyncio.create_task(ws_send(state, websocket, {
                "type": "status",
                "state": "backpressure",
                "message": f"Audio backlog, dropped ~{dropped_sec:.1f}s to stay realtime (source={source})",
                "dropped_frames": state.dropped_frames,
                "dropped_seconds": round(dropped_sec, 2),
                "backlog_seconds": round(current_bytes / (SAMPLE_RATE * BYTES_PER_SAMPLE), 2),
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
                    source_key = _normalize_source(event.get("source", source))
                    samples = state.asr_samples_by_source.setdefault(source_key, [])
                    samples.append((processing_time, audio_duration))
                    # Bound memory: keep a moderate amount of history per source.
                    if len(samples) > 200:
                        del samples[: len(samples) - 200]
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
                # Stable transcript segment IDs (groundwork for offline canonical merge).
                if "segment_id" not in event:
                    event["segment_id"] = generate_segment_id(
                        source=event.get("source", source),
                        t0=float(event.get("t0", 0.0) or 0.0),
                        t1=float(event.get("t1", 0.0) or 0.0),
                        text=str(event.get("text", "") or ""),
                    )
                source_key = _normalize_source(event.get("source", source))
                state.asr_last_t1_by_source[source_key] = float(event.get("t1", 0.0))
                _update_source_clock_spread(state)
                async with state.transcript_lock:
                    state.transcript.append(event)
                
                # Brain Dump: Index transcript event
                try:
                    integration = get_integration()
                    if integration and state.connection_id:
                        await index_transcript_event(
                            connection_id=state.connection_id,
                            event=event,
                            source=event.get("source", source)
                        )
                except Exception as e:
                    logger.debug(f"Failed to index transcript: {e}")
            
            await ws_send(state, websocket, event)
            
    except Exception as e:
        logger.error(f"error in ASR loop ({source}): {e}")
        # TCK-20260211-010: Report error to degrade ladder for potential failover
        if state.degrade_ladder:
            try:
                await state.degrade_ladder.report_provider_error(e)
            except Exception as degrade_err:
                logger.error(f"Failed to report error to degrade ladder: {degrade_err}")


def _has_new_transcript_segments(state: SessionState, last_t1: float) -> bool:
    """Check if there are new transcript segments since last analysis."""
    if not state.transcript:
        return False
    # Find max t1 in transcript
    max_t1 = max((seg.get("t1", 0.0) for seg in state.transcript), default=0.0)
    return max_t1 > last_t1


async def _analysis_loop(websocket: WebSocket, state: SessionState) -> None:
    """
    Analysis loop with activity-gated processing.
    
    QW-001: Only runs analysis when new transcript segments exist,
    reducing CPU usage during silence.
    """
    # Configuration
    ENTITY_INTERVAL = 12.0  # Min seconds between entity analysis
    CARD_INTERVAL = 28.0    # Min seconds between card analysis
    IDLE_POLL_INTERVAL = 1.0  # Short poll when idle
    
    try:
        while True:
            # QW-001: Activity-gated entity extraction
            await asyncio.sleep(ENTITY_INTERVAL)
            
            if not _has_new_transcript_segments(state, state.last_entity_analysis_t1):
                # No new content, skip this cycle
                logger.debug("Skipping entity analysis: no new transcript segments")
                continue
            
            async with state.transcript_lock:
                snapshot = list(state.transcript)
            # P1: Add timeout to prevent indefinite hang on NLP processing
            try:
                # Use incremental entity extraction
                entities, state.last_entity_analysis_t1 = await asyncio.wait_for(
                    asyncio.to_thread(extract_entities_incremental, snapshot, state.last_entity_analysis_t1, state.current_entities),
                    timeout=10.0  # 10 second timeout for entity extraction
                )
                state.current_entities = entities
                await ws_send(state, websocket, {"type": "entities_update", **entities})
                logger.debug(f"Entity analysis completed, tracked {len(entities)} entity types")
            except asyncio.TimeoutError:
                logger.warning("Entity extraction timed out after 10s, skipping this cycle")
                await ws_send(state, websocket, {"type": "status", "state": "warning", "message": "Analysis delayed"})

            # QW-001: Activity-gated card extraction
            await asyncio.sleep(CARD_INTERVAL)
            
            if not _has_new_transcript_segments(state, state.last_card_analysis_t1):
                # No new content, skip this cycle
                logger.debug("Skipping card analysis: no new transcript segments")
                continue
            
            async with state.transcript_lock:
                snapshot = list(state.transcript)
            # P1: Add timeout to prevent indefinite hang on NLP processing
            try:
                # Use incremental card extraction
                cards, state.last_card_analysis_t1 = await asyncio.wait_for(
                    asyncio.to_thread(extract_cards_incremental, snapshot, state.last_card_analysis_t1, state.current_cards),
                    timeout=15.0  # 15 second timeout for card extraction (more complex)
                )
                state.current_cards = cards
                total_cards = len(cards.get("actions", [])) + len(cards.get("decisions", [])) + len(cards.get("risks", []))
                logger.debug(f"Card analysis completed, found {total_cards} cards")
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
        logger.debug("Analysis loop cancelled")
        return


async def _transcribe_voice_note(websocket: WebSocket, state: SessionState, audio_data: bytes) -> None:
    """VNI: Transcribe voice note audio and send transcript back to client."""
    if not audio_data:
        logger.warning("Voice note audio data is empty")
        await ws_send(state, websocket, {
            "type": "voice_note_transcript",
            "text": "",
            "duration": 0.0,
            "error": "No audio data"
        })
        return
    
    try:
        # Calculate duration
        duration_seconds = len(audio_data) / (SAMPLE_RATE * BYTES_PER_SAMPLE)
        
        if DEBUG:
            logger.debug(f"Transcribing voice note: {len(audio_data)} bytes ({duration_seconds:.2f}s)")
        
        # Import ASR streaming function
        from server.services.asr_stream import _get_default_config, stream_asr
        
        # Get ASR config
        config = _get_default_config()
        
        # Create a queue for the voice note audio
        queue = asyncio.Queue()
        
        # Put all audio data into queue in one chunk
        await queue.put(audio_data)
        await queue.put(None)  # Signal EOF
        
        # Create a simple async iterator for the queue
        async def audio_stream():
            while True:
                chunk = await queue.get()
                if chunk is None:
                    break
                yield chunk
        
        # Stream ASR for voice note
        transcript_parts = []
        
        async for result in stream_asr(audio_stream(), config, sample_rate=SAMPLE_RATE):
            if result.text and not result.text.startswith("  "):
                transcript_parts.append(result.text.strip())
        
        # Combine transcript parts
        final_transcript = " ".join(transcript_parts)
        
        if DEBUG:
            logger.debug(f"Voice note transcript: {final_transcript[:100]}...")
        
        # Send transcript back to client
        await ws_send(state, websocket, {
            "type": "voice_note_transcript",
            "text": final_transcript,
            "duration": duration_seconds
        })
        
    except Exception as e:
        logger.error(f"Voice note transcription failed: {e}")
        await ws_send(state, websocket, {
            "type": "voice_note_transcript",
            "text": "",
            "duration": 0.0,
            "error": str(e)
        })
    finally:
        state.voice_note_buffer.clear()
        state.voice_note_asr_task = None



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

            # PR3: Provider health metrics (queried once per tick; repeated in each source payload for simplicity).
            provider_health_payload: Optional[Dict[str, Any]] = None
            try:
                if state.provider_name not in {"", "unknown"} and state.asr_config is not None:
                    from server.services.asr_providers import ASRProviderRegistry
                    provider = ASRProviderRegistry.get_provider(name=state.provider_name, config=state.asr_config)
                    if provider is not None:
                        provider_health_payload = _health_to_payload(await provider.health())
            except Exception as e:
                logger.debug(f"Failed to query provider health: {e}")
            
            # Snapshot queues to avoid "dictionary changed size during iteration" errors
            # when new sources are added concurrently (from get_queue in main loop)
            queues_snapshot = list(state.queues.items())
            for source, q in queues_snapshot:
                source_key = _normalize_source(source)
                
                # Byte-based queue metrics for predictable latency
                queue_bytes = _queue_bytes(q)
                queue_bytes_max = QUEUE_MAX_BYTES
                fill_ratio = queue_bytes / queue_bytes_max if queue_bytes_max > 0 else 0
                
                # Backlog in seconds (predictable regardless of frame size)
                bytes_per_second = SAMPLE_RATE * BYTES_PER_SAMPLE
                backlog_seconds = queue_bytes / bytes_per_second if bytes_per_second > 0 else 0
                max_backlog_seconds = QUEUE_MAX_SECONDS
                
                # Legacy: also report frame count for compatibility
                queue_depth = q.qsize()
                
                # Calculate dropped in last 10s
                dropped_recent = state.dropped_frames - state.asr_last_dropped
                state.asr_last_dropped = state.dropped_frames
                
                # PR6: Compute realtime factor from actual audio duration processed (not configured chunk size).
                recent_samples = state.asr_samples_by_source.get(source_key, [])
                recent_window = recent_samples[-10:] if recent_samples else []
                recent_processing_times = [p for (p, _) in recent_window]
                avg_infer_time = (
                    (sum(recent_processing_times) / len(recent_processing_times)) if recent_processing_times else 0.0
                )
                realtime_factor = _compute_recent_rtf(recent_window)
                
                # Backpressure warnings based on time-based fill ratio
                if fill_ratio > 0.95 and not state.backpressure_warned:
                    state.backpressure_warned = True
                    await ws_send(state, websocket, {
                        "type": "status",
                        "state": "overloaded",
                        "message": f"Audio backlog critical: {backlog_seconds:.1f}s buffered for {source}",
                        "source": source,
                        "backlog_seconds": round(backlog_seconds, 2),
                    })
                elif fill_ratio > 0.85 and not state.backpressure_warned:
                    await ws_send(state, websocket, {
                        "type": "status",
                        "state": "buffering",
                        "message": f"Processing backlog: {backlog_seconds:.1f}s buffered for {source}",
                        "source": source,
                        "backlog_seconds": round(backlog_seconds, 2),
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
                # TCK-20260213-074: Updated with byte-based queue metrics
                metrics_payload = {
                    "type": "metrics",
                    "session_id": state.session_id,
                    "attempt_id": state.attempt_id,
                    "connection_id": state.connection_id,
                    "source": source,
                    # Byte-based queue metrics (TCK-20260213-074)
                    "queue_bytes": queue_bytes,
                    "queue_bytes_max": queue_bytes_max,
                    "queue_fill_ratio": round(fill_ratio, 2),
                    "backlog_seconds": round(backlog_seconds, 2),
                    "max_backlog_seconds": round(max_backlog_seconds, 2),
                    # Legacy frame-based metrics (for compatibility)
                    "queue_depth": queue_depth,
                    "queue_max_frames": QUEUE_MAX,
                    # Performance metrics
                    "dropped_total": state.dropped_frames,
                    "dropped_recent": dropped_recent,
                    "dropped_chunks_last_10s": dropped_recent,
                    "avg_infer_ms": round(avg_infer_time * 1000, 1),
                    "avg_processing_ms": round(avg_infer_time * 1000, 1),
                    "realtime_factor": round(realtime_factor, 2),
                    # Provider info
                    "provider": state.provider_name,
                    "model_id": state.model_id,
                    "vad_enabled": state.vad_enabled,
                    "provider_health": provider_health_payload,
                    # Client features
                    "client_clock_drift_compensation_enabled": state.client_clock_drift_compensation_enabled,
                    "client_vad_enabled": state.client_vad_enabled,
                    "client_clock_drift_telemetry_enabled": state.client_clock_drift_telemetry_enabled,
                    "client_vad_telemetry_enabled": state.client_vad_telemetry_enabled,
                    # Source/sync metrics
                    "source_clock_spread_ms": round(state.source_clock_spread_ms, 1),
                    "max_source_clock_spread_ms": round(state.max_source_clock_spread_ms, 1),
                    "sources_active": list(state.active_sources),
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

    provided_token = extract_ws_token(websocket)
    if not is_authorized(provided_token):
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
                    logger.debug("ws_live_listener: received %s", _debug_ws_message_summary(message))
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
                        # Validate message schema
                        try:
                            start_msg = parse_websocket_message(payload)
                        except ValueError as e:
                            logger.warning(f"Invalid start message: {e}")
                            await ws_send(state, websocket, {
                                "type": "error",
                                "message": f"Invalid start message: {str(e)}"
                            })
                            await websocket.close()
                            return
                        
                        # Cast to StartMessage for type safety
                        if not isinstance(start_msg, StartMessage):
                            await ws_send(state, websocket, {
                                "type": "error",
                                "message": "Expected start message"
                            })
                            await websocket.close()
                            return
                        
                        state.session_id = start_msg.session_id
                        state.attempt_id = start_msg.attempt_id  # V1: Client attempt ID
                        state.connection_id = start_msg.connection_id or str(uuid.uuid4())  # V1: Generate if not provided
                        client_features = _extract_client_features(payload)
                        state.client_clock_drift_compensation_enabled = client_features["clock_drift_compensation_enabled"]
                        state.client_vad_enabled = client_features["client_vad_enabled"]
                        state.client_clock_drift_telemetry_enabled = client_features["clock_drift_telemetry_enabled"]
                        state.client_vad_telemetry_enabled = client_features["client_vad_telemetry_enabled"]
                        sample_rate = start_msg.sample_rate
                        encoding = start_msg.format
                        channels = start_msg.channels
                        
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
                            state.asr_config = config
                        
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
                            "connection_id": state.connection_id,  # V1: Echo back for confirmation
                            "client_features": {
                                "clock_drift_compensation_enabled": state.client_clock_drift_compensation_enabled,
                                "client_vad_enabled": state.client_vad_enabled,
                                "clock_drift_telemetry_enabled": state.client_clock_drift_telemetry_enabled,
                                "client_vad_telemetry_enabled": state.client_vad_telemetry_enabled,
                            },
                        })
                        
                        logger.info(f"Session started: session_id={state.session_id}, "
                                  f"attempt_id={state.attempt_id}, connection_id={state.connection_id}, "
                                  f"provider={state.provider_name}, model={state.model_id}, "
                                  f"client_vad={state.client_vad_enabled}, "
                                  f"clock_drift_comp={state.client_clock_drift_compensation_enabled}")
                        
                        # Brain Dump: Start indexing session
                        try:
                            integration = get_integration()
                            if integration:
                                await integration.start_session(
                                    connection_id=state.connection_id,
                                    title=f"Session {state.session_id}",
                                    source_app="echopanel"
                                )
                        except Exception as e:
                            logger.warning(f"Failed to start brain dump session: {e}")
                        
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
                            source = _normalize_source(payload.get("source", "system"))

                            if MAX_ACTIVE_SOURCES_PER_SESSION > 0 and source not in state.started_sources:
                                if len(state.started_sources) >= MAX_ACTIVE_SOURCES_PER_SESSION:
                                    await _reject_new_source(websocket, state, source)
                                    continue
                            chunk = base64.b64decode(b64_data)
                            
                            q = get_queue(state, source)
                            if source not in state.started_sources:
                                state.started_sources.add(source)
                                # P2-13: Initialize audio dump for new source
                                _init_audio_dump(state, source)
                                # TCK-20260213-074: Initialize recording lane (lossless)
                                _init_recording_lane(state, source, state.sample_rate)
                                if DEBUG:
                                    logger.debug(f"ws_live_listener: starting ASR task for source={source}")
                                state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                            
                            # P2-13: Write audio to dump file
                            _write_audio_dump(state, source, chunk)
                            
                            await put_audio(q, chunk, state=state, source=source, websocket=websocket)
                            _append_diarization_audio(state, source, chunk)

                    elif msg_type == "screen_frame":
                        # OCR Pipeline: Process screen capture frame
                        if state.started:
                            try:
                                ocr_handler = get_ocr_handler()
                                if ocr_handler.enabled:
                                    image_data = payload.get("image_data", "")
                                    timestamp = payload.get("timestamp", time.time())
                                    mode = payload.get("mode", "background")  # background, query, quality
                                    
                                    # Use hybrid pipeline with mode
                                    from server.services.ocr_hybrid import HybridOCRPipeline
                                    hybrid = getattr(ocr_handler, '_hybrid', None)
                                    
                                    if hybrid and mode in ["query", "quality"]:
                                        # Direct hybrid pipeline for special modes
                                        image_bytes = base64.b64decode(image_data)
                                        result = await hybrid.process_frame(
                                            image_bytes=image_bytes,
                                            session_id=state.session_id or "unknown",
                                            mode=mode,
                                            skip_duplicates=(mode == "background")
                                        )
                                        
                                        # Build enriched response
                                        response = {
                                            "type": "ocr_result",
                                            "timestamp": timestamp,
                                            "success": result.success,
                                            "text_preview": result.primary_text[:100] + "..." if len(result.primary_text) > 100 else result.primary_text,
                                            "full_text": result.primary_text,
                                            "word_count": result.word_count,
                                            "confidence": round(result.confidence, 1),
                                            "source": result.source,
                                            "is_enriched": result.is_enriched,
                                            "layout_type": result.layout_type,
                                            "processing_time_ms": round(result.processing_time_ms, 1),
                                        }
                                        
                                        # Add enrichment data if available
                                        if result.semantic_summary:
                                            response["semantic_summary"] = result.semantic_summary
                                        if result.key_insights:
                                            response["key_insights"] = result.key_insights
                                        if result.entities:
                                            response["entities"] = [{"text": e.text, "type": e.type} for e in result.entities]
                                        
                                        await ws_send(state, websocket, response)
                                    else:
                                        # Standard OCR handling
                                        result = await ocr_handler.handle_frame(
                                            image_base64=image_data,
                                            session_id=state.session_id or "unknown",
                                            timestamp=timestamp
                                        )
                                        
                                        # Build response with new fields if available
                                        response = {
                                            "type": "ocr_result",
                                            "timestamp": timestamp,
                                            "success": result.success,
                                            "text_preview": result.text[:100] + "..." if len(result.text) > 100 else result.text,
                                            "word_count": result.word_count,
                                            "confidence": round(result.confidence, 1),
                                            "indexed": result.should_index,
                                            "is_duplicate": result.is_duplicate,
                                            "processing_time_ms": round(result.processing_time_ms, 1),
                                        }
                                        
                                        # Add hybrid fields if available
                                        if hasattr(result, 'is_enriched'):
                                            response["is_enriched"] = result.is_enriched
                                        if hasattr(result, 'semantic_summary') and result.semantic_summary:
                                            response["semantic_summary"] = result.semantic_summary
                                        if hasattr(result, 'layout_type'):
                                            response["layout_type"] = result.layout_type
                                        
                                        await ws_send(state, websocket, response)
                                    
                                    if DEBUG:
                                        logger.debug(f"OCR processed: {result.word_count if hasattr(result, 'word_count') else len(result.primary_text.split())} words, mode={mode}")
                                else:
                                    if DEBUG:
                                        logger.debug("OCR disabled, ignoring screen frame")
                            except Exception as e:
                                logger.error(f"OCR processing error: {e}")
                                await ws_send(state, websocket, {
                                    "type": "ocr_result",
                                    "timestamp": time.time(),
                                    "success": False,
                                    "error": str(e),
                                })
                    
                    elif msg_type == "slide_query":
                        # Query a specific slide (requires hybrid OCR)
                        if state.started:
                            try:
                                ocr_handler = get_ocr_handler()
                                hybrid = getattr(ocr_handler, '_hybrid', None)
                                
                                if hybrid and hybrid.is_available():
                                    image_data = payload.get("image_data", "")
                                    query = payload.get("query", "")
                                    timestamp = payload.get("timestamp", time.time())
                                    
                                    if image_data and query:
                                        answer = await hybrid.answer_query(
                                            image_bytes=base64.b64decode(image_data),
                                            query=query,
                                            session_id=state.session_id or "unknown"
                                        )
                                        
                                        await ws_send(state, websocket, {
                                            "type": "slide_query_result",
                                            "timestamp": timestamp,
                                            "query": query,
                                            "answer": answer,
                                            "success": True,
                                        })
                                    else:
                                        await ws_send(state, websocket, {
                                            "type": "slide_query_result",
                                            "timestamp": time.time(),
                                            "success": False,
                                            "error": "Missing image_data or query",
                                        })
                                else:
                                    await ws_send(state, websocket, {
                                        "type": "slide_query_result",
                                        "timestamp": time.time(),
                                        "success": False,
                                        "error": "Hybrid OCR not available",
                                    })
                            except Exception as e:
                                logger.error(f"Slide query error: {e}")
                                await ws_send(state, websocket, {
                                    "type": "slide_query_result",
                                    "timestamp": time.time(),
                                    "success": False,
                                    "error": str(e),
                                })

                    elif msg_type == "voice_note_start":
                        # VNI: Start voice note session
                        voice_note_id = payload.get("session_id", str(uuid.uuid4()))
                        if DEBUG:
                            logger.debug(f"ws_live_listener: voice note started: {voice_note_id}")
                        
                        state.voice_note_buffer.clear()
                        state.voice_note_started = True
                        
                        await ws_send(state, websocket, {
                            "type": "voice_note_started",
                            "session_id": voice_note_id
                        })

                    elif msg_type == "voice_note_audio":
                        # VNI: Receive voice note audio data
                        if not state.voice_note_started:
                            logger.warning("Received voice_note_audio without session start")
                            return
                        
                        b64_data = payload.get("data", "")
                        chunk = base64.b64decode(b64_data)
                        state.voice_note_buffer.extend(chunk)
                        
                        if DEBUG:
                            logger.debug(f"ws_live_listener: voice note audio received: {len(chunk)} bytes, total: {len(state.voice_note_buffer)} bytes")

                    elif msg_type == "voice_note_stop":
                        # VNI: Stop voice note and transcribe
                        if not state.voice_note_started:
                            logger.warning("Received voice_note_stop without session start")
                            return
                        
                        if DEBUG:
                            logger.debug(f"ws_live_listener: voice note stopped, transcribing {len(state.voice_note_buffer)} bytes")
                        
                        # Cancel any existing ASR task
                        if state.voice_note_asr_task:
                            state.voice_note_asr_task.cancel()
                            try:
                                await state.voice_note_asr_task
                            except asyncio.CancelledError:
                                pass
                        
                        # Run ASR on voice note buffer
                        state.voice_note_started = False
                        state.voice_note_asr_task = asyncio.create_task(
                            _transcribe_voice_note(websocket, state, bytes(state.voice_note_buffer))
                        )

                    elif msg_type == "stop":
                        # Validate message schema
                        try:
                            stop_msg = parse_websocket_message(payload)
                        except ValueError as e:
                            logger.warning(f"Invalid stop message: {e}")
                            await ws_send(state, websocket, {
                                "type": "error",
                                "message": f"Invalid stop message: {str(e)}"
                            })
                            await websocket.close()
                            return
                        
                        if not isinstance(stop_msg, StopMessage):
                            await ws_send(state, websocket, {
                                "type": "error",
                                "message": "Expected stop message"
                            })
                            await websocket.close()
                            return
                        
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
                        
                        # TCK-20260213-074: Finalize recording lanes (lossless audio files)
                        recording_paths = _close_all_recording_lanes(state, state.sample_rate)
                        if recording_paths:
                            logger.info(f"Session recordings finalized: {recording_paths}")
                        
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
                                    "client_features": {
                                        "clock_drift_compensation_enabled": state.client_clock_drift_compensation_enabled,
                                        "client_vad_enabled": state.client_vad_enabled,
                                        "clock_drift_telemetry_enabled": state.client_clock_drift_telemetry_enabled,
                                        "client_vad_telemetry_enabled": state.client_vad_telemetry_enabled,
                                    },
                                    "clock_spread_ms": {
                                        "last": round(state.source_clock_spread_ms, 1),
                                        "max": round(state.max_source_clock_spread_ms, 1),
                                    },
                                    # TCK-20260213-074: Recording lane paths
                                    "recordings": {
                                        source: str(path) for source, path in recording_paths.items() if path
                                    } if recording_paths else {},
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

                # Binary audio framing (v1):
                # Header: b"EP" + version(1 byte) + source(1 byte) + raw PCM16 payload.
                # - source: 0=system, 1=mic
                # Backwards compatible: if header absent, treat as legacy system PCM.
                source = "system"
                if len(chunk) >= 4 and chunk[0:2] == b"EP" and chunk[2] == 1 and chunk[3] in (0, 1):
                    source = "system" if chunk[3] == 0 else "mic"
                    chunk = chunk[4:]

                source = _normalize_source(source)

                if MAX_ACTIVE_SOURCES_PER_SESSION > 0 and source not in state.started_sources:
                    if len(state.started_sources) >= MAX_ACTIVE_SOURCES_PER_SESSION:
                        await _reject_new_source(websocket, state, source)
                        continue
                
                q = get_queue(state, source)
                if source not in state.started_sources:
                    state.started_sources.add(source)
                    # P2-13: Initialize audio dump for new source (match JSON path)
                    _init_audio_dump(state, source)
                    # TCK-20260213-074: Initialize recording lane (lossless)
                    _init_recording_lane(state, source, state.sample_rate)
                    if DEBUG:
                        logger.debug(f"ws_live_listener: starting ASR task for source={source}")
                    state.asr_tasks.append(asyncio.create_task(_asr_loop(websocket, state, q, source)))
                
                # P2-13: Write audio to dump file
                _write_audio_dump(state, source, chunk)
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
        
        # TCK-20260213-074: Finalize recording lanes on disconnect/abnormal close
        if state.recording_files:
            recording_paths = _close_all_recording_lanes(state, state.sample_rate)
            if recording_paths:
                logger.info(f"Disconnect recordings finalized: {recording_paths}")
        
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
        
        # Enforce timeout on task cleanup to prevent indefinite hangs during disconnect
        # (similar to the stop handler which uses timeout=5.0). This ensures server
        # resources are released even if a task ignores CancelledError or blocks indefinitely.
        try:
            await asyncio.wait_for(asyncio.gather(*all_tasks, return_exceptions=True), timeout=5.0)
        except asyncio.TimeoutError:
            logger.warning(
                f"Task cleanup for session {state.session_id} timed out after 5s "
                "(some tasks may still be running). Forcing closure."
            )
        
        # Brain Dump: End indexing session
        try:
            integration = get_integration()
            if integration and state.connection_id:
                await integration.end_session(state.connection_id)
        except Exception as e:
            logger.warning(f"Failed to end brain dump session: {e}")
        
        # Log session metrics for observability
        logger.info(f"Session {state.session_id} complete: "
                   f"connection_id={state.connection_id}, "
                   f"dropped_frames={state.dropped_frames}, "
                   f"transcript_segments={len(state.transcript)}, "
                   f"audio_time={state.audio_time_processed:.1f}s")
