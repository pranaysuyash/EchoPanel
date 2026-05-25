<overview>
EchoPanel is a macOS-only menu bar meeting transcription app (Apple Silicon). The session covered two major tracks: (1) upgrading the Swift app to Swift 6 strict concurrency + macOS 15, fixing all resulting compiler errors across 20+ files and test targets; and (2) a multi-agent research sprint resolving P0 blockers for the native Swift MLX migration (TCK-20260225-001) — verifying FluidAudio API, RAM budget, ASR benchmarks, and library updates. The user's principle: Mac-only = go fully native, FastAPI is fallback only. A third research wave was just launched (3 more agents) to deep-dive VoxtralRealtime, HF Pro model sweep, MossFormer2, and Sortformer.
</overview>

<history>
1. **User resumed from prior session — Swift 6 upgrade in progress**
   - Prior context: Package.swift had been bumped to swift-tools-version: 6.0, .macOS(.v15), .swiftLanguageMode(.v5) removed
   - Build was failing with Swift 6 strict concurrency errors across 18+ files

2. **Swift 6 error triage**
   - Ran `swift build` to get full error list: 50+ errors across 18 source files + test files
   - Categorized into patterns: non-Sendable statics, `sending` data race errors, `@MainActor` singletons, deprecated APIs

3. **Two parallel agents launched for bulk fixes**
   - agent-0 (Sonnet): Fixed ASR types + singletons (ASRTypes, ASRBackendProtocol, FeatureFlagManager, NativeMLXBackend, PythonBackend, BackendManager, BetaGatingManager, SessionStore, StructuredLogger, EntityHighlighter)
   - agent-1 (Sonnet): Fixed capture managers + OCR + AppState (OCRFrameCapture, AudioCaptureManager, AppState, MicrophoneCaptureManager, RedundantAudioCaptureManager, CrashReporter, DeviceHotSwapManager, HotKeyManager, SidePanelController, VoiceNoteCaptureManager)

4. **Remaining errors fixed manually (4 rounds)**
   - HotKeyManager: `@preconcurrency import Cocoa` to suppress Carbon `kAXTrustedCheckOptionPrompt` global
   - VoiceNoteCaptureManager: added `@MainActor`, removed deinit Task (caused SIGABRT — `[weak self]` in `@MainActor` deinit crashes)
   - ResourceMonitor: `nonisolated(unsafe) var monitoringTimer`
   - WebSocketStreamer: `@unchecked Sendable`, extract payload type string before DispatchQueue closure
   - DeviceHotSwapManager: `@preconcurrency import AVFoundation` not enough; inlined notification handler logic to extract only `String` values before `MainActor.assumeIsolated`
   - OCRFrameCapture: `CGDisplayCreateImage` removed in macOS 15 — replaced with `SCScreenshotManager.captureSampleBuffer` + `CIContext→CGImage` conversion; added `@preconcurrency import ScreenCaptureKit` + `import CoreImage`
   - HybridASRManager: `BackendStatus: Sendable`, `BackendState: Sendable`, `PerformanceMetrics: Sendable`, `BackendSelectionStrategy: Sendable`, `SmartBackendSelection: Sendable`; fixed `MainActor.run` capture list for region isolation checker bug
   - MicrophoneCaptureManager: `@unchecked Sendable` (not `@MainActor` — has audio tap closures + `nonisolated` metrics properties that are incompatible with actor isolation)

5. **Test target errors fixed**
   - NativeMLXBackendTests: `@MainActor` on class, `@MainActor extension XCTestCase` for `wait(for:timeout:)` helper
   - ProductionReadinessTests: extract `appState` before `withTaskGroup` to avoid capturing `self`

6. **Build + all 163 tests pass — committed**

7. **User asked "what's next?" → research sprint proposed and launched**
   - Reviewed open tickets: TCK-20260225-001 (Native Swift migration, P0, IN_PROGRESS) + 10 open questions in NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md + 4 red gaps from Opus review

8. **5-agent parallel research sprint (resolved P0 blockers)**
   - agent-2 (Opus): FluidAudio API verification
   - agent-3 (Sonnet): RAM budget for 8GB Mac
   - agent-4 (Haiku): ASR accuracy + latency benchmarks
   - agent-5 (Sonnet): Latest mlx-audio-swift + mlx-swift-lm + WhisperKit
   - agent-6 (Sonnet synthesis): Updated DECISIONS.md (DEC-026→034), updated OPEN_QUESTIONS.md (Q1-Q10), created RESEARCH_SPRINT_2026-02-26.md

9. **User asked to research VoxtralRealtime + more HF Pro models**
   - 3 more agents launched (still running):
     - agent-7 (Sonnet): VoxtralRealtime + LFM-2.5-Audio deep dive
     - agent-8 (Sonnet): HF Pro models sweep (all categories)
     - agent-9 (Haiku): MossFormer2 + Sortformer deep dive
</history>

<work_done>
**Files modified:**
- `macapp/MeetingListenerApp/Package.swift` — swift-tools-version 5.9→6.0, .macOS(.v14→.v15), removed .swiftLanguageMode(.v5)
- `Sources/ASR/ASRTypes.swift` — Sendable on BackendCapabilities, BackendStatus, BackendState, PerformanceMetrics, Language, TranscriptionConfig, TranscriptionResult, TranscriptionSegment, ASRError, TranscriptionEvent
- `Sources/ASR/ASRBackendProtocol.swift` — Sendable on BackendSelectionContext, BackendSelectionStrategy, SmartBackendSelection, NetworkQuality, PrivacyRequirement
- `Sources/ASR/FeatureFlagManager.swift` — nonisolated(unsafe) static let shared
- `Sources/ASR/NativeMLXBackend.swift` — @preconcurrency import MLX + AVFoundation, FeedAudioResult: Sendable
- `Sources/ASR/HybridASRManager.swift` — Sendable on BackendSelectionStrategy; fixed MainActor.run capture list [comparison]
- `Sources/BackendManager.swift` — @MainActor on class
- `Sources/BetaGatingManager.swift` — @MainActor on class
- `Sources/SessionStore.swift` — @MainActor on class
- `Sources/StructuredLogger.swift` — nonisolated(unsafe) static let shared
- `Sources/EntityHighlighter.swift` — nonisolated(unsafe) static var nlpCache
- `Sources/HotKeyManager.swift` — @preconcurrency import Cocoa; moved kAXTrustedCheckOptionPrompt access into @MainActor methods
- `Sources/VoiceNoteCaptureManager.swift` — @MainActor on class; removed deinit (SIGABRT risk)
- `Sources/ResourceMonitor.swift` — nonisolated(unsafe) var monitoringTimer
- `Sources/WebSocketStreamer.swift` — @unchecked Sendable; extract payloadType before DispatchQueue closure
- `Sources/AudioCaptureManager.swift` — @unchecked Sendable
- `Sources/MicrophoneCaptureManager.swift` — @unchecked Sendable; removed invalid nonisolated on var properties
- `Sources/SidePanelController.swift` — @MainActor on class
- `Sources/AppState.swift` — extract capture refs before async boundaries; @Sendable on callbacks
- `Sources/CrashReporter.swift` — extract exception name before Task boundary
- `Sources/RedundantAudioCaptureManager.swift` — extract primaryCapture before await
- `Sources/DeviceHotSwapManager.swift` — @preconcurrency import AVFoundation; inlined notification handlers
- `Sources/Services/OCRFrameCapture.swift` — @preconcurrency import ScreenCaptureKit; import CoreImage; replaced CGDisplayCreateImage with SCScreenshotManager.captureSampleBuffer + CIContext→CGImage; nonisolated(unsafe) private var timer
- `Tests/NativeMLXBackendTests.swift` — @MainActor on class; @MainActor extension XCTestCase for wait helper
- `Tests/ProductionReadinessTests.swift` — extract appState before task group

**Files created (research docs):**
- `docs/research/FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` — Verified real source, correct API
- `docs/research/RAM_BUDGET_ANALYSIS_2026-02-26.md` — 8GB Mac: 2.3-2.6GB peak
- `docs/research/ASR_BENCHMARK_COMPARISON_2026-02-26.md` + ASR_BENCHMARK_SUMMARY.md + README_ASR_BENCHMARK.md
- `docs/research/MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` — mlx-audio-swift v0.1.0 delta
- `docs/research/RESEARCH_SPRINT_2026-02-26.md` — synthesis + 4-week plan

**Files updated (existing docs):**
- `docs/DECISIONS.md` — DEC-026 through DEC-034 appended
- `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md` — Q1, Q3, Q4, Q6, Q7 fully resolved; Q2, Q5, Q8, Q9, Q10 updated

**Files in-flight (agents still running):**
- `docs/research/VOXTRAL_LFM_RESEARCH_2026-02-26.md` — agent-7 creating
- `docs/research/HF_PRO_MODELS_SWEEP_2026-02-26.md` — agent-8 creating
- `docs/research/MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md` — agent-9 creating

**Current state:**
- [x] Swift 6 build: PASSES
- [x] All 163 tests: PASS
- [x] Committed to git
- [x] Research sprint committed to git
- [ ] agent-7, agent-8, agent-9 still running (VoxtralRealtime / HF sweep / MossFormer2+Sortformer)
- [ ] Package.swift still on `branch: "main"` for mlx-audio-swift (needs pin to `from: "0.1.0"`)
- [ ] TCK-20260225-001 implementation not yet started
</work_done>

<technical_details>
**Swift 6 concurrency fixes — patterns used:**

1. **Non-Sendable value types** → add `: Sendable` conformance. If stored properties aren't Sendable, add them too recursively.
2. **Singleton `static var shared` on class** → `@MainActor` on class if it's an ObservableObject/UI class. Use `nonisolated(unsafe) static let shared` for utilities like loggers.
3. **`@MainActor` class deinit** → deinit is nonisolated in Swift 6. Cannot call `@MainActor` methods or access `@MainActor` properties. Cannot use `Task { @MainActor [weak self] in }` — causes SIGABRT ("Cannot form weak reference to instance in dealloc"). Solution: remove deinit entirely or access only `nonisolated(unsafe)` properties.
4. **Thread-safe classes with internal locking** → `@unchecked Sendable` (AudioCaptureManager, WebSocketStreamer, MicrophoneCaptureManager all use NSLock).
5. **Carbon/C globals (kAXTrustedCheckOptionPrompt)** → `@preconcurrency import Cocoa` at the import site, or access inside `@MainActor` methods only.
6. **AVFoundation notification closures on @MainActor class** → extracting only Sendable values (String) before `MainActor.assumeIsolated`; `@preconcurrency import AVFoundation` alone was insufficient.
7. **ScreenCaptureKit @preconcurrency** → needed for `SCShareableContent.current` non-Sendable result; also `captureHighResolutionScreenshot` doesn't exist — use `captureSampleBuffer` instead.
8. **`nonisolated` on mutable stored properties** → only valid on `@MainActor` class properties as `nonisolated(unsafe)`. Not valid on non-actor classes.
9. **Swift 6 region isolation checker bug** → `await MainActor.run { lastComparison = comparison }` triggers "pattern that the region based isolation checker does not understand" — fix with explicit capture list `[comparison]`.
10. **XCTestCase in Swift 6** → `@MainActor` on test class + `@MainActor extension XCTestCase` for helpers that create tasks. `withTaskGroup` child closures capturing `self` of `@MainActor` class need `self` extracted first.
11. **Package.swift swift-tools-version 6.0 required** for `.macOS(.v15)` (5.9 doesn't have .v15).

**Research sprint findings:**

- **FluidAudio**: Source code (not binary XCFramework), MIT license, Swift 6, macOS 14+. Correct init: `DiarizerManager(config: DiarizerConfig)` synchronous. `VadManager` is an `actor` (async/await). 3 pipelines: DiarizerManager (online), OfflineDiarizerManager (VBx batch), SortformerDiarizer (streaming). Models downloaded from HF at runtime (~300MB ANE memory).
- **RAM budget 8GB Mac**: Qwen3-ASR-0.6B-4bit = 676MB disk/~720MB runtime. FluidAudio (ANE) ~300MB. Full stack peaks 2.3–2.6GB. Fits in 6GB with ~1.5GB headroom. Sequential phases (never ASR + LLM simultaneously) is key constraint.
- **Qwen3-Embedding-0.6B-4bit**: NOT publicly available yet (HF 401). Use `nomic-embed-text-v1.5` (140MB) as interim.
- **mlx-audio-swift v0.1.0** (Feb 23): Parakeet NOW in Swift (`ParakeetModel`, PR #51). Qwen3ASR streaming fixed (PR #32). GLM still batch-only. New: VoxtralRealtime (PR #52), LFM-2.5-Audio (#53), Sortformer (#33), MossFormer2 (#29, #44). Requires `swift-tools-version: 6.2` in its own Package.swift. Our Package.swift tracks `branch: "main"` — must pin to `from: "0.1.0"`.
- **WhisperKit**: CoreML-only, cannot share MLX unified memory pool. Rejected (DEC-033).
- **mlx-swift-lm**: v2.30.6 (Feb 18). MLXEmbedders supports NomicBert. Separate repo from mlx-swift-examples.
- **16GB Mac tier**: Qwen2.5-7B (4.3GB) unlocks dramatically better meeting summaries — marketing differentiator (DEC-034).

**Updated ASR fallback chain:**
```
P1: Qwen3-ASR-0.6B-4bit   (streaming, ~720MB)  ← primary
P2: Qwen3-ASR-1.7B-4bit   (streaming, ~1.6GB)
P3: Qwen3-ASR-1.7B-8bit   (streaming, ~3.2GB)
P4: ParakeetModel v2       (streaming, ~1.2GB)  ← NEW
P5: PythonBackend          (ultimate fallback)
GLM-ASR-Nano: REMOVED      (batch-only)
```

**Open questions still unresolved:** Q5 (first-run UX product decision), Q8 (diarization accuracy parity — needs benchmarks), Q9 (ANE vs GPU profiling), Q10 (HF token in production distribution).
</technical_details>

<important_files>
- `macapp/MeetingListenerApp/Package.swift`
  - Defines all deps, platform, Swift tools version
  - URGENT: still on `branch: "main"` for mlx-audio-swift — must change to `from: "0.1.0"`
  - mlx-swift-lm not yet added as direct dependency (needed for MLXEmbedders + MLXLLM)

- `Sources/ASR/NativeMLXBackend.swift`
  - Primary native ASR implementation; uses Qwen3ASRModel from mlx-audio-swift
  - Fixed: @preconcurrency imports, FeedAudioResult: Sendable
  - Still needs: ASR fallback chain (Parakeet at P4, Qwen3 chain P1-P3)

- `Sources/ASR/ASRTypes.swift`
  - All ASR value types; now fully Sendable
  - BackendCapabilities, BackendStatus, PerformanceMetrics all Sendable

- `Sources/ASR/HybridASRManager.swift`
  - @MainActor orchestrator; BackendSelectionStrategy now Sendable
  - Fixed MainActor.run capture list bug

- `Sources/Services/OCRFrameCapture.swift`
  - Critical macOS 15 API fix: CGDisplayCreateImage → SCScreenshotManager.captureSampleBuffer
  - Lines 328-348: new screen capture implementation using CIContext

- `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`
  - 10 open questions; Q1/Q3/Q4/Q6/Q7 fully resolved
  - Q1: Parakeet now in Swift; Q3: FluidAudio is source code; Q4: RAM fits

- `docs/DECISIONS.md`
  - DEC-026 through DEC-034 added (2026-02-26 sprint)
  - Key: DEC-031 (never run ASR+LLM simultaneously), DEC-033 (WhisperKit rejected)

- `docs/research/RESEARCH_SPRINT_2026-02-26.md`
  - Master synthesis doc; contains 4-week implementation plan for TCK-20260225-001
  - 11 prioritized action items; updated ASR chain; memory budget table

- `docs/research/FLUIDAUDIO_API_VERIFICATION_2026-02-26.md`
  - Correct FluidAudio API: DiarizerManager(config:), VadManager actor
  - Required before implementing FluidAudio integration

- `docs/research/RAM_BUDGET_ANALYSIS_2026-02-26.md`
  - Per-phase memory table; load/unload strategy for 8GB Mac

- `docs/WORKLOG_TICKETS.md`
  - TCK-20260225-001 (Native Swift migration, P0, IN_PROGRESS) — main implementation ticket
</important_files>

<next_steps>
**Immediate — agents still running:**
- Read agent-7 (VoxtralRealtime + LFM-2.5-Audio), agent-8 (HF Pro sweep), agent-9 (MossFormer2 + Sortformer) when complete
- Synthesize findings into DECISIONS.md and OPEN_QUESTIONS.md updates
- Commit all new research docs

**Week 1 (after agents complete) — in order:**
1. **Fix Package.swift** (P0, 1 min): `branch: "main"` → `from: "0.1.0"` for mlx-audio-swift; add `mlx-swift-lm` from `"2.30.6"` as direct dep; verify build still passes
2. **Fix FluidAudio API examples** in `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` (wrong signatures in old doc)

**Week 2 — Core Pipeline (TCK-20260225-001):**
3. Implement FluidAudio VAD using corrected `VadManager` actor API (async/await)
4. Implement `OfflineDiarizerManager` for post-recording batch diarization
5. Wire Qwen3-ASR `generateStream` with confirmed streaming API
6. Add Parakeet as P4 fallback in NativeMLXBackend

**Week 3 — Analysis Layer:**
7. Add `nomic-embed-text-v1.5` via `MLXEmbedders.NomicBert` for Brain Dump
8. Add `Qwen2.5-1.5B-Instruct-4bit` via MLXLLM for meeting analysis

**Week 4 — Phase Scheduling:**
9. Sequential phase scheduler + `MLX.GPU.clearCache()` memory pressure hook
10. Hardware tier detection (16GB → Qwen2.5-7B unlock)

**SQL todos created (pending):** pkg-pin-fix, asr-fallback-chain, fluidaudio-vad, fluidaudio-diarize, embed-nomic, llm-analysis, phase-scheduler

**Blockers / open questions:**
- VoxtralRealtime position in fallback chain: unknown until agent-7 completes
- MossFormer2 integration complexity: unknown until agent-9 completes
- Package.swift swift-tools-version: mlx-audio-swift v0.1.0 requires 6.2 in its own manifest — our 6.0 should still consume it (toolchain is 6.2.3) but needs verification
</next_steps>