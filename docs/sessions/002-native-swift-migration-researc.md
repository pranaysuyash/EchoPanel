<overview>
The user (pranaysuyash, HuggingFace Pro) is building EchoPanel — a macOS-only menu bar app with a local FastAPI backend and audio pipeline. The session covered: (1) deep research into Mac local AI inference options (MLX, mlx-audio, mlx-audio-swift, Argmax SDK v2, all inference frameworks), (2) discovering the Swift app already has a complete native ASR architecture built (NativeMLXBackend, HybridASRManager), (3) designing a full Python→Swift migration plan replacing all FastAPI services with native equivalents, and (4) beginning the Swift 6 upgrade. The user's core principle: Mac-only = go fully native, FastAPI is fallback only.
</overview>

<history>
1. **User asked for research on MLX, mlx-audio, mlx-audio-swift, Argmax SDK v2, Prince Canuma, HuggingFace Pro**
   - Searched GitHub repos for all MLX ecosystem packages
   - Verified HF token from `.env` (`pranaysuyash`, isPro:true, read-only token)
   - Confirmed Prince Canuma = GitHub `Blaizzy`, author of mlx-audio and mlx-audio-swift
   - Saved first report to session state (tmp path — user later complained about this)

2. **User said files must go in the project, not tmp paths**
   - Moved both research files to `docs/research/`
   - Updated convention going forward

3. **User asked to check other session state locations for other projects**
   - Found docs in session states for `learning_for_kids`, `model-lab` (inside `speech_experiments`), `media_exp`
   - Copied all to proper project locations, then deleted originals from session state

4. **User asked "what's next?"**
   - Reviewed open tickets (TCK-20260216-003, TCK-20260216-004)
   - Recommended integrating Parakeet-TDT-0.6b-v3 via mlx-audio Python provider

5. **User challenged the Python-first recommendation — why not native Swift?**
   - Discovered `NativeMLXBackend.swift`, `HybridASRManager.swift`, full ASR abstraction already built in `macapp/`
   - Package.swift already has `mlx-audio-swift` dependency
   - `swift build` passes ✅
   - Completely changed recommendation: native Swift IS already the architecture

6. **User confirmed: Mac-only = native makes sense**
   - Designed ASR fallback chain: Qwen3-ASR-0.6B-4bit → 1.7B-4bit → 1.7B-8bit → GLM-ASR-Nano → Python
   - Discovered critical constraint: `StreamingInferenceSession` is hardcoded to `Qwen3ASRModel` only

7. **User asked to research ALL FastAPI replacement options (diarization, embeddings, LLM, OCR, RAG)**
   - Live HF API queries using user's token
   - Launched background research agent
   - Key find: **FluidAudio** (open-source SDK, `FluidInference/FluidAudio`) — replaces pyannote.audio + Silero VAD entirely via CoreML/ANE
   - Full matrix: MLXLLM + MLXVLM + MLXEmbedders (ml-explore/mlx-swift-lm), Vision OCR, GRDB+vDSP for RAG
   - Saved to `docs/research/NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`

8. **User asked "are all findings documented?"**
   - Ran 4 parallel agents (Sonnet x2, Haiku, Opus):
     - agent-1 (Sonnet): Architecture discovery doc (903 lines)
     - agent-2 (Sonnet): DECISIONS.md updated with 5 new decisions
     - agent-3 (Haiku): WORKLOG ticket TCK-20260225-001 + open questions doc
     - agent-4 (Opus): Senior review doc — flagged gaps, contradictions, unverified claims
   - All completed successfully

9. **User said "follow workflow and start"**
   - Read AGENTS.md workflow: Intake → Execution → Closeout
   - Read prompts/README.md for right prompt
   - User interrupted: "why macOS 14, why not 15?"

10. **User asked to upgrade to macOS 15 / latest**
    - Checked: OS is actually macOS 15.7.3, Swift 6.2.3, Xcode SDK MacOSX26.2
    - `.v15` requires `swift-tools-version: 6.0` (was on 5.9)
    - Bumped to `swift-tools-version: 6.0` + `.macOS(.v15)` ✅ build passed
    - User then said: "don't keep anything on old Swift, upgrade all" — remove `.swiftLanguageMode(.v5)`
    - Removed the Swift 5 language mode shims
    - Build now shows Swift 6 strict concurrency errors to fix
</history>

<work_done>
Files created (all in project):
- `docs/research/MAC_LOCAL_INFERENCE_COMPLETE_GUIDE_2026-02-25.md` (642 lines) — all Mac inference frameworks + live HF data
- `docs/research/MLX_ECOSYSTEM_RESEARCH_2026-02-25.md` (682 lines) — MLX ecosystem, Argmax, Prince Canuma
- `docs/research/NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` (246 lines) — Python→Swift replacement matrix
- `docs/NATIVE_SWIFT_ASR_ARCHITECTURE_2026-02-25.md` (903 lines) — full existing Swift ASR code map, API constraints, gaps
- `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md` (359 lines) — 10 unresolved questions with options + priority
- `docs/research/RESEARCH_REVIEW_2026-02-25.md` (280 lines) — Opus senior review, gaps, risks

Files modified:
- `docs/DECISIONS.md` — 5 new decisions appended: Native Swift primary, ASR fallback chain, FluidAudio for diarization/VAD, full FastAPI replacement stack, macOS 15 target
- `docs/WORKLOG_TICKETS.md` — TCK-20260225-001 added (P0, IN_PROGRESS)
- `macapp/MeetingListenerApp/Package.swift` — bumped to `swift-tools-version: 6.0`, `.macOS(.v15)`, removed `.swiftLanguageMode(.v5)`

Current state:
- [x] All research documented
- [x] DECISIONS.md updated
- [x] WORKLOG ticket created
- [x] Package.swift on Swift 6 tools + macOS 15
- [ ] Swift 6 strict concurrency errors NOT YET FIXED — build currently failing
</work_done>

<technical_details>
**Swift 6 upgrade:**
- `swift-tools-version: 6.0` required for `.macOS(.v15)` — 5.9 doesn't have `.v15`
- Swift 6 strict concurrency (`#MutableGlobalVariable`) breaks existing code
- Errors found (not yet fixed):
  1. `CGDisplayCreateImage` removed in macOS 15 — `Sources/Services/OCRFrameCapture.swift:329` must use ScreenCaptureKit
  2. `static var shared` on non-`@MainActor`/non-`Sendable` classes: `BackendManager`, `BetaGatingManager`, `SessionStore`, `StructuredLogger`, `FeatureFlagManager`
  3. `static var nlpCache` in `EntityHighlighter.swift:22` — mutable global state
  4. `BackendCapabilities` not `Sendable` — blocks `nonisolated` on `capabilities` in `NativeMLXBackend` and `PythonBackend`
  5. `BackendSelectionContext.default` static — non-Sendable type as static
  6. `ASRTypes.swift:124,134` — `BackendCapabilities` static properties not concurrency-safe

**mlx-audio-swift critical constraint:**
- `StreamingInferenceSession` is hardcoded to `Qwen3ASRModel` — GLMASRModel cannot stream
- GLMASRModel has its own `generateStream` but different API, batch-friendly only
- Available Swift STT model classes: `Qwen3ASRModel` (streaming + batch), `GLMASRModel` (batch only)

**ASR Fallback Chain:**
- P1: `mlx-community/Qwen3-ASR-0.6B-4bit` (streaming, fast, 1052 DL)
- P2: `mlx-community/Qwen3-ASR-1.7B-4bit` (streaming, 300 DL)
- P3: `mlx-community/Qwen3-ASR-1.7B-8bit` (streaming, best quality, 2034 DL)
- P4: `mlx-community/GLM-ASR-Nano-2512-4bit` (batch only, diversity fallback, 344 DL)
- P5: PythonBackend (ultimate fallback, diarization)
- Parakeet-TDT-0.6b-v3 NOT in Swift API yet (Python mlx-audio only)

**FluidAudio (key discovery):**
- `github.com/FluidInference/FluidAudio` — open-source, CoreML/ANE
- Replaces both pyannote.audio (diarization) AND Silero VAD (Python)
- Used in production by BoltAI, VoiceInk, Whisper Mate
- Models distributed as precompiled CoreML binaries

**Full FastAPI replacement stack:**
- Diarization + VAD: FluidAudio
- Embeddings: MLXEmbedders (ml-explore/mlx-swift-lm) — Qwen3-Embedding-0.6B-4bit
- LLM analysis: MLXLLM ChatSession (ml-explore/mlx-swift-lm)
- OCR text: Apple Vision `VNRecognizeTextRequest` (built-in)
- OCR VLM: MLXVLM (ml-explore/mlx-swift-lm)
- RAG storage: GRDB.swift + vDSP brute-force cosine

**HuggingFace account:** pranaysuyash, isPro:true, token: `[REDACTED]` (read-only, in `.env`)

**Environment:** macOS 15.7.3, Swift 6.2.3, Xcode SDK MacOSX26.2, Apple Silicon
</technical_details>

<important_files>
- `macapp/MeetingListenerApp/Package.swift`
  - Central: defines all deps, platform target, Swift tools version
  - Changed: swift-tools-version 5.9→6.0, .v14→.v15, removed swiftLanguageMode(.v5)
  - Currently causes build failure (Swift 6 concurrency errors in source files)

- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift`
  - Primary native ASR implementation using Qwen3ASRModel from mlx-audio-swift
  - Has Swift 6 error: `BackendCapabilities` not `Sendable`, `nonisolated` issue on `capabilities` property
  - Default model: `mlx-community/Qwen3-ASR-0.6B-4bit`

- `macapp/MeetingListenerApp/Sources/ASR/ASRTypes.swift`
  - Defines `BackendCapabilities`, `TranscriptionResult`, `BackendStatus` etc.
  - Needs `Sendable` conformance added to fix Swift 6 errors (lines 124, 134)

- `macapp/MeetingListenerApp/Sources/ASR/ASRBackendProtocol.swift`
  - `BackendSelectionContext.default` static — needs `Sendable` (line 66)

- `macapp/MeetingListenerApp/Sources/ASR/FeatureFlagManager.swift`
  - `static var shared` not concurrency-safe — needs `@MainActor` (line 8)

- `macapp/MeetingListenerApp/Sources/BackendManager.swift`
  - `static var shared` not concurrency-safe — needs `@MainActor` (line 7)

- `macapp/MeetingListenerApp/Sources/BetaGatingManager.swift`
  - `static var shared` — needs `@MainActor` (line 6)

- `macapp/MeetingListenerApp/Sources/SessionStore.swift`
  - `static var shared` — needs `@MainActor` (line 12)

- `macapp/MeetingListenerApp/Sources/StructuredLogger.swift`
  - `static var shared` — needs `@MainActor` or `nonisolated(unsafe)` for logging (line 121)

- `macapp/MeetingListenerApp/Sources/EntityHighlighter.swift`
  - `static var nlpCache` mutable global — needs `@MainActor` or actor isolation (line 22)

- `macapp/MeetingListenerApp/Sources/Services/OCRFrameCapture.swift`
  - `CGDisplayCreateImage` removed in macOS 15 — must replace with ScreenCaptureKit (line 329)

- `docs/NATIVE_SWIFT_ASR_ARCHITECTURE_2026-02-25.md`
  - 903-line architecture doc covering all existing Swift ASR code, mlx-audio-swift constraints, open gaps

- `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`
  - 10 unresolved questions (Parakeet in Swift, vector search scale, FluidAudio risk, RAM budget, etc.)

- `docs/research/RESEARCH_REVIEW_2026-02-25.md`
  - Opus senior review — critical flags before implementing (no benchmarks, FluidAudio API unverified, memory pressure)
</important_files>

<next_steps>
**Immediate — fix Swift 6 build errors (blocking everything):**

Pattern fixes needed (same fix applied across multiple files):
1. Add `Sendable` to value types: `BackendCapabilities`, `BackendSelectionContext`, `BackendStatus`, `TranscriptionResult`, `TranscriptionSegment`, `TranscriptionConfig`, `PerformanceMetrics` in `ASRTypes.swift` and `ASRBackendProtocol.swift`
2. Add `@MainActor` to singleton classes: `FeatureFlagManager`, `BackendManager`, `BetaGatingManager`, `SessionStore` (their `shared` statics)
3. Fix `StructuredLogger.shared` — either `@MainActor` or `nonisolated(unsafe) static let shared` (logging is safe to call from anywhere)
4. Fix `EntityHighlighter.nlpCache` — wrap in actor or add `@MainActor`
5. Replace `CGDisplayCreateImage` in `OCRFrameCapture.swift:329` with `ScreenCaptureKit` API

**After build is green:**
6. Follow workflow: read `prompts/remediation/implementation-v1.1.md` for implementation prompt
7. Run pre-flight check: `prompts/workflow/pre-flight-check-v1.0.md`
8. Begin TCK-20260225-001 implementation:
   - Add FluidAudio + mlx-swift-lm + GRDB + WhisperKit to Package.swift
   - Implement ASR fallback chain in `NativeMLXBackend`
   - Wire FluidAudio for diarization + VAD

**Open question to resolve before diarization work:**
- FluidAudio API examples in research doc flagged as potentially speculative by Opus review — verify against actual FluidAudio source before implementing
</next_steps>
