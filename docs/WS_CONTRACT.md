# WebSocket Contract v0.1

## Endpoint
`/ws/asr`

## Transport
- WebSocket
- Binary frames for PCM data
- JSON for control and event messages

## Binary framing
- Format: PCM16 little-endian
- Sample rate: 16 kHz
- Channels: 1
- Frame size: 20 ms, 320 samples, 640 bytes

## Client to server JSON messages
Start:
```json
{"type":"start","session_id":"uuid","sample_rate":16000,"format":"pcm_s16le","channels":1}
```

Stop:
```json
{"type":"stop","session_id":"uuid"}
```

## Server to client JSON messages
ASR partial:
```json
{"type":"asr_partial","t0":123.4,"t1":126.2,"text":"we should ship by friday","stable":false}
```

ASR final:
```json
{"type":"asr_final","t0":123.4,"t1":126.2,"text":"We should ship by Friday.","stable":true}
```

Cards update:
```json
{
  "type":"cards_update",
  "actions":[
    {"text":"Send revised proposal","owner":"Avery","due":"2024-03-01","confidence":0.86,"evidence":[{"t0":120.0,"t1":126.2,"quote":"I will send the proposal tomorrow"}]}
  ],
  "decisions":[
    {"text":"Ship v0.1 on Friday","confidence":0.82,"evidence":[{"t0":123.4,"t1":126.2,"quote":"We should ship by Friday"}]}
  ],
  "risks":[
    {"text":"Scope creep in review process","confidence":0.61,"evidence":[{"t0":210.0,"t1":219.2,"quote":"The review could expand beyond v0.1"}]}
  ],
  "window":{"t0":0,"t1":420}
}
```

Entities update:
```json
{
  "type":"entities_update",
  "people":[{"name":"Avery","last_seen":126.2,"confidence":0.9}],
  "orgs":[{"name":"EchoPanel","last_seen":126.2,"confidence":0.88}],
  "dates":[{"name":"Friday","last_seen":126.2,"confidence":0.77}],
  "projects":[{"name":"v0.1","last_seen":126.2,"confidence":0.84}],
  "topics":[{"name":"Launch plan","last_seen":126.2,"confidence":0.74}]
}
```

Status update:
```json
{"type":"status","state":"streaming","message":"Streaming"}
```

Final summary:
```json
{
  "type":"final_summary",
  "markdown":"## Summary\n- ...",
  "json":{
    "actions":[{"text":"Send revised proposal","owner":"Avery","due":"2024-03-01","confidence":0.86}],
    "decisions":[{"text":"Ship v0.1 on Friday","confidence":0.82}],
    "risks":[{"text":"Scope creep in review process","confidence":0.61}]
  }
}
```
