> **⚠️ OBSOLETE (2026-02-16):** Core findings resolved — verified against source code:
> - whisper.cpp inference lock: `provider_whisper_cpp.py:49` — `self._session_lock = asyncio.Lock()`
> - Client WS send queue: `WebSocketStreamer.swift` — bounded `OperationQueue` with 5s send timeout
> - NLP timeouts: `ws_live_listener.py:955-958` — `asyncio.wait_for(...)` on incremental entity/card extraction
> - Provider health in metrics: `ws_live_listener.py` metrics loop — `provider.health()` included in payload
> - Correlation IDs: `ws_live_listener.py:1196-1197` — `attempt_id`/`connection_id` propagated; client validates
> - Provider lifecycle: `server/main.py:188-194` — `shutdown_model_manager()` with explicit unload
> - Auth headers: `BackendConfig.swift:44-49` — `Authorization: Bearer` + `x-echopanel-token` (no query string)

# Senior Architect Code Review: EchoPanel
**Date:** 2026-02-12  
**Reviewer:** Principal Architect Review  
**Scope:** Full-stack macOS desktop app with streaming ASR/diarization/analysis  

---

## Update (2026-02-13)

This review was authored on **2026-02-12**. Several items called out as gaps here have been addressed since then. Key changes observed as of **2026-02-13**:

- ✅ `whisper_cpp` inference is serialized under a lock (multi-source safety): `server/services/provider_whisper_cpp.py` uses `_infer_lock`.
- ✅ Client WS send is off the capture thread via a bounded send queue: `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` uses `sendQueue` and logs send timeouts.
- ✅ NLP `asyncio.to_thread(...)` calls in analysis loop are bounded by timeouts: `server/api/ws_live_listener.py` wraps incremental entity/card extraction in `asyncio.wait_for(...)`.
- ✅ Provider health is now emitted in WS `metrics` payloads: `server/api/ws_live_listener.py` includes `provider_health`.
- ✅ Correlation IDs are propagated server→client and validated client-side: `attempt_id` / `connection_id` in WS events, and the client drops mismatched-attempt messages.

Remaining items from this review are still relevant (notably provider instance eviction / lifecycle cleanup policy, and long-term removal of auth tokens from URL query parameters).

## 1) Repository Map

```
/Users/pranay/Projects/EchoPanel/
├── macapp/MeetingListenerApp/          # SwiftUI macOS app (23 source files)
│   ├── Sources/
│   │   ├── MeetingListenerApp.swift    # App entry point
│   │   ├── AppState.swift              # Main state machine (1,396 lines)
│   │   ├── AudioCaptureManager.swift   # ScreenCaptureKit audio
│   │   ├── MicrophoneCaptureManager.swift  # AVAudioEngine mic
│   │   ├── WebSocketStreamer.swift     # WS client, correlation IDs
│   │   ├── BackendManager.swift        # Python server lifecycle
│   │   ├── SessionStore.swift          # Local persistence
│   │   ├── StructuredLogger.swift      # V1: Correlation ID logging
│   │   └── SidePanel/                  # UI components
│   ├── Package.swift                   # Swift Package Manager
│   └── Tests/                          # Swift tests
├── server/                             # Python FastAPI backend
│   ├── main.py                         # FastAPI app, lifespan
│   ├── api/
│   │   ├── ws_live_listener.py         # WebSocket handler (616 lines)
│   │   └── documents.py                # RAG document API
│   └── services/                       # Core services (17 files)
│       ├── asr_providers.py            # Provider abstraction (370 lines)
│       ├── provider_faster_whisper.py  # CTranslate2 implementation
│       ├── provider_whisper_cpp.py     # Metal GPU implementation
│       ├── provider_voxtral_realtime.py # Streaming subprocess
│       ├── degrade_ladder.py           # Adaptive performance
│       ├── analysis_stream.py          # NLP cards/entities
│       └── diarization.py              # Speaker separation
├── tests/                              # Python tests (6 files)
├── scripts/                            # Utilities
│   ├── benchmark_voxtral_vs_whisper.py
│   └── soak_test.py
├── docs/                               # Documentation
│   ├── audit/                          # Audit documents
│   └── WORKLOG_TICKETS.md
├── landing/                            # Static landing page
├── pyproject.toml                      # Python deps (FastAPI, etc.)
└── AGENTS.md                           # Development workflow
```

**Lines of Code:**
- Swift: ~8,900 lines (macapp)
- Python: ~6,500 lines (server + tests)

---

## 2) Critical Execution Path Trace

### Audio Flow: Capture → Transcription → UI

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLIENT (Swift) - macOS Menu Bar App                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ScreenCaptureKit / AVAudioEngine                                           │
│       │                                                                     │
│       ▼                                                                     │
│  AudioCaptureManager.processAudio()              [AudioCaptureManager.swift]│
│  - Converts to 16kHz PCM16 mono                                            │
│  - Emits 320-sample (20ms) frames                                          │
│       │                                                                     │
│       ▼                                                                     │
│  onPCMFrame?(data, "system") → WebSocketStreamer.sendPCMFrame()            │
│       │                                                                     │
│       ▼                                                                     │
│  WebSocket (ws://localhost:8000/ws/live-listener)                          │
│  - JSON: {"type":"audio","source":"system","data":"base64..."}              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  SERVER (Python/FastAPI)                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ws_live_listener.py:ws_live_listener()                                     │
│       │                                                                     │
│       ▼                                                                     │
│  put_audio() → asyncio.Queue (per source, max 48 chunks)                   │
│       │                                                                     │
│       ▼                                                                     │
│  _asr_loop() → stream_asr() → provider.transcribe_stream()                 │
│       │                                                                     │
│       ├── FasterWhisperProvider:                                           │
│       │   - Accumulates chunks (default 4s)                                │
│       │   - threading.Lock() on model.transcribe()                         │
│       │   - Yields ASRSegment(is_final=True)                               │
│       │                                                                    │
│       ├── WhisperCppProvider:                                              │
│       │   - Similar chunked-batch pattern                                  │
│       │   - Inference serialized under lock (`_infer_lock`, as of 2026-02-13) │
│       │                                                                    │
│       └── VoxtralRealtimeProvider:                                         │
│           - Streaming subprocess (--stdin mode)                            │
│           - Session lifecycle management                                   │
│                                                                             │
│       ▼                                                                     │
│  ws_send() → WebSocket JSON → Client                                       │
│  {"type":"asr_final","text":"...","t0":1.0,"t1":3.0,...}                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  CLIENT (Swift) - UI Update                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WebSocketStreamer.handleJSON()                                             │
│       │                                                                     │
│       ▼                                                                     │
│  onASRFinal?(text, t0, t1, confidence, source)                              │
│       │                                                                     │
│       ▼                                                                     │
│  AppState.handleFinal() → Updates @Published transcriptSegments            │
│       │                                                                     │
│       ▼                                                                     │
│  SwiftUI View re-renders with new transcript                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## A) Architecture Summary

### Components + Boundaries

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              ECHOPANEL ARCHITECTURE                        │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                         PRESENTATION LAYER                          │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  │
│  │  │  SidePanel   │  │ Onboarding   │  │  SummaryView │   SwiftUI    │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │  │
│  │                           ▲                                         │  │
│  │                           │ @Published                              │  │
│  │  ┌────────────────────────┴────────────────────────┐               │  │
│  │  │                   AppState (MainActor)          │               │  │
│  │  │  - Session state machine                        │               │  │
│  │  │  - Audio capture orchestration                  │               │  │
│  │  │  - Transcript accumulation                      │               │  │
│  │  └─────────────────────────────────────────────────┘               │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                       │
│                                    │ WebSocket + HTTP                       │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                         SERVICE LAYER (Python)                      │  │
│  │  ┌───────────────────────────────────────────────────────────────┐ │  │
│  │  │  FastAPI + WebSocket                                          │ │  │
│  │  │  - ws_live_listener.py (per-source queues)                    │ │  │
│  │  │  - documents.py (RAG storage)                                 │ │  │
│  │  └───────────────────────────────────────────────────────────────┘ │  │
│  │                                    │                                 │  │
│  │  ┌─────────────────────────────────┼─────────────────────────────┐ │  │
│  │  │           ASR PIPELINE          │                             │ │  │
│  │  │  ┌──────────────┐  ┌──────────┐▼┌──────────────┐            │ │  │
│  │  │  │   Provider   │──│   VAD    │││  Diarization │            │ │  │
│  │  │  │   Registry   │  │  Filter  │││   (optional) │            │ │  │
│  │  │  └──────────────┘  └──────────┘└──────────────┘            │ │  │
│  │  │         │                                                     │ │  │
│  │  │         ├── faster_whisper (CTranslate2, CPU)                 │ │  │
│  │  │         ├── whisper_cpp (Metal GPU)                           │ │  │
│  │  │         └── voxtral_realtime (streaming subprocess)           │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐ │  │
│  │  │           ANALYSIS PIPELINE (asyncio.to_thread)             │ │  │
│  │  │  - extract_cards() → actions, decisions, risks              │ │  │
│  │  │  - extract_entities() → people, orgs, dates                 │ │  │
│  │  │  - generate_rolling_summary() → markdown                    │ │  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                       │
│                                    ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                      PERSISTENCE LAYER                              │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐        │  │
│  │  │ SessionBundle  │  │   Keychain     │  │  UserDefaults  │        │  │
│  │  │ (JSON on disk) │  │ (HF token)     │  │ (preferences)  │        │  │
│  │  └────────────────┘  └────────────────┘  └────────────────┘        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### Threading/Concurrency Model

**Client (Swift):**
- **MainActor**: All UI state updates (`AppState` is `@MainActor`)
- **Background queues**: 
  - `SCStream` callbacks on `.global(qos: .userInitiated)`
  - Audio conversion happens synchronously on callback thread
  - WebSocket send is synchronous (⚠️ potential blocking)

**Server (Python/asyncio):**
- **Single event loop**: All ASR providers use `asyncio.to_thread()` for CPU work
- **Per-source queues**: Each audio source (system, mic) has independent `asyncio.Queue`
- **Provider locking**:
  - `faster_whisper`: `threading.Lock()` on inference (serializes concurrent calls)
  - `whisper_cpp`: NO lock (⚠️ assumes thread-safe or single-threaded)
  - `voxtral`: Subprocess-based, naturally serialized

### Data Flow Per Audio Frame

| Stage | Location | Transform | Latency Budget |
|-------|----------|-----------|----------------|
| 1. Capture | macOS SCStream | Raw PCM → 16kHz float | <5ms |
| 2. Convert | AudioCaptureManager | float → int16, 320-sample frames | <1ms |
| 3. Send | WebSocketStreamer | JSON + base64 | <5ms |
| 4. Receive | ws_live_listener.py | Parse → Queue | <1ms |
| 5. ASR | Provider | Accumulate → Infer → Emit | 200-1000ms (chunked) |
| 6. Return | WebSocket | JSON response | <5ms |
| 7. UI | AppState → SwiftUI | Update transcript | <16ms (60fps) |

---

## B) Code-Specific Findings (Table)

### P0 Critical (5 items)

| Severity | Area | Finding | Evidence | Why It Matters | Fix Strategy | Effort |
|----------|------|---------|----------|----------------|--------------|--------|
| **P0** | ASR | `whisper_cpp` provider inference must be serialized for multi-source safety | **Status (2026-02-13):** Implemented via `_infer_lock` in `server/services/provider_whisper_cpp.py` | With 2 audio sources (mic+system), concurrent calls to whisper.cpp can crash/corrupt | Keep lock; document thread-safety assumptions per provider | S |
| **P0** | Security | Auth token support via URL query param is risky | Server still accepts `?token=` for backward compatibility (`server/api/ws_live_listener.py`), but the client uses headers (`macapp/MeetingListenerApp/Sources/BackendConfig.swift`) | URL tokens are easier to leak via logs/copy/paste | Deprecate/remove query-token support; keep header-only | M |
| **P0** | Reliability | Audio capture must not be blocked by WebSocket sends | **Status (2026-02-13):** Client uses bounded async send queue (`macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`) | Network stall blocks audio capture; dropped audio | Keep bounded queue + explicit drop policy + metrics | M |
| **P0** | Concurrency | Provider registry instances never evicted | `asr_providers.py:299,334`: `_instances: dict[str, ASRProvider]` grows unbounded; no eviction policy | Long-running server with varied configs = memory leak | Add LRU eviction (max 2-3 providers) | M |
| **P0** | Performance | `faster_whisper` single lock serializes ALL inference | `provider_faster_whisper.py:166`: `with self._infer_lock` around `model.transcribe()` | 2 sources cannot parallelize; 2x latency with dual-source | Consider per-source provider instances or lock-free design | L |

### P1 High (8 items)

| Severity | Area | Finding | Evidence | Why It Matters | Fix Strategy | Effort |
|----------|------|---------|----------|----------------|--------------|--------|
| **P1** | Architecture | VAD runs INSIDE ASR, not pre-filter | `provider_faster_whisper.py:167`: `vad_filter=self.config.vad_enabled` passed to `transcribe()` | Silent audio still triggers model inference; wasted compute | Pre-filter with `vad_filter.py` before enqueueing | M |
| **P1** | Reliability | NLP work must be bounded by timeouts | **Status (2026-02-13):** Implemented via `asyncio.wait_for(...)` around incremental entity/card extraction in `server/api/ws_live_listener.py` | NLP hang blocks analysis loop indefinitely | Keep timeouts + status emissions when delayed | S |
| **P1** | Security | Backend token stored in Keychain but also migrated from UserDefaults | `KeychainHelper.swift`: Migration logic suggests previous insecure storage | Token may exist in plaintext in UserDefaults backup | Audit migration; clear UserDefaults after migration | S |
| **P1** | Observability | Provider health should be visible in WS metrics | **Status (2026-02-13):** Implemented: `provider_health` emitted in WS `metrics` payload (`server/api/ws_live_listener.py`) | Cannot detect ASR stall vs queue backlog | Keep provider health emission and document field shape | S |
| **P1** | Performance | Diarization runs synchronously at session end | `ws_live_listener.py:526-537`: `await _run_diarization_per_source()` blocks WS close | 30s+ audio = multi-second delay for final summary | Run diarization in background; stream interim results | M |
| **P1** | Reliability | `stopAndAwaitFinalSummary` timeout not configurable | `WebSocketStreamer.swift:121`: Hardcoded 10s timeout in `stopAndAwaitFinalSummary()` | Long sessions may need more time for flush | Make timeout configurable via parameter | XS |
| **P1** | Testing | No integration tests for 2-source scenario | `tests/test_streaming_correctness.py`: Tests single source only | Dual-source is common use case; untested | Add 2-source soak test | M |
| **P1** | Architecture | `ASRConfig` includes 7 parameters in registry key | `asr_providers.py:317`: `_cfg_key()` includes all config fields | Minor config change = new model instance = memory waste | Normalize key; exclude rarely-changed params | S |

### P2 Medium (7 items)

| Severity | Area | Finding | Evidence | Why It Matters | Fix Strategy | Effort |
|----------|------|---------|----------|----------------|--------------|--------|
| **P2** | Security | Debug audio dump writes to `/tmp` | `ws_live_listener.py:24`: `DEBUG_AUDIO_DUMP_DIR = /tmp/echopanel_audio_dump` | Sensitive audio data in world-readable location | Use app-specific directory with restricted permissions | S |
| **P2** | Reliability | Reconnect doesn't carry attempt_id | `WebSocketStreamer.swift:400`: `reconnect()` calls `connect(sessionID:)` without attemptID | Correlation broken on reconnect; debugging harder | Preserve attempt_id across reconnects | S |
| **P2** | Performance | PCM frames sent as base64 JSON | `WebSocketStreamer.swift:152-156`: Each frame base64 encoded | 33% overhead vs binary; unnecessary CPU | Support binary WebSocket frames | M |
| **P2** | Observability | `totalSamples` counter overflows | `AudioCaptureManager.swift:179`: `Int` counter, no wrap handling | Long sessions may overflow (though unlikely) | Use `UInt64` or wrap intentionally | XS |
| **P2** | Testing | Benchmark harness doesn't test VAD effectiveness | `scripts/benchmark_voxtral_vs_whisper.py`: No silence-heavy scenario | Cannot measure VAD performance gains | Add scenario C (95% silence) | S |
| **P2** | Architecture | Adaptive performance must be integrated (degrade ladder) | **Status (2026-02-13):** Integrated: `server/api/ws_live_listener.py` initializes `DegradeLadder` per session and checks it during `_asr_loop` | Without integration, backpressure handling is passive only | Keep integration + add tests for level transitions | M |
| **P2** | Security | No rate limiting on WebSocket connections | `ws_live_listener.py`: No connection rate limiting | Potential DoS via connection spam | Add connection rate limit (max 10/min) | S |

---

## C) Non-Negotiable Invariants (10)

1. **Audio Capture Thread Must Never Block**
   - Capture callbacks must return in <10ms
   - All network I/O must be offloaded to background queues
   - *Status (2026-02-13)*: Client uses bounded send queue (`macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`)

2. **Provider Inference Must Be Serialized Per Model Instance**
   - `faster_whisper`: ✅ Uses `threading.Lock()`
   - `whisper_cpp`: ✅ Uses `_infer_lock` (as of 2026-02-13)
   - *Enforcement*: All providers must document thread-safety guarantees

3. **WebSocket Messages Must Include Correlation IDs**
   - `session_id`: User-facing session identifier
   - `attempt_id`: Per-connection attempt (survives reconnect)
   - `connection_id`: Per-WS connection (for debugging)
   - *Current state*: Partially implemented in V1 branch

4. **ASR Provider Must Stay Resident Within Session**
   - Model load happens once per unique config
   - No per-chunk subprocess spawn (Voxtral v0.2 fixed this)
   - *Violation if*: Registry eviction happens mid-session

5. **Queue Overflow Must Drop Oldest, Not Newest**
   - Audio latency is cumulative; dropping newest would amplify lag
   - *Current implementation*: ✅ `put_audio()` drops oldest at L253

6. **Secrets Must Never Appear in Logs or URLs**
   - HF token, backend token in Keychain only
   - URL query params must not contain auth tokens
   - *Current violation*: Token extraction from query params (P0)

7. **Graceful Degradation Must Be Automatic**
   - RTF > 1.0 → increase chunk size
   - RTF > 1.2 → drop to single source
   - Provider crash → failover to alternative
   - *Status (2026-02-13)*: Degrade ladder is wired into WS session handling (`server/api/ws_live_listener.py`)

8. **Session End Must Complete Within Bounded Time**
   - ASR flush: <5 seconds
   - Diarization: <10 seconds (or skipped)
   - Final summary: <5 seconds
   - *Current violation*: No timeout on NLP calls (P1)

9. **Timestamps Must Be Monotonic Per Source**
   - `t1` of segment N must equal `t0` of segment N+1
   - Gaps allowed but must be explicit (not hidden by timestamp math)
   - *Current state*: ✅ `processed_samples` counter

10. **All Async Operations Must Have Timeouts**
    - WebSocket send: <100ms
    - ASR inference: <10s
    - NLP extraction: <10s
    - Health check: <2s
    - *Status (2026-02-13)*: NLP calls are guarded with `asyncio.wait_for(...)` timeouts in analysis loop

---

## D) Security Review (STRIDE-lite)

### Spoofing
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| WS auth token | Medium | Token in query param (`ws_live_listener.py:150`) | Move to header; constant-time compare |
| Session ID | Low | UUID generated client-side (`AppState.swift:519`) | Validate format server-side |

### Tampering
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| Audio dump files | Medium | Written to `/tmp` (`ws_live_listener.py:24`) | Restrict to app directory; encrypt |
| Transcript storage | Low | JSON on disk (`SessionStore.swift`) | Sandbox-enforced path; no additional encryption |

### Repudiation
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| Missing audit log | Medium | No structured audit log of session events | Add `StructuredLogger` to all operations |

### Information Disclosure
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| Debug logs | Medium | `NSLog` used throughout; may log PII | Sanitize logs; use structured logger |
| Health endpoint | Low | Returns provider name (`main.py:67`) | Acceptable - no sensitive data |

### Denial of Service
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| WS connection spam | Medium | No rate limiting on WS endpoint | Add connection rate limit |
| Audio queue overflow | Low | Queue max 48 chunks (`ws_live_listener.py:22`) | Drops oldest; prevents memory exhaustion |
| Slowloris | Low | Ping/pong every 10s (`WebSocketStreamer.swift:406`) | Connection timeout adequate |

### Elevation of Privilege
| Vector | Risk | Evidence | Mitigation |
|--------|------|----------|------------|
| Screen recording | N/A | User-granted permission | Expected for app function |
| Microphone | N/A | User-granted permission | Expected for app function |

### Secrets Handling
| Secret | Storage | Evidence | Assessment |
|--------|---------|----------|------------|
| HF Token | Keychain | `KeychainHelper.swift` | ✅ Secure |
| Backend Token | Keychain | `KeychainHelper.swift` | ✅ Secure |
| Session Data | JSON on disk | `SessionStore.swift` | ⚠️ No encryption at rest |

### Model Download Integrity
| Aspect | Status | Evidence |
|--------|--------|----------|
| Checksum verification | NOT FOUND | No evidence of hash verification for downloaded models |
| HTTPS | Assumed | `faster-whisper` uses HuggingFace Hub (HTTPS) |
| Supply chain | Risk | PyPI dependencies in `pyproject.toml` |

---

## E) Performance and Reliability

### Hotspots (Profiling Candidates)

1. **ASR Inference** — `provider_faster_whisper.py:167`
   - Takes 200-1000ms per chunk
   - Holds GIL via `asyncio.to_thread()`
   - **Profile target**: `model.transcribe()` latency distribution

2. **Audio Conversion** — `AudioCaptureManager.swift:157`
   - `AVAudioConverter.convert()` on every buffer
   - **Profile target**: Conversion time vs buffer size

3. **NLP Analysis** — `analysis_stream.py:101-162`
   - `extract_cards()` called every 40s
   - Pattern matching on all transcript text
   - **Profile target**: Execution time vs transcript length

### Backpressure Points

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BACKPRESSURE CHAIN                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. WebSocket Send Buffer (Client)                                      │
│     - NOT MONITORED — URLSession internal                               │
│     - Risk: Blocks capture thread                                       │
│                                                                         │
│  2. Server Queue (per source)                                          │
│     - Size: 48 chunks (~1.5s audio)                                    │
│     - Overflow: Drop oldest                                            │
│     - Metric: `queue_fill_ratio`                                        │
│                                                                         │
│  3. ASR Provider Buffer                                                │
│     - Size: Unbounded (accumulates to chunk_seconds)                   │
│     - Overflow: None (grows indefinitely)                              │
│     - Metric: Implicit in latency                                      │
│                                                                         │
│  4. Analysis Queue (Implicit)                                          │
│     - Size: 1 (transcript list)                                        │
│     - Overflow: Blocks on NLP completion                               │
│     - Metric: None                                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Crash-Only Design Assessment

| Component | Crash Behavior | Recovery | Evidence |
|-----------|----------------|----------|----------|
| Swift App | Restart | Session lost; no auto-recovery | `AppState.swift` no crash handler |
| Python Server | Restart | Server recovers; session lost | `BackendManager.swift` restart logic |
| ASR Provider | Session error | Provider stays loaded; new session | `provider_*.py` no crash recovery |
| WebSocket | Reconnect | Exponential backoff (1s→10s) | `WebSocketStreamer.swift:394-401` |

### Logging Granularity and Correlation

**Current State (V1 Implementation):**
- `StructuredLogger.swift`: New structured logging with correlation IDs
- `WebSocketStreamer.swift:46-47`: `correlationIDs` property added
- Server-side: `attempt_id`, `connection_id` in `SessionState` (`ws_live_listener.py:31-32`)

**Gaps:**
- Python side doesn't use correlation IDs consistently
- No distributed tracing across Swift/Python boundary

---

## F) Testing Strategy Critique

### Unit Tests
| Area | Coverage | Gaps |
|------|----------|------|
| ASR providers | Basic | No test for 2-source concurrency |
| Provider registry | Thread-safety | No eviction test |
| Degrade ladder | Logic only | No integration with real providers |

### Integration Tests
| Area | Coverage | Gaps |
|------|----------|------|
| WebSocket protocol | Yes (`test_streaming_correctness.py`) | No 2-source test |
| Audio capture | No | Requires macOS environment |
| Full pipeline | No | No end-to-end automated test |

### Packaged Smoke Test
| Component | Status | Issue |
|-----------|--------|-------|
| Swift tests | Present | Requires macOS; not CI-friendly |
| Python tests | Present | Run with `pytest` |
| E2E Playwright | NOT FOUND | No browser-based E2E |

### Reproducible Run Receipts
| Requirement | Status | Evidence |
|-------------|--------|----------|
| Version pinning | Partial | `uv.lock` present; `Package.resolved` for Swift |
| Environment capture | No | No `requirements.txt` export in tests |
| Seed for random | N/A | No randomness in tests |
| Log correlation | Partial | Correlation IDs added in V1 |

---

## G) Concrete Patch Set

### Patch 1: Add Inference Lock to Whisper.cpp (P0)

```diff
--- a/server/services/provider_whisper_cpp.py
+++ b/server/services/provider_whisper_cpp.py
@@ -40,6 +40,7 @@ class WhisperCppProvider(ASRProvider):
         self._model_path = _default_model()
         self._n_threads = _n_threads()
         self._ctx: Optional[WhisperContext] = None
+        self._infer_lock = threading.Lock()  # P0: Add lock for thread safety
         self._stats = WhisperCppStats()
 
@@ -379,7 +380,10 @@ class WhisperCppProvider(ASRProvider):
                     infer_start = time.perf_counter()
                     
                     def _transcribe():
-                        return ctx.transcribe(audio, language=self.config.language)
+                        with self._infer_lock:  # P0: Serialize inference
+                            return ctx.transcribe(
+                                audio, language=self.config.language
+                            )
 
                     segments = await asyncio.to_thread(_transcribe)
```

### Patch 2: Add Timeout to NLP Calls (P1)

```diff
--- a/server/api/ws_live_listener.py
+++ b/server/api/ws_live_listener.py
@@ -306,7 +306,10 @@ async def _analysis_loop(websocket: WebSocket, state: SessionState) -> None:
         while True:
             await asyncio.sleep(12)
             snapshot = list(state.transcript)
-            entities = await asyncio.to_thread(extract_entities, snapshot)
+            entities = await asyncio.wait_for(
+                asyncio.to_thread(extract_entities, snapshot),
+                timeout=10.0  # P1: Prevent indefinite hang
+            )
             await ws_send(state, websocket, {"type": "entities_update", **entities})
 
             await asyncio.sleep(28)
```

### Patch 3: Add Async Send Queue to WebSocketStreamer (P0)

```diff
--- a/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift
+++ b/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift
@@ -53,6 +53,10 @@ final class WebSocketStreamer: NSObject {
     private var reconnectDelay: TimeInterval = 1
     private let maxReconnectDelay: TimeInterval = 10
     private var finalSummaryWaiter: CheckedContinuation<Bool, Never>?
+    
+    // P0: Bounded send queue to prevent blocking capture thread
+    private let sendQueue = OperationQueue()
+    private let maxQueuedSends = 100
 
     override init() {
+        sendQueue.maxConcurrentOperationCount = 1
+        sendQueue.qualityOfService = .utility
         super.init()
     }
 
@@ -204,9 +208,20 @@ final class WebSocketStreamer: NSObject {
     private func sendJSON(_ payload: [String: Any]) {
         guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
         guard let text = String(data: data, encoding: .utf8) else { return }
-        task?.send(.string(text)) { [weak self] error in
-            if let error { self?.handleError(error) }
+        
+        // P0: Enqueue send instead of blocking
+        guard sendQueue.operationCount < maxQueuedSends else {
+            StructuredLogger.shared.warning("Send queue overflow, dropping frame")
+            return
         }
+        
+        sendQueue.addOperation { [weak self] in
+            guard let self else { return }
+            self.task?.send(.string(text)) { error in
+                if let error { self.handleError(error) }
+            }
+        }
     }
```

### Command Block to Run Tests

```bash
#!/bin/bash
# Run from /Users/pranay/Projects/EchoPanel

set -e

echo "=== 1. Format Swift ==="
cd macapp/MeetingListenerApp
swiftformat --lint Sources/ 2>/dev/null || echo "swiftformat not installed, skipping"

echo "=== 2. Build Swift ==="
swift build 2>&1 | head -20

echo "=== 3. Swift Tests ==="
swift test 2>&1 | tail -30

cd ../..

echo "=== 4. Python Format ==="
python -m black --check server/ tests/ 2>/dev/null || echo "black not installed, skipping"

echo "=== 5. Python Lint ==="
python -m mypy server/ --ignore-missing-imports 2>/dev/null || echo "mypy issues found"

echo "=== 6. Python Tests ==="
python -m pytest tests/ -v --tb=short 2>&1 | tail -40

echo "=== 7. Minimal Smoke Run ==="
# Start server in background
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 &
SERVER_PID=$!
sleep 5

# Health check
curl -s http://127.0.0.1:8000/health | head -1

# Kill server
kill $SERVER_PID 2>/dev/null || true

echo "=== Complete ==="
```

---

## Summary

### Risk Rankings

| Rank | Issue | Severity | Effort | Files |
|------|-------|----------|--------|-------|
| 1 | Whisper.cpp inference lock (implemented as of 2026-02-13) | P0 | S | `provider_whisper_cpp.py` |
| 2 | WebSocket send off capture thread (implemented as of 2026-02-13) | P0 | M | `WebSocketStreamer.swift` |
| 3 | Provider registry memory leak | P0 | M | `asr_providers.py` |
| 4 | VAD runs inside ASR (wasted compute) | P1 | M | `asr_stream.py` |
| 5 | NLP timeouts required (implemented as of 2026-02-13) | P1 | S | `ws_live_listener.py` |
| 6 | Debug audio in /tmp | P2 | S | `ws_live_listener.py` |
| 7 | Degrade ladder integration (implemented as of 2026-02-13) | P2 | M | `server/api/ws_live_listener.py` |

### Architecture Strengths
1. Clean separation between Swift UI and Python backend
2. Provider abstraction allows ASR swapping
3. Per-source queues prevent head-of-line blocking
4. Correlation IDs added for observability (V1)
5. Comprehensive audit documentation

### Architecture Weaknesses
1. WebSocket transport couples client and server tightly
2. No binary frame support (base64 overhead)
3. NLP blocking on main thread pool
4. Missing end-to-end integration tests
5. No chaos engineering / fault injection

---

*End of Review*
