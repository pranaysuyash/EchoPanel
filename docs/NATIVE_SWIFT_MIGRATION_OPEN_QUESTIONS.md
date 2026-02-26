# Native Swift Migration: Open Questions & Gaps

**Document:** `NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`  
**Created:** 2026-02-25  
**Status:** Updated 2026-02-26 — 4 questions resolved, 3 updated, 3 open  
**Ticket:** TCK-20260225-001  
**Last sprint:** `docs/research/RESEARCH_SPRINT_2026-02-26.md`

---

## Overview

This document captures all unresolved technical, architectural, and operational questions discovered during research for the Swift MLX native stack migration (ASR, diarization, embeddings, LLM analysis, vision OCR).

Each question includes:
- **Context**: Why it matters
- **Options/Approaches**: Known paths forward
- **Decision Owner**: Who decides
- **Priority**: P0 (blocking), P1 (needed soon), P2 (nice-to-have)
- **Blocking**: Whether this blocks milestone or can be workaround-able

---

## Q1: Parakeet-TDT-0.6b-v3 Not in Swift

**Question:**  
Parakeet-TDT is the best English ASR model (286k HF downloads) but `mlx-audio-swift` only has `Qwen3ASRModel` + `GLMASRModel` classes. When will Blaizzy add Parakeet? Can we use it via a bridging approach? Should we track the mlx-audio-swift repo for additions?

**Context:**
- Parakeet-TDT-0.6b-v3 has superior accuracy on meeting audio (especially diarization hints)
- mlx-audio-swift is the official Swift MLX audio library, but limited model coverage
- We're committing to Qwen3-ASR-0.6B-4bit as primary (286MB), GLM-ASR-Nano as fallback (179MB)
- Missing Parakeet means no "gold standard" option in native Swift

**Options/Approaches:**
1. **Track & wait**: Monitor mlx-audio-swift for Parakeet support, fallback to Qwen3 now
2. **Implement wrapper**: Convert Parakeet ONNX to MLX format ourselves (effort: 3-5 days)
3. **Use server fallback**: Let FastAPI serve Parakeet if native path fails (defeats "native" goal)
4. **Evaluate Qwen3 quality**: Benchmark Qwen3-ASR-0.6B-4bit on meeting audio; may be sufficient
5. **Custom MLX bridge**: Write Swift FFI wrapper around mlx-audio's Python Parakeet support (risk: complexity)

**Decision Owner:** Pranay (architecture decision)  
**Priority:** P1 (nice-to-have for launch, not blocking)  
**Blocking:** No—Qwen3 is viable fallback, but revisit if accuracy insufficient

**Evidence/References:**
- mlx-audio-swift model classes: `Qwen3ASRModel`, `GLMASRModel` (no Parakeet)
- Parakeet-TDT popularity: 286k downloads on HF (high signal)
- Qwen3-ASR-0.6B accuracy: 4.2% WER on LibriSpeech (acceptable for meetings)

### RESOLVED — 2026-02-26 ✅

`ParakeetModel` (with TDT, TDT-CTC, RNNT, and CTC variants) was merged into `mlx-audio-swift` via **PR #51** on ≈ Feb 21, 2026 and ships in **v0.1.0** (Feb 23, 2026).

- **Recommended variant:** `nvidia/parakeet-tdt-0.6b-v2` — ~1.2 GB unified memory, best WER among variants
- **Swift API:** `ParakeetModel.generate()` and `ParakeetModel.generateStream()` (chunked streaming)
- **Decision:** DEC-027 — Parakeet-TDT added to the ASR fallback chain as **P5** (after Qwen3 options); Apple Silicon benchmarks planned for Q2 2026 before promoting to higher priority
- **Source:** `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.2

---

## Q2: Vector Search at Scale

**Question:**  
Brute-force vDSP cosine similarity is fine now but what's the threshold? Estimate ops/sec for M1/M2. At what corpus size does it become too slow? What's the migration path to `sqlite-vec` when needed?

**Context:**
- Brain Dump indexes embeddings via GRDB + vDSP cosine similarity
- Current scope: ~100-500 clips per session, ~1-10 sessions stored
- Total corpus: maybe 5k-50k embeddings before slow-down
- vDSP dot product: ~1B ops/sec per core on M1, scales with SIMD
- Future: Multi-GB corpus, real-time retrieval during active session

**Options/Approaches:**
1. **Benchmark vDSP**: Profile M1/M2 with 1k, 10k, 100k embeddings; find break-even point
2. **Implement sqlite-vec layer**: Pre-build VSS infrastructure now, keep vDSP as fallback
3. **Lazy migration**: Ship with vDSP, switch to sqlite-vec once corpus > N (TBD)
4. **Hybrid**: vDSP for hot corpus (<10k), sqlite-vec for archive
5. **Accept current limits**: Assume 50k embeddings is enough for MVP, defer VSS

**Decision Owner:** Pranay (performance target)  
**Priority:** P2 (not blocking launch, but important for scale)  
**Blocking:** No—can ship with vDSP and migrate post-launch if needed

**Evidence/References:**
- vDSP performance: https://developer.apple.com/documentation/accelerate/vdsp
- sqlite-vec: https://github.com/asg017/sqlite-vec (new, not yet production-ready for Swift)
- Current Brain Dump corpus: ~100-200 clips/session (measured from usage)

### UPDATED — 2026-02-26 🔵

Corpus size concern reduced; interim embedding model identified.

- `mlx-community/Qwen3-Embedding-0.6B-4bit` returned **HTTP 401** on 2026-02-26 — not yet public under that name
- **Interim embedding model:** `mlx-community/nomic-embed-text-v1.5` — ~130 MB disk, ~140 MB runtime, 768-dim, Apache 2.0. Already supported as `NomicBert.swift` in `mlx-swift-lm 2.30.6`'s `MLXEmbedders`
- At 768-dim, vDSP cosine brute-force handles ~50k embeddings well under 100ms on M1 — no scale blocker before launch
- **Decision:** DEC-030 — use `nomic-embed-text-v1.5` as interim; swap to Qwen3-Embedding-0.6B-4bit once the MLX 4-bit version ships publicly
- **Source:** `RAM_BUDGET_ANALYSIS_2026-02-26.md` §6, `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §3.2

---

## Q3: FluidAudio Binary Frameworks Risk

**Question:**  
CoreML models are distributed as pre-compiled binaries. What happens if Apple changes ANE architecture? Can we convert models ourselves using their möbius tool? What's the fallback if FluidAudio goes unmaintained?

**Context:**
- FluidAudio relies on Apple's Neural Engine (ANE) via CoreML
- ANE architecture changes across generations (M1 vs M2 vs M4)
- FluidAudio is less well-maintained than mlx-audio-swift
- If FluidAudio abandoned, we lose diarization without rebuilding from scratch
- Models distributed as `.mlmodel` binaries, not source

**Options/Approaches:**
1. **Audit ANE compatibility**: Test FluidAudio models on M1, M2, M4; document compatibility matrix
2. **Build model conversion pipeline**: Learn möbius tool, convert Sortformer to MLX (effort: 1-2 weeks)
3. **Backup diarization logic**: Implement VAD-only fallback (no speaker separation) in Swift
4. **Track FluidAudio maintenance**: Monitor for updates, set deadline for migration decision
5. **Dual-track**: Keep pyannote server fallback, mark FluidAudio as experimental

**Decision Owner:** Pranay (risk mitigation)  
**Priority:** P0 (blocking if FluidAudio is only diarization path)  
**Blocking:** Yes—need fallback story or commit to model conversion effort

**Evidence/References:**
- FluidAudio GitHub: https://github.com/byoungwookjang/FluidAudio
- Apple möbius tool: Part of Create ML, requires enrollment
- CoreML ANE: https://developer.apple.com/documentation/coreml/neural_engine

### RESOLVED — 2026-02-26 ✅

FluidAudio is **source code, not a binary framework** — the binary risk is eliminated.

- `Package.swift` defines FluidAudio as a **source target** (not `.binaryTarget`). Only binary dep is `ESpeakNG.xcframework` (TTS only — irrelevant to diarization/VAD).
- Full Swift 6 source code, MIT license. Can be forked and patched.
- ANE compatibility risk is low: models use `.mlmodelc` (compiled CoreML) with `computeUnits: .cpuAndNeuralEngine` — same API across M1/M2/M3/M4.
- Active maintenance: commits every few days, 1,560 stars, 191 forks, 20+ production apps (BoltAI, VoiceInk, Slipbox, SamScribe).
- Correct GitHub URL: `https://github.com/FluidInference/FluidAudio` (not the old byoungwookjang URL above)
- **Decision:** DEC-028 — FluidAudio confirmed as primary diarization solution
- **Source:** `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §5, §7, §9

---

## Q4: WhisperKit vs mlx-audio-swift Coexistence

**Question:**  
Both WhisperKit and mlx-audio-swift use Metal/MLX unified memory. What's the RAM overhead of having both loaded? Test plan needed for 8GB Mac.

**Context:**
- WhisperKit provides fallback ASR (Whisper.cpp converted to Metal)
- mlx-audio-swift is primary (Qwen3-ASR)
- Both allocate GPU memory via Metal
- On 8GB Mac, ASR + diarization + embeddings + GUI already tight
- Unknown: Does loading both simultaneously cause OOM? Swap thrashing?

**Options/Approaches:**
1. **Memory profiling session**: Load both models, measure peak GPU+CPU memory with Instruments
2. **Lazy loading**: Only load WhisperKit if mlx-audio-swift fails (avoid double allocation)
3. **Model pruning**: Use smaller Whisper model if WhisperKit becomes fallback (e.g., Tiny)
4. **Single-ASR strategy**: Commit to mlx-audio-swift, use server fallback instead of WhisperKit
5. **Memory pool**: Implement shared Metal allocator to reduce fragmentation

**Decision Owner:** Pranay (target hardware constraints)  
**Priority:** P0 (8GB Mac is target, RAM is critical)  
**Blocking:** Yes—need validated memory profile before finalizing fallback chain

**Evidence/References:**
- Metal unified memory: https://developer.apple.com/metal/
- Instruments: Memory Profile tool (built-in to Xcode)
- Current ASR model: Qwen3-ASR-0.6B-4bit = ~300MB; FluidAudio diarization = ~150MB

### RESOLVED — 2026-02-26 ✅

Two findings close this question:

**1. RAM budget verified — full stack fits comfortably on 8 GB Mac:**

| Scenario | EchoPanel RAM | + macOS 2 GB | Total | Headroom |
|---|---|---|---|---|
| Recording (ASR + Diarization) | 2.3 GB | 4.3 GB | 4.3 GB | 1.7 GB ✅ |
| Analysis (LLM active) | 2.5 GB | 4.5 GB | 4.5 GB | 1.5 GB ✅ |
| All loaded, idle | 2.5 GB | 4.5 GB | 4.5 GB | 1.5 GB ✅ |

Actual model sizes (HF API verified): Qwen3-ASR-0.6B-4bit = 676 MB disk (~720 MB runtime), FluidAudio diarization = 242 MB disk (~280–300 MB runtime including CoreML overhead).

**2. WhisperKit NOT adopted:**  
WhisperKit uses CoreML/ANE — a **separate memory pool** from MLX unified GPU memory. Running both breaks zero-copy pipelining (no shared buffer between CoreML and MLX layers) and adds a separate HuggingFace model download path. Parakeet-TDT is now available in `mlx-audio-swift` (PR #51), eliminating the need for WhisperKit as a quality fallback.

- **Decision:** DEC-031 — ASR + LLM never run simultaneously (sequential phases). DEC-033 — WhisperKit NOT adopted.
- **Source:** `RAM_BUDGET_ANALYSIS_2026-02-26.md` §4, `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §4.2, §6

---

## Q5: First-Run Model Download UX

**Question:**  
Qwen3-4B-4bit = ~2.5GB. Qwen3-ASR-0.6B-4bit = ~300MB. FluidAudio models = ? Total first-run download. Need UX design: progress bar, wifi-only option, deferred download?

**Context:**
- Users expect instant app launch, but downloading 2-3GB on first run is poor UX
- No download cache on .app distribution (each user downloads fresh)
- Cellular data cost/time is prohibitive
- Users in low-bandwidth areas may give up

**Options/Approaches:**
1. **Cloud distribution**: Ship models in .app bundle (bloats .app to ~2GB, slower download)
2. **On-demand download**: Show setup wizard, download with progress bar, wifi-only enforcement
3. **Tiered rollout**: Ship ASR models (300MB) only; defer analysis engine to later
4. **Hybrid cloud**: Offer cloud-first option, fallback to local download
5. **Background download**: Download models in background after app launch (can still use server ASR)

**Decision Owner:** Pranay (product/UX decision)  
**Priority:** P1 (affects user onboarding)  
**Blocking:** Somewhat—need clear story before beta

**Evidence/References:**
- App Store bundle size limits: 4GB max download, 5GB uncompressed
- Typical cellular: 1-2 Mbps, Wifi: 20-100 Mbps
- HuggingFace model downloads: gated by rate limits (~5MB/s with token)

### STATUS — 2026-02-26 🔵 (still open — product/UX decision)

Updated size data from the RAM budget sprint:

| Model | Disk | Notes |
|---|---|---|
| Qwen3-ASR-0.6B-4bit | 676 MB | Was estimated ~300 MB — now verified |
| FluidAudio diarization | 242 MB | HF API verified |
| FluidAudio VAD | 15 MB | HF API verified |
| Qwen2.5-1.5B-Instruct-4bit | 829 MB | HF API verified |
| nomic-embed-text-v1.5 | ~130 MB | Interim embedding model |
| **Total core stack** | **~1.9 GB** | |

This still requires a product/UX decision on download flow. Background-download-while-using-server-fallback remains viable given Python FastAPI is kept during transition.

- **Source:** `RAM_BUDGET_ANALYSIS_2026-02-26.md` §1a–§1b

---

## Q6: GLM-ASR-Nano Streaming Workaround

**Question:**  
`GLMASRModel` has its own `generateStream` but not compatible with `StreamingInferenceSession`. Can we wrap it behind the `ASRBackend` protocol for near-streaming (short batch chunks)? What latency would 2-second batch chunks give?

**Context:**
- mlx-audio-swift has `StreamingInferenceSession` for Qwen3-ASR (true streaming)
- GLM-ASR-Nano has `generateStream` but different API (not compatible)
- Fallback ASR should be streaming-like to match primary UX
- 2-second chunks = ~200ms latency (acceptable for meeting context)

**Options/Approaches:**
1. **API wrapper**: Implement adapter pattern to make GLM stream look like StreamingInferenceSession
2. **Chunk-based processing**: Accept 2-second audio buffers, reuse GLM's generateStream (pseudo-streaming)
3. **Full compatibility layer**: Fork mlx-audio-swift to add GLM streaming support
4. **Accept latency gap**: Use GLM for off-the-fly batch processing only (no streaming)
5. **Monitor mlx-audio-swift**: Wait for GLM streaming support in upstream

**Decision Owner:** Pranay (fallback strategy)  
**Priority:** P1 (fallback must feel responsive)  
**Blocking:** Somewhat—need clear latency profile

**Evidence/References:**
- StreamingInferenceSession: mlx-audio-swift/MLXAudio/MLXAudioProcessor.swift
- GLMASRModel.generateStream: mlx-audio-swift/Models/GLMASRModel.swift
- Typical meeting latency tolerance: <500ms (user acceptable)

### RESOLVED — 2026-02-26 ✅

GLM-ASR streaming is **still batch-only** in mlx-audio-swift v0.1.0. `GLMASR.swift` has no `generateStream` method and no open PRs addressing this.

The Q6 concern is moot: **GLM ASR is deprioritized** from the fallback chain. The streaming path is now:

1. **Qwen3-ASR** → full `generateStream` support (PR #32, merged before v0.1.0), chunk-by-chunk real-time
2. **Parakeet-TDT** → `generateStream` (chunked streaming, PR #51)
3. **Python FastAPI** → server fallback

There is no need to wrap GLM for pseudo-streaming. GLM's slot in the fallback chain is replaced by Parakeet-TDT.

- **Decision:** DEC-026 (Qwen3-ASR-0.6B-4bit confirmed primary), DEC-027 (Parakeet as P5 fallback replacing GLM)
- **Source:** `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.3, §2.4

---

## Q7: mlx-swift-lm Version Stability

**Question:**  
`MLXEmbedders` + `MLXLLM` moved from mlx-swift-examples to mlx-swift-lm. Is the API stable? What's the pinning strategy?

**Context:**
- Brain Dump embeds via MLXEmbedders (from mlx-swift-lm)
- Analysis engine uses MLXLLM for Qwen3-7B-Chat
- mlx-swift-lm is newer, less mature than mlx-audio-swift
- API surface may change; no SemVer guarantees yet
- Dependency pinning strategy unclear

**Options/Approaches:**
1. **Pin version**: Use exact version in Package.swift, update on tested releases
2. **Branch pin**: Pin to mlx-swift-lm main, accept instability during dev
3. **Fork safeguard**: Fork critical modules if API breaks in production
4. **Abstract interface**: Wrap MLXEmbedders/MLXLLM in own protocol, decouple from upstream
5. **Dual-source**: Keep mlx-swift-examples copy as fallback if mlx-swift-lm breaks

**Decision Owner:** Pranay (dependency management)  
**Priority:** P1 (affects build stability)  
**Blocking:** Yes—need pinning decision before CI/CD setup

**Evidence/References:**
- mlx-swift-lm: https://github.com/ml-explore/mlx-swift-lm (no SemVer tags yet)
- Current pinning: Would be `from("0.1.0")` or pinned commit SHA

### UPDATED — 2026-02-26 ✅

`mlx-swift-lm` now has a tagged release. Pinning strategy is clear.

- **v2.30.6** (Feb 18, 2026) is the current stable release. SemVer is now being honored.
- Correct package URL: `github.com/ml-explore/mlx-swift-lm` (not `mlx-swift-examples` — that's an older, superseded repo)
- `MLXEmbedders` in v2.30.6 ships `Bert.swift`, `NomicBert.swift` (nomic-embed-text), and `Qwen3.swift` — all relevant to EchoPanel
- `mlx-audio-swift` v0.1.0 already transitively requires `mlx-swift-lm ≥ 2.30.3`
- **Recommended pin:** `from: "2.30.6"` with `.upToNextMinor` for mlx-swift-lm; `from: "0.1.0"` for mlx-audio-swift
- **The previous `branch: "main"` pin for mlx-audio-swift is a P0 fix** (silent breaking changes)
- **Decision:** DEC-032 — pin mlx-audio-swift from `"0.1.0"` (was `branch: "main"`)
- **Source:** `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §1, §3.2, §7

---

## Q8: Diarization Accuracy Parity

**Question:**  
FluidAudio Sortformer vs pyannote 3.1 — is accuracy equivalent for meeting audio with 2-6 speakers? Any benchmarks for English meeting audio specifically?

**Context:**
- Current production: pyannote 3.1 on FastAPI (proven on meeting audio)
- Migration target: FluidAudio Sortformer (iOS/macOS optimized, unproven at scale)
- Risk: Speaker accuracy regression affecting transcript clarity
- No public benchmarks comparing FluidAudio to pyannote on meeting audio

**Options/Approaches:**
1. **Benchmark study**: Collect 50-100 meeting recordings, compare diarization accuracy side-by-side
2. **Accept trade-off**: Ship with FluidAudio, monitor user feedback, fallback to pyannote if needed
3. **Hybrid approach**: Use FluidAudio for VAD+segmentation, pyannote server for diarization (defeats "native" goal)
4. **Fine-tune FluidAudio**: Retrain Sortformer on meeting corpus (effort: 2-3 weeks)
5. **Implement VAD-only**: Use FluidAudio for voice activity detection, skip speaker separation

**Decision Owner:** Pranay (product quality decision)  
**Priority:** P1 (affects user experience)  
**Blocking:** Somewhat—need confidence before shipping

**Evidence/References:**
- FluidAudio: https://github.com/byoungwookjang/FluidAudio (Sortformer model)
- pyannote 3.1: https://github.com/pyannote/pyannote-audio (proven on meetings)
- Meeting audio characteristics: multiple speakers, overlaps, background noise

### UPDATED — 2026-02-26 🔵

New diarization option available; accuracy parity benchmarks still needed.

**New development:** Sortformer diarization is now natively available in **mlx-audio-swift** (PR #33, merged before v0.1.0) via `MLXAudioVAD`. This gives us a third diarization path that runs entirely in the MLX/GPU unified memory pool alongside ASR and LLM.

| Path | Technology | Memory pool | Accuracy | Status |
|---|---|---|---|---|
| FluidAudio `OfflineDiarizerManager` | CoreML/ANE | ANE SRAM | Best (VBx) | Primary (DEC-028) |
| FluidAudio `SortformerDiarizer` | CoreML/ANE | ANE SRAM | ~11% DER (DI-HARD III) | Alternative (DEC-029) |
| mlx-audio-swift `Sortformer` | MLX/GPU | Unified | TBD | New — evaluate |

**Outstanding:** Head-to-head accuracy comparison of FluidAudio vs pyannote 3.1 on real EchoPanel meeting audio remains an open action item.

- **Decision:** DEC-029 — SortformerDiarizer (in mlx-audio-swift) added as alternative to FluidAudio VAD
- **Source:** `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.5, `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §3

---

## Q9: ANE vs GPU for Different Workloads

**Question:**  
FluidAudio runs on ANE (CoreML), NativeMLXBackend runs on GPU (MLX Metal). Is there contention? Priority ordering?

**Context:**
- ANE: Apple Neural Engine, efficient for inference but specialized
- GPU: Metal GPU, flexible for various workloads
- Simultaneous usage: ASR (GPU) + diarization (ANE) + embeddings (GPU)
- Contention could cause latency spikes or thrashing

**Options/Approaches:**
1. **Profile contention**: Run simultaneous ASR + diarization, measure latency impact
2. **Sequential scheduling**: Prioritize ASR, defer diarization to background queue
3. **ANE support in MLX**: Track mlx-swift effort to support ANE (may reduce GPU contention)
4. **Resource hints**: Use Metal priority groups, ANE hints in CoreML graph
5. **Accept tradeoffs**: Run GPU-only (pyannote server for diarization as fallback)

**Decision Owner:** Pranay (performance optimization)  
**Priority:** P2 (optimization, not blocking)  
**Blocking:** No—can profile and optimize post-launch

**Evidence/References:**
- Metal GPU: https://developer.apple.com/metal/
- ANE: https://developer.apple.com/documentation/coreml/neural_engine
- mlx-swift: GPU-only as of Feb 2026 (ANE support TBD)

### UPDATED — 2026-02-26 🔵

Contention risk is lower than originally assumed; profiling still recommended.

FluidAudio is confirmed to run on ANE via `computeUnits: .cpuAndNeuralEngine` with ANE-aligned `MLMultiArray` buffers. Activation tensors live in the ANE's internal SRAM — **not in the main unified memory pool**. This means ANE and MLX GPU runs are on truly separate compute sub-systems.

Apple Silicon has independent ANE, GPU, and CPU complexes with separate command queues. Running FluidAudio (ANE) + Qwen3ASR (GPU/MLX) simultaneously should not cause architectural memory contention — only the shared thermal/power budget is a concern.

**Still open:** Empirical profiling under simultaneous load (Instruments → Metal System Trace + CoreML Profiler) is recommended before shipping to catch thermal throttling scenarios.

- **Source:** `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §3, `RAM_BUDGET_ANALYSIS_2026-02-26.md` §2

---

## Q10: HuggingFace Token for Model Downloads in Production

**Question:**  
`NativeMLXBackend` calls `Qwen3ASRModel.fromPretrained()` which downloads from HuggingFace. In production .app without a token, will public mlx-community models download without auth? Rate limits?

**Context:**
- mlx-community models are public (no auth required)
- But HuggingFace has rate limits: ~5-10 downloads per IP/hour
- Multiple app installations from same IP (office, university) could hit limits
- Unknown: Do mlx-audio-swift downloads bypass limits? Include user-agent caching?

**Options/Approaches:**
1. **Test without token**: Launch beta, monitor for download failures on shared IPs
2. **Bundle models**: Include mlx-community models in .app (bloats bundle)
3. **Optional HF token**: Let power users set HF_TOKEN env var for higher limits
4. **Fallback mirror**: Cache models on Pranay's server, fallback to HF
5. **Offline-first**: Ship with one default model, make others optional downloads

**Decision Owner:** Pranay (distribution/reliability)  
**Priority:** P1 (production reliability)  
**Blocking:** Somewhat—need fallback if rate limiting happens

**Evidence/References:**
- HuggingFace CDN limits: https://huggingface.co/docs/hub/security#rate-limiting
- mlx-community public models: https://huggingface.co/mlx-community
- Typical office: 10-50+ Macs sharing IP

### STATUS — 2026-02-26 🔵 (still open — ops/distribution decision)

No new data from the 2026-02-26 research sprint. From the FluidAudio verification: `DownloadUtils.swift` uses `HF_TOKEN` env var for private repos — all public FluidAudio and `mlx-community` models are unauthenticated. The rate-limit risk for shared IPs (offices, universities) remains unvalidated. Recommendation: expose an optional `HF_TOKEN` settings field in the first beta and monitor download failures.

- **Source:** `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §4

---

## Summary Table

| Q# | Title | Priority | Blocking | Owner | Status |
|----|------------------------------------------------------------------|----------|-----------|--------|----------------------------------|
| 1  | Parakeet-TDT-0.6b-v3 not in Swift                               | P1       | No        | Pranay | ✅ Resolved 2026-02-26           |
| 2  | Vector search at scale                                          | P2       | No        | Pranay | 🔵 Updated — interim model set  |
| 3  | FluidAudio binary frameworks risk                               | P0       | ~~Yes~~   | Pranay | ✅ Resolved 2026-02-26           |
| 4  | WhisperKit vs mlx-audio-swift coexistence                       | P0       | ~~Yes~~   | Pranay | ✅ Resolved 2026-02-26           |
| 5  | First-run model download UX                                     | P1       | Somewhat  | Pranay | 🔵 Open (product decision)      |
| 6  | GLM-ASR-Nano streaming workaround                               | P1       | Somewhat  | Pranay | ✅ Resolved — GLM deprioritized  |
| 7  | mlx-swift-lm version stability                                  | P1       | ~~Yes~~   | Pranay | ✅ Resolved — pin from: "0.1.0" |
| 8  | Diarization accuracy parity                                     | P1       | Somewhat  | Pranay | 🔵 Updated — new option added   |
| 9  | ANE vs GPU contention                                           | P2       | No        | Pranay | 🔵 Updated — risk reduced       |
| 10 | HuggingFace token + rate limits                                 | P1       | Somewhat  | Pranay | 🔵 Open (ops decision)          |

---

## Blocking Dependencies

**Critical path — ~~resolved~~ as of 2026-02-26:**
1. ✅ ~~**Q3 (FluidAudio risk)**~~ → Source code confirmed, MIT license, fork-safe
2. ✅ ~~**Q4 (WhisperKit + mlx-audio coexistence)**~~ → RAM budget verified (2.3–2.6 GB); WhisperKit not adopted
3. ✅ ~~**Q7 (mlx-swift-lm stability)**~~ → v2.30.6 tagged, pin to `from: "0.1.0"` / `from: "2.30.6"`

**Still open (action required):**
4. ✋ **Q10 (HF token + rate limits)** → Add optional token field in beta settings, monitor

**High priority (should resolve in Q1–Q2 2026):**
1. **Q5 (Download UX)** → Define onboarding flow with updated 1.9 GB total size
2. **Q8 (Diarization accuracy)** → Benchmark FluidAudio vs pyannote on 20+ real meeting recordings

**Low priority (post-launch optimization):**
1. **Q2 (Vector search scale)** → vDSP is fine for MVP; revisit at >50k embeddings
2. **Q9 (ANE vs GPU)** → Run Instruments profile; low contention risk confirmed architecturally
3. **Q1 (Parakeet)** → Resolved in Swift; Q2 2026 benchmark against Qwen3 on real audio

---

## Next Steps

1. ✅ ~~**Prioritize blocking questions**~~ (Q3, Q4, Q7 resolved; Q10 remains)
2. **Fix Package.swift** — change `branch: "main"` → `from: "0.1.0"` for mlx-audio-swift (P0, 1 min)
3. **Schedule diarization accuracy study** — 20+ real meetings, FluidAudio vs pyannote (Q8)
4. **Benchmark Parakeet-TDT-0.6b-v2 on Apple Silicon** — real meeting audio, measure WER + RTF (Q2 2026)
5. **Define first-run UX** — download flow for ~1.9 GB core stack (Q5)
6. **Add HF_TOKEN settings field** in beta build and monitor rate limits (Q10)
7. **Profile ANE + MLX simultaneous load** — Instruments Metal System Trace + CoreML Profiler (Q9)
8. **Link findings to architecture document** (`NATIVE_SWIFT_ASR_ARCHITECTURE_2026-02-25.md`) — update API examples per FluidAudio verification
