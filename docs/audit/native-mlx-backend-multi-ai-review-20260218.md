# NativeMLXBackend.swift Multi-AI Code Review

**Review Date:** 2026-02-18
**Review Type:** AUDIT
**Reviewers:** Qwen, Kimi, GLM (synthesized analysis)
**Target File:** `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift` (336 lines)

---

## Executive Summary

1. **Critical Safety Issue: Force Unwrapping** - Multiple instances of force unwrapping `model!` (lines 111, 127, 195) will crash if `initialize()` hasn't completed or failed. All three AI agents identified this as the highest-priority issue.

2. **Incorrect Duration Calculation** - Duration calculated from raw `Data` byte count assuming 16kHz/16-bit PCM (line 147). Ignores actual sample rate from `loadAudioArray`, causing wrong duration values for other formats.

3. **Hardcoded Confidence Values** - Confidence hardcoded to 0.95 (final) and 0.9 (partial) throughout codebase. Misleading to users and downstream logic since model doesn't provide actual confidence scores.

4. **Race Condition in Streaming Initialization** - `startStreaming` returns stream before session is initialized (lines 173-251). Caller may invoke `feedAudio` before session exists, causing silent audio drops.

5. **`isAvailable` Lies About State** - Property returns `true` hardcoded without checking `isModelLoaded` (line 19). Misleads callers about backend availability and creates trust boundary issues.

6. **Thread Safety Issue in `feedAudio`** - Method is synchronous but accesses actor-isolated `streamingSession` (line 260-262). Calling from real-time audio thread causes data races and potential audio dropouts.

7. **Inefficient File I/O Pipeline** - Writes audio `Data` to temp file then immediately reads it back (lines 102-110). Disk I/O adds unnecessary latency to transcription.

8. **Heavy Memory Copies in Resampling** - Multiple format conversions create excessive copies (lines 290-334). Inefficient for large audio chunks and streaming scenarios.

9. **Mutable Public Configuration** - Public mutable vars (`modelId`, `maxTokens`, `temperature`) on actor create unclear behavior if changed during active operations (lines 54-58).

10. **Missing Error Context** - Errors converted to strings before propagating (line 247), losing original error context and debugging information.

11. **Inconsistent Timestamp Handling** - Timestamps hardcoded to zero in streaming mode (lines 210, 230), breaking downstream consumers needing alignment data.

12. **Swift 6 Concurrency Issues** - Using `@preconcurrency` to suppress warnings (lines 1, 5) suggests avoiding proper Sendable conformance. Code smell for production Swift 6 code.

---

## Files Inspected

| File | Lines | Key Sections |
|------|-------|--------------|
| `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift` | 336 | All sections reviewed |

**Key Sections Analyzed:**
- Properties (lines 14-59): Configuration, state, streaming, metrics
- Initialization (lines 64-92): `initialize()`, `reloadModel()`, `unload()`
- Transcription (lines 94-171): `transcribe()` with file I/O and generation
- Streaming (lines 173-262): `startStreaming()`, `feedAudio()`, `stopStreaming()`
- Helpers (lines 279-334): `updateStatus()`, `resampleAudio()`

---

## Failure Modes Table

| ID | Failure Mode | Severity | Impact | Likelihood | Detection |
|----|--------------|----------|--------|------------|-----------|
| FM-001 | Crash: Model force unwrap before initialization | P0 | Crash | Medium | Runtime crash |
| FM-002 | Crash: Model force unwrap after unload | P0 | Crash | Low | Runtime crash |
| FM-003 | Crash: Race condition - transcribe called during reload | P0 | Crash | Low | Runtime crash |
| FM-004 | Silent failure: feedAudio called before session ready | P0 | Audio loss | Medium | Missing transcripts |
| FM-005 | Data corruption: Incorrect duration calculation | P1 | UX bug | High | Wrong timestamps |
| FM-006 | Misleading data: Hardcoded confidence values | P1 | Trust issue | High | Always visible |
| FM-007 | Data race: feedAudio from real-time thread | P0 | Undefined behavior | Medium | Audio glitches, crashes |
| FM-008 | Performance: Disk I/O bottleneck in transcribe | P1 | Latency | High | Slow transcription |
| FM-009 | Memory: Excessive copies in resampling | P2 | Memory pressure | High | Memory usage spikes |
| FM-010 | UX: isAvailable lies about actual state | P1 | Misleading UI | Medium | Wrong availability indicators |
| FM-011 | Data loss: Streaming session not initialized before return | P0 | Audio loss | Medium | Missing initial audio |
| FM-012 | Debug: Error context lost in string conversion | P2 | Debug difficulty | High | Poor error messages |
| FM-013 | UX: Timestamps always zero in streaming | P1 | Feature broken | High | Always visible |
| FM-014 | Concurrency: feedAudio blocks real-time thread | P0 | Audio dropouts | Medium | Audio glitches |
| FM-015 | State: Mutable config during active operations | P2 | Unexpected behavior | Low | Hard to reproduce |

---

## Root Causes Analysis

### Ranked by Impact

**RC-001: Lack of defensive programming for optional model** (Impact: P0)

- **Root Cause:** Developer assumes `initialize()` always succeeds and `model` is always non-nil
- **Evidence:** Force unwrapping at lines 111, 127, 195 without guards
- **Contributing Factors:**
  - No validation of `isModelLoaded` before accessing `model`
  - No early return patterns for initialization failures
  - Confusing `isAvailable` (hardcoded true) vs actual state
- **Fix Strategy:** Replace all `model!` with guard-let pattern throwing appropriate errors

**RC-002: Streaming initialization timing mismatch** (Impact: P0)

- **Root Cause:** AsyncThrowingStream builder returns before session creation completes
- **Evidence:** `startStreaming` returns stream (line 173), session created inside Task (line 194-198)
- **Contributing Factors:**
  - Task scheduling delays allow `feedAudio` calls before session exists
  - No state flag to indicate "session initializing"
  - Optional chaining in `feedAudio` silently drops audio
- **Fix Strategy:** Initialize session before returning stream, add state machine validation

**RC-003: Thread safety boundary violation in feedAudio** (Impact: P0)

- **Root Cause:** Synchronous method accesses actor-isolated state from potentially non-actor thread
- **Evidence:** `feedAudio` is synchronous (line 260), accesses `streamingSession` (actor-isolated)
- **Contributing Factors:**
  - AVAudioEngine calls from real-time thread
  - Actor isolation hop blocks audio thread
  - No thread-safe buffer between audio capture and actor
- **Fix Strategy:** Use thread-safe ring buffer or Nonisolated(unsafe) with proper synchronization

**RC-004: Hardcoded audio format assumptions** (Impact: P1)

- **Root Cause:** Assumes input is always 16kHz/16-bit PCM without validation
- **Evidence:** Duration formula `Double(audio.count) / 16000.0 / 2.0` (line 147)
- **Contributing Factors:**
  - Doesn't use actual sample rate from `loadAudioArray` (available at line 110)
  - Doesn't validate audio format before processing
  - Doesn't handle compressed formats (AAC, MP3, FLAC)
- **Fix Strategy:** Calculate duration from loaded `MLXArray` sample count and actual sample rate

**RC-005: Trust boundary violation with isAvailable** (Impact: P1)

- **Root Cause:** Returns hardcoded `true` without checking actual state
- **Evidence:** `return true` at line 19, ignores `isModelLoaded`
- **Contributing Factors:**
  - Attempted optimization to avoid actor hop
  - Nonisolated property can't access actor state
  - Misleading API contract
- **Fix Strategy:** Remove `nonisolated`, make async property checking `isModelLoaded`

**RC-006: Inefficient data pipeline with unnecessary disk I/O** (Impact: P1)

- **Root Cause:** Intermediate file write/read when in-memory processing possible
- **Evidence:** `audio.write(to: tempURL)` (line 106), `loadAudioArray(from: tempURL)` (line 110)
- **Contributing Factors:**
  - MLXAudioSTT library requires file path
  - No in-memory audio loading API
  - Blocking I/O on actor context
- **Fix Strategy:** Offload I/O to background thread with Task.detached or use in-memory loading if supported

**RC-007: Multiple memory copies in resampling** (Impact: P2)

- **Root Cause:** Multiple format conversions create intermediate arrays
- **Evidence:** `audio.asArray(Float.self)` (line 291), `memcpy` (line 310), `Array(UnsafeBufferPointer...)` (line 330)
- **Contributing Factors:**
  - AVAudioConverter requires AVAudioPCMBuffer
  - No zero-copy conversion path
  - Swift Array overhead
- **Fix Strategy:** Use vDSP or work directly with unsafe buffers to minimize copies

**RC-008: Missing model confidence data** (Impact: P1)

- **Root Cause:** Hardcoded values instead of using model probabilities
- **Evidence:** `confidence: 0.95` (lines 155, 164, 212, 232)
- **Contributing Factors:**
  - MLXAudioSTT library may not expose confidence data
  - No protocol field for optional confidence
  - Developer convenience over correctness
- **Fix Strategy:** Return 0.0 or special value indicating "unknown", document limitation

---

## Concrete Fixes

### Ranked by Impact/Effort/Risk

**FIX-001: Replace force unwrapping with guard-let pattern** (Impact: P0, Effort: Low, Risk: Low)

- **Location:** Lines 111, 127, 195
- **Code:**
  ```swift
  // Before:
  let targetRate = model!.sampleRate
  for try await event in model!.generateStream(...)

  // After:
  guard let currentModel = model else {
      throw ASRError.backendNotAvailable(backend: name)
  }
  let targetRate = currentModel.sampleRate
  for try await event in currentModel.generateStream(...)
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Add unit tests for transcribe/startStreaming without initialization
- **Rollback:** Simple rollback, no behavior change

**FIX-002: Fix streaming initialization race condition** (Impact: P0, Effort: Medium, Risk: Low)

- **Location:** Lines 173-251
- **Code:**
  ```swift
  public func startStreaming(config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error> {
      // Initialize session BEFORE returning stream
      guard let currentModel = model else {
          return AsyncThrowingStream { $0.finish(throwing: ASRError.backendNotAvailable(backend: name)) }
      }

      let streamingConfig = StreamingConfig(...)
      let session = StreamingInferenceSession(model: currentModel, config: streamingConfig)
      self.streamingSession = session
      self.isStreaming = true

      return AsyncThrowingStream { continuation in
          continuation.yield(.started)
          continuation.onTermination = { @Sendable _ in
              Task { await self.stopStreaming() }
          }

          Task {
              for await event in session.events {
                  // ... event mapping ...
              }
              continuation.finish()
          }
      }
  }
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Integration test calling feedAudio immediately after startStreaming
- **Rollback:** Moderate, requires state machine adjustment

**FIX-003: Add thread-safe audio buffer for feedAudio** (Impact: P0, Effort: High, Risk: Medium)

- **Location:** Lines 260-262
- **Approach:**
  1. Create `Nonisolated(unsafe)` ring buffer (e.g., using swift-atomics)
  2. `feedAudio` writes to buffer synchronously (non-blocking)
  3. Actor task periodically reads from buffer and feeds to session
  4. Add backpressure signaling if buffer full
- **Code:**
  ```swift
  // Add property
  private nonisolated(unsafe) var audioBuffer: ThreadSafeRingBuffer<Float> = ThreadSafeRingBuffer(capacity: 4096)

  public func feedAudio(samples: [Float]) {
      // Fast non-blocking write
      audioBuffer.write(samples)
  }

  // Add background task in actor
  private func startAudioBufferConsumer() {
      Task {
          while isStreaming {
              var chunk = audioBuffer.read(upTo: 1024)
              if !chunk.isEmpty {
                  streamingSession?.feedAudio(samples: chunk)
              }
              try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
          }
      }
  }
  ```
- **Files:** `NativeMLXBackend.swift`, new `ThreadSafeRingBuffer.swift`
- **Testing:** Load test with high-frequency audio samples from multiple threads
- **Rollback:** Complex, affects audio pipeline architecture

**FIX-004: Fix duration calculation using actual sample rate** (Impact: P1, Effort: Low, Risk: Low)

- **Location:** Line 147
- **Code:**
  ```swift
  // Before:
  let duration = Double(audio.count) / 16000.0 / 2.0

  // After:
  let sampleCount = Double(audioData.shape[0])  // MLXArray holds actual samples
  let duration = sampleCount / Double(sampleRate)
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Unit tests with various sample rates and formats
- **Rollback:** Simple, improves correctness

**FIX-005: Make isAvailable reflect actual state** (Impact: P1, Effort: Low, Risk: Low)

- **Location:** Lines 16-20
- **Code:**
  ```swift
  // Before:
  public nonisolated var isAvailable: Bool {
      return true
  }

  // After:
  public var isAvailable: Bool {
      return isModelLoaded && model != nil
  }
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Verify isAvailable false before init, true after, false after unload
- **Rollback:** Simple, improves trustworthiness

**FIX-006: Offload disk I/O to background thread** (Impact: P1, Effort: Medium, Risk: Low)

- **Location:** Lines 102-110
- **Code:**
  ```swift
  // Before:
  try audio.write(to: tempURL)
  let (sampleRate, audioData) = try loadAudioArray(from: tempURL)

  // After:
  let (sampleRate, audioData) = try await Task.detached(priority: .userInitiated) {
      try audio.write(to: tempURL)
      return try loadAudioArray(from: tempURL)
  }.value
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Measure transcription time with/without offloading
- **Rollback:** Simple, improves performance

**FIX-007: Replace hardcoded confidence with unknown value** (Impact: P1, Effort: Low, Risk: Low)

- **Location:** Lines 155, 164, 205, 212, 232
- **Code:**
  ```swift
  // Before:
  confidence: 0.95

  // After:
  confidence: 0.0  // Placeholder - actual confidence not available from model

  // Or make TranscriptionSegment.confidence optional:
  // confidence: nil  // Signals "unknown"
  ```
- **Files:** `NativeMLXBackend.swift`, potentially update `TranscriptionSegment` protocol
- **Testing:** Verify UI handles zero/nil confidence correctly
- **Rollback:** Simple, improves honesty

**FIX-008: Replace mutable public config with immutable struct** (Impact: P2, Effort: Medium, Risk: Medium)

- **Location:** Lines 54-58
- **Code:**
  ```swift
  // Before:
  public var modelId: String = "mlx-community/Qwen3-ASR-0.6B-4bit"
  public var maxTokens: Int = 1024

  // After:
  public struct Configuration {
      public let modelId: String
      public let maxTokens: Int
      public let temperature: Float
      public let chunkDuration: Float
      public let streamingDelayMs: Int

      public static let `default` = Configuration(
          modelId: "mlx-community/Qwen3-ASR-0.6B-4bit",
          maxTokens: 1024,
          temperature: 0.0,
          chunkDuration: 30.0,
          streamingDelayMs: 480
      )
  }

  public var configuration: Configuration = .default
  ```
- **Files:** `NativeMLXBackend.swift`, update initialization API
- **Testing:** Verify config immutability, update tests
- **Rollback:** Moderate, API change

**FIX-009: Preserve error context in propagation** (Impact: P2, Effort: Low, Risk: Low)

- **Location:** Line 247
- **Code:**
  ```swift
  // Before:
  continuation.yield(.error(ASRError.transcriptionFailed(reason: error.localizedDescription)))

  // After:
  continuation.yield(.error(error))  // Pass original error
  ```
- **Files:** `NativeMLXBackend.swift`
- **Testing:** Verify error context preserved in logs
- **Rollback:** Simple, improves debuggability

**FIX-010: Add proper timestamp handling in streaming** (Impact: P1, Effort: High, Risk: Medium)

- **Location:** Lines 210, 230
- **Approach:**
  1. Track audio feed timing in streaming session
  2. Calculate segment boundaries based on audio duration
  3. Pass timestamps through event stream
  4. Requires updates to StreamingInferenceSession and TranscriptionEvent
- **Code:**
  ```swift
  // Track audio timing
  private var streamingAudioDuration: TimeInterval = 0

  public func feedAudio(samples: [Float]) {
      streamingAudioDuration += Double(samples.count) / 16000.0
      streamingSession?.feedAudio(samples: samples)
  }

  // In event handler:
  case .confirmed(let text):
      let segment = TranscriptionSegment(
          text: text,
          startTime: lastSegmentEndTime,
          endTime: streamingAudioDuration,
          confidence: 0.0,
          isFinal: true
      )
      lastSegmentEndTime = streamingAudioDuration
  ```
- **Files:** `NativeMLXBackend.swift`, potentially update streaming library
- **Testing:** Integration tests with timing validation
- **Rollback:** Complex, affects streaming architecture

---

## Test Plan

### Unit Tests

1. **UT-001: Force unwrap protection**
   - Call `transcribe()` before `initialize()`
   - Expected: `ASRError.backendNotAvailable` thrown
   - Call `startStreaming()` before `initialize()`
   - Expected: Error stream yielded

2. **UT-002: Duration calculation accuracy**
   - Create test audio with known duration (10s at 16kHz)
   - Call `transcribe()`
   - Expected: Duration ≈ 10.0s within 1% tolerance
   - Test with 44.1kHz audio
   - Expected: Duration calculated correctly from actual sample rate

3. **UT-003: isAvailable state tracking**
   - Check `isAvailable` before init
   - Expected: `false`
   - Call `initialize()`
   - Check `isAvailable`
   - Expected: `true`
   - Call `unload()`
   - Check `isAvailable`
   - Expected: `false`

4. **UT-004: Confidence values**
   - Call `transcribe()` with test audio
   - Expected: Confidence = 0.0 (or nil)
   - Start streaming, receive partial event
   - Expected: Partial confidence = 0.0 (or nil)

5. **UT-005: Configuration immutability**
   - Create backend with config
   - Attempt to modify config properties
   - Expected: Compile error (immutable) or runtime error

### Integration Tests

6. **IT-001: Streaming initialization timing**
   - Call `startStreaming()`
   - Immediately call `feedAudio()` with test samples
   - Expected: Audio processed, not silently dropped
   - Verify transcript contains test audio content

7. **IT-002: Thread-safe audio feeding**
   - Spawn 10 threads calling `feedAudio()` concurrently
   - Each feeds 1000 samples
   - Expected: All samples processed, no crashes, correct total duration
   - Verify transcript completeness

8. **IT-003: Error propagation**
   - Initialize backend
   - Corrupt model file
   - Call `transcribe()`
   - Expected: Original error preserved, not stringified

9. **IT-004: Long-form transcription**
   - Create 5-minute test audio
   - Call `transcribe()`
   - Expected: No timeouts, correct duration, complete transcript

10. **IT-005: Model lifecycle**
    - Initialize model
    - Transcribe audio
    - Reload model with different ID
    - Transcribe again
    - Expected: Both transcriptions use correct models

### Manual Tests

11. **MT-001: Crash prevention**
    - Launch app
    - Start session before MLX model loads
    - Expected: Graceful error message, no crash
    - Quit app
    - Start session, immediately close
    - Expected: No crash

12. **MT-002: Audio format handling**
    - Record audio at 44.1kHz
    - Transcribe
    - Expected: Correct duration, accurate transcript
    - Export transcript
    - Verify timestamps make sense

13. **MT-003: Streaming under load**
    - Start 30-minute meeting recording
    - Monitor CPU/memory usage
    - Expected: Stable performance, no memory leaks
    - Check transcript completeness

14. **MT-004: Offline behavior**
    - Disable network
    - Initialize NativeMLXBackend
    - Expected: Successful initialization (no network dependency)
    - Transcribe local audio
    - Expected: Successful transcription

15. **MT-005: Multi-session**
    - Start session A
    - Start session B (different backend)
    - Expected: Both sessions work independently
    - Stop session A
    - Expected: Session B continues unaffected

---

## Instrumentation Plan

### Metrics

**Client-Side Metrics:**

1. **MLX-001: Model load time**
   - Type: Histogram
   - Labels: `model_id`, `success` (true/false)
   - Description: Time to load MLX model in seconds
   - Alert: > 30s threshold

2. **MLX-002: Transcription latency**
   - Type: Histogram
   - Labels: `audio_duration_seconds`, `model_id`
   - Description: Processing time / audio duration (RTF)
   - Alert: > 0.5 RTF

3. **MLX-003: Streaming audio buffer**
   - Type: Gauge
   - Labels: `session_id`
   - Description: Number of samples in ring buffer
   - Alert: > 4096 (backpressure)

4. **MLX-004: Force unwrap attempts**
   - Type: Counter
   - Labels: `location` (method name)
   - Description: Number of guard-let failures (attempted force unwraps)
   - Alert: Any increment

5. **MLX-005: Initialization failures**
   - Type: Counter
   - Labels: `reason`
   - Description: Number of model load failures
   - Alert: Any increment

6. **MLX-006: Duration calculation errors**
   - Type: Counter
   - Labels: `input_sr`, `calculated_duration`
   - Description: Discrepancy between expected and calculated duration
   - Alert: > 10% discrepancy

**Server-Side Metrics:** (N/A - NativeMLXBackend is client-only)

### Logs

**Client-Side Logs:**

7. **LOG-MLX-001: Model state transitions**
   - Level: INFO
   - Event: `model_state_changed`
   - Fields: `from`, `to`, `model_id`
   - Frequency: On each state change

8. **LOG-MLX-002: Transcription started**
   - Level: DEBUG
   - Event: `transcription_started`
   - Fields: `backend_name`, `audio_duration`, `sample_rate`
   - Frequency: On each transcribe call

9. **LOG-MLX-003: Transcription completed**
   - Level: DEBUG
   - Event: `transcription_completed`
   - Fields: `backend_name`, `processing_time`, `duration`, `confidence`
   - Frequency: On each transcribe completion

10. **LOG-MLX-004: Streaming session created**
    - Level: DEBUG
    - Event: `streaming_session_created`
    - Fields: `session_id`, `config`, `model_id`
    - Frequency: On each startStreaming call

11. **LOG-MLX-005: Streaming session ended**
    - Level: DEBUG
    - Event: `streaming_session_ended`
    - Fields: `session_id`, `reason`, `audio_duration`
    - Frequency: On each stopStreaming call

12. **LOG-MLX-006: Audio buffer overflow**
    - Level: WARN
    - Event: `audio_buffer_overflow`
    - Fields: `buffer_size`, `capacity`, `session_id`
    - Frequency: On buffer overflow

13. **LOG-MLX-007: Guard-let failure**
    - Level: ERROR
    - Event: `guard_let_failure`
    - Fields: `method`, `variable`, `error`
    - Frequency: On each guard-let failure

14. **LOG-MLX-008: Model reload started**
    - Level: INFO
    - Event: `model_reload_started`
    - Fields: `old_model_id`, `new_model_id`
    - Frequency: On reloadModel call

15. **LOG-MLX-009: Model reload completed**
    - Level: INFO
    - Event: `model_reload_completed`
    - Fields: `model_id`, `duration`, `success`
    - Frequency: On reloadModel completion

---

## State Machine Diagrams

### Model Lifecycle State Machine

```
States:
- UNINITIALIZED
- LOADING
- READY
- ERROR
- UNLOADING

Transitions:

UNINITIALIZED
  -- initialize() --> LOADING
  -- transcribe() without init --> ERROR (throw)

LOADING
  -- Qwen3ASRModel.fromPretrained() success --> READY
  -- Qwen3ASRModel.fromPretrained() failure --> ERROR

READY
  -- transcribe() --> READY (transcribing)
  -- startStreaming() --> READY (streaming)
  -- reloadModel() --> LOADING
  -- unload() --> UNLOADING

ERROR
  -- reloadModel() --> LOADING
  -- unload() --> UNLOADING

UNLOADING
  -- cleanup complete --> UNINITIALIZED
```

### Streaming Session State Machine

```
States:
- IDLE
- INITIALIZING
- ACTIVE
- STOPPING

Transitions:

IDLE
  -- startStreaming() called --> INITIALIZING

INITIALIZING
  -- session created --> ACTIVE
  -- error --> IDLE

ACTIVE
  -- feedAudio() --> ACTIVE (buffering)
  -- stopStreaming() --> STOPPING
  -- error --> IDLE

STOPPING
  -- cleanup complete --> IDLE
```

### Audio Buffer State Machine

```
States:
- EMPTY
- FILLING
- FULL
- DRAINING

Transitions:

EMPTY
  -- feedAudio() called --> FILLING

FILLING
  -- samples written --> FILLING
  -- buffer capacity reached --> FULL
  -- consumer reads --> DRAINING

FULL
  -- consumer reads --> DRAINING

DRAINING
  -- samples consumed --> FILLING
  -- buffer empty --> EMPTY
```

---

## Evidence Citations

### Critical Safety Issues

**Force Unwrapping (FM-001, FM-002, FM-003):**
- Line 111: `let targetRate = model!.sampleRate` - NativeMLXBackend.swift
- Line 127: `for try await event in model!.generateStream(...)` - NativeMLXBackend.swift
- Line 195: `model: self.model!` - NativeMLXBackend.swift

**Streaming Race Condition (FM-004, FM-011):**
- Lines 173-251: `startStreaming()` returns AsyncThrowingStream before session initialization - NativeMLXBackend.swift
- Line 194-198: Session created inside Task after stream returned - NativeMLXBackend.swift
- Lines 260-262: `feedAudio()` uses optional chaining - NativeMLXBackend.swift

**Thread Safety (FM-007, FM-014):**
- Lines 260-262: `feedAudio()` is synchronous, accesses actor-isolated `streamingSession` - NativeMLXBackend.swift

### Audio Handling Issues

**Incorrect Duration Calculation (FM-005):**
- Line 147: `let duration = Double(audio.count) / 16000.0 / 2.0` - NativeMLXBackend.swift
- Line 110: `let (sampleRate, audioData) = try loadAudioArray(from: tempURL)` - Actual sample rate available but not used - NativeMLXBackend.swift

**Inefficient File I/O (FM-008):**
- Line 106: `try audio.write(to: tempURL)` - Disk write - NativeMLXBackend.swift
- Line 110: `loadAudioArray(from: tempURL)` - Immediate disk read - NativeMLXBackend.swift

**Memory Copies in Resampling (FM-009):**
- Line 291: `audio.asArray(Float.self)` - MLXArray to Array - NativeMLXBackend.swift
- Line 310: `memcpy(inputBuffer.floatChannelData![0], samples, ...)` - Unsafe copy - NativeMLXBackend.swift
- Line 330: `Array(UnsafeBufferPointer(start: ...))` - Buffer to Array - NativeMLXBackend.swift

### API and State Issues

**isAvailable Lies (FM-010):**
- Lines 16-20: `isAvailable` returns hardcoded `true` - NativeMLXBackend.swift
- Line 40: `isModelLoaded` exists but not checked - NativeMLXBackend.swift

**Hardcoded Confidence (FM-006):**
- Line 155: `confidence: 0.95` - TranscriptionSegment - NativeMLXBackend.swift
- Line 164: `confidence: 0.95` - TranscriptionResult - NativeMLXBackend.swift
- Line 205: `confidence: 0.9` - Partial event - NativeMLXBackend.swift
- Line 212: `confidence: 0.95` - Confirmed segment - NativeMLXBackend.swift
- Line 232: `confidence: 0.95` - Full text result - NativeMLXBackend.swift

**Zero Timestamps (FM-013):**
- Line 210: `startTime: 0, endTime: 0` - Streaming segment - NativeMLXBackend.swift
- Line 230: `startTime: 0, endTime: 0` - Streaming final - NativeMLXBackend.swift

**Mutable Config (FM-015):**
- Lines 54-58: Public mutable vars on actor - NativeMLXBackend.swift

**Error Context Loss (FM-012):**
- Line 247: `ASRError.transcriptionFailed(reason: error.localizedDescription)` - NativeMLXBackend.swift

### Swift Concurrency Issues

**@preconcurrency Usage:**
- Line 1: `@preconcurrency import Foundation` - NativeMLXBackend.swift
- Line 5: `@preconcurrency import AVFoundation` - NativeMLXBackend.swift

---

## Key Questions Answered

### Qwen's Questions:

1. **What guarantees exist that initialize() has been called before transcribe()?**
   - **Answer:** None. This is the critical gap. `transcribe()` force unwraps `model!` without checking `isModelLoaded`. Fix: Add guard-let check (FIX-001).

2. **What is the reasoning for file system intermediary step?**
   - **Answer:** MLXAudioSTT library's `loadAudioArray()` requires a file path URL, not in-memory Data. This is a library limitation. Fix: Offload I/O to background thread (FIX-006).

3. **What prevents us from exposing actual model confidence?**
   - **Answer:** The MLXAudioSTT library's `StreamingInferenceSession` events (`.token`, `.info`, `.result`) do not include probability/logit data. Only `tokensPerSecond` and `peakMemoryUsage` are available. Fix: Return 0.0 to indicate unknown (FIX-007).

4. **How does the system behave if audio is 44.1kHz or compressed?**
   - **Answer:** Incorrect. Duration calculation assumes 16kHz/16-bit PCM, giving wrong values. However, `resampleAudio()` correctly converts different sample rates to model's sample rate (16kHz). Fix: Calculate duration from actual loaded samples (FIX-004).

5. **What prevents concurrent streaming sessions?**
   - **Answer:** Nothing. `startStreaming()` can be called while a session is active. The old session is orphaned (no stop() call). Fix: Check `isStreaming` guard before creating new session.

### Kimi's Questions:

1. **Does feedAudio risk returning stale info?**
   - **Answer:** No risk of staleness since `isAvailable` is hardcoded true, but the real issue is that `isAvailable` doesn't reflect actual state (`isModelLoaded`). Fix: Remove `nonisolated`, check `isModelLoaded` (FIX-005).

2. **What happens if startStreaming is called while previous session active?**
   - **Answer:** The new session overwrites `streamingSession` property. Old session continues running in background until GC, causing resource leaks. No guard prevents this. Fix: Add state machine validation.

3. **How do we ensure metrics updates remain atomic?**
   - **Answer:** `metrics` is actor-isolated, so all updates are atomic by actor guarantee. This is correct. However, if `PerformanceMetrics` is a reference type, internal mutations could still race. Verify `PerformanceMetrics` is value type or thread-safe.

### GLM's Questions:

1. **What happens at runtime if transcribe is called before initialize?**
   - **Answer:** Crash. Force unwrap `model!` at line 111 or 127 will throw `fatalError` and terminate the app. Fix: Guard-let pattern (FIX-001).

2. **How might we use Swift's safety features to check if model exists?**
   - **Answer:** Use `guard let` inside the actor context:
     ```swift
     guard let currentModel = model else {
         throw ASRError.backendNotAvailable(backend: name)
     }
     ```
     This provides compile-time safety and explicit error handling.

3. **If app records at 44.1kHz or 32-bit Float, how does this affect duration?**
   - **Answer:** Wrong duration. Formula `audio.count / 16000.0 / 2.0` assumes 16kHz/16-bit. 44.1kHz/32-bit input would give ~3.75x incorrect duration. However, `resampleAudio()` handles conversion. Fix: Use `loadAudioArray` sample rate and `audioData.shape[0]` (FIX-004).

4. **What problems could hardcoded 0.95 confidence cause?**
   - **Answer:**
   - User distrust: App says "95% confident" but transcription is wrong due to noise
   - Downstream logic errors: Filtering based on confidence threshold breaks
   - Misleading UI: Confidence indicators show high confidence for low-quality audio
   Fix: Return 0.0 to signal "unknown" (FIX-007).

5. **Does MLX provide probability scores?**
   - **Answer:** Not exposed in current API. `.info` event only provides `tokensPerSecond` and `peakMemoryUsage`. No token-level probabilities or logits available. Fix: Document limitation, return unknown value (FIX-007).

---

## Recommendations Summary

### Immediate Actions (P0 - Critical Safety)

1. **Implement FIX-001:** Replace all force unwraps with guard-let pattern (30 min)
2. **Implement FIX-002:** Fix streaming initialization race condition (1 hour)
3. **Implement FIX-003:** Add thread-safe audio buffer (4-6 hours, complex)

### Short-term Actions (P1 - Correctness & Performance)

4. **Implement FIX-004:** Fix duration calculation (30 min)
5. **Implement FIX-005:** Make isAvailable reflect actual state (15 min)
6. **Implement FIX-006:** Offload disk I/O to background (1 hour)
7. **Implement FIX-007:** Replace hardcoded confidence with 0.0 (15 min)
8. **Implement FIX-010:** Add proper timestamp handling (4-8 hours, complex)

### Medium-term Actions (P2 - Code Quality)

9. **Implement FIX-008:** Replace mutable config with immutable struct (2 hours)
10. **Implement FIX-009:** Preserve error context (15 min)
11. Remove `@preconcurrency` imports and add proper Sendable conformance (2 hours)

### Long-term Actions

12. Investigate MLXAudioSTT library for confidence score API
13. Add comprehensive instrumentation (metrics + logs)
14. Implement full test suite (unit + integration + manual)
15. Consider alternative to file-based audio loading if library updates support in-memory

---

## Conclusion

The three AI reviewers (Qwen, Kimi, GLM) achieved remarkable consensus on the critical issues:

** unanimous P0 priorities:**
- Force unwrapping (`model!`)
- Streaming race condition
- Thread safety in `feedAudio`

** unanimous P1 priorities:**
- Incorrect duration calculation
- Hardcoded confidence values
- `isAvailable` lying about state

The implementation uses modern Swift concurrency correctly in many areas (actor isolation, async/await), but critical gaps in defensive programming, thread safety, and honest state reporting pose production risks. Most fixes are low-to-medium effort with high impact.

**Recommended execution order:**
1. FIX-001 (30 min) - Prevent crashes
2. FIX-002 (1 hour) - Fix streaming race
3. FIX-004 (30 min) - Fix duration math
4. FIX-005 (15 min) - Fix isAvailable
5. FIX-007 (15 min) - Fix confidence honesty

Total immediate fix time: ~3.5 hours for P0/P1 safety/correctness issues.

---

**Document Version:** 2.0
**Last Updated:** 2026-02-18
**Review Coverage:** 100% (all 336 lines inspected)
**AI Reviewers:** Qwen, Kimi, GLM
**Synthesis Agent:** OpenCode
**Additional Review Date:** 2026-02-18
**Additional Reviewers:** Multiple AI agents (comprehensive architecture review)

---

## Post-Implementation Updates

All 10 fixes from the initial review have been implemented. An additional review was conducted which identified further improvements:

### NativeMLXBackend.swift Additional Fixes (Completed)

| Fix | Description | Status |
|-----|-------------|--------|
| MLX-001 | Hardcoded 16kHz in feedAudio duration - now uses `modelSampleRate` | ✅ |
| MLX-002 | Missing input validation in feedAudio - now returns `FeedAudioResult` enum | ✅ |
| MLX-003 | Buffer consumer polling - now uses adaptive sleep (5ms/20ms) | ✅ |

### OCRFrameCapture.swift Fixes (Completed)

| Fix | Description | Status |
|-----|-------------|--------|
| OCR-001 | MainActor isolation violation - OCR now runs on background Task.detached | ✅ |
| OCR-002 | No permission check - added checkPermissions() and requestPermission() | ✅ |
| OCR-003 | Memory-inefficient pipeline - direct CGImage→VNImageRequestHandler | ✅ |
| OCR-004 | Timer not adaptive - restartTimer() called on interval change | ✅ |
| OCR-005 | updateConfiguration logic bug - fixed enabled state transitions | ✅ |

### Test Coverage

- **NativeMLXBackendTests**: 43 tests
- **OCRFrameCaptureTests**: 18 tests
- **Total**: 163 tests pass, 0 failures, 12 skipped
