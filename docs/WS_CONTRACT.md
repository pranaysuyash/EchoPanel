# WebSocket Contract: Live Listener v0.1

This document is the source of truth for the client/server WebSocket protocol between the macOS app and the backend for v0.1.

## Endpoint
- WebSocket path: `/ws/live-listener`
- Transport: WebSocket over TLS in production (`wss://`)

## Message types (overview)
- Client to server:
  - JSON control messages: `start`, `stop`
  - Binary audio messages: PCM frames, `pcm_s16le`, mono, 16 kHz
- Server to client:
  - ASR events: `asr_partial`, `asr_final`
  - Analysis events: `cards_update`, `entities_update`
  - Status events: `status`
  - Finalization: `final_summary`

## Binary framing (client to server)
- Each binary message is a single audio frame.
- Encoding: PCM signed 16-bit little-endian (`pcm_s16le`)
- Sample rate: 16000 Hz
- Channels: 1 (mono)
- Suggested frame duration: 20 ms
  - Samples per frame: `16000 * 0.02 = 320`
  - Bytes per frame: `320 samples * 2 bytes = 640`
- Timing:
  - The backend should treat frame arrival order as the clock for streaming ASR.
  - The client should send frames at approximately real time cadence.

## JSON control messages (client to server)
All JSON messages are UTF-8 text frames.

### `start`
Schema:
```json
{
  "type": "start",
  "session_id": "uuid",
  "sample_rate": 16000,
  "format": "pcm_s16le",
  "channels": 1
}
```

Notes:
- `session_id` must be stable for the session.
- After `start`, the client begins sending binary audio frames.

Example:
```json
{"type":"start","session_id":"2E3B2BC2-0F6D-46E0-8B7A-5D80A8B8BE68","sample_rate":16000,"format":"pcm_s16le","channels":1}
```

### `stop`
Schema:
```json
{
  "type": "stop",
  "session_id": "uuid"
}
```

Example:
```json
{"type":"stop","session_id":"2E3B2BC2-0F6D-46E0-8B7A-5D80A8B8BE68"}
```

## Server events (server to client)
All events are JSON UTF-8 text frames.

### ASR: `asr_partial`
Schema:
```json
{
  "type": "asr_partial",
  "t0": 123.4,
  "t1": 126.2,
  "text": "we should ship by friday",
  "stable": false
}
```

Example:
```json
{"type":"asr_partial","t0":123.40,"t1":126.20,"text":"we should ship by friday","stable":false}
```

### ASR: `asr_final`
Schema:
```json
{
  "type": "asr_final",
  "t0": 123.4,
  "t1": 126.2,
  "text": "We should ship by Friday.",
  "stable": true
}
```

Example:
```json
{"type":"asr_final","t0":123.40,"t1":126.20,"text":"We should ship by Friday.","stable":true}
```

### Analysis: `cards_update`
Schema:
```json
{
  "type": "cards_update",
  "actions": [{"text":"...","owner":"...","due":"YYYY-MM-DD","confidence":0.0,"evidence":[{"t0":0.0,"t1":1.2,"quote":"..."}]}],
  "decisions": [{"text":"...","confidence":0.0,"evidence":[{"t0":0.0,"t1":1.2,"quote":"..."}]}],
  "risks": [{"text":"...","confidence":0.0,"evidence":[{"t0":0.0,"t1":1.2,"quote":"..."}]}],
  "window": {"t0": 0.0, "t1": 420.0}
}
```

Example:
```json
{"type":"cards_update","actions":[{"text":"Send revised proposal","owner":"Pranay","due":"2026-01-23","confidence":0.82,"evidence":[{"t0":310.2,"t1":316.9,"quote":"I'll send the revised proposal by Tuesday."}]}],"decisions":[{"text":"Ship v0.1 on Friday","confidence":0.74,"evidence":[{"t0":120.1,"t1":126.2,"quote":"We should ship by Friday."}]}],"risks":[{"text":"Audio quality may be poor without permissions","confidence":0.61,"evidence":[{"t0":30.0,"t1":34.2,"quote":"If we can't capture system audio, we are stuck."}]}],"window":{"t0":0,"t1":600}}
```

### Analysis: `entities_update`
Schema:
```json
{
  "type": "entities_update",
  "people": [{"name":"...","last_seen":123.4,"confidence":0.0}],
  "orgs": [{"name":"...","last_seen":123.4,"confidence":0.0}],
  "dates": [{"name":"...","last_seen":123.4,"confidence":0.0}],
  "projects": [{"name":"...","last_seen":123.4,"confidence":0.0}],
  "topics": [{"name":"...","last_seen":123.4,"confidence":0.0}]
}
```

Example:
```json
{"type":"entities_update","people":[{"name":"Alex","last_seen":222.3,"confidence":0.77}],"orgs":[{"name":"EchoPanel","last_seen":100.0,"confidence":0.88}],"dates":[{"name":"Friday","last_seen":124.2,"confidence":0.71}],"projects":[{"name":"v0.1","last_seen":123.9,"confidence":0.69}],"topics":[{"name":"ScreenCaptureKit","last_seen":240.4,"confidence":0.74}]}
```

### Status: `status`
Schema:
```json
{
  "type": "status",
  "state": "streaming|reconnecting|error",
  "message": "..."
}
```

Examples:
```json
{"type":"status","state":"streaming","message":"Connected"}
```

```json
{"type":"status","state":"reconnecting","message":"Retrying in 2s"}
```

### Finalization: `final_summary`
Schema:
```json
{
  "type": "final_summary",
  "markdown": "...",
  "json": {}
}
```

Example:
```json
{"type":"final_summary","markdown":"# Summary\\n...","json":{"session_id":"2E3B2BC2-0F6D-46E0-8B7A-5D80A8B8BE68","actions":[],"decisions":[],"risks":[],"entities":{}}}
```

## Error handling expectations
- If the server cannot process audio, it sends a `status` with `state:"error"` and a human-readable `message`.
- If the client disconnects unexpectedly, the server may terminate analysis for that session unless it supports resumption (not required in v0.1).

