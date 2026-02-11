# Audio Pipeline Hardening — Implementation Plan

**Derived from**: TCK-20260211-004 Audio Industry Code Review  
**Author**: Agent Amp  
**Date**: 2026-02-11  
**Status**: Phase 1 Planned, Awaiting Approval

---

## Executive Summary

The audio industry code review (TCK-20260211-004) identified **3 P0 critical issues**, **3 P1 high-priority issues**, and several P2/P3 improvements. This plan organizes fixes into **4 implementation phases** to address issues incrementally while maintaining system stability.

**Current Audio Quality Score**: 5/10 (dual-source), 6-7/10 (single-source)  
**Target Score**: 9/10 (all phases complete)

---

## Phase Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1 (P0)      PHASE 2 (P0)      PHASE 3 (P1)      PHASE 4 (P1)         │
│  Clipping Fix      Clock Drift       Client VAD        Bluetooth &         │
│  + Limiter         Compensation      Pre-filter        Device Handling      │
│                                                                              │
│  ┌─────────┐      ┌─────────┐       ┌─────────┐       ┌─────────┐          │
│  │ 🔴 P0-2 │  →   │ 🔴 P0-1 │   →   │ 🟡 P1-3 │   →   │ 🟡 P1-1 │          │
│  │ Limiter │      │ Drift   │       │ VAD     │       │ BT      │          │
│  └─────────┘      └─────────┘       └─────────┘       └─────────┘          │
│       │                │                 │                 │                │
│       ▼                ▼                 ▼                 ▼                │
│  ┌─────────┐      ┌─────────┐       ┌─────────┐       ┌─────────┐          │
│  │ Metrics │      │ Sync    │       │ 40% CPU │       │ Quality │          │
│  │ + Tests │      │ Buffer  │       │ Savings │       │ Alerts  │          │
│  └─────────┘      └─────────┘       └─────────┘       └─────────┘          │
│                                                                              │
│  Est: 1-2 days    Est: 3-5 days     Est: 2-3 days     Est: 2-3 days        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Clipping Fix + Limiter (P0-2)

**Ticket**: TCK-20260211-005  
**Priority**: P0 - Critical  
**Estimated Time**: 1-2 days  
**Risk**: Low (additive change, easy to revert)

### Problem
Hard clipping in `emitPCMFrames()` causes digital distortion:
```swift
let value = max(-1.0, min(1.0, samples[i]))  // Square-wave distortion!
```

### Solution
Add soft limiter with attack/release before conversion:
```swift
// Smooth gain reduction to -0.9 dBFS
let limitedSample = applyLimiter(sample)
let int16Value = Int16(limitedSample * Float(Int16.max))
```

### Implementation Steps

1. **Add Limiter State** (both managers)
   ```swift
   private var limiterGain: Float = 1.0
   private let limiterAttack: Float = 0.9
   private let limiterRelease: Float = 0.999
   private let limiterThreshold: Float = 0.9
   ```

2. **Implement applyLimiter()** (both managers)
   - Target: -0.9 dBFS headroom
   - Fast attack (0.9 coefficient)
   - Slow release (0.999 coefficient)
   - Return limited samples array

3. **Integrate into processAudio()**
   - Call `applyLimiter()` before `emitPCMFrames()`
   - Pass limited samples to `emitPCMFrames()`

4. **Add Metrics**
   - Track `limitingRatio` in `updateAudioQuality()`
   - Log when >10% limiting in debug builds

5. **Write Tests**
   - `testLimiterReducesPeaks()`: Verify 0 dBFS → -0.9 dBFS
   - `testLimiterPreservesQuiet()`: Verify -60 dBFS unchanged
   - `testLimiterAttackFast()`: Verify peaks caught immediately
   - `testLimiterReleaseSlow()`: Verify smooth return to unity

6. **Manual Testing**
   - Test with system audio at 100% volume
   - Test with microphone gain at maximum
   - Verify no audible distortion on loud speech
   - Run 1-hour meeting simulation

### Files Changed
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
- `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift`
- `macapp/MeetingListenerApp/Tests/AudioLimiterTests.swift` (new)

### Success Criteria
- [ ] No clipping on 0 dBFS sine wave test
- [ ] ASR accuracy maintained on loud audio
- [ ] Unit tests pass
- [ ] Manual test confirms no distortion

---

## Phase 2: Clock Drift Compensation (P0-1)

**Ticket**: TBD (create after Phase 1)  
**Priority**: P0 - Critical  
**Estimated Time**: 3-5 days  
**Risk**: Medium (changes timing architecture)

### Problem
System audio and microphone run on independent clocks. Over 1 hour, they drift 10-100ms apart, causing desynchronization.

### Solution
Implement drift-compensated mixing buffer with resampling.

### Implementation Steps

1. **Design Shared Timestamp Reference**
   - Use `CACurrentMediaTime()` (host time)
   - Map audio timestamps to common reference

2. **Create AudioRingBuffer Class**
   - Thread-safe ring buffer per source
   - Timestamp-indexed storage
   - Drift detection logic

3. **Implement Drift Detection**
   - Compare arrival rates of mic vs system
   - Calculate drift ratio (e.g., 1.0001x)
   - Trigger compensation when >5ms drift

4. **Add Resampling Compensation**
   - Use AVAudioConverter for micro-resampling
   - Adjust rate ±0.1% to compensate
   - Preserve audio quality

5. **Integrate into AppState**
   - Replace separate callbacks with synchronized mixer
   - Emit combined or separate streams with sync

6. **Write Tests**
   - `testDriftDetection()`: Verify 10ms drift caught
   - `testResamplingQuality()`: Verify no artifacts
   - `testLongTermSync()`: Verify 1-hour stability

### Files Changed
- `macapp/MeetingListenerApp/Sources/AudioRingBuffer.swift` (new)
- `macapp/MeetingListenerApp/Sources/AudioClockSynchronizer.swift` (new)
- `macapp/MeetingListenerApp/Sources/AppState.swift`
- `macapp/MeetingListenerApp/Tests/AudioSyncTests.swift` (new)

### Success Criteria
- [ ] Mic and system audio stay <10ms synchronized over 1 hour
- [ ] No audible pitch changes from resampling
- [ ] ASR quality maintained on both sources

---

## Phase 3: Client-Side VAD Pre-filter (P1-3)

**Ticket**: TBD (create after Phase 2)  
**Priority**: P1 - High  
**Estimated Time**: 2-3 days  
**Risk**: Low (additive, can disable)

### Problem
All audio sent to server, including silence (~40% of meeting time). Wastes compute and battery.

### Solution
Run Silero VAD on client, send only speech segments.

### Implementation Steps

1. **Add Silero VAD to Project**
   - Import onnxruntime-swift or use CoreML conversion
   - Bundle VAD model (~1MB)

2. **Create VADProcessor Class**
   - Buffer 30ms frames
   - Run inference every 30ms
   - Output speech/silence decisions

3. **Implement Frame Gating**
   - Accumulate PCM in buffer
   - Only send when VAD triggers
   - Send short silence buffer for context

4. **Add VAD Metrics**
   - Track speech ratio
   - Log bandwidth savings
   - Expose to UI for debugging

5. **Write Tests**
   - `testVADDetectsSpeech()`: Verify speech caught
   - `testVADFiltersSilence()`: Verify silence dropped
   - `testVADNoFalseNegatives()`: Verify no dropped speech

### Files Changed
- `macapp/MeetingListenerApp/Sources/VADProcessor.swift` (new)
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
- `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift`
- `macapp/MeetingListenerApp/Tests/VADTests.swift` (new)

### Success Criteria
- [ ] 30-40% reduction in bytes sent
- [ ] No speech segments dropped
- [ ] <5% CPU overhead from VAD

---

## Phase 4: Bluetooth & Device Handling (P1-1, P1-2)

**Ticket**: TBD (create after Phase 3)  
**Priority**: P1 - High  
**Estimated Time**: 2-3 days  
**Risk**: Low (defensive programming)

### Problems
1. Bluetooth audio adds latency and codec artifacts
2. Device changes (display, mic) not handled

### Solution
Detect conditions and adapt or warn.

### Implementation Steps

1. **Add Route Change Detection**
   - Observe `AVAudioEngineConfigurationChangeNotification`
   - Detect `AVAudioSessionRouteChangeNotification`
   - Log new device properties

2. **Implement Bluetooth Detection**
   - Check `AVAudioSession.currentRoute.inputs`
   - Detect BluetoothHFP vs BluetoothA2DP
   - Log codec and sample rate

3. **Add User Warnings**
   - Toast/notification: "Bluetooth detected - quality may be reduced"
   - Suggest wired mic for best ASR

4. **Handle Format Changes**
   - On route change, restart capture with new format
   - Validate sample rate matches expected
   - Log format mismatches

5. **Write Tests**
   - `testRouteChangeHandling()`: Verify restart on change
   - `testBluetoothDetection()`: Verify BT recognized
   - `testFormatValidation()`: Verify errors on mismatch

### Files Changed
- `macapp/MeetingListenerApp/Sources/AudioDeviceMonitor.swift` (new)
- `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift`
- `macapp/MeetingListenerApp/Sources/AppState.swift`

### Success Criteria
- [ ] Bluetooth usage detected and logged
- [ ] User warned about Bluetooth quality
- [ ] Device changes handled without crash
- [ ] Format changes logged

---

## Phase 5+: Future Improvements (P2-P3)

After core stability is achieved, consider:

| Feature | Benefit | Effort |
|---------|---------|--------|
| Binary WebSocket frames | 33% bandwidth reduction | 1 day |
| Echo Cancellation (AEC) | Remove system→mic bleed | 3-5 days |
| Noise Suppression (NS) | Cleaner ASR input | 2-3 days |
| Automatic Gain Control | Consistent levels | 2-3 days |
| Dithering on conversion | Better low-level quality | 1 day |

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-11 | Start with Phase 1 (clipping) | P0 issue, lowest risk, immediate ASR quality impact |
| 2026-02-11 | Defer clock drift to Phase 2 | Requires architecture changes, higher risk |
| 2026-02-11 | Use sample-based limiter | Simple, portable, no AVAudioUnit complexity |
| 2026-02-11 | Target -0.9 dBFS | Industry standard headroom, preserves dynamic range |

---

## Approval Checklist

Before starting Phase 1, confirm:

- [ ] Human (Pranay) approves scope and priority order
- [ ] Swift development environment available
- [ ] Unit test infrastructure ready
- [ ] Manual testing plan understood
- [ ] Rollback plan (git revert) confirmed

---

**Next Action**: Await human approval to begin Phase 1 implementation.
