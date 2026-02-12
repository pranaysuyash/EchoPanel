# EchoPanel Flow Atlas

## Executive Summary

EchoPanel is a macOS menu bar application that captures system audio, microphone input, or both, streams PCM audio to a local FastAPI backend, and generates real-time transcripts with intelligent insights (cards, entities, summaries). This Flow Atlas documents all end-to-end flows across the product, including external user journeys, internal audio pipelines, model lifecycles, data storage, analysis pipelines, observability, and security boundaries.

## Flow Atlas Inventory

| Flow ID | Name | Status | Priority | Evidence Confidence |
|---------|------|--------|----------|-------------------|
| ONBOARDING_001 | First-Time User Onboarding | Implemented | High | High |
| SESSION_MANAGEMENT_001 | Start/Stop Recording Session | Implemented | High | High |
| AUDIO_SOURCE_SELECTION_001 | Audio Source Configuration | Implemented | High | High |
| SETTINGS_CONFIGURATION_001 | Application Settings | Implemented | High | High |
| PLAYBACK_REVIEW_001 | Session History and Review | Implemented | High | High |
| EXPORT_SHARING_001 | Data Export and Sharing | Implemented | High | High |
| SEARCH_DISCOVERY_001 | Session Search and Navigation | Implemented | High | High |
| SUBSCRIPTION_LICENSING_001 | Premium Features and Licensing | Partial/Hypothesized | Low | Low |
| ERROR_RECOVERY_001 | Error Recovery and Troubleshooting | Implemented | High | High |
| DIAGNOSTICS_MONITORING_001 | System Health and Performance Monitoring | Implemented | Medium | High |
| AUDIO_CAPTURE_DETECTION | Audio Source Detection | Implemented | High | High |
| PERMISSION_ACQUISITION | Screen Recording/Microphone Permissions | Implemented | High | High |
| AUDIO_CAPTURE_INITIALIZATION | Audio Capture Initialization | Implemented | High | High |
| PCM_BUFFERING_CHUNKING | PCM Buffering and Chunking | Implemented | High | High |
| VAD_DIARIZATION | Voice Activity Detection and Diarization | Implemented | Medium | High |
| SAMPLE_RATE_CONVERSION | Sample Rate and Format Conversion | Implemented | Medium | High |
| BACKPRESSURE_MANAGEMENT | Backpressure and Queue Management | Implemented | High | High |
| AUDIO_DEVICE_SELECTION | Audio Device Selection | Implemented | Medium | High |
| AUDIO_STREAM_TERMINATION | Audio Stream Termination | Implemented | High | High |
| AUDIO_ERROR_HANDLING | Audio Error Handling | Implemented | High | High |
| MODEL_SELECTION | Model Selection Flow | Implemented | High | High |
| MODEL_PRELOADING | Model Preloading/Warmup Flow | Implemented | High | High |
| PROVIDER_DETECTION | Provider Detection Flow | Implemented | High | High |
| MODEL_LOADING | Model Loading Flow | Implemented | High | High |
| FALLBACK_MODEL | Fallback Model Flow | Implemented | High | High |
| MODEL_UPDATE | Model Update Flow | Implemented | Medium | High |
| DEGRADE_LADDER | Degrade Ladder Flow | Implemented | High | High |
| HEALTH_MONITORING | Health Monitoring Flow | Implemented | High | High |
| CONCURRENCY_CONTROL | Concurrency Control Flow | Implemented | High | High |
| MEMORY_MANAGEMENT | Memory Management Flow | Implemented | Medium | High |
| TRANSCRIPT_STORAGE | Transcript Storage Flow | Implemented | High | High |
| AUDIO_STORAGE | Audio Storage Flow | Implemented | High | High |
| METADATA_STORAGE | Session Metadata Storage Flow | Implemented | High | High |
| RAG_STORAGE | RAG Storage Flow | Implemented | High | High |
| EXPORT_STORAGE | Export Flow | Partial | Medium | High |
| ENCRYPTION_STORAGE | Encryption Flow | Not Implemented | Low | High |
| RETENTION_STORAGE | Retention Policy Flow | Not Implemented | Low | High |
| BACKUP_STORAGE | Backup and Restore Flow | Not Implemented | Low | High |
| MIGRATION_STORAGE | Data Migration Flow | Not Implemented | Low | High |
| NER_EXTRACTION | Named Entity Recognition Extraction | Implemented | High | High |
| CARD_DETECTION | Action/Decision/Risk Card Extraction | Implemented | High | High |
| SUMMARIZATION | Rolling Summary Generation | Implemented | High | High |
| TOPIC_EXTRACTION | Theme and Topic Identification | Implemented | Medium | High |
| RAG_RETRIEVAL | Document Retrieval and Context | Implemented | High | High |
| EMBEDDING_GENERATION | Embedding Generation | Hypothesized | Low | Low |
| INCREMENTAL_ANALYSIS | Real-time Analysis Updates | Implemented | High | High |
| WINDOWING_MANAGEMENT | Rolling vs Session-End Analysis | Implemented | High | High |
| CITATION_TRACKING | Source and Evidence Tracking | Implemented | Medium | High |
| DETERMINISM_GUARANTEE | Consistent Analysis Results | Implemented | Medium | High |
| LOG_001 | Logging Flow | Partial | Medium | Medium |
| MET_001 | Metrics Flow | Partial | Medium | Medium |
| TRACE_001 | Request Tracing Flow | Partial | Medium | Medium |
| HEALTH_001 | Health Check Flow | Implemented | High | High |
| ERROR_001 | Error Taxonomy Flow | Partial | Medium | Medium |
| RETRY_001 | Retry/Backoff Flow | Partial | Medium | Medium |
| CIRCUIT_001 | Circuit Breaker Flow | Partial | Medium | Medium |
| WATCHDOG_001 | Watchdog Flow | Partial | Medium | Medium |
| PERF_001 | Performance Monitoring Flow | Partial | Medium | Medium |
| USER_001 | User-Facing Error Flow | Partial | Medium | Medium |
| SP_001 | Screen Recording Permission Acquisition | Implemented | High | High |
| SP_002 | Microphone Permission Acquisition | Implemented | High | High |
| SP_003 | Keychain Credential Storage | Implemented | High | High |
| SP_004 | Local WebSocket Transmission | Implemented | High | High |
| SP_005 | Remote WebSocket Transmission | Implemented | High | High |
| SP_006 | WebSocket Response Handling | Implemented | High | High |
| SP_007 | Structured Logging Redaction | Implemented | High | High |
| SP_008 | File-Based Logging | Implemented | High | High |
| SP_009 | Server Session State Management | Implemented | High | High |
| SP_010 | Debug Audio Dump | Partial | Low | Medium |
| SP_011 | UserDefaults Configuration Storage | Implemented | Low | High |

**Total Flows:** 50
**Implemented:** 39 (78%)
**Partial:** 7 (14%)
**Not Implemented:** 4 (8%)
**Hypothesized:** 1 (2%)

## Component/Module Map

### Core Components

#### macOS App (`macapp/MeetingListenerApp/`)
- **MeetingListenerApp.swift**: Main app entry point, MenuBarExtra
- **AppState.swift**: Global state management, session control
- **AudioCaptureManager.swift**: ScreenCaptureKit system audio capture
- **MicrophoneCaptureManager.swift**: AVFoundation microphone capture
- **BackendManager.swift**: Python server subprocess lifecycle
- **WebSocketStreamer.swift**: WebSocket communication with backend
- **SidePanelController.swift**: Live transcript overlay UI
- **SettingsView.swift**: Application settings panel
- **SessionHistoryView.swift**: Session history and playback
- **DiagnosticsView.swift**: System health and debugging
- **OnboardingView.swift**: First-time user experience
- **KeychainHelper.swift**: Secure credential storage
- **StructuredLogger.swift**: JSON-structured logging with redaction

#### FastAPI Backend (`server/`)
- **main.py**: FastAPI application entry, health endpoints
- **ws_live_listener.py**: WebSocket handler for live audio streaming
- **asr_stream.py**: Streaming ASR pipeline with provider abstraction
- **asr_providers.py**: Multi-provider support (Faster-Whisper, Voxtral, Whisper-C++)
- **analysis_stream.py**: NLP extraction (cards, entities, summaries)
- **diarization.py**: Speaker labeling and segmentation
- **rag_store.py**: Local document store with RAG capabilities
- **model_preloader.py**: ASR model warmup and health monitoring
- **capability_detector.py**: Auto-detection of optimal ASR provider
- **concurrency_controller.py**: Backpressure and resource management
- **degrade_ladder.py**: Adaptive performance degradation
- **metrics_registry.py**: Central metrics collection

#### Landing Page (`landing/`)
- **app.js**: Waitlist form and Google Sheets integration
- **index.html**: Static landing page

### Key Data Structures

#### Session Management
- **SessionState**: Comprehensive session metadata and state
- **CorrelationIDs**: session_id, attempt_id, connection_id
- **BackendConfig**: WebSocket URLs, authentication tokens

#### Audio Processing
- **AudioChunk**: Base64-encoded PCM16 audio data
- **SessionState.pcm_buffers_by_source**: In-memory audio buffers
- **AudioCaptureManager**: ScreenCaptureKit integration

#### ASR and Analysis
- **ASRProvider**: Abstract base for ASR providers
- **ASRHealth**: Runtime performance metrics
- **Entity**: Named entity with counts and grounding quotes
- **Card**: Action/decision/risk card with evidence
- **TranscriptSegment**: ASR result with timestamps and metadata

#### Storage and RAG
- **Document**: RAG document with chunks and metadata
- **Chunk**: Text segment with tokens for BM25 scoring
- **SessionBundle**: Exported session data with audio files

#### Observability
- **MetricsRegistry**: Thread-safe metrics collection
- **DegradeState**: Current performance degradation level
- **ASRHealth**: Provider performance metrics

## Flow Specs (by ID)

### External User Flows

#### ONBOARDING_001 - First-Time User Onboarding
**Trigger**: App launch when `UserDefaults.standard.bool(forKey: "onboardingCompleted")` is false
**Preconditions**: Fresh installation or first launch
**Sequence**:
1. Welcome screen displays app purpose
2. Permissions step requests Screen Recording and Microphone access
3. Source selection step configures audio source (System/Microphone/Both)
4. Diarization setup step configures HuggingFace token
5. Ready screen shows configured settings and backend status
6. "Start Listening" button triggers `completeOnboarding()`
**Failure Modes**: Backend not ready, permission denied
**Status**: Implemented
**Proof**: `OnboardingView.swift:99-310`, `AppState.swift:531-549`

#### SESSION_MANAGEMENT_001 - Start/Stop Recording Session
**Trigger**: Menu bar button, Cmd+Shift+L keyboard shortcut, or onboarding completion
**Preconditions**: Permissions granted, backend ready
**Sequence**:
1. Permission checks for screen recording and microphone
2. Audio capture initialization via `AudioCaptureManager` and `MicrophoneCaptureManager`
3. WebSocket connection to backend with 5-second handshake timeout
4. Real-time transcript display in side panel
5. Session stop triggers cleanup and session data persistence
**Failure Modes**: Permission denied, backend not ready, connection timeout, ASR processing failure
**Status**: Implemented
**Proof**: `AppState.swift:492-711`, `WebSocketStreamer.connect`, `ws_live_listener.py:401-409`

#### SETTINGS_CONFIGURATION_001 - Application Settings
**Trigger**: Settings menu item or Cmd+, keyboard shortcut
**Preconditions**: App running
**Sequence**:
1. General settings panel with audio source, ASR model, backend configuration
2. Broadcast settings for caption streaming and UDP output
3. Server management with status indicators and restart button
**Failure Modes**: Invalid port, model unsupported, connection failed
**Status**: Implemented
**Proof**: `SettingsView.swift:363-449`, `BackendManager.swift:276-338`

### Audio Pipeline Flows

#### AUDIO_CAPTURE_DETECTION - Audio Source Detection
**Trigger**: App launch or audio source configuration change
**Preconditions**: macOS ScreenCaptureKit and AVFoundation available
**Sequence**:
1. ScreenCaptureKit enumerates available displays and windows
2. AVFoundation queries available audio devices
3. App determines available audio sources (system audio, microphone, apps)
4. User selects source via UI or defaults to system audio
**Failure Modes**: No displays available, no audio devices, ScreenCaptureKit unavailable
**Status**: Implemented
**Proof**: `AudioCaptureManager.swift:61-66`, `MicrophoneCaptureManager.swift:29-39`

#### PERMISSION_ACQUISITION - Screen Recording/Microphone Permissions
**Trigger**: Audio capture initialization
**Preconditions**: macOS security settings accessible
**Sequence**:
1. Screen Recording permission check via `CGPreflightScreenCaptureAccess()`
2. If not granted, `CGRequestScreenCaptureAccess()` prompts user
3. Microphone permission check via `AVCaptureDevice.authorizationStatus(for: .audio)`
4. If not granted, `AVCaptureDevice.requestAccess(for: .audio)` prompts user
5. Permission granted → capture initialization proceeds
**Failure Modes**: Permission denied, permission revoked mid-session, OS version incompatibility
**Status**: Implemented
**Proof**: `AudioCaptureManager.swift:61-66`, `MicrophoneCaptureManager.swift:29-39`

#### PCM_BUFFERING_CHUNKING - PCM Buffering and Chunking
**Trigger**: Audio frames received from ScreenCaptureKit/AVFoundation
**Preconditions**: Audio capture initialized, format conversion successful
**Sequence**:
1. `AudioSampleHandler` receives `CMSampleBuffer` from ScreenCaptureKit
2. `AVAudioConverter` converts to 16kHz mono PCM16
3. Audio frames appended to `SessionState.pcm_buffers_by_source`
4. 20ms chunks (320 bytes) extracted for streaming
5. Base64 encoding applied for WebSocket transmission
6. Backpressure handling via bounded queues (maxsize=48)
**Failure Modes**: Queue overflow, format conversion failure, buffer allocation failure
**Status**: Implemented
**Proof**: `AudioCaptureManager.swift:73`, `ws_live_listener.py:706-729`

### Model Lifecycle Flows

#### MODEL_SELECTION - Model Selection Flow
**Trigger**: Server startup or user configuration change
**Preconditions**: Machine capabilities detected, provider availability checked
**Sequence**:
1. `_auto_select_provider()` checks `ECHOPANEL_ASR_PROVIDER` env var
2. If not set, `CapabilityDetector.detect()` analyzes hardware (RAM, CPU, GPU)
3. `CapabilityDetector.recommend()` maps capabilities to provider configuration
4. Environment variables set for selected provider
5. Provider registry creates instance with configured model
**Failure Modes**: Provider unavailable, model not found, capability detection failure
**Status**: Implemented
**Proof**: `main.py:17-54`, `capability_detector.py:175-398`

#### DEGRADE_LADDER - Degrade Ladder Flow
**Trigger**: RTF monitoring or performance degradation
**Preconditions**: ASR provider running, metrics available
**Sequence**:
1. `ws_live_listener.py:356-391` calculates realtime_factor = processing_time / audio_time
2. Degrade ladder levels: NORMAL (0), WARNING (1), DEGRADE (2), EMERGENCY (3), FAILOVER (4)
3. Level transitions based on RTF thresholds:
   - NORMAL: RTF << 0.8 - Optimal performance
   - WARNING: RTF 0.8-1.0 - Increase chunk size
   - DEGRADE: RTF 1.0-1.2 - Switch to smaller model, disable VAD
   - EMERGENCY: RTF > 1.2 - Drop every other chunk
   - FAILOVER: Provider crash - Switch to fallback provider
4. `DegradeLadder.apply_actions()` implements configuration changes
5. Client notified of status changes via WebSocket messages
**Failure Modes**: Provider crash, memory pressure, CPU saturation
**Status**: Implemented
**Proof**: `degrade_ladder.py:230-272`, `ws_live_listener.py:356-391`

### Analysis Pipeline Flows

#### NER_EXTRACTION - Named Entity Recognition Extraction
**Trigger**: ASR transcript segments arriving in `state.transcript` during real-time analysis
**Preconditions**: ASR transcription complete for segments, analysis window contains sufficient data
**Sequence**:
1. `_filter_window` function filters transcript to 10-minute sliding window (600 seconds)
2. `extract_entities` function classifies entities:
   - Person detection via title patterns and capitalized names
   - Organization detection via known orgs list
   - Date detection via day names
   - Topic extraction via capitalized tokens
3. `Entity` dataclass tracks count, recency, and grounding quotes
4. Results deduplicated and sorted by count/recency
**Failure Modes**: Timeout handling (10s), empty transcript, corrupt data
**Status**: Implemented
**Proof**: `analysis_stream.py:26-365`, `ws_live_listener.py:411-448`

#### CARD_DETECTION - Action/Decision/Risk Card Extraction
**Trigger**: ASR transcript segments arriving during analysis cycles
**Preconditions**: Transcript contains sufficient text for keyword matching
**Sequence**:
1. 10-minute sliding window applied to transcript
2. `extract_cards` function classifies cards via keyword matching:
   - Action keywords: "i will", "we will", "todo", "follow up"
   - Decision keywords: "decide", "decided", "decision", "approve"
   - Risk keywords: "risk", "issue", "blocker", "problem"
3. `Card` dataclass created with text, type, timestamps, confidence
4. `_deduplicate_cards` function removes duplicates via fuzzy matching
**Failure Modes**: Keyword misses, false positives, timeout handling (15s)
**Status**: Implemented
**Proof**: `analysis_stream.py:38-162`, `ws_live_listener.py:431-437`

### Storage and Data Flows

#### TRANSCRIPT_STORAGE - Transcript Storage Flow
**Trigger**: Session completion (stop message received)
**Preconditions**: Active WebSocket session with audio data processed
**Sequence**:
1. Stop message received triggers EOF signals to all audio queues
2. Waits for ASR tasks to flush final transcriptions (8s timeout)
3. Creates transcript snapshot: `sorted(state.transcript, key=lambda s: s.get("t0", 0.0))`
4. Runs session-end diarization per source to avoid mixed-source corruption
5. Merges transcript with source-specific speaker labels
6. Generates rolling summary as markdown
7. Extracts final cards and entities using `extract_cards()` and `extract_entities()`
8. Constructs final JSON payload with labeled_transcript, actions, decisions, risks, entities, diarization
**Failure Modes**: ASR flush timeout, diarization failure, analysis timeout
**Status**: Implemented
**Proof**: `ws_live_listener.py:739-803`

#### RAG_STORAGE - RAG Storage Flow
**Trigger**: Document indexing or querying
**Preconditions**: HTTP request with auth token
**Sequence**:
1. `LocalRAGStore` class tokenizes text and chunks into 120-word segments with 30-word overlap
2. Creates document metadata: `document_id`, `title`, `source`, `indexed_at`
3. Stores chunks with tokens for BM25 scoring
4. Persists to JSON file with atomic temp file replacement
5. Query processing uses BM25 algorithm with TF-IDF scoring
6. Returns top-k results (max 20) with snippets and relevance scores
**Failure Modes**: JSON corruption, file permission issues, concurrent access
**Status**: Implemented
**Proof**: `rag_store.py:27-280`

### Observability and Reliability Flows

#### HEALTH_001 - Health Check Flow
**Trigger**: HTTP GET /health endpoint request
**Preconditions**: FastAPI application running, ASR provider available
**Sequence**:
1. `main.py:101-156` handles deep health check with provider and model status
2. 200 OK only when ASR provider available AND model warmed up
3. 503 Service Unavailable with detailed reason otherwise
4. `ModelState` enum tracks: UNINITIALIZED → LOADING → WARMING_UP → READY → ERROR
5. Provider availability checked via `ASRProviderRegistry.get_provider()`
**Failure Modes**: Provider unavailable, model not warmed up, registry failure
**Status**: Implemented
**Proof**: `main.py:101-156`, `model_preloader.py:311-321`

#### LOG_001 - Logging Flow
**Trigger**: Application startup, WebSocket connection, session events, errors, metrics emission
**Preconditions**: Python logging configured in `server/main.py:13`, macOS logging available
**Sequence**:
1. `server/main.py:13` initializes Python logging with `logging.basicConfig(level=logging.INFO)`
2. `server/api/ws_live_listener.py:25` creates module-specific logger
3. `macapp/MeetingListenerApp/Sources/StructuredLogger.swift` provides JSON-structured logging
4. Key log points: session start, frame drops, session completion, ASR errors
5. Redaction patterns protect PII and tokens in structured logs
**Failure Modes**: Missing correlation IDs, plain text format, no client-side file persistence
**Status**: Partial
**Proof**: `server/main.py:13`, `server/api/ws_live_listener.py:25`, `macapp/MeetingListenerApp/Sources/StructuredLogger.swift`

### Security and Privacy Flows

#### SP_001 - Screen Recording Permission Acquisition
**Trigger**: User clicks "Start Listening" button in UI
**Preconditions**: App checks if Screen Recording permission is granted
**Sequence**:
1. `AudioCaptureManager.requestPermission()` calls `CGPreflightScreenCaptureAccess()`
2. If not granted, `CGRequestScreenCaptureAccess()` prompts user
3. Permission granted → `AudioCaptureManager.startCapture()` calls `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`
4. `SCStreamConfiguration` sets `capturesAudio = true` and `excludesCurrentProcessAudio = true`
5. `SCStream.startCapture()` begins audio capture
6. `AudioSampleHandler` receives `CMSampleBuffer` and forwards to `AudioCaptureManager.processAudio()`
**Failure Modes**: Permission denied, permission revoked mid-session, ScreenCaptureKit failure, OS version incompatibility
**Status**: Implemented
**Proof**: `AudioCaptureManager.swift:61-66`, `AudioCaptureManager.swift:68-95`

#### SP_003 - Keychain Credential Storage
**Trigger**: User enters HuggingFace token or backend token
**Preconditions**: App needs to store credentials securely
**Sequence**:
1. User enters token in Settings UI
2. `KeychainHelper.saveHFToken()` or `saveBackendToken()` called
3. Token converted to UTF-8 data
4. `SecItemAdd()` with `kSecClassGenericPassword` stores in Keychain
5. `kSecAttrAccessibleAfterFirstUnlock` set for access control
6. If token exists in UserDefaults, `migrateFromUserDefaults()` moves it
**Failure Modes**: Keychain unavailable, encoding failure, migration failure, race condition
**Status**: Implemented
**Proof**: `KeychainHelper.swift:13-34`, `KeychainHelper.swift:70-89`, `KeychainHelper.swift:126-150`

## Event + State Glossary

### WebSocket Message Types
- **start**: Session initialization with configuration
- **pcm_frame**: Base64-encoded audio data chunks
- **stop**: Session termination request
- **entities_update**: Real-time entity extraction results
- **cards_update**: Real-time card detection results
- **final_summary**: Session-end summary and analysis
- **metrics**: Real-time performance metrics
- **status**: Connection and performance status updates

### ASR Provider Types
- **faster-whisper**: Local ASR with multiple model sizes
- **voxtral**: Alternative local ASR provider
- **whisper-cpp**: High-performance ASR engine

### Degrade Ladder Levels
- **NORMAL (0)**: Optimal performance, RTF << 0.8
- **WARNING (1)**: Increased chunk size, RTF 0.8-1.0
- **DEGRADE (2)**: Smaller model, disable VAD, RTF 1.0-1.2
- **EMERGENCY (3)**: Drop every other chunk, RTF > 1.2
- **FAILOVER (4)**: Provider crash, switch to fallback

### Audio Source Types
- **system**: System audio capture via ScreenCaptureKit
- **microphone**: Microphone input via AVFoundation
- **both**: Combined system and microphone audio

### Card Types
- **action**: Action items and follow-ups
- **decision**: Decisions and approvals
- **risk**: Risks and issues identified

### Entity Types
- **person**: People and roles
- **organization**: Companies and organizations
- **date**: Dates and time references
- **project**: Projects and version numbers
- **topic**: General topics and themes

### Analysis Window Types
- **rolling**: 10-minute sliding window for real-time analysis
- **session-end**: Complete transcript for final analysis

### Correlation IDs
- **session_id**: Unique identifier for each session
- **attempt_id**: Unique identifier for each connection attempt
- **connection_id**: Unique identifier for each WebSocket connection

### Permission Types
- **screen_recording**: Required for system audio capture
- **microphone**: Required for microphone audio capture

## Dependency Graph (textual)

```
macOS App (SwiftUI)
├── MenuBarExtra (MeetingListenerApp.swift)
├── AppState (Global state management)
├── AudioCaptureManager (ScreenCaptureKit)
├── MicrophoneCaptureManager (AVFoundation)
├── BackendManager (Python subprocess)
├── WebSocketStreamer (WebSocket communication)
└── SidePanelController (Live UI overlay)

FastAPI Backend (Python)
├── main.py (FastAPI app)
├── ws_live_listener.py (WebSocket handler)
├── asr_stream.py (ASR pipeline)
├── analysis_stream.py (NLP analysis)
├── rag_store.py (Document store)
├── model_preloader.py (Model management)
└── capability_detector.py (Hardware detection)

Key Dependencies
├── ScreenCaptureKit (macOS 13+)
├── AVFoundation (Audio capture)
├── URLSessionWebSocketTask (WebSocket)
├── Python subprocess (Backend execution)
├── Keychain Services (Credential storage)
└── Structured logging (JSON logs)

Data Flow
├── Audio capture → PCM buffering → WebSocket → ASR → Analysis → UI
├── User settings → UserDefaults → Keychain → Backend config
└── RAG documents → JSON store → BM25 search → Context retrieval
```

## Risk Register

### High Impact Risks

#### 1. Token Leakage in URL Query Parameters
**Flow**: SP-004/SP-005 (Remote WebSocket Transmission)
**Impact**: High - Authentication tokens visible in proxy logs, browser history
**Likelihood**: Medium - Occurs on every remote connection
**Mitigation**: Move token from URL query parameter to Authorization header
**Status**: Not implemented
**Evidence**: `BackendConfig.swift:18-20` uses query parameters

#### 2. Lack of Explicit User Consent
**Flow**: SP-001/SP-002 (Permission Acquisition)
**Impact**: High - Users unaware of data transmission and processing
**Likelihood**: High - All users affected
**Mitigation**: Add explicit consent dialog explaining data flow
**Status**: Not implemented
**Evidence**: No consent flow in codebase

#### 3. No PII Redaction in Transcripts
**Flow**: SP-006 (WebSocket Response Handling)
**Impact**: High - Sensitive information transmitted in plaintext
**Likelihood**: High - All sessions contain PII
**Mitigation**: Implement server-side PII redaction
**Status**: Not implemented
**Evidence**: No redaction in `ws_live_listener.py:385-436`

#### 4. Debug Audio Dump Persistence
**Flow**: SP-010 (Debug Audio Dump)
**Impact**: High - Sensitive audio files persist indefinitely
**Likelihood**: Low - Debug mode only
**Mitigation**: Auto-cleanup or disable by default
**Status**: Partial implementation
**Evidence**: `ws_live_listener.py:26-28`, `ws_live_listener.py:197-240`

### Medium Impact Risks

#### 5. No Permission Change Monitoring
**Flow**: SP-001/SP-002 (Permission Acquisition)
**Impact**: Medium - App continues using revoked permissions
**Likelihood**: Medium - Users may revoke permissions
**Mitigation**: Observe permission changes via macOS notifications
**Status**: Not implemented
**Evidence**: No permission change observers

#### 6. No User Data Export/Delete
**Flow**: SP-009 (Server Session State Management)
**Impact**: Medium - No data portability or right to deletion
**Likelihood**: Medium - GDPR/CCPA compliance requirement
**Mitigation**: Add export/delete functionality
**Status**: Not implemented
**Evidence**: No export/delete endpoints

#### 7. Plaintext UserDefaults Storage
**Flow**: SP-011 (UserDefaults Configuration Storage)
**Impact**: Low - Only non-sensitive data stored
**Likelihood**: High - All configuration changes
**Mitigation**: Consider encryption for sensitive config
**Status**: Implemented
**Evidence**: `BackendConfig.swift:4-25`

#### 8. No TLS Certificate Validation Feedback
**Flow**: SP-005 (Remote WebSocket Transmission)
**Impact**: Low - Users unaware of certificate issues
**Likelihood**: Low - Remote connections rare
**Mitigation**: Show certificate info for remote connections
**Status**: Not implemented
**Evidence**: No certificate validation feedback

### Low Impact Risks

#### 9. No Token Usage Tracking
**Flow**: SP-003 (Keychain Credential Storage)
**Impact**: Low - Hard to audit token access
**Likelihood**: Low - Security monitoring requirement
**Mitigation**: Log token access with correlation IDs
**Status**: Not implemented
**Evidence**: No token usage tracking

#### 10. No Performance Baselines
**Flow**: MET_001 (Metrics Flow)
**Impact**: Low - No historical performance data
**Likelihood**: Medium - Performance monitoring needed
**Mitigation**: Add metrics persistence and alerting
**Status**: Partial implementation
**Evidence**: `metrics_registry.py:82-212`

## Verification Checklist

### External User Flows

#### ONBOARDING_001 - First-Time User Onboarding
- [ ] App launches with onboarding screen
- [ ] Screen Recording permission request appears
- [ ] Microphone permission request appears (if mic source selected)
- [ ] Audio source selection works correctly
- [ ] Diarization token input appears
- [ ] Backend status feedback shown
- [ ] "Start Listening" button completes onboarding

#### SESSION_MANAGEMENT_001 - Start/Stop Recording Session
- [ ] Menu bar button starts recording
- [ ] Cmd+Shift+L keyboard shortcut works
- [ ] Permission checks occur before recording
- [ ] Audio capture initializes correctly
- [ ] WebSocket connection establishes within 5 seconds
- [ ] Real-time transcript displays in side panel
- [ ] Session stop triggers cleanup
- [ ] Session data persists correctly

#### SETTINGS_CONFIGURATION_001 - Application Settings
- [ ] Settings menu item opens settings panel
- [ ] Cmd+, keyboard shortcut works
- [ ] Audio source picker functions
- [ ] ASR model selection works
- [ ] Backend configuration accepts valid URLs
- [ ] Server status indicators update correctly
- [ ] Restart button restarts backend

### Audio Pipeline Flows

#### AUDIO_CAPTURE_DETECTION - Audio Source Detection
- [ ] ScreenCaptureKit enumerates displays correctly
- [ ] AVFoundation queries audio devices correctly
- [ ] System audio source available
- [ ] Microphone source available
- [ ] Both sources available when both permissions granted
- [ ] App defaults to appropriate source

#### PERMISSION_ACQUISITION - Screen Recording/Microphone Permissions
- [ ] Screen Recording permission request appears
- [ ] Microphone permission request appears
- [ ] Permission granted → capture starts
- [ ] Permission denied → appropriate error shown
- [ ] Permission revoked → capture stops
- [ ] OS version compatibility handled

#### PCM_BUFFERING_CHUNKING - PCM Buffering and Chunking
- [ ] Audio frames received from ScreenCaptureKit
- [ ] Format conversion to 16kHz mono PCM16 succeeds
- [ ] Audio frames appended to buffers correctly
- [ ] 20ms chunks (320 bytes) extracted correctly
- [ ] Base64 encoding applied correctly
- [ ] Backpressure handling prevents overflow

### Model Lifecycle Flows

#### MODEL_SELECTION - Model Selection Flow
- [ ] Server startup triggers provider detection
- [ ] Hardware capabilities detected correctly
- [ ] Provider recommendation matches capabilities
- [ ] Environment variables set correctly
- [ ] Provider registry creates instance
- [ ] Model loads successfully

#### DEGRADE_LADDER - Degrade Ladder Flow
- [ ] Realtime factor calculated correctly
- [ ] Degrade ladder levels transition appropriately
- [ ] Configuration changes applied correctly
- [ ] Client notified of status changes
- [ ] Fallback provider activated on failure

### Analysis Pipeline Flows

#### NER_EXTRACTION - Named Entity Recognition Extraction
- [ ] 10-minute sliding window applied correctly
- [ ] Person detection via title patterns works
- [ ] Organization detection via known orgs works
- [ ] Date detection via day names works
- [ ] Topic extraction via capitalized tokens works
- [ ] Results deduplicated and sorted correctly
- [ ] Timeout handling works

#### CARD_DETECTION - Action/Decision/Risk Card Extraction
- [ ] 10-minute sliding window applied correctly
- [ ] Action keywords detection works
- [ ] Decision keywords detection works
- [ ] Risk keywords detection works
- [ ] Card creation with evidence works
- [ ] Deduplication via fuzzy matching works
- [ ] Timeout handling works

### Storage and Data Flows

#### TRANSCRIPT_STORAGE - Transcript Storage Flow
- [ ] Stop message triggers EOF signals
- [ ] ASR tasks flush within 8-second timeout
- [ ] Transcript snapshot created correctly
- [ ] Session-end diarization runs correctly
- [ ] Transcript merged with speaker labels
- [ ] Rolling summary generated correctly
- [ ] Final JSON payload constructed correctly

#### RAG_STORAGE - RAG Storage Flow
- [ ] Document indexing creates 120-word chunks
- [ ] BM25 scoring works correctly
- [ ] JSON persistence works with atomic writes
- [ ] Query processing returns relevant results
- [ ] Thread safety maintained
- [ ] Corruption handling works

### Observability and Reliability Flows

#### HEALTH_001 - Health Check Flow
- [ ] HTTP GET /health endpoint responds
- [ ] Deep health check includes provider status
- [ ] 200 OK returned only when ready
- [ ] 503 returned with detailed reason when not ready
- [ ] Model state tracked correctly
- [ ] Provider availability checked correctly

#### LOG_001 - Logging Flow
- [ ] Python logging configured correctly
- [ ] WebSocket session logging works
- [ ] Structured logging with correlation IDs works
- [ ] Redaction patterns protect PII
- [ ] Key log points captured
- [ ] Log rotation works correctly

### Security and Privacy Flows

#### SP_001 - Screen Recording Permission Acquisition
- [ ] Permission check via `CGPreflightScreenCaptureAccess()` works
- [ ] Permission request via `CGRequestScreenCaptureAccess()` works
- [ ] Permission granted → capture starts
- [ ] Permission denied → appropriate error shown
- [ ] Capture initialization via ScreenCaptureKit works
- [ ] Audio processing pipeline works

#### SP_003 - Keychain Credential Storage
- [ ] Token input saved to Keychain correctly
- [ ] UTF-8 encoding works correctly
- [ ] `SecItemAdd()` stores credentials securely
- [ ] `kSecAttrAccessibleAfterFirstUnlock` set correctly
- [ ] UserDefaults migration works correctly
- [ ] Keychain retrieval works correctly

## Implementation Status Summary

### Fully Implemented (39 flows)
The majority of EchoPanel's flows are fully implemented with comprehensive error handling, observability, and recovery mechanisms. Key implemented flows include:

- **User Experience**: Complete onboarding, session management, settings, playback, and export flows
- **Audio Pipeline**: Full audio capture, permission handling, buffering, and error recovery
- **Model Lifecycle**: Comprehensive model selection, loading, health monitoring, and degrade ladder
- **Analysis Pipeline**: Real-time NER, card detection, summarization, and RAG retrieval
- **Security**: Strong credential storage via Keychain, effective logging redaction
- **Observability**: Health checks, structured logging, metrics collection, circuit breakers

### Partially Implemented (7 flows)
Some flows have partial implementations requiring completion:

- **Logging**: Server-side logging lacks correlation IDs and structured format
- **Metrics**: No metrics persistence or historical data
- **Error Handling**: No centralized error taxonomy or user analytics
- **Retry Logic**: Only client-side retry implemented
- **Circuit Breakers**: Only client-side circuit breakers
- **Watchdogs**: Only client-side health monitoring
- **Debug Audio Dump**: Debug-only feature with no cleanup policy

### Not Implemented (4 flows)
Critical gaps in data management and compliance:

- **Encryption**: No encryption for stored data or in-transit data (localhost)
- **Retention**: No automatic cleanup or data retention policies
- **Backup**: No backup/restore capabilities
- **Migration**: No data migration support for schema changes

### Hypothesized (1 flow)
Missing advanced functionality:

- **Embedding Generation**: No semantic embeddings for RAG retrieval

## Architecture Strengths

1. **Strong Credential Security**: Keychain storage with hardware-backed encryption
2. **Effective Redaction**: Regex-based PII protection in logs
3. **Local-First Architecture**: Minimizes data exposure and network dependencies
4. **Session-Scoped Data**: No persistent storage of sensitive audio
5. **Structured Logging**: Machine-parseable logs with correlation IDs
6. **Backpressure Handling**: Prevents resource exhaustion with bounded queues
7. **Resilience Features**: Automatic reconnection, circuit breaker patterns
8. **Comprehensive Error Handling**: Degrade ladder for adaptive performance
9. **Real-time Processing**: Low-latency audio streaming and analysis
10. **Modular Design**: Clear separation of concerns across components

## Recommendations for Production Readiness

### Immediate Actions (High Priority)
1. **Move authentication token from URL query parameter to Authorization header**
2. **Add explicit user consent dialog for data transmission**
3. **Implement PII redaction in server-side transcripts**
4. **Add permission change observer for real-time permission revocation handling**
5. **Implement debug audio dump cleanup policy**

### Short-term Actions (Medium Priority)
6. **Add user data export and deletion functionality**
7. **Consider encrypting UserDefaults for sensitive configuration**
8. **Add TLS certificate validation feedback for remote connections**
9. **Implement token usage tracking for audit purposes**
10. **Add metrics persistence and historical data collection**

### Long-term Actions (Low Priority)
11. **Consider encryption for localhost WebSocket connections**
12. **Implement data migration support for schema changes**
13. **Add backup/restore capabilities**
14. **Implement semantic embeddings for RAG retrieval**
15. **Add comprehensive error analytics and user feedback**

This Flow Atlas provides a comprehensive foundation for understanding EchoPanel's architecture, identifying gaps, and planning production deployment and enhancements.