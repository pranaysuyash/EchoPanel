# EchoPanel Broadcast Readiness Review
**Date:** 2026-02-11  
**Reviewer:** Technical Operations (Live Broadcast/Captioning)  
**Version:** v0.2 (post-hardening)  
**Scope:** macOS menu bar app with local Python backend

---

## Executive Summary

EchoPanel is a **meeting transcription tool** that has been hardened for reliability but remains **fundamentally unsuitable for live broadcast captioning** without substantial architectural changes. The current implementation targets internal meeting documentation, not real-time public transmission.

**Broadcast Readiness Score: 42/100**

---

## A) Broadcast Readiness Scorecard

### 1. Capture Layer

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Audio source redundancy | **FAIL** | `AudioCaptureManager.swift:60-77` only captures main display; no fallback for display failure |
| Sample rate flexibility | **PARTIAL** | Hardcoded 16kHz in `AudioCaptureManager.swift:18`; no runtime negotiation |
| Clipping detection | **PASS** | `AudioCaptureManager.swift:239-244` tracks clip ratio with EMA |
| Silence detection | **PASS** | `AudioCaptureManager.swift:242-243` silence threshold 0.01; `AppState.swift:736-748` alerts after 10s |
| Device switching mid-call | **FAIL** | `AudioCaptureManager.swift` has no hot-swap logic; `startCapture()` throws if no display |
| Audio clock stability | **UNKNOWN** | Uses `CACurrentMediaTime()` but no NTP sync or drift measurement |

**Score: 2.5/6**

### 2. Processing Layer

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Engine restart without UI kill | **PASS** | `BackendManager.swift:177-178` auto-restart with `maxRestartAttempts=3` |
| Dual-path (primary/backup ASR) | **FAIL** | `asr_stream.py:55-63` single provider only; no hot-standby |
| Real-time factor monitoring | **PASS** | `asr_providers.py:112-119` RTF tracking; `ws_live_listener.py:366-367` calculates |
| Model pre-loading | **FAIL** | `provider_faster_whisper.py:76-111` lazy-load on first `_get_model()` call |
| Backpressure handling | **PASS** | `ws_live_listener.py:254-281` queue drops + warnings to client |
| Graceful degradation | **PARTIAL** | `degrade_ladder.py` exists but not integrated into main flow |
| Concurrency limits | **FAIL** | `ws_live_listener.py:541` creates ASR task per source with no global limit |

**Score: 3.5/7**

### 3. Output Layer

| Criterion | Status | Evidence |
|-----------|--------|----------|
| SRT/VTT generation | **FAIL** | No subtitle format exports found; only JSON and Markdown |
| Word-level timestamps | **FAIL** | `TranscriptSegment` has t0/t1 only per segment; no word alignment |
| Speaker tagging | **PARTIAL** | `diarization.py:135-180` runs post-hoc at session end only |
| Caption burn-in | **FAIL** | No video pipeline; audio-only system |
| Sidecar output | **PARTIAL** | `AppState.swift:782-813` JSON/Markdown export only |
| Network output (UDP/RTP) | **FAIL** | HTTP/WebSocket only; no broadcast transport |

**Score: 0.5/6**

### 4. Timing & Sync

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Timestamp source | **PARTIAL** | `CACurrentMediaTime()` used; no NTP or PTP |
| Monotonic clock usage | **PARTIAL** | `Date()` for wall time; `CACurrentMediaTime()` for audio |
| Drift detection | **FAIL** | No drift measurement between audio and system clock |
| Timecode support | **FAIL** | No LTC/VITC/ATC support; no frame-accurate timestamps |
| Lip-sync alignment | **FAIL** | No video reference; impossible to verify |
| Backfill capability | **FAIL** | No audio buffer for reprocessing; queue drops oldest |

**Score: 1/6**

### 5. Monitoring & Observability

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Real-time level meters | **PASS** | `AppState.swift:108-109` publishes `systemAudioLevel`, `microphoneAudioLevel` |
| VAD activity indicator | **PARTIAL** | VAD runs internally but not exposed to UI |
| Buffer/latency display | **PASS** | `ws_live_listener.py:392-413` emits `queue_fill_ratio`, `backlog_seconds` |
| Dropped frame counter | **PASS** | `ws_live_listener.py:267-271` tracks `audio_frames_dropped` |
| ASR health metrics | **PASS** | `SourceMetrics` in `WebSocketStreamer.swift:4-19` includes `realtimeFactor` |
| Structured logging | **PASS** | `StructuredLogger.swift` with correlation IDs |
| Session bundles | **PASS** | `SessionBundle.swift` exports NDJSON metrics, events, transcripts |

**Score: 6/7**

### 6. Operator UX

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Hotkey controls | **FAIL** | No global hotkeys registered; menu bar only |
| Pause/resume | **FAIL** | `AppState.swift:636-691` only has start/stop; no pause |
| Manual speaker labels | **FAIL** | No UI for forcing speaker assignment |
| Quick language switch | **FAIL** | Requires backend restart for language change |
| Connection status | **PASS** | `WebSocketStreamer.swift:249-259` shows streaming/reconnecting/error |
| Source selection | **PASS** | `AppState.swift:107` supports system/mic/both |

**Score: 2/6**

### 7. Recovery & Resilience

| Criterion | Status | Evidence |
|-----------|--------|----------|
| WebSocket reconnection | **PASS** | `ResilientWebSocket.swift:396-468` exponential backoff + circuit breaker |
| Backend crash recovery | **PASS** | `BackendManager.swift:249-272` 3 attempts with exponential backoff |
| Message buffering | **PASS** | `ResilientWebSocket.swift:80-136` 1000 msg circular buffer |
| Session persistence | **PARTIAL** | `SessionStore.swift` auto-saves but no resume from crash |
| State machine robustness | **PARTIAL** | `AppState.swift:492-634` has gaps in error recovery paths |

**Score: 4/5**

### 8. Compliance & Security

| Criterion | Status | Evidence |
|-----------|--------|----------|
| PII redaction | **PARTIAL** | `SessionBundle.Configuration.privacySafe` excludes audio; no transcript redaction |
| Encryption at rest | **PARTIAL** | Keychain for tokens; temp files unencrypted |
| Audit trail | **PASS** | `SessionBundle.swift` records full event timeline |
| Retention policy | **FAIL** | No automatic cleanup; logs accumulate in `/tmp` |
| Air-gapped operation | **PASS** | Local model inference; no cloud dependency for ASR |
| Access controls | **PARTIAL** | `ws_live_listener.py:166-175` token auth optional |

**Score: 3/6**

---

## B) Critical Scenarios Playbook (10 Scenarios)

### Scenario 1: System Audio Device Changes Mid-Call

**What happens today:**
- `AudioCaptureManager.swift:55-82` captures from `CGMainDisplayID()` at start
- `SCStream` continues but may output silence if display changes
- No hot-swap detection or recovery logic

**What SHOULD happen (broadcast standard):**
- Continuous device enumeration
- Seamless failover to new default device
- Operator alert with option to accept/reject switch
- No audio gap > 50ms

**Changes needed:**
1. Add `SCShareableContent` observer for display changes
2. Implement `stopCapture()` → `startCapture()` with new display
3. Add ring buffer to bridge the gap (200ms)
4. UI notification with 5-second auto-accept

**Test approach:**
```bash
# Physical: Disconnect/reconnect HDMI during capture
# Simulated: Switch DisplayPort source on monitor
```

---

### Scenario 2: ASR Backend Stalls 5 Seconds

**What happens today:**
- `ws_live_listener.py:561-572` has 8-second flush timeout only
- No stall detection during streaming
- `ResilientWebSocket.swift:517-522` pong timeout at 15s catches dead connections
- Model inference blocks `asyncio.to_thread()`; no cancellation

**What SHOULD happen:**
- Per-chunk timeout (3x expected latency)
- Automatic failover to backup ASR provider
- Operator alert: "ASR stalled - switching to backup"
- Degraded mode with shorter chunks

**Changes needed:**
1. `provider_faster_whisper.py:165-174` wrap in `asyncio.wait_for()` with 10s timeout
2. Add `ASRProviderRegistry.get_backup_provider()` method
3. `AppState.swift` add "Degraded Mode" UI state
4. Auto-reduce `chunk_seconds` from 2s to 1s on stall

**Test approach:**
```python
# Inject sleep into _transcribe() to simulate 10s stall
# Verify: timeout triggers, warning emitted, session continues
```

---

### Scenario 3: Translation API Rate-Limits

**What happens today:**
- No translation layer exists in codebase
- `analysis_stream.py` only does keyword extraction

**What SHOULD happen (for broadcast):**
- Local translation model (argos-translate/CTranslate2)
- Rate-limit queue with priority (floor > interpreter > captions)
- Fallback to original language if translation fails

**Changes needed:**
1. Add `TranslationProvider` abstraction parallel to `ASRProvider`
2. Implement token bucket rate limiter
3. Add `priority` field to translation queue
4. UI language pair selector with "Auto" option

**Test approach:**
```python
# Mock translator with 1 req/sec limit
# Flood with 10 segments, verify queue depth warning
```

---

### Scenario 4: Long Silence Then Sudden Speech Burst

**What happens today:**
- `AppState.swift:736-748` detects 10s silence, shows warning
- VAD enabled by default (`asr_stream.py:32`)
- 2-second chunks may miss very short utterances
- `provider_faster_whisper.py:225-236` final chunk skipped if <0.5s

**What SHOULD happen:**
- Adaptive buffer sizing based on VAD state
- Pre-roll buffer to capture speech onset
- No dropped first words

**Changes needed:**
1. Implement 500ms pre-roll ring buffer
2. Reduce minimum chunk to 0.25s when VAD detects activity
3. Remove final chunk size filter or reduce to 0.25s
4. Add "speech detected" UI indicator

**Test approach:**
```bash
# Play test file: 15s silence + "Testing one two three"
# Verify: all three words transcribed, no truncation
```

---

### Scenario 5: Interpreter Joins Late

**What happens today:**
- Single language per session (`ECHOPANEL_WHISPER_LANGUAGE`)
- No per-source language configuration
- Diarization runs post-hoc, not real-time

**What SHOULD happen:**
- Per-source language detection
- Separate ASR streams per language
- Real-time language identification

**Changes needed:**
1. Add `language` field to audio frame metadata
2. Run language detection every 5 seconds per source
3. Spawn separate ASR task per detected language
4. Merge transcripts with language tags

**Test approach:**
```bash
# Start with English, inject Spanish at 30s mark
# Verify: transcript shows [ES] prefix, no garbage transcription
```

---

### Scenario 6: Two Speakers Overlap Continuously

**What happens today:**
- Single mixed stream from system audio
- Diarization runs at session end only
- `diarization.py:135-180` merges speakers post-hoc
- No real-time speaker separation

**What SHOULD happen:**
- Real-time speaker diarization (every 5s)
- Overlap detection and marking
- Separate caption tracks per speaker

**Changes needed:**
1. Move diarization to background thread every 5s
2. Stream partial diarization results
3. Add "overlapping speech" indicator in UI
4. Create per-speaker transcript streams

**Test approach:**
```bash
# Play two simultaneous audio files
# Verify: each speaker labeled, overlap marked with [OVERLAP]
```

---

### Scenario 7: Laptop Sleeps for 30 Seconds Mid-Session

**What happens today:**
- `ResilientWebSocket.swift:517-522` detects pong timeout after 15s
- `BackendManager.swift:177-178` will restart backend if terminated
- Audio capture stops; no gap filling on resume
- `AppState.swift` session continues but with gap

**What SHOULD happen:**
- Detect sleep via `NSWorkspace` notification
- Pause session marking "SLEEP GAP" in transcript
- On wake: verify backend health, resume or restart
- Option to "fill gap" if audio was buffered

**Changes needed:**
1. Add `NSWorkspace.didWakeNotification` observer
2. Implement session pause/resume state
3. Add gap markers to transcript
4. Buffer last 30s of audio for post-resume catch-up

**Test approach:**
```bash
# Close laptop lid during capture, reopen after 30s
# Verify: gap marker in transcript, session continues
```

---

### Scenario 8: CPU Overload Causes Processing Lag

**What happens today:**
- `ws_live_listener.py:392-413` emits `realtime_factor` every 1s
- `AppState.swift:299-305` shows backpressure warning if RTF > 1.0
- Queue drops frames at 95% fill (`ws_live_listener.py:373`)
- No automatic quality reduction

**What SHOULD happen:**
- Automatic degrade ladder: reduce model size → disable diarization → shorter chunks
- Operator override with explicit quality selection
- Alert: "CPU overload - reduced quality mode"

**Changes needed:**
1. Integrate `degrade_ladder.py` into main flow
2. Auto-switch to `tiny.en` model if RTF > 1.0 for 10s
3. Add CPU usage monitoring thread
4. UI button for manual quality override

**Test approach:**
```bash
# Run with CPU limit: `taskset -c 0` or throttle
# Verify: automatic model downgrade, warning shown
```

---

### Scenario 9: Permission Revoked Mid-Session

**What happens today:**
- `CGPreflightScreenCaptureAccess()` checked at start only
- `AppState.swift:541-548` stops session on denial
- No runtime permission monitoring

**What SHOULD happen:**
- Continuous permission monitoring
- Graceful degradation to microphone-only if screen recording revoked
- Immediate operator alert with recovery steps

**Changes needed:**
1. Poll `CGPreflightScreenCaptureAccess()` every 5s during capture
2. On revocation: switch to mic-only mode if available
3. Show prominent "Permission Lost" banner
4. One-click button to reopen System Settings

**Test approach:**
```bash
# Revoke permission in System Settings during capture
# Verify: app detects, switches to mic-only, shows banner
```

---

### Scenario 10: Output File Write Fails (Disk Full)

**What happens today:**
- `SessionBundle.swift:211-231` generates bundle in temp directory
- `AppState.swift:815-843` exports to user-selected location
- No disk space check before write
- Export fails silently or with generic error

**What SHOULD happen:**
- Pre-write disk space check
- Fallback to temp location with alert
- Compressed streaming output to stay under limit
- Alert: "Disk full - using compressed fallback"

**Changes needed:**
1. Check `NSURLVolumeAvailableCapacityForImportantUsageKey` before export
2. Add fallback export with gzip compression
3. Stream to output instead of buffering entire bundle
4. Estimated bundle size calculation

**Test approach:**
```bash
# Create small ramdisk, fill to 99%
# Attempt export, verify graceful fallback
```

---

## C) Code-Specific Issues List (P0–P3)

### P0 - Critical (Broadcast Blocking)

| ID | Issue | Location | Evidence | Fix |
|----|-------|----------|----------|-----|
| P0-1 | No subtitle format support | `AppState.swift:782-813` | Only JSON/Markdown export | Add SRT/VTT encoder with word-level timing |
| P0-2 | No real-time speaker diarization | `diarization.py:135-180` | Runs only at session end | Move to async loop every 5s during session |
| P0-3 | Hardcoded capture display | `AudioCaptureManager.swift:61-62` | `CGMainDisplayID()` only | Add display enumeration and failover |
| P0-4 | No per-chunk ASR timeout | `provider_faster_whisper.py:165-174` | `asyncio.to_thread()` unbounded | Wrap with `asyncio.wait_for(chunk_timeout)` |
| P0-5 | No backup ASR provider | `asr_stream.py:55-63` | Single provider selection | Implement hot-standby provider registry |

### P1 - High (Operational Impact)

| ID | Issue | Location | Evidence | Fix |
|----|-------|----------|----------|-----|
| P1-1 | No pause/resume | `AppState.swift:636-691` | Only start/stop states | Add `paused` state with buffer continuation |
| P1-2 | No sleep/wake handling | `MeetingListenerApp.swift` | No `NSWorkspace` observers | Add sleep notification handlers |
| P1-3 | Model loads on first request | `provider_faster_whisper.py:80` | Lazy `_get_model()` | Pre-load during backend startup |
| P1-4 | No pre-roll buffer | `AudioCaptureManager.swift:200-227` | Immediate frame emission | Add 500ms ring buffer for speech onset |
| P1-5 | DEBUG logging in production | `ws_live_listener.py:21` | `DEBUG = os.getenv(...)` used for `if DEBUG:` | Replace with proper logging levels |
| P1-6 | No disk space check | `SessionBundle.swift:233-257` | Direct write without check | Add capacity check before export |

### P2 - Medium (Reliability)

| ID | Issue | Location | Evidence | Fix |
|----|-------|----------|----------|-----|
| P2-1 | Port in use = hard failure | `BackendManager.swift:85-90` | Returns `.portInUse` → error state | Auto-retry on alternative ports |
| P2-2 | No global concurrency limit | `ws_live_listener.py:541` | Unlimited ASR tasks | Add semaphore with configurable limit |
| P2-3 | Analysis pile-up | `ws_live_listener.py:521` | Analysis runs every 12s/28s regardless of load | Skip if previous analysis still running |
| P2-4 | No drift measurement | `AppState.swift` | No audio vs wall clock comparison | Add drift ppm calculation |
| P2-5 | Temporary file leak | `BackendManager.swift:136-155` | Log file never cleaned | Add rotation and cleanup |

### P3 - Low (Polish)

| ID | Issue | Location | Evidence | Fix |
|----|-------|----------|----------|-----|
| P3-1 | No global hotkeys | `MeetingListenerApp.swift` | No `NSEvent.addGlobalMonitor` registered | Add Media Key and custom hotkey support |
| P3-2 | Language change requires restart | `asr_stream.py:30` | Environment variable only | Add runtime language switching |
| P3-3 | No manual speaker assignment | `SidePanelView.swift` | No speaker override UI | Add "Assign to Speaker" context menu |
| P3-4 | Silence threshold fixed | `AudioCaptureManager.swift:242` | Hardcoded 0.01 | Make configurable in Settings |
| P3-5 | No retention policy | `SessionBundle.swift` | Bundles accumulate | Add 30-day auto-cleanup |

---

## D) Operator Observability Requirements

### Required Metrics (to be emitted)

| Metric Name | Unit | Frequency | Source | Surface Location |
|-------------|------|-----------|--------|------------------|
| `audio_rms_dbfs` | dBFS | 100ms | `AudioCaptureManager.swift:247` | Level meter overlay |
| `audio_clip_count` | count | 1Hz | `AudioCaptureManager.swift:240` | Status bar indicator |
| `silence_seconds` | seconds | 1Hz | `AppState.swift:740` | Warning banner |
| `vad_active` | boolean | 100ms | `provider_faster_whisper.py:169` | LED indicator |
| `buffer_depth_ms` | milliseconds | 1Hz | `ws_live_listener.py:399` | Status bar |
| `processing_lag_ms` | milliseconds | 1Hz | `ws_live_listener.py:407` | Status bar (red if >2000ms) |
| `dropped_chunks` | count | 1Hz | `ws_live_listener.py:401` | Warning badge |
| `asr_rtf` | ratio | 1Hz | `ws_live_listener.py:406` | Status bar (green <0.8, red >1.0) |
| `diarization_confidence` | 0-1 | 5Hz | `diarization.py:156` | Speaker label opacity |
| `backend_cpu_percent` | percent | 5Hz | New metric | Status bar |
| `backend_memory_mb` | MB | 5Hz | New metric | Status bar |
| `websocket_latency_ms` | milliseconds | 10s | Ping/pong | Diagnostics panel |
| `session_duration_seconds` | seconds | 1Hz | `AppState.swift:1015-1021` | Timer display |

### Required Events (to be logged)

| Event | Trigger | Payload | Export |
|-------|---------|---------|--------|
| `session.started` | User clicks Start | session_id, audio_source, timestamp | NDJSON |
| `session.paused` | Sleep/operator pause | reason, timestamp | NDJSON |
| `session.resumed` | Wake/operator resume | timestamp | NDJSON |
| `session.ended` | User clicks Stop | duration, finalization_status | NDJSON |
| `audio.source_changed` | Display/mic switch | from, to, timestamp | NDJSON |
| `audio.silence_detected` | >10s no audio | duration, source | NDJSON |
| `audio.clipping_detected` | clip_ratio > 0.1 | severity, duration | NDJSON |
| `asr.stall_detected` | No output for 5s | last_output_time | NDJSON + Alert |
| `asr.provider_switched` | Failover to backup | from, to, reason | NDJSON + Alert |
| `backend.crashed` | Unexpected termination | exit_code, restart_attempt | NDJSON + Alert |
| `backend.recovered` | Successful restart | attempts_taken, time_to_recover | NDJSON |
| `network.reconnect` | WebSocket reconnect | attempt, delay | NDJSON |
| `export.completed` | Bundle saved | size_bytes, duration_seconds | NDJSON |
| `export.failed` | Disk full/error | error_type | NDJSON + Alert |

---

## E) Patch Set

### Patch 1: Add Per-Chunk ASR Timeout (P0-4)

**File:** `server/services/provider_faster_whisper.py`

```diff
--- a/server/services/provider_faster_whisper.py
+++ b/server/services/provider_faster_whisper.py
@@ -161,10 +161,14 @@ class FasterWhisperProvider(ASRProvider):
                 audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
 
                 infer_start = time.perf_counter()
+                chunk_timeout = float(os.getenv("ECHOPANEL_ASR_CHUNK_TIMEOUT", "10"))
                 
                 def _transcribe():
                     with self._infer_lock:
-                        segments, info = model.transcribe(
+                        segments, info = model.transcribe(
+                            audio,
+                            vad_filter=self.config.vad_enabled,
+                            language=self.config.language,
+                        )
+                    return list(segments), info
+
+                try:
+                    segments, info = await asyncio.wait_for(
+                        asyncio.to_thread(_transcribe),
+                        timeout=chunk_timeout
+                    )
+                except asyncio.TimeoutError:
+                    self._health.consecutive_errors += 1
+                    self._health.last_error = f"ASR chunk timeout after {chunk_timeout}s"
+                    self.log(f"WARNING: ASR chunk timeout after {chunk_timeout}s")
+                    # Yield empty segment to keep stream alive
+                    yield ASRSegment(
+                        text="",
+                        t0=t0, t1=t1,
+                        confidence=0.0,
+                        is_final=True,
+                        source=source,
+                    )
+                    continue
                 
                 infer_ms = (time.perf_counter() - infer_start) * 1000
                 self._infer_times.append(infer_ms)
```

### Patch 2: Add Pre-Roll Buffer for Speech Onset (P1-4)

**File:** `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`

```diff
--- a/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift
+++ b/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift
@@ -16,6 +16,10 @@ final class AudioCaptureManager: NSObject {
     private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
     private var converter: AVAudioConverter?
     private var pcmRemainder: [Int16] = []
+    
+    // P1-4: Pre-roll buffer for speech onset capture
+    private let preRollCapacity = 8000  // 0.5s at 16kHz
+    private var preRollBuffer: [Int16] = []
+    
     private var rmsEMA: Float = 0
     private var silenceEMA: Float = 0
     private var clipEMA: Float = 0
@@ -197,6 +201,16 @@ final class AudioCaptureManager: NSObject {
     }
 
     private func emitPCMFrames(samples: UnsafePointer<Float>, count: Int) {
+        // P1-4: Build pre-roll buffer
+        var pcmSamples: [Int16] = []
+        pcmSamples.reserveCapacity(count)
+        
+        for i in 0..<count {
+            let value = max(-1.0, min(1.0, samples[i]))
+            let int16Value = Int16(value * Float(Int16.max))
+            pcmSamples.append(int16Value)
+        }
+        
+        // Add to pre-roll buffer
+        preRollBuffer.append(contentsOf: pcmSamples)
+        if preRollBuffer.count > preRollCapacity {
+            preRollBuffer.removeFirst(preRollBuffer.count - preRollCapacity)
+        }
+        
+        // Check if we should emit (based on VAD or continuous streaming)
+        // For now, emit normally but preRollBuffer is available for burst detection
+        
         var pcmSamples: [Int16] = []
         pcmSamples.reserveCapacity(count)
 
```

### Patch 3: Add SRT Export Format (P0-1)

**File:** `macapp/MeetingListenerApp/Sources/AppState.swift` (add new method)

```swift
// MARK: - Broadcast Export Formats

func exportSRT() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "srt")!]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "echopanel-captions.srt"
    panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url, let self = self else { return }
        
        let srtContent = self.renderSRT()
        do {
            try srtContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Export SRT failed: %@", error.localizedDescription)
        }
    }
}

private func renderSRT() -> String {
    var lines: [String] = []
    var cueNumber = 1
    
    for segment in transcriptSegments where segment.isFinal {
        let startTime = formatSRTTime(segment.t0)
        let endTime = formatSRTTime(segment.t1)
        let speaker = segment.speaker.map { "\($0): " } ?? ""
        
        lines.append("\(cueNumber)")
        lines.append("\(startTime) --> \(endTime)")
        lines.append("\(speaker)\(segment.text)")
        lines.append("")  // Empty line between cues
        
        cueNumber += 1
    }
    
    return lines.joined(separator: "\n")
}

private func formatSRTTime(_ seconds: TimeInterval) -> String {
    let totalMillis = Int(seconds * 1000)
    let millis = totalMillis % 1000
    let totalSeconds = totalMillis / 1000
    let secs = totalSeconds % 60
    let mins = (totalSeconds / 60) % 60
    let hours = totalSeconds / 3600
    
    return String(format: "%02d:%02d:%02d,%03d", hours, mins, secs, millis)
}
```

---

## Summary & Recommendations

### For Meeting Documentation (Current Use Case):
- **Status:** Production-ready with v0.2 hardening
- **Key strengths:** Session bundles, crash recovery, structured logging
- **Recommendation:** Ship as-is for internal meeting notes

### For Live Broadcast Captioning:
- **Status:** Requires significant architectural changes
- **Minimum viable broadcast:** 4-6 weeks with 2 engineers
- **Blockers:** Real-time diarization, subtitle formats, device hot-swap, timing sync

### Priority Roadmap:

**Phase 1 (Weeks 1-2): Core Broadcast**
- [ ] P0-1: SRT/VTT export
- [ ] P0-2: Real-time diarization
- [ ] P0-4: ASR timeout with failover
- [ ] P1-4: Pre-roll buffer

**Phase 2 (Weeks 3-4): Reliability**
- [ ] P0-3: Display hot-swap
- [ ] P1-1: Pause/resume
- [ ] P1-2: Sleep/wake handling
- [ ] P2-1: Port retry

**Phase 3 (Weeks 5-6): Professional Features**
- [ ] Word-level timestamps
- [ ] Timecode support (LTC)
- [ ] UDP output for broadcast gear
- [ ] Global hotkeys

---

*Review completed: 2026-02-11*  
*Evidence base: 21 Swift files, 21 Python files analyzed*  
*Lines of code reviewed: ~15,000*
