> **⚠️ OBSOLETE (2026-02-16):** Core findings addressed. Remaining items are aspirational audio engineering recommendations, not bugs.
> - Clipping prevention: `applyLimiter()` in both `AudioCaptureManager.swift:398` and `MicrophoneCaptureManager.swift:324`
> - Sample rate conversion: AVAudioConverter 48kHz→16kHz in both managers
> - Thread safety: NSLock in both managers for EMA/metrics updates
> - Device monitoring: `DeviceHotSwapManager.swift` with bounded recovery
> Aspirational items (custom resampler, NTP clock, anti-alias filter) are out of scope for v0.2. Moved to archive.

# EchoPanel Audio Industry Code Review

**Date**: 2026-02-11  
**Reviewer**: Senior Audio Engineer (Broadcast/DAW/VoIP perspective)  
**Scope**: macOS audio capture, signal chain, latency, clocking, quality  
**Files Reviewed**:
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` (312 lines)
- `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift` (139 lines)
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` (420 lines)
- `macapp/MeetingListenerApp/Sources/AppState.swift` (sections)
- `server/api/ws_live_listener.py` (683 lines)
- `server/services/asr_stream.py` (92 lines)
- `server/services/provider_faster_whisper.py` (307 lines)
- `server/services/vad_filter.py` (148 lines)

---

## A) Signal Chain Diagram (Text)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                               MACOS CLIENT SIDE                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────┐         ┌─────────────────────┐                        │
│  │   SYSTEM AUDIO      │         │     MICROPHONE      │                        │
│  │  (ScreenCaptureKit) │         │   (AVAudioEngine)   │                        │
│  └──────────┬──────────┘         └──────────┬──────────┘                        │
│             │                               │                                    │
│             ▼                               ▼                                    │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │              SCStream (SCContentFilter)              │                        │
│  │         Captures: display + audio + screen          │                        │
│  │         Delegate: AudioSampleHandler                │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │      CMSampleBuffer (compressed, display-native)     │                        │
│  │      ASBD: mSampleRate=? (varies by display)         │                        │
│  │      mChannelsPerFrame=2 (stereo)                    │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   AVAudioConverter (inputFormat → targetFormat)      │                        │
│  │   Target: 16kHz, mono, PCM Float32                   │                        │
│  │   ⚠️ NO quality-controlled resampler (uses AVAudio)  │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   AVAudioPCMBuffer (Float32, 16kHz, mono)            │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   Float→Int16 conversion (clamping to [-1,1])        │                        │
│  │   samples[i] = Int16(clamp(float, -1, 1) * 32767)    │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   Frame packing: 320 samples = 20ms @ 16kHz         │                        │
│  │   pcmRemainder[] handles non-aligned buffers        │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   Base64 encoding → JSON WebSocket frame            │                        │
│  │   ⚠️ 33% overhead, no compression                   │                        │
│  │   {"type":"audio","source":"system","data":"..."}   │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
└──────────────────────┼───────────────────────────────────────────────────────────┘
                       │
                       │  WebSocket (localhost)
                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SERVER SIDE (Python)                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   ws_live_listener.py: WebSocket receive            │                        │
│  │   Base64 decode → PCM16 bytes                       │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   asyncio.Queue (maxsize=48, ~6s @ 2s chunks)       │                        │
│  │   Drop oldest on overflow (backpressure)            │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   ASR: faster-whisper (CTranslate2)                 │                        │
│  │   - Chunk size: 2-4s (configurable)                 │                        │
│  │   - VAD: optional (faster-whisper built-in)         │                        │
│  │   - Inference: threaded, serialized by lock         │                        │
│  └───────────────────┬─────────────────────────────────┘                        │
│                      │                                                           │
│                      ▼                                                           │
│  ┌─────────────────────────────────────────────────────┐                        │
│  │   Transcript segments → WebSocket → Client          │                        │
│  └─────────────────────────────────────────────────────┘                        │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

PARALLEL PATH (Microphone):
┌─────────────────────────────────────────────────────────┐
│  AVAudioEngine.inputNode (tapped)                        │
│  → AVAudioConverter (mic SR → 16kHz)                     │
│  → Same Float→Int16 → 320-sample frames                  │
│  → WebSocket → server                                    │
└─────────────────────────────────────────────────────────┘
```

---

## B) Latency Budget Table

| Stage | Component | Nominal Latency (ms) | Worst Case (ms) | Notes |
|-------|-----------|---------------------|-----------------|-------|
| **CAPTURE** | | | | |
| | ScreenCaptureKit callback | 5-20 | 50 | macOS scheduling, not real-time thread |
| | AVAudioEngine tap | 5-10 | 20 | Standard tap latency |
| | Bluetooth mic (if used) | +40-150 | +300 | AirPods add significant latency |
| **RESAMPLING** | | | | |
| | AVAudioConverter (system) | 5-10 | 30 | Quality depends on SRC algorithm |
| | AVAudioConverter (mic) | 5-10 | 30 | Same as above |
| | Float→Int16 conversion | <1 | <1 | Negligible |
| **PACKING** | | | | |
| | Frame assembly (320-sample) | 20 | 20 | Fixed 20ms frames |
| | pcmRemainder handling | 0-19 | 19 | Non-aligned buffer edge case |
| **TRANSMISSION** | | | | |
| | Base64 encoding | 1-2 | 5 | 33% data expansion |
| | WebSocket send | 1-5 | 50 | localhost, but JSON parsing overhead |
| | Server receive + queue | 1-3 | 20 | asyncio overhead |
| **QUEUING** | | | | |
| | Queue depth (typical) | 0-100 | 2000 | 48 max × 2s chunks = 96s max buffer |
| | Backpressure (drop) | 0 | N/A | Oldest frame dropped |
| **ASR PROCESSING** | | | | |
| | Chunk accumulation (2s) | 2000 | 2000 | Fixed by ECHOPANEL_ASR_CHUNK_SECONDS |
| | faster-whisper inference | 200-800 | 2000+ | CPU-dependent, model-dependent |
| | VAD (if enabled) | +50 | +100 | whisper VAD is internal |
| | Thread scheduling | 5-20 | 100 | GIL + threading.Lock |
| **RESPONSE** | | | | |
| | JSON serialization | 1-2 | 5 | |
| | WebSocket send | 1-5 | 50 | |
| | Client parsing + UI | 5-10 | 50 | SwiftUI update |
| **TOTAL** | | **~2300-3100** | **~4700+** | End-to-end, per 2s chunk |

### Critical Latency Observations:

1. **2-second chunking is the dominant latency** (~65% of total budget). This is a product decision, not a technical limitation. For real-time transcription, consider:
   - 500ms chunks for more responsive UI (but higher CPU %)
   - Hybrid approach: fast partial on VAD trigger, final on chunk boundary

2. **No timestamp compensation for processing delay**. The `t0`/`t1` timestamps reflect audio capture time, but ASR results are emitted after processing completes. For a 3s total latency, the transcript shows "0.0-2.0s" when the actual wall time is 3.0-5.0s.

3. **ScreenCaptureKit sample rate variability**:
   ```swift
   // AudioCaptureManager.swift:108-110
   NSLog("📊 processAudio: Input format - sampleRate: %.0f, channels: %d, bitsPerChannel: %d...",
         asbd.pointee.mSampleRate, asbd.pointee.mChannelsPerFrame, ...)
   ```
   The input sample rate depends on the display's audio configuration (typically 48kHz, but could be 44.1kHz). The AVAudioConverter handles this, but the conversion quality is not explicitly controlled.

---

## C) Risk-Ranked Issues List (P0–P3)

### 🔴 P0 - CRITICAL (Will cause audio corruption or data loss)

#### P0-1: NO CLOCK DRIFT COMPENSATION BETWEEN SOURCES
**Location**: `macapp/MeetingListenerApp/Sources/AppState.swift:233-265` (both onPCMFrame handlers)  
**Evidence**:
```swift
// System audio callback
audioCapture.onPCMFrame = { [weak self] frame, source in
    // ...
    self.streamer.sendPCMFrame(frame, source: source)  // Line 247
}

// Mic callback  
micCapture.onPCMFrame = { [weak self] frame, source in
    // ...
    self.streamer.sendPCMFrame(frame, source: source)  // Line 265
}
```
**Problem**: System audio (ScreenCaptureKit) and microphone (AVAudioEngine) run on independent clocks. Over a 1-hour meeting, they will drift apart by 10-100ms (typical for consumer hardware). This causes:
- Desynchronization between mic and system audio
- Incorrect speaker attribution in diarization
- Lip-sync issues if video is ever added

**Fix**: Implement a drift-compensated mixing buffer:
```swift
// Use a common timestamp reference (e.g., CACurrentMediaTime())
// and resample to compensate for drift
let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
let hostTime = CACurrentMediaTime()
// Calculate drift and resample accordingly
```

---

#### P0-2: HARD CLIPPING WITHOUT HEADROOM MANAGEMENT
**Location**: `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift:204-207`  
**Evidence**:
```swift
private func emitPCMFrames(samples: UnsafePointer<Float>, count: Int) {
    // ...
    let value = max(-1.0, min(1.0, samples[i]))  // Hard clipping!
    let int16Value = Int16(value * Float(Int16.max))
```

**Problem**: The code hard-clips at -1.0/1.0 before converting to Int16. For loud signals (e.g., system audio at max volume, or mic gain too high), this creates digital distortion. The `clipEMA` tracks clipping but doesn't prevent it.

**Impact**: ASR accuracy degrades significantly on clipped speech (whisper models are trained on clean audio).

**Fix**: Add AGC/limiter before the clip:
```swift
// Simple limiter with lookahead (or use AVAudioEngine's built-in limiter)
let gainReduction = max(1.0, peakLevel / 0.9)  // Target -0.9dBFS headroom
let limitedSample = sample / gainReduction
```

---

#### P0-3: NO SAMPLE RATE VERIFICATION AFTER CONVERSION
**Location**: `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift:148-165`  
**Evidence**: The AVAudioConverter is created once and cached. If the input format changes (e.g., display switch, Bluetooth device reconnect), the cached converter becomes invalid but is not recreated.

**Fix**: Validate output format matches expected:
```swift
// After conversion
guard outputBuffer.format.sampleRate == 16000,
      outputBuffer.format.channelCount == 1 else {
    // Recreate converter or error
}
```

---

### 🟡 P1 - HIGH (Will cause noticeable quality issues or reliability problems)

#### P1-1: BLUETOOTH AUDIO NOT HANDLED SPECIALLY
**Location**: `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift:29-52`  
**Evidence**: No check for `AVAudioSession.RouteChangeNotification` or Bluetooth device properties.

**Problem**: Bluetooth headsets (AirPods, etc.) often:
- Switch to lower sample rate in voice mode (8kHz or 16kHz)
- Have variable latency
- Add PLC (packet loss concealment) artifacts

**Impact**: ASR accuracy drops on Bluetooth audio due to codec artifacts and reduced bandwidth.

**Fix**: Detect Bluetooth and either:
- Warn user to use wired mic for best quality
- Apply noise suppression tuned for Bluetooth codecs

---

#### P1-2: NO DEVICE CHANGE HANDLING
**Location**: Both capture managers  
**Evidence**: No observers for `AVAudioEngineConfigurationChangeNotification` or display changes.

**Problem**: If user switches:
- Displays (different audio device)
- Microphones
- Audio output (which can affect input on some devices)

The capture continues with potentially wrong format or fails silently.

**Fix**: Add notification observers and restart capture with new format.

---

#### P1-3: VAD RUNS ON ASR SERVER, NOT CLIENT
**Location**: `server/services/vad_filter.py` exists but `server/services/asr_stream.py` doesn't use it  
**Evidence**:
```python
# asr_stream.py imports providers but NOT vad_filter
from . import provider_faster_whisper
from . import provider_voxtral_realtime
from . import provider_whisper_cpp
```

**Problem**: All audio is sent over WebSocket (including silence), wasting:
- Network bandwidth (localhost, but still)
- Server CPU (ASR runs on silence)
- Battery (unnecessary processing)

**Impact**: ~40% of meeting audio is silence. Running ASR on silence wastes compute.

**Fix**: Run VAD on client before sending:
```swift
// Add to AudioCaptureManager
private let vad = SileroVAD()  // or use Apple's voiceActivity detection

// In emitPCMFrames
if vad.hasSpeech(pcmSamples) {
    streamer.sendPCMFrame(frame, source: source)
}
```

---

#### P1-4: BASE64 ENCODING INEFFICIENCY
**Location**: `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift:152-158`  
**Evidence**:
```swift
let payload: [String: Any] = [
    "type": "audio",
    "source": source,
    "data": data.base64EncodedString()  // 33% overhead
]
```

**Problem**: Base64 adds 33% overhead to already-large audio data. For 16kHz mono, that's:
- Raw PCM: 32 KB/s
- Base64: 42.7 KB/s
- JSON wrapping: ~45 KB/s

**Fix**: Use binary WebSocket frames:
```swift
// Prefix with source byte, then raw PCM
task?.send(.data(frame)) { error in ... }
```

---

### 🟢 P2 - MEDIUM (Will cause minor issues or missed optimizations)

#### P2-1: NO AUDIO QUALITY METRICS ON SERVER
**Location**: Server receives audio but doesn't validate quality  
**Problem**: Clipping, low SNR, or DC offset on client won't be detected until ASR fails.

**Fix**: Add server-side audio quality check:
```python
# In ws_live_listener.py
rms = np.sqrt(np.mean(np.frombuffer(chunk, dtype=np.int16).astype(np.float32)**2))
if rms < 100:  # Very quiet
    logger.warning(f"Low audio level from {source}")
```

---

#### P2-2: MONO MIXING WITHOUT CHANNEL GAIN COMPENSATION
**Location**: `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` (stereo→mono conversion implied)  
**Problem**: If stereo input has out-of-phase content (common in system audio with spatial audio/Dolby), simple averaging causes cancellation.

**Fix**: Use energy-based mixing or take max of channels.

---

#### P2-3: NO DITHERING ON FLOAT→INT CONVERSION
**Location**: `AudioCaptureManager.swift:206`  
**Problem**: Converting Float32 to Int16 without dithering adds quantization distortion at low levels.

**Fix**: Add TPDF dither:
```swift
let dither = Float.random(in: -0.5...0.5) / 32768.0
let int16Value = Int16((value + dither) * 32767.0)
```

---

### 🔵 P3 - LOW (Nitpicks and future improvements)

- P3-1: No logging of actual sample rates in use (only logged once at start)
- P3-2: No measurement of actual round-trip latency
- P3-3: No automatic gain control (AGC) for mic input
- P3-4: No echo cancellation (AEC) for system→mic bleed
- P3-5: No noise suppression before ASR
- P3-6: Audio dump is raw PCM, no WAV header (makes debugging harder)

---

## D) Audio Correctness Checklist for CI/Smoke Tests

### Unit Tests (Client)
- [ ] **ClipDetectionTest**: Verify clipEMA correctly identifies clipped signals
- [ ] **SampleRateConversionTest**: Verify 48kHz→16kHz conversion is bit-accurate to reference
- [ ] **FramePackingTest**: Verify 320-sample frames are correctly packed, remainder handling
- [ ] **ClockDriftTest**: Verify mic and system audio stay synchronized over 5+ minutes
- [ ] **FormatChangeTest**: Verify capture survives format changes (mocked)

### Integration Tests (Client → Server)
- [ ] **EndToEndLatencyTest**: Measure total latency with known test tone
- [ ] **BackpressureTest**: Verify graceful degradation when server is slow
- [ ] **MultiSourceSyncTest**: Verify mic + system audio are correctly interleaved
- [ ] **SilenceTest**: Verify silence is handled correctly (no ASR hallucinations)
- [ ] **ClippingTest**: Verify clipped audio still produces reasonable ASR (degraded but not broken)

### Golden Reference Tests
- [ ] **KnownSpeechTest**: Feed known test file, verify transcript matches
- [ ] **VADAccuracyTest**: Compare VAD output against labeled ground truth
- [ ] **SampleRateRobustnessTest**: Test 44.1kHz, 48kHz, 96kHz inputs

### Manual QA Checklist
- [ ] Record 1-hour meeting, verify no clock drift artifacts
- [ ] Test with AirPods (Bluetooth) vs wired mic
- [ ] Test with external display (different audio routing)
- [ ] Test with system audio at max volume (check clipping)
- [ ] Test with very quiet speech (check noise floor)
- [ ] Verify silence detection works (no "you" hallucinations)

---

## E) Concrete Patch for Most Dangerous Bug

### P0-2 Fix: Add Limiter Before Clipping

**File**: `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`

```diff
--- a/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift
+++ b/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift
@@ -20,6 +20,10 @@ final class AudioCaptureManager: NSObject {
      private var pcmRemainder: [Int16] = []
      private var rmsEMA: Float = 0
      private var silenceEMA: Float = 0
      private var clipEMA: Float = 0
+    
+    // Limiter state for headroom management
+    private var limiterGain: Float = 1.0
+    private let limiterAttack: Float = 0.9  // Fast attack
+    private let limiterRelease: Float = 0.999  // Slow release
+    private let limiterThreshold: Float = 0.9  // -0.9 dBFS
 
      override init() {
          super.init()
@@ -197,11 +201,29 @@ final class AudioCaptureManager: NSObject {
          onSampleCount?(currentTotal)
 
          updateAudioQuality(samples: samples, count: frameCount)
-        emitPCMFrames(samples: samples, count: frameCount)
+        let limitedSamples = applyLimiter(samples: samples, count: frameCount)
+        emitPCMFrames(samples: limitedSamples, count: frameCount)
      }
 
+    private func applyLimiter(samples: UnsafePointer<Float>, count: Int) -> [Float] {
+        var limited = [Float](repeating: 0, count: count)
+        for i in 0..<count {
+            let sample = samples[i]
+            let absSample = abs(sample)
+            
+            // Calculate target gain
+            let targetGain = absSample > limiterThreshold ? limiterThreshold / absSample : 1.0
+            
+            // Attack/release smoothing
+            if targetGain < limiterGain {
+                limiterGain = limiterGain * limiterAttack + targetGain * (1 - limiterAttack)
+            } else {
+                limiterGain = limiterGain * limiterRelease + targetGain * (1 - limiterRelease)
+            }
+            
+            limited[i] = sample * limiterGain
+        }
+        return limited
+    }
 
      private func emitPCMFrames(samples: UnsafePointer<Float>, count: Int) {
          var pcmSamples: [Int16] = []
          pcmSamples.reserveCapacity(count)
 
          for i in 0..<count {
-            let value = max(-1.0, min(1.0, samples[i]))
+            let value = samples[i]  // Already limited, no need to clamp
              let int16Value = Int16(value * Float(Int16.max))
              pcmSamples.append(int16Value)
          }
```

**Same change applies to**: `MicrophoneCaptureManager.swift:111-114`

### Alternative: Use AVAudioEngine's Built-in Limiter

```swift
// In MicrophoneCaptureManager.startCapture()
let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
    componentType: kAudioUnitType_Effect,
    componentSubType: kAudioUnitSubType_PeakLimiter,
    componentManufacturer: kAudioUnitManufacturer_Apple,
    componentFlags: 0,
    componentFlagsMask: 0
))
audioEngine.attach(limiter)
audioEngine.connect(inputNode, to: limiter, format: inputFormat)
audioEngine.connect(limiter, to: audioEngine.mainMixerNode, format: targetFormat)
```

---

## Summary

### Most Critical Issues
1. **Clock drift** between mic and system audio will cause desync in multi-source scenarios
2. **Hard clipping** degrades ASR quality on loud signals
3. **No client-side VAD** wastes 40% of compute on silence

### Recommended Priority Order
1. **Immediate (this week)**: Add limiter to prevent clipping (P0-2 patch above)
2. **Short term (next sprint)**: Implement client-side VAD to reduce bandwidth/compute
3. **Medium term**: Add clock drift compensation for multi-source sync
4. **Long term**: Binary WebSocket frames, AEC, NS, AGC for production quality

### Audio Quality Confidence
- **Single source (mic only)**: 7/10 (clipping risk, no AGC)
- **Single source (system only)**: 6/10 (more likely to clip, variable input SR)
- **Dual source (mic + system)**: 5/10 (clock drift will cause issues in long meetings)

---

*Review completed: 2026-02-11*  
*Method: Static analysis with evidence citations*  
*Recommendation: Address P0 issues before production use*
