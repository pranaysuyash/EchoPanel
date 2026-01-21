# WebSocket Contract: Live Meeting Listener v0.1

## Endpoint
- Path: `/ws/live-listener`
- Protocol: WebSocket
- Audio framing: binary messages of PCM16 16 kHz mono

## Control messages: client to server
```json
{"type":"start","session_id":"<uuid>","sample_rate":16000,"format":"pcm_s16le","channels":1,"client_version":"0.1"}
```

```json
{"type":"stop","session_id":"<uuid>"}
```

## Server to client events
### ASR partial
```json
{"type":"asr_partial","t0":12.40,"t1":14.20,"text":"we should ship by friday","stable":false}
```

### ASR final
```json
{"type":"asr_final","t0":12.40,"t1":14.20,"text":"We should ship by Friday.","stable":true}
```

### Cards update
```json
{
  "type":"cards_update",
  "window":{"t0":0,"t1":420},
  "actions":[
    {"text":"Ship v0.1 by Friday","owner":"Ava","due":"2024-06-21","confidence":0.78,
     "evidence":[{"t0":12.4,"t1":14.2,"quote":"we should ship by Friday"}]}
  ],
  "decisions":[
    {"text":"Use ScreenCaptureKit for system audio","confidence":0.83,
     "evidence":[{"t0":32.0,"t1":36.1,"quote":"use ScreenCaptureKit"}]}
  ],
  "risks":[
    {"text":"Backend ASR latency under load","confidence":0.52,
     "evidence":[{"t0":88.0,"t1":92.4,"quote":"latency might spike"}]}
  ]
}
```

### Entities update
```json
{
  "type":"entities_update",
  "people":[{"name":"Ava","last_seen":14.2,"confidence":0.88}],
  "orgs":[{"name":"Antigravity","last_seen":60.0,"confidence":0.75}],
  "dates":[{"name":"Friday","last_seen":14.2,"confidence":0.64}],
  "projects":[{"name":"EchoPanel v0.1","last_seen":120.5,"confidence":0.71}],
  "topics":[{"name":"ScreenCaptureKit","last_seen":36.1,"confidence":0.8}]
}
```

### Status update
```json
{"type":"status","state":"streaming","message":"Connected"}
```

### Final summary
```json
{
  "type":"final_summary",
  "markdown":"# Summary\n- Ship v0.1 by Friday",
  "json":{
    "actions":[{"text":"Ship v0.1 by Friday","confidence":0.78}],
    "decisions":[{"text":"Use ScreenCaptureKit","confidence":0.83}],
    "risks":[{"text":"ASR latency under load","confidence":0.52}]
  }
}
```

## Binary framing
- Each binary WebSocket message is a single PCM frame
- Encoding: signed int16 little-endian, mono, 16 kHz
- Target frame size: 20 ms = 320 samples = 640 bytes
- Client must send a JSON start message before any audio frames

## Error handling
- Server may emit `{"type":"status","state":"reconnecting","message":"backend unavailable"}`
- Client should retry with exponential backoff, max 10 seconds
