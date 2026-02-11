# EchoPanel Observability Implementation Guide

**Status:** Implemented (Phase 0B)  
**Date:** 2026-02-11  
**Version:** 1.0

## Overview

This document describes the observability infrastructure implemented in EchoPanel Phase 0B, including structured logging, metrics collection, session bundles, and diagnostic tools.

## Features Implemented

### 1. Structured Logging (Swift Client)

**File:** `macapp/MeetingListenerApp/Sources/StructuredLogger.swift`

The `StructuredLogger` provides JSON-structured logging with correlation IDs:

```swift
// Usage examples
StructuredLogger.shared.info("Session started", metadata: ["audio_source": "both"])
StructuredLogger.shared.error("ASR failed", error: error, metadata: ["source": "mic"])

// With correlation context
StructuredLogger.shared.withContext(
    sessionId: sessionId,
    attemptId: attemptId,
    connectionId: connectionId
) {
    StructuredLogger.shared.info("WebSocket connected")
}
```

**Features:**
- JSON output format for machine parsing
- Log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- Automatic redaction of tokens, API keys, and file paths with PII
- Sampling for high-frequency events (e.g., audio frames)
- Rotating log files (5 files × 10 MB max)
- Correlation ID propagation

**Log Output Format:**
```json
{
  "timestamp": "2026-02-11T12:34:56.789Z",
  "level": "INFO",
  "message": "Session started",
  "component": "AppState",
  "function": "startSession",
  "line": 485,
  "context": {
    "session_id": "uuid",
    "attempt_id": "uuid",
    "connection_id": "uuid"
  },
  "metadata": {
    "audio_source": "both"
  }
}
```

**Log Locations:**
- Console: OS unified logging (Console.app)
- File: `~/Library/Application Support/com.echopanel/logs/echopanel.log`

### 2. Correlation IDs

**Implementation:** `WebSocketStreamer.swift`, `ws_live_listener.py`

Three levels of correlation IDs track sessions across reconnects:

| ID | Scope | Lifetime | Purpose |
|----|-------|----------|---------|
| `session_id` | User session | Start → End | Stable across entire recording |
| `attempt_id` | Start attempt | Each `startSession()` call | Distinguish user-initiated restarts |
| `connection_id` | WebSocket | Each WS connection | Track transport-level reconnects |

**Usage:**
```swift
// Client sends IDs in start message
{
  "type": "start",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid"
}

// Server echoes in responses
{
  "type": "metrics",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid",
  ...
}
```

### 3. Server Metrics Registry (Python)

**File:** `server/services/metrics_registry.py`

Lightweight in-memory metrics collection:

```python
from server.services.metrics_registry import get_registry

registry = get_registry()
registry.inc_counter("audio_bytes_received", amount=len(chunk), labels={"source": "system"})
registry.set_gauge("queue_depth", queue_depth, labels={"source": "mic"})
registry.observe_histogram("inference_time_ms", processing_time)
```

**Available Metrics:**

| Metric | Type | Description |
|--------|------|-------------|
| `audio_bytes_received` | Counter | Total audio bytes by source |
| `audio_frames_dropped` | Counter | Dropped frames due to backpressure |
| `asr_chunks_processed` | Counter | Successfully processed chunks |
| `asr_errors` | Counter | Processing errors |
| `ws_connections_total` | Counter | Total WebSocket connections |
| `ws_disconnects_total` | Counter | Total disconnects |
| `queue_depth` | Gauge | Current queue size by source |
| `active_sessions` | Gauge | Number of active sessions |
| `processing_lag_seconds` | Gauge | Current processing lag |
| `inference_time_ms` | Histogram | ASR inference time distribution |
| `processing_time_ms` | Histogram | Total processing time distribution |

### 4. Enhanced WebSocket Metrics

**File:** `server/api/ws_live_listener.py`

Metrics emitted at 1 Hz per source:

```json
{
  "type": "metrics",
  "session_id": "uuid",
  "attempt_id": "uuid",
  "connection_id": "uuid",
  "source": "system",
  "queue_depth": 12,
  "queue_max": 48,
  "queue_fill_ratio": 0.25,
  "dropped_total": 5,
  "dropped_recent": 0,
  "dropped_chunks_last_10s": 0,
  "avg_infer_ms": 450.5,
  "avg_processing_ms": 450.5,
  "realtime_factor": 0.23,
  "backlog_seconds": 0.5,
  "provider": "faster-whisper",
  "model_id": "base.en",
  "vad_enabled": true,
  "sources_active": ["system", "mic"],
  "timestamp": 1707676800.123
}
```

**UI Thresholds:**

| State | Queue Fill | Realtime Factor | Backlog |
|-------|------------|-----------------|---------|
| `normal` | < 70% | < 0.8 | < 1s |
| `buffering` | 70-85% | 0.8-1.2 | 1-3s |
| `overloaded` | > 85% | > 1.2 | > 3s |

### 5. Session Bundle Builder

**File:** `macapp/MeetingListenerApp/Sources/SessionBundle.swift`

Automatically collects session artifacts for debugging:

```swift
// Bundle is created automatically on session start
let bundle = SessionBundleManager.shared.createBundle(for: sessionId)

// Events recorded throughout session
bundle.recordEvent(.wsConnect)
bundle.recordMetrics(metrics)
bundle.recordTranscriptSegment(segment)

// Export when needed
try await bundle.exportBundle(to: destinationURL)
```

**Bundle Contents:**

```
echopanel_session_<id>_<timestamp>.bundle/
├── receipt.json              # Metadata and configuration
├── events.ndjson             # State transitions, WS events
├── metrics.ndjson            # 1 Hz metric samples
├── transcript_realtime.json  # As-received transcript
├── transcript_final.json     # Post-diarization final
├── drops_summary.json        # Frame drop analysis
├── audio_manifest.json       # Audio file references
└── logs/
    ├── client.log            # Structured client logs
    └── server.log            # Server stdout/stderr
```

**Privacy Controls:**
- Raw audio NOT included by default
- User must explicitly enable audio sharing
- Machine IDs are hashed (SHA-256)
- File paths sanitized

**receipt.json Example:**
```json
{
  "receipt_version": "1.0",
  "session_id": "uuid",
  "created_at": "2026-02-11T12:34:56Z",
  "client_info": {
    "app_version": "0.2.0",
    "os_version": "macOS 14.2",
    "machine_id": "a1b2c3d4..."
  },
  "server_info": {
    "provider": "faster-whisper",
    "model_id": "base.en",
    "vad_enabled": true
  },
  "session_summary": {
    "started_at": "2026-02-11T12:30:00Z",
    "duration_seconds": 930,
    "total_transcript_segments": 156,
    "dropped_frames_total": 12,
    "max_queue_fill_ratio": 0.45
  },
  "flags": {
    "has_audio": false,
    "has_transcript": true
  }
}
```

### 6. Audio Replay Tool

**File:** `scripts/replay_audio.py`

Reproduce session issues by replaying recorded audio:

```bash
# Replay from session bundle
python scripts/replay_audio.py \
  --session-bundle ./session.bundle \
  --output ./replay_results/

# Replay standalone PCM file
python scripts/replay_audio.py \
  --audio-file ./recording.pcm \
  --source system \
  --output ./results/

# Compare with original transcript
python scripts/replay_audio.py \
  --session-bundle ./session.bundle \
  --compare \
  --verify  # Exit code 1 if mismatch
```

**Output:**
- `transcript.json` - Generated transcript
- `comparison.json` - Diff vs original (if --compare)
- Console output with timing

## Testing

**Unit Tests:** `macapp/MeetingListenerApp/Tests/ObservabilityTests.swift`

```bash
cd macapp/MeetingListenerApp
swift test --filter ObservabilityTests
```

**Manual Testing:**

1. **Verify structured logging:**
   ```bash
   # Tail client logs
   tail -f ~/Library/Application\ Support/com.echopanel/logs/echopanel.log | jq .
   ```

2. **Verify correlation IDs:**
   - Start a session
   - Check logs contain session_id, attempt_id, connection_id

3. **Verify session bundle:**
   - Record a session
   - Export debug bundle
   - Unzip and verify all files present

4. **Verify replay tool:**
   ```bash
   python scripts/replay_audio.py --help
   ```

## Integration Points

### AppState.swift
- Sets logging context on session start
- Creates SessionBundle automatically
- Records events at key transitions

### WebSocketStreamer.swift
- Generates correlation IDs on connect
- Includes IDs in all WS messages
- Parses enhanced metrics from server

### ws_live_listener.py
- Receives correlation IDs from client
- Includes IDs in all responses
- Updates metrics registry

## Troubleshooting

### Logs not appearing
- Check `enableFileOutput` in StructuredLogger configuration
- Verify Application Support directory permissions
- Check log level (minLevel) setting

### Missing correlation IDs
- Ensure `connect(sessionID:attemptID:)` is called with attempt ID
- Check server is receiving and echoing IDs

### Bundle export fails
- Check disk space
- Verify session bundle exists in SessionBundleManager
- Check file permissions

### Replay tool errors
- Ensure audio file exists and is valid PCM
- Verify ASR provider is available
- Check Python dependencies installed

## Future Enhancements

1. **Centralized logging:** Ship logs to external system (Loki, CloudWatch)
2. **Metrics dashboard:** Real-time Grafana dashboard
3. **Alerting:** Automatic alerts on high drop rates or latency
4. **Distributed tracing:** OpenTelemetry integration
5. **Audio fingerprinting:** Verify replay authenticity

## References

- Original Audit: `docs/audit/OBSERVABILITY_RUN_RECEIPTS_PHASE0B_20260211.md`
- Session Bundle Spec: Section G of audit document
- Correlation ID Scheme: Section D of audit document
