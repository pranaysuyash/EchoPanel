# Native Swift ASR Architecture Discovery
**EchoPanel — macapp/MeetingListenerApp**
**Date:** 2026-02-25
**Status:** Living document — verified against HEAD

---

## Evidence Key

| Symbol | Meaning |
|--------|---------|
| ✅ Observed | Directly verified in source code |
| ⚠️ Inferred | Reasonable conclusion from code structure; not directly tested at runtime |
| ❌ Not present | Explicitly absent from codebase |

---

## 1. Current State

✅ **`swift build` passes cleanly** (`Build complete! 0.96s`), confirmed 2026-02-25.

The full hybrid ASR subsystem — Native MLX backend, Python backend, feature flags, streaming, SwiftUI views, and tests — **compiles without errors or warnings** under Swift 6.0 strict concurrency rules on macOS 14+.

### What is built and working (compile-time confirmed)

| Artifact | State |
|----------|-------|
| `NativeMLXBackend` actor | ✅ Compiles |
| `HybridASRManager` @MainActor ObservableObject | ✅ Compiles |
| `PythonBackend` actor | ✅ Compiles |
| `FeatureFlagManager` | ✅ Compiles |
| `ASRBackendProtocol` + `SmartBackendSelection` | ✅ Compiles |
| `ASRTypes` (all enums, structs, errors, events) | ✅ Compiles |
| `ASRIntegration` + SwiftUI view helpers | ✅ Compiles |
| `BackendSelectionView` SwiftUI | ✅ Compiles |
| `ASRBackendStatusView` SwiftUI | ✅ Compiles |
| `NativeMLXBackendTests` (XCTest) | ✅ Compiles |
| mlx-audio-swift dependency resolved | ✅ Checked out at `.build/checkouts/mlx-audio-swift` |

### What has NOT been verified at runtime

- Model download from HuggingFace (`mlx-community/Qwen3-ASR-0.6B-4bit`)
- Actual MLX inference on device
- WebSocket connection to FastAPI server
- End-to-end audio → transcription pipeline

---

## 2. File Map

All ASR-related Swift files are under `macapp/MeetingListenerApp/Sources/ASR/`.

| File | Purpose | Evidence |
|------|---------|----------|
| `ASRTypes.swift` | All shared types: `BackendMode`, `BackendState`, `BackendStatus`, `BackendCapabilities`, `Language`, `TranscriptionConfig`, `TranscriptionSegment`, `TranscriptionResult`, `PerformanceMetrics`, `BackendComparisonResult`, `ASRError`, `TranscriptionEvent` | ✅ Observed |
| `ASRBackendProtocol.swift` | `ASRBackend` protocol (Actor-based), `BackendSelectionContext`, `NetworkQuality`, `PrivacyRequirement`, `BackendSelectionStrategy`, `SmartBackendSelection`, `SubscriptionTier` | ✅ Observed |
| `NativeMLXBackend.swift` | `MLXBackendConfiguration`, `ThreadSafeAudioBuffer`, `NativeMLXBackend` actor — the full on-device MLX implementation | ✅ Observed |
| `HybridASRManager.swift` | `HybridASRManager` @MainActor class — orchestration, routing, dual mode, fallback; `ASRContainer` dependency singleton | ✅ Observed |
| `PythonBackend.swift` | `PythonBackend` actor — WebSocket client to FastAPI server | ✅ Observed |
| `FeatureFlagManager.swift` | `FeatureFlagManager` ObservableObject — all feature flags, UserDefaults persistence, `FeatureFlagDebugViewModel` | ✅ Observed |
| `ASRIntegration.swift` | `ASRIntegration` singleton, `ASREnvironmentModifier`, `BackendStatusMenuItem`, `TranscriptionButton`, `TranscriptionDisplay`, `BackendBadge`, `ASRAudioCaptureIntegration` | ✅ Observed |
| `BackendSelectionView.swift` | Settings UI: backend picker, status cards, capabilities table, dev mode controls | ✅ Observed |
| `ASRBackendStatusView.swift` | Menu-bar-style status panel: `ASRBackendStatusView`, `StatusCard`, `StatusDot` | ✅ Observed |
| `ASR/README.md` | Brief module overview, usage snippet | ✅ Observed (excluded from build in Package.swift) |
| `Tests/NativeMLXBackendTests.swift` | XCTest coverage for config, buffer, error handling, metrics, events, capabilities | ✅ Observed |

### mlx-audio-swift dependency files used

Located at `.build/checkouts/mlx-audio-swift/Sources/`:

| File | Purpose | Evidence |
|------|---------|----------|
| `MLXAudioSTT/Streaming/StreamingInferenceSession.swift` | Streaming inference engine — **hardcoded to `Qwen3ASRModel`** | ✅ Observed |
| `MLXAudioSTT/Streaming/StreamingTypes.swift` | `StreamingConfig`, `DelayPreset`, `TranscriptionEvent` (mlx-audio-swift internal), `StreamingStats` | ✅ Observed |
| `MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | `Qwen3ASRModel` — `fromPretrained()`, `generateStream()`, `generate()`, `sampleRate`, streaming+batch capable | ✅ Observed |
| `MLXAudioSTT/Models/GLMASR/GLMASR.swift` | `GLMASRModel` — `fromPretrained()`, `generateStream()`, `generate()` — **batch-only** (no `StreamingInferenceSession` support) | ✅ Observed |
| `MLXAudioVAD/VADOutput.swift` | `DiarizationSegment`, `DiarizationOutput`, `StreamingState` (Sortformer) | ✅ Observed |
| `MLXAudioVAD/Models/Sortformer/Sortformer.swift` | Sortformer diarization model | ✅ Observed (file exists, not deeply read) |
| `MLXAudioSTT/MLXAudioSTT.swift` | Package entry stub (only 3 lines, imports Foundation) | ✅ Observed |

---

## 3. Package.swift — Dependencies and Targets

✅ File: `macapp/MeetingListenerApp/Package.swift`

```
platforms: [.macOS(.v14)]  // Required for MLX Audio Swift

dependencies:
  - swift-snapshot-testing (from: "1.17.4")  // testing only
  - mlx-audio-swift (branch: "main")          // pinned to main branch — NOT a stable tag

executableTarget "MeetingListenerApp":
  products: MLXAudioSTT, MLXAudioVAD

testTarget "MeetingListenerAppTests":
  depends on: MeetingListenerApp + SnapshotTesting
```

⚠️ **Risk**: `branch: "main"` means the dependency can drift. If mlx-audio-swift renames an API, the build will break on next `swift package update`.

**Packages imported by EchoPanel** (from mlx-audio-swift):
- `MLXAudioSTT` — STT models (Qwen3ASR, GLMASR), StreamingInferenceSession
- `MLXAudioVAD` — Sortformer diarization

**Packages NOT imported** (available in mlx-audio-swift but unused by EchoPanel):
- `MLXAudioTTS` — text-to-speech
- `MLXAudioSTS` — speech-to-speech (MossFormer2)
- `MLXAudioCodecs` — Mimi codec
- `MLXAudioCore` — utilities (note: `NativeMLXBackend.swift` imports `MLXAudioCore` directly for `Memory.clearCache()`)

---

## 4. HybridASRManager — Full Description

✅ File: `Sources/ASR/HybridASRManager.swift`
✅ Actor isolation: `@MainActor public final class HybridASRManager: ObservableObject, Sendable`

### 4.1 BackendMode Enum

Defined in `ASRTypes.swift` (not HybridASRManager.swift directly):

```swift
public enum BackendMode: String, CaseIterable, Identifiable {
    case autoSelect = "auto"     // Smart selection based on context
    case nativeMLX = "native"    // Force on-device MLX
    case pythonServer = "python" // Force cloud/Python backend
    case dualMode = "dual"       // Run both simultaneously (dev mode)
}
```

Mode persisted to `UserDefaults` under key `"hybrid_asr_mode"`.
Mode is restored on init if `subscriptionTier.canUseBackend(mode) || FeatureFlagManager.shared.isDevMode`.

### 4.2 SmartBackendSelection Logic

Defined in `ASRBackendProtocol.swift` as `struct SmartBackendSelection: BackendSelectionStrategy`.

Decision tree (evaluated in order, first match wins):

```
1. isOffline == true            → native
2. privacyRequirement == .strict → native
3. requiresDiarization == true  → python (if available) else native
4. requiresAdvancedNLP == true  → python (if available) else native
5. networkQuality not suitable  → native
6. default                      → native   ← privacy-first default
```

⚠️ **Note**: The default selection always returns native. Python is only selected when explicitly required by context (diarization or advanced NLP) and network is available.

### 4.3 Auto-Fallback (batch transcription)

In `transcribe()`:
```
1. Attempt transcription with selected backend
2. On failure:
   - If primary was NativeMLXBackend → try PythonBackend (if isAvailable)
   - If primary was PythonBackend    → try NativeMLXBackend (if isAvailable)
3. If fallback also unavailable → throw original error
```

❌ **Not implemented**: RTF-based fallback trigger (designed in session but not coded)
❌ **Not implemented**: OOM detection during model load (ASRError.initializationFailed is thrown but not inspected for memory cause)
❌ **Not implemented**: Consecutive error counting for automatic backend switch

### 4.4 Dual Mode

When `selectedMode == .dualMode`:

**Batch**: Primary result returned immediately; second backend runs in a fire-and-forget `Task`, result stored in `comparisonBuffer` (last 100).

**Streaming** (`runDualStreamTranscription`): Both `nativeBackend.startStreaming()` and `pythonBackend.startStreaming()` are called. Audio is fed to native via `NativeMLXBackend.feedAudio()`. Events from both streams are merged into a single output via `withThrowingTaskGroup`.

⚠️ **Gap**: In dual-stream mode, audio feeding to PythonBackend is commented as "Python backend handles audio via WebSocket" but no actual audio bytes are sent to the WebSocket during streaming.

### 4.5 `ASRContainer` Singleton

```swift
@MainActor public final class ASRContainer {
    public static let shared = ASRContainer()
    public private(set) lazy var hybridASRManager: HybridASRManager = {
        let native = NativeMLXBackend()          // default config = Qwen3-ASR-0.6B-4bit
        let python = PythonBackend()             // default = ws://localhost:8000/ws/transcribe
        return HybridASRManager(
            nativeBackend: native,
            pythonBackend: python,
            subscriptionTier: .free              // ← hardcoded; updated via updateSubscription()
        )
    }()
}
```

---

## 5. NativeMLXBackend — Full Description

✅ File: `Sources/ASR/NativeMLXBackend.swift`
✅ Actor isolation: `public actor NativeMLXBackend: ASRBackend`

### 5.1 MLXBackendConfiguration.default

```swift
MLXBackendConfiguration.default = MLXBackendConfiguration(
    modelId:          "mlx-community/Qwen3-ASR-0.6B-4bit",
    maxTokens:        1024,
    temperature:      0.0,      // greedy decoding
    chunkDuration:    30.0,     // seconds per batch chunk
    streamingDelayMs: 480       // DelayPreset.agent
)
```

All fields are `public` and mutable via `reloadModel(newConfiguration:)`.

### 5.2 Model Loading

```swift
model = try await Qwen3ASRModel.fromPretrained(configuration.modelId)
```

- Uses mlx-audio-swift's `Qwen3ASRModel.fromPretrained()` which downloads from HuggingFace Hub
- Model stored as `private var model: Qwen3ASRModel?`
- `modelSampleRate` captured from `model.sampleRate` (default 16000 before load)
- `Memory.clearCache()` called on unload / reload

### 5.3 StreamingInferenceSession Usage

```swift
let streamingConfig = StreamingConfig(
    decodeIntervalSeconds: 1.0,
    maxCachedWindows: 60,
    delayPreset: .custom(ms: configuration.streamingDelayMs),   // 480ms = agent preset
    language: config.language.displayName,
    temperature: configuration.temperature,
    maxTokensPerPass: configuration.maxTokens
)
let session = StreamingInferenceSession(model: currentModel, config: streamingConfig)
```

Session events are consumed via `for await event in session.events`.

**mlx-audio-swift `TranscriptionEvent` → app `TranscriptionEvent` mapping:**

| mlx-audio-swift event | App event emitted |
|-----------------------|------------------|
| `.displayUpdate(confirmed, provisional)` | `.partial(text: confirmed + provisional, confidence: 0.0)` |
| `.confirmed(text)` | `.final(segment: TranscriptionSegment(...))` |
| `.provisional` | *(ignored)* |
| `.stats(stats)` | *(logged if verboseLogging, not forwarded)* |
| `.ended(fullText)` | `.completed(result: TranscriptionResult(...))` |

⚠️ **Note**: The two `TranscriptionEvent` enums (mlx-audio-swift's and the app's) have the same name but live in different Swift modules (`MLXAudioSTT` vs `MeetingListenerApp`). Swift resolves them by context — the `session.events` loop uses the mlx-audio-swift type; the `continuation.yield()` calls use the app type.

### 5.4 ThreadSafeAudioBuffer

```swift
final class ThreadSafeAudioBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private let lock = NSLock()
    private let maxCapacity: Int   // default 32768 samples (~2.05s at 16kHz)

    func write(_ samples: [Float]) -> Bool   // returns false on overflow (drops)
    func read(upTo count: Int) -> [Float]    // FIFO read
    func clear()
    var count: Int
    var isOverflow: Bool
}
```

The buffer consumer `Task` (running in the actor) polls at:
- 5ms when recently active (< 10 consecutive empty reads)
- 20ms when idle
- Exits after 100 consecutive empty reads AND `isStreaming == false`

Reads up to 2048 samples per cycle and feeds them to `StreamingInferenceSession.feedAudio(samples:)`.

### 5.5 feedAudio API

```swift
public enum FeedAudioResult {
    case success
    case notStreaming
    case bufferOverflow
}

// Actor-isolated (requires await from outside the actor):
public func feedAudio(samples: [Float]) -> FeedAudioResult

// Convenience wrapper (discards result):
public func feedAudioSync(samples: [Float])
```

Audio must already be at the model's sample rate (16kHz). The buffer will silently drop chunks that exceed capacity (`maxCapacity = 32768`).

### 5.6 Resampling via AVAudioConverter

Used in `transcribe()` (batch mode) when the incoming WAV file's sample rate ≠ `model.sampleRate`:

```swift
private func resampleAudio(_ audio: MLXArray, from sourceSR: Int, to targetSR: Int) throws -> MLXArray
```

Process:
1. Creates `AVAudioFormat` for source and target
2. Creates `AVAudioConverter(from:to:)`
3. Allocates `AVAudioPCMBuffer` for input and output
4. Copies `[Float]` → PCM buffer via `memcpy`
5. Calls `converter.convert(to:error:withInputFrom:)`
6. Returns `MLXArray` of output Float samples

⚠️ **Gap**: Resampling is only done in batch `transcribe()`. The streaming `feedAudio()` path has NO resampling — caller must supply 16kHz mono Float32 samples.

### 5.7 Batch Transcription

Uses `Qwen3ASRModel.generateStream()`:

```swift
for try await event in currentModel.generateStream(
    audio: resampled,
    maxTokens: configuration.maxTokens,
    temperature: configuration.temperature,
    language: config.language.displayName,
    chunkDuration: configuration.chunkDuration
) { ... }
```

Events: `.token(String)`, `.info(STTGenerationInfo)`, `.result(STTOutput)`.
Tokens are concatenated; final `TranscriptionResult` has a single segment covering `[0, duration]`.
Confidence is always `0.0` (MLX models don't provide per-token confidence scores).

### 5.8 Capabilities (declared)

```swift
BackendCapabilities(
    supportsStreaming:       true,
    supportsBatch:           true,
    supportsDiarization:     false,  // ← no diarization in current native backend
    supportsOffline:         true,
    requiresNetwork:         false,
    supportedLanguages:      Language.allCases,  // 13 languages
    estimatedRTF:            0.08    // declared; not measured at runtime
)
```

---

## 6. PythonBackend — Full Description

✅ File: `Sources/ASR/PythonBackend.swift`
✅ Actor isolation: `public actor PythonBackend: ASRBackend`

### 6.1 Connection

```swift
serverURL = URL(string: "ws://\(serverHost):\(serverPort)/ws/transcribe")!
// Defaults: localhost:8000 → ws://localhost:8000/ws/transcribe
```

Uses `URLSessionWebSocketTask`. Connection verified by checking `webSocketTask?.state == .running` after a 500ms sleep (⚠️ fragile heuristic).

Reconnect: up to 3 attempts with 1-second delay between attempts.

### 6.2 Capabilities (declared)

```swift
BackendCapabilities(
    supportsStreaming:       true,
    supportsBatch:           true,
    supportsDiarization:     true,   // ← Python server supports diarization
    supportsOffline:         false,  // ← requires server running
    requiresNetwork:         true,
    supportedLanguages:      Language.allCases,
    estimatedRTF:            0.15
)
```

### 6.3 Batch Message Format (outgoing)

```json
{
  "type": "transcribe",
  "audio": "<base64-encoded WAV>",
  "language": "en",
  "diarize": false,
  "punctuation": true,
  "timestamps": true,
  "custom_vocabulary": []
}
```

### 6.4 Streaming Control Messages

```json
{ "type": "start_stream", "language": "en", "diarize": false, "punctuation": true }
{ "type": "stop_stream" }
```

### 6.5 Known Implementation Gaps

❌ **`isAvailable` always returns `true`** — hardcoded, regardless of connection state.

```swift
public nonisolated var isAvailable: Bool {
    return true  // Assume available, actual check done in initialize
}
```

⚠️ **`waitForResponse` is not properly correlated** — response IDs are generated but `handleServerMessage` never resolves `pendingResponses`. Batch transcription will always time out after `connectionTimeout` (30s) unless the server responds in a format that triggers `pendingResponses` resolution (which it never does in the current code).

⚠️ **No audio streaming bytes sent** — `startStreaming()` sends `start_stream` message but never forwards actual PCM samples to the server. The `receiveMessages` loop handles inbound events but there is no mechanism to push captured audio bytes through the WebSocket during a streaming session.

---

## 7. FeatureFlagManager — All Flags

✅ File: `Sources/ASR/FeatureFlagManager.swift`
✅ Singleton: `FeatureFlagManager.shared`
✅ Persistence: `UserDefaults.standard`, key prefix `"feature_"`

### 7.1 Flags and Current Defaults

| Flag | Type | Default | UserDefaults Key |
|------|------|---------|-----------------|
| `enableHybridBackend` | Bool | `true` | `feature_enableHybridBackend` |
| `enableNativeBackend` | Bool | `true` | `feature_enableNativeBackend` |
| `enablePythonBackend` | Bool | `true` | `feature_enablePythonBackend` |
| `enableBackendSelectionUI` | Bool | `true` | `feature_enableBackendSelectionUI` |
| `enableDualMode` | Bool | `false` | `feature_enableDualMode` |
| `nativeBackendRolloutPercentage` | Double | `100.0` | `feature_nativeBackendRolloutPercentage` |
| `forcedBackendMode` | `BackendMode?` | `nil` | `feature_forcedBackendMode` |
| `isDevMode` | Bool | `true` | `feature_isDevMode` |
| `enableVerboseLogging` | Bool | `true` | `feature_enableVerboseLogging` |
| `enableComparisonMetrics` | Bool | `true` | `feature_enableComparisonMetrics` |

⚠️ **`isDevMode` defaults to `true`** — This means ALL subscription checks are bypassed in the current build. All tiers can access all features. This must be set to `false` before production release.

⚠️ **`nativeBackendRolloutPercentage = 100.0`** — 100% of users get native backend in the current build.

### 7.2 Key Methods

```swift
shouldEnableNativeBackend() → Bool
// DevMode → true; else: enableHybridBackend && enableNativeBackend && random% ≤ rolloutPercentage

shouldEnablePythonBackend() → Bool
// DevMode → true; else: enableHybridBackend && enablePythonBackend

shouldEnableDualMode() → Bool
// DevMode → true; else: enableDualMode flag

effectiveBackendMode(_ requested: BackendMode) → BackendMode
// Returns forcedBackendMode if set, else requested
```

---

## 8. mlx-audio-swift API Constraints (CRITICAL)

These constraints were discovered by reading the actual source files in `.build/checkouts/mlx-audio-swift/`. They have **hard architectural implications** for any future backend work.

### 8.1 StreamingInferenceSession is HARDCODED to Qwen3ASRModel

```swift
// StreamingInferenceSession.swift line 70, 92:
public class StreamingInferenceSession: @unchecked Sendable {
    private let model: Qwen3ASRModel   // ← Qwen3 only, no protocol

    public init(model: Qwen3ASRModel, config: StreamingConfig = StreamingConfig())
```

`GLMASRModel` **cannot** use `StreamingInferenceSession`. This is not a limitation of EchoPanel's code — it is baked into the mlx-audio-swift library.

### 8.2 Available Model Classes

| Model Class | Streaming via StreamingInferenceSession | Batch via generateStream | Notes |
|-------------|----------------------------------------|--------------------------|-------|
| `Qwen3ASRModel` | ✅ Yes | ✅ Yes | Primary streaming model |
| `GLMASRModel` | ❌ No | ✅ Yes (own generateStream) | Batch-only; different event types |

**Qwen3ASRModel.generateStream signature:**
```swift
func generateStream(
    audio: MLXArray,
    maxTokens: Int,
    temperature: Float,
    language: String,       // e.g. "English"
    chunkDuration: Float    // seconds
) -> AsyncThrowingStream<STTGeneration, Error>
```
Events: `.token(String)`, `.info(STTGenerationInfo)`, `.result(STTOutput)`

**GLMASRModel.generateStream signature:**
```swift
func generateStream(
    audio: MLXArray,
    maxTokens: Int = 128,
    temperature: Float = 0.0,
    topP: Float = 0.95
    // ← NO language param
    // ← NO chunkDuration param
) -> AsyncThrowingStream<STTGeneration, Error>
```
Same event types (STTGeneration: `.token`, `.info`, `.result`).

### 8.3 StreamingConfig Fields

```swift
public struct StreamingConfig: Sendable {
    var decodeIntervalSeconds: Double        // default 1.0
    var boundaryDecodeIntervalSeconds: Double // default 0.2 (faster at 8s boundaries)
    var boundaryBoostSeconds: Double         // default 1.0
    var encoderWindowOverlapSeconds: Double  // default 1.0
    var maxCachedWindows: Int                // default 60 (~8m of audio)
    var delayPreset: DelayPreset             // .realtime(200ms), .agent(480ms), .subtitle(2400ms), .custom(ms:)
    var language: String                     // default "English"
    var temperature: Float                   // default 0.0
    var maxTokensPerPass: Int                // default 512
    var minAgreementPasses: Int              // default 2
    var boundaryMinAgreementPasses: Int      // default 3
    var maxDecodeWindows: Int                // default 1
    var finalizeCompletedWindows: Bool       // default true
}
```

### 8.4 mlx-audio-swift TranscriptionEvent (Streaming)

⚠️ **Name collision**: mlx-audio-swift's `StreamingTypes.swift` defines `TranscriptionEvent`; so does EchoPanel's `ASRTypes.swift`. Different modules, but importers must be careful.

**mlx-audio-swift `TranscriptionEvent`** (from `StreamingTypes.swift`):
```swift
public enum TranscriptionEvent: Sendable {
    case provisional(text: String)
    case confirmed(text: String)
    case displayUpdate(confirmedText: String, provisionalText: String)
    case stats(StreamingStats)
    case ended(fullText: String)
}
```

**App `TranscriptionEvent`** (from `ASRTypes.swift`):
```swift
public enum TranscriptionEvent {
    case started
    case partial(text: String, confidence: Double)
    case final(segment: TranscriptionSegment)
    case completed(result: TranscriptionResult)
    case error(ASRError)
    case cancelled
}
```

`NativeMLXBackend.startStreaming()` correctly handles this by context: `session.events` yields the mlx-audio-swift type; `continuation.yield()` uses the app type.

### 8.5 MLXAudioVAD — Sortformer Diarization Types

From `MLXAudioVAD/VADOutput.swift`:

```swift
public struct DiarizationSegment: Sendable {
    public let start: Float      // seconds
    public let end: Float        // seconds
    public let speaker: Int      // 0-indexed speaker ID
}

public struct DiarizationOutput: Sendable {
    public let segments: [DiarizationSegment]
    public let speakerProbs: MLXArray?
    public let numSpeakers: Int
    public let totalTime: Double
    public var state: StreamingState?    // optional streaming continuation state

    public var text: String  // RTTM format output
}

public struct StreamingState: Sendable {
    public var spkcache: MLXArray        // (1, cache_frames, emb_dim)
    public var spkcachePreds: MLXArray   // (1, cache_frames, n_spk)
    public var fifo: MLXArray            // (1, fifo_frames, emb_dim)
    public var fifoPreds: MLXArray       // (1, fifo_frames, n_spk)
    public var framesProcessed: Int
    public var meanSilEmb: MLXArray      // (1, emb_dim)
    public var nSilFrames: MLXArray      // (1,)
}
```

❌ **No high-level diarization manager** — The `Sortformer` model and `DiarizationOutput` types exist but there is no pre-built `DiarizationManager` or easy one-call API equivalent to `Qwen3ASRModel.fromPretrained()`. Integration requires direct model instantiation.

### 8.6 Available mlx-audio-swift Packages (Full List)

| Package | Contents | Used by EchoPanel |
|---------|----------|-------------------|
| `MLXAudioCore` | `Memory.clearCache()`, `AudioUtils`, `DSP`, `ModelUtils`, `AudioPlayerManager` | ✅ Yes (Memory.clearCache) |
| `MLXAudioCodecs` | Mimi codec | ❌ No |
| `MLXAudioSTT` | Qwen3ASR, GLMASR, StreamingInferenceSession | ✅ Yes |
| `MLXAudioVAD` | Sortformer (DiarizationOutput, StreamingState) | ✅ Linked (not yet called) |
| `MLXAudioTTS` | Qwen3TTS, PocketTTS, Marvis, Soprano, LlamaTTS | ❌ No |
| `MLXAudioSTS` | MossFormer2 speech enhancement/separation | ❌ No |

---

## 9. ASR Model Fallback Chain (Designed This Session)

This fallback chain was **designed** in the 2026-02-25 session. The P1 model is **wired in** via `MLXBackendConfiguration.default`. P2–P4 are **designed but not yet implemented** in code.

```
P1: mlx-community/Qwen3-ASR-0.6B-4bit
    Mode: streaming + batch
    RTF target: ~0.08x (very fast)
    Memory: ~0.3GB
    Notes: DEFAULT — currently wired in NativeMLXBackend

P2: mlx-community/Qwen3-ASR-1.7B-4bit
    Mode: streaming + batch
    RTF target: ~0.2x
    Memory: ~1.0GB
    Notes: Accuracy upgrade, same StreamingInferenceSession API

P3: mlx-community/Qwen3-ASR-1.7B-8bit
    Mode: streaming + batch
    RTF target: ~0.3x
    Memory: ~1.8GB
    Notes: Best native quality; requires NativeMLXBackend reloadModel()

P4: mlx-community/GLM-ASR-Nano-2512-4bit (placeholder name — verify HF slug)
    Mode: batch-only
    RTF target: unknown
    Memory: unknown
    Notes: Uses GLMASRModel.generateStream() — different API, no language param,
           no StreamingInferenceSession; diversity fallback for edge cases

P5: PythonBackend
    Mode: streaming + batch + diarization
    RTF target: ~0.15x (declared)
    Notes: Ultimate fallback; requires running FastAPI server + network
```

### Fallback Trigger Conditions (Designed, Not Implemented)

| Trigger | Action |
|---------|--------|
| OOM error during `Qwen3ASRModel.fromPretrained()` | Retry with smaller model (P2→P1, P3→P2) |
| RTF > 2.0 for 3 consecutive chunks | Escalate to faster model or P5 |
| 3 consecutive `ASRError` from current model | Try next model in chain |
| `ASRError.initializationFailed` on all native models | Fall to P5 |

❌ **None of these triggers are currently implemented.** Current code only has a single catch-all fallback in `HybridASRManager.transcribe()` that tries the opposite backend (native ↔ python) once.

---

## 10. Open Gaps in Existing Code

### 10.1 Audio Not Fed to NativeMLXBackend in Single-Backend Streaming Mode

`HybridASRManager.transcribeStream()` (single-backend path):

```swift
let backend = await self.currentBackend()
let stream = await backend.startStreaming(config: config)
for try await event in stream { ... }
// ← audioStream parameter is never consumed here!
```

The `audioStream: AsyncStream<[Float]>` parameter is completely ignored in the single-backend branch. Audio must be fed separately via `NativeMLXBackend.feedAudio()` through `ASRAudioCaptureIntegration`. The dual mode path correctly feeds audio, but the single mode path does not.

### 10.2 PythonBackend.isAvailable Always Returns true

```swift
public nonisolated var isAvailable: Bool {
    return true  // Assume available, actual check done in initialize
}
```

This means `HybridASRManager`'s auto-fallback check `if fallback.isAvailable` will always attempt to use PythonBackend even when the server is not running.

### 10.3 waitForResponse Never Resolves

`PythonBackend.waitForResponse()` creates a continuation in `pendingResponses` but `handleServerMessage()` never calls `pendingResponses[id]?.resume(...)`. Batch transcription will always time out (30s). This is a **complete functional gap** in the Python batch path.

### 10.4 WER Calculation is Set-Based, Not Sequence-Aligned

```swift
private func calculateWER(_ reference: String, _ hypothesis: String) -> Double {
    let refSet = Set(refWords)
    let hypSet = Set(hypWords)
    let errors = refSet.symmetricDifference(hypSet).count  // bag-of-words, not WER
```

Real WER requires dynamic programming (Levenshtein distance on word sequences). The current implementation is a bag-of-words similarity metric. The `accuracyMatch: wer < 0.1` threshold may be unreliable.

### 10.5 MLXAudioVAD Linked but Not Called

`MLXAudioVAD` is in `Package.swift` target dependencies but no code in EchoPanel calls any Sortformer API. The package is compiled but dormant.

### 10.6 ASRContainer SubscriptionTier Hardcoded to .free

```swift
HybridASRManager(
    nativeBackend: native,
    pythonBackend: python,
    subscriptionTier: .free  // Will be updated from actual subscription
)
```

`ASRContainer.updateSubscription()` exists but is never called from app code. All users currently get `.free` tier (though `isDevMode = true` bypasses all tier checks anyway).

### 10.7 No RTF-Based Auto-Scaling

`PerformanceMetrics` tracks `realtimeFactor` across requests but nothing reads it to trigger model swaps or backend switches. The metrics are display-only.

### 10.8 Streaming Audio Path Not Resampled

`feedAudio(samples:)` assumes input is already at `modelSampleRate` (16kHz mono Float32). There is no guard or resampling in this path. If `AudioCaptureManager` provides 44.1kHz or 48kHz samples, the output will be garbled.

---

## 11. SubscriptionTier Integration

### 11.1 Tier Definitions

Defined in `ASRBackendProtocol.swift`:

```swift
public enum SubscriptionTier: String, CaseIterable {
    case free        // "free"
    case pro         // "pro"
    case proCloud    // "pro_cloud"
    case enterprise  // "enterprise"
}
```

### 11.2 Backend Mode Gate (canUseBackend)

| Tier | autoSelect | nativeMLX | pythonServer | dualMode |
|------|-----------|-----------|--------------|----------|
| free | ✅ | ❌ | ❌ | ❌ |
| pro | ✅ | ✅ | ❌ | ❌ |
| proCloud | ✅ | ✅ | ✅ | ✅ |
| enterprise | ✅ | ✅ | ✅ | ✅ |
| *devMode* | ✅ | ✅ | ✅ | ✅ |

`isDevMode = true` bypasses ALL tier checks. This is the current state.

### 11.3 Feature Gates

```swift
canUseDiarization() → Bool
// isDevMode || (proCloud or enterprise)

canUseDualMode() → Bool
// isDevMode || enterprise only
```

### 11.4 Where Gates Are Enforced

- **HybridASRManager.init()**: Restores saved mode only if `subscriptionTier.canUseBackend(mode)`
- **HybridASRManager.isModeAllowed()**: Checked in `BackendSelectionView` before switching
- **HybridASRManager.compareBackends()**: Checks `FeatureFlagManager.shouldEnableDualMode()`
- **BackendSelectionView**: `onChange(of: selectedMode)` reverts and shows upgrade prompt if `!isModeAllowed`

### 11.5 Tier Update Path

```swift
// In ASRContainer:
public func updateSubscription(_ tier: SubscriptionTier) {
    // Creates a NEW HybridASRManager — discards current state
    hybridASRManager = HybridASRManager(
        nativeBackend: NativeMLXBackend(),
        pythonBackend: PythonBackend(),
        subscriptionTier: tier
    )
}
```

⚠️ This creates fresh backends — any loaded models will be discarded (not just unloaded, but garbage collected). Consider lazy re-initialization or pausing streaming before subscription update.

---

## 12. Concurrency Architecture Summary

| Component | Isolation | Notes |
|-----------|-----------|-------|
| `NativeMLXBackend` | `actor` | All state isolated; `feedAudio()` returns immediately (actor hop) |
| `PythonBackend` | `actor` | All state isolated; WebSocket callbacks hop back via `Task { await self... }` |
| `HybridASRManager` | `@MainActor` class | All `@Published` properties on MainActor |
| `FeatureFlagManager` | `@MainActor` ObservableObject | `@Published` flags; `shared` is nonisolated |
| `ASRContainer` | `@MainActor` | Singleton; lazy init on MainActor |
| `ThreadSafeAudioBuffer` | `@unchecked Sendable` | Uses `NSLock` for manual synchronization |
| `StreamingInferenceSession` | `@unchecked Sendable` | Uses `OSAllocatedUnfairLock` internally |
| `MLXBackendConfiguration` | `Sendable` struct | Value type, safe across actors |

---

## 13. Data Flow Diagram

```
[Audio Capture] ──[Float32 16kHz mono]──▶ NativeMLXBackend.feedAudio()
                                              │
                                         ThreadSafeAudioBuffer (32768 samples)
                                              │ (polled every 5–20ms)
                                         bufferConsumer Task
                                              │ read(upTo: 2048)
                                              ▼
                                    StreamingInferenceSession.feedAudio(samples:)
                                              │
                                    [mlx-audio-swift internal]
                                    IncrementalMelSpectrogram
                                    StreamingEncoder
                                    Qwen3ASRModel decoder
                                              │
                                    AsyncStream<MLXAudioSTT.TranscriptionEvent>
                                              │
                                    NativeMLXBackend maps to app TranscriptionEvent
                                              │
                                    AsyncThrowingStream<App.TranscriptionEvent, Error>
                                              │
                                    HybridASRManager.handleStreamEvent()
                                              │
                                    @MainActor: streamingText updated
                                              │
                                    SwiftUI: TranscriptionDisplay refreshes
```

```
[Audio Data]──▶ HybridASRManager.transcribe()
                    │
              SmartBackendSelection (or forced mode)
                    │
              ┌─────┴─────┐
         NativeMLXBackend  PythonBackend
              │                  │
        Qwen3ASRModel        URLSession WebSocket
        .generateStream()    ws://localhost:8000/ws/transcribe
              │                  │
        TranscriptionResult   TranscriptionResult
              └─────┬─────┘
              (primary used; fallback if error)
                    │
              HybridASRManager.currentResult published
```

---

## 14. Test Coverage Summary

✅ `Tests/NativeMLXBackendTests.swift` — 35+ test cases covering:

| Category | Tests |
|----------|-------|
| MLXBackendConfiguration | default values, custom values, Sendable |
| NativeMLXBackend init | name, isAvailable=false before init, capabilities |
| ThreadSafeAudioBuffer | write/read, overflow detection, clear, concurrent access, thread safety |
| Error handling | transcribe without init throws backendNotAvailable, streaming returns error stream |
| State management | health(), isStreaming=false initially |
| Confidence values | default=1.0, custom preserved |
| Duration calculation | 16kHz, 44.1kHz |
| PerformanceMetrics | recordSuccess, multiple successes, recordError, realtimeFactor |
| ASRError descriptions | all error cases |
| TranscriptionEvent | all 6 event types |
| TranscriptionConfig | defaults, custom |
| BackendStatus | defaults, custom |
| FeedAudioResult | all 3 cases; returns .notStreaming when not active |
| Language | displayNames, allCases count=13 |
| BackendCapabilities | nativeDefault, pythonDefault |

❌ No tests for: HybridASRManager, PythonBackend, FeatureFlagManager, SmartBackendSelection, SubscriptionTier, ASRIntegration, SwiftUI views.

---

## 15. Quick Reference: Critical API Signatures

```swift
// Initialize the full ASR system
await ASRContainer.shared.hybridASRManager.initialize()

// Batch transcription with auto-backend and fallback
let result = try await manager.transcribe(audio: wavData, config: TranscriptionConfig())

// Streaming (caller must feed audio separately via feedAudio)
let stream = manager.transcribeStream(audioStream: audioStream, config: config)
for try await event in stream { ... }

// Feed audio to native backend (must be 16kHz mono Float32)
let nativeBackend = manager.nativeBackend as! NativeMLXBackend
await nativeBackend.feedAudio(samples: float32Samples)

// Reload with different model
try await nativeBackend.reloadModel(newConfiguration: MLXBackendConfiguration(
    modelId: "mlx-community/Qwen3-ASR-1.7B-4bit"
))

// Compare both backends on same audio
let comparison = try await manager.compareBackends(audio: wavData)
// comparison.wordErrorRate, comparison.speedup, comparison.accuracyMatch

// Feature flags (dev)
FeatureFlagManager.shared.enableAllForDev()
FeatureFlagManager.shared.forcedBackendMode = .nativeMLX
```

---

*Document generated from code inspection of HEAD on 2026-02-25. All `✅ Observed` facts verified by reading source. Runtime behavior not verified.*
