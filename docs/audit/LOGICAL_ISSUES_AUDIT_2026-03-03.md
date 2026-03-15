# EchoPanel Logical Issues Audit

**Date:** 2026-03-03  
**Scope:** Full codebase (server/ + macapp/)  
**Auditor:** AI Agent  
**Status:** COMPLETE

---

## Executive Summary

This audit identifies **14 logical issues** across the EchoPanel codebase, categorized by severity:

| Severity | Count | Description |
|----------|-------|-------------|
| **HIGH** | 3 | Race conditions, resource leaks, potential crashes |
| **MEDIUM** | 7 | Logic errors, inconsistent state handling, performance issues |
| **LOW** | 4 | Code quality, redundant operations, minor edge cases |

---

## HIGH Severity Issues

### 1. Race Condition in WebSocketStreamer sendQueue (Swift)

**Location:** `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift:581-626`

**Issue:** The `sendQueue.operationCount` check and `sendQueue.addOperation` are not atomic. Between checking the count and adding an operation, another thread could add an operation, causing the queue to exceed `maxQueuedSends`.

```swift
// Line 581-590
// Vulnerable code:
guard sendQueue.operationCount < maxQueuedSends else {  // Check
    // ... log warning
    return
}
// Another thread could add operation here!
sendQueue.addOperation { [weak self] in  // Add
    // ...
}
```

**Impact:** Queue could grow beyond intended bounds, causing memory pressure during network stalls.

**Fix:** Use a dedicated serial queue for queue management or NSLock around the check-and-add operation.

---

### 2. Missing Lock in ConcurrencyController._dropped_frames_recent Reset

**Location:** `server/services/concurrency_controller.py:340-344`

**Issue:** The `_dropped_frames_recent` counter reset in `get_metrics()` is not protected by a lock, but is modified by `submit_chunk()` which also isn't fully synchronized for this counter.

```python
# Line 340-344
def get_metrics(self) -> ConcurrencyMetrics:
    now = time.time()
    if now - self._last_metrics_reset > 10:
        self._dropped_frames_recent = 0  # No lock protection!
        self._last_metrics_reset = now
```

**Impact:** Race condition could cause incorrect metrics reporting or lost drop counts.

**Fix:** Add proper locking around metrics state mutations.

---

### 3. Improper Asyncio Lock Usage in RateLimiter.get_remaining

**Location:** `server/api/rate_limiter.py:123-139`

**Issue:** `get_remaining()` accesses `self._clients` without acquiring the lock, but `acquire()` modifies this dict under lock protection.

```python
# Line 123-139
def get_remaining(self, client_id: str) -> Dict[str, int]:
    # No lock acquired here!
    state = self._clients.get(client_id)  # Concurrent with acquire()'s modifications
    if not state:
        return {"minute": self.config.requests_per_minute, "hour": self.config.requests_per_hour}
    
    return {
        "minute": int(state.minute_tokens),  # May see inconsistent state
        "hour": int(state.hour_tokens)
    }
```

**Impact:** May read inconsistent token state during concurrent updates.

**Fix:** Acquire `self._lock` when reading client state.

---

## MEDIUM Severity Issues

### 4. Analysis Loop Timing Bug

**Location:** `server/api/ws_live_listener.py:956-1028`

**Issue:** The analysis loop has incorrect sleep logic. After entity analysis at `ENTITY_INTERVAL` (12s), it sleeps another `CARD_INTERVAL` (28s) before card analysis, making the actual interval between entity analyses 40s, not 12s.

```python
# Line 969-971, 994-995
while True:
    await asyncio.sleep(ENTITY_INTERVAL)  # Sleep 12s
    # ... entity analysis ...
    
    await asyncio.sleep(CARD_INTERVAL)    # Sleep ANOTHER 28s
    # ... card analysis ...
```

**Impact:** Entity analysis runs much less frequently than intended (every 40s instead of 12s).

**Fix:** Use independent timers or track last run times separately.

---

### 5. Voice Note ASR Type Mismatch

**Location:** `server/api/ws_live_listener.py:1076`

**Issue:** `_transcribe_voice_note` calls `stream_asr()` with `config` as second argument, but `stream_asr()` expects `sample_rate` as the second positional argument.

```python
# Line 1076 - BUG
current code:
async for result in stream_asr(audio_stream(), config, sample_rate=SAMPLE_RATE):

# stream_asr signature (line 43-46 in asr_stream.py):
async def stream_asr(
    pcm_stream: AsyncIterator[bytes],
    sample_rate: int = 16000,      # <- This is position 2!
    source: Optional[str] = None,
) -> AsyncIterator[dict]:
```

**Impact:** Voice note transcription likely fails or produces incorrect results.

**Fix:** Remove `config` argument or pass it correctly:
```python
async for result in stream_asr(audio_stream(), sample_rate=SAMPLE_RATE):
```

---

### 6. BackendManager.healthCheckTimer Double-Invalidation

**Location:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:344-345`

**Issue:** When server becomes ready, the health check timer is invalidated but the reference is not immediately nil'd, and the timer callback could still be in flight on another thread.

```swift
// Line 344-345
self.healthCheckTimer?.invalidate()
self.healthCheckTimer = nil  // Race: callback may still execute
```

**Impact:** Potential race where health check callback executes after timer invalidation.

**Fix:** Use a flag or more robust cancellation pattern.

---

### 7. ASRProviderRegistry.available_providers Creates Unnecessary Instances

**Location:** `server/services/asr_providers.py:404-415`

**Issue:** `available_providers()` creates new provider instances just to check availability, which is expensive for providers that may load models or initialize heavy resources.

```python
# Lines 404-415
@classmethod
def available_providers(cls) -> List[str]:
    result = []
    for name, provider_class in cls._providers.items():
        try:
            instance = provider_class(ASRConfig())  # Creates instance every call!
            if instance.is_available:
                result.append(name)
        except Exception:
            pass
    return result
```

**Impact:** Unnecessary resource consumption every time this method is called.

**Fix:** Cache availability results or use lightweight class-level checks.

---

### 8. DegradeLadder Recovery Logic Bug

**Location:** `server/services/degrade_ladder.py:275-327`

**Issue:** Recovery only happens if `target_level < self.state.level`, but when RTF improves gradually, the target level might equal the current level, preventing recovery.

```python
# Line 225-229
elif target_level < self.state.level:  # Strictly less than
    return await self._maybe_recover(target_level)
```

Also, `_maybe_recover` checks `if now - self.state.last_recovery_check < self.RECOVERY_WINDOW_S` which prevents recovery checks for 30s even if RTF has been good for a long time.

**Impact:** System may stay in degraded state longer than necessary.

**Fix:** Consider recovery even when target_level equals current level based on sustained good performance.

---

### 9. CircuitBreaker Timer No-Op

**Location:** `macapp/MeetingListenerApp/Sources/CircuitBreaker.swift:193-200`

**Issue:** The half-open timer schedules a Task that does nothing. The actual half-open transition only happens in `canExecute()`.

```swift
// Line 193-200
halfOpenTimer = Timer.scheduledTimer(withTimeInterval: resetTimeout, repeats: false) { _ in
    Task { @MainActor in
        // Timer just marks that we can try half-open next time
        // Actual transition happens in canExecute()
    }
}
```

**Impact:** Confusing code - timer exists but serves no purpose. Transition only happens lazily on next `canExecute()` call.

**Fix:** Either remove the timer or implement proactive state transition.

---

### 10. AudioCaptureManager CPU Usage Calculation is Incorrect

**Location:** `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift:238-246`

**Issue:** The CPU usage calculation uses `systemUptime` incorrectly - it's not actual CPU usage percentage.

```swift
// Line 240
cpuUsage = (processInfo.systemUptime.truncatingRemainder(dividingBy: 60)) / 60.0 * 100.0
```

This calculates a value based on uptime modulo 60, not actual CPU utilization.

**Impact:** VAD may be incorrectly disabled based on false CPU load detection.

**Fix:** Use actual CPU measurement APIs or remove this check.

---

## LOW Severity Issues

### 11. Redundant State Check in ModelManager.initialize

**Location:** `server/services/model_preloader.py:166-178`

**Issue:** The logic for `should_wait_for_existing_load` is convoluted - it sets the flag inside the lock but then checks it outside with inverted logic.

```python
# Lines 166-191
async with self._lock:
    if self._state == ModelState.READY:
        return True
    if self._state in {ModelState.LOADING, ModelState.WARMING_UP}:
        should_wait_for_existing_load = True  # Set to True
    # ...
    if should_wait_for_existing_load:
        pass  # Do nothing special?
    else:
        # Actually initialize
```

**Impact:** Code is confusing but functionally correct.

**Fix:** Simplify the logic flow.

---

### 12. WebSocketStreamer receiveLoop Retains Cycle Risk

**Location:** `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift:700-710`

**Issue:** The receiveLoop uses `[weak self]` but then immediately strongifies it in the switch cases without checking.

```swift
// Line 701-710
private func receiveLoop() {
    task?.receive { [weak self] result in
        guard let self else { return }  // Good
        switch result {
        case .success(let message):
            self.handle(message)  // self is strong now
            self.receiveLoop()    // Recursive call - potential stack growth
        // ...
        }
    }
}
```

While the strong reference is fine here, recursive calls through async callbacks could theoretically cause stack issues with rapid messages (though unlikely in practice).

**Impact:** Minor - theoretical concern only.

**Fix:** Use iterative pattern instead of recursive if concerned.

---

### 13. SessionState dataclass Uses Mutable Default Arguments

**Location:** `server/api/ws_live_listener.py:67-134`

**Issue:** While the code correctly uses `field(default_factory=...)` for most mutable fields, some type annotations suggest potential mutability issues:

```python
# Lines 98-100
asr_processing_times: list[float] = field(default_factory=list)
asr_samples_by_source: Dict[str, list[tuple[float, float]]] = field(default_factory=dict)
```

The inner lists in `asr_samples_by_source` are created dynamically, which is correct, but this pattern is error-prone.

**Impact:** Currently safe but fragile pattern.

**Fix:** Document carefully or use immutable types where possible.

---

### 14. put_audio Dropping Logic Doesn't Account for Chunk Size

**Location:** `server/api/ws_live_listener.py:754-848`

**Issue:** The byte-based backpressure in `put_audio` drops oldest chunks until there's room, but if a single chunk is larger than `QUEUE_MAX_BYTES`, it will drop all existing chunks and still fail to enqueue.

```python
# Line 799
while current_bytes + chunk_bytes > QUEUE_MAX_BYTES and not q.empty():
    # Drop oldest chunks...

# Line 811-817
try:
    q.put_nowait(chunk)  # May still fail!
except asyncio.QueueFull:
    dropped_count += 1
```

**Impact:** Single very large audio chunk could cause total buffer loss.

**Fix:** Handle the case where a single chunk exceeds max size.

---

## Recommendations Summary

| Priority | Issue | Effort | Risk |
|----------|-------|--------|------|
| P0 | Fix sendQueue race condition (HIGH-1) | Low | Low |
| P0 | Fix Voice Note ASR type mismatch (MED-5) | Low | Low |
| P1 | Add locks to ConcurrencyController metrics (HIGH-2) | Low | Low |
| P1 | Fix RateLimiter lock in get_remaining (HIGH-3) | Low | Low |
| P1 | Fix Analysis Loop timing (MED-4) | Medium | Low |
| P2 | Fix CPU usage calculation (MED-10) | Low | Low |
| P2 | Fix DegradeLadder recovery logic (MED-8) | Medium | Medium |
| P2 | Optimize ASRProviderRegistry.available_providers (MED-7) | Medium | Low |
| P3 | Clean up CircuitBreaker timer (MED-9) | Low | Low |
| P3 | Fix BackendManager timer race (MED-6) | Medium | Low |
| P3 | Handle oversized chunks in put_audio (LOW-14) | Low | Low |

---

## Files with Most Issues

1. `server/api/ws_live_listener.py` - 4 issues (MED-5, LOW-13, LOW-14, plus implicit in MED-4)
2. `server/services/concurrency_controller.py` - 1 issue (HIGH-2)
3. `server/api/rate_limiter.py` - 1 issue (HIGH-3)
4. `server/services/degrade_ladder.py` - 1 issue (MED-8)
5. `server/services/asr_providers.py` - 1 issue (MED-7)
6. `server/services/model_preloader.py` - 1 issue (LOW-11)
7. `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` - 2 issues (HIGH-1, LOW-12)
8. `macapp/MeetingListenerApp/Sources/BackendManager.swift` - 1 issue (MED-6)
9. `macapp/MeetingListenerApp/Sources/CircuitBreaker.swift` - 1 issue (MED-9)
10. `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` - 1 issue (MED-10)

---

## Verification Commands

```bash
# Run Swift tests
cd macapp/MeetingListenerApp && swift test

# Run Python tests
.venv/bin/pytest tests/ -v

# Type check Python
.venv/bin/mypy server/ --ignore-missing-imports

# Lint Python
.venv/bin/ruff check server/
```

---

*End of Audit*
