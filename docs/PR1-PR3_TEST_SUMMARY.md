# PR1-PR3 Test Summary

**Date:** 2026-02-11  
**Scope:** UI Handshake, Server Metrics, VAD Default On

## Test Results

### Python Backend Tests
```
23 passed, 3 warnings in 1.32s
```

**Test Coverage:**
- `test_ws_live_listener.py` - WebSocket lifecycle with handshake flow
- `test_ws_integration.py` - Auth, source-tagged audio, diarization
- `test_streaming_correctness.py` - Transcript ordering, diarization merge, queue config

### Swift Frontend Tests
```
Executed 20 tests, with 0 failures (0 unexpected)
```

**Test Suites:**
| Suite | Tests | Status |
|-------|-------|--------|
| BackendRecoveryUXTests | 1 | ✅ |
| SidePanelContractsTests | 5 | ✅ |
| SidePanelPerformanceTests | 2 | ✅ |
| SidePanelVisualSnapshotTests | 6 | ✅ |
| StreamingVisualTests | 6 | ✅ |

## Implementation Verification

### PR1: UI Handshake + Truthful States ✅
**Evidence:** `BackendRecoveryUXTests.testBackendUXStateTransitions`
- State transitions: `idle` → `starting` (blue) → `listening` (green)
- 5-second timeout for backend ACK
- `startAttemptId` properly ignores late messages

### PR2: Server Metrics ✅
**Evidence:** `test_ws_live_listener.py::test_ws_live_listener_start_stop`
- Server emits 1Hz metrics after "streaming" status
- Correct handshake: "connected" → "streaming" only after start message
- Metrics include queue_depth, queue_fill_ratio, dropped frames, realtime_factor

### PR3: VAD Default On ✅
**Evidence:** `server/services/asr_stream.py` configuration
- Default `ECHOPANEL_ASR_VAD=1` (was 0)
- Chunk size reduced 4s→2s for lower latency
- `vad_filter.py` stub created for future Silero VAD integration

## What Changed

### Behavior Changes (Expected)
1. **Status pill now shows "Starting..." first** - Previously showed "Listening" immediately
2. **Visual snapshots updated** - 6 snapshots regenerated to reflect new UI state

### Bug Fixes
1. `DesignTokens.swift` - Fixed `Int`→`Double` for `SortPriority` (was blocking build)
2. `SidePanelContractsTests.swift` - Fixed `Color`→`NSColor` conversion for contrast test

## Regression Check

| Area | Status | Evidence |
|------|--------|----------|
| Core ASR streaming | ✅ Pass | All Python tests pass |
| WebSocket protocol | ✅ Pass | Handshake + auth tests pass |
| Side panel UI | ✅ Pass | Snapshot tests pass |
| Performance | ✅ Pass | Layout perf tests pass |
| Color contrast | ✅ Pass | WCAG AA badge test passes (~5.2:1) |

## Commands Used

```bash
# Python tests
.venv/bin/python -m pytest tests/ -v

# Swift tests
cd macapp/MeetingListenerApp && swift test

# Update snapshots (done)
RECORD_SNAPSHOTS=1 swift test --filter SidePanelVisual
```

## Notes

- All snapshot diffs are intentional - they reflect the new "Starting..." state
- The contrast test now passes with black text on orange (~5.2:1 ratio)
- No functional regressions detected
