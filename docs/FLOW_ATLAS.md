# EchoPanel Flow Atlas

**Generated:** 2026-02-11  
**Status:** COMPLETE  
**Priority:** P0 - Production Documentation

---

## Flow Atlas Inventory

| ID | Flow Name | Status | Priority | Category |
|----|-----------|--------|----------|----------|
| UJ-001 | Onboarding Flow | Implemented | P0 | User Journey |
| UJ-002 | Recording Session Flow | Implemented | P0 | User Journey |
| UJ-003 | Live Playback/Review Flow | Implemented | P1 | User Journey |
| UJ-004 | Session Export Flow | Implemented | P1 | User Journey |
| UJ-005 | Session | Implemented | History & Search Flow P1 | User Journey |
| UJ-006 | Settings & Configuration Flow | Implemented | P2 | User Journey |
| UJ-007 | Permissions Request Flow | Implemented | P0 | User Journey |
| UJ-008 | Server Lifecycle Flow | Implemented | P0 | User Journey |
| UJ-009 | Session Recovery Flow | Implemented | P1 | User Journey |
| UJ-010 | Diagnostics & Debug Flow | Implemented | P2 | User Journey |
| AP-001 | Microphone Capture | Implemented | P0 | Audio Pipeline |
| AP-002 | System Audio Capture | Implemented | P0 | Audio Pipeline |
| AP-003 | Redundant Capture + Failover | Implemented | P1 | Audio Pipeline |
| AP-004 | WebSocket Audio Upload | Implemented | P0 | Audio Pipeline |
| AP-005 | VAD Pre-Filtering | Implemented | P1 | Audio Pipeline |
| AP-006 | Speaker Diarization | Implemented | P2 | Audio Pipeline |
| AP-007 | ASR Provider (faster_whisper) | Implemented | P0 | Audio Pipeline |
| AP-008 | WebSocket Streaming | Implemented | P0 | Audio Pipeline |
| ML-001 | Model Manager Initialization | Implemented | P0 | Model Lifecycle |
| ML-002 | Faster-Whisper Provider Init | Implemented | P0 | Model Lifecycle |
| ML-003 | Whisper.cpp Provider Init | Implemented | P1 | Model Lifecycle |
| ML-004 | Voxtral Realtime Provider Init | Implemented | P2 | Model Lifecycle |
| ML-005 | Capability Detection | Implemented | P1 | Model Lifecycle |
| ML-006 | Degrade Ladder Fallback | Implemented | P1 | Model Lifecycle |
| ML-007 | ASR Provider Registry | Implemented | P1 | Model Lifecycle |
| DS-001 | Session Store (Client Persistence) | Implemented | P1 | Data & Storage |
| DS-002 | RAG Document Store (Server) | Implemented | P2 | Data & Storage |
| DS-003 | Session Bundle Export | Implemented | P1 | Data & Storage |
| DS-004 | Caption/Transcript Output | Implemented | P2 | Data & Storage |
| DS-005 | Keychain Credentials | Implemented | P1 | Data & Storage |
| DS-006 | Structured Logging | Implemented | P1 | Data & Storage |
| DS-007 | Server Logs | Implemented | P2 | Data & Storage |
| DS-008 | Debug Audio Dump | Implemented | P3 | Data & Storage |
| DS-009 | UserDefaults Preferences | Implemented | P2 | Data & Storage |
| AI-001 | Entity Extraction (NER) | Implemented | P1 | Analysis |
| AI-002 | Card Extraction (Actions/Decisions/Risks) | Implemented | P1 | Analysis |
| AI-003 | Rolling Summary Generation | Implemented | P1 | Analysis |
| AI-004 | RAG Document Indexing | Implemented | P2 | Analysis |
| AI-005 | RAG Query Retrieval | Implemented | P2 | Analysis |
| AI-006 | Session-End Final Analysis Pipeline | Implemented | P1 | Analysis |
| OR-001 | Client-Side Structured Logging | Implemented | P1 | Observability |
| OR-002 | Server-Side Metrics Registry | Implemented | P1 | Observability |
| OR-003 | Concurrency Controller & Backpressure | Implemented | P0 | Observability |
| OR-004 | Server Health Checks | Implemented | P0 | Observability |
| OR-005 | WebSocket Reconnection Resilience | Implemented | P0 | Observability |
| OR-006 | Degrade Ladder | Implemented | P1 | Observability |
| OR-007 | ASR Provider Health | Implemented | P1 | Observability |
| OR-008 | WebSocket Session Metrics | Implemented | P1 | Observability |
| SP-001 | Screen Recording Permission | Implemented | P0 | Security |
| SP-002 | Microphone Permission | Implemented | P0 | Security |
| SP-003 | Keychain Credential Storage | Implemented | P1 | Security |
| SP-004 | WebSocket Audio Upload | Implemented | P0 | Security |
| SP-005 | WebSocket Control Messages | Implemented | P0 | Security |
| SP-006 | WebSocket Transcript Response | Implemented | P0 | Security |
| SP-007 | Logging with Redaction | Implemented | P1 | Security |
| SP-008 | Logging (Server) | Implemented | P2 | Security |
| SP-009 | Server Session State | Implemented | P1 | Security |
| SP-010 | Debug Audio Dump | Partial | P3 | Security |
| SP-011 | UserDefaults Configuration | Implemented | P2 | Security |

---

## Component/Module Map

### Client (macOS)

| Component | File | Purpose |
|-----------|------|---------|
| MeetingListenerApp | `MeetingListenerApp.swift` | App entry, lifecycle, menu bar |
| AppState | `AppState.swift` | Global state, session management |
| AudioCaptureManager | `AudioCaptureManager.swift` | System audio capture (ScreenCaptureKit) |
| MicrophoneCaptureManager | `MicrophoneCaptureManager.swift` | Microphone capture (AVCapture) |
| RedundantAudioCaptureManager | `RedundantAudioCaptureManager.swift` | Dual-path redundancy |
| BroadcastFeatureManager | `BroadcastFeatureManager.swift` | Screen Recording broadcast setup |
| WebSocketStreamer | `WebSocketStreamer.swift` | WebSocket client |
| ResilientWebSocket | `ResilientWebSocket.swift` | Reconnection, circuit breaker |
| BackendManager | `BackendManager.swift` | Server lifecycle, health checks |
| SessionStore | `SessionStore.swift` | Session persistence |
| SessionBundle | `SessionBundle.swift` | Debug bundle export |
| OnboardingView | `OnboardingView.swift` | First-run onboarding |
| SidePanelView | `SidePanelView.swift` | Live transcript UI |
| SessionHistoryView | `SessionHistoryView.swift` | Session history UI |
| SummaryView | `SummaryView.swift` | Summary, actions, entities UI |
| StructuredLogger | `StructuredLogger.swift` | Structured logging with correlation |
| HotKeyManager | `HotKeyManager.swift` | Global hotkey handling |
| DeviceHotSwapManager | `DeviceHotSwapManager.swift` | Audio device hot-swap |
| KeychainHelper | `KeychainHelper.swift` | Credential storage |

### Server (Python)

| Component | File | Purpose |
|-----------|------|---------|
| FastAPI App | `main.py` | HTTP endpoints, WS upgrade |
| WSLiveListener | `api/ws_live_listener.py` | WebSocket handler, session state |
| ASRStream | `services/asr_stream.py` | ASR streaming orchestration |
| VADASRWrapper | `services/vad_asr_wrapper.py` | VAD pre-filtering |
| Diarization | `services/diarization.py` | Speaker diarization |
| ProviderFasterWhisper | `services/provider_faster_whisper.py` | Faster-Whisper ASR |
| ProviderWhisperCpp | `services/provider_whisper_cpp.py` | Whisper.cpp ASR |
| ProviderVoxtralRealtime | `services/provider_voxtral_realtime.py` | Voxtral realtime ASR |
| ASRProviders | `services/asr_providers.py` | Provider registry |
| ModelPreloader | `services/model_preloader.py` | Model lifecycle manager |
| CapabilityDetector | `services/capability_detector.py` | Hardware detection |
| DegradeLadder | `services/degrade_ladder.py` | Performance fallback |
| ConcurrencyController | `services/concurrency_controller.py` | Queue/backpressure |
| MetricsRegistry | `services/metrics_registry.py` | Metrics collection |
| AnalysisStream | `services/analysis_stream.py` | NER, cards, summary |
| RAGStore | `services/rag_store.py` | Document storage |
| CaptionOutput | `services/caption_output.py` | SRT/VTT output |
| DocumentsAPI | `api/documents.py` | RAG document API |

---

## Flow Specs (Selected Key Flows)

### UJ-002: Recording Session Flow (Happy Path)

```
Trigger: User clicks "Start Listening" or Cmd+Shift+L
Preconditions: onboardingCompleted=true, serverReady=true, permissions granted

Sequence:
1. User clicks start → toggleSession() [MeetingListenerApp.swift:239]
2. Validate onboarding + backend ready
3. appState.startSession() [AppState.swift:492]
4. resetSession() - clear transcript/actions/entities
5. Generate sessionId, attemptId
6. Create SessionBundle
7. Check permissions (Screen Recording, Microphone)
8. Start audio capture:
   - If redundant: BroadcastFeatureManager.startRedundantCapture()
   - Else: AudioCaptureManager.startCapture() or MicCapture.startCapture()
9. Connect WebSocket: streamer.connect(sessionId, attemptId) [WebSocketStreamer.swift:71]
10. sessionState = .starting
11. Start silence detection, auto-save timer
12. Send WebSocket start message
13. Wait for ACK (5s timeout)
14. sessionState = .listening
15. Side panel shows live transcript

Exit: User clicks Stop → stopSession() → sessionState = .finalizing

Failure Modes:
- Screen Recording permission denied → error.state = .screenRecordingPermissionRequired
- Backend timeout (5s) → error.state = .streaming
- Audio capture fails → error.state = .systemCaptureFailed/.microphoneCaptureFailed
- WebSocket disconnect → Reconnection via ResilientWebSocket
- No audio 10s → silence warning banner
- Queue overflow → frame drops, backpressure logging

Proof: AppState.swift:492-650, MeetingListenerApp.swift:39-41, 158-160
```

### AP-001: Microphone Capture → AP-008: Transcript Output (End-to-End)

```
Trigger: startCapture() [MicrophoneCaptureManager.swift]
Preconditions: microphone permission granted, WebSocket connected

Sequence:
1. AVCaptureSession config with audio device
2. AudioEngine setup with 16kHz sample rate
3. installTap on audio output
4. onPCMFrame callback [MicrophoneCaptureManager.swift:140]
5. AudioCaptureManager framesProcessed counter
6. sendAudioFrame(frame) → WebSocketStreamer [WebSocketStreamer.swift:204]
7. JSON payload: {type: "audio", source: "mic", timestamp, pcm: base64}
8. WebSocket send with correlation IDs
9. Server: ws_live_listener receives [ws_live_listener.py:264]
10. ConcurrencyController enqueue [concurrency_controller.py:160]
11. VAD filter (if enabled) [vad_asr_wrapper.py:101]
12. ASR provider transcribe_stream [asr_stream.py:89]
13. Partial transcript events [ws_live_listener.py:622-650]
14. Final transcript events [ws_live_listener.py:652-680]
15. Client: onTranscript callback [WebSocketStreamer.swift:108]
16. AppState update: transcript, entities, actions
17. SidePanelView refresh

Latency Budget:
- Capture to send: <50ms
- Server enqueue: <100ms
- ASR inference: 400ms-2s (normal), 4s-10s (degraded)
- Transcript emit to UI: <100ms
- E2E: 0.5-3s (good), 5-12s (degraded)

Failure Modes:
- Permission revoked mid-session → capture fails
- WebSocket disconnect → ResilientWebSocket buffers (30s)
- VAD false positive → speech marked silence
- ASR OOM → provider restart
- RTF > 1.0 → degrade ladder triggers

Proof: MicrophoneCaptureManager.swift, ws_live_listener.py:264-680, asr_stream.py
```

### ML-001 + ML-002: Model Load → Warmup → Ready

```
Trigger: Server startup or first transcription request
Preconditions: Provider available, model files downloaded

Sequence:
1. initialize_model_at_startup() [model_preloader.py:84]
2. ModelManager state: UNINITIALIZED → LOADING
3. ASRProviderRegistry.get_provider() [asr_providers.py:320]
4. Provider.__init__() creates empty model
5. _get_model() on first inference:
   - Env vars: ECHOPANEL_WHISPER_MODEL, ECHOPANEL_WHISPER_DEVICE
   - Device: cpu on macOS (no Metal in CTranslate2)
   - WhisperModel(model, device, compute_type) [provider_faster_whisper.py:100]
6. _model_loaded_at timestamp
7. State: WARMING_UP (if enabled)
8. _warmup(): generate 2s silent audio, run inference [model_preloader.py:220-276]
9. State: READY, _ready_event.set()
10. Health check returns 200 OK

Model Config:
- Default: large-v3-turbo
- Device: cpu (MPS not supported in CTranslate2)
- Compute: int8 (forced on CPU)

Warmup Duration:
- Load: 2-15s
- Warmup: 100ms minimum
- Total: 2-16s

Failure Modes:
- Provider unavailable → RuntimeError, 503
- Model download fails → CTranslate2 error
- Memory OOM → crash
- Warmup timeout → still READY, logged

Proof: model_preloader.py:84-403, provider_faster_whisper.py:41-111
```

### AI-006: Session-End Final Analysis Pipeline

```
Trigger: WebSocket stop message [ws_live_listener.py:730]
Preconditions: Session started, ASR flushed, transcript available

Sequence:
1. Receive stop message
2. Signal EOF to audio queues
3. Wait for ASR flush (8s timeout)
4. Cancel running analysis tasks (5s timeout)
5. For each source: run_diarization() [diarization.py]
6. Sort transcript by t0 [ws_live_listener.py:773]
7. Merge diarization with transcript
8. Threaded analysis (no await):
   - generate_rolling_summary(transcript) [analysis_stream.py:368]
   - extract_cards(window) [analysis_stream.py:101]
   - extract_entities(window) [analysis_stream.py:178]
9. Send final_summary event [ws_live_listener.py:787-803]
   - transcript: full sorted
   - entities: extracted
   - cards: actions/decisions/risks
   - summary: markdown
10. sessionState = .idle

Timing:
- ASR flush: 8s max
- Diarization: O(session_length)
- Analysis: 5-30s depending on length
- Total: 15-45s post-stop

Failure Modes:
- ASR flush timeout → partial transcript
- Analysis timeout → empty results
- Diarization failure → no speaker labels
- Memory OOM on long sessions

Proof: ws_live_listener.py:730-803, analysis_stream.py:368-416
```

---

## Event + State Glossary

### Client States (AppState.swift)

| State | Meaning | Transitions |
|-------|---------|--------------|
| `.idle` | No active session | → .starting on startSession |
| `.starting` | Session initializing | → .listening on ACK, → .error on failure |
| `.listening` | Recording + streaming | → .finalizing on stop |
| `.finalizing` | Stop received, flushing | → .idle on complete, → .error on failure |
| `.error` | Error occurred | → .idle on reset |

### Backend Session States (SessionState)

| State | Meaning |
|-------|---------|
| `created` | Session ID allocated |
| `starting` | Audio queues starting |
| `running` | Processing audio |
| `stopping` | Stop received, flushing |
| `stopped` | Cleanup complete |

### WebSocket Message Types

| Direction | Type | Purpose |
|-----------|------|---------|
| C→S | `start` | Begin session |
| C→S | `audio` | PCM audio frame |
| C→S | `stop` | End session |
| C→S | `ack` | ACK received |
| S→C | `partial` | Partial transcript |
| S→C | `final` | Final transcript |
| S→C | `entities` | Extracted entities |
| S→C | `cards` | Actions/decisions/risks |
| S→C | `summary` | Rolling summary |
| S→C | `final_summary` | Session-end summary |
| S→C | `status` | Health/metrics update |

### Audio Sources

| Source | Identifier | Capture Method |
|--------|------------|----------------|
| Microphone | `"mic"` | AVCaptureDevice |
| System Audio | `"system"` | ScreenCaptureKit |
| Redundant | `"redundant"` | Both (dual-path) |

### Correlation IDs

| ID | Purpose | Generated |
|----|---------|-----------|
| `sessionId` | Session lifecycle | Client on start |
| `attemptId` | Retry within session | Client on start |
| `connectionId` | WebSocket connection | Client on connect |
| `sourceId` | Audio source | Client per frame |

---

## Dependency Graph (Textual)

```
macOS Menu Bar App
├── BackendManager
│   ├── startServer() → Python uvicorn
│   └── healthCheck() → /health endpoint
├── WebSocketStreamer
│   ├── connect(sessionId, attemptId) → ws://127.0.0.1:8000/ws/listener
│   └── send(audio) / receive(transcript)
├── AudioCaptureManager (System Audio)
│   └── ScreenCaptureKit → CoreMedia
├── MicrophoneCaptureManager
│   └── AVCaptureSession → AVAudioEngine
├── RedundantAudioCaptureManager
│   ├── BroadcastFeatureManager (Screen Recording broadcast)
│   └── AudioCaptureManager + MicrophoneCaptureManager (dual)
├── SessionStore
│   └── ~/Library/Application Support/com.echopanel/sessions/
├── SessionBundle
│   └── ZIP export (receipt.json, events.ndjson, transcripts)
└── StructuredLogger
    └── ~/Library/Application Support/com.echopanel/logs/

FastAPI Server (localhost:8000)
├── WSLiveListener (/ws/listener)
│   ├── ConcurrencyController (queues, backpressure)
│   ├── VADASRWrapper (Silero VAD)
│   ├── ASRStream
│   │   ├── FasterWhisperProvider (default)
│   │   ├── WhisperCppProvider (Metal)
│   │   └── VoxtralRealtimeProvider
│   ├── Diarization (Pyannote)
│   └── AnalysisStream
│       ├── Entity Extraction (regex)
│       ├── Card Extraction (keywords)
│       └── Summary Generation (extractive)
├── DocumentsAPI (/documents)
│   └── RAGStore (~/.echopanel/rag_store.json)
├── CaptionOutput (/captions)
│   └── SRT/WebVTT file output
└── HealthEndpoints
    ├── /health → 200/503
    ├── /model-status
    └── /capabilities
```

---

## Risk Register

| ID | Risk | Severity | Location | Mitigation |
|----|------|----------|----------|------------|
| R-001 | Audio capture drop on permission revoke | High | AP-001, AP-002 | Error state, UI notification |
| R-002 | RTF > 1.0 sustained causes lag | High | ML-006, OR-006 | Degrade ladder, chunk dropping |
| R-003 | Diarization batch-only (no realtime) | Medium | AP-006 | Session-end labeling only |
| R-004 | No server-side PII redaction | Medium | SP-009 | Client-side regex in logs only |
| R-005 | Memory growth on long sessions | Medium | DS-001, AI-006 | Periodic transcript trimming? |
| R-006 | Keychain migration may lose tokens | Low | DS-005 | Migration attempts, returns false on fail |
| R-007 | No distributed tracing | Medium | OR-001-008 | Correlation IDs only, no OpenTelemetry |
| R-008 | No crash reporting (Swift) | Medium | OR-001 | Structured logs only |
| R-009 | WSS not enforced on localhost | Low | SP-004 | Localhost assumed trusted |
| R-010 | Session history no TTL | Low | DS-001 | Manual delete only |

### Critical Path Risks

1. **Audio → Server → ASR → Transcript**: Any failure here blocks the entire product
   - Mitigations: Redundant capture, reconnection, degrade ladder
   - Observability: Backpressure metrics, RTF monitoring

2. **Permission loss mid-session**: Common macOS issue
   - Mitigations: Permission checking before start, error states
   - Recovery: User must re-grant, restart session

---

## Verification Checklist

### UJ-002: Recording Session Flow

| Step | Action | Expected | Verify |
|------|--------|----------|--------|
| 1 | Start app | Backend auto-starts | `curl http://127.0.0.1:8000/health` → 200 |
| 2 | Click Start Listening | sessionState = .listening | UI shows "Stop Listening" |
| 3 | Speak into mic | Partial transcripts appear | Side panel updates |
| 4 | Stop session | sessionState = .finalizing → .idle | Final transcript shown |
| 5 | Check transcript | Text matches speech | Manual verification |

**Command:**
```bash
# Full integration test
./scripts/run-dev-app.sh &
sleep 5
curl -s http://127.0.0.1:8000/health | jq .
# Speak for 10s, stop, verify transcript in UI
```

### AP-001: Microphone Capture

| Step | Action | Expected |
|------|--------|----------|
| 1 | Grant Microphone permission | System prompt → Allow |
| 2 | Start session | Audio frames sent |
| 3 | Check logs | `onPCMFrame` events in `log stream` |
| 4 | Measure latency | <100ms capture→send |

**Command:**
```bash
log stream --style compact --predicate 'process == "MeetingListenerApp" && eventMessage CONTAINS "onPCMFrame"'
```

### ML-001: Model Load

| Step | Action | Expected |
|------|--------|----------|
| 1 | Start server | Model loads within 30s |
| 2 | Check /model-status | model_state = READY |
| 3 | Start transcription | First partial within 3s |

**Command:**
```bash
python -m uuvicorn server.main:app &
sleep 10
curl -s http://127.0.0.1:8000/model-status | jq .
```

### OR-003: Backpressure

| Step | Action | Expected |
|------|--------|----------|
| 1 | Start session | backpressureLevel = normal |
| 2 | Monitor metrics | queue_fill_ratio < 70% |
| 3 | Force overload (simulate) | Degrade level increases |

**Command:**
```bash
# Watch metrics during session
curl -s http://127.0.0.1:8000/health | jq .
```

### DS-001: Session Persistence

| Step | Action | Expected |
|------|--------|----------|
| 1 | Complete session | Files in ~/Library/Application Support/com.echopanel/sessions/ |
| 2 | Check transcript.jsonl | One line per segment |
| 3 | Crash/reopen | Recovery offered |
| 4 | Export bundle | ZIP created |

**Command:**
```bash
ls ~/Library/Application\ Support/com.echopanel/sessions/*/transcript.jsonl
```

---

## Special Focus: Full Audio Source → Transcript → Analysis Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AUDIO SOURCE → MODEL → TRANSCRIPT → ANALYSIS                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Mic/System │    │   WebSocket  │    │   Server     │    │   VAD        │
│   Audio      │───▶│   Upload     │───▶│   Reception  │───▶│   Filter     │
│   (16kHz)    │    │   (Base64)   │    │   (Queues)   │    │   (Silero)   │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
      │                                      │                   │
      │                                      │                   ▼
      │                                      │           ┌──────────────┐
      │                                      │           │   ASR        │
      │                                      │           │   Inference  │
      │                                      │           │   (Whisper)  │
      │                                      │           └──────────────┘
      │                                      │                   │
      │                                      ▼                   ▼
      │                              ┌──────────────┐    ┌──────────────┐
      │                              │   Concurrency│    │   Partial    │
      │                              │   Controller │    │   Emit       │
      │                              │   (Queues)   │    │              │
      │                              └──────────────┘    └──────────────┘
      │                                      │                   │
      │                                      │                   ▼
      │                                      │           ┌──────────────┐
      │                                      │           │   Final      │
      │                                      │           │   Emit       │
      │                                      │           └──────────────┘
      │                                      │                   │
      │                                      ▼                   │
      │                              ┌──────────────┐            │
      │                              │   Analysis  │◀───────────┘
      │                              │   Pipeline  │
      │                              └──────────────┘
      │                                      │
      │              ┌───────────────────────┼───────────────────────┐
      │              │                       │                       │
      │              ▼                       ▼                       ▼
      │      ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
      │      │   Entities   │       │   Cards      │       │   Summary    │
      │      │   (NER)      │       │   (Actions)  │       │   (Rolling)  │
      │      └──────────────┘       └──────────────┘       └──────────────┘
      │              │                       │                       │
      └──────────────┴───────────────────────┴───────────────────────┘
                                       │
                                       ▼
                              ┌──────────────┐
                              │   Client     │
                              │   UI Update  │
                              │   (SidePanel)│
                              └──────────────┘
```

### Failure Modes Summary for Full Flow

| Stage | Failure | User Impact | Recovery |
|-------|---------|-------------|----------|
| Audio Source | Permission denied | Cannot record | Request permission, restart |
| Audio Source | Device disconnected | Capture fails | Device hot-swap handler |
| WebSocket | Disconnect | Transcript gaps | Buffer replay (30s) |
| Concurrency | Queue overflow | Audio dropped | Backpressure, degrade |
| VAD | False positive | Speech → silence | User repeats |
| ASR | Model OOM | Crash | Provider restart |
| ASR | RTF > 1.0 | Lag | Model downgrade |
| Analysis | Timeout | Missing entities | Skipped, logged |
| UI | Lag | Stutter | Refresh on change |

---

## Evidence Summary

### Primary Evidence Sources

| Category | Files |
|----------|-------|
| Client UI/State | `AppState.swift`, `MeetingListenerApp.swift`, `OnboardingView.swift`, `SidePanelView.swift` |
| Audio Capture | `AudioCaptureManager.swift`, `MicrophoneCaptureManager.swift`, `BroadcastFeatureManager.swift` |
| Audio Pipeline | `ws_live_listener.py`, `asr_stream.py`, `vad_asr_wrapper.py`, `concurrency_controller.py` |
| ASR Providers | `provider_faster_whisper.py`, `provider_whisper_cpp.py`, `provider_voxtral_realtime.py` |
| Model Lifecycle | `model_preloader.py`, `capability_detector.py`, `degrade_ladder.py` |
| Analysis | `analysis_stream.py`, `diarization.py`, `rag_store.py` |
| Storage | `SessionStore.swift`, `SessionBundle.swift`, `KeychainHelper.swift` |
| Observability | `StructuredLogger.swift`, `metrics_registry.py`, `ResilientWebSocket.swift` |
| Security | Permission checks in `AppState.swift`, `KeychainHelper.swift`, redaction in `StructuredLogger.swift` |

### Audit Documents Referenced

- `docs/audit/audio-pipeline-audit-20260211.md` (Audio Pipeline Analyst)
- `docs/audit/security-privacy-boundaries-20260211.md` (Security Analyst)
- `docs/WORKLOG_TICKETS.md` - Ticket TCK-20260211-006

---

*Flow Atlas generated from multi-agent analysis. All flows documented with code evidence. Last updated: 2026-02-11*
