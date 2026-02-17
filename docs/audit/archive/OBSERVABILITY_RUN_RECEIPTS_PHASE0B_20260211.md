> **⚠️ OBSOLETE (2026-02-16):** Key gaps cited here have been resolved:
> - "No correlation IDs" → `StructuredLogger.swift` with session/component/function context, `attempt_id`/`connection_id` in WS events
> - "Unstructured logging" → `StructuredLogger.swift:13` produces JSON-structured logs with component, level, metadata
> - "No metrics registry" → `server/services/metrics_registry.py:82` with `MetricsRegistry`, counters, gauges
> - "No session bundles" → `SessionBundle.swift:20` with export, audio manifest, debug bundles
> Code evidence verified against actual source files. Moved to archive.

# EchoPanel Phase 0B Audit: Observability + Run Receipts

**Title:** Observability + Run Receipts (Session Bundles, Metrics, Diagnosability)  
**Date:** 2026-02-11  
**Auditor:** Agent (Forensic Debugger + SRE Personas)  
**Scope:** Logging, metrics, session artifacts, diagnosability, reproducibility  
**Status:** Evidence-based assessment with V1 proposals

---

## A) Files Inspected

### Client (macOS/Swift)
| Path | Purpose |
|------|---------|
| `macapp/MeetingListenerApp/Sources/AppState.swift` | Session state, metrics tracking, debug bundle export (L746-795) |
| `macapp/MeetingListenerApp/Sources/SessionStore.swift` | Local persistence, auto-save, crash recovery (L1-327) |
| `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` | WS client, metrics parsing, SourceMetrics struct (L1-351) |
| `macapp/MeetingListenerApp/Sources/BackendManager.swift` | Server lifecycle, health checks, crash recovery (L1-501) |
| `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` | DiagnosticsView, debug bundle export UI (L471-562) |
| `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` | Audio capture, quality metrics, debug logging (L1-150+) |
| `macapp/MeetingListenerApp/Sources/Models.swift` | Data models (TranscriptSegment, etc.) |

### Server (Python)
| Path | Purpose |
|------|---------|
| `server/main.py` | FastAPI app, logging setup, health endpoint (L1-94) |
| `server/api/ws_live_listener.py` | WebSocket handler, metrics loop, SessionState (L1-616) |
| `server/services/asr_stream.py` | ASR pipeline, provider abstraction (L1-91) |
| `server/services/asr_providers.py` | Provider registry (inspected for context) |
| `server/services/vad_filter.py` | VAD processing (inspected for context) |

### Shared/Docs
| Path | Purpose |
|------|---------|
| `docs/OBSERVABILITY.md` | Existing observability documentation |
| `docs/DUAL_PIPELINE_ARCHITECTURE.md` | Architecture context |

---

## B) Current Observability Inventory

### B1) Logging

#### Client-Side (Swift)
| Aspect | Current State | Evidence |
|--------|---------------|----------|
| **Framework** | `NSLog` (Apple system logger) | `AppState.swift:L725`, `BackendManager.swift:L151` |
| **Log levels** | Implicit (no structured levels) | `debugEnabled` flag gates some logs |
| **Format** | Plain text, unstructured | Example: `"SessionStore: Started session \(sessionId)"` (L82) |
| **Destination** | OS unified logging (Console.app) | `NSLog` default behavior |
| **Correlation IDs** | ❌ **MISSING** | No session_id/attempt_id in log lines |
| **Server log capture** | ✅ Yes | `BackendManager.swift:L136-155` redirects server stdout/stderr to temp file |

**Log Locations:**
- Server logs: `~/tmp/echopanel_server.log` (temporary, cleared on reboot)
- No persistent client log file

#### Server-Side (Python)
| Aspect | Current State | Evidence |
|--------|---------------|----------|
| **Framework** | Python `logging` module | `main.py:L11-13` |
| **Log levels** | Basic (INFO default) | `logging.basicConfig(level=logging.INFO)` |
| **Format** | Plain text, unstructured | Default formatter |
| **Destination** | stdout (captured by client) | Redirected to file by BackendManager |
| **Correlation IDs** | ❌ **MISSING** | No request/session context in logs |
| **Key log points** | Startup, health checks, errors | `main.py:L19-34`, `ws_live_listener.py:L258` |

**Observed Log Patterns:**
```
# From ws_live_listener.py
logger.warning(f"Backpressure: dropped frame for {source}, total={state.dropped_frames}")  # L258
logger.info(f"Session {state.session_id} complete: dropped_frames={state.dropped_frames}")  # L615
logger.error(f"error in ASR loop ({source}): {e}")  # L301
```

### B2) Metrics

#### Client-Side Metrics (Swift)
| Metric | Type | Source | Evidence |
|--------|------|--------|----------|
| `lastMetrics: [String: SourceMetrics]` | Published dict | WS `metrics` message | `AppState.swift:L139` |
| `backpressureLevel` | Enum (.normal/.buffering/.overloaded) | Derived from metrics | `AppState.swift:L140-146`, `L299-305` |
| `inputLastSeenBySource` | Dict [String: Date] | Frame callbacks | `AppState.swift:L117` |
| `asrLastSeenBySource` | Dict [String: Date] | ASR events | `AppState.swift:L118` |
| `asrEventCount` | Int | Counter | `AppState.swift:L119` |
| `debugBytes` | Int (private) | Byte counter | `AppState.swift:L202` |
| `debugSamples` | Int (private) | Sample counter | `AppState:L201` |

**SourceMetrics struct** (`WebSocketStreamer.swift:L4-14`):
```swift
struct SourceMetrics {
    let source: String
    let queueDepth: Int
    let queueMax: Int
    let queueFillRatio: Double
    let droppedTotal: Int
    let droppedRecent: Int
    let avgInferMs: Double
    let realtimeFactor: Double
    let timestamp: TimeInterval
}
```

#### Server-Side Metrics (Python)
| Metric | Type | Source | Evidence |
|--------|------|--------|----------|
| `queue_depth` | Int | `asyncio.Queue.qsize()` | `ws_live_listener.py:L336` |
| `queue_max` | Int | Constant (QUEUE_MAX=48) | `ws_live_listener.py:L21`, `L337` |
| `queue_fill_ratio` | Float | depth/max | `ws_live_listener.py:L338` |
| `dropped_total` | Int | Counter | `ws_live_listener.py:L256` |
| `dropped_recent` | Int | Delta over 10s | `ws_live_listener.py:L341-342` |
| `avg_infer_ms` | Float | Derived from processing times | `ws_live_listener.py:L347` |
| `realtime_factor` | Float | infer_time/chunk_time | `ws_live_listener.py:L352-353` |
| `timestamp` | Float | `time.time()` | `ws_live_listener.py:L385` |

**Metrics Emission:**
- Frequency: 1 Hz (every 1 second per source)
- Transport: WebSocket `metrics` message type
- Handler: `_metrics_loop()` (`ws_live_listener.py:L326-391`)

**Thresholds Used:**
| Threshold | Value | Action | Evidence |
|-----------|-------|--------|----------|
| Queue fill > 0.95 | 95% | Set `backpressure_warned=true`, send `overloaded` status | `ws_live_listener.py:L356-363` |
| Queue fill > 0.85 | 85% | Send `buffering` status | `ws_live_listener.py:L364-370` |
| Queue fill < 0.70 | 70% | Clear `backpressure_warned` | `ws_live_listener.py:L371-372` |

### B3) Artifacts

#### Session Storage (SessionStore.swift)
| Artifact | Format | Location | Retention | Evidence |
|----------|--------|----------|-----------|----------|
| `metadata.json` | JSON | `~/Library/Application Support/<bundle>/sessions/<session_id>/` | Until deleted | `SessionStore.swift:L60-69` |
| `snapshot.json` | JSON | Same | Until deleted | `SessionStore.swift:L123-141` |
| `final_snapshot.json` | JSON | Same | Until deleted | `SessionStore.swift:L126` |
| `transcript.jsonl` | NDJSON | Same | Until deleted | `SessionStore.swift:L71-74`, `L111-121` |
| `recovery.json` | JSON | Parent directory | Until session ended | `SessionStore.swift:L159-174` |

**Directory Structure:**
```
~/Library/Application Support/com.echopanel/sessions/
├── recovery.json              # Points to active session
├── <session_id_1>/
│   ├── metadata.json          # {session_id, started_at, audio_source, app_version}
│   ├── snapshot.json          # Periodic state (30s interval)
│   ├── final_snapshot.json    # Final state (if properly ended)
│   └── transcript.jsonl       # Append-only transcript log
├── <session_id_2>/
│   └── ...
```

**Auto-Save Behavior:**
- Interval: 30 seconds (`saveInterval: TimeInterval = 30.0`, L24)
- Trigger: Timer → Notification → `saveSnapshot()` → `sessionStore.saveSnapshot()`
- Content: Full `exportPayload()` including transcript, actions, decisions, entities

#### Debug Bundle Export
**Current Implementation** (`AppState.swift:L746-795`):
- Trigger: User-initiated ("Export Debug Bundle..." button)
- Contents:
  - `server.log` (from temp directory)
  - `session_dump.json` (current session state)
- **Missing:** Metrics history, event timeline, structured logs, audio samples

#### Audio Debug Dump (Server-Side)
**Conditional Feature** (`ws_live_listener.py:L22-23`, `L183-226`):
- Enabled by: `ECHOPANEL_DEBUG_AUDIO_DUMP=1`
- Location: `ECHOPANEL_DEBUG_AUDIO_DUMP_DIR` (default: `/tmp/echopanel_audio_dump/`)
- Format: Raw PCM files per source: `{session_id}_{source}_{timestamp}.pcm`
- **Security:** Raw audio captured (privacy risk)

---

## C) Gap Analysis (12+ Gaps)

| # | Gap Name | Why It Matters | Evidence | Proposed Fix Direction |
|---|----------|----------------|----------|------------------------|
| 1 | **No structured logging** | Cannot filter/query logs by session, severity, or component | All `NSLog` and `logger.*` calls are plain text | Proposed: JSON structured logs with schema |
| 2 | **No correlation IDs in logs** | Cannot trace a session across client/server boundaries | No `session_id` in any log line | Proposed: session_id, attempt_id, connection_id in every log |
| 3 | **No client-side log file** | Logs lost when app closes (only in Console.app memory) | `NSLog` only, no file persistence | Proposed: Rotating file log in Application Support |
| 4 | **No event timeline** | Cannot reconstruct session timeline for debugging | No centralized event log | Proposed: events.ndjson with structured events |
| 5 | **No metrics persistence** | Metrics lost after session ends (only live in UI) | `lastMetrics` is ephemeral | Proposed: metrics.ndjson sampled at 1Hz |
| 6 | **No attempt_id tracking** | Cannot distinguish reconnects from new sessions | `startAttemptId` exists (L191) but not in logs/metrics | Proposed: Add attempt_id to all events |
| 7 | **No connection_id** | Cannot track WebSocket reconnects | Not present in any data structure | Proposed: UUID per WS connection |
| 8 | **Incomplete debug bundle** | Missing metrics, events, logs for support | Only server.log + session_dump | Proposed: Session bundle spec (Section G) |
| 9 | **No log redaction rules** | Potential PII/API key leakage | `BackendManager.swift:L452` has hardcoded path | Proposed: Redaction rules for tokens, paths |
| 10 | **No server-side metrics registry** | Metrics only exist in WS handler | No centralized counter registry | Proposed: Prometheus-style counters/gauges |
| 11 | **No audio replay tooling** | Cannot reproduce ASR issues | No replay script exists | Proposed: replay_audio.py tool |
| 12 | **No centralized health signals** | DiagnosticsView is ad-hoc | `MeetingListenerApp.swift:L471-562` | Proposed: Standardized health payload |
| 13 | **Debug audio lacks consent** | Raw audio captured without explicit opt-in | `ECHOPANEL_DEBUG_AUDIO_DUMP` env var | Proposed: Explicit user consent + encryption |
| 14 | **No log sampling/flood protection** | Risk of log flooding | No rate limiting on logs | Proposed: Sampling rules for high-frequency events |

---

## D) Proposed Correlation ID Scheme (V1)

### ID Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│  SESSION (User-facing)                                          │
│  ├── session_id: UUID (stable across entire user session)       │
│  │   └── Created: User clicks "Start Listening"                 │
│  │   └── Destroyed: User clicks "End Session"                   │
│  │                                                              │
│  ├── attempt_id: UUID (per start attempt / reconnect)           │
│  │   └── Created: Each WS connect() call                        │
│  │   └── Destroyed: WS disconnect or new attempt                │
│  │   └── Used for: Ignoring stale messages (Phase 0A fix)       │
│  │                                                              │
│  └── connection_id: UUID (per WebSocket connection)             │
│      └── Created: WS connection accepted                        │
│      └── Destroyed: WS close                                    │
│      └── Used for: Connection-level debugging                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ID Propagation Rules

| ID | Client Logs | Server Logs | WS Messages | Session Bundle |
|----|-------------|-------------|-------------|----------------|
| `session_id` | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| `attempt_id` | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| `connection_id` | ✅ Required | ✅ Required | ❌ Optional | ✅ Required |
| `source_id` | ✅ Per-frame | ✅ Per-frame | ✅ Per-frame | ✅ In metadata |

### Implementation Points

**Client (Swift):**
- `AppState.startAttemptId` already exists (`L191`) - use for `attempt_id`
- `WebSocketStreamer` should generate `connection_id` on each `connect()`
- Add to all `NSLog` calls via wrapper macro/function

**Server (Python):**
- Generate `connection_id` in `ws_live_listener` on connection accept
- Store in `SessionState` dataclass
- Add to all `logger.*` calls via `extra=` parameter or contextvar

**WS Message Schema:**
```json
{
  "type": "audio|asr_partial|asr_final|metrics|...",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid",
  "timestamp": 1707676800.123,
  "...": "..."
}
```

---

## E) Proposed Metrics Contract (V1)

### Server → Client Metrics Payload (1 Hz)

**Current (exists):**
```json
{
  "type": "metrics",
  "source": "system|mic",
  "queue_depth": 12,
  "queue_max": 48,
  "queue_fill_ratio": 0.25,
  "dropped_total": 5,
  "dropped_recent": 0,
  "avg_infer_ms": 450.5,
  "realtime_factor": 0.23,
  "timestamp": 1707676800.123
}
```

**Proposed V1 Additions:**
```json
{
  "type": "metrics",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid",
  "source": "system|mic",
  "queue_depth": 12,
  "queue_max": 48,
  "queue_fill_ratio": 0.25,
  "dropped_total": 5,
  "dropped_recent": 0,
  "dropped_chunks_last_10s": 2,
  "avg_infer_ms": 450.5,
  "avg_processing_ms": 480.0,
  "realtime_factor": 0.23,
  "backlog_seconds": 0.5,
  "provider": "faster-whisper",
  "model_id": "base.en",
  "vad_enabled": true,
  "sources_active": ["system", "mic"],
  "last_error_code": null,
  "timestamp": 1707676800.123,
  "server_timestamp": 1707676800.125
}
```

### UI State Thresholds

| State | Queue Fill | Dropped (10s) | Realtime Factor | Backlog |
|-------|------------|---------------|-----------------|---------|
| `normal` | < 70% | 0 | < 0.8 | < 1s |
| `buffering` | 70-85% | 0-1 | 0.8-1.2 | 1-3s |
| `overloaded` | > 85% | > 1 | > 1.2 | > 3s |

### Server-Side Metrics Registry (Proposed)

```python
# Proposed minimal registry
class MetricsRegistry:
    """Lightweight in-memory metrics for observability."""
    
    # Counters (monotonic)
    audio_bytes_received: Counter  # by source
    audio_frames_dropped: Counter  # by source
    asr_chunks_processed: Counter
    asr_errors: Counter
    ws_connections: Counter
    ws_disconnects: Counter  # by code
    
    # Gauges (current value)
    queue_depth: Gauge  # by source
    active_sessions: Gauge
    
    # Histograms (distributions)
    inference_time_ms: Histogram  # buckets: 100, 250, 500, 1000, 2000
    processing_time_ms: Histogram
```

---

## F) Proposed Logging Standard (V1)

### Log Levels

| Level | When to Use | Example |
|-------|-------------|---------|
| `DEBUG` | Detailed diagnostic info | Frame-level audio processing |
| `INFO` | Normal operations | Session start/stop, config |
| `WARNING` | Recoverable issues | Frame drops, backpressure |
| `ERROR` | Failures requiring attention | ASR loop crash, WS error |
| `CRITICAL` | App cannot continue | Server bind failure |

### Structured Log Schema (JSON)

```json
{
  "timestamp": "2026-02-11T12:34:56.789Z",
  "level": "INFO",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid",
  "component": "WebSocketStreamer|ASRProvider|SessionStore",
  "event": "session_started|frame_dropped|asr_error",
  "detail": "Human-readable message",
  "context": {
    "source": "system",
    "queue_depth": 12,
    "custom_field": "value"
  }
}
```

### Redaction Rules

| Pattern | Redaction | Example |
|---------|-----------|---------|
| API tokens | `***` | `hf_...` → `***` |
| Auth tokens | `***` | `Bearer ...` → `Bearer ***` |
| File paths with PII | basename only | `/Users/john/...` → `.../file.ext` |
| Raw audio | Never log | ❌ Never include audio data |
| Transcript text | Optional (opt-in) | Default: omit from logs |

### Sampling Rules

| Event Type | Rate | Rationale |
|------------|------|-----------|
| `audio_frame` | 0.1% | High volume, low info |
| `metrics` | 100% | Low volume, critical |
| `asr_partial` | 0% | Too verbose |
| `asr_final` | 100% | Important state |
| `ws_ping` | 1% | Health indicator |

### File Rotation (Client)

```
~/Library/Application Support/com.echopanel/logs/
├── echopanel.log          # Current log
├── echopanel.log.1        # Rotated (previous)
├── echopanel.log.2.gz     # Compressed older
└── echopanel.log.3.gz
```

- Max size: 10 MB per file
- Max files: 5 (with compression for older)
- Total retention: 50 MB (~last few days)

---

## G) Session Bundle ("Run Receipt") Spec (V1)

### Bundle Structure

```
echopanel_session_<session_id>_<timestamp>.bundle/
├── receipt.json              # Metadata and config
├── events.ndjson             # State transitions, WS events
├── metrics.ndjson            # 1 Hz metric samples
├── transcript_realtime.json  # As-received transcript
├── transcript_final.json     # Post-diarization final
├── drops_summary.json        # Drop analysis
├── audio_manifest.json       # Audio file references
└── logs/
    ├── client.log            # Structured client logs
    └── server.log            # Server stdout/stderr
```

### File Specifications

#### 1. receipt.json
```json
{
  "receipt_version": "1.0",
  "session_id": "uuid",
  "created_at": "2026-02-11T12:34:56Z",
  "client_info": {
    "app_version": "0.2.0",
    "build": "123",
    "os_version": "macOS 14.2",
    "machine_id": "hashed_identifier"
  },
  "server_info": {
    "provider": "faster-whisper",
    "model_id": "base.en",
    "vad_enabled": true,
    "diarization_enabled": false
  },
  "config": {
    "audio_source": "both",
    "sample_rate": 16000,
    "chunk_seconds": 2
  },
  "session_summary": {
    "started_at": "2026-02-11T12:30:00Z",
    "ended_at": "2026-02-11T12:45:30Z",
    "duration_seconds": 930,
    "total_transcript_segments": 156,
    "dropped_frames_total": 12,
    "max_queue_fill_ratio": 0.45
  },
  "flags": {
    "has_audio": false,
    "has_transcript": true,
    "ended_gracefully": true,
    "errors_encountered": false
  }
}
```

#### 2. events.ndjson (Line-delimited JSON)
```json
{"timestamp": 1707676800.123, "type": "session_start", "session_id": "uuid", "attempt_id": "uuid"}
{"timestamp": 1707676800.456, "type": "ws_connect", "connection_id": "uuid"}
{"timestamp": 1707676800.789, "type": "ws_status", "state": "streaming"}
{"timestamp": 1707676801.000, "type": "first_audio_frame", "source": "system"}
{"timestamp": 1707676803.500, "type": "first_asr", "source": "system", "text_preview": "Hello..."}
{"timestamp": 1707677000.000, "type": "frame_drop", "source": "mic", "dropped_total": 1}
{"timestamp": 1707677730.000, "type": "ws_status", "state": "backpressure", "message": "..."}
{"timestamp": 1707677730.000, "type": "session_end", "finalization": "complete"}
```

#### 3. metrics.ndjson (1 Hz samples)
```json
{"timestamp": 1707676801.000, "source": "system", "queue_depth": 0, "queue_fill_ratio": 0.0, "dropped_recent": 0, "avg_infer_ms": 0, "realtime_factor": 0}
{"timestamp": 1707676802.000, "source": "system", "queue_depth": 2, "queue_fill_ratio": 0.04, "dropped_recent": 0, "avg_infer_ms": 420, "realtime_factor": 0.21}
```

#### 4. drops_summary.json
```json
{
  "total_dropped_frames": 12,
  "drop_intervals": [
    {"start": 1707677000.000, "end": 1707677002.000, "count": 5, "source": "mic", "trigger": "queue_full"}
  ],
  "by_source": {
    "system": 3,
    "mic": 9
  }
}
```

#### 5. audio_manifest.json
```json
{
  "note": "Audio files not included by default for privacy",
  "included": false,
  "files": [
    {
      "filename": "session_uuid_system_1707676800.pcm",
      "source": "system",
      "format": "pcm_s16le",
      "sample_rate": 16000,
      "channels": 1,
      "duration_seconds": 930,
      "size_bytes": 29760000,
      "sha256": "abc123...",
      "included": false
    }
  ],
  "opt_in_instructions": "To include audio, enable 'Share audio samples' in Settings"
}
```

### Safety Rules

1. **Default: No Raw Audio** - Audio files referenced but not included
2. **Opt-in Required** - User must explicitly enable audio sharing
3. **Checksums** - SHA-256 for all files for integrity verification
4. **PII Redaction** - Machine IDs hashed, paths sanitized
5. **Size Limits** - Bundle max 50 MB (without audio)

---

## H) Repro / Replay Protocol (V1)

### Goal
Enable engineers to replay a session's audio through the ASR pipeline to reproduce issues.

### Replay Tool Spec: `replay_audio.py`

#### Inputs
| Argument | Type | Description |
|----------|------|-------------|
| `--session-bundle` | Path | Path to session bundle directory |
| `--audio-file` | Path | Alternative: direct PCM file |
| `--config` | Path | JSON config (from receipt.json) |
| `--source` | String | "system" or "mic" |
| `--speed` | Float | Playback speed (1.0 = realtime, 2.0 = 2x) |

#### Outputs
| Output | Format | Description |
|--------|--------|-------------|
| `transcript.json` | JSON | Generated transcript |
| `metrics.ndjson` | NDJSON | Metrics during replay |
| `comparison.json` | JSON | Diff vs original transcript |
| Console | Text | Real-time ASR output |

#### Acceptance Criteria
1. Replay produces deterministic transcript (same audio → same text)
2. Metrics comparable to original (within 10% for latency)
3. Frame drops reproducible under same queue constraints
4. Exit code 0 on success, 1 on mismatch (with `--verify`)

#### Example Usage
```bash
# Replay from bundle
python scripts/replay_audio.py \
  --session-bundle ./echopanel_session_uuid_20260211.bundle \
  --speed 1.0 \
  --output ./replay_results/

# Compare to original
diff ./replay_results/transcript.json \
     ./echopanel_session_uuid_20260211.bundle/transcript_final.json

# Replay with specific constraints (reproduce backpressure)
python scripts/replay_audio.py \
  --audio-file ./audio.pcm \
  --config ./config.json \
  --queue-max 10 \
  --speed 2.0
```

### Current State
- **Status:** ❌ Tool does not exist
- **Gap:** No way to reproduce ASR issues offline
- **Prerequisites:** Session bundle format (Section G)

---

## I) Patch Plan (PR-Sized)

### PR 1: Structured Logging Foundation
| Field | Value |
|-------|-------|
| **Name** | Add structured logging with correlation IDs |
| **Impact** | High (all debugging) |
| **Effort** | Medium |
| **Risk** | Low |
| **Files** | `AppState.swift`, `WebSocketStreamer.swift`, `BackendManager.swift`, `SessionStore.swift` |
| **Validation** | Logs contain session_id, attempt_id; receipt.json shows correct IDs |

**Changes:**
- Add `Logger` wrapper with structured JSON output
- Add `session_id`, `attempt_id`, `connection_id` to all log calls
- Create rotating log file in Application Support

### PR 2: Server-Side Metrics Registry
| Field | Value |
|-------|-------|
| **Name** | Add server-side metrics registry and enhanced WS metrics |
| **Impact** | High (observability) |
| **Effort** | Medium |
| **Risk** | Low |
| **Files** | `ws_live_listener.py`, new `metrics.py` |
| **Validation** | metrics.ndjson in bundle shows 1Hz samples with all fields |

**Changes:**
- Create `MetricsRegistry` class with counters/gauges
- Enhance `_metrics_loop()` with new fields (provider, model_id, etc.)
- Add server startup metrics dump

### PR 3: Session Bundle Generation
| Field | Value |
|-------|-------|
| **Name** | Implement session bundle export with all artifacts |
| **Impact** | High (support/debugging) |
| **Effort** | Medium |
| **Risk** | Medium (privacy) |
| **Files** | `AppState.swift`, `SessionStore.swift`, new `SessionBundle.swift` |
| **Validation** | Export creates valid bundle; receipt.json passes schema validation |

**Changes:**
- Create `SessionBundle` builder class
- Collect events, metrics, logs during session
- Generate all bundle files on export
- Implement audio manifest (without audio by default)

### PR 4: Audio Replay Tool
| Field | Value |
|-------|-------|
| **Name** | Create replay_audio.py for session reproduction |
| **Impact** | Medium (engineering velocity) |
| **Effort** | Medium |
| **Risk** | Low |
| **Files** | New `scripts/replay_audio.py`, `server/tools/` updates |
| **Validation** | Replay of captured session produces matching transcript |

**Changes:**
- Create replay tool with PCM playback
- Integrate with ASR pipeline
- Add transcript comparison/diff

### PR 5: Log Redaction and Privacy
| Field | Value |
|-------|-------|
| **Name** | Implement log redaction rules and audio opt-in |
| **Impact** | High (privacy/security) |
| **Effort** | Small |
| **Risk** | Low |
| **Files** | All logging files, `SettingsView` |
| **Validation** | No tokens/paths in logs; audio only with opt-in |

**Changes:**
- Add redaction patterns for tokens, paths
- Add Settings toggle for audio inclusion
- Encrypt audio in bundles if included

### PR 6: Diagnostics Panel Enhancements
| Field | Value |
|-------|-------|
| **Name** | Enhanced DiagnosticsView with real-time metrics |
| **Impact** | Medium (user support) |
| **Effort** | Small |
| **Risk** | Low |
| **Files** | `MeetingListenerApp.swift` (DiagnosticsView) |
| **Validation** | Panel shows live metrics graph, recent events |

**Changes:**
- Add metrics history chart
- Add recent events log viewer
- Add "Copy session ID" button

---

## Appendix: Evidence Citations

All claims in this audit are backed by code inspection:

| Claim | File | Lines |
|-------|------|-------|
| SessionStore auto-save interval | `SessionStore.swift` | L24 |
| Metrics struct definition | `WebSocketStreamer.swift` | L4-14 |
| Server metrics loop | `ws_live_listener.py` | L326-391 |
| Debug bundle export | `AppState.swift` | L746-795 |
| Queue drop logging | `ws_live_listener.py` | L256-267 |
| Correlation IDs missing | All log calls | No IDs present |
| Audio dump feature | `ws_live_listener.py` | L183-226 |
| Recovery marker | `SessionStore.swift` | L159-174 |

---

## Persona Findings Summary

### Forensic Debugger
- **Finding:** No event timeline makes reconstructing session flow impossible
- **Priority:** Session bundle (Section G) is critical

### SRE / Reliability Engineer
- **Finding:** Metrics exist but aren't persisted; queue thresholds hardcoded
- **Priority:** Metrics registry + persistence (PR 2)

### Support/Customer Success
- **Finding:** Debug bundle incomplete; no session ID for lookup
- **Priority:** Bundle completeness + correlation IDs (PR 1, 3)

### Security/Privacy Steward
- **Finding:** Raw audio captured without explicit consent; tokens may leak in logs
- **Priority:** Redaction rules + opt-in (PR 5)
