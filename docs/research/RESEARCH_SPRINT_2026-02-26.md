# Research Sprint Summary — 2026-02-26

**Sprint goal:** Resolve the 4 highest-risk open questions blocking the native Swift migration architecture decision.  
**Agents run:** 4 parallel research agents  
**Decisions made:** 9 (DEC-026 through DEC-034)  
**Questions resolved:** Q1, Q3, Q4, Q6, Q7 (5 of 10)  
**Questions updated:** Q2, Q8, Q9 (3 of 10)  
**Questions still open:** Q5, Q10 (2 of 10 — both product/ops decisions, not technical blockers)

---

## Executive Summary

The four research docs produced this sprint resolve all **technical** blockers for the native Swift MLX migration. The stack fits on an 8 GB Mac (verified), FluidAudio is safe to depend on (source code, not binary), the ASR model selection is benchmark-confirmed, and the Swift library ecosystem has matured significantly since the Feb 25 baseline.

**Key headline findings:**
1. **Parakeet is now in Swift.** PR #51 in mlx-audio-swift landed ~Feb 21, 2026 — the top missing item from the previous research sprint is resolved.
2. **RAM is not the bottleneck.** The full stack peaks at 2.3–2.6 GB (EchoPanel portion) on an 8 GB Mac — 1.4–1.7 GB headroom above the 6 GB budget.
3. **FluidAudio is real source code.** The binary risk concern is eliminated. It's MIT-licensed Swift 6 source, actively maintained, with 20+ production apps.
4. **Qwen3-ASR-0.6B-4bit is benchmark-confirmed.** 5.8% WER, RTF < 0.1 on M1/M2, streaming verified.
5. **mlx-swift-lm 2.30.6 is stable.** `MLXEmbedders` ships NomicBert, Qwen3 embeddings. SemVer is now honored.
6. **Interim embedding model identified.** `nomic-embed-text-v1.5` (~140 MB) fills the gap while `Qwen3-Embedding-0.6B-4bit` awaits public release.

---

## Open Question Resolution Table

| Q# | Title | Status Before Sprint | Status After Sprint | Decision | Source |
|----|-------|---------------------|---------------------|----------|--------|
| Q1 | Parakeet not in Swift | 🔴 Open | ✅ Resolved | DEC-027 | `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.2 |
| Q2 | Vector search at scale | 🔵 Open | 🔵 Updated — interim model set | DEC-030 | `RAM_BUDGET_ANALYSIS_2026-02-26.md` §6 |
| Q3 | FluidAudio binary risk | 🔴 Blocking | ✅ Resolved — source code | DEC-028 | `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §5 |
| Q4 | RAM on 8 GB Mac | 🔴 Blocking | ✅ Resolved — 2.3–2.6 GB peak | DEC-031, DEC-033 | `RAM_BUDGET_ANALYSIS_2026-02-26.md` §4 |
| Q5 | First-run download UX | 🔵 Open | 🔵 Open (product decision) | — | `RAM_BUDGET_ANALYSIS_2026-02-26.md` §1 |
| Q6 | GLM-ASR streaming | 🔵 Open | ✅ Resolved — GLM deprioritized | DEC-026, DEC-027 | `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §2.3 |
| Q7 | mlx-swift-lm stability | 🔴 Blocking | ✅ Resolved — v2.30.6 stable | DEC-032 | `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` §3.2 |
| Q8 | Diarization accuracy parity | 🔵 Open | 🔵 Updated — new option available | DEC-029 | `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §3 |
| Q9 | ANE vs GPU contention | 🔵 Open | 🔵 Updated — risk reduced | — | `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §3 |
| Q10 | HuggingFace token / rate limits | 🔵 Open | 🔵 Open (ops decision) | — | `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` §4 |

---

## Updated ASR Fallback Chain

The Feb 25 fallback chain is updated. GLM-ASR-Nano is removed (batch-only, no streaming). Parakeet-TDT replaces it at P5.

| Priority | Model | WER | RTF (M1) | Streaming | Memory | Status | Trigger |
|----------|-------|-----|-----------|-----------|--------|--------|---------|
| **P1** | `Qwen3-ASR-0.6B-4bit` | 5.8% | < 0.1 | ✅ | ~720 MB | ✅ Primary | — |
| P2 | `Qwen3-ASR-1.7B-4bit` | ~4.5% | ~0.15 | ✅ | ~1,600 MB | Fallback | OOM / RTF > 2.0 |
| P3 | `Qwen3-ASR-1.7B-8bit` | ~4.2% | ~0.2 | ✅ | ~3,200 MB | Quality fallback (M2+ 16 GB) | User opt-in |
| ~~P4~~ | ~~`GLM-ASR-Nano`~~ | — | — | ❌ | — | ❌ Removed | — |
| **P5** | `Parakeet-TDT-0.6B-v2` | 4.8% | ~0.18–0.25 est. | ✅ | ~1,200 MB | Future (Q2 2026 eval) | Benchmark pass |
| P6 | `PythonBackend` | — | — | ✅ | — | Server fallback | Swift stack failure |

> ⚠️ P5 (Parakeet) is held at position 5 until Apple Silicon RTF and meeting-audio WER are measured empirically. The benchmark cadence is planned for Q2 2026.

---

## Updated Memory Budget (8 GB Mac)

All disk sizes from HuggingFace API (verified 2026-02-26). Runtime sizes derived from MLX loading behaviour.

### Model Roster

| Component | Technology | Disk | Runtime | Memory Pool | Notes |
|-----------|-----------|------|---------|-------------|-------|
| Qwen3-ASR-0.6B-4bit | MLX/GPU | 676 MB | ~720 MB | Unified | Primary ASR |
| FluidAudio diarization | CoreML/ANE | 242 MB | ~280–300 MB | ANE SRAM (weights in unified) | `OfflineDiarizerManager` |
| FluidAudio VAD | CoreML/ANE | 15 MB | ~20 MB | ANE SRAM | `VadManager` (actor) |
| Qwen2.5-1.5B-Instruct-4bit | MLX/GPU | 829 MB | ~870–1,300 MB | Unified | LLM analysis (8 GB default) |
| nomic-embed-text-v1.5 | MLX/GPU | ~130 MB | ~140 MB | Unified | Interim embedding |
| MLX Swift runtime | — | — | ~50–60 MB | Unified | Shared across all MLX models |
| App overhead | Swift/macOS | — | ~175 MB | CPU | SwiftUI + AVAudioEngine + buffers |

> Qwen2.5-7B-Instruct-4bit (~4.3 GB runtime) unlocks on 16 GB Macs — see DEC-034.

### Phase Budget (8 GB Mac)

| Phase | Active Components | EchoPanel RAM | + macOS 2 GB | Total | Headroom |
|-------|-------------------|---------------|--------------|-------|----------|
| Recording | ASR + FluidAudio (active) | **2.3 GB** | 4.3 GB | 4.3 GB | **1.7 GB** ✅ |
| Analysis | LLM active, ASR idle | **2.5 GB** | 4.5 GB | 4.5 GB | **1.5 GB** ✅ |
| Brain Dump | Embeddings active | **2.6 GB** | 4.6 GB | 4.6 GB | **1.4 GB** ✅ |
| All idle (worst-case idle) | All loaded, nothing running | **2.5 GB** | 4.5 GB | 4.5 GB | **1.5 GB** ✅ |

**Sequential phase rule (DEC-031):** ASR and LLM are never running inference simultaneously.

**Memory eviction rule:**
```swift
// Evict a model
model = nil
MLX.GPU.clearCache()   // Must call explicitly — MLX does not free on dereference alone
```

---

## New Findings Not in Previous Docs

### FluidAudio API Corrections

The Feb 25 research doc (`NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`) contains incorrect API examples. Required corrections:

| What we wrote | Actual API |
|---------------|-----------|
| `try await DiarizerManager(model: .sortformer)` | `DiarizerManager()` — synchronous, no model enum |
| `diarizer.diarize(audioURL: url)` | `diarizer.performCompleteDiarization(samples)` — takes `[Float]` |
| `VadManager(model: .sileroV4)` | `VadManager()` — auto-loads Silero, no model enum |
| Callback-based VAD event handling | Async/await with explicit `VadStreamState` passing |
| `VadManager` as a class | `VadManager` is an **actor** — all methods must be `await`ed |

Correct model loading pattern:
```swift
// Diarization
let models = try await DiarizerModels.download()
let diarizer = DiarizerManager()   // synchronous
diarizer.initialize(models: models)
let result = try diarizer.performCompleteDiarization(audioSamples)

// VAD (actor — always await)
let vad = try await VadManager()
var state = vad.makeStreamState()
let result = try await vad.processStreamingChunk(chunk, state: state)
state = result.state
```

### New mlx-audio-swift Models (Available Now)

| Model | PR | Type | Notes |
|-------|-----|------|-------|
| `ParakeetModel` (TDT/TDT-CTC/RNNT/CTC) | #51 | ASR | Best open-source WER in the lib |
| `VoxtralRealtime` | #52 | ASR | Mistral's real-time STT; multilingual |
| `LFM-2.5-Audio` | #53 | ASR | Liquid Foundation Model, multimodal |
| Sortformer (VAD) | #33 | Diarization | Speaker diarization in `MLXAudioVAD` |
| MossFormer2 SE | #29, #44 | Enhancement | Noise removal pre-processing |

### 16 GB Mac Tier

| Feature | 8 GB Mac | 16 GB Mac |
|---------|---------|---------|
| LLM | Qwen2.5-1.5B (829 MB disk) | Qwen2.5-7B (4.3 GB runtime) |
| ASR | Qwen3-ASR-0.6B | Qwen3-ASR-1.7B (better accuracy) |
| All models resident? | Sequential phases required | Yes — everything fits simultaneously |
| Load/unload needed? | Yes | No cold-start latency |
| Context window | 4K–8K (chunk long meetings) | 32K+ (full meeting in one pass) |

---

## New Action Items from This Sprint

| Priority | Action | Owner | Effort | Deadline |
|----------|--------|-------|--------|---------|
| 🔴 P0 | Fix Package.swift: `branch: "main"` → `from: "0.1.0"` for mlx-audio-swift | Dev | 1 min | Now |
| 🔴 P0 | Fix incorrect API examples in `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` (FluidAudio) | Dev | 30 min | Now |
| 🟡 P1 | Benchmark Parakeet-TDT-0.6b-v2 on 10+ real EchoPanel meeting recordings | Pranay | 2 days | Q2 2026 |
| 🟡 P1 | Benchmark FluidAudio vs pyannote 3.1 on 20+ real meeting recordings (Q8) | Pranay | 2–3 days | Q2 2026 |
| 🟡 P1 | Design first-run download UX for ~1.9 GB core stack (Q5) | Pranay | — | Before beta |
| 🟡 P1 | Add optional `HF_TOKEN` field to Settings and monitor rate limits (Q10) | Dev | 1 hr | Beta build |
| 🟢 P2 | Add mlx-swift-lm as direct dep in Package.swift (`from: "2.30.6"`) for MLXLLM + MLXEmbedders | Dev | 5 min | Next sprint |
| 🟢 P2 | Run Instruments Metal + CoreML profile under simultaneous ASR + diarization load (Q9) | Dev | 2 hrs | Pre-launch |
| 🟢 P2 | Add hardware-tier detection: unlock Qwen2.5-7B on 16 GB Macs (DEC-034) | Dev | 1 day | v0.3+ |
| ⚪ P3 | Evaluate MossFormer2 speech enhancement (noise pre-processing before ASR) | Dev | 1 day | Post-launch |
| ⚪ P3 | Monitor HF for `mlx-community/Qwen3-Embedding-0.6B-4bit` public release | Dev | Passive | Ongoing |

---

## Implementation Sequence Recommendation

Based on sprint findings, the recommended implementation order for the native Swift stack is:

### Week 1 — Fix & Stabilize
1. **Fix Package.swift pin** (DEC-032) — 1 minute, prevents silent breakage
2. **Fix FluidAudio API examples** in architecture doc — prevents wrong code entering macOS app
3. **Verify build** after pin change

### Week 2 — Core Pipeline
4. **Implement FluidAudio VAD** with corrected `VadManager` actor API (async/await pattern)
5. **Implement FluidAudio `OfflineDiarizerManager`** for post-recording batch diarization
6. **Wire Qwen3-ASR `generateStream`** with the confirmed streaming API

### Week 3 — Analysis Layer
7. **Add mlx-swift-lm** as direct dependency (`from: "2.30.6"`)
8. **Integrate `nomic-embed-text-v1.5`** via `MLXEmbedders.NomicBert` (DEC-030)
9. **Integrate `Qwen2.5-1.5B-Instruct-4bit`** via `MLXLLM` for meeting analysis

### Week 4 — Phase Scheduling
10. **Implement sequential phase scheduler** with `MLX.GPU.clearCache()` on eviction (DEC-031)
11. **Add memory pressure hook** (`NSProcessInfo` + `UInt64` available memory check)
12. **Add hardware tier detection** for 16 GB Mac unlock path (DEC-034)

### Q2 2026 — Validation & Upgrade Path
13. **Benchmark Parakeet-TDT** on real meeting audio; promote to P3 if criteria met
14. **Benchmark FluidAudio vs pyannote** on meeting corpus; confirm or challenge DEC-028
15. **Swap to Qwen3-Embedding-0.6B-4bit** once MLX 4-bit version ships publicly (DEC-030)

---

## Research Artifacts

| File | Purpose | Agent |
|------|---------|-------|
| `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` | FluidAudio source audit, correct API surface | FluidAudio verification agent |
| `RAM_BUDGET_ANALYSIS_2026-02-26.md` | Memory budget for 8 GB Mac, all scenarios | RAM budget agent |
| `ASR_BENCHMARK_COMPARISON_2026-02-26.md` | 6-model ASR comparison, meeting-audio analysis | ASR benchmark agent |
| `ASR_BENCHMARK_SUMMARY.md` | Quick-reference summary of ASR decisions | ASR benchmark agent |
| `README_ASR_BENCHMARK.md` | Navigation guide for ASR research docs | ASR benchmark agent |
| `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` | mlx-audio-swift v0.1.0, mlx-swift-lm 2.30.6 delta | Swift libs update agent |

---

**Document generated:** 2026-02-26  
**Status:** Final — sprint complete  
**Next sprint:** Q8 (diarization accuracy) + Q2 2026 Parakeet benchmark
