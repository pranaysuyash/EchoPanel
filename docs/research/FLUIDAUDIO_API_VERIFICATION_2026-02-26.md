# FluidAudio API Verification Report

**Date:** 2026-02-26
**Repo:** https://github.com/FluidInference/FluidAudio (commit `064daacd`)
**Version:** 0.7.0 (per CITATION.cff)
**Stars:** 1,560 | **Forks:** 191 | **Open Issues:** 3 (only 1 non-trivial)
**License:** MIT (per repo)

---

## Executive Summary

FluidAudio is **real, production-grade, and actively maintained**. The Opus review concern that claims were "potentially speculative" is **not warranted** — FluidAudio does provide diarization + VAD via CoreML/ANE in pure Swift. However, our existing research doc (`NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`) has **multiple incorrect API signatures and initialization patterns**. This report corrects them.

**Verdict: Keep FluidAudio as primary diarization + VAD path. Fix API usage examples.**

---

## Claim-by-Claim Verification

### 1. `DiarizerManager` exists

**Status: ✅ VERIFIED**

- **File:** `Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift`
- **Declaration:** `public final class DiarizerManager` (not an actor, not Sendable — standard class)
- **Init:** `public init(config: DiarizerConfig = .default)` — takes `DiarizerConfig`, NOT a model enum

**⚠️ Our doc claimed:** `let diarizer = try await DiarizerManager(model: .sortformer)`
**Actual API:** Init is synchronous, takes `DiarizerConfig`, not a model selector. Sortformer is a completely separate class (`SortformerDiarizer`).

### 2. `VadManager` exists

**Status: ✅ VERIFIED**

- **File:** `Sources/FluidAudio/VAD/VadManager.swift`
- **Declaration:** `public actor VadManager` — note: it's an **actor**, not a class
- **Init variants:**
  - `public init(config: VadConfig = .default) async throws` — auto-downloads model
  - `public init(config: VadConfig = .default, vadModel: MLModel)` — pre-loaded model
  - `public init(config: VadConfig = .default, modelDirectory: URL) async throws` — from directory

**⚠️ Our doc claimed:** `let vad = try await VadManager(model: .sileroV4)` with callback-based API
**Actual API:** No `.sileroV4` enum. Init auto-loads Silero model. Processing is async/await, not callback.

### 3. CoreML/ANE based

**Status: ✅ VERIFIED**

- Models are `.mlmodelc` format (compiled CoreML bundles), not ONNX
- `VadConfig.computeUnits` defaults to `.cpuAndNeuralEngine`
- `ANEMemoryOptimizer` class used in both VadManager and DiarizerManager
- Explicit ANE-aligned `MLMultiArray` buffer management throughout

**Source:** `VadTypes.swift:9` — `computeUnits: MLComputeUnits = .cpuAndNeuralEngine`

### 4. Models bundled or downloaded at runtime

**Status: ✅ VERIFIED — Downloaded at runtime from HuggingFace**

- Models are NOT bundled in the SPM package
- `DownloadUtils.swift` handles download from HuggingFace repos
- Model repos enumerated in `ModelNames.swift`:
  - VAD: `FluidInference/silero-vad-coreml`
  - Diarizer: `FluidInference/speaker-diarization-coreml`
  - Sortformer: `FluidInference/diar-streaming-sortformer-coreml`
- Models cached locally after first download at `~/Library/Application Support/FluidAudio/Models/`
- Auth via `HF_TOKEN` env var for private repos

**Source:** `DownloadUtils.swift:92-107`, `ModelNames.swift:1-14`

### 5. Source code or binary framework

**Status: ✅ VERIFIED — Source code (with one binary target)**

- `Package.swift` defines FluidAudio as a source target (not `.binaryTarget`)
- One binary dependency: `ESpeakNG.xcframework` (for TTS only — irrelevant to diarization/VAD)
- Dependencies: `huggingface/swift-transformers` (for tokenizers)
- C++ interop: `FastClusterWrapper` and `MachTaskSelfWrapper` (bundled C/C++ source)

**Source:** `Package.swift:17-42`

### 6. macOS version requirement

**Status: ✅ VERIFIED — macOS 14 (Sonoma) / iOS 17**

```swift
platforms: [
    .macOS(.v14),
    .iOS(.v17),
]
```
**Source:** `Package.swift:6-9`

### 7. Model formats

**Status: ✅ VERIFIED — CoreML `.mlmodelc` (compiled)**

All models use `.mlmodelc` (compiled CoreML) format:
- `pyannote_segmentation.mlmodelc` — segmentation model
- `wespeaker_v2.mlmodelc` — speaker embedding model
- `silero_vad.mlmodelc` — VAD model
- Sortformer uses `.mlpackage` compiled at load time

**Source:** `ModelNames.swift:105-111` (Diarizer), `ModelNames.swift:125-127` (VAD)

### 8. Swift tools version

**Status:** Swift 6.0 (`swift-tools-version: 6.0`)
- Full Swift 6 strict concurrency support
- C++17 interop (`cxxLanguageStandard: .cxx17`)

**Source:** `Package.swift:1`

### 9. Production usage

**Status: ✅ VERIFIED — Extensively used in production**

20+ production apps listed in README showcase, including:
- **Voice Ink** — Parakeet ASR
- **Spokenly** — ASR + speaker diarization
- **Slipbox** — meeting assistant with diarization
- **BoltAI** — content writing
- **SamScribe** — open-source meeting transcription with cross-session speaker recognition
- **Senko** — Python + FluidAudio diarization pipeline

HuggingFace badge claims 500k+ model downloads.

---

## Actual Public API Surface

### DiarizerManager (Online/Streaming Diarization)

**File:** `Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift`

```swift
public final class DiarizerManager {
    // Properties
    public var segmentationModel: MLModel?  // getter only
    public let segmentationProcessor: SegmentationProcessor
    public var embeddingExtractor: EmbeddingExtractor?
    public let speakerManager: SpeakerManager
    public var isAvailable: Bool

    // Init
    public init(config: DiarizerConfig = .default)

    // Lifecycle
    public func initialize(models: consuming DiarizerModels)
    public func cleanup()

    // Core API
    public func performCompleteDiarization<C>(
        _ samples: C, sampleRate: Int = 16000, atTime startTime: TimeInterval = 0
    ) throws -> DiarizationResult
    where C: RandomAccessCollection, C.Element == Float, C.Index == Int

    // Validation
    public func validateEmbedding(_ embedding: [Float]) -> Bool
    public func validateAudio<C>(_ samples: C) -> AudioValidationResult
    where C: Collection, C.Element == Float

    // Known speakers
    public func initializeKnownSpeakers(_ speakers: [Speaker])
}
```

**Model Loading (separate step):**
```swift
// Auto-download from HuggingFace
let models = try await DiarizerModels.download()
// Or from local directory
let models = try await DiarizerModels.load(from: directoryURL)
// Or from pre-downloaded files
let models = try await DiarizerModels.load(
    localSegmentationModel: segURL,
    localEmbeddingModel: embURL
)

let diarizer = DiarizerManager()
diarizer.initialize(models: models)
let result = try diarizer.performCompleteDiarization(audioSamples)
```

### OfflineDiarizerManager (Batch/Offline Diarization)

**File:** `Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift`

```swift
@available(macOS 14.0, iOS 17.0, *)
public final class OfflineDiarizerManager {
    public init(config: OfflineDiarizerConfig = .default)
    public func initialize(models: OfflineDiarizerModels)
    public func prepareModels(
        directory: URL? = nil,
        configuration: MLModelConfiguration? = nil,
        forceRedownload: Bool = false
    ) async throws
    public func process(audio: [Float]) async throws -> DiarizationResult
    public func process(_ url: URL) async throws -> DiarizationResult
    public func process(
        audioSource: StreamingAudioSampleSource,
        audioLoadingSeconds: TimeInterval
    ) async throws -> DiarizationResult
}
```

### SortformerDiarizer (Streaming Diarization)

**File:** `Sources/FluidAudio/Diarizer/Sortformer/SortformerDiarizerPipeline.swift`

```swift
public final class SortformerDiarizer {
    public var timeline: SortformerTimeline
    public var isAvailable: Bool
    public var state: SortformerStreamingState
    public var numFramesProcessed: Int
    public let config: SortformerConfig

    public init(
        config: SortformerConfig = .default,
        postProcessingConfig: SortformerPostProcessingConfig = .default
    )
    public func initialize(mainModelPath: URL) async throws
    public func initialize(models: SortformerModels)
    public func reset()
    public func processSamples(_ audioSamples: [Float]) throws -> SortformerChunkResult?
    public func processComplete(_ audioSamples: [Float]) throws -> SortformerTimeline
}
```
- 4 fixed speaker slots, ~11% DER on DI-HARD III
- Separate from `DiarizerManager` — different class, different pipeline

### VadManager

**File:** `Sources/FluidAudio/VAD/VadManager.swift`

```swift
public actor VadManager {
    // Constants
    public static let chunkSize = 4096      // 256ms at 16kHz
    public static let sampleRate = 16000

    // Properties
    public let config: VadConfig
    public var isAvailable: Bool
    public var currentConfig: VadConfig

    // Init variants
    public init(config: VadConfig = .default) async throws                    // auto-download
    public init(config: VadConfig = .default, vadModel: MLModel)              // pre-loaded
    public init(config: VadConfig = .default, modelDirectory: URL) async throws  // from dir

    // Batch processing
    public func process(_ url: URL) async throws -> [VadResult]
    public func process(_ audioBuffer: AVAudioPCMBuffer) async throws -> [VadResult]
    public func process(_ samples: [Float]) async throws -> [VadResult]

    // Streaming
    public func makeStreamState() -> VadStreamState
    public func processStreamingChunk(
        _ audioChunk: [Float],
        state: VadStreamState,
        config: VadSegmentationConfig = .default,
        returnSeconds: Bool = false,
        timeResolution: Int = 1
    ) async throws -> VadStreamResult

    // Speech segmentation
    public func segmentSpeech(
        _ samples: [Float],
        config: VadSegmentationConfig = .default
    ) async throws -> [VadSegment]
    public func segmentSpeechAudio(
        _ samples: [Float],
        config: VadSegmentationConfig = .default
    ) async throws -> [[Float]]
}
```

---

## Key Types

### DiarizerConfig
```swift
public struct DiarizerConfig: Sendable {
    public var clusteringThreshold: Float   // default: 0.7
    public var minSpeechDuration: Float     // default: 1.0s
    public var minEmbeddingUpdateDuration: Float  // default: 2.0s
    public var minSilenceGap: Float         // default: 0.5s
    public var numClusters: Int             // default: -1 (auto)
    public var debugMode: Bool              // default: false
    public var chunkDuration: Float         // default: 10.0s
    public var chunkOverlap: Float          // default: 0.0s
}
```

### VadConfig
```swift
public struct VadConfig: Sendable {
    public var defaultThreshold: Float      // default: 0.85
    public var debugMode: Bool              // default: false
    public var computeUnits: MLComputeUnits // default: .cpuAndNeuralEngine
}
```

### DiarizationResult
```swift
public struct DiarizationResult: Sendable {
    public let segments: [TimedSpeakerSegment]
    public let speakerDatabase: [String: [Float]]?
    public let timings: PipelineTimings?
}
```

### TimedSpeakerSegment
```swift
public struct TimedSpeakerSegment: Sendable, Identifiable {
    public let speakerId: String
    public let embedding: [Float]
    public let startTimeSeconds: Float
    public let endTimeSeconds: Float
    public let qualityScore: Float
    public var durationSeconds: Float { endTimeSeconds - startTimeSeconds }
}
```

### VadResult / VadStreamResult
```swift
public struct VadResult: Sendable {
    public let probability: Float
    public let isVoiceActive: Bool
    public let processingTime: TimeInterval
    public let outputState: VadState
}

public struct VadStreamResult: Sendable {
    public let state: VadStreamState
    public let event: VadStreamEvent?    // .speechStart or .speechEnd
    public let probability: Float
}
```

---

## Errors in Our Existing Research Doc

### `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` — Lines 59-63

**Claimed API:**
```swift
import FluidAudio
let diarizer = try await DiarizerManager(model: .sortformer)
let segments = try await diarizer.diarize(audioURL: sessionURL)
```

**Actual API:**
```swift
import FluidAudio

// Option A: Online diarization (pyannote-based segmentation + wespeaker embeddings)
let models = try await DiarizerModels.download()
let diarizer = DiarizerManager()
diarizer.initialize(models: models)
let result = try diarizer.performCompleteDiarization(audioSamples)
for seg in result.segments {
    print("\(seg.speakerId): \(seg.startTimeSeconds)–\(seg.endTimeSeconds)")
}

// Option B: Offline diarization (VBx clustering, pyannote parity)
let offlineDiarizer = OfflineDiarizerManager()
try await offlineDiarizer.prepareModels()
let result = try await offlineDiarizer.process(audio: audioSamples)

// Option C: Sortformer streaming diarization (4 speakers, real-time)
let sortformer = SortformerDiarizer()
try await sortformer.initialize(mainModelPath: modelURL)
for chunk in audioChunks {
    if let result = try sortformer.processSamples(chunk) { ... }
}
```

**Key differences:**
1. `DiarizerManager` init is **synchronous**, takes `DiarizerConfig`, not a model enum
2. No `.diarize(audioURL:)` method — it's `performCompleteDiarization(_:)` taking `[Float]`
3. Sortformer is a **separate class** `SortformerDiarizer`, not a mode of `DiarizerManager`
4. Model loading is a **separate step** via `DiarizerModels.download()`

### `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` — Lines 76-82

**Claimed API:**
```swift
let vad = try await VadManager(model: .sileroV4)
vad.processAudioChunk(samples: pcmBuffer) { event in
    switch event { ... }
}
```

**Actual API:**
```swift
let vad = try await VadManager()  // auto-downloads Silero model

// Batch mode
let results = try await vad.process(audioURL)

// Streaming mode
var streamState = vad.makeStreamState()
let result = try await vad.processStreamingChunk(
    audioChunk,
    state: streamState,
    config: .default,
    returnSeconds: true
)
streamState = result.state
if let event = result.event {
    switch event.kind {
    case .speechStart: print("Speech started at \(event.time ?? 0)")
    case .speechEnd:   print("Speech ended at \(event.time ?? 0)")
    }
}
```

**Key differences:**
1. No `.sileroV4` model selector — it auto-loads Silero
2. `VadManager` is an **actor**, not a class — all methods are async
3. No callback-based API — returns `VadStreamResult` with optional event
4. Streaming uses explicit state passing (`VadStreamState`)

---

## Risk Assessment

### ✅ Low Risk

| Factor | Assessment |
|---|---|
| **Maturity** | 1,560 stars, 191 forks, 20+ production apps. Active since June 2025. |
| **Maintenance** | Commits every few days. Community PRs merged regularly. |
| **API stability** | Core classes (`DiarizerManager`, `VadManager`) stable since v0.5+. New features are additive (Sortformer, Qwen3-ASR, PocketTTS). |
| **Binary risk** | Source code, not binary framework. Only ESpeakNG.xcframework (TTS — we don't need). |
| **Platform** | macOS 14+ is fine for EchoPanel (we target macOS 14+). |
| **Model hosting** | HuggingFace with retry logic, auth support, local caching. |
| **Concurrency** | Swift 6 compatible. `VadManager` is actor-isolated. `DiarizerManager` uses locks. |

### ⚠️ Medium Risk

| Factor | Assessment |
|---|---|
| **Swift 6 sendability** | Open issue #331 — `MLModel` not Sendable in strict concurrency. Workaround exists (`@unchecked @retroactive Sendable`). |
| **iOS beta crash** | Issue #328 — `BNNSGraphContextExecute_v2` crash on iOS 26.4 beta with cpuAndGPU. macOS not affected. |
| **Model download size** | Models downloaded at runtime (~50-100MB for diarization). First-launch latency concern. Mitigate by pre-downloading in background. |

### 🟢 No Risk

| Factor | Assessment |
|---|---|
| **Lock-in** | MIT license. Full source code. Models on HuggingFace. |
| **Alternatives** | If FluidAudio dies, could use raw CoreML models directly (pyannote segmentation + wespeaker). |

---

## Recommendation

### **KEEP FluidAudio as primary diarization + VAD path**

**Rationale:**
1. It IS what we thought — CoreML/ANE diarization + Silero VAD in Swift
2. Much more mature than assumed: 3 diarization pipelines (online, offline, Sortformer)
3. Production-proven in 20+ apps including meeting assistants like Slipbox and SamScribe
4. Active development with community contributions
5. Source code, not binary — we can fork/patch if needed

**Action Items:**
1. **Fix API signatures** in `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` per corrections above
2. **Choose diarization pipeline**: `OfflineDiarizerManager` for batch processing (best DER), or `SortformerDiarizer` for real-time streaming
3. **Pre-download models** at first launch or in background to avoid latency
4. **Pin SPM version** — use `.upToNextMinor` or specific commit to avoid breaking changes
5. **Handle actor isolation** — `VadManager` is an actor; all calls must be `await`

---

## Corrected Package.swift Dependency

```swift
// In EchoPanel's Package.swift
.package(url: "https://github.com/FluidInference/FluidAudio", branch: "main"),
// Or pin to known-good commit:
.package(url: "https://github.com/FluidInference/FluidAudio", revision: "064daacd"),
```

---

## Appendix: File Reference

| File | Path | Purpose |
|---|---|---|
| Package.swift | `Package.swift` | SPM manifest — platforms, deps, targets |
| DiarizerManager | `Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift` | Online diarization orchestrator |
| DiarizerModels | `Sources/FluidAudio/Diarizer/Core/DiarizerModels.swift` | Model download/loading |
| DiarizerTypes | `Sources/FluidAudio/Diarizer/Core/DiarizerTypes.swift` | Config, result types, errors |
| OfflineDiarizerManager | `Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift` | VBx batch pipeline |
| SortformerDiarizer | `Sources/FluidAudio/Diarizer/Sortformer/SortformerDiarizerPipeline.swift` | Real-time streaming diarization |
| VadManager | `Sources/FluidAudio/VAD/VadManager.swift` | Silero VAD (actor) |
| VadManager+Streaming | `Sources/FluidAudio/VAD/VadManager+Streaming.swift` | Streaming VAD extension |
| VadManager+Segmentation | `Sources/FluidAudio/VAD/VadManager+SpeechSegmentation.swift` | Speech segmentation |
| VadTypes | `Sources/FluidAudio/VAD/VadTypes.swift` | VAD configs, results, errors |
| ModelNames | `Sources/FluidAudio/ModelNames.swift` | All model names and HF repos |
| DownloadUtils | `Sources/FluidAudio/DownloadUtils.swift` | HuggingFace download logic |
| API Reference | `Documentation/API.md` | Official API docs |
