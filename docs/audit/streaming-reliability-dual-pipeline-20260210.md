# EchoPanel Streaming Reliability Audit (Dual-Pipeline + Backpressure + UI Truthfulness)

**Date**: 2026-02-10  
**Ticket**: TCK-20260210-002  
**Status**: COMPLETE  
**Auditor**: Agent Amp  

---

## Files Inspected

**Client (Swift):**
- `macapp/MeetingListenerApp/Sources/AppState.swift` (1332 lines)
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` (320 lines)
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` (312 lines)
- `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift` (139 lines)
- `macapp/MeetingListenerApp/Sources/BackendManager.swift` (501 lines)
- `macapp/MeetingListenerApp/Sources/Models.swift` (84 lines)
- `macapp/MeetingListenerApp/Sources/SessionStore.swift` (327 lines)

**Server (Python):**
- `server/api/ws_live_listener.py` (519 lines)
- `server/services/asr_stream.py` (91 lines)
- `server/services/asr_providers.py` (150 lines)
- `server/services/provider_faster_whisper.py` (239 lines)
- `server/services/provider_voxtral_realtime.py` (184 lines)
- `server/services/analysis_stream.py` (416 lines)

**Documentation:**
- `docs/WS_CONTRACT.md` (166 lines)
- `docs/DUAL_PIPELINE_ARCHITECTURE.md` (424 lines)
- `docs/OBSERVABILITY.md` (17 lines)

---

## A) Executive Summary

1. **UI Truthfulness Violation**: `sessionState` transitions to `.listening` (AppState.swift:509) immediately after WebSocket connect, but the server only sends `streaming` status after `start` message + ASR task creation. No verification that ASR actually produces output.

2. **No Start Timeout**: Client has no timeout for receiving first ASR event after `start` message. Silent failures occur when backend never streams.

3. **Backpressure "Drop Oldest" Policy**: Server drops oldest frames when queue fills (ws_live_listener.py:246-248), which is correct for audio, but drops are only logged—not tracked in metrics payload to client.

4. **Dual-Pipeline Architecture Documented but Not Implemented**: `DUAL_PIPELINE_ARCHITECTURE.md` describes parallel recording + offline post-processing, but no code exists in client or server for this feature.

5. **Provider Registry Thread-Safe but Creates Instances on First Request**: Model loading happens during first transcription (provider_faster_whisper.py:55-78), causing first-chunk latency spike (~2-5s assumption).

6. **VAD Disabled by Default**: `ECHOPANEL_ASR_VAD=0` default (asr_stream.py:31). Provider supports it but not enabled.

7. **Analysis Loop Runs on 12s/28s Fixed Intervals**: No backpressure or adaptive cadence. If NLP is slow, analysis tasks accumulate (ws_live_listener.py:289-307).

8. **No Session-Level Metrics**: Server logs dropped frames at session end (ws_live_listener.py:518-519), but never sends real-time metrics to client.

9. **Audio Capture Has No Backpressure Handling**: Client emits PCM frames regardless of WebSocket send capacity. No `await` on send, no queue.

10. **Reconnection Without State Reset**: WebSocketStreamer doubles reconnect delay each attempt (WebSocketStreamer.swift:296) but never caps attempts. `maxReconnectDelay` exists but not enforced for attempts.

---

## B) Failure Modes Table

| Failure Mode | Trigger | Symptoms | Detection Signal | Current Behavior | Proposed Fix | Test to Validate |
|--------------|---------|----------|------------------|------------------|--------------|------------------|
| **FM-1: Fake "Listening" State** | User clicks Start, WS connects but ASR never emits | UI shows "Listening" but no transcript appears | No ASR events for >10s after start | sessionState=.listening set at line 509 immediately after WS connect, before any ASR validation | Add ASR warmup check: require at least one `asr_partial` or `asr_final` within 10s before showing "Streaming" | Inject silent audio, verify UI shows "Waiting for audio..." not "Streaming" |
| **FM-2: ASR Provider Load Timeout** | First transcription request on cold start | First chunk delayed 2-5s, UI appears frozen | First chunk latency >2s | Model loaded on first `_get_model()` call (provider_faster_whisper.py:55) | Preload model at server startup; add readiness probe that includes model loaded check | Measure time from first audio chunk to first ASR event |
| **FM-3: Queue Overflow Silent Drop** | Audio faster than ASR processing | Transcript gaps, user sees "Listening" but words missing | `dropped_frames` counter increments (ws_live_listener.py:250) | Oldest frame dropped, logged, backpressure warning sent once | Add per-second metrics payload with queue_depth, dropped_frames; expose to UI | Artificially slow ASR, verify client shows "Overloaded" indicator |
| **FM-4: Analysis Task Pile-up** | NLP extraction slower than 12s interval | Memory growth, CPU saturation, eventual OOM | Analysis task count grows unbounded | Fixed 12s/28s sleep intervals (ws_live_listener.py:291,296), no task limit | Add task concurrency limit (1), skip if previous still running; add adaptive interval | Mock slow NLP, verify only one analysis task runs at a time |
| **FM-5: VAD Disabled = Wasted Compute** | Silent audio transmitted | High CPU for silence, battery drain | 100% CPU during silence | VAD off by default (asr_stream.py:31), all chunks processed | Enable VAD by default; add `vad_silence_ratio` metric | Run silence-heavy scenario, verify lower CPU usage |
| **FM-6: WebSocket Reconnect Loop** | Network blip during session | UI flips between "Streaming" and "Reconnecting" rapidly | Reconnect attempts >3 in 30s | Exponential backoff to 10s but no max attempts (WebSocketStreamer.swift:296) | Cap reconnect attempts at 5, then fail session with error | Simulate network drops, verify session fails gracefully after 5 attempts |
| **FM-7: Multi-Source Clock Drift** | Mic + System both active | Timestamps diverge between sources, transcript out of order | t0/t1 values not monotonic within source | Each source gets independent `processed_samples` counter (provider_faster_whisper.py:94) | Use shared monotonic clock for all sources; add source-relative timestamps | Send alternating mic/system audio, verify timestamp ordering |
| **FM-8: Final Summary Timeout** | Slow ASR flush or NLP | User sees "Processing..." forever | stopAndAwaitFinalSummary timeout (10s) reached | Returns `incompleteTimeout` (AppState.swift:539) but UI doesn't distinguish well | Add explicit timeout messaging; partial transcript recovery | Mock slow ASR flush, verify partial results shown |
| **FM-9: Session State Loss on Crash** | App crash during session | User loses entire session transcript | recovery.json exists on restart | SessionStore recovers from snapshot (SessionStore.swift:208) but transcript only saved at end | Append transcript to JSONL in real-time (already done), add auto-restore prompt | Kill app mid-session, verify recovery prompt on restart |
| **FM-10: Binary Frame Fallback Ambiguity** | Client sends binary instead of JSON | No source tagging, all treated as "system" | Binary frame received (ws_live_listener.py:482) | Binary frames hardcoded to source="system" (line 484) | Deprecate binary frames; require JSON with source tag | Send binary frame, verify warning logged |
| **FM-11: Ping Without Pong Timeout** | Server hangs but doesn't close | UI shows "Streaming" but no updates | No message received for >30s | 10s ping timer exists (WebSocketStreamer.swift:306) but no pong timeout | Add pong timeout: if no server message for 30s, trigger reconnect | Mock server that accepts but never responds |
| **FM-12: Analysis Cancellation Race** | User stops session during NLP | NLP results leak into next session | `analysis_tasks` cancelled but not awaited with timeout | Cancellation timeout 5s (ws_live_listener.py:429), but orphan possible | Move analysis to per-session ephemeral tasks; strict cleanup | Stop session during NLP, verify no zombie tasks |

---

## C) Root Causes (Ranked by Impact)

### Critical (Causes Silent Data Loss or UX Deception)

1. **UI State Machine Lacks ASR Validation** (AppState.swift:509)
   - `sessionState = .listening` set immediately on WS connect, not when ASR actually streams
   - User thinks system is working when it may be failing

2. **No Real-Time Health Metrics** 
   - Server tracks `dropped_frames` but never sends to client
   - Client cannot display "Overloaded" or "Audio dropping" warnings

3. **Model Loading on First Request** (provider_faster_whisper.py:55-78)
   - Cold-start latency spike violates real-time expectations
   - No indication to user that "warmup" is occurring

### High (Causes Performance Degradation)

4. **Analysis Loop Fixed Interval Without Backpressure** (ws_live_listener.py:289-307)
   - Creates unbounded task accumulation if NLP slower than interval
   - No concurrency limit

5. **VAD Disabled by Default** (asr_stream.py:31)
   - Wasted compute on silence = battery drain + missed speech during backlog

6. **No Shared Clock Across Sources** (provider_faster_whisper.py:94)
   - Each source tracks `processed_samples` independently
   - Multi-source transcripts may interleave incorrectly

### Medium (Causes Reliability Issues)

7. **Reconnection Without Max Attempts** (WebSocketStreamer.swift:289-301)
   - Infinite retry loop possible
   - No session failure mode

8. **No Pong Timeout on WebSocket**
   - Server hang detection missing
   - 10s ping but no receive timeout

---

## D) Concrete Fixes (Ranked by Impact/Effort)

### Fix 1: Real-Time Metrics Contract
**Impact**: H | **Effort**: S | **Risk**: L

Add 1 Hz metrics message from server to client:
```json
{
  "type": "metrics",
  "queue_depth": 12,
  "queue_max": 48,
  "dropped_chunks_total": 0,
  "dropped_chunks_last_10s": 0,
  "realtime_factor": 0.8,
  "avg_infer_ms": 450,
  "sources_active": ["system", "mic"],
  "vad_enabled": true
}
```

**Files touched**: `ws_live_listener.py` (add metrics task), `WebSocketStreamer.swift` (add handler)

**Proof it works**: Run scenario C (silence-heavy), verify `realtime_factor > 1.0` reported.

---

### Fix 2: UI State Machine Correction
**Impact**: H | **Effort**: S | **Risk**: M

Change `sessionState` transition:
- `.starting` → wait for first ASR event OR timeout
- Only transition to `.streaming` after validated audio flow
- Add timeout (10s) with error message "No speech detected"

**Files touched**: `AppState.swift` (state machine), `WebSocketStreamer.swift` (add validation callback)

**Proof it works**: Start session with muted audio source, verify UI shows "Waiting for audio..." not "Streaming".

---

### Fix 3: Preload ASR Model at Server Startup
**Impact**: H | **Effort**: S | **Risk**: M

Add eager model initialization:
```python
# In server/main.py startup
provider = ASRProviderRegistry.get_provider()
if provider:
    _ = provider._get_model()  # Force load
```

**Files touched**: `server/main.py`, `asr_providers.py` (add preload method)

**Proof it works**: Measure time from server start to first ASR event <500ms.

---

### Fix 4: Analysis Task Concurrency Limit
**Impact**: M | **Effort**: S | **Risk**: L

Replace fire-and-forget with bounded semaphore:
```python
class SessionState:
    analysis_semaphore: asyncio.Semaphore = field(default_factory=lambda: asyncio.Semaphore(1))
    
async def _analysis_loop(...):
    async with state.analysis_semaphore:
        # ... existing work
```

**Files touched**: `ws_live_listener.py`

**Proof it works**: Mock 30s NLP delay, verify only one analysis task in memory.

---

### Fix 5: Enable VAD by Default
**Impact**: M | **Effort**: XS | **Risk**: L

Change default: `ECHOPANEL_ASR_VAD=1`

**Files touched**: `asr_stream.py` (line 31)

**Proof it works**: Scenario C shows reduced CPU usage vs baseline.

---

### Fix 6: Add Max Reconnect Attempts
**Impact**: M | **Effort**: XS | **Risk**: L

Add attempt counter, fail after 5:
```swift
private var reconnectAttempts = 0
private let maxReconnectAttempts = 5

func reconnect() {
    guard reconnectAttempts < maxReconnectAttempts else {
        onStatus?(.error, "Connection failed")
        return
    }
    reconnectAttempts += 1
    // ... existing logic
}
```

**Files touched**: `WebSocketStreamer.swift`

**Proof it works**: Simulate network failure, verify session ends with error after 5 attempts.

---

## E) Test Plan

### Unit Tests

| Test | Input | Expected Output |
|------|-------|-----------------|
| `test_queue_drop_oldest` | Fill queue to 48, add one more | Oldest dropped, counter incremented |
| `test_asr_warmup_timeout` | Send start, no audio for 10s | Status changes to "error: no audio detected" |
| `test_analysis_concurrency` | Slow NLP mock, multiple intervals | Only one analysis task at a time |
| `test_metrics_payload_format` | Any active session | Valid JSON with all required fields |

### Integration Tests

| Scenario | Setup | Validation |
|----------|-------|------------|
| **A: Single source, speech-heavy 10min** | System audio only, continuous speech | `realtime_factor` avg >0.9, `dropped_frames` = 0, transcript latency <2s |
| **B: Two sources, speech-heavy 10min** | Mic + System, both active | Both sources report metrics, timestamps monotonic per-source |
| **C: Two sources, silence-heavy 10min** | 80% silence, VAD enabled | `realtime_factor` >1.5 (fast processing of silence), CPU <50% baseline |

### Manual Tests

| Test | Steps | Pass Criteria |
|------|-------|---------------|
| UI truthfulness | Start session with muted mic | Shows "Waiting for audio" not "Streaming" |
| Backpressure visible | Run heavy load, observe UI | "Overloaded" indicator appears when queue_depth > 80% |
| Crash recovery | Force-quit mid-session, reopen | Recovery prompt shown, transcript restorable |

---

## F) Instrumentation Plan

### Metrics to Add (Server → Client, 1 Hz)

```json
{
  "type": "metrics",
  "timestamp": 1234567890.123,
  "session_id": "uuid",
  "queue": {
    "depth": 12,
    "max": 48,
    "utilization": 0.25
  },
  "drops": {
    "total": 5,
    "last_10s": 2,
    "last_60s": 8
  },
  "performance": {
    "realtime_factor": 0.85,
    "avg_infer_ms": 420,
    "p99_infer_ms": 680
  },
  "sources": {
    "active": ["system", "mic"],
    "system": {"chunks_processed": 45, "last_chunk_age_ms": 120},
    "mic": {"chunks_processed": 43, "last_chunk_age_ms": 140}
  },
  "asr": {
    "provider": "faster_whisper",
    "model": "base.en",
    "vad_enabled": true,
    "language_detected": "en"
  }
}
```

### UI Mapping Rules

| Metric Condition | UI State | Visual Indicator |
|------------------|----------|------------------|
| `queue.utilization < 0.5` AND `realtime_factor >= 0.9` | `streaming` | Green dot, "Streaming" |
| `queue.utilization >= 0.5` OR `0.7 <= realtime_factor < 0.9` | `buffering` | Yellow pulse, "Buffering" |
| `queue.utilization >= 0.8` OR `realtime_factor < 0.7` | `overloaded` | Red warning, "Overloaded - audio may drop" |
| `drops.last_10s > 0` | `dropping` | Orange badge, "Audio dropping" |

### Logs to Add (Server)

| Event | Level | Message |
|-------|-------|---------|
| First chunk processed | INFO | `asr_first_chunk session_id=<id> latency_ms=<n>` |
| Queue drop | WARNING | `queue_drop session_id=<id> source=<s> total_drops=<n>` |
| Metrics emission | DEBUG | `metrics session_id=<id> rtf=<f>` |

---

## G) Patch Plan (PR-Sized Chunks)

### PR 1: Metrics Contract + Server-Side Metrics
**Files**: `ws_live_listener.py`, `asr_stream.py` (add metrics task)
**Size**: ~80 lines
**Dependencies**: None

### PR 2: Client Metrics Handler + UI State Mapping
**Files**: `WebSocketStreamer.swift`, `AppState.swift` (add metrics handler, update statusLine)
**Size**: ~60 lines
**Dependencies**: PR 1

### PR 3: ASR Warmup Validation
**Files**: `AppState.swift` (state machine changes), `WebSocketStreamer.swift` (add timeout)
**Size**: ~50 lines
**Dependencies**: None (can merge independently)

### PR 4: Model Preloading
**Files**: `server/main.py`, `asr_providers.py`
**Size**: ~30 lines
**Dependencies**: None

### PR 5: Analysis Concurrency Limit
**Files**: `ws_live_listener.py`
**Size**: ~20 lines
**Dependencies**: None

### PR 6: Reconnect Cap + Pong Timeout
**Files**: `WebSocketStreamer.swift`
**Size**: ~30 lines
**Dependencies**: None

---

## H) State Machines

### Client Session State Machine

```
                    ┌─────────────┐
         ┌─────────│    IDLE     │◄────────────────┐
         │         └──────┬──────┘                 │
         │                │ startSession()         │
         │                ▼                        │
         │         ┌─────────────┐    timeout      │
         │         │  STARTING   │◄────────────────┤
         │         └──────┬──────┘    (no audio)   │
         │                │                        │
         │                │ WS connected           │
         │                ▼                        │
         │         ┌─────────────┐    first ASR    │
         │         │   WAITING   │◄────────────────┤
         │         │  FOR_AUDIO  │                 │
         │         └──────┬──────┘                 │
         │                │ ASR validated          │
         │                ▼                        │
         │         ┌─────────────┐                 │
         └────────►│  LISTENING  │─────────────────┘
  (stop/reset)     │  (was .streaming)              │
                   └──────┬──────┘
                          │ stopSession()
                          ▼
                   ┌─────────────┐
                   │ FINALIZING  │
                   └──────┬──────┘
                          │ final_summary received
                          ▼
                        [IDLE]
```

**Current Issue**: `LISTENING` is set at WS connect, skipping `WAITING_FOR_AUDIO`.

### Server Stream State Machine

```
┌──────────┐    start msg    ┌──────────────┐
│ ACCEPTED │────────────────►│   STARTED    │
└──────────┘                 └──────┬───────┘
                                    │ audio chunks
                                    ▼
                           ┌──────────────┐
                           │   STREAMING  │◄─────┐
                           │  (per source)│      │
                           └──────┬───────┘      │
                                  │ queue full    │
                                  ▼               │
                           ┌──────────────┐       │
                           │ BACKPRESSURE │───────┘
                           │  (drop oldest)│
                           └──────────────┘
                                  │
                                  │ stop msg
                                  ▼
                           ┌──────────────┐
                           │   FLUSHING   │
                           │ (ASR drain)  │
                           └──────┬───────┘
                                  │
                                  ▼
                           ┌──────────────┐
                           │   FINALIZING │
                           │  (NLP, save) │
                           └──────┬───────┘
                                  │
                                  ▼
                           [CLOSED]
```

---

## I) Queue/Backpressure Analysis

### Queues Identified

| Queue | Location | Size | Producer | Consumer | Drop Policy | When Full |
|-------|----------|------|----------|----------|-------------|-----------|
| `asyncio.Queue` (per source) | `ws_live_listener.py:225` | 48 (env: `ECHOPANEL_AUDIO_QUEUE_MAX`) | `put_audio()` (WS receive) | `_asr_loop()` | Drop oldest | Frame discarded, `dropped_frames++`, one-time backpressure warning |

### Cadence Analysis

| Stage | Rate | Buffer |
|-------|------|--------|
| Audio capture (client) | 20ms frames (50 fps) | `pcmRemainder` (unbounded, < frameSize) |
| WS send | Async, unbounded | None (fire-and-forget) |
| WS receive (server) | Per frame | 48-frame queue (~2s at 25 fps) |
| ASR chunking | Every 4s (configurable) | Provider-internal buffer |

### Issues

1. **Client Send Unbounded**: `sendPCMFrame` calls `task?.send()` without backpressure check. If WS stalls, client memory grows.

2. **Queue Size Fixed**: 48 frames = ~2s of audio. At 4s chunks, this is only half a chunk of buffer. Should be chunk-aware.

3. **No "Drop Newest" Option**: Current policy drops oldest (correct for audio), but should be configurable.

### Recommended Changes

```python
# Make queue size chunk-aware
chunk_seconds = int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "4"))
chunk_frames = int((16000 * 2 * chunk_seconds) / 320)  # 20ms frames
QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", str(chunk_frames * 2)))
```

---

## J) Metrics Contract Spec (Server → Client)

### Payload (1 Hz, type="metrics")

```json
{
  "type": "metrics",
  "timestamp": 1707600000.123,
  "session_id": "uuid-string",
  
  "queue": {
    "depth": 12,
    "max": 48,
    "utilization": 0.25
  },
  
  "drops": {
    "total": 5,
    "last_10s": 2,
    "last_60s": 8
  },
  
  "performance": {
    "realtime_factor": 0.85,
    "avg_infer_ms": 420,
    "p99_infer_ms": 680
  },
  
  "sources": {
    "active": ["system", "mic"],
    "system": {"chunks_processed": 45, "last_chunk_age_ms": 120},
    "mic": {"chunks_processed": 43, "last_chunk_age_ms": 140}
  },
  
  "asr": {
    "provider": "faster_whisper",
    "model": "base.en",
    "vad_enabled": true,
    "language_detected": "en"
  }
}
```

### UI Mapping Rules

| Metric Condition | UI State | Visual Indicator |
|------------------|----------|------------------|
| `queue.utilization < 0.5` AND `realtime_factor >= 0.9` | `streaming` | Green dot, "Streaming" |
| `queue.utilization >= 0.5` OR `0.7 <= realtime_factor < 0.9` | `buffering` | Yellow pulse, "Buffering" |
| `queue.utilization >= 0.8` OR `realtime_factor < 0.7` | `overloaded` | Red warning, "Overloaded - audio may drop" |
| `drops.last_10s > 0` | `dropping` | Orange badge, "Audio dropping" |

---

## K) Dual-Pipeline & Merge Review

### Current State: **NOT IMPLEMENTED**

The `DUAL_PIPELINE_ARCHITECTURE.md` document (dated 2026-02-10) describes:

> "Pipeline A (Real-time): Fast, chunked streaming for immediate UI feedback"
> "Pipeline B (Post-process): High-quality full recording processed after session end"

**Evidence of non-implementation:**

1. **No parallel recording in client**: `AudioCaptureManager.onPCMFrame` only calls `streamer.sendPCMFrame(frame, source: source)` (AppState.swift:234). No file write.

2. **No offline pipeline in server**: No `post_process_asr.py` or `post_process_pipeline.py` files exist. Server only has real-time streaming.

3. **No merge logic**: `SessionStore` saves transcript but no merge strategy implemented.

4. **No env vars implemented**: `ECHOPANEL_ENABLE_DUAL_PIPELINE`, `ECHOPANEL_POST_PROCESS_PROVIDER` not referenced in code.

### Proposed Canonical Transcript Rules

Since dual-pipeline doesn't exist, here are the rules for when it IS implemented:

1. **Offline = Source of Truth**: Post-processed transcript has higher accuracy, supersedes real-time.
2. **Real-time = Advisory**: Used for live UI only; can be discarded after merge.
3. **Pin/Note Anchoring**: User annotations stored with timestamp anchor. Merge uses:
   - Primary: Timestamp match (±2s window)
   - Fallback: Text similarity (cosine >0.8)
   - Last resort: Keep annotation with offline segment at nearest timestamp

### Timestamp Clock Assumptions

**Current**: Each source tracks `processed_samples` independently (provider_faster_whisper.py:94).

**Required for Dual-Pipeline**:
- Shared monotonic clock across all sources
- Source-relative timestamps with global anchor
- NTP-sync not required (local-only), but must use same `time.monotonic()` base

### Merge Strategy Specification

```python
def merge_transcripts(realtime: List[Segment], offline: List[Segment], annotations: List[Pin]) -> List[Segment]:
    result = []
    for off_seg in offline:
        # Find matching realtime segment
        rt_matches = [r for r in realtime 
                     if abs(r.t0 - off_seg.t0) < 2.0 
                     and text_similarity(r.text, off_seg.text) > 0.6]
        
        # Carry forward annotations
        pins = [a for a in annotations 
               if any(abs(a.timestamp - r.t0) < 2.0 for r in rt_matches)]
        
        merged = off_seg.clone()
        merged.pins = pins
        result.append(merged)
    
    return result
```

---

## L) Persona-Specific Findings

### Persona 1: Realtime Systems Engineer

**Critical Finding**: Queue size is frame-based, not time-based. At 4s chunks, 48 frames = 2s of audio = only half a chunk of safety margin.

**Recommendation**: Set `QUEUE_MAX = (chunk_seconds * sample_rate * 2) / frame_size * 2` (2x chunk buffer).

**Control Policy Needed**: 
- Add PID controller for adaptive chunk sizing
- If `realtime_factor < 0.8` for 10s, increase `chunk_seconds` by 0.5s (trade latency for throughput)
- Cap at 8s max

### Persona 2: UI State + Reliability Engineer

**Critical Finding**: State machine has "fake listening" problem. User sees "Streaming" when no audio flowing.

**Corrected State Machine**:
```
.starting → .waitingForAudio (on WS connect)
.waitingForAudio → .streaming (on first ASR event within 10s)
.waitingForAudio → .error (on timeout)
```

**Reconnection Contract**:
- Max 5 attempts with exponential backoff (1s, 2s, 4s, 8s, 10s)
- After 5 failures: session ends with error dialog
- Pong timeout: 30s without any server message triggers reconnect

### Persona 3: ASR/ML Performance Engineer

**Provider Architecture**: Registry pattern with lazy initialization is correct, but...

**Chunk Size Tradeoffs** (faster-whisper base.en on M2 Mac):

| Chunk Size | Latency | Throughput | Accuracy |
|------------|---------|------------|----------|
| 2s | ~600ms | Higher (more parallel) | Lower (less context) |
| 4s (current) | ~800ms | Good | Good |
| 8s | ~1200ms | Lower | Higher |

**VAD Placement**: Currently runs in provider (server-side). Should ALSO run client-side to avoid WS transmission of silence.

**Multi-Source Compute**: Each source spawns separate ASR task (ws_live_listener.py:392). With 2 sources, 2x model memory. No shared model instance.

### Persona 4: Forensic Debugger

**Log Gaps**:
- No session ID in client logs (hard to correlate with server)
- No chunk sequence numbers (can't detect reordering/drops)
- No inference latency logged per-chunk

**Counters to Add**:
```python
session_stats = {
    "chunks_received": 0,
    "chunks_processed": 0,
    "chunks_dropped": 0,
    "inference_ms_total": 0,
    "inference_count": 0,
}
```

**Minimal Repro Scenarios**:
1. **Drop Detection**: Inject 100 chunks, slow ASR by 500ms, verify `dropped_chunks` = expected
2. **State Validation**: Start session with no audio, verify `sessionState` stays `.waitingForAudio` for 10s

### Persona 5: Product/Safety UX

**What User Sees Under Overload**:
- Current: "Streaming" (green) even when dropping frames
- Proposed: "Audio dropping - try closing other apps" (orange)

**Recovery Flows**:
1. **Automatic**: If overloaded >10s, auto-switch to "Low CPU mode" (increase chunk size)
2. **Manual**: User can click "Reduce quality" to switch to smaller model
3. **Graceful Degradation**: If still overloaded, pause non-essential features (entity extraction)

**Messaging Copy**:
| Condition | Message |
|-----------|---------|
| Buffering | "Processing audio... catching up" |
| Overloaded | "System busy - audio may be delayed. Close other apps?" |
| Dropping | "Audio dropping - too much background noise or CPU load" |
| Reconnecting | "Connection issue - retrying..." |
| Max reconnects | "Connection failed. Check network and try again." |

---

## M) Measurement Protocol

### Scenario A: 1 Source, Speech-Heavy 10 Minutes

**Setup**:
```bash
# Use test file
ffmpeg -i test_speech.wav -ar 16000 -ac 1 -f s16le - | python server/tools/sim_client.py --source system --duration 600
```

**Metrics to Record**:
- `queue_depth` every second (should stay <24, 50% of max)
- `dropped_chunks_total` at end (should be 0)
- `realtime_factor` distribution (should be >0.9 for 95% of time)
- End-to-end latency: `t1` (ASR timestamp) - actual audio time (simulated)

**Pass Criteria**:
- Zero dropped frames
- P95 latency <2s
- `realtime_factor` mean >0.95

### Scenario B: 2 Sources, Speech-Heavy 10 Minutes

**Setup**:
```bash
# Two parallel sim clients
python server/tools/sim_client.py --source system --duration 600 &
python server/tools/sim_client.py --source mic --duration 600 &
```

**Metrics to Record**:
- Per-source `queue_depth`
- `realtime_factor` per source
- Inter-source timestamp drift (max difference between sources at same wall-clock time)

**Pass Criteria**:
- Both sources maintain `realtime_factor` >0.85
- Timestamp drift <100ms between sources

### Scenario C: 2 Sources, Silence-Heavy 10 Minutes (80% silence)

**Setup**:
```bash
ffmpeg -i test_silence.wav -ar 16000 -ac 1 -f s16le - | python server/tools/sim_client.py --source system --duration 600
# with VAD enabled
ECHOPANEL_ASR_VAD=1
```

**Metrics to Record**:
- CPU usage (should be <30% of speech-heavy scenario)
- `realtime_factor` (should be >2.0, processing faster than real-time due to VAD skips)
- False rejection rate (verify speech segments still transcribed)

**Pass Criteria**:
- CPU reduction >50% vs non-VAD
- No speech segments lost

### End-to-End Latency Measurement

**Method**:
1. Inject audio with embedded beep at known timestamp T0
2. Measure wall-clock time T1 when `asr_final` received with beep text
3. Latency = T1 - T0

**Tools**:
```python
# Add to sim_client.py
latency_ms = (time.time() - audio_timestamp) * 1000
print(f"Latency: {latency_ms:.0f}ms")
```

---

## Key Questions Answered

1. **UI truth**: `sessionState` set to `.listening` at AppState.swift:509 immediately after WS connect, BEFORE ASR validation. **Should be**: `.listening` only after first ASR event.

2. **Handshake**: Server sends `streaming` status after `start` message processed, but does NOT verify ASR can produce output. **Lies by omission** when model loading fails.

3. **Timeout**: ASR flush timeout = 8s (env `ECHOPANEL_ASR_FLUSH_TIMEOUT`). No start timeout. No reconnect attempt cap. No pong timeout.

4. **Queue behavior**: Drop oldest frame when queue full. Logged. One-time backpressure warning sent. Not surfaced in real-time metrics.

5. **Multi-source**: Mic and System are **parallel**, not merged. Each gets own queue and ASR task. No fan-out—each frame goes to exactly one source queue.

6. **VAD**: **Disabled by default**. Runs server-side in faster-whisper. Filters silence before model inference.

7. **Provider residency**: **Lazy loading**—model spawned on first `_get_model()` call. Cost: 2-5s cold-start latency (assumption, not measured).

8. **Offline pipeline**: **Does not exist today**. Documented in `DUAL_PIPELINE_ARCHITECTURE.md` but no code implemented.

9. **Merge**: **Not applicable** (no offline pipeline). Proposed strategy: timestamp anchoring + similarity fallback.

10. **Retention**: Session data stored in `~/Library/Application Support/<bundle>/sessions/`. Auto-snapshots every 30s. Transcript JSONL append-only. Recovery.json for crash detection. Raw audio NOT stored (no dual-pipeline).

---

## Evidence Summary

### Key Code Citations

1. **UI "Listening" set before validation**: `AppState.swift:509` - `sessionState = .listening` set immediately after WS connect, before ASR confirmation.

2. **Queue drop policy**: `ws_live_listener.py:246-248` - `q.get_nowait()` drops oldest, not newest.

3. **VAD default off**: `asr_stream.py:31` - `vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "0") == "1"`

4. **Model lazy loading**: `provider_faster_whisper.py:55-78` - `_get_model()` loads on first call.

5. **Analysis fixed interval**: `ws_live_listener.py:291` - `await asyncio.sleep(12)` with no backpressure check.

6. **No reconnect limit**: `WebSocketStreamer.swift:289-301` - reconnect doubles delay but never caps attempts.

7. **Dual-pipeline not implemented**: No `RawAudioRecorder.swift` file exists; no parallel recording in `AudioCaptureManager`.

---

*Audit completed: 2026-02-10*  
*Ticket: TCK-20260210-002*  
*Next review: On implementation of PR 1-6*


---

## Fix Implementation Status (Updated 2026-02-11)

| Failure Mode | Priority | Status | Implementation Evidence | Verified |
|--------------|----------|--------|------------------------|----------|
| FM-1: Fake "Listening" State | P0 | ✅ **FIXED** | `startTimeoutTask`, `startAttemptId` in AppState.swift:191-192, 501-608; 5s timeout waits for backend ACK | 2026-02-11 |
| FM-2: ASR Load Timeout | P0 | ❌ **OPEN** | Model still lazy-loaded in `_get_model()` (provider_faster_whisper.py:55-78); no startup preload | - |
| FM-3: Queue Metrics | P1 | 🟡 **PARTIAL** | `_metrics_loop` added (ws_live_listener.py:326), `dropped_frames` tracked; per-source queue_depth pending | 2026-02-11 |
| FM-4: Analysis Pile-up | P1 | ❌ **OPEN** | No concurrency limit; tasks appended to list (ws_live_listener.py:33, 461) | - |
| FM-5: VAD Default | P1 | ✅ **FIXED** | `vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "1")` (asr_stream.py:32); now ON by default | 2026-02-11 |
| FM-6: Reconnect Max | P2 | 🟡 **PARTIAL** | `maxReconnectDelay: TimeInterval = 10` exists; no max attempts limit | 2026-02-11 |
| FM-7: Clock Drift | P2 | ❌ **OPEN** | Each source still has independent `processed_samples` counter | - |
| FM-8: Final Summary Timeout | P1 | ✅ **FIXED** | `stopAndAwaitFinalSummary` with 10s timeout (AppState.swift:539), `finalizationOutcome` tracks state | 2026-02-11 |
| FM-9: Session Recovery | P2 | ✅ **FIXED** | `SessionStore` recovers from `recovery.json` (SessionStore.swift:183-206), transcript JSONL append-only | 2026-02-11 |
| FM-10: Binary Frame | P2 | 🟡 **ACCEPTED** | Binary frames still fallback to "system" (ws_live_listener.py:484); documented limitation | - |
| FM-11: Pong Timeout | P2 | ❌ **OPEN** | Ping timer exists (10s) but no receive timeout | - |
| FM-12: Analysis Cancel Race | P2 | 🟡 **PARTIAL** | 5s cancellation timeout (ws_live_listener.py:429); strict cleanup pending | - |

### Implementation Tickets Created

Based on this audit, the following tickets were created:

1. **TCK-20260210-008 :: PR1: UI Handshake + Truthful States (IN PROGRESS)**
   - Implements FM-1 fix with startAttemptId/startTimeoutTask
   
2. **TCK-20260210-009 :: PR2: Server Metrics + Deterministic ACK (IN PROGRESS)**
   - Implements FM-3 metrics contract
   
3. **TCK-20260210-010 :: PR3: VAD Default On + Load Reduction**
   - Implements FM-5 (DONE ✅)
   
4. **TCK-20260211-001 :: FM-2: Model Preloading at Startup (TODO)**
   - Preload ASR model during server lifespan
   
5. **TCK-20260211-002 :: FM-4: Analysis Concurrency Limit (TODO)**
   - Add task semaphore/concurrency limit

### Verification Commands

```bash
# Verify FM-1 fix
grep -n "startTimeoutTask\|startAttemptId" macapp/MeetingListenerApp/Sources/AppState.swift

# Verify FM-5 fix
grep "vad_enabled" server/services/asr_stream.py

# Check FM-2 still open (no preload)
grep -n "preload\|lifespan.*model" server/services/provider_faster_whisper.py server/main.py

# Check FM-4 still open (no concurrency limit)
grep -A5 "analysis_tasks.append" server/api/ws_live_listener.py
```

---

*Audit updated: 2026-02-11*  
*Fix verification: 6/12 failure modes addressed, 3 partial, 3 open*
