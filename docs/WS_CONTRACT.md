# WebSocket + Local Docs API Contract (v0.2)

This is the current source of truth for the live listener protocol implemented in:
- `/Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py`
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`

## Transport and endpoint
- WebSocket endpoint: `/ws/live-listener`
- App URL policy:
  - Localhost backends (`127.0.0.1`, `localhost`, `::1`) use `ws://` and `http://`.
  - Non-local backends default to `wss://` and `https://`.
  - Evidence: `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/BackendConfig.swift`

## Authentication
- Controlled by env var: `ECHOPANEL_WS_AUTH_TOKEN`
- When unset/empty:
  - WebSocket and documents API are open (local-dev default).
- When set:
  - Accepted token inputs (priority order):
    1) `?token=...` query parameter
    2) `x-echopanel-token` header
    3) `Authorization: Bearer ...` header
  - Current client transport:
    - EchoPanel client sends `Authorization` + `x-echopanel-token` headers.
    - Query-token support remains server-side for backward compatibility.
- Unauthorized websocket behavior:
  - Server sends `{"type":"status","state":"error","message":"Unauthorized websocket connection"}`
  - Then closes with close code `1008`.
- Unauthorized HTTP documents behavior:
  - Returns `401 {"detail":"Unauthorized"}`.

## Client -> server messages
All structured messages are UTF-8 JSON text frames.

### `start`
```json
{
  "type": "start",
  "session_id": "uuid-string",
  "attempt_id": "uuid-string (optional but recommended)",
  "connection_id": "uuid-string (optional; diagnostics only)",
  "sample_rate": 16000,
  "format": "pcm_s16le",
  "channels": 1,
  "client_features": {
    "clock_drift_compensation_enabled": false,
    "client_vad_enabled": false,
    "clock_drift_telemetry_enabled": true,
    "client_vad_telemetry_enabled": true
  }
}
```
- Server currently requires exactly `16000` / `pcm_s16le` / `1`.
- On mismatch, server sends:
  - `{"type":"error","message":"Unsupported audio format: ..."}`
  - then closes connection.
- `client_features` is optional; these flags are telemetry/staging controls and do not change default processing behavior yet.
- `attempt_id` is used to correlate a single start attempt across reconnects and to drop late/out-of-order messages.

### `audio` (preferred)
```json
{
  "type": "audio",
  "source": "system | mic | microphone",
  "data": "base64_pcm16_bytes"
}
```
- `source` defaults to `system` when omitted.
- Multi-source streams create independent ASR queues/tasks per source.

### Binary frame (legacy fallback)
- Raw PCM16 bytes in binary websocket frames are still accepted.
- If the binary payload starts with the v1 header, the server will extract `source` from the header.
- Otherwise, legacy binary frames are treated as `source="system"`.

#### Binary frame (v1 header)
Header format:
- Bytes 0-1: ASCII `"EP"`
- Byte 2: Version `1`
- Byte 3: Source (`0` = `system`, `1` = `mic`)
- Bytes 4..: Raw PCM16 mono @ 16kHz

This is the preferred binary encoding used by the macOS client when `BackendConfig.useBinaryAudioFrames` is enabled.

### `stop`
```json
{
  "type": "stop",
  "session_id": "uuid-string"
}
```
- Server flushes ASR, cancels periodic analysis loop, runs finalization, emits `final_summary`, and closes the socket.

## Server -> client events

### `status`
```json
{
  "type": "status",
  "session_id": "uuid-string (optional)",
  "attempt_id": "uuid-string (optional)",
  "connection_id": "uuid-string (optional)",
  "state": "streaming | warning | backpressure | error",
  "message": "human-readable message",
  "dropped_frames": 3
}
```
- `dropped_frames` appears for backpressure warnings.

### `asr_partial` / `asr_final`
```json
{
  "type": "asr_partial | asr_final",
  "session_id": "uuid-string (optional)",
  "attempt_id": "uuid-string (optional)",
  "connection_id": "uuid-string (optional)",
  "text": "recognized text",
  "t0": 12.3,
  "t1": 14.0,
  "confidence": 0.88,
  "source": "system | mic"
}
```
- The protocol supports both event types.
- Current `faster-whisper` provider emits final segments only.

### `entities_update`
```json
{
  "type": "entities_update",
  "session_id": "uuid-string (optional)",
  "attempt_id": "uuid-string (optional)",
  "connection_id": "uuid-string (optional)",
  "people": [],
  "orgs": [],
  "dates": [],
  "projects": [],
  "topics": []
}
```

### `cards_update`
```json
{
  "type": "cards_update",
  "session_id": "uuid-string (optional)",
  "attempt_id": "uuid-string (optional)",
  "connection_id": "uuid-string (optional)",
  "actions": [],
  "decisions": [],
  "risks": [],
  "window": { "t0": 0.0, "t1": 600.0 }
}
```

### `metrics`
```json
{
  "type": "metrics",
  "session_id": "uuid-string (optional)",
  "attempt_id": "uuid-string (optional)",
  "connection_id": "uuid-string (optional)",
  "source": "system | mic",
  "queue_depth": 1,
  "queue_max": 48,
  "queue_fill_ratio": 0.02,
  "dropped_total": 0,
  "dropped_recent": 0,
  "avg_infer_ms": 420.0,
  "realtime_factor": 0.21,
  "client_clock_drift_compensation_enabled": false,
  "client_vad_enabled": false,
  "source_clock_spread_ms": 0.0,
  "max_source_clock_spread_ms": 0.0
}
```
- Emitted about once per second per active source.
- `source_clock_spread_ms`/`max_source_clock_spread_ms` expose cross-source ASR timeline spread telemetry groundwork.

### `final_summary`
```json
{
  "type": "final_summary",
  "markdown": "# Notes ...",
  "json": {
    "session_id": "uuid-string",
    "transcript": [],
    "actions": [],
    "decisions": [],
    "risks": [],
    "entities": {},
    "diarization": [],
    "client_features": {
      "clock_drift_compensation_enabled": false,
      "client_vad_enabled": false,
      "clock_drift_telemetry_enabled": true,
      "client_vad_telemetry_enabled": true
    },
    "clock_spread_ms": {
      "last": 0.0,
      "max": 0.0
    }
  }
}
```
- `json.transcript` is speaker-labeled when diarization succeeds.
- `json.diarization` includes flattened source-tagged diarization segments.

## Finalization behavior
- Diarization is session-end only (not live), controlled by:
  - `ECHOPANEL_DIARIZATION=1`
  - optional `ECHOPANEL_DIARIZATION_MAX_SECONDS` cap.
- NLP extraction (`cards`, `entities`, summary markdown) runs on transcript snapshot after ASR flush.

## Local documents API (RAG MVP)
All endpoints are included by `/Users/pranay/Projects/EchoPanel/server/main.py`.

- `GET /documents`
  - Returns indexed document summaries.
- `POST /documents/index`
  - Body:
    ```json
    { "title": "Doc", "text": "content", "source": "local", "document_id": "optional" }
    ```
- `POST /documents/query`
  - Body:
    ```json
    { "query": "pricing auth", "top_k": 5 }
    ```
- `DELETE /documents/{document_id}`
  - Deletes one indexed document.

## Compatibility notes
- JSON `audio` frames are the expected v0.2 path.
- Binary frame support remains for backward compatibility only.
