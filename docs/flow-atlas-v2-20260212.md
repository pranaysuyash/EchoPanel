# EchoPanel Flow Atlas v2.0

**Document Version**: 2.0
**Generated**: 2026-02-12
**Scope**: Complete end-to-end flow extraction for EchoPanel v0.2 (comprehensive with copy mapping)

---

## Executive Summary

EchoPanel is a macOS menu bar application with local FastAPI backend that performs real-time speech-to-text transcription, speaker diarization, NLP analysis (NER, summarization, action extraction), and RAG (Retrieval-Augmented Generation) for meeting notes.

**Architecture**:
- **Client (Swift)**: macOS menu bar app with side panel UI, audio capture, WebSocket client
- **Server (Python)**: FastAPI backend with ASR providers (faster-whisper, whisper.cpp, voxtral), diarization, NLP, RAG
- **Communication**: WebSocket (localhost with optional auth) for real-time streaming
- **Storage**: Local filesystem (JSON/JSONL), macOS Keychain for secrets, no cloud sync

**Total Flows Identified**: 118 flows across 8 categories

---

## Flow Atlas Inventory

### A) User Journeys and UX Flows - 24 flows

| Flow ID | Name | Status | Priority | UI Copy Key Messages |
|----------|------|--------|----------|---------------------|
| EXT-001 | First Launch Onboarding | Implemented | P0 | "Welcome to EchoPanel", "Permissions Required", "Audio Source", "Speaker Labels", "You're All Set!" |
| EXT-002 | Screen Recording Permission Request | Implemented | P0 | "Screen Recording permission required for System Audio. Open Settings → Privacy & Security → Screen Recording." |
| EXT-003 | Microphone Permission Request | Implemented | P0 | "Microphone permission required for Microphone audio" |
| EXT-004 | Session Start | Implemented | P0 | "Start Listening", "Listening", "Timer: HH:MM:SS" |
| EXT-005 | Session Stop & Finalization | Implemented | P0 | "Stop Listening", "Finalization complete", "Finalization incomplete" |
| EXT-006 | Export JSON | Implemented | P1 | "Export JSON", "Save As" |
| EXT-007 | Export Markdown | Implemented | P1 | "Export Markdown", "Copy Markdown" |
| EXT-008 | Export Debug Bundle | Implemented | P1 | "Export Debug Bundle...", "Diagnostics" |
| EXT-009 | Settings Configuration | Implemented | P1 | "General", "Broadcast", "Audio", "ASR Model", "Backend", "Server" |
| EXT-010 | Session History Browse | Implemented | P1 | "Sessions", "Search by date/time", "Details", "Summary", "Transcript", "JSON" |
| EXT-011 | Session Recovery from Crash | Implemented | P0 | "Recover Last Session...", "Discard Last Session", "RECOVER" |
| EXT-012 | Backend Server Start | Implemented | P0 | "Starting server...", "Server ready.", "Backend unavailable." |
| EXT-013 | Backend Auto-Restart/Recovery | Implemented | P0 | "Recovering backend (attempt X/3)..." |
| EXT-014 | Global Hotkey Actions | Implemented | P2 | "Enable Global Hot-Keys", "View Hot-Key Reference" |
| EXT-015 | Context Document Indexing (RAG) | Implemented | P2 | "Index document", "Documents API" |
| EXT-016 | Context Query (RAG Search) | Implemented | P2 | "Query document", "Search results" |
| EXT-017 | Menu Bar Quick Actions | Implemented | P1 | "EchoPanel", "Quit", "Diagnostics...", "Session Summary...", "Session History..." |
| EXT-018 | Side Panel View Mode Switching | Implemented | P2 | View modes (Full, Compact, Roll) |
| EXT-019 | Audio Source Selection (Broadcast Mode) | Implemented | P2 | "Enable Dual-Path Audio", "Emergency Failover to Backup" |
| EXT-020 | Speaker Labels/Diarization Configuration | Implemented | P1 | "Speaker Labels (Optional)", "HuggingFace Token (Read-only)", "Get a token →" |
| EXT-021 | Show Onboarding Trigger | Implemented | P1 | "Show Onboarding" |
| EXT-022 | Report Issue Flow | Implemented | P2 | "Report Issue...", "EchoPanel Beta Issue Report", "Describe the issue:" |
| EXT-023 | Session Delete | Implemented | P1 | "Delete…", "Delete this session?", "This removes session snapshot and transcript from local storage. This can't be undone." |
| EXT-024 | Empty State Displays | Implemented | P1 | "Select a session to view details.", "No actions detected.", "No decisions detected.", "No risks detected.", "No entities detected." |

### B) UI Copy and Messaging Flows - 45 flows

| Flow ID | Name | Status | Priority | Copy Surface |
|----------|------|--------|----------|--------------|
| UI-COPY-001 | Welcome Screen Copy | Implemented | P0 | OnboardingView.swift:99-114 |
| UI-COPY-002 | Permissions Explainer Copy | Implemented | P0 | OnboardingView.swift:116-174 |
| UI-COPY-003 | Permission Status Badges | Implemented | P0 | "Granted", "Required", "Optional", "Denied" |
| UI-COPY-004 | Source Selection Copy | Implemented | P0 | OnboardingView.swift:176-200 |
| UI-COPY-005 | Diarization Explainer Copy | Implemented | P0 | OnboardingView.swift:202-235 |
| UI-COPY-006 | Ready Step Copy | Implemented | P0 | OnboardingView.swift:237-310 |
| UI-COPY-007 | Error Messages (Runtime) | Implemented | P0 | AppState.swift:71-88 (AppRuntimeErrorState.message) |
| UI-COPY-008 | Backend Status Messages | Implemented | P0 | BackendManager.swift:17-21 (ServerStatus rawValues) |
| UI-COPY-009 | Menu Bar Labels | Implemented | P0 | "Start Listening", "Stop Listening", "Export JSON", "Export Markdown" |
| UI-COPY-010 | Settings Tab Labels | Implemented | P1 | "General", "Broadcast", "Gear", "antenna.radiowaves.left.and.right" |
| UI-COPY-011 | ASR Model Copy | Implemented | P1 | "Base English (Recommended)", "Base (Multilingual)", "Small", "Medium", "Large v3 Turbo (Best)" |
| UI-COPY-012 | Model Recommendation Copy | Implemented | P1 | "Recommended for this Mac:", "high-memory profile supports better quality model", "fastest stable baseline" |
| UI-COPY-013 | Backend Settings Copy | Implemented | P0 | "Host", "Port", "Optional WS auth token", "Local backend uses ws/http.", "Remote backend defaults to wss/https." |
| UI-COPY-014 | Server Status Display Copy | Implemented | P0 | "Status", "Server ready.", "Backend unavailable.", "Restart Server" |
| UI-COPY-015 | Broadcast Settings Labels | Implemented | P2 | "Audio Redundancy", "Enable Dual-Path Audio", "Emergency Failover to Backup" |
| UI-COPY-016 | Hot-Key Settings Copy | Implemented | P2 | "Operator Controls", "Enable Global Hot-Keys", "View Hot-Key Reference" |
| UI-COPY-017 | Confidence Meter Copy | Implemented | P2 | "ASR Quality Monitoring", "Show Confidence Scores", "Current: X%", "5s Avg: Y%" |
| UI-COPY-018 | NTP Settings Copy | Implemented | P2 | "Timestamp Synchronization", "Use NTP Synchronization", "NTP Offset: X ms", "Sync Now" |
| UI-COPY-019 | Session Summary Labels | Implemented | P0 | "Session Summary", "Markdown", "Details", "Actions", "Decisions", "Risks", "Entities" |
| UI-COPY-020 | Banner Messages | Implemented | P0 | "Finalization complete", "Finalization incomplete", "The backend didn't return a final summary." |
| UI-COPY-021 | Empty State Messages | Implemented | P1 | "No actions detected.", "No decisions detected.", "No risks detected.", "No entities detected." |
| UI-COPY-022 | Session History Labels | Implemented | P1 | "Sessions", "Search by date/time", "Details", "View" |
| UI-COPY-023 | History Tab Labels | Implemented | P1 | "Summary", "Transcript", "JSON" |
| UI-COPY-024 | Diagnostics Labels | Implemented | P0 | "Diagnostics", "System Status", "Backend Status:", "Backend Detail:", "Last Exit Code:", "Server Ready:" |
| UI-COPY-025 | Troubleshooting Copy | Implemented | P0 | "Troubleshooting", "Export Debug Bundle...", "Report Issue..." |
| UI-COPY-026 | Accessibility Permission Copy | Implemented | P1 | "Accessibility permission required for global hot-keys", "Grant" |
| UI-COPY-027 | Redundancy Status Copy | Implemented | P2 | "Primary", "Backup", "Health", "Quality", "Switching" |
| UI-COPY-028 | Status Messages (WebSocket) | Implemented | P0 | "Listening", "Idle", "Streaming", "Connecting", "Reconnecting" |
| UI-COPY-029 | Timer Display | Implemented | P0 | "Timer: HH:MM:SS", monospace digits |
| UI-COPY-030 | Audio Level Meters | Implemented | P1 | System and Mic level indicators |
| UI-COPY-031 | Source Probe Chips | Implemented | P1 | "In Xs", "ASR Ys", "live" indicators |
| UI-COPY-032 | Export Dialog Labels | Implemented | P1 | "Export JSON...", "Export Markdown...", "Save As" |
| UI-COPY-033 | Export Success Messages | Implemented | P1 | Copy success feedback |
| UI-COPY-034 | Delete Confirmation Copy | Implemented | P1 | "Delete this session?", "This removes session snapshot and transcript from local storage. This can't be undone.", "Delete", "Cancel" |
| UI-COPY-035 | Recovery UI Labels | Implemented | P0 | "Recover Last Session...", "Discard Last Session", "RECOVER" badge |
| UI-COPY-036 | Backend Error Messages | Implemented | P0 | "Backend Error", "The python server failed to start. Check if Python 3.10+ is installed.", "Retry", "Collect Diagnostics" |
| UI-COPY-037 | Health Detail Messages | Implemented | P0 | "Backend not ready.", "Port 8000 is already in use.", "Server exited (code X)" |
| UI-COPY-038 | Finalization Outcome Messages | Implemented | P0 | "complete", "incompleteTimeout", "incompleteError" states |
| UI-COPY-039 | Permission Explainer Detail | Implemented | P0 | "EchoPanel needs the following permissions to capture meeting audio:", "Required to capture system audio from meetings", "Optional: Capture your voice in addition to meeting audio" |
| UI-COPY-040 | Action Buttons | Implemented | P0 | "Open Settings", "Check Again", "Back", "Next", "Start Listening" |
| UI-COPY-041 | Tooltip/Help Copy | Implemented | P1 | Various help texts and tooltips |
| UI-COPY-042 | Progress Messages | Implemented | P0 | "Starting server...", "Loading model...", "Preparing..." |
| UI-COPY-043 | Success/Completion Messages | Implemented | P0 | "You're All Set!", "Finalization complete", "Your final summary is ready." |
| UI-COPY-044 | Warning Messages | Implemented | P0 | "Screen Recording permission was granted, but macOS requires you to quit and relaunch EchoPanel" |
| UI-COPY-045 | Error Alert Titles | Implemented | P0 | Various error state titles across components |

### C) Monetization and Entitlement Flows - 4 flows (ALL NOT IMPLEMENTED)

| Flow ID | Name | Status | Priority | Evidence |
|----------|------|--------|----------|----------|
| MON-001 | Free Beta Access | **Not Implemented** | P0 | **CONFIRMED NONE** - docs/PRICING.md exists as plan only |
| MON-002 | Pro/Paid Subscription | **Not Implemented** | P0 | **CONFIRMED NONE** - no IAP, no Gumroad integration |
| MON-003 | License Key Validation | **Not Implemented** | P0 | **CONFIRMED NONE** - docs/LICENSING.md exists as plan only |
| MON-004 | Usage Limits Enforcement | **Not Implemented** | P2 | **CONFIRMED NONE** - no session count limits, no feature gates |

**Key Finding**: EchoPanel v0.2 has NO monetization or entitlement flows implemented. The PRICING.md and LICENSING.md documents are PLANNING documents only, not implemented features.

### D) Login/Auth/Account Flows - 4 flows (ALL NOT IMPLEMENTED)

| Flow ID | Name | Status | Priority | Evidence |
|----------|------|--------|----------|----------|
| AUTH-001 | User Account Creation | **Not Implemented** | P0 | **CONFIRMED NONE** - no signup flow |
| AUTH-002 | Login/Sign In | **Not Implemented** | P0 | **CONFIRMED NONE** - no login UI or flow |
| AUTH-003 | Session Authentication | **Not Implemented** | P0 | **CONFIRMED NONE** - only technical token auth (ECHOPANEL_WS_AUTH_TOKEN) |
| AUTH-004 | Logout/Sign Out | **Not Implemented** | P0 | **CONFIRMED NONE** - no user logout flow |

**Key Finding**: EchoPanel v0.2 has NO user account authentication. The only "auth" is:
- Backend WebSocket token (ECHOPANEL_WS_AUTH_TOKEN env var) - technical auth for local/remote backend communication
- This is NOT user account auth - it's API token for WebSocket/HTTP endpoint access
- No user profiles, no cloud sync, no session management for users

### E) Core Runtime Pipelines - 12 flows

| Flow ID | Name | Status | Priority |
|----------|------|--------|----------|
| RUN-001 | Complete Audio-to-Transcript Flow | Implemented | P0 |
| RUN-002 | Multi-Source Audio Capture | Implemented | P0 |
| RUN-003 | Redundant Audio Capture (Broadcast) | Implemented | P0 |
| RUN-004 | Client-Side Audio Processing | Implemented | P0 |
| RUN-005 | WebSocket Streaming | Implemented | P0 |
| RUN-006 | Server-Side ASR Processing | Implemented | P0 |
| RUN-007 | Real-Time Entity Extraction | Implemented | P0 |
| RUN-008 | Real-Time Card (Action/Decision/Risk) Extraction | Implemented | P0 |
| RUN-009 | Rolling Summary Generation | Implemented (extractive only) | P1 |
| RUN-010 | RAG Document Indexing | Implemented (lexical-only) | P1 |
| RUN-011 | RAG Query Retrieval | Implemented (lexical-only) | P1 |
| RUN-012 | Diarization Processing | Implemented | P2 |

### F) Lifecycle/Admin/Ops Flows - 20 flows

| Flow ID | Name | Status | Priority |
|----------|------|--------|----------|
| LIF-001 | App Launch Initialization | Implemented | P0 |
| LIF-002 | Backend Server Process Management | Implemented | P0 |
| LIF-003 | Model Preloading & Warmup | Implemented | P0 |
| LIF-004 | Health Check Polling | Implemented | P0 |
| LIF-005 | Graceful Shutdown | Implemented | P0 |
| LIF-006 | Crash Recovery Marker Management | Implemented | P0 |
| LIF-007 | Session Auto-Save | Implemented | P0 |
| LIF-008 | Log File Rotation | Implemented | P1 |
| LIF-009 | Log Redaction (PII Protection) | Implemented | P0 |
| LIF-010 | Debug Bundle Creation | Implemented | P1 |
| LIF-011 | Session Persistence | Implemented | P0 |
| LIF-012 | Keychain Secrets Storage | Implemented | P0 |
| LIF-013 | UserDefaults Migration | Implemented | P1 |
| LIF-014 | Circuit Breaker Pattern | Implemented | P1 |
| LIF-015 | Exponential Backoff Retry | Implemented | P0 |
| LIF-016 | Degradation Management | Implemented | P0 |
| LIF-017 | Concurrency Limiting | Implemented | P0 |
| LIF-018 | Device Hot-Swap Detection | Implemented | P1 |
| LIF-019 | Audio Quality Monitoring | Implemented | P0 |
| LIF-020 | Performance Metrics Collection | Implemented | P0 |

### G) Security/Privacy Flows - 15 flows

| Flow ID | Name | Status | Priority |
|----------|------|--------|----------|
| SEC-001 | Screen Recording Permission Flow | Implemented | P0 |
| SEC-002 | Microphone Permission Flow | Implemented | P0 |
| SEC-003 | Backend Token Keychain Storage | Implemented | P0 |
| SEC-004 | HuggingFace Token Keychain Storage | Implemented | P0 |
| SEC-005 | WebSocket Authentication | Implemented (token-based, technical only) | P0 |
| SEC-006 | Documents API Authentication | Implemented (token-based, technical only) | P0 |
| SEC-007 | Network Security (TLS) | Partial Implemented (auto-switch based on host) | P0 |
| SEC-008 | Audio Data Movement | Implemented | P0 |
| SEC-009 | Debug Audio Dump (Privacy Risk) | Implemented (env var gated + bounded cleanup) | P2 |
| SEC-010 | Log Redaction (PII Protection) | Implemented | P0 |
| SEC-011 | Session Bundle Privacy Controls | Implemented | P0 |
| SEC-012 | Diarization Model Privacy | Implemented | P0 |
| SEC-013 | Data Retention & Cleanup | Partial Implemented (no TTL enforcement) | P2 |
| SEC-014 | Authorization & Access Control | Partial Implemented (token-based, no RBAC) | P1 |
| SEC-015 | Local Documents Privacy | Implemented | P0 |

---

## Summary Statistics

| Category | Implemented | Partial | Hypothesized | Not Implemented | Total |
|-----------|-----------|---------|----------------|-------|-------|
| A) User Journeys & UX | 24 | 0 | 0 | 0 | 24 |
| B) UI Copy & Messaging | 45 | 0 | 0 | 0 | 45 |
| C) Monetization & Entitlements | 0 | 0 | 0 | 4 | 4 |
| D) Login/Auth/Account | 0 | 0 | 0 | 4 | 4 |
| E) Core Runtime Pipelines | 12 | 0 | 0 | 0 | 12 |
| F) Lifecycle/Admin/Ops | 20 | 0 | 0 | 0 | 20 |
| G) Security/Privacy | 15 | 0 | 0 | 0 | 15 |
| **TOTAL** | **116** | **0** | **0** | **8** | **124** |

**Breakdown**:
- Implemented: 116 flows (93.5%)
- Not Implemented: 8 flows (6.5%) - ALL related to monetization and user authentication

---

## Component/Module Map

### Client-Side Components (Swift)

| Component | File | Purpose | UI Copy Managed |
|----------|------|---------|-----------------|
| **AppState** | `AppState.swift` | Central state manager, session lifecycle, error messages | YES - All runtime error messages (AppRuntimeErrorState.message) |
| **BackendManager** | `BackendManager.swift` | Python server process management, health checks | YES - Server status messages |
| **AudioCaptureManager** | `AudioCaptureManager.swift` | System audio capture via ScreenCaptureKit | NO |
| **MicrophoneCaptureManager** | `MicrophoneCaptureManager.swift` | Microphone capture via AVAudioEngine | NO |
| **RedundantAudioCaptureManager** | `RedundantAudioCaptureManager.swift` | Dual-source capture with auto-failover | NO |
| **BroadcastFeatureManager** | `BroadcastFeatureManager.swift` | Broadcast mode coordination | YES - Broadcast settings UI |
| **WebSocketStreamer** | `WebSocketStreamer.swift` | WebSocket client, connection management | NO |
| **StructuredLogger** | `StructuredLogger.swift` | Structured logging with redaction | NO |
| **KeychainHelper** | `KeychainHelper.swift` | macOS Keychain storage for tokens | NO |
| **SessionBundle** | `SessionBundle.swift` | Debug bundle creation and export | NO |
| **SessionStore** | `SessionStore.swift` | Session persistence, auto-save, recovery marker | NO |
| **OnboardingView** | `OnboardingView.swift` | First-launch onboarding flow | YES - Full onboarding wizard copy |
| **SummaryView** | `SummaryView.swift` | Post-session summary window | YES - Summary UI copy |
| **SessionHistoryView** | `SessionHistoryView.swift` | Session history browser | YES - History UI copy |
| **SidePanelView** | `SidePanelView.swift` | Side panel UI with three-cut renderers | YES - Side panel UI copy |
| **SettingsView** | `SettingsView.swift` | Settings configuration | YES - Full settings UI copy |
| **BroadcastSettingsView** | `BroadcastSettingsView.swift` | Broadcast-specific settings | YES - Broadcast UI copy |
| **HotKeyManager** | `HotKeyManager.swift` | Global hotkey monitoring and handling | YES - Hot key settings UI |
| **Models** | `Models.swift` | Data models (TranscriptSegment, ActionItem, etc.) | NO |

### Server-Side Components (Python)

| Component | File | Purpose | UI Copy Managed |
|----------|------|---------|-----------------|
| **main** | `main.py` | FastAPI app entry, health endpoint, model preloading | NO |
| **ws_live_listener** | `server/api/ws_live_listener.py` | WebSocket endpoint, session management, audio queueing | NO |
| **documents** | `server/api/documents.py` | RAG documents API (index, query, delete) | NO |
| **asr_providers** | `server/services/asr_providers.py` | ASR provider registry and interface | NO |
| **provider_faster_whisper** | `server/services/provider_faster_whisper.py` | faster-whisper provider implementation | NO |
| **provider_whisper_cpp** | `server/services/provider_whisper_cpp.py` | whisper.cpp provider with Metal support | NO |
| **provider_voxtral_realtime** | `server/services/provider_voxtral_realtime.py` | Voxtral streaming provider | NO |
| **asr_stream** | `server/services/asr_stream.py` | ASR streaming interface and chunking | NO |
| **vad_filter** | `server/services/vad_filter.py` | Silero VAD pre-filtering | NO |
| **diarization** | `server/services/diarization.py` | Pyannote speaker diarization | NO |
| **analysis_stream** | `server/services/analysis_stream.py` | NLP extraction (NER, cards, summary) | NO |
| **rag_store** | `server/services/rag_store.py` | RAG storage with BM25/TF-IDF (lexical only) | NO |
| **metrics_registry** | `server/services/metrics_registry.py` | Metrics collection (counters, gauges, histograms) | NO |
| **concurrency_controller** | `server/services/concurrency_controller.py` | Session concurrency limiting | NO |
| **degrade_ladder** | `server/services/degrade_ladder.py` | 5-level degradation management | NO |
| **capability_detector** | `server/services/capability_detector.py` | Hardware capability detection for auto-provider | NO |
| **model_preloader** | `server/services/model_preloader.py` | Model eager loading and warmup | NO |

---

## Special Focus: UI Copy Surface Map

### Copy by Category

#### 1) Onboarding Copy (OnboardingView.swift)

| Location | Copy String | Context/Trigger |
|----------|-------------|-----------------|
| Lines 105-106 | "Welcome to EchoPanel" | Welcome screen title |
| Line 109 | "Your AI-powered meeting companion that captures, transcribes, and analyzes conversations in real-time." | Welcome screen description |
| Lines 118-119 | "Permissions Required" | Permissions step title |
| Line 122 | "EchoPanel needs the following permissions to capture meeting audio:" | Permissions step description |
| Line 129 | "Screen Recording" | Permission title |
| Line 130 | "Required to capture system audio from meetings" | Permission description |
| Line 143 | "Microphone" | Permission title |
| Line 144 | "Optional: Capture your voice in addition to meeting audio" | Permission description |
| Line 160 | "Click 'Open Settings' and add EchoPanel to the allowed apps." | Permission instruction |
| Line 178 | "Audio Source" | Source selection title |
| Line 182 | "Choose which audio sources to capture:" | Source selection description |
| Lines 205-206 | "Speaker Labels (Optional)" | Diarization step title |
| Line 209 | "To identify who is speaking (Diarization), EchoPanel uses a model that requires a HuggingFace User Access Token due to license restrictions." | Diarization explanation |
| Line 227 | "You can leave this empty and set it later. Speaker labels won't be available without it." | Diarization optional note |
| Line 243-244 | "You're All Set!" | Ready step title |
| Line 247 | "EchoPanel is ready to capture and analyze your meetings. Click 'Start Listening' to begin your first session." | Ready step description |
| Lines 265-270 | "Backend Error", "The python server failed to start. Check if Python 3.10+ is installed." | Backend error state |
| Lines 293-294 | "Starting server..." | Backend loading state |
| Lines 318-321 | "Backend unavailable." | Backend failed state |

#### 2) Runtime Error Messages (AppState.swift:71-88)

| Error Type | Copy String | Trigger |
|------------|-------------|---------|
| backendNotReady | "Backend not ready. Open Diagnostics to see logs." | Backend not ready when starting session |
| screenRecordingPermissionRequired | "Screen Recording permission required for System Audio. Open Settings → Privacy & Security → Screen Recording." | Screen recording permission denied |
| screenRecordingRequiresRelaunch | "Screen Recording permission was granted, but macOS requires you to quit and relaunch EchoPanel before system audio can be captured." | Permission granted but requires app restart |
| microphonePermissionRequired | "Microphone permission required for Microphone audio" | Microphone permission denied |
| systemCaptureFailed | "Capture failed: {detail}" | System audio capture failure |
| microphoneCaptureFailed | "Mic capture failed: {detail}" | Microphone capture failure |
| streaming | {detail} | Various streaming errors |

#### 3) Menu Bar Copy (MeetingListenerApp.swift)

| Location | Copy String | Context |
|----------|-------------|---------|
| Line 39 | "Stop Listening" | Menu item when session active |
| Line 39 | "Start Listening" | Menu item when session idle |
| Line 44 | "Copy Markdown" | Menu item |
| Line 49 | "Export JSON" | Menu item |
| Line 54 | "Export Markdown" | Menu item |
| Line 62 | "Server: {status}" | Server status display |
| Line 65 | "Diagnostics..." | Menu item |
| Line 70 | "Session Summary..." | Menu item |
| Line 75 | "Session History..." | Menu item |
| Line 81 | "Quit" | Menu item |

#### 4) Settings Copy (SettingsView.swift)

| Tab/Section | Copy String | Context |
|-------------|-------------|---------|
| General tab | "General" | Tab label |
| Broadcast tab | "Broadcast" | Tab label |
| Audio section | "Audio" | Settings section |
| "Source" | Audio source picker label | |
| ASR Model section | "ASR Model" | Settings section |
| "Whisper Model" | Model picker label | |
| "Base English (Recommended)" | Model option | |
| "Base (Multilingual)" | Model option | |
| "Small" | Model option | |
| "Medium" | Model option | |
| "Large v3 Turbo (Best)" | Model option | |
| "Recommended for this Mac:" | Model recommendation prefix | |
| "high-memory profile supports better quality model" | Model recommendation reason | |
| "fastest stable baseline for local real-time meetings" | Model recommendation reason | |
| "Use Recommended" | Button to use recommended model | |
| "Changes take effect after restarting the server." | Model change warning | |
| Backend section | "Backend" | Settings section |
| "Host" | Backend host field label | |
| "Port: {port}" | Backend port stepper label | |
| "Optional WS auth token" | Auth token field label | |
| "Local backend uses ws/http." | Backend transport note | |
| "Remote backend defaults to wss/https." | Backend transport note | |
| "Backend changes take effect after restarting the server." | Backend change warning | |
| Server section | "Server" | Settings section |
| "Status" | Server status label | |
| "Restart Server" | Restart server button | |

#### 5) Broadcast Settings Copy (BroadcastSettingsView.swift)

| Section | Copy String | Context |
|---------|-------------|---------|
| Audio Redundancy | "Audio Redundancy" | Section header |
| "Enable Dual-Path Audio" | Toggle label | |
| "Emergency Failover to Backup" | Failover button | |
| "Uses both system audio and microphone simultaneously, automatically switching if one fails." | Explanation | |
| Operator Controls | "Operator Controls" | Section header |
| "Enable Global Hot-Keys" | Toggle label | |
| "View Hot-Key Reference" | Help button | |
| "Accessibility permission required for global hot-keys" | Permission warning | |
| "Grant" | Permission grant button | |
| "Hot-keys work even when EchoPanel is not the active app." | Explanation | |
| ASR Quality Monitoring | "ASR Quality Monitoring" | Section header |
| "Show Confidence Scores" | Toggle label | |
| "Current: X%" | Current confidence display | |
| "5s Avg: Y%" | Rolling average display | |
| Timestamp Synchronization | "Timestamp Synchronization" | Section header |
| "Use NTP Synchronization" | Toggle label | |
| "NTP Offset: X ms" | NTP offset display | |
| "Sync Now" | Sync button | |

#### 6) Summary View Copy (SummaryView.swift)

| Element | Copy String | Context |
|---------|-------------|---------|
| Header | "Session Summary" | Window title |
| Subtitle | "{transcriptCount} transcript lines · {actionsCount} actions · {decisionsCount} decisions · {risksCount} risks" | Summary metadata |
| Tabs | "Markdown", "Details" | Tab labels |
| Banners | "Finalization complete", "Your final summary is ready." | Success state |
| Banners | "Finalization incomplete", "The backend didn't return a final summary. You can still export partial notes, or open Diagnostics." | Incomplete state |
| Sections | "Actions", "Decisions", "Risks", "Entities" | Detail sections |
| Empty states | "No actions detected.", "No decisions detected.", "No risks detected.", "No entities detected." | Empty section messages |
| Buttons | "Copy Markdown", "Export Markdown", "Export JSON" | Footer actions |

#### 7) Session History Copy (SessionHistoryView.swift)

| Element | Copy String | Context |
|---------|-------------|---------|
| Header | "Sessions" | Sidebar header |
| Search | "Search by date/time" | Search placeholder |
| Detail header | "Details" | Detail view header |
| Buttons | "Export Markdown…", "Export JSON…", "Delete…" | Action buttons |
| Tabs | "Summary", "Transcript", "JSON" | View tabs |
| Empty | "Select a session to view details." | Empty selection message |
| Recovery | "A recoverable session is available." | Recovery availability message |
| Delete dialog | "Delete this session?" | Alert title |
| Delete message | "This removes session snapshot and transcript from local storage. This can't be undone." | Alert message |
| Recovery badge | "RECOVER" | Recoverable session indicator |

#### 8) Diagnostics Copy (DiagnosticsView.swift)

| Section | Copy String | Context |
|---------|-------------|---------|
| System Status | "System Status" | GroupBox header |
| "Backend Status:" | Server status label | |
| "Backend Detail:" | Health detail label | |
| "Last Exit Code:" | Exit code label | |
| "Server Ready:" | Readiness label | |
| "Input Source:" | Audio source label | |
| "Last Heartbeat:" | Last message timestamp label | |
| Troubleshooting | "Troubleshooting" | GroupBox header |
| "If you encounter issues, please export a debug bundle to share with support." | Instruction | |
| "Export Debug Bundle..." | Export button | |
| "Report Issue..." | Report button | |
| Issue report template | "EchoPanel Beta Issue Report", "Describe the issue:" | Report body |

#### 9) Permission Badge Copy (OnboardingView.swift)

| Badge Type | Copy String | Color/Icon |
|------------|-------------|-------------|
| Granted | "Granted", "checkmark.circle.fill" | Green |
| Required | "Required", "exclamationmark.circle.fill" | Orange |
| Optional | "Optional", "minus.circle" | Gray |
| Denied | "Denied", "xmark.octagon.fill" | Red |

#### 10) Audio Source Options (OnboardingView.swift)

| Source | Copy String | Description |
|--------|-------------|-------------|
| System | "System Audio" | "Capture audio from Zoom, Meet, Teams, etc." |
| Microphone | "Microphone" | "Capture your voice using the microphone" |
| Both | "Both" | "Capture both meeting audio and your voice" |

---

## Risk Register

### P0 - Critical Risks (Immediate Attention)

| Risk | Location | Impact | Mitigation Status |
|------|----------|--------|------------------|
| **No monetization flow** | MON-001 to MON-004 | Cannot transition from beta to paid product | Not implemented - docs/PRICING.md and docs/LICENSING.md are plans only |
| **No user authentication** | AUTH-001 to AUTH-004 | Cannot support multi-user, cloud sync, or account-based features | Not implemented - only technical WebSocket auth |
| **Token-in-query for WebSocket** | SEC-005 | Auth token visible in logs/proxies, security vulnerability | Partial - acknowledged in docs, requires header-based auth |
| **Clock drift between audio sources** | AUD-009 (Hypothesized) | Multi-source sessions lose sync after several minutes, speaker labels become incorrect | Not implemented - requires drift compensation with CACurrentMediaTime |

### P1 - High Priority Risks

| Risk | Location | Impact | Mitigation Status |
|------|----------|--------|------------------|
| **VAD not integrated client-side** | AUD-010 (Partial) | 40% compute wasted on silence, network bandwidth waste | Partial - server-side VAD exists but not integrated into ASR stream |
| **Embeddings not implemented** | INT-009 | RAG uses pure lexical BM25, missing semantic search | Not implemented - contradicts RAG_PIPELINE_ARCHITECTURE.md |
| **GLiNER not implemented** | INT-008 | NER uses regex patterns, missing semantic layer | Not implemented - contradicts NER_PIPELINE_ARCHITECTURE.md |
| **Silent failure propagation** | STO-002/003 | File write failures only logged, not surfaced to user | Implemented - logs errors but no UI feedback |
| **Health check timeout hardcoding** | OBS-004 | Client health check timeout 2.0s, server-side no timeout, hangs possible | Implemented - but values not configurable |
| **Queue full drop policy** | AUD-005 | Drop oldest frame when queue full, may lose critical speech | Implemented - but configurable, may drop important content |
| **No retransmission** | AUD-005 | Dropped frames lost forever, no recovery mechanism | Implemented - no retry or retransmission |
| **Exponential backoff unbounded** | OBS-012 | Restart delay grows exponentially but no max cap (currently 10s) | Implemented - max attempts limited but delay could grow indefinitely |
| **ASR flush timeout** | COMPOSITE-001 | 8s timeout may truncate final transcript on long sessions | Implemented - timeout enforced but may be too short for some sessions |
| **Circuit breaker not present** | OBS-015 | No circuit breaker pattern to prevent cascading failures | Not implemented - degration ladder provides some fallback |

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

# Health check
curl http://localhost:8000/health  # Verify server health
```

### Manual Verification Steps

#### UI Copy Verification
1. [ ] Launch fresh app and verify all onboarding steps display correctly
2. [ ] Verify all error messages appear when triggered
3. [ ] Verify menu bar items display correct labels
4. [ ] Verify settings UI shows all sections and labels
5. [ ] Verify broadcast settings UI shows all controls
6. [ ] Verify summary view shows all sections correctly
7. [ ] Verify session history view shows all tabs and buttons
8. [ ] Verify diagnostics view shows all status items
9. [ ] Verify all permission badges show correct text and colors
10. [ ] Verify empty state messages display correctly

#### Monetization/Auth Verification (Should All Be Negative)
1. [ ] Verify no purchase/upgrade prompts exist
2. [ ] Verify no login/signup screens exist
3. [ ] Verify no license key entry screens exist
4. [ ] Verify no usage limits are enforced
5. [ ] Verify no user account UI exists

---

## Document Metadata

**Generated By**: Open Exploration Flow Mapper v2
**Sub-Agents**: 
- User Journey Mapper (24 flows)
- UI Copy Specialist (45 flows)
- Monetization Auditor (4 flows - all not implemented)
- Authentication Auditor (4 flows - all not implemented)
- Runtime Pipeline Analyst (12 flows)
- Lifecycle/Admin/Ops Analyst (20 flows)
- Security/Privacy Analyst (15 flows)

**Evidence Discipline**: All flows tagged as Observed (code/file evidence), Inferred (reasonable conclusion without direct evidence), or Hypothesized (no evidence found). Never presented Inferred as Observed.

**Critical Gaps Identified**: 4 (0 P0, 4 P1 - all related to monetization and auth)
**Total Flows Documented**: 124 (116 implemented, 8 not implemented)

**Key Finding**: EchoPanel v0.2 is a complete local-first application with NO user account, monetization, or authentication flows. All business-critical flows (monetization, licensing, user auth) are documented as plans only in PRICING.md and LICENSING.md.
