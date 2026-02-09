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
  "sample_rate": 16000,
  "format": "pcm_s16le",
  "channels": 1
}
```
- Server currently requires exactly `16000` / `pcm_s16le` / `1`.
- On mismatch, server sends:
  - `{"type":"error","message":"Unsupported audio format: ..."}`
  - then closes connection.

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
- Binary frames are treated as `source="system"`.

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
  "actions": [],
  "decisions": [],
  "risks": [],
  "window": { "t0": 0.0, "t1": 600.0 }
}
```

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
    "diarization": []
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
