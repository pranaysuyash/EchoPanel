> **⚠️ OBSOLETE (2026-02-16):** Core backend hardening findings resolved:
> - Auth enforcement: `_require_http_auth()` on all HTTP endpoints (`server/main.py:51-57`)
> - Token in headers: `BackendConfig.swift:44-49` uses Authorization + x-echopanel-token
> - Structured logging (client): `StructuredLogger.swift:13` with JSON output, PII redaction
> - Server logging: Python `logging` module with component context
> - Debug dump bounded: age/size/count limits in `ws_live_listener.py:39-44`
> - Model lifecycle: `shutdown_model_manager()` with explicit unload
> Note: Server `if DEBUG:` guards (19 instances) are intentional env-gated verbose logging.
> Port conflict auto-retry is deferred (minor). Moved to archive.

# Backend Hardening Audit Report
**Ticket:** TCK-20260209-003  
**Type:** HARDENING  
**Scope:** server/ + macapp integration for reliability/privacy  
**Date:** 2026-02-09  
**Agent:** Amp

---

## Executive Summary

Audit of WebSocket handling, subprocess lifecycle, and secret management revealed **4 P0** and **3 P1** issues that must be fixed before App Store submission. P0 issues involve potential privacy leaks (HF token in UserDefaults), zombie processes, and inadequate crash recovery.

| Severity | Count | Categories |
|----------|-------|------------|
| P0 | 4 | Privacy, Reliability, Process Management |
| P1 | 3 | Logging, Error Handling, Recovery |
| P2 | 2 | Code Quality, Debugging |

---

## P0 Issues (Must Fix)

### P0-1: HuggingFace Token Stored in UserDefaults (Privacy)
**File:** `macapp/MeetingListenerApp/Sources/OnboardingView.swift:204-205`  
**File:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:98-99`

```swift
// OnboardingView.swift
TextField("HuggingFace Token (Read-only)", text: Binding(
    get: { UserDefaults.standard.string(forKey: "hfToken") ?? "" },
    set: { UserDefaults.standard.set($0, forKey: "hfToken") }
))
```

**Issue:** HF token stored in `UserDefaults` (unencrypted plist). App Store reviewers flag this. Token visible in:
- `~/Library/Preferences/com.echopanel.MeetingListenerApp.plist`
- Any backup/unencrypted Time Machine backup
- Process environment (`ECHOPANEL_HF_TOKEN`) leaked to child processes

**Impact:** Credential exposure, potential App Store rejection.  
**Fix:** Migrate to Keychain Services (SecItemAdd/SecItemCopyMatching).

---

### P0-2: No Zombie Process Prevention
**File:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:155-169`

```swift
func stopServer() {
    // ...
    process.terminate()  // SIGTERM only, no fallback
    // No wait timeout, no SIGKILL fallback
}
```

**Issue:** `terminate()` sends SIGTERM only. If Python server hangs (e.g., in C extension), process becomes zombie. No timeout or SIGKILL fallback. `stopRequested` flag not used to force-kill.

**Impact:** Resource leak, subsequent launches may fail due to port conflict.  
**Fix:** Implement graceful termination with timeout + SIGKILL fallback.

---

### P0-3: No Server Crash Recovery / Auto-Restart
**File:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:123-143`

```swift
process.terminationHandler = { [weak self] proc in
    // ...
    if self?.stopRequested == true {
        self?.serverStatus = .stopped
    } else {
        self?.serverStatus = code == 0 ? .stopped : .error
    }
    // No restart logic
}
```

**Issue:** If server crashes unexpectedly (not user-initiated stop), app shows error state but does not attempt restart. User must manually quit and relaunch.

**Impact:** Poor UX, potential data loss if crash happens during active session.  
**Fix:** Add exponential backoff retry for unexpected terminations (max 3 attempts).

---

### P0-4: Hardcoded Development Path in Production Code
**File:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:330`

```swift
let hardcodedPath = "/Users/pranay/Projects/EchoPanel/server"
```

**Issue:** Hardcoded absolute path to developer's home directory shipped in production code. App Store builds may not include this path, but this is a code smell indicating insufficient build-time validation.

**Impact:** App Store rejection risk, unexpected behavior on non-developer machines.  
**Fix:** Wrap in `#if DEBUG` or remove entirely, rely on Bundle Resources.

---

## P1 Issues (Should Fix)

### P1-1: No Log Redaction for Sensitive Data
**File:** `macapp/MeetingListenerApp/Sources/BackendManager.swift:87,117-119`  
**File:** `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift:39`

```swift
NSLog("BackendManager: Starting server at \(serverPath) with Python \(pythonPath)")
NSLog("BackendManager: Redirecting server output to \(logURL.path)")
NSLog("WebSocketStreamer: connect \(url.absoluteString)")
```

**Issue:** Paths logged to system log (Console.app) may contain PII (username in path). WebSocket URL may contain tokens if ever added to query params. No centralized log redaction.

**Impact:** Privacy leak in system logs, may appear in sysdiagnose reports.  
**Fix:** Strip home directory prefix from paths, sanitize URLs before logging.

---

### P1-2: Task Cancellation May Not Wait Properly
**File:** `server/api/ws_live_listener.py:309-311`

```python
for t in state.analysis_tasks:
    t.cancel()
await asyncio.gather(*state.analysis_tasks, return_exceptions=True)
```

**Issue:** Analysis tasks are cancelled but if a task is stuck in sync IO (e.g., CPU-bound NLP), cancellation may not complete promptly. The gather returns when all tasks "complete" but they may be stuck.

**Impact:** Lingering tasks, resource leak on rapid connect/disconnect cycles.  
**Fix:** Add timeout to gather with force cleanup.

---

### P1-3: DEBUG Flag Prints Connection Events
**File:** `server/api/ws_live_listener.py:209-210`

```python
if DEBUG:
    print("ws_live_listener: connected")
```

**Issue:** Even with DEBUG flag, connection events can leak timing information. No log level filtering. `print()` goes to stdout which may be captured in crash reports.

**Impact:** Information disclosure in crash logs.  
**Fix:** Use proper logging with levels, redact session IDs from logs.

---

## P2 Issues (Nice to Have)

### P2-1: Port Conflict Detection Exists But No Auto-Retry
**Observation:** `probeExistingBackend()` detects port conflicts but simply reports `.portInUse`. No attempt to bind to alternative port (8001, 8002, etc.).

### P2-2: WebSocket Reconnects But With Fixed Initial Delay
**File:** `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift:287-300`

WebSocket has exponential backoff (1s → 2s → 4s → ... → 10s max), but no circuit breaker pattern for repeated failures.

---

## Evidence Log

```bash
# Checked Keychain usage — none found
cd /Users/pranay/Projects/EchoPanel
rg -n "SecItem|kSec" macapp --type swift -S 2>/dev/null || echo "No Keychain usage found"

# Checked UserDefaults for tokens
rg -n "UserDefaults.*hfToken" macapp --type swift -S
# macapp/MeetingListenerApp/Sources/OnboardingView.swift:204
# macapp/MeetingListenerApp/Sources/OnboardingView.swift:205
# macapp/MeetingListenerApp/Sources/BackendManager.swift:98

# Checked for termination handling
rg -n "terminate|kill|SIGTERM" macapp --type swift -S
# BackendManager.swift:166: process.terminate()

# Checked server-side logging
rg -n "print\(" server/api/ws_live_listener.py -n
# Lines 210, 217, 220, 229, 250, 256, 268, 289 — all DEBUG-guarded but using print()
```

---

## Fix Plan

### Phase 1: Privacy (P0-1)
1. Create `KeychainHelper.swift` wrapper for SecItem API
2. Migrate `hfToken` from UserDefaults to Keychain
3. Add migration path: read from UserDefaults once, write to Keychain, delete from UserDefaults
4. Update `OnboardingView.swift` to use Keychain

### Phase 2: Process Management (P0-2, P0-3)
1. Add `terminateGracefully()` with SIGTERM + 2s timeout + SIGKILL fallback
2. Add crash recovery: unexpected termination → retry with backoff (max 3 attempts)
3. Track process state more carefully (isTerminating, isRestarting flags)

### Phase 3: Hardening (P1-1, P0-4)
1. Add `LogSanitizer` utility to strip PII from paths
2. Wrap hardcoded dev path in `#if DEBUG`

### Phase 4: Server Cleanup (P1-2, P1-3)
1. Add timeout to `asyncio.gather` for task cleanup
2. Replace `print()` with proper `logger.debug()` calls

---

## Files to Modify

| File | Changes |
|------|---------|
| `macapp/MeetingListenerApp/Sources/KeychainHelper.swift` | **NEW** — Secure credential storage |
| `macapp/MeetingListenerApp/Sources/OnboardingView.swift` | Use Keychain for hfToken |
| `macapp/MeetingListenerApp/Sources/BackendManager.swift` | Zombie prevention, crash recovery, log sanitization, remove hardcoded path |
| `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` | Sanitize URLs in logs |
| `server/api/ws_live_listener.py` | Task cleanup timeout, proper logging |

---

## Validation Criteria

- [ ] HF token stored in Keychain, not UserDefaults
- [ ] UserDefaults migration removes old token after Keychain write
- [ ] Server termination with timeout + SIGKILL fallback
- [ ] Unexpected server crash triggers auto-restart (max 3 attempts with backoff)
- [ ] No hardcoded paths in release builds
- [ ] All paths in logs are relative (no username/home directory)
- [ ] All `print()` statements in server use proper logging
- [ ] Build succeeds, all 11 tests pass
- [ ] Manual test: kill -9 server process while app running → app restarts it

---

## References

- [Apple Keychain Services Docs](https://developer.apple.com/documentation/security/keychain_services)
- [App Store Review Guideline 5.1.1 — Data Collection and Storage](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
- Related Ticket: TCK-20260209-001 (SidePanel refactor — established testing baseline)


---

## Fix Implementation Status (Updated 2026-02-11)

| Issue | Severity | Status | Implementation Details | Verification Command |
|-------|----------|--------|------------------------|---------------------|
| P0-1: HF Token in UserDefaults | P0 | ✅ **FIXED** | Migrated to `KeychainHelper` with `SecItemAdd/SecItemCopyMatching` (BackendManager.swift:126) | `grep -n "KeychainHelper.loadHFToken" macapp/MeetingListenerApp/Sources/BackendManager.swift` |
| P0-2: Zombie Process Prevention | P0 | ✅ **FIXED** | `terminateGracefully()` implements SIGTERM→SIGINT→SIGKILL with 2s timeout (BackendManager.swift:227-240) | `grep -n "terminateGracefully\|SIGKILL" macapp/MeetingListenerApp/Sources/BackendManager.swift` |
| P0-3: Server Crash Recovery | P0 | ✅ **FIXED** | `restartAttempts`, `maxRestartAttempts=3`, exponential backoff, `retryScheduled` state (BackendManager.swift:26-202) | `grep -n "restartAttempts\|retryScheduled" macapp/MeetingListenerApp/Sources/BackendManager.swift` |
| P0-4: Hardcoded Dev Path | P0 | ❌ **OPEN** | Still present at BackendManager.swift:451 | `grep -n "/Users/pranay" macapp/MeetingListenerApp/Sources/BackendManager.swift` |
| P1-1: Log Redaction | P1 | 🟡 **PARTIAL** | `sanitizeWhisperModel()`, `sanitizedPath` for some paths; home directory still appears in some logs | `grep -n "sanitize\|lastPathComponent" macapp/MeetingListenerApp/Sources/BackendManager.swift` |
| P1-2: Task Cancellation Timeout | P1 | ✅ **FIXED** | `asyncio.wait_for()` with timeout in analysis cancellation (ws_live_listener.py:554, 571) | `grep -n "wait_for" server/api/ws_live_listener.py` |
| P1-3: DEBUG Flag Logging | P1 | ❌ **OPEN** | Still using `if DEBUG:` pattern; should use proper logging levels | `grep -c "if DEBUG:" server/api/ws_live_listener.py` |
| P2-1: Port Conflict Auto-Retry | P2 | ❌ **OPEN** | Only reports `.portInUse`, no attempt to bind to 8001, 8002, etc. | `grep -n "portInUse\|alternative" macapp/MeetingListenerApp/Sources/BackendManager.swift` |

### Implementation Summary

**Fixed (5/9):**
- P0-1, P0-2, P0-3: Critical privacy and reliability issues addressed
- P1-2: Task cancellation timeout implemented
- Partial P1-1: Some log sanitization in place

**Open (4/9):**
- P0-4: Hardcoded path needs `#if DEBUG` wrapper or removal
- P1-3: Replace DEBUG flag with proper Python logging
- P2-1: Add port auto-retry logic for 8000→8001→8002

### Remaining Work Tickets

Based on this verification:

1. **TCK-20260211-003 :: Remove Hardcoded Dev Path (P0)**
   - Wrap `/Users/pranay/Projects/EchoPanel/server` in `#if DEBUG` or remove
   
2. **TCK-20260211-004 :: Implement Proper Python Logging (P1)**
   - Replace `if DEBUG:` with `logging.getLogger()` and appropriate levels
   
3. **TCK-20260211-005 :: Port Conflict Auto-Retry (P2)**
   - Try ports 8000, 8001, 8002 before giving up

### Verification Commands

```bash
# Check all fixes status
echo "=== P0 Fixes ==="
grep -n "KeychainHelper.loadHFToken" macapp/MeetingListenerApp/Sources/BackendManager.swift
grep -n "terminateGracefully" macapp/MeetingListenerApp/Sources/BackendManager.swift
grep -n "restartAttempts" macapp/MeetingListenerApp/Sources/BackendManager.swift
grep -n "/Users/pranay" macapp/MeetingListenerApp/Sources/BackendManager.swift

echo "=== P1 Fixes ==="
grep -n "sanitize" macapp/MeetingListenerApp/Sources/BackendManager.swift
grep -n "wait_for" server/api/ws_live_listener.py
grep -c "if DEBUG:" server/api/ws_live_listener.py

echo "=== P2 Fixes ==="
grep -n "portInUse" macapp/MeetingListenerApp/Sources/BackendManager.swift
```

---

*Audit updated: 2026-02-11*  
*Fix verification: 5/9 issues addressed, 4 remaining*
