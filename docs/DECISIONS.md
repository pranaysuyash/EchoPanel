# Decisions

This is a lightweight decision log. Prefer short entries that explain why.

## v0.1
- Capture: Use ScreenCaptureKit (macOS 13+) to capture system audio output without virtual drivers.
- Streaming: Use WebSocket; stream PCM16 16 kHz mono frames.
- UI: Three lanes only in the side panel (Transcript, Cards, Entities).
- No diarization in v0.1.

## v0.2
- Multi-source audio: JSON-tagged frames with `source: "system" | "mic"` instead of raw binary.
- Diarization: batch-only at session end via pyannote; requires user-provided HuggingFace token; disabled by default.
- Session storage: auto-save every 30s with crash recovery.
- Embedded backend: macOS app starts/stops the Python server automatically.

## v0.3 (planned)

### LLM-Powered Analysis Strategy (decided 2026-02-06, updated 2026-02-15)

**Decision**: Hybrid approach — keyword extraction as default, LLM as opt-in upgrade via user's own API key (cloud) OR local Ollama (Option D+B+A).

**Why**: Preserves "works offline out of the box" while enabling production-quality analysis for users who want it. Added Ollama support due to availability of lightweight 3B models (2025-2026).

**Options evaluated**:

| Option | Description | Status |
|--------|-------------|--------|
| A: Ollama (local LLM) | User installs Ollama + pulls 2-4GB model | **IMPLEMENTED** — 3B models (llama3.2, qwen2.5, gemma2) now viable on 8GB Macs |
| B: User's own cloud API key | User enters OpenAI/Anthropic key in Settings | **IMPLEMENTED** — OpenAI GPT-4o/4o-mini supported |
| C: Our hosted API | We run the LLM, user connects to our backend | **Rejected** — Requires servers, auth, billing, GDPR, on-call — too heavy for solo dev |
| D: Hybrid default | Keyword extraction default + optional LLM | **IMPLEMENTED** — Always-available fallback |

**Key architectural constraints**:
- The LLM never touches audio. It only processes transcript text that ASR already produced locally.
- Audio capture (ScreenCaptureKit) and ASR (faster-whisper) always run locally — this never changes.
- Privacy story: "Audio never leaves your Mac. Transcript text can optionally be sent to your own LLM provider for enhanced analysis."
- No user accounts, no auth, no billing infrastructure needed. User pays their LLM provider directly.
- Keyword extraction remains the always-available fallback (offline, zero cost, zero setup).

**Implementation scope** (completed 2026-02-15):
- ✅ `ECHOPANEL_LLM_PROVIDER` env var / Settings UI (values: `none`, `openai`, `ollama`)
- ✅ `ECHOPANEL_OPENAI_API_KEY` setting (stored in macOS Keychain, not env var)
- ✅ `analysis_stream.py`: LLM path alongside keyword path for `extract_cards()`, `generate_rolling_summary()`
- ✅ `llm_providers.py`: Provider abstraction with OpenAI + Ollama implementations
- ✅ Settings UI: "AI Analysis" tab with VAD + LLM configuration
- No changes to ASR pipeline, WebSocket protocol, or audio capture

**Recommended models (2026-02-15)**:

| Model | Params | RAM | Context | Best For |
|-------|--------|-----|---------|----------|
| **gemma3:1b** | 1B | ~0.8GB | 32k | 8GB Macs, basic extraction |
| **llama3.2:1b** | 1B | ~0.7GB | 128k | 8GB Macs, long context |
| **gemma3:4b** | 4B | ~2.5GB | 128k | 16GB Macs, best quality |
| **llama3.2:3b** | 3B | ~2GB | 128k | 16GB Macs, balanced |
| **qwen2.5:7b** | 7B | ~4.5GB | 128k | 16GB+ Macs, multilingual |
| gpt-4o-mini | - | - | - | Cloud option (best quality) |

**Model Notes**:
- **Gemma 3** (March 2025): Google's latest. 4B beats Gemma 2 27B on benchmarks. 1B perfect for 8GB Macs.
- **Llama 3.2**: Meta's edge models. 1B for low RAM, 3B for balanced quality.
- **Qwen2.5**: Alibaba's multilingual models. Excellent for non-English meetings.
- **Phi-4 Mini** (3.8B): Strong reasoning alternative.

**What changed the original decision**:
- ✅ **Ollama models now viable**: 2025-2026 brought lightweight 3B models (llama3.2, qwen2.5) that run in <3GB RAM, making Whisper + LLM feasible on 8GB Macs
- ✅ **User demand**: Beta feedback requested fully offline option
- ✅ **Implementation complete**: See `docs/LLM_ANALYSIS_ARCHITECTURE.md`

**Future considerations**:
- MLX native provider: Bypass Ollama overhead (~13-30% speed improvement on Apple Silicon) — see [LLM_ANALYSIS_ARCHITECTURE.md](LLM_ANALYSIS_ARCHITECTURE.md)
- Per-user custom prompts for domain-specific extraction
- Multi-model ensemble for higher accuracy

### Commercialization Strategy (decided 2026-02-06)

**Decision**: Hybrid (A+B) — monetize the packaged macOS app; open-source the backend/protocol.

**Why**: Privacy/local-only wedge is real and defensible. Open-sourcing the backend builds trust ("look, no exfiltration") without commoditizing the hard part (macOS capture + permissions + UX).

**Details**: See `docs/audit/COMMERCIALIZATION_STRATEGY_AUDIT_2026-02.md`

### Gap Priorities (decided 2026-02-06)

**Decision**: Address gaps in this order: (1) NLP quality via LLM, (2) Silero VAD, (3) Distribution blockers.

**Why**: NLP quality is the #1 difference between "toy" and "product." VAD prevents hallucinations. Distribution unblocks external users.

**Details**: See `docs/audit/GAPS_ANALYSIS_2026-02.md`

### ASR Provider Strategy — Voxtral Transcribe 2 (researched 2026-02-08)

**Decision**: Try Voxtral Realtime (4B, open-source) locally as alternative ASR provider. Keep pyannote for diarization. Voxtral Mini Transcribe V2 (paid API) is optional/future — only pursue if paid plan is justified.

**Why**: Voxtral Realtime is Apache 2.0 open weights — can self-host for free with no API key. 4B params is feasible on Apple Silicon. Better accuracy than Whisper large-v3 at sub-200ms latency. Diarization stays with pyannote since V2 (the only Voxtral model with native diarization) is API-only and paid.

**What we're doing**:

| Component | Now | Future (if paid justified) |
|-----------|-----|---------------------------|
| Live transcription | Faster-Whisper (default) + Voxtral Realtime local (try out) | Voxtral Realtime API ($0.006/min) |
| Diarization | pyannote (keep as-is) | Voxtral Mini Transcribe V2 API ($0.003/min) |

**Key facts**:
- Voxtral Realtime: 4B params, Apache 2.0, open weights on HuggingFace — free to self-host
- Voxtral Mini Transcribe V2: API-only (not open-source), $0.003/min, native diarization — skip for now
- Mistral API has free "Experiment" tier for testing if we want to try V2 later
- Same PCM16/16kHz input format EchoPanel already uses — no capture changes needed
- pyannote stays for diarization — already works, no reason to replace with a paid API

**What would change this decision**:
- If Voxtral Realtime runs well locally on M1 8GB → could become default over Faster-Whisper
- If Mistral open-sources V2 with diarization → could replace pyannote for free
- If paid V2 diarization quality is significantly better than pyannote → justify the API cost

**Details**: See `docs/VOXTRAL_RESEARCH_2026-02.md`

### Native Swift Primary ASR — NativeMLXBackend (decided 2026-02-25) ⬅ supersedes "ASR Provider Strategy — Voxtral Transcribe 2"

**Decision**: Use native Swift `mlx-audio-swift` (`NativeMLXBackend`) as the **primary** ASR path. Python FastAPI kept as **fallback only** (diarization hand-off, offline Python providers).

**Why**: EchoPanel is macOS-only. Native MLX runs entirely in unified memory — no CPU↔GPU transfer, no process IPC overhead, lower latency, lower power draw. The macOS app already has `NativeMLXBackend.swift`, `HybridASRManager`, and `ASRBackendProtocol` and builds successfully.

**Feature flags set**:
- `nativeBackendRolloutPercentage = 100`
- `isDevMode = true`

**What changed**:
- Primary ASR moves from Python faster-whisper/Voxtral → Swift mlx-audio-swift
- Voxtral Realtime (Python self-host) is no longer the evaluation target
- pyannote diarization is ALSO being replaced (see FluidAudio decision below)

**What stays**:
- Python FastAPI server remains for session HTTP API and complex LLM fallback until full Swift rewrite is complete

**What would change this decision**:
- If mlx-audio-swift develops a blocking bug on a required macOS release

---

### ASR Model Fallback Chain (decided 2026-02-25)

**Decision**: Use the following ordered fallback chain inside `NativeMLXBackend` / `HybridASRManager`:

1. `Qwen3-ASR-0.6B-4bit` (fastest, lowest RAM)
2. `Qwen3-ASR-1.7B-4bit`
3. `Qwen3-ASR-1.7B-8bit`
4. `GLM-ASR-Nano-2512-4bit` (batch-only — no streaming)
5. `PythonBackend` (FastAPI fallback)

**Constraints**:
- `StreamingInferenceSession` in mlx-audio-swift only works with `Qwen3ASRModel` — GLM is batch-only
- `Parakeet-TDT-0.6b-v3` (best English ASR benchmark) is **not yet available** in the Swift API — revisit when mlx-audio-swift adds support

**Fallback triggers**:
- OOM on model load
- RTF > 2.0 sustained for 3 consecutive chunks
- 3 consecutive inference errors

---

### Diarization + VAD: FluidAudio replaces pyannote (decided 2026-02-25) ⬅ supersedes "pyannote stays" from Voxtral decision

**Decision**: Replace `pyannote.audio` (Python / torch / GPU) with `FluidAudio` (Swift / CoreML / ANE) for both diarization and VAD.

**Why**: ANE execution is lower-power than pyannote's GPU path. Removes the HuggingFace token requirement. Keeps the entire pipeline inside the macOS app with no Python dependency for these two components.

**FluidAudio details**:
- Repo: `github.com/FluidInference/FluidAudio`
- Architecture: Sortformer-based diarization
- Distribution: open-source
- Used by: BoltAI, VoiceInk, Whisper Mate

**VAD**:
- Replaces Silero VAD Python with `FluidAudio VadManager` (same Silero model weights → CoreML)

**What changes**:
- `pyannote.audio` dependency removed from Python server once Swift migration complete
- Silero VAD Python path becomes unreachable after FluidAudio VAD is stable

**What would change this decision**:
- If FluidAudio diarization accuracy degrades significantly vs pyannote on our test corpus

---

### Full FastAPI Replacement Stack (decided 2026-02-25)

**Decision**: Replace each remaining Python service with a native Swift equivalent:

| Service | Python (current) | Swift replacement | Model / library |
|---------|-----------------|-------------------|-----------------|
| Embeddings | sentence-transformers | `MLXEmbedders` (ml-explore/mlx-swift-lm) | Qwen3-Embedding-0.6B-4bit |
| LLM analysis | Ollama / OpenAI | `MLXLLM ChatSession` (ml-explore/mlx-swift-lm) | Qwen3-4B-4bit or SmolLM2-1.7B |
| OCR text | pytesseract / EasyOCR | Apple Vision `VNRecognizeTextRequest` (built-in) | — |
| OCR VLM | — | `MLXVLM` (ml-explore/mlx-swift-lm) | SmolVLM2-256M |
| Storage / RAG | SQLite + pgvector | `GRDB.swift` + vDSP brute-force cosine | — |

**Why**: Eliminates Python process management overhead; keeps everything in unified memory; reduces app bundle complexity. vDSP brute-force cosine is adequate for EchoPanel's corpus size (no need for approximate nearest-neighbour index).

**Transition**: Python FastAPI kept for session HTTP API and complex LLM fallback until full Swift rewrite is validated.

**Details**: See `docs/research/NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`

---

### Minimum Deployment Target: macOS 14.0 (confirmed 2026-02-25)

**Decision**: macOS 14.0 (Sonoma) is the minimum deployment target. Do **not** lower it.

**Why**: Required by mlx-audio-swift, FluidAudio, and SwiftData. Already set in `Package.swift`.

---

## 2026-02-26 Research Sprint Decisions

Research sprint: 4 agents × 4 research docs. Sources: `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md`, `RAM_BUDGET_ANALYSIS_2026-02-26.md`, `ASR_BENCHMARK_COMPARISON_2026-02-26.md`, `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md`.

---

### DEC-026: Qwen3-ASR-0.6B-4bit confirmed as primary ASR (decided 2026-02-26)

**Decision**: Qwen3-ASR-0.6B-4bit remains the primary ASR model. No change from Feb 25 selection — now benchmark-verified.

**Why**: 5.8% WER on LibriSpeech, RTF < 0.1 on M1/M2, ~720 MB runtime RAM, streaming via `generateStream` (PR #32). Best balance of accuracy, speed, and memory for the 8 GB Mac target. Full `generateStream` support (chunk-by-chunk) confirmed in mlx-audio-swift v0.1.0.

**Evidence**: `ASR_BENCHMARK_COMPARISON_2026-02-26.md` §1, verified disk size 676 MB via HF API (`RAM_BUDGET_ANALYSIS_2026-02-26.md` §1a).

---

### DEC-027: Parakeet-TDT added to ASR fallback chain as P5 (decided 2026-02-26)

**Decision**: `ParakeetModel` (variant: `tdt`, model slug: `nvidia/parakeet-tdt-0.6b-v2`) is added to the fallback chain at **position 5**, replacing the former GLM-ASR-Nano slot.

**Updated fallback chain:**
1. `Qwen3-ASR-0.6B-4bit` (fastest, lowest RAM — primary)
2. `Qwen3-ASR-1.7B-4bit` (higher accuracy, 8 GB viable)
3. `Qwen3-ASR-1.7B-8bit` (quality fallback — M2+ 16 GB only)
4. ~~`GLM-ASR-Nano`~~ → removed (batch-only, no streaming, no active development)
5. `Parakeet-TDT-0.6B-v2` (~1.2 GB, 4.8% WER, streaming — pending Q2 2026 Apple Silicon benchmark)
6. `PythonBackend` (FastAPI fallback)

**Why**: Parakeet is now available in Swift (PR #51, mlx-audio-swift v0.1.0). Better WER (4.8% vs 5.8%), lower first-token latency (50–150 ms vs 200–400 ms), native timestamps. Held at P5 until Apple Silicon RTF and meeting-audio WER are measured on real data (Q2 2026).

**Evidence**: `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.2, §5; `ASR_BENCHMARK_COMPARISON_2026-02-26.md` §3.

---

### DEC-028: FluidAudio confirmed as primary diarization solution (decided 2026-02-26)

**Decision**: FluidAudio (`github.com/FluidInference/FluidAudio`) is confirmed as the diarization + VAD solution. The "binary risk" concern from the Feb 25 open questions is resolved — it is source code.

**Why**: Full source code, MIT license, Swift 6 strict concurrency, 1,560 stars, 20+ production apps. ANE-based (`.mlmodelc` via `cpuAndNeuralEngine`). Three diarization pipelines: `DiarizerManager` (online), `OfflineDiarizerManager` (VBx batch, best DER), `SortformerDiarizer` (real-time streaming). Actively maintained (commits every few days).

**Correct API (supersedes Feb 25 research doc):**
```swift
// Load models first (separate step)
let models = try await DiarizerModels.download()
let diarizer = DiarizerManager()          // synchronous init — no model enum
diarizer.initialize(models: models)
let result = try diarizer.performCompleteDiarization(audioSamples)
```

**Evidence**: `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` (full report). API examples in `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` must be updated.

---

### DEC-029: SortformerDiarizer (mlx-audio-swift) as alternative diarization option (decided 2026-02-26)

**Decision**: `mlx-audio-swift`'s native Sortformer diarization (PR #33, `MLXAudioVAD`) is tracked as an alternative to FluidAudio for the VAD + speaker attribution path.

**Why**: Runs in the MLX/GPU unified memory pool — same pool as ASR and LLM. Enables zero-copy pipeline (no cross-framework data transfer). Useful if FluidAudio ANE + MLX GPU thermal contention becomes a problem in practice.

**Status**: Evaluate after Q8 (diarization accuracy parity study) completes. Not replacing FluidAudio today.

**Evidence**: `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.5.

---

### DEC-030: nomic-embed-text-v1.5 as interim embedding model (decided 2026-02-26)

**Decision**: Use `mlx-community/nomic-embed-text-v1.5` (~130 MB disk, ~140 MB runtime, 768-dim) as the interim embedding model. Swap to `Qwen3-Embedding-0.6B-4bit` when the MLX 4-bit version is published publicly.

**Why**: `mlx-community/Qwen3-Embedding-0.6B-4bit` returned HTTP 401 on 2026-02-26 — not yet public. `nomic-embed-text-v1.5` is already supported as `NomicBert.swift` in `MLXEmbedders` (mlx-swift-lm 2.30.6), saves ~310 MB vs the planned Qwen3 model, Apache 2.0 license.

**Evidence**: `RAM_BUDGET_ANALYSIS_2026-02-26.md` §6; `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §3.2.

---

### DEC-031: ASR + LLM never run simultaneously — sequential phases (decided 2026-02-26)

**Decision**: The inference pipeline enforces sequential phase scheduling. ASR and LLM are never both running inference at the same time.

**Phases:**
1. **Recording** — ASR + FluidAudio diarization active; LLM unloaded
2. **Analysis** — LLM active; ASR idle (resident or evicted based on meeting length)
3. **Brain Dump** — Embeddings active; LLM evicted after analysis completes

**Why**: Verified RAM budget shows 2.3–2.6 GB for EchoPanel during any single phase, giving 1.4–1.7 GB headroom on an 8 GB Mac. Running ASR + LLM simultaneously would peak at ~3.1 GB for EchoPanel — still safe, but sequential phases leave more headroom for macOS + other apps (Chrome, Slack, Zoom).

**Implementation**: Set model reference to `nil` + call `MLX.GPU.clearCache()` when evicting. Load on demand.

**Evidence**: `RAM_BUDGET_ANALYSIS_2026-02-26.md` §3, §5.

---

### DEC-032: Pin mlx-audio-swift to `from: "0.1.0"` (decided 2026-02-26)

**Decision**: Change the Package.swift dependency from `branch: "main"` to `from: "0.1.0"` for `mlx-audio-swift`.

**Why**: v0.1.0 is the first stable tagged release (Feb 23, 2026). Tracking `branch: "main"` silently pulls breaking changes. v0.1.0 contains all features needed (Parakeet, Qwen3ASR streaming, Sortformer VAD). `swift-tools-version: 6.2` required — verify Xcode version before upgrading.

```swift
// Before (risky):
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
// After (stable):
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.0")
```

**Evidence**: `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §1, §7.

---

### DEC-033: WhisperKit NOT adopted (decided 2026-02-26)

**Decision**: WhisperKit (`argmaxinc/WhisperKit`) will not be added to EchoPanel's dependency chain.

**Why**: WhisperKit uses CoreML/ANE — a separate memory pool from MLX's unified GPU memory. Adding it would break zero-copy pipelining between ASR → embeddings → LLM. Parakeet-TDT is now available in `mlx-audio-swift` (DEC-027) and provides a better accuracy upgrade path within the same memory pool. WhisperKit's WER (8.4–12.1%) is also worse than Qwen3 (5.8%) and Parakeet (4.8%).

**What would change this**: If a future EchoPanel variant targets ANE-first architecture (e.g., battery-optimized mode leaving GPU fully for LLM).

**Evidence**: `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §4.2, §6; `ASR_BENCHMARK_COMPARISON_2026-02-26.md` §6.

---

### DEC-034: 16 GB Mac tier unlocks Qwen2.5-7B for meeting summaries (decided 2026-02-26)

**Decision**: When EchoPanel detects ≥ 16 GB unified memory, offer `mlx-community/Qwen2.5-7B-Instruct-4bit` (~4.3 GB runtime) as the analysis LLM instead of Qwen2.5-1.5B-Instruct-4bit.

**Why**: On 16 GB Macs, all models can be resident simultaneously (~7 GB total). Qwen2.5-7B provides dramatically better meeting summaries, entity extraction, and action item quality. Full 30-min transcript (~6K tokens) can fit in a single LLM pass without chunking. This is a meaningful product differentiator for users who choose higher-spec hardware.

**8 GB Mac default is unchanged**: Qwen2.5-1.5B-Instruct-4bit remains the default for memory-constrained users.

**Evidence**: `RAM_BUDGET_ANALYSIS_2026-02-26.md` §7.


---

### DEC-035: VoxtralRealtime-4bit as opt-in Premium ASR tier (decided 2026-02-26)

**Decision**: Add `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` as an opt-in Premium tier gated on ≥ 8 GB RAM + explicit user opt-in. It does NOT replace Qwen3-ASR-0.6B-4bit as the default primary.

**Why**: VoxtralRealtime (Mistral's streaming ASR LLM) achieves 4.90% WER on English and 15.05% on AMI meeting audio — competitive with Whisper large-v3 offline. However at 3.15 GB it can only coexist on ≥ 8 GB Macs and requires a custom `VoxtralRealtimeStreamingAdapter` since `StreamingInferenceSession` is hardcoded to `Qwen3ASRModel`. The 0.6B model keeps default experience fast and lightweight.

**Updated fallback chain**: Qwen3-0.6B (P1) → Qwen3-1.7B-4bit (P2) → VoxtralRealtime-4bit [opt-in, 8GB+] (P3) → Parakeet-TDT (P4) → PythonBackend (P5).

**What would change this**: If a future mlx-audio-swift release makes `StreamingInferenceSession` model-agnostic (open protocol).

**Evidence**: `VOXTRAL_LFM_RESEARCH_2026-02-26.md` §2, §5; PR #52 source.

---

### DEC-036: Replace MossFormer2 + FluidAudio with Sortformer (mlx-audio-swift) for diarization (decided 2026-02-26)

**Decision**: Use `SortformerModel` from `mlx-audio-swift` (`MLXAudioVAD`) as the primary diarization engine. FluidAudio (`SortformerDiarizer`) is secondary fallback. `MossFormer2Model` is used for speech enhancement (denoising) not diarization.

**Why**: Sortformer v2.1 achieves 11–15% DER on AMI corpus — 1–3% better than pyannote 3.1, 2× faster, streaming-ready, and ships in the same mlx-audio-swift package we already depend on. No separate Python/FluidAudio dependency needed. `MossFormer2Model` (120 MB) is a noise-suppressor that improves ASR WER by 20–30% relative, running asynchronously before ASR in the pipeline.

**Pipeline**: `Audio → MossFormer2 (150–300ms) → ASR → Sortformer (post-meeting batch) → Transcript`.

**Evidence**: `MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md` §3, §6; `RESEARCH_SUMMARY_MOSSFORMER2_SORTFORMER.md`.

---

### DEC-037: LFM-2.5-Audio (Liquid AI) rejected — proprietary license (decided 2026-02-26)

**Decision**: `mlx-community/LFM2.5-Audio-1.5B-4bit` will not be used in EchoPanel.

**Why**: Liquid Foundation Model uses a proprietary "LFM Open License" (not Apache 2.0 or MIT). Commercial use requires explicit authorization from Liquid AI. EchoPanel is a commercial product.

**Evidence**: `VOXTRAL_LFM_RESEARCH_2026-02-26.md` §3; `HF_PRO_MODELS_SWEEP_2026-02-26.md` §3.

---

### DEC-038: Add Qwen3-ForcedAligner for word-level timestamps (decided 2026-02-26)

**Decision**: Evaluate `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` for word-level timestamp alignment in transcript-to-audio sync feature. Does not block current sprint.

**Why**: Same Qwen3 family as our primary ASR, tiny model (~340 MB), enables clickable word-level sync in the transcript UI — a differentiated UX feature not available in any competing tool. Discovered as underexplored gem in HF Pro sweep.

**Evidence**: `HF_PRO_MODELS_SWEEP_2026-02-26.md` §5.

---

### DEC-039: Nomic-embed-text-v2-moe replaces v1.5 as embedding model (decided 2026-02-26)

**Decision**: Use `nomic-ai/nomic-embed-text-v2-moe` (MoE architecture, 100+ languages) instead of `nomic-embed-text-v1.5` for the Brain Dump semantic search feature.

**Why**: Drop-in upgrade, same API via `MLXEmbedders.NomicBert`, better multilingual coverage, same ~140 MB footprint. Since we haven't shipped yet, no migration cost.

**Evidence**: `HF_PRO_MODELS_SWEEP_2026-02-26.md` §4.
