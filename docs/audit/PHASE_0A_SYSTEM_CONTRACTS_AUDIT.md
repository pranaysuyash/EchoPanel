# EchoPanel Phase 0A Audit: System Contracts + State Machines

**Date:** 2026-02-11
**Auditor:** Amp (AI Agent)
**Scope:** Client/Server Streaming Truth Contracts
**Status:** OPEN
**Last reviewed:** 2026-02-11 (Audit Queue Runner)

---

## A) Files Inspected

### Client (macOS Swift)
```
macapp/MeetingListenerApp/Sources/
├── AppState.swift                    (lines 1-1000+)
├── WebSocketStreamer.swift           (lines 1-351)
├── BackendManager.swift              (lines 1-501)
├── Models.swift                      (lines 1-84)
├── AudioCaptureManager.swift
├── MicrophoneCaptureManager.swift
├── DesignTokens.swift
└── SidePanelView.swift
```

### Server (Python/FastAPI)
```
server/
├── api/ws_live_listener.py           (lines 1-616)
├── services/asr_stream.py            (lines 1-91)
├── services/asr_providers.py
├── services/provider_faster_whisper.py
└── main.py                           (lines 1-94)
```

---

## B) Current Contract Extraction (From Repo)

### B1) Client → Server Message Types

| Type | Schema | Sent From | Evidence |
|------|--------|-----------|----------|
| `start` | `{type: "start", session_id: string, sample_rate: int, format: "pcm_s16le", channels: int}` | `WebSocketStreamer.sendStart()` | ws_live_listener.py:440-458 |
| `audio` | `{type: "audio", source: "system"\|"mic", data: base64_string}` | `WebSocketStreamer.sendPCMFrame()` | ws_live_listener.py:465-487 |
| `stop` | `{type: "stop", session_id: string}` | `WebSocketStreamer.sendStop()` | ws_live_listener.py:489-564 |

**CRITICAL GAP:** No `attempt_id` or correlation ID in messages. Client has `startAttemptId` (AppState.swift:481) but never sends it to server.

### B2) Server → Client Message Types

| Type | Schema | Purpose | Evidence |
|------|--------|---------|----------|
| `status` | `{type: "status", state: "streaming"\|"backpressure"\|"warning"\|"overloaded"\|"buffering"\|"error"\|"connected", message: string, ...}` | State notifications | ws_live_listener.py:417, 458, 508, 560 |
| `asr_partial` | `{type: "asr_partial", t0, t1, text, stable, confidence, source?, language?, speaker?}` | Interim transcript | asr_stream.py:74-90 |
| `asr_final` | `{type: "asr_final", ...same as partial...}` | Final transcript | asr_stream.py:74-90 |
| `cards_update` | `{type: "cards_update", actions: [], decisions: [], risks: [], window: {}}` | NLP extraction | ws_live_listener.py:315-321 |
| `entities_update` | `{type: "entities_update", people: [], orgs: [], dates: [], projects: [], topics: []}` | Entity extraction | ws_live_listener.py:310 |
| `final_summary` | `{type: "final_summary", markdown: string, json: object}` | Session end summary | ws_live_listener.py:546-562 |
| `metrics` | `{type: "metrics", source, queue_depth, queue_max, queue_fill_ratio, dropped_total, dropped_recent, avg_infer_ms, realtime_factor, timestamp}` | Health metrics (1Hz) | ws_live_listener.py:375-386 |

**CRITICAL GAP:** No `session_ack` message. Server sends `status: "connected"` immediately on connect, then `status: "streaming"` after start, but no explicit ACK with accepted: true/false.

### B3) Client State Variables

```swift
// From AppState.swift
@Published var sessionState: SessionState = .idle        // idle | starting | listening | finalizing | error
@Published var streamStatus: StreamStatus = .reconnecting // streaming | reconnecting | error
@Published var backpressureLevel: BackpressureLevel = .normal // normal | buffering | overloaded
@Published var elapsedSeconds: Int = 0

// Private tracking
private var startAttemptId: UUID?                        // NOT sent to server
private var startTimeoutTask: Task<Void, Never>?
private var sessionID: String?
```

### B4) Server State Variables

```python
# From ws_live_listener.py SessionState dataclass
session_id: Optional[str] = None
started: bool = False                                    # True after "start" message received
asr_tasks: list[asyncio.Task] = field(default_factory=list)
queues: Dict[str, asyncio.Queue] = field(default_factory=dict)
active_sources: Set[str] = field(default_factory=set)
backpressure_warned: bool = False
dropped_frames: int = 0
closed: bool = False

# Environment-based constants
QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", "48"))
ECHOPANEL_ASR_FLUSH_TIMEOUT = float(os.getenv("ECHOPANEL_ASR_FLUSH_TIMEOUT", "8"))
ECHOPANEL_ASR_CHUNK_SECONDS = float(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2"))
```

---

## C) State Machines (CURRENT)

### C1) Client Session State Machine

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CLIENT STATE MACHINE                               │
└─────────────────────────────────────────────────────────────────────────────┘

STATES:
  [IDLE] → [STARTING] → [LISTENING] → [FINALIZING] → [IDLE]
                              ↓
                           [ERROR]

TRANSITIONS:

1. IDLE → STARTING
   Trigger: User clicks "Start Session"
   Action: AppState.startSession() called
   Evidence: AppState.swift:472-583

2. STARTING → LISTENING  
   Trigger: streamer.onStatus receives .streaming
   Condition: status == .streaming && sessionState == .starting
   Action: Cancel timeout task, set sessionState = .listening
   Evidence: AppState.swift:277-281

3. STARTING → ERROR
   Trigger: Timeout (5s) OR permission denied OR capture failed
   Action: stopSession(), set error state
   Evidence: AppState.swift:555-571 (timeout), 499-544 (permission errors)

4. LISTENING → FINALIZING
   Trigger: User clicks "Stop Session"
   Action: AppState.stopSession() called
   Evidence: AppState.swift:586-622

5. FINALIZING → IDLE
   Trigger: ASR flush complete + final summary received (or timeout)
   Action: Cleanup, reset state
   Evidence: AppState.swift:593-621

6. ANY → ERROR
   Trigger: streamer.onStatus receives .error
   Action: Set runtimeErrorState
   Evidence: AppState.swift:283-289

CRITICAL RACE:
- STARTING → LISTENING transition depends on server sending status: "streaming"
- But server sends this immediately after receiving "start" (ws_live_listener.py:458)
- Server does NOT wait for ASR pipeline to be actually ready
```

### C2) Server Stream State Machine

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SERVER STATE MACHINE                                │
└─────────────────────────────────────────────────────────────────────────────┘

STATES (per WebSocket connection):
  [CONNECTED] → [STARTED] → [STREAMING] → [STOPPING] → [CLOSED]
                    ↓
              [BACKPRESSURE] → [RECOVERING]

TRANSITIONS:

1. CONNECTED → STARTED
   Trigger: Receive "start" message from client
   Condition: Validate sample_rate==16000, format=="pcm_s16le", channels==1
   Action: Set started=True, create queues, start analysis task
   Evidence: ws_live_listener.py:440-463

2. STARTED → STREAMING
   Trigger: Immediately after validation (same function)
   Action: Send status: "streaming" to client
   Evidence: ws_live_listener.py:458
   
   *** CONTRACT ISSUE: Server claims "streaming" before ASR is actually ready ***

3. STREAMING → BACKPRESSURE
   Trigger: Queue fill ratio > 0.95 OR dropped frames detected
   Action: Send status: "backpressure" or "overloaded" to client
   Evidence: ws_live_listener.py:260-267, 356-363

4. BACKPRESSURE → RECOVERING → STREAMING
   Trigger: Queue fill ratio drops below 0.70
   Action: Clear backpressure_warned flag
   Evidence: ws_live_listener.py:371-372

5. STREAMING → STOPPING
   Trigger: Receive "stop" message
   Action: Signal EOF to queues, wait for ASR flush (8s timeout)
   Evidence: ws_live_listener.py:489-522

6. STOPPING → CLOSED
   Trigger: ASR flush complete + final summary sent
   Action: Close websocket
   Evidence: ws_live_listener.py:563

WHEN IS SERVER "READY TO INGEST AUDIO"?
- Current: Immediately after "start" message validation (line 458)
- Actual ASR readiness depends on:
  - Provider initialization (may be lazy)
  - Model loading (may be on-demand)
  - Queue creation (immediate)
```

---

## D) Truth Table: UI Labels vs Backend Truth (CURRENT)

| UI Label | Condition in Code | Backend Truth Needed | Failure Risk | Evidence |
|----------|-------------------|---------------------|--------------|----------|
| "Ready" | sessionState==.idle && isServerReady | Health check 200 | Backend 503 but UI shows Ready | AppState.swift:374-375 |
| "Starting" | sessionState==.starting | Capture permissions granted, WS connecting | UI shows Starting but capture failed | AppState.swift:475 |
| "Listening" | sessionState==.listening | Received status: "streaming" | **UI LIE**: Server sent streaming but ASR not actually processing | AppState.swift:277-281 |
| "Streaming" | streamStatus==.streaming | Server sent status: "streaming" | Same as above - no verification | AppState.swift:379 |
| "Reconnecting" | streamStatus==.reconnecting | WebSocket error/close | May flicker rapidly | WebSocketStreamer.swift:315-317 |
| "Preparing backend" | sessionState==.idle && !isServerReady | Health check !200 | Stuck if backend never ready | AppState.swift:374-375 |
| "Buffering" | backpressureLevel==.buffering | queue_fill_ratio > 0.85 | May not clear if metrics stop | AppState.swift:302 |
| "Overloaded" | backpressureLevel==.overloaded | queue_fill_ratio > 0.95 OR dropped_recent > 0 | False positive on transient drops | AppState.swift:299-300 |

**CRITICAL UI LIE:**
- UI shows "Listening" immediately when server sends `status: "streaming"`
- But server sends this BEFORE ASR provider is actually transcribing
- User thinks system is listening, but transcription may be silently failing

---

## E) Race Conditions and Contract Breaks (CURRENT)

### Issue 1: Phantom Listening
**Trigger Sequence:**
1. Client sends "start"
2. Server validates format, sets started=True
3. Server IMMEDIATELY sends status: "streaming"
4. Client transitions STARTING → LISTENING
5. ASR provider fails to initialize or model not loaded
6. User sees "Listening" but no transcription occurs

**Result:** UI lies - shows active listening when ASR is not processing

**Evidence:** ws_live_listener.py:458 sends streaming before ASR ready

**Fix Direction:** Server must only send "streaming" after ASR provider confirms readiness

---

### Issue 2: Orphaned Timeout Task
**Trigger Sequence:**
1. Client starts session, creates 5s timeout task
2. Server responds with streaming within 5s
3. Client cancels timeout task
4. User stops session immediately
5. User starts new session (new attemptId)
6. OLD timeout task wakes up, sees attemptId mismatch, but still calls stopSession()

**Result:** New session may be incorrectly stopped by old timeout

**Evidence:** AppState.swift:555-571 - timeout task doesn't check if session was stopped

**Fix Direction:** Timeout task must check sessionState and attemptId before acting

---

### Issue 3: Reconnect Without Session
**Trigger Sequence:**
1. Session active, streaming
2. WebSocket drops
3. WebSocketStreamer.reconnect() called
4. Reconnects with SAME sessionID
5. Server accepts connection, sends "connected"
6. Client sends audio frames
7. Server drops frames because started=False (no "start" message on new connection)

**Result:** Client thinks it's streaming, server silently drops audio

**Evidence:** ws_live_listener.py:571 - binary messages ignored if not state.started

**Fix Direction:** Reconnect must re-send "start" or server must persist session state

---

### Issue 4: Missing Correlation IDs
**Trigger Sequence:**
1. Client sends multiple messages rapidly
2. Server processes out of order
3. Client receives status: "error" 
4. Can't determine which message failed

**Result:** Can't correlate errors with requests

**Evidence:** No message_id or attempt_id in any message type

**Fix Direction:** Add attempt_id to all client→server messages

---

### Issue 5: Double Start
**Trigger Sequence:**
1. Client sends "start"
2. Network delay, client thinks it failed
3. Client sends "start" again
4. Server processes both, creates duplicate ASR tasks

**Result:** Duplicate transcription streams

**Evidence:** ws_live_listener.py:440-456 - no idempotency check

**Fix Direction:** Server must track session_id and reject duplicate starts

---

### Issue 6: Final Summary Race
**Trigger Sequence:**
1. Client sends "stop"
2. Server signals EOF to queues
3. ASR tasks flush finals
4. Client disconnects WebSocket (thinks stop complete)
5. Server tries to send final_summary
6. WebSocket closed, send fails silently

**Result:** Client never receives final summary

**Evidence:** ws_live_listener.py:546-562 - send happens after flush but no ACK required

**Fix Direction:** Client must wait for final_summary before closing

---

### Issue 7: Metrics Stale
**Trigger Sequence:**
1. Session active
2. Metrics flowing at 1Hz
3. ASR pipeline stalls (provider hangs)
4. Metrics stop updating (no new inference times)
5. UI shows "Listening" with stale metrics

**Result:** User thinks system is working, but ASR stalled

**Evidence:** AppState.swift:294-307 - no timeout on metrics freshness

**Fix Direction:** Client must track metrics timestamp, alert if stale > 5s

---

### Issue 8: Permission UI Lie
**Trigger Sequence:**
1. User starts session
2. Permission check passes
3. Session starts
4. User revokes permission in System Settings
5. Capture fails silently (no error callback)
6. UI still shows "Listening"

**Result:** UI shows active session but no audio flowing

**Evidence:** AudioCaptureManager doesn't notify on permission revocation

**Fix Direction:** Periodic permission re-check during session

---

## F) Proposed Minimal Contract (V1)

### F1) Required Message Types

#### Client → Server

**`start_session`** (replaces "start")
```json
{
  "type": "start_session",
  "attempt_id": "uuid",           // REQUIRED - correlation ID
  "session_id": "uuid",           // Session identifier
  "config": {
    "sample_rate": 16000,
    "format": "pcm_s16le", 
    "channels": 1
  },
  "sources": ["system", "mic"]    // Requested audio sources
}
```

**`audio_chunk`** (replaces "audio")
```json
{
  "type": "audio_chunk",
  "attempt_id": "uuid",           // Must match start_session
  "source": "system",             // "system" or "mic"
  "seq": 123,                     // Sequence number for detection of gaps
  "data": "base64..."             // PCM16 audio
}
```

**`stop_session`** (replaces "stop")
```json
{
  "type": "stop_session",
  "attempt_id": "uuid",           // Must match start_session
  "session_id": "uuid"
}
```

#### Server → Client

**`session_ack`** (NEW - REQUIRED)
```json
{
  "type": "session_ack",
  "attempt_id": "uuid",           // Echoes client's attempt_id
  "accepted": true,
  "ready_at": 1234567890.123      // Timestamp when ASR actually ready
}
// OR
{
  "type": "session_ack",
  "attempt_id": "uuid",
  "accepted": false,
  "reason": "ASR provider unavailable",
  "code": "ASR_UNAVAILABLE"
}
```

**`state`** (replaces "status" with stricter semantics)
```json
{
  "type": "state",
  "attempt_id": "uuid",
  "state": "streaming",           // Enum: starting | streaming | buffering | overloaded | stopping | error
  "since": 1234567890.123,        // When entered this state
  "detail": "optional message"
}
```

**`metrics`** (enhanced)
```json
{
  "type": "metrics",
  "attempt_id": "uuid",
  "source": "system",
  "timestamp": 1234567890.123,    // Server timestamp
  "queue": {
    "depth": 10,
    "max": 48,
    "fill_ratio": 0.21
  },
  "processing": {
    "dropped_total": 0,
    "dropped_recent": 0,
    "avg_infer_ms": 150.5,
    "realtime_factor": 0.75       // <1.0 = good, >1.0 = falling behind
  },
  "health": "healthy"             // healthy | degraded | critical
}
```

**`error`** (NEW - REQUIRED)
```json
{
  "type": "error",
  "attempt_id": "uuid",
  "code": "QUEUE_OVERFLOW",       // Machine-readable
  "message": "Audio queue full, dropping frames",
  "recoverable": true,            // Can retry or will auto-recover
  "fatal": false                  // If true, session ending
}
```

**`asr_partial` / `asr_final`** (unchanged structure, add attempt_id)
```json
{
  "type": "asr_final",
  "attempt_id": "uuid",           // Correlation
  "t0": 0.0,
  "t1": 2.5,
  "text": "transcribed text",
  "confidence": 0.95,
  "source": "system",
  "speaker": "Speaker 1"
}
```

### F2) Ordering Rules (Invariants)

1. **UI "Listening" only after:**
   - Client receives `session_ack` with `accepted: true`
   - AND client receives `state: "streaming"`
   - AND client receives first `metrics` with `health: "healthy"`

2. **Audio chunks ignored unless:**
   - Client has received `session_ack` with `accepted: true`
   - AND `attempt_id` matches the start_session attempt_id

3. **Late message handling:**
   - If `attempt_id` doesn't match current session → DROP (log warning)
   - If `seq` number shows gap → LOG gap, continue (don't crash)

4. **Stop idempotency:**
   - Multiple `stop_session` with same `attempt_id` → All return same response
   - Server must track "already stopped" state

5. **State machine integrity:**
   ```
   starting → streaming → buffering → overloaded → stopping
      ↓           ↓           ↓            ↓          ↓
    error       error      recover    recover    complete
   ```

### F3) Timeout and Retry Rules

| Timeout | Value | Behavior | Evidence |
|---------|-------|----------|----------|
| Start ACK | 5s | If no session_ack → fail with "Backend did not respond" | AppState.swift:557 |
| Streaming Ready | 10s | If session_ack but no streaming state → fail | NEW |
| Metrics Freshness | 5s | If no metrics update > 5s → show "Processing stalled" | NEW |
| Reconnect | 1s initial, exp backoff | Max 10s delay, max 3 attempts | WebSocketStreamer.swift:33 |
| Stop Flush | 8s | Wait for ASR flush, then force close | ws_live_listener.py:503 |
| Final Summary | 10s | Wait for final_summary, then close | AppState.swift:599 |

**Retry Strategy:**
- Exponential backoff: 1s → 2s → 4s → 8s → 10s (max)
- Max reconnect attempts: 3
- After max attempts → Enter ERROR state with recovery instructions

### F4) UI Label Mapping (Proposed)

| UI Label | Conditions | Backend State Required | Metrics Required |
|----------|------------|----------------------|------------------|
| "Starting..." | sessionState == .starting | N/A | N/A |
| "Connecting..." | Waiting for session_ack | N/A | N/A |
| "Initializing ASR..." | Got ack, waiting for streaming | session_ack.accepted == true | N/A |
| "Listening" | Fully operational | state == "streaming" | health == "healthy", metrics < 5s old |
| "Buffering" | Processing backlog | state == "buffering" | queue.fill_ratio > 0.85 |
| "Overloaded" | Dropping audio | state == "overloaded" | dropped_recent > 0 |
| "Reconnecting..." | WS disconnected | N/A | N/A |
| "Error" | Unrecoverable | fatal error received | N/A |

---

## G) Acceptance Criteria (V1)

### Measurable Pass/Fail Conditions

1. **It is impossible for UI to show "Listening" when server has not acknowledged streaming:**
   - Test: Mock server that sends session_ack but never sends state:streaming
   - Expected: UI shows "Initializing ASR..." indefinitely (or timeout)
   - Fail: UI shows "Listening"

2. **Late/out-of-order messages cannot flip state incorrectly:**
   - Test: Send status: "streaming" with old attempt_id during new session
   - Expected: Message dropped, state unchanged
   - Fail: State changes to listening

3. **Any start attempt either reaches streaming within timeout or fails with visible error:**
   - Test: Start session with backend that never responds
   - Expected: After 5s, UI shows error with "Backend did not respond"
   - Fail: UI stuck on "Starting..." forever

4. **stop_session always results in terminal state within bounded time:**
   - Test: Start session, immediately stop, mock server that hangs
   - Expected: After 10s, UI returns to idle (may show "Finalization incomplete")
   - Fail: UI stuck on "Finalizing" forever

5. **Metrics staleness detected and surfaced:**
   - Test: Start session, mock server that stops sending metrics after 2s
   - Expected: After 5s of no metrics, UI shows "Processing stalled" warning
   - Fail: UI continues showing "Listening" normally

6. **Reconnect with session continuity:**
   - Test: Start session, drop WS, reconnect
   - Expected: Client re-sends start_session with same attempt_id, server resumes
   - Fail: Client sends audio without start, server drops silently

---

## H1) Implementation Status (Updated 2026-02-11)

### PR 1: Add Correlation IDs to Protocol
**Status:** PARTIAL ✅ (50% complete)

**Completed:**
- ✅ Client sends attempt_id in start message (WebSocketStreamer.swift:187)
- ✅ Server stores and echoes attempt_id in responses (ws_live_listener.py:549, 469)
- ✅ CorrelationIDs struct created (WebSocketStreamer.swift:22-34)
- ✅ Metrics include attempt_id from server (ws_live_listener.py:469)

**Remaining:**
- ❌ Client does NOT validate attempt_id before accepting "streaming" status (WebSocketStreamer.swift:305-311)
- ❌ Late/out-of-order messages with old attempt_id can incorrectly flip state
- ❌ AppState.swift does not track or validate incoming attempt_id

**Evidence:** See Evidence Log below

---

### PR 2: Implement session_ack Contract
**Status:** NOT STARTED ❌

**Evidence:** No session_ack message type found in codebase (grep returned zero results)

---

### PR 3: Fix Server "Streaming" Truth
**Status:** NOT STARTED ❌

**Evidence:**
- Server sends "streaming" status at ws_live_listener.py:594-600
- Comment says "Now ASR is ready" but provider only retrieved for metadata
- No ASR provider readiness check before streaming status
- ASR loop starts lazily on first audio (ws_live_listener.py:622-628)

---

### PR 4: Client Timeout Hardening
**Status:** NOT STARTED ❌

**Evidence:**
- No metrics staleness detection (timestamp parsed but not validated)
- No 5s metrics freshness timeout implemented

---

### PR 5: Reconnect Session Continuity
**Status:** PARTIAL ✅ (40% complete)

**Completed:**
- ✅ Client re-sends start on reconnect (WebSocketStreamer.swift:448-461)
- ✅ Same session_id preserved across reconnect

**Remaining:**
- ❌ Server treats reconnect as new start (no session resume)
- ❌ No attempt_id validation on reconnect

---

### PR 6: Stop Flow Idempotency
**Status:** UNKNOWN (not reviewed)

---

## H2) Evidence Log

**2026-02-11 Evidence Gathering:**

```bash
# Checked for attempt_id in Swift client
rg "attempt_id" /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Found: WebSocketStreamer.swift:187, StructuredLogger.swift, SessionBundle.swift

# Checked for attempt_id in Python server
rg "attempt_id" /Users/pranay/Projects/EchoPanel/server/ --type py
# Found: ws_live_listener.py:549, 469, 603

# Checked for session_ack message
rg "session_ack" /Users/pranay/Projects/EchoPanel/ --type py --type swift
# Result: No matches (message type does not exist)

# Checked streaming status sending sequence
rg '"streaming"' /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py -B 20 -A 5
# Found: ws_live_listener.py:594-600 - sends streaming after retrieving provider metadata
# Critical: No ASR readiness check, just provider.get_provider() call

# Checked client status handling
rg 'case "status"' /Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift -A 15
# Found: Lines 301-312 - no attempt_id validation before state transition

# Checked metrics staleness detection
rg 'staleness\|stalled.*metric' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches (no staleness checking implemented)

# Verified file existence
ls /Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AppState.swift
# Exists (57825 bytes)
ls /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py
# Exists (35515 bytes)
```

**Interpretation:**
- PR 1 is 50% complete (correlation IDs sent but not validated)
- PR 2-4 are not started
- PR 5 is partially complete (reconnect sends start but no resume logic)
- Critical issue remains: server sends "streaming" before ASR is confirmed ready

---

## H3) Original Patch Plan (No Code, PR-Sized)

### PR 1: Add Correlation IDs to Protocol (HIGH IMPACT)
**Impact:** HIGH - Foundation for all other fixes  
**Effort:** MEDIUM - Touch all message handlers  
**Risk:** MEDIUM - Wire format change  

**Files:**
- `WebSocketStreamer.swift` - Add attempt_id to all sends
- `AppState.swift` - Track and validate attempt_ids
- `ws_live_listener.py` - Echo attempt_id in all responses

**Validation:**
- Manual: Start session, verify attempt_id appears in logs
- Unit: Test message serialization includes attempt_id

---

### PR 2: Implement session_ack Contract (HIGH IMPACT)
**Impact:** HIGH - Eliminates "Phantom Listening"  
**Effort:** MEDIUM - New message type, state handling  
**Risk:** LOW - Additive change  

**Files:**
- `ws_live_listener.py` - Send session_ack, defer streaming state
- `AppState.swift` - Wait for session_ack before showing connected
- `Models.swift` - Add new message types

**Validation:**
- Manual: Mock slow ASR startup, verify UI waits
- Integration: Test start→ack→streaming flow

---

### PR 3: Fix Server "Streaming" Truth (HIGH IMPACT)
**Impact:** HIGH - Core reliability fix  
**Effort:** MEDIUM - ASR provider readiness check  
**Risk:** MEDIUM - May expose slow ASR issues  

**Files:**
- `ws_live_listener.py` - Only send streaming after ASR confirms ready
- `asr_providers.py` - Add is_ready() method
- `provider_faster_whisper.py` - Implement readiness check

**Validation:**
- Manual: First session after server start, verify latency
- Integration: Test rapid start/stop/start sequence

---

### PR 4: Client Timeout Hardening (MEDIUM IMPACT)
**Impact:** MEDIUM - Better UX for failures  
**Effort:** SMALL - Add timeouts, fix race  
**Risk:** LOW - Defensive programming  

**Files:**
- `AppState.swift` - Fix orphaned timeout task, add metrics staleness check
- `WebSocketStreamer.swift` - Add reconnect cap

**Validation:**
- Unit: Test timeout scenarios with mocked delays
- Manual: Disconnect network mid-session, verify recovery

---

### PR 5: Reconnect Session Continuity (MEDIUM IMPACT)
**Impact:** MEDIUM - Fixes reconnect data loss  
**Effort:** MEDIUM - Session state persistence  
**Risk:** MEDIUM - Complex state handling  

**Files:**
- `WebSocketStreamer.swift` - Re-send start on reconnect
- `ws_live_listener.py` - Accept existing session_id for resume
- `AppState.swift` - Track partial transcript for resume

**Validation:**
- Integration: Test WS drop→reconnect→continue flow
- Manual: Kill/restart server mid-session

---

### PR 6: Stop Flow Idempotency (LOW IMPACT)
**Impact:** LOW - Edge case handling  
**Effort:** SMALL - State tracking  
**Risk:** LOW - Defensive  

**Files:**
- `ws_live_listener.py` - Track "stopped" state, handle duplicate stops
- `AppState.swift` - Ensure stop timeout bounded

**Validation:**
- Unit: Test multiple stop messages
- Integration: Rapid start/stop/start sequence

---

## Summary

**Current State:** The EchoPanel streaming system has functional gaps in its contract that allow "UI lies" - showing the user that the system is listening when it may not be processing audio.

**Key Issues:**
1. No correlation IDs - can't track request/response pairs
2. Server claims "streaming" before ASR is ready
3. Client timeout races can orphan tasks
4. Reconnect doesn't re-establish session context
5. No metrics staleness detection

**Proposed V1 Contract:**
- Adds `attempt_id` correlation to all messages
- Introduces explicit `session_ack` before streaming
- Defines strict state machine transitions
- Adds timeouts for all operations
- Surfaces backend health via metrics

**Implementation Path:**
6 PRs from foundational (correlation IDs) to polish (stop idempotency), totaling approximately 2-3 weeks of work for one engineer.

---

## I) Next Steps (Prioritized by Impact)

### Immediate (P0 - Critical Reliability):
1. **Complete PR 1 (attempt_id validation):** Add validation in WebSocketStreamer.swift:305-312 to reject messages with mismatched attempt_id
2. **Implement PR 2 (session_ack):** Add session_ack message to protocol and modify both client and server

### High Priority (P1):
3. **Implement PR 3 (ASR readiness check):** Add is_ready() method to ASR providers and only send streaming after confirmed ready
4. **Implement PR 4 (metrics staleness):** Add 5s timeout check in metrics handler, alert if no updates

### Medium Priority (P2):
5. **Complete PR 5 (session resume):** Add server-side session resume logic for reconnect
6. **Implement PR 6 (stop idempotency):** Add state tracking for duplicate stop messages

### Suggested Work Order:
- Week 1: Complete PR 1 + PR 2 (foundational contract fixes)
- Week 2: Implement PR 3 + PR 4 (reliability hardening)
- Week 3: Complete PR 5 + PR 6 (edge case handling)
