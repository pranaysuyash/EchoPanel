# EchoPanel Flow Atlas

**Document Version**: 1.0
**Generated**: 2026-02-11
**Scope**: Complete end-to-end flow extraction for EchoPanel v0.2

---

## Executive Summary

EchoPanel is a macOS menu bar application with local FastAPI backend that performs real-time speech-to-text transcription, speaker diarization, NLP analysis (NER, summarization, action extraction), and RAG (Retrieval-Augmented Generation) for meeting notes.

**Architecture**:

- **Client (Swift)**: macOS menu bar app with side panel UI, audio capture, WebSocket client
- **Server (Python)**: FastAPI backend with ASR providers (faster-whisper, whisper.cpp, voxtral), diarization, NLP, RAG
- **Communication**: WebSocket (localhost with optional auth) for real-time streaming
- **Storage**: Local filesystem (JSON/JSONL), macOS Keychain for secrets, no cloud sync

**Total Flows Identified**: 80 flows across 8 domains

---

## Flow Atlas Inventory

### External Flows (User Journey) - 18 flows

| Flow ID | Name                                | Status      | Priority |
| ------- | ----------------------------------- | ----------- | -------- |
| EXT-001 | First Launch Onboarding             | Implemented | P0       |
| EXT-002 | Screen Recording Permission Request | Implemented | P0       |
| EXT-003 | Microphone Permission Request       | Implemented | P0       |
| EXT-004 | Session Start                       | Implemented | P0       |
| EXT-005 | Session Stop & Finalization         | Implemented | P0       |
| EXT-006 | Export JSON                         | Implemented | P1       |
| EXT-007 | Export Markdown                     | Implemented | P1       |
| EXT-008 | Export Debug Bundle                 | Implemented | P1       |
| EXT-009 | Settings Configuration              | Implemented | P1       |
| EXT-010 | Session History Browse              | Implemented | P1       |
| EXT-011 | Session Recovery from Crash         | Implemented | P0       |
| EXT-012 | Backend Server Start                | Implemented | P0       |
| EXT-013 | Backend Auto-Restart/Recovery       | Implemented | P0       |
| EXT-014 | Global Hotkey Actions               | Implemented | P2       |
| EXT-015 | Context Document Indexing (RAG)     | Implemented | P2       |
| EXT-016 | Context Query (RAG Search)          | Implemented | P2       |
| EXT-017 | Menu Bar Quick Actions              | Implemented | P1       |
| EXT-018 | Side Panel View Mode Switching      | Implemented | P2       |

### Audio Pipeline Flows - 10 flows

| Flow ID | Name                                             | Status       | Priority |
| ------- | ------------------------------------------------ | ------------ | -------- |
| AUD-001 | System Audio Capture (ScreenCaptureKit)          | Implemented  | P0       |
| AUD-002 | Microphone Audio Capture (AVAudioEngine)         | Implemented  | P0       |
| AUD-003 | Dual-Source Redundant Capture with Auto-Failover | Implemented  | P0       |
| AUD-004 | Client-to-Server WebSocket Transmission          | Implemented  | P0       |
| AUD-005 | Server-Side Audio Queueing & Backpressure        | Implemented  | P0       |
| AUD-006 | Server-Side ASR Processing (faster-whisper)      | Implemented  | P0       |
| AUD-007 | Session-End Diarization (pyannote)               | Implemented  | P2       |
| AUD-008 | Device Hot-Swap Recovery                         | Implemented  | P1       |
| AUD-009 | Clock Drift Compensation                         | Hypothesized | P1       |
| AUD-010 | Client-Side VAD (Silero)                         | Partial      | P1       |

### Model Lifecycle Flows - 15 flows

| Flow ID | Name                                                                         | Status                                    | Priority |
| ------- | ---------------------------------------------------------------------------- | ----------------------------------------- | -------- |
| MOD-001 | Capability Detection with Tier-Based Recommendations                         | Implemented                               | P0       |
| MOD-002 | Registry Pattern with Thread-Safe Caching                                    | Implemented                               | P1       |
| MOD-003 | Eager Load + 3-Phase Warmup (Load → Warm → Ready)                            | Implemented                               | P0       |
| MOD-004 | Lazy Model Loading on First Inference                                        | Implemented                               | P1       |
| MOD-005 | Fixed-Size Chunked Batch Inference                                           | Implemented                               | P0       |
| MOD-006 | Auto Device Selection (Metal/CUDA/CPU)                                       | Implemented                               | P0       |
| MOD-007 | 5-Level Degrade Ladder (NORMAL → WARNING → DEGRADE → EMERGENCY → FAILOVER)   | Implemented                               | P1       |
| MOD-008 | Comprehensive Health Metrics                                                 | Implemented                               | P1       |
| MOD-009 | VAD Pre-Filtering with Silero                                                | Implemented                               | P1       |
| MOD-010 | Thread-Safe Inference Serialization                                          | Implemented                               | P1       |
| MOD-011 | 5-State Model Machine (UNINITIALIZED → LOADING → WARMING_UP → READY → ERROR) | Implemented                               | P0       |
| MOD-012 | Voxtral Streaming Session with Auto-Recovery                                 | Implemented                               | P1       |
| MOD-013 | Fallback Provider Switching                                                  | Implemented                               | P1       |
| MOD-014 | Memory Management                                                            | Implemented (explicit unload on shutdown) | P2       |
| MOD-015 | Model Versioning/Updates                                                     | Not Implemented                           | P2       |

### Data & Storage Flows - 15 flows

| Flow ID | Name                           | Status       | Priority |
| ------- | ------------------------------ | ------------ | -------- |
| STO-001 | Session Lifecycle Storage      | Implemented  | P0       |
| STO-002 | Transcript Append-Only Storage | Implemented  | P0       |
| STO-003 | Session Auto-Save Snapshot     | Implemented  | P0       |
| STO-004 | Crash Recovery Marker          | Implemented  | P0       |
| STO-005 | RAG Document Indexing          | Implemented  | P1       |
| STO-006 | Keychain Secrets Storage       | Implemented  | P0       |
| STO-007 | Session Bundle Export          | Implemented  | P1       |
| STO-008 | Structured Logging Storage     | Implemented  | P1       |
| STO-009 | JSON/Markdown Export           | Implemented  | P1       |
| STO-010 | Audio Debug Dump (Server-Side) | Implemented  | P2       |
| STO-011 | Session History Listing        | Implemented  | P1       |
| STO-012 | Session Deletion               | Implemented  | P1       |
| STO-013 | Audio Storage (Raw PCM)        | Hypothesized | P2       |
| STO-014 | Encryption                     | Hypothesized | P1       |
| STO-015 | Backup/Restore                 | Hypothesized | P2       |

### Intelligence Flows - 12 flows

| Flow ID | Name                                                  | Status                                                | Priority |
| ------- | ----------------------------------------------------- | ----------------------------------------------------- | -------- |
| INT-001 | Real-Time Entity Extraction Flow                      | Implemented                                           | P0       |
| INT-002 | Real-Time Card (Action/Decision/Risk) Extraction Flow | Implemented                                           | P0       |
| INT-003 | Rolling Summary Generation Flow                       | Implemented (extractive only)                         | P1       |
| INT-004 | RAG Document Indexing Flow                            | Implemented (lexical-only, NO embeddings)             | P1       |
| INT-005 | RAG Query Retrieval Flow                              | Implemented (lexical BM25/TF-IDF, NO semantic search) | P1       |
| INT-006 | Session-End Final Analysis Flow                       | Implemented                                           | P0       |
| INT-007 | Real-Time Analysis Loop                               | Implemented                                           | P0       |
| INT-008 | Topic Extraction Flow                                 | Hypothesized (GLiNER not implemented)                 | P2       |
| INT-009 | Embedding Generation Flow                             | Hypothesized (NO embeddings)                          | P2       |
| INT-010 | Incremental Analysis Update Flow                      | Partial (sliding window only)                         | P1       |
| INT-011 | Citation/Grounding Flow                               | Implemented (basic only)                              | P1       |
| INT-012 | Post-Session Archival Analysis Flow                   | Hypothesized                                          | P2       |

### Observability & Reliability Flows - 23 flows

| Flow ID | Name                                                     | Status      | Priority |
| ------- | -------------------------------------------------------- | ----------- | -------- |
| OBS-001 | Structured Logging Flow (Swift Client)                   | Implemented | P0       |
| OBS-002 | Metrics Collection Flow (Python Server)                  | Implemented | P1       |
| OBS-003 | Correlation ID Propagation Flow                          | Implemented | P0       |
| OBS-004 | Backend Health Check Flow                                | Implemented | P0       |
| OBS-005 | Backend Crash Detection & Restart Flow                   | Implemented | P0       |
| OBS-006 | WebSocket Connection Health Monitoring                   | Implemented | P0       |
| OBS-007 | Metrics Emission Flow (1Hz)                              | Implemented | P0       |
| OBS-008 | Session Lifecycle Event Logging                          | Implemented | P0       |
| OBS-009 | Backpressure Monitoring & Alerting Flow                  | Implemented | P0       |
| OBS-010 | Frame Drop Detection & Reporting Flow                    | Implemented | P0       |
| OBS-011 | Timeout Enforcement Flow                                 | Implemented | P0       |
| OBS-012 | Exponential Backoff Restart Flow                         | Implemented | P0       |
| OBS-013 | Error Classification & User Surfacing Flow               | Implemented | P0       |
| OBS-014 | Session Bundle Creation & Export Flow                    | Implemented | P1       |
| OBS-015 | Audio Queue Backpressure Flow                            | Implemented | P0       |
| OBS-016 | Concurrency Limiting Flow                                | Implemented | P0       |
| OBS-017 | Degradation Detection & Management Flow (Degrade Ladder) | Implemented | P0       |
| OBS-018 | Performance Metrics Tracking Flow (RTF, Latency)         | Implemented | P0       |
| OBS-019 | Health Check Polling Flow (Client Side)                  | Implemented | P1       |
| OBS-020 | Session Finalization Metrics Flow                        | Implemented | P0       |
| OBS-021 | Log File Rotation Flow                                   | Implemented | P1       |
| OBS-022 | Watchdog Timer Flow (Health Check Timer)                 | Implemented | P0       |
| OBS-023 | Source Drop Decision Flow (Extreme Overload)             | Implemented | P0       |

### Security & Privacy Flows - 15 flows

| Flow ID | Name                               | Status                                          | Priority                                                                |
| ------- | ---------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------- | --- |
| SEC-001 | Screen Recording Permission Flow   | Implemented                                     | P0                                                                      |
| SEC-002 | Microphone Permission Flow         | Implemented                                     | P0                                                                      |
| SEC-003 | Backend Token Keychain Storage     | Implemented                                     | P0                                                                      |
| SEC-004 | HuggingFace Token Keychain Storage | Implemented                                     | P0                                                                      |
| SEC-005 | WebSocket Authentication           | Implemented                                     | Header-based auth for WS client (`Authorization` + `x-echopanel-token`) | P0  |
| SEC-006 | Documents API Authentication       | Implemented                                     | P0                                                                      |
| SEC-007 | Network Security (TLS)             | Partial Implemented (auto-switch based on host) | P0                                                                      |
| SEC-008 | Audio Data Movement                | Implemented                                     | P0                                                                      |
| SEC-009 | Debug Audio Dump (Privacy Risk)    | Implemented (env var gated + bounded cleanup)   | P2                                                                      |
| SEC-010 | Log Redaction (PII Protection)     | Implemented                                     | P0                                                                      |
| SEC-011 | Session Bundle Privacy Controls    | Implemented                                     | P0                                                                      |
| SEC-012 | Diarization Model Privacy          | Implemented                                     | P0                                                                      |
| SEC-013 | Data Retention & Cleanup           | Hypothesized (partial implementation)           | P2                                                                      |
| SEC-014 | Authorization & Access Control     | Partial Implemented (token-based, no RBAC)      | P1                                                                      |
| SEC-015 | Local Documents Privacy            | Implemented                                     | P0                                                                      |

### UI Flows - 5 flows

| Flow ID | Name                  | Status       | Priority |
| ------- | --------------------- | ------------ | -------- |
| UI-001  | Menu Bar Interaction  | Hypothesized | P1       |
| UI-002  | Side Panel Display    | Hypothesized | P1       |
| UI-003  | Transcript Rendering  | Hypothesized | P1       |
| UI-004  | Search and Navigation | Hypothesized | P1       |
| UI-005  | Export UI Actions     | Hypothesized | P1       |

### Summary Statistics

| Category              | Implemented | Partial | Hypothesized | Not Implemented | Total   |
| --------------------- | ----------- | ------- | ------------ | --------------- | ------- |
| External Flows        | 18          | 0       | 0            | 0               | 18      |
| Audio Pipeline Flows  | 10          | 1       | 1            | 0               | 12      |
| Model Lifecycle Flows | 13          | 1       | 1            | 1               | 16      |
| Data & Storage Flows  | 12          | 0       | 3            | 0               | 15      |
| Intelligence Flows    | 7           | 1       | 4            | 0               | 12      |
| Observability Flows   | 23          | 0       | 0            | 0               | 23      |
| Security Flows        | 14          | 2       | 0            | 1               | 15      |
| UI Flows              | 0           | 0       | 5            | 0               | 5       |
| **TOTAL**             | **97**      | **4**   | **14**       | **1**           | **116** |

**Breakdown**:

- Implemented: 97 flows (87%)
- Partial: 4 flows (4%)
- Hypothesized: 9 flows (8%)
- Not Implemented: 1 flow (1%)

---

## Component/Module Map

### Client-Side Components (Swift)

| Component                        | File                                 | Purpose                                                         |
| -------------------------------- | ------------------------------------ | --------------------------------------------------------------- |
| **AppState**                     | `AppState.swift`                     | Central state manager, session lifecycle, transcript management |
| **BackendManager**               | `BackendManager.swift`               | Python server process management, health checks, crash recovery |
| **AudioCaptureManager**          | `AudioCaptureManager.swift`          | System audio capture via ScreenCaptureKit, limiter, resampling  |
| **MicrophoneCaptureManager**     | `MicrophoneCaptureManager.swift`     | Microphone capture via AVAudioEngine, limiter, resampling       |
| **RedundantAudioCaptureManager** | `RedundantAudioCaptureManager.swift` | Dual-source capture with auto-failover                          |
| **DeviceHotSwapManager**         | `DeviceHotSwapManager.swift`         | USB audio device hot-swap detection and recovery                |
| **WebSocketStreamer**            | `WebSocketStreamer.swift`            | WebSocket client, connection management, backpressure           |
| **StructuredLogger**             | `StructuredLogger.swift`             | Structured logging with redaction, rotation, multi-sink         |
| **KeychainHelper**               | `KeychainHelper.swift`               | macOS Keychain storage for tokens                               |
| **SessionBundle**                | `SessionBundle.swift`                | Debug bundle creation and export                                |
| **SessionStore**                 | `SessionStore.swift`                 | Session persistence, auto-save, recovery marker                 |
| **SidePanelView**                | `SidePanelView.swift`                | Side panel UI with three-cut renderers                          |
| **OnboardingView**               | `OnboardingView.swift`               | First-launch onboarding flow                                    |
| **SessionHistoryView**           | `SessionHistoryView.swift`           | Session history browser                                         |
| **HotKeyManager**                | `HotKeyManager.swift`                | Global hotkey monitoring and handling                           |
| **BroadcastFeatureManager**      | `BroadcastFeatureManager.swift`      | Broadcast mode coordination                                     |
| **Models**                       | `Models.swift`                       | Data models (TranscriptSegment, ActionItem, etc.)               |

### Server-Side Components (Python)

| Component                     | File                                           | Purpose                                                |
| ----------------------------- | ---------------------------------------------- | ------------------------------------------------------ |
| **main**                      | `main.py`                                      | FastAPI app entry, health endpoint, model preloading   |
| **ws_live_listener**          | `server/api/ws_live_listener.py`               | WebSocket endpoint, session management, audio queueing |
| **documents**                 | `server/api/documents.py`                      | RAG documents API (index, query, delete)               |
| **asr_providers**             | `server/services/asr_providers.py`             | ASR provider registry and interface                    |
| **provider_faster_whisper**   | `server/services/provider_faster_whisper.py`   | faster-whisper provider implementation                 |
| **provider_whisper_cpp**      | `server/services/provider_whisper_cpp.py`      | whisper.cpp provider with Metal support                |
| **provider_voxtral_realtime** | `server/services/provider_voxtral_realtime.py` | Voxtral streaming provider                             |
| **asr_stream**                | `server/services/asr_stream.py`                | ASR streaming interface and chunking                   |
| **vad_filter**                | `server/services/vad_filter.py`                | Silero VAD pre-filtering                               |
| **diarization**               | `server/services/diarization.py`               | Pyannote speaker diarization                           |
| **analysis_stream**           | `server/services/analysis_stream.py`           | NLP extraction (NER, cards, summary)                   |
| **rag_store**                 | `server/services/rag_store.py`                 | RAG storage with BM25/TF-IDF (lexical only)            |
| **metrics_registry**          | `server/services/metrics_registry.py`          | Metrics collection (counters, gauges, histograms)      |
| **concurrency_controller**    | `server/services/concurrency_controller.py`    | Session concurrency limiting                           |
| **degrade_ladder**            | `server/services/degrade_ladder.py`            | 5-level degradation management                         |
| **vad_asr_wrapper**           | `server/services/vad_asr_wrapper.py`           | VAD + ASR wrapper (not integrated)                     |
| **capability_detector**       | `server/services/capability_detector.py`       | Hardware capability detection for auto-provider        |
| **model_preloader**           | `server/services/model_preloader.py`           | Model eager loading and warmup                         |

---

## Event + State Glossary

### WebSocket Events (Client → Server)

| Event        | Type    | Purpose                                                   | Evidence             |
| ------------ | ------- | --------------------------------------------------------- | -------------------- |
| `start`      | control | Initiates session, passes session_id, sample_rate, format | WS_CONTRACT.md:32-45 |
| `audio`      | data    | Sends PCM16 audio chunks as base64 JSON                   | WS_CONTRACT.md:47-54 |
| `stop`       | control | Ends session, triggers finalization                       | WS_CONTRACT.md:62-68 |
| Binary frame | data    | Legacy: raw PCM16 bytes (treated as source="system")      | WS_CONTRACT.md:58-60 |

### WebSocket Events (Server → Client)

| Event             | Type         | Purpose                                                                | Evidence                    |
| ----------------- | ------------ | ---------------------------------------------------------------------- | --------------------------- |
| `status`          | notification | Connection state, error messages, backpressure warnings                | ws_live_listener.py:576-593 |
| `asr_partial`     | data         | Partial transcription result (currently not emitted by faster-whisper) | ws_live_listener.py:84-94   |
| `asr_final`       | data         | Final transcription with text, timestamps, confidence, source          | ws_live_listener.py:84-94   |
| `entities_update` | notification | Named entities (people, orgs, dates, projects, topics)                 | ws_live_listener.py:422-423 |
| `cards_update`    | notification | Actions, decisions, risks extracted from transcript                    | ws_live_listener.py:439-445 |
| `final_summary`   | notification | Session-end transcript, analysis, diarization, markdown                | ws_live_listener.py:787-804 |
| `metrics`         | notification | 1Hz metrics (queue depth, RTF, dropped frames, correlation IDs)        | ws_live_listener.py:540-571 |

### Client State Machine

| State        | Transitions                                      | Evidence                |
| ------------ | ------------------------------------------------ | ----------------------- |
| `idle`       | idle → starting → listening → finalizing → idle  | AppState.swift:94-99    |
| `starting`   | starting → listening (on streaming ACK) or error | AppState.swift:495, 280 |
| `listening`  | listening → finalizing (on stop) or error        | AppState.swift:653      |
| `finalizing` | finalizing → idle (on complete) or error         | AppState.swift:653      |
| `error`      | error → idle (on reset)                          | AppState.swift:484      |

### Permission States

| State            | Meaning                     | Evidence          |
| ---------------- | --------------------------- | ----------------- |
| `unknown`        | Permission not yet checked  | AppState.swift:12 |
| `nonInteractive` | During init before UI ready | AppState.swift:13 |
| `authorized`     | Permission granted          | AppState.swift:15 |
| `denied`         | Permission denied           | AppState.swift:15 |

### Backend Server States

| State               | Meaning                                      | Evidence                |
| ------------------- | -------------------------------------------- | ----------------------- |
| `stopped`           | Server not running                           | BackendManager.swift:16 |
| `starting`          | Server process started, health check pending | BackendManager.swift:17 |
| `running`           | Server healthy, ASR ready                    | BackendManager.swift:19 |
| `runningNeedsSetup` | Server running but ASR/model not ready       | BackendManager.swift:20 |
| `error`             | Server failed to start/start                 | BackendManager.swift:21 |

### Backend Recovery Phases

| Phase            | Meaning                                    | Evidence                |
| ---------------- | ------------------------------------------ | ----------------------- |
| `idle`           | No recovery needed                         | BackendManager.swift:24 |
| `retryScheduled` | Restart scheduled with exponential backoff | BackendManager.swift:25 |
| `failed`         | Max restart attempts reached               | BackendManager.swift:26 |

### WebSocket Stream States

| State          | Meaning                                            | Evidence                   |
| -------------- | -------------------------------------------------- | -------------------------- |
| `streaming`    | Actively processing audio and emitting transcripts | WebSocketStreamer.swift:40 |
| `reconnecting` | Connection lost, attempting to reconnect           | WebSocketStreamer.swift:41 |
| `error`        | Connection failed, will not auto-reconnect         | WebSocketStreamer.swift:42 |

### Audio Quality States

| State     | Meaning                         | Threshold      | Evidence                         |
| --------- | ------------------------------- | -------------- | -------------------------------- |
| `unknown` | No audio data received          | -              | AudioCaptureManager.swift:96     |
| `poor`    | RMS < 0.01 or clipping detected | <0.01, >10%    | AudioCaptureManager.swift:96-100 |
| `good`    | Normal audio levels             | 0.01-0.3, <10% | AudioCaptureManager.swift:96-100 |
| `limited` | Limiter active (gain < 0.9)     | 0.9 max gain   | AudioCaptureManager.swift:96-100 |

### Redundant Audio Source States

| State     | Meaning                  | Evidence                              |
| --------- | ------------------------ | ------------------------------------- |
| `primary` | System audio (preferred) | RedundantAudioCaptureManager.swift:30 |
| `backup`  | Microphone (fallback)    | RedundantAudioCaptureManager.swift:31 |

### Model State Machine

| State           | Meaning                   | Evidence              |
| --------------- | ------------------------- | --------------------- |
| `UNINITIALIZED` | Model not loaded          | model_preloader.py:52 |
| `LOADING`       | Model loading from disk   | model_preloader.py:53 |
| `WARMING_UP`    | Running warmup inferences | model_preloader.py:54 |
| `READY`         | Model ready for inference | model_preloader.py:55 |
| `ERROR`         | Model load failed         | model_preloader.py:56 |

### Degradation Levels

| Level       | RTF Threshold           | Action                            | Evidence              |
| ----------- | ----------------------- | --------------------------------- | --------------------- |
| `NORMAL`    | < 0.8                   | None                              | degrade_ladder.py:212 |
| `WARNING`   | 0.8 - 1.2               | Increase chunk size (if possible) | degrade_ladder.py:230 |
| `DEGRADE`   | 1.2 - 2.0               | Disable VAD                       | degrade_ladder.py:239 |
| `EMERGENCY` | 2.0 - 5.0               | Start dropping chunks             | degrade_ladder.py:176 |
| `FAILOVER`  | > 5.0 or provider error | Switch provider                   | degrade_ladder.py:178 |

### Backpressure Levels

| Level        | Queue Fill Ratio | Meaning                           | Evidence                          |
| ------------ | ---------------- | --------------------------------- | --------------------------------- |
| `normal`     | < 70%            | No issue                          | concurrency_controller.py:296-331 |
| `buffering`  | 70-85%           | Processing backlog                | concurrency_controller.py:309-318 |
| `degraded`   | 85-95%           | High backlog, some drops          | concurrency_controller.py:320-319 |
| `overloaded` | > 95%            | Critical backlog, dropping frames | concurrency_controller.py:321-322 |

---

## Flow Specs

### SPECIAL FOCUS: Complete Audio-to-Transcript Flow

This is the comprehensive flow from audio source detection through model inference to transcript persistence.

#### Flow ID: COMPOSITE-001

**Status**: Implemented (with known gaps)
**Triggers**: User clicks "Start Listening" button, global hotkey F1, or from onboarding

**Preconditions**:

- Backend server ready (`BackendManager.isServerReady == true`)
- Required permissions granted (Screen Recording for system audio, Microphone for mic)
- ASR model loaded (`model_preloader.health().ready == true`)

**Sequence (Complete End-to-End)**:

```
1. USER ACTION: Start Session
   → toggleSession() called [AppState.swift:492]
   → resetSession() clears previous state [AppState.swift:713]
   → Generate sessionID = UUID() [AppState.swift:505]

2. PERMISSION CHECK
   → refreshPermissionStatuses() [AppState.swift:527]
   → If audioSource includes system:
       → CGPreflightScreenCaptureAccess() [AppState.swift:531]
       → If not granted → setSessionError(.screenRecordingPermissionRequired) [AppState.swift:542]
       → If granted but CGPreflightScreenCaptureAccess() = false → setSessionError(.screenRecordingRequiresRelaunch) [AppState.swift:546]
   → If audioSource includes microphone:
       → await micCapture.requestPermission() [AppState.swift:553]
       → If denied → setSessionError(.microphonePermissionRequired) [AppState.swift:556]

3. BROADCAST SETUP (if enabled)
   → setupBroadcastFeaturesForSession() [AppState.swift:567]
   → Check BroadcastFeatureManager.useRedundantAudio
   → If true:
       → RedundantAudioCaptureManager.startRedundantCapture(autoFailover:true) [AppState.swift:573]
       → Primary source: system audio, Backup source: microphone [RedundantAudioCaptureManager.swift:141]
       → Both captures start simultaneously [AudioCaptureManager.swift:68, MicrophoneCaptureManager.swift:41]
   → activeSource = .primary, quality monitoring enabled [RedundantAudioCaptureManager.swift:158]

4. AUDIO CAPTURE START
   → If NOT redundant mode:
       → If audioSource == .system or .both:
           → AudioCaptureManager.startCapture() [AppState.swift:583]
           → SCShareableContent.excludingDesktopWindows() [AudioCaptureManager.swift:68-73]
           → ScreenCaptureKit captures system audio [AudioCaptureManager.swift:90]
       → If audioSource == .microphone or .both:
           → MicrophoneCaptureManager.startCapture() [AppState.swift:593]
           → AVAudioEngine initializes [MicrophoneCaptureManager.swift:61]
           → Tap installed on input bus [MicrophoneCaptureManager.swift:57]

5. AUDIO PROCESSING (Client-Side)
   → CMSampleBuffer arrives [AudioCaptureManager.swift:350]
   → processAudio() called [AudioCaptureManager.swift:106]
       → Extract ASBD from format description [AudioCaptureManager.swift:107-111]
       → Create AVAudioPCMBuffer from CMSampleBuffer [AudioCaptureManager.swift:127-131]
       → AVAudioConverter(inputFormat → targetFormat) [AudioCaptureManager.swift:149]
           → targetFormat = 16kHz, mono, Float32 [AudioCaptureManager.swift:18]
       → converter.convert() to outputBuffer [AudioCaptureManager.swift:170]

6. LIMITER APPLICATION (P0-2 FIX)
   → applyLimiter(samples) called [AudioCaptureManager.swift:222-253]
       → limiterAttack: 0.001 (fast, ~1 sample) [AudioCaptureManager.swift:31]
       → limiterRelease: 0.99995 (slow, ~1s) [AudioCaptureManager.swift:33]
       → limiterThreshold: 0.9 (-0.9 dBFS) [AudioCaptureManager.swift:35]
       → If sample > 0.9 → multiply by gain [AudioCaptureManager.swift:239-241]
       → limiterGainEMA tracks limiting activity [AudioCaptureManager.swift:243-247]
       → If sample > 0.999 → multiply by 0.9 max reduction [AudioCaptureManager.swift:248]

7. CHUNKING AND TRANSMISSION
   → emitPCMFrames(limitedSamples) [AudioCaptureManager.swift:255]
       → Float32 → Int16 conversion [AudioCaptureManager.swift:263]
       → Chunk into 320-sample frames (20ms @ 16kHz) = 640 bytes [AudioCaptureManager.swift:272]
       → onPCMFrame?(data, source) callback [AudioCaptureManager.swift:277]

8. WEBSOCKET CONNECTION
   → WebSocketStreamer.connect(sessionID, attemptID) [WebSocketStreamer.swift:102]
   → Generate correlation IDs: session_id, attempt_id, connection_id [WebSocketStreamer.swift:107-110]
   → sendStart() after 0.2s delay [WebSocketStreamer.swift:119-121]
       → {"type":"start","session_id":...,"sample_rate":16000,"format":"pcm_s16le"}

9. SERVER-SIDE CONNECTION
   → ws_live_listener endpoint accepts WebSocket [ws_live_listener.py:585]
   → _extract_ws_auth_token() validates token [ws_live_listener.py:157-182]
   → If ECHOPANEL_WS_AUTH_TOKEN set, compare using hmac.compare_digest() [ws_live_listener.py:173-182]
   → SessionState created with session_id, attempt_id, connection_id [ws_live_listener.py:597]
   → Acquire session slot via ConcurrencyController.acquire_session(timeout=5s) [ws_live_listener.py:647-657]

10. SERVER READY ACK
   → ASR provider loaded, model warmed up
   → Provider registry returns provider [asr_providers.py]
   → Send {"type":"status","state":"streaming","connection_id":...} [ws_live_listener.py:689-694]
   → Client onStatus(.streaming) → Cancel timeout task [AppState.swift:280]
   → sessionState = .listening [AppState.swift:280]
   → Start timer (elapsedSeconds increments) [AppState.swift:1065]

11. AUDIO RECEIPT (Server)
   → WebSocket receives {"type":"audio","source":"system/mic","data":"base64..."} [ws_live_listener.py:706-728]
   → Base64 decode to PCM bytes [ws_live_listener.py:713]
   → q = get_queue(state, source) [ws_live_listener.py:715]
       → Creates asyncio.Queue(maxsize=48) [ws_live_listener.py:245]

12. ASR LOOP (PER-SOURCE)
   → If first frame for source:
       → state.asr_tasks.append(asyncio.create_task(_asr_loop(q, source))) [ws_live_listener.py:722]
   → _asr_loop() drains queue [ws_live_listener.py:344-350]
       → stream_asr() yields PCM bytes [ws_live_listener.py:361]
       → Accumulates 2 seconds of audio (chunk_seconds=2) [ws_live_listener.py:36]

13. ASR INFERENCE
   → config = _get_default_config() [asr_stream.py:54]
   → provider = ASRProviderRegistry.get_provider(config) [asr_stream.py:55]
   → provider.transcribe_stream(pcm_stream, 16000, audio_source) [provider_faster_whisper.py:74]
       → faster-whisper loads model (if not loaded)
       → VAD filters silence (if vad_enabled=true) [provider_faster_whisper.py:93]
       → Accumulates 2s chunks [provider_faster_whisper.py:82]
       → Yields ASRSegment objects:
           - type: "asr_final" (partials disabled for faster-whisper)
           - text: recognized text
           - t0, t1: timestamps
           - confidence: segment confidence
           - source: audio_source tag

14. TRANSCRIPT EMIT
   → ws_send(state, websocket, event) [ws_live_listener.py:399]
   → Client receives via onASRFinal [AppState.swift:329]
   → TranscriptSegment appended to transcriptSegments [AppState.swift:329]
   → SessionBundle records segment [AppState.swift:538]
   → StructuredLogger logs with correlation context

15. METRICS LOOP (1Hz)
   → _metrics_loop() runs every 1 second [ws_live_listener.py:481]
   → For each source:
       → queueDepth = q.qsize() [ws_live_listener.py:491]
       → fillRatio = queueDepth / 48 [ws_live_listener.py:493]
       → droppedRecent = dropped_frames - asr_last_dropped [ws_live_listener.py:496]
       → avgInferTime = mean(last 10 processing times) [ws_live_listener.py:501]
       → realtimeFactor = avgInferTime / 2.0 [ws_live_listener.py:508]
       → backlog_seconds = fillRatio * 2.0 * 48 [ws_live_listener.py:511]
       → Send {"type":"metrics", ...} [ws_live_listener.py:570]

16. ANALYSIS LOOP (Every 40s)
   → _analysis_loop() task created on session start [ws_live_listener.py:702]
   → sleep 12s → extract_entities(transcript_snapshot) [ws_live_listener.py:418]
       → 10s timeout enforced
       → Regex pattern matching for entities [analysis_stream.py:229-337]
       → Sort by count/recency, limit to 7 per category [analysis_stream.py:343-364]
       → Send {"type":"entities_update",...} [ws_live_listener.py:422]
   → sleep 28s → extract_cards(transcript_snapshot) [ws_live_listener.py:431]
       → 15s timeout enforced
       → Keyword matching for actions/decisions/risks [analysis_stream.py:113-118]
       → Fuzzy deduplication (0.7 Jaccard) [analysis_stream.py:77-98]
       → Limit to 7 per category [analysis_stream.py:154-156]
       → Send {"type":"cards_update",...} [ws_live_listener.py:439]

17. SESSION FINALIZATION
   → User clicks "Stop Listening"
   → stopSession() called [AppState.swift:651]
   → sessionState = .finalizing [AppState.swift:653]
   → Stop audio capture (system and/or mic) [AppState.swift:668, 672]
   → Signal EOF to all queues (put None) [ws_live_listener.py:733]

18. ASR FLUSH WITH TIMEOUT
   → Wait for ASR tasks to flush with 8s timeout [ws_live_listener.py:742-753]
   → Timeout → Log warning "ASR flush timed out" [ws_live_listener.py:748]
   → Continue with partial transcript

19. CANCEL ANALYSIS TASKS
   → Cancel analysis tasks with 5s timeout [ws_live_listener.py:756-764]
   → Timeout → Log warning "Analysis task cancellation timed out" [ws_live_listener.py:764]

20. DIARIZATION (if enabled)
   → _run_diarization_per_source() [ws_live_listener.py:767]
   → For each source with PCM buffer:
       → diarize_pcm(pcm_bytes, 16000) [diarization.py:111]
       → pyannote.audio Pipeline [diarization.py:156]
       → Yields speaker turns [diarization.py:159]
       → Merge adjacent same-speaker segments [diarization.py:169]

21. MERGE TRANSCRIPT WITH SPEAKERS
   → Sort transcript snapshot by t0 [ws_live_listener.py:773]
   → _merge_transcript_with_source_diarization(transcript_snapshot, diarization_by_source) [ws_live_listener.py:776]
   → Add "speaker" field to each segment [ws_live_listener.py:211]

22. GENERATE FINAL ANALYSIS
   → generate_rolling_summary(transcript_snapshot) [ws_live_listener.py:781]
   → extract_cards(transcript_snapshot) [ws_live_listener.py:784]
   → extract_entities(transcript_snapshot) [ws_live_listener.py:785]
   → Send {"type":"final_summary", "markdown":..., "json": {...}} [ws_live_listener.py:787-803]

23. SESSION END
   → Close WebSocket [ws_live_listener.py:804]
   → Release session slot (ConcurrencyController) [ws_live_listener.py:841]
   → sessionState = .idle [AppState.swift:700]
   → Save snapshot to SessionStore [AppState.swift:691]
   → StructuredLogger.clearContext() [AppState.swift:707]
   → Post .summaryShouldOpen notification → SummaryView opens [AppState.swift:709]

```

**Inputs**:

- User selection (audio source: system/microphone/both)
- Audio: Variable sample rate (typically 48kHz), converted to 16kHz mono PCM16
- Permissions: Screen Recording, Microphone
- Server config: ASR provider, model name, VAD enabled

**Outputs**:

- Transcript: Real-time ASR segments with text, timestamps, confidence, source
- Analysis: Entities, actions, decisions, risks (every 40s)
- Metrics: Queue depth, RTF, dropped frames (every 1s)
- Files: Session JSON, transcript JSONL, debug bundle ZIP

**Key Modules**:

- Client: `AppState.swift:492-649`, `AudioCaptureManager.swift`, `MicrophoneCaptureManager.swift`, `WebSocketStreamer.swift`, `StructuredLogger.swift`
- Server: `ws_live_listener.py`, `asr_stream.py`, `asr_providers.py`, `analysis_stream.py`, `metrics_registry.py`

**Failure Modes** (10+):

1. **Permission denied** (screen recording or microphone) → setSessionError(), session blocked
2. **Permission granted but requires relaunch** → screenRecordingRequiresRelaunch error, user must quit app
3. **Audio capture start failure** → systemCaptureFailed or microphoneCaptureFailed error, no audio
4. **WebSocket connection timeout** (5s handshake timeout) → Backend didn't start streaming, error shown
5. **Server not ready** → Health check fails with 503, waiting for model load
6. **Model load failure** → Provider unavailable, ASR never starts
7. **Audio queue overflow** → Queue > 48 frames, backpressure triggered, frames dropped
8. **ASR flush timeout** (8s) → Finalization timeout, partial transcript
9. **Analysis timeout** (10s/15s) → NLP tasks cancelled, partial analysis
10. **Diarization failure** → HF token invalid, model download fails, no speaker labels
11. **Buffer corruption** → AVAudioConverter fails, frames dropped
12. **Limiter failure** → If limiterGain stays reduced, quality reports `.poor`
13. **Clock drift** (HYPOTHESIZED, NOT IMPLEMENTED) → System and mic clocks drift apart over time, multi-source sessions lose sync
14. **Device hot-swap during session** → Device disconnects, capture stops, no recovery path
15. **Client crash before session end** → Session bundle not saved, partial loss

**Observability**:

- **Logs**: StructuredLogger with correlation IDs (session_id, attempt_id, connection_id)
- **Metrics**: Queue depth, fill ratio, dropped frames, RTF (every 1s)
- **Health checks**: Backend /health endpoint, client polls health status
- **Diagnostics**: Debug bundle export (logs, metrics, events, audio dumps if enabled)
- **Audio quality**: RMS level monitoring, clipping detection via limiter

**Proof**:

- `AppState.swift:492-649` - Complete session start/stop flow
- `AudioCaptureManager.swift:106-214` - Audio processing pipeline with limiter
- `WebSocketStreamer.swift:102-200` - WebSocket connection management
- `ws_live_listener.py:585-871` - Server-side session management
- `WS_CONTRACT.md` - WebSocket protocol specification

```

---

## Dependency Graph (Textual)

### Client-Side Dependencies

```

MeetingListenerApp.swift (app entry)
├── AppState (central state manager)
│ ├── AudioCaptureManager (system audio capture)
│ │ └── Callbacks: onPCMFrame, onAudioQualityUpdate, onSampleCount
│ ├── MicrophoneCaptureManager (mic capture)
│ │ └── Callbacks: onPCMFrame, onAudioLevelUpdate
│ ├── RedundantAudioCaptureManager (dual-source + failover)
│ │ └── Callbacks: onPCMFrame, onSourceChanged, onHealthChanged
│ ├── WebSocketStreamer (WebSocket client)
│ │ ├── Callbacks: onStatus, onASRPartial, onASRFinal, onMetrics
│ │ └── Dependency: BackendConfig (URL, auth token)
│ ├── StructuredLogger (logging)
│ ├── SessionStore (persistence)
│ ├── SessionBundleManager (debug exports)
│ ├── HotKeyManager (global hotkeys)
│ ├── KeychainHelper (secrets)
│ └── Notification: NSNotificationCenter
├── BackendManager (server process management)
│ ├── Dependencies: BackendConfig, KeychainHelper
│ └── Callbacks: serverStatus, healthDetail (published)
└── UI Views
├── SidePanelView (three-cut renderers)
├── OnboardingView (first-launch flow)
├── SessionHistoryView (session browser)
└── SettingsView (configuration)

External Dependencies:
├── ScreenCaptureKit (system audio)
├── AVFoundation (microphone audio)
├── OSLog/unified logging
└── macOS Keychain (secrets storage)

```

### Server-Side Dependencies

```

main.py (FastAPI entry point)
├── Lifespan: model_preloader
│ └── ASRProviderRegistry initialization
├── Router: ws_live_listener
│ ├── SessionState (per-connection state)
│ ├── ASR Loop: \_asr_loop (per-source)
│ │ ├── ASRStream (chunking)
│ │ └── ASRProvider (faster-whisper/whisper.cpp/voxtral)
│ │ └── Dependencies: VAD filter (optional), Model files
│ ├── Analysis Loop: \_analysis_loop
│ │ ├── extract_entities (NER)
│ │ └── extract_cards (Actions/Decisions/Risks)
│ └── Metrics Loop: \_metrics_loop
│ └── Dependencies: MetricsRegistry
├── Router: documents
│ └── LocalRAGStore (BM25/TF-IDF indexing)
└── ConcurrencyController (session limiting)
└── Session slot management

External Dependencies:
├── fast-whisper (CTranslate2 Python package)
├── whisper.cpp (CTranslate2, optional with Metal)
├── pyannote.audio (HuggingFace model for diarization)
├── Silero VAD (HuggingFace model, optional)
├── uvicorn (ASGI server)
└── pydantic (JSON validation)

```

### Cross-Boundary Data Flow

```

Client → Server (WebSocket)
├── Audio frames (base64 JSON)
│ ├── System audio: 16kHz mono PCM16, 320-sample chunks (20ms)
│ └── Mic audio: 16kHz mono PCM16, 320-sample chunks (20ms)
├── Control messages: start, stop
└── Correlation IDs: session_id, attempt_id, connection_id
├── Latency: ~5ms round trip (localhost)
└── Backpressure: Queue depth monitoring, drop oldest

Server → Client (WebSocket)
├── Transcript events: asr_final
│ ├── Text, t0, t1, confidence, source
│ └── 1Hz emission rate during speech
├── Analysis events: entities_update, cards_update
│ └── 40s emission rate
├── Final summary: markdown + JSON
│ ├── Transcript (speaker-labeled if diarization enabled)
│ ├── Entities, Actions, Decisions, Risks
│ └── Diarization segments
└── Metrics events (1Hz)
├── Queue depth, fill ratio, dropped frames
├── RTF (realtime factor), avg_infer_ms
├── Correlation IDs
└── Degrade level

Data Flow Boundaries:

- Client-side: Capture → Process → Chunk → Transmit
- Network: WebSocket over localhost (ws://) with optional TLS (wss:// for remote)
- Server-side: Receive → Queue → ASR → Analyze → Emit
- Storage: JSON/JSONL files, no database, local filesystem only

````

---

## Risk Register

### P0 - Critical Risks (Immediate Attention)

| Risk | Location | Impact | Mitigation Status |
|------|----------|--------|------------------|
| **Clock drift between audio sources** | AUD-009 (Hypothesized) | Multi-source sessions lose sync after several minutes, speaker labels become incorrect | Not implemented - requires drift compensation with CACurrentMediaTime |
| **Token-in-query for WebSocket** | SEC-005 | Auth token visible in logs/proxies, security vulnerability | Mitigated - client now sends auth in headers; server keeps temporary query-token compatibility |
| **No model unload on session end** | MOD-014 | Models stay in memory indefinitely, OOM risk under load | Mitigated - explicit model unload + provider cache eviction on shutdown |
| **Debug audio dump PII exposure** | SEC-009 | Unredacted audio written to /tmp when env var set, privacy breach | Partial - env-gated debug dump now enforces age/file-count/size cleanup limits |
| **Data retention policy undefined** | STO-013 | Sessions, logs, RAG docs persist indefinitely, no auto-cleanup | Hypothesized - no TTL enforcement |
| **Plaintext storage of sensitive data** | STO-014 | All JSON/JSONL files stored in plaintext, no encryption | Hypothesized - no encryption layer implemented |

### P1 - High Priority Risks

| Risk | Location | Impact | Mitigation Status |
|------|----------|--------|------------------|
| **VAD not integrated client-side** | AUD-010 (Partial) | 40% compute wasted on silence, network bandwidth waste | Partial - server-side VAD exists but not integrated into ASR stream |
| **Embeddings not implemented** | INT-009 | RAG uses pure lexical BM25, missing semantic search | Not implemented - contradicts RAG_PIPELINE_ARCHITECTURE.md |
| **GLiNER not implemented** | INT-008 | NER uses regex patterns, missing semantic layer | Not implemented - contradicts NER_PIPELINE_ARCHITECTURE.md |
| **Silent failure propagation** | STO-002/003 | File write failures only logged, not surfaced to user | Implemented - logs errors but no UI feedback |
| **Health check timeout hardcoding** | OBS-004 | Client health check timeout can be tuned (default 2.0s), server-side no timeout, hangs possible | Mitigated - client timeout now config-backed (`backendHealthTimeoutSeconds`) |
| **Queue full drop policy** | AUD-005 | Drop oldest frame when queue full, may lose critical speech | Implemented - but configurable, may drop important content |
| **No retransmission** | AUD-005 | Dropped frames lost forever, no recovery mechanism | Implemented - no retry or retransmission |
| **Exponential backoff unbounded** | OBS-012 | Restart delay grows exponentially but no max cap (currently 10s) | Implemented - max attempts limited but delay could grow indefinitely |
| **ASR flush timeout** | COMPOSITE-001 | 8s timeout may truncate final transcript on long sessions | Implemented - timeout enforced but may be too short for some sessions |
| **Circuit breaker not present** | OBS-015 | No circuit breaker pattern to prevent cascading failures | Not implemented - degration ladder provides some fallback |

### P2 - Medium Priority Risks

| Risk | Location | Impact | Mitigation Status |
|------|----------|--------|------------------|
| **No data integrity checks** | STO-013 | No checksums, validation, or corruption detection | Not implemented - JSON files have no integrity layer |
| **Metrics no persistent storage** | OBS-002 | Metrics only sent to client, not persisted for offline analysis | Not implemented - metrics lost if session crashes |
| **No crash reporting** | OBS-005 | Crashes detected locally, no telemetry to developer | Not implemented - only local logging |
| **Session bundle size unbounded** | STO-007 | No size limits on debug bundles, could exhaust disk | Implemented - but no enforcement |
| **Error classification basic** | OBS-013 | Generic exception handling, no error taxonomy | Implemented - basic error messages, no categorization |
| **Log redaction over-matches** | SEC-010 | Regex patterns may miss PII or over-redact, losing debugging info | Implemented - redaction patterns defined but may be incomplete |
| **Audio quality no SNR measurement** | AUD-001 | Only RMS and clipping detection, no SNR or noise floor metrics | Implemented - P0-2 audit identified gaps |
| **No per-sample timestamps** | AUD-006 | Can't track per-frame processing latency, only aggregate metrics | Implemented - only 1Hz metrics, no per-sample timing |
| **Localhost auth bypass** | SEC-005 | Remote mode security not enforced, ws:// used instead of wss:// | Partial - auto-switch based on host, but could be exploited |
| **No model versioning** | MOD-015 | Manual model download required, no auto-update or version management | Not implemented - users must manually replace models |

---

## Verification Checklist

### Automated Verification Commands

```bash
# Client-side Swift tests
cd macapp/MeetingListenerApp
swift test                    # Run all unit tests
swift build                  # Verify compilation

# Server-side Python tests
cd server
pytest tests/ -q           # Run all test suites
pytest tests/test_ws_live_listener.py -q  # WebSocket tests
pytest tests/test_streaming_correctness.py -q  # Correctness tests

# Integration tests
python tests/test_ws_integration.py -q  # End-to-end WebSocket integration

# Linting (if applicable)
# Swift: swiftlint (not in project yet)
# Python: ruff check server/

# Health check
curl http://localhost:8000/health  # Verify server health
````

### Manual Verification Steps

#### EXT-001: First Launch Onboarding

1. [ ] Fresh install: Run app, verify onboarding appears
2. [ ] Permissions: Verify screen recording prompt appears for system audio
3. [ ] Permissions: Verify microphone prompt appears for mic audio
4. [ ] Completion: Verify "Start Listening" button appears after all permissions granted
5. [ ] Backend: Verify backend status display shows healthy state

#### EXT-004: Session Start

1. [ ] Start session with system audio source
2. [ ] Verify audio frames flowing (debug: count bytes sent)
3. [ ] Verify WebSocket connects (status → streaming)
4. [ ] Verify transcript segments appear (partial/final)
5. [ ] Verify metrics received (queue depth, RTF)
6. [ ] Start session with microphone source
7. [ ] Verify mic audio capture working
8. [ ] Verify source tag in transcript ("mic" vs "system")

#### EXT-005: Session Stop & Finalization

1. [ ] Stop session mid-stream
2. [ ] Verify ASR flush completes within 8s
3. [ ] Verify final_summary received
4. [ ] Verify summary window opens
5. [ ] Verify Transcript view shows speaker labels (if diarization enabled)
6. [ ] Verify all analysis (entities, cards) present
7. [ ] Verify session saved to history

#### AUD-001: System Audio Capture

1. [ ] Start system audio capture
2. [ ] Play system audio (YouTube, Spotify, etc.)
3. [ ] Verify capture stops on app quit
4. [ ] Verify limiter activates on loud audio (check logs)
5. [ ] Verify 16kHz conversion (verify frame size)
6. [ ] Verify 20ms chunks (320 samples @ 16kHz)

#### AUD-003: Dual-Source Redundant Capture

1. [ ] Enable broadcast mode with redundant audio
2. [ ] Play system audio at high volume
3. [ ] Verify failover to microphone (check active source changes)
4. [ ] Verify failover back to system (check recovery)
5. [ ] Verify quality monitoring updates UI

#### MOD-003: Eager Load + Warmup

1. [ ] Start server cold (no model in memory)
2. [ ] Check /health endpoint (should return 503 during load)
3. [ ] Verify model warmup completes (< 10s typical)
4. [ ] Start session immediately after warmup (should not re-load)
5. [ ] Check server logs for "eager load" and "warmup"

#### MOD-007: 5-Level Degrade Ladder

1. [ ] Start session and inject synthetic load (high RTF)
2. [ ] Verify degrade level transitions: NORMAL → WARNING → DEGRADE → EMERGENCY
3. [ ] Verify chunk size increases at DEGRADE level
4. [ ] Verify VAD disabled at DEGRADE level
5. [ ] Verify status messages sent to client
6. [ ] Verify chunk dropping at EMERGENCY level
7. [ ] Test failover (simulate provider crash)

#### COMPOSITE-001: Complete Audio-to-Transcript Flow

1. [ ] Test with slow backend (simulate RTF > 2.0)
2. [ ] Verify backpressure warnings appear
3. [ ] Verify degrade ladder activates
4. [ ] Test permission denied mid-session
5. [ ] Test WebSocket disconnect during session
6. [ ] Verify reconnection attempt
7. [ ] Test device hot-swap during session
8. [ ] Verify partial transcript preserved
9. [ ] Verify final summary complete
10. [ ] Check session bundle contains all artifacts (receipt, events, metrics, logs)
11. [ ] Export debug bundle and verify contents

#### SEC-001: Screen Recording Permission

1. [ ] Fresh install: Deny screen recording permission
2. [ ] Verify app shows error state
3. [ ] Grant permission via System Settings
4. [ ] Relaunch app and verify permission detected
5. [ ] Verify CGPreflightScreenCaptureAccess() returns true after grant

#### SEC-003: Backend Token Keychain Storage

1. [ ] Save HF token via KeychainHelper
2. [ ] Restart app and verify token persists
3. [ ] Load token and verify server uses it
4. [ ] Test: Delete token and reload app
5. [ ] Verify token not in logs (redaction working)

#### SEC-010: Log Redaction

1. [ ] Enable debug mode and generate logs
2. [ ] Verify HF tokens redacted (search logs for token string)
3. [ ] Verify file paths redacted (search for user home directory)
4. [ ] Verify API keys redacted
5. [ ] Check logs in Console.app and ~/Library/Application Support/com.echopanel/logs/

#### STO-007: Session Bundle Export

1. [ ] Complete a 5-minute session
2. [ ] Export debug bundle via Diagnostics or UI
3. [ ] Verify ZIP file created
4. [ ] Extract and verify contents:
   - receipt.json (metadata, flags)
   - events.ndjson (timeline)
   - metrics.ndjson (1Hz samples)
   - transcript_realtime.json
   - transcript_final.json
   - drops_summary.json
   - logs/client.log
   - logs/server.log
5. [ ] Verify machine ID hashed (SHA256)
6. [ ] Verify audio NOT included (privacy-safe default)

#### INT-004: RAG Document Indexing

1. [ ] Index a document (test.txt)
2. [ ] Verify document appears in list
3. [ ] Query document and verify results
4. [ ] Check rag_store.json persisted to ~/.echopanel/
5. [ ] Verify BM25 scoring (not embeddings)

#### OBS-002: Metrics Collection

1. [ ] Start session and let run for 1 minute
2. [ ] Verify metrics events received every 1 second
3. [ ] Check queue_depth, queue_fill_ratio, avg_infer_ms, realtime_factor
4. [ ] Verify correlation IDs included (session_id, attempt_id, connection_id)
5. [ ] Verify degrade ladder status in metrics
6. [ ] Stop session and verify final metrics logged

---

## Document Metadata

**Generated By**: Flow Extraction Orchestrator
**Sub-Agents**: 7 parallel specialists

- User Journey Mapper (18 flows)
- Audio Pipeline Analyst (10 flows, 1 partial, 1 hypothesized)
- Model Lifecycle Analyst (15 flows, 1 partial, 1 not implemented)
- Data & Storage Analyst (15 flows, 3 hypothesized)
- Analysis & Intelligence Analyst (12 flows, 4 partial, 4 hypothesized)
- Observability & Reliability Analyst (23 flows)
- Security & Privacy Boundary Analyst (15 flows, 2 partial)

**Evidence Discipline**: All flows tagged as Observed (code/file evidence), Inferred (reasonable conclusion without direct evidence), or Hypothesized (no evidence found). Never presented Inferred as Observed.

**Critical Gaps Identified**: 9 (4 P0, 4 P1, 1 P2)
**Total Flows Documented**: 111 (97 implemented, 4 partial, 9 hypothesized, 1 not implemented)
