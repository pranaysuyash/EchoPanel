<overview>
EchoPanel is a macOS-only menu bar meeting transcription app (Apple Silicon). This session continued two parallel tracks from prior work: (1) completing all Python backend hardening PRs (F-001→F-012 audit findings), and (2) implementing TCK-20260225-001 — a full native Swift MLX migration making FastAPI a fallback only. The user's principle: Mac-only = native Swift/MLX primary; document everything; use uv/venv for Python. We are now mid-Phase 3 (Brain Dump UI integration), having completed Phase 1 (core Swift actors) and Phase 2 (wiring + GRDB RAG).
</overview>

<history>

1. **Session resumed from prior checkpoint** — backend hardening complete, native Swift Phase 1 actors built
   - All 12 audit findings fixed (F-001→F-012), 152 Python tests passing
   - Phase 1 Swift actors already committed: FluidAudioVADProvider, ASRFallbackChain, FluidAudioDiarization, PhaseScheduler, MLXAnalysisEngine, MLXEmbeddingsEngine

2. **User said "proceed"** — implement Phase 2 (wiring)
   - **Wire ASRFallbackChain into NativeMLXBackend**: replaced single `Qwen3ASRModel` with `ASRFallbackChain` actor; chain tiers: Qwen3-0.6B → 1.7B → Parakeet TDT → Python; streaming path retains `qwen3Model` direct reference for `StreamingInferenceSession`
   - **Wire PhaseScheduler into AppState**: added `phaseScheduler`, `analysisEngine`, `embeddingsEngine`, `diarization` properties; `setup()` called on init; `transition(to: .recording)` on `startSession()`; `recording→analysis→brainDump→idle` in `stopSession()`
   - **Wire MLXAnalysisEngine**: `runNativeAnalysis()` in analysis phase, idempotent `load()`, populates `finalSummaryMarkdown` when Python summary absent
   - **Wire FluidAudioDiarization**: PCM audio accumulator in `accumulateAudioFrame()` (Float32 16kHz, 3h cap); `runNativeDiarization()` in analysis phase; `applySpeakerLabels()` maps diar segments to TranscriptSegments by timestamp midpoint
   - **Add GRDB 6.29.3** to Package.swift; created `SessionRAGStore` (SQLite + vDSP cosine, NomicBert 768-dim, `indexTranscript`/`search`/`deleteSession`)
   - **Vision OCR**: confirmed already native (`VNRecognizeTextRequest`) — no change needed
   - Build clean, 152 Python tests pass; committed

3. **User said "proceed"** — implement Phase 3 (Brain Dump UI integration)
   - Added Phase 3 todos to SQL: `rag-wire-appstate`, `rag-search-ui`, `speaker-label-ui`, `phase3-integration-test`
   - **Started `rag-wire-appstate`**: added `ragStore = SessionRAGStore()` property and `@Published var ragSearchResults: [ContextQueryResult] = []` to AppState
   - **Was mid-edit** when compaction triggered — `ragStore.setup()` init call and `indexTranscript` wiring in brainDump phase NOT YET COMPLETE

</history>

<work_done>

**Files modified this session:**

- `macapp/MeetingListenerApp/Package.swift` — Added FluidAudio (branch: main), MLXLLM, MLXEmbedders, GRDB 6.29.3
- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift` — Replaced `model: Qwen3ASRModel?` with `chain: ASRFallbackChain` + `qwen3Model` for streaming; new `chainTiers` init param
- `macapp/MeetingListenerApp/Sources/ASR/ASRFallbackChain.swift` — Fixed arg order: `language:` before `chunkDuration:` in STTGenerateParameters
- `macapp/MeetingListenerApp/Sources/Analysis/MLXAnalysisEngine.swift` — Fixed GenerateParameters arg order; added idempotent guard in `load()`
- `macapp/MeetingListenerApp/Sources/AppState.swift` — PhaseScheduler wired; audio accumulator; `runNativeDiarization()`, `runNativeAnalysis()`, `applySpeakerLabels()`; `ragStore` + `ragSearchResults` added (INCOMPLETE — setup() not wired yet)

**Files created this session:**

- `macapp/MeetingListenerApp/Sources/ASR/FluidAudioVADProvider.swift` — Silero VAD actor (Phase 1)
- `macapp/MeetingListenerApp/Sources/ASR/ASRFallbackChain.swift` — 4-tier fallback chain (Phase 1)
- `macapp/MeetingListenerApp/Sources/ASR/FluidAudioDiarization.swift` — OfflineDiarizerManager + RTTM (Phase 1)
- `macapp/MeetingListenerApp/Sources/Services/PhaseScheduler.swift` — Sequential phase + memory pressure (Phase 1)
- `macapp/MeetingListenerApp/Sources/Analysis/MLXAnalysisEngine.swift` — MLXLLM Qwen2.5-1.5B (Phase 1)
- `macapp/MeetingListenerApp/Sources/BrainDump/MLXEmbeddingsEngine.swift` — NomicBert 768-dim (Phase 1)
- `macapp/MeetingListenerApp/Sources/BrainDump/SessionRAGStore.swift` — GRDB SQLite + vDSP cosine search (Phase 2)

**Git commits this session:**
1. `feat(native-swift): TCK-20260225-001 — FluidAudio VAD+Diarize, ASR fallback chain, PhaseScheduler, MLX analysis+embeddings`
2. `docs: update TCK-20260225-001 evidence log — Phase 1 Swift actors complete`
3. `feat(native-swift): TCK-20260225-001 Phase 2 — wiring + GRDB RAG store`

**Current state:**
- `swift build` ✅ clean
- 152 Python tests pass ✅
- Phase 3 `rag-wire-appstate` todo: IN PROGRESS — `ragStore` and `ragSearchResults` properties added but `ragStore.setup()` not yet called in `init()` and `indexTranscript()` not yet wired into brainDump phase

**SQL todos:**
- `rag-wire-appstate` — in_progress
- `rag-search-ui` — pending
- `speaker-label-ui` — pending
- `phase3-integration-test` — pending

</work_done>

<technical_details>

**Package.swift pins:**
- `mlx-audio-swift` at `from: "0.1.0"` (NOT branch: "main")
- `mlx-swift-lm` at `from: "2.30.6"`
- `FluidAudio` at `branch: "main"` (no semver tag — use branch)
- `GRDB.swift` at `from: "6.29.3"`
- `swift-tools-version: 6.2`, macOS 15 target

**FluidAudio API (verified from SPM checkout):**
- `VadManager` is an **actor** — `makeStreamState()` must be `await`ed from outside actor
- `OfflineDiarizerManager` init is **synchronous** (`init(config:)`)
- `prepareModels()` is async, `process(audio:)` is async
- `DiarizerConfig` vs `OfflineDiarizerConfig` — these are different types
- FluidAudio resolves many transitive deps (swift-nio, swift-certificates, etc.)

**MLXEmbedders API (verified from SPM checkout):**
- `ModelContainer.perform` is actor-isolated — must `await` from outside
- `MLXArray.ones([1, n], dtype: .int32)` NOT `type: .int32` (use `dtype:` label)
- `Pooling.callAsFunction(_:mask:normalize:applyLayerNorm:)` is the correct signature
- `tokenizer.encode(text:addSpecialTokens:)` — needs `addSpecialTokens: true`
- Return `pooled[0].asArray(Float.self)` for single-text embedding (2D → 1D)

**MLXLLM API:**
- `loadModelContainer(id:progressHandler:)` from `MLXLMCommon` — returns `ModelContainer`
- `ChatSession(mc, instructions:system, generateParameters:)` — init with container
- `GenerateParameters(maxTokens:temperature:)` — `maxTokens` MUST precede `temperature`
- `session.respond(to: userPrompt)` → `String`

**ASRFallbackChain:**
- `STTGenerateParameters`: `language:` MUST precede `chunkDuration:` in init
- Streaming path (StreamingInferenceSession) is Qwen3-only — `qwen3Model` stored separately
- Chain loads by trying tiers; on success sets `activeTier`; on each failure calls `Memory.clearCache()`

**SessionRAGStore:**
- `EmbeddingRecord` must use `let id: Int64?` (not `var`) to avoid Swift 6 Sendable capture error in `pool.write` closure
- `vDSP_dotpr` used for cosine similarity — assumes vectors are L2-normalised by `MLXEmbeddingsEngine`
- Both vectors normalised = dot product == cosine similarity (no norm division needed)
- Chunking: 80 words/chunk default; prepends "search_document:" / "search_query:" for Nomic embed format

**AppState audio accumulator:**
- PCM frames from `AudioCaptureManager.onPCMFrame` are `Data` of `Float32 LE` at 16kHz (confirmed from `targetFormat` in AudioCaptureManager)
- Max buffer: `16000 * 60 * 180` samples = 3 hours
- `accumulateAudioFrame()` must be called on MainActor (inside the existing `Task { @MainActor in }` block)

**PhaseScheduler:**
- Valid transitions: `idle→recording`, `recording→analysis`, `analysis→brainDump`, `brainDump→idle`, any→idle
- `exporting` phase: `idle→exporting`, `exporting→idle` only
- Memory pressure `.critical` blocks entry to `.analysis` and `.brainDump`
- `setup()` must be called after `init()` (registers DispatchSource memory pressure handler)

**TranscriptSegment:**
- `speaker: String?` field already exists — diarization just sets it
- `applySpeakerLabels()` uses segment midpoint `(t0+t1)/2` to match diar segment
- `TranscriptSegment` is a struct — must construct new instance to mutate (no `var` fields except `speaker`)

**Vision OCR:**
- `OCRFrameCapture.swift` already uses `VNRecognizeTextRequest` natively — no Python dependency existed

**Pre-commit gate:**
- `scripts/verify.sh`: `swift build` → `swift test` → `uv run ruff check server/` → `uv run pytest tests/ -x -q --timeout=60`
- Must use `uv run` (not raw `python -m pytest`)
- 152 Python tests pass; 1 pre-existing failure in `test_video_understanding.py` (SSL error, unrelated to our changes)

</technical_details>

<important_files>

- `macapp/MeetingListenerApp/Package.swift`
  - SPM manifest; all deps pinned here
  - Added: FluidAudio (branch:main), MLXLLM, MLXEmbedders, GRDB 6.29.3
  - Target deps: MLXAudioSTT, MLXAudioVAD, MLXLLM, MLXEmbedders, FluidAudio, GRDB

- `macapp/MeetingListenerApp/Sources/AppState.swift`
  - Central app coordinator (2300+ lines, @MainActor)
  - **INCOMPLETE EDIT IN PROGRESS**: `ragStore` and `ragSearchResults` added (lines ~373-392) but `ragStore.setup()` NOT yet in `init()` and `indexTranscript()` NOT yet wired into brainDump phase
  - Key additions: `phaseScheduler`, `analysisEngine`, `embeddingsEngine`, `diarization`, `ragStore`, `recordingAudioBuffer`, `ragSearchResults`
  - `runNativeDiarization()` at ~line 1005; `runNativeAnalysis()` at ~line 990; `applySpeakerLabels()` at ~line 1030
  - `accumulateAudioFrame()` called from `audioCapture.onPCMFrame` callback
  - `stopSession()` at line 882: transitions phase recording→analysis→brainDump→idle

- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift`
  - Core ASR actor; now uses `ASRFallbackChain` instead of single `Qwen3ASRModel`
  - `chain: ASRFallbackChain?` + `qwen3Model: Qwen3ASRModel?` properties
  - `initialize()` tries chain; `transcribe()` delegates to chain; `startStreaming()` uses qwen3Model

- `macapp/MeetingListenerApp/Sources/BrainDump/SessionRAGStore.swift`
  - New file: GRDB SQLite store + vDSP cosine search
  - `setup()`, `insert()`, `indexTranscript()`, `search()`, `deleteSession()`
  - DB at `~/Library/Application Support/com.echopanel/rag.sqlite`

- `macapp/MeetingListenerApp/Sources/BrainDump/MLXEmbeddingsEngine.swift`
  - NomicBert 768-dim embeddings via MLXEmbedders
  - `embed(text:)` → `[Float]`; `embedBatch()`, `cosineSimilarity()`
  - `load()` is idempotent (guard `!isLoaded`)

- `macapp/MeetingListenerApp/Sources/Analysis/MLXAnalysisEngine.swift`
  - MLXLLM ChatSession (Qwen2.5-1.5B-Instruct-4bit)
  - `load()` is idempotent; `analyze(.summarize/extractActionItems/extractDecisions/custom)`
  - `unload()` called after each use to free VRAM

- `macapp/MeetingListenerApp/Sources/ASR/ASRFallbackChain.swift`
  - 4-tier chain: Qwen3-0.6B → 1.7B → Parakeet TDT → Python
  - `transcribe(audio:language:maxTokens:temperature:chunkDuration:)` handles both Qwen3 and Parakeet models

- `macapp/MeetingListenerApp/Sources/Services/PhaseScheduler.swift`
  - Sequential phase enforcer + memory pressure monitoring
  - `setup()` must be called post-init; `transition(to:)` returns `.success`/`.rejected`

- `docs/WORKLOG_TICKETS.md`
  - TCK-20260225-001 at line 9666; status updated with Phase 1+2 evidence log

</important_files>

<next_steps>

**Immediate — complete `rag-wire-appstate` (in_progress):**

The last edit added `ragStore` and `ragSearchResults` to AppState properties. Still needed:

1. **Wire `ragStore.setup()` into `AppState.init()`** — add after `Task { await phaseScheduler.setup() }`:
   ```swift
   Task { try? await ragStore.setup() }
   ```

2. **Wire `indexTranscript()` into brainDump phase in `stopSession()`** — add after `phaseScheduler.transition(to: .brainDump)`:
   ```swift
   await self.runNativeBrainDump()
   ```
   And add the helper:
   ```swift
   @MainActor
   private func runNativeBrainDump() async {
       guard let id = sessionID else { return }
       let transcript = transcriptSegments.map(\.text).joined(separator: " ")
       guard !transcript.isEmpty else { return }
       do {
           try await embeddingsEngine.load()
           try await ragStore.indexTranscript(sessionId: id, transcript: transcript, engine: embeddingsEngine)
       } catch {
           logger.warning("AppState: brain dump indexing failed — \(error.localizedDescription)")
       }
       await embeddingsEngine.unload()
   }
   ```

**Todo: `rag-search-ui`:**
3. **Augment `queryContextDocumentsAsync`** — after Python query (or on Python failure), run local RAG search:
   ```swift
   // Local RAG fallback/supplement
   if ragSearchResults.isEmpty || contextQueryResults.isEmpty {
       let localResults = try? await ragStore.search(query: query, engine: embeddingsEngine, topK: 5)
       ragSearchResults = localResults?.map { r in
           ContextQueryResult(documentID: r.sessionId, title: "Session \(r.sessionId.prefix(8))",
               source: "local", chunkIndex: r.chunkIndex, snippet: r.text, score: Double(r.score))
       } ?? []
   }
   ```

**Todo: `speaker-label-ui`:**
4. Find transcript render in SidePanelView — add speaker badge when `segment.speaker != nil`

**Todo: `phase3-integration-test`:**
5. Add a Swift test in `Tests/` verifying: phase transitions fire correctly, ragStore has entries after `indexTranscript`, `search()` returns results

**Then:** Run `swift build` + pytest, commit Phase 3, update TCK-20260225-001 ticket.

</next_steps>