# Research Documentation Review — 2026-02-25
**Reviewer role:** Senior ML Engineer + macOS Architect  
**Scope:** Critical review of 3 research docs produced for EchoPanel native Swift stack migration  
**Files reviewed:**
- `docs/research/MAC_LOCAL_INFERENCE_COMPLETE_GUIDE_2026-02-25.md` (hereafter: **GUIDE**)
- `docs/research/MLX_ECOSYSTEM_RESEARCH_2026-02-25.md` (hereafter: **MLX-ECO**)
- `docs/research/NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` (hereafter: **NATIVE**)
- `macapp/MeetingListenerApp/Package.swift` (actual code)
- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift` (actual code)
- `docs/DECISIONS.md` (project decisions)

---

## 1. Gaps in Documentation

### 🔴 No latency/RTF benchmarks for Qwen3-ASR models on Apple Silicon
**NATIVE:15-28** defines an entire ASR fallback chain around Qwen3-ASR but provides **zero measured RTF (Real-Time Factor) numbers**. The fallback trigger mentions "RTF > 2.0" but we have no baseline RTF for Qwen3-ASR-0.6B-4bit on M1/M2/M3/M4. Without this data, the fallback thresholds are arbitrary.

### 🔴 No WER (Word Error Rate) data for Qwen3-ASR
The fallback chain ranks models by quantization level (4-bit → 8-bit) as a proxy for accuracy, but provides no WER benchmarks. We don't know if Qwen3-ASR-0.6B-4bit is 5% WER or 25% WER on English meeting audio. The entire ASR strategy rests on an unquantified model.

### 🟡 FluidAudio integration details are thin
**NATIVE:44-65** recommends FluidAudio for diarization+VAD but doesn't document:
- License terms (commercial use OK?)
- Whether the `DiarizerManager` and `VadManager` APIs shown are real or speculative
- How FluidAudio's CoreML models are updated (bundled? downloaded? version-pinned?)
- Whether FluidAudio works in a sandboxed App Store context

### 🟡 Model download UX completely unaddressed
**NATIVE:244** mentions "Need UX for first-launch model fetch" for MLXLLM (2.5GB) but doesn't discuss:
- Total first-launch download size if all models are fetched (ASR + LLM + embeddings + VAD + diarization)
- Resume-on-interrupt behavior for HuggingFace Hub downloads
- Where models are cached (`~/.cache/huggingface/` is outside sandbox)
- Progress UX for a menu bar app (no main window)

### 🟡 Memory budget for concurrent model loading not analyzed
The NATIVE doc proposes loading ASR (Qwen3-ASR) + VAD (Silero) + Diarization (Sortformer) + LLM (Qwen3-4B) + Embeddings (Qwen3-Embedding-0.6B) simultaneously. **GUIDE:459** gives individual RAM estimates but no analysis of total concurrent footprint. On a 16GB Mac, OS + app + 5 models = real pressure.

### 🟢 No mention of model versioning/update strategy
What happens when `mlx-community/Qwen3-ASR-0.6B-4bit` is updated on HuggingFace? Is the app pinned to a commit SHA? Can a bad model update break transcription silently?

---

## 2. Contradictions and Stale Info

### 🔴 DECISIONS.md says "Keep pyannote for diarization" — NATIVE doc says replace it
**DECISIONS.md:L96-100** (Voxtral decision, 2026-02-08): "Diarization stays with pyannote since V2 (the only Voxtral model with native diarization) is API-only and paid." and "pyannote stays for diarization — already works, no reason to replace with a paid API."  
**NATIVE:42-65**: Proposes replacing pyannote entirely with FluidAudio Sortformer.  
This is a **direct contradiction**. The DECISIONS.md entry was never updated to reflect the new research.

### 🟡 DECISIONS.md says "Faster-Whisper (default)" — NATIVE doc picks Qwen3-ASR as primary
**DECISIONS.md:L88-91**: "Live transcription: Faster-Whisper (default) + Voxtral Realtime local (try out)."  
**NATIVE:15-28**: Primary ASR is Qwen3-ASR-0.6B-4bit. No mention of Faster-Whisper at all.  
The research doc implicitly overrides the ASR decision without referencing it.

### 🟡 Inconsistent star counts / download counts across docs
**GUIDE:621**: `Blaizzy/mlx-audio` = 6,064 ⭐  
**MLX-ECO:396**: `Blaizzy/mlx-audio` = 6,064 ⭐ (consistent)  
But these are snapshots from one day. No dates on individual data points means they'll be stale within weeks.

### 🟢 GUIDE lists Parakeet as "best accuracy/speed" ASR; NATIVE excludes it from Swift chain
**GUIDE:400**: "Parakeet TDT 0.6B v3 — NVIDIA, best accuracy/speed (286K DL)"  
**NATIVE:35**: "Parakeet-TDT-0.6b-v3 is NOT supported by mlx-audio-swift's current Swift API"  
Not a contradiction per se — NATIVE correctly explains why — but the GUIDE's recommendation section (**GUIDE:492-498**) lists `mlx-audio → Parakeet-TDT-0.6b-v3` as the top STT choice without noting this is Python-only. A reader following the GUIDE alone would attempt Swift Parakeet and fail.

---

## 3. Unverified Claims

### 🔴 FluidAudio API examples may be speculative
**NATIVE:58-63** and **NATIVE:76-83** show `DiarizerManager` and `VadManager` Swift APIs. These APIs are not verified against the actual FluidAudio repository source code. The research doc's confidence assessment (**NATIVE** has no confidence section at all) never rates these claims. FluidAudio has **zero presence** in the current codebase — no Package.swift reference, no code usage.

### 🔴 "6 of 7 backend areas have production-ready Swift replacements today"
**NATIVE:8**: This claim is the executive summary's headline. But "production-ready" is doing heavy lifting:
- **MLXEmbedders**: Exists in `mlx-swift-lm` but has it been tested with EchoPanel's embedding dimensions and corpus?
- **MLXVLM for OCR**: SmolVLM2-256M has only 689 downloads. Production-ready?
- **FluidAudio**: Used by listed apps but we haven't verified those claims
- **vDSP brute-force vector search**: Works but calling a hand-rolled cosine search "production-ready" is generous

### 🟡 Argmax SDK v2 GA date
**MLX-ECO:460**: "General Availability: February 2026 (Early access: December 17, 2025)."  
Confidence is listed as "Medium-High" — sourced from web search, not official docs. If GA slipped, the WhisperKit Pro recommendation may not be actionable.

### 🟡 "9x faster" claim for WhisperKit Pro
**MLX-ECO:471**: "9x faster, higher accuracy than cloud APIs." This is a marketing claim from Argmax, presented without independent verification.

### 🟡 tok/s benchmarks in GUIDE
**GUIDE:57-59**: "30–70+ tok/s for 7–13B models on M3/M4." The confidence assessment says "High (web sources, consistent across multiple)" but these are not first-party measurements. The numbers are plausible but unverified on the target hardware EchoPanel users will have.

### 🟢 Sortformer "handles overlapping speech" claim
**NATIVE:55**: "Handles overlapping speech (Sortformer's key strength over pyannote)." This is a known property of Sortformer but was not verified against EchoPanel's actual meeting audio characteristics.

---

## 4. Missing Model Comparisons

### 🔴 No ASR accuracy benchmarks: Qwen3-ASR vs Whisper vs Parakeet

The ASR fallback chain picks Qwen3-ASR as primary but provides **zero comparative data**:

| Metric | Qwen3-ASR-0.6B | Whisper-large-v3-turbo | Parakeet-TDT-0.6B-v3 | Status |
|--------|----------------|------------------------|----------------------|--------|
| WER (LibriSpeech clean) | ❓ Unknown | ~2.7% | ~3.0% | **Missing** |
| WER (meeting audio, multi-speaker) | ❓ Unknown | ❓ Unknown | ❓ Unknown | **Missing** |
| RTF on M1 16GB | ❓ Unknown | ~0.15 (WhisperKit) | ❓ Unknown | **Missing** |
| RTF on M3 16GB | ❓ Unknown | ❓ Unknown | ❓ Unknown | **Missing** |
| Streaming support (Swift) | ✅ Yes | ✅ (WhisperKit) | ❌ No Swift | Known |
| 4-bit quality degradation | ❓ Unknown | N/A (WhisperKit CoreML) | ❓ Unknown | **Missing** |

**Why this matters:** The choice of Qwen3-ASR over Whisper large-v3-turbo (via WhisperKit) could be a significant accuracy regression. Qwen3-ASR-0.6B has **1,052 downloads** (**NATIVE:25**) vs WhisperKit's **4.9M downloads** (**GUIDE:406**). Download count isn't quality, but it's a proxy for community testing. Qwen3-ASR is a newer, less-validated model.

### 🟡 No TTS quality comparison
**GUIDE:415-423** lists TTS models with subjective star ratings (⭐⭐⭐⭐) but no MOS scores, no listening tests, no side-by-side. If EchoPanel ever adds TTS, this section provides no actionable comparison data.

### 🟡 No embedding quality benchmarks
**NATIVE:103-110** lists embedding models but doesn't compare MTEB scores. `Qwen3-Embedding-0.6B-4bit-DWQ` is recommended but its retrieval quality vs `all-MiniLM-L6-v2` at 4-bit is unknown.

---

## 5. Architecture Concerns (macOS App)

### 🔴 Memory pressure with concurrent MLX models
The proposed native stack loads at minimum:
| Model | Est. RAM |
|-------|----------|
| Qwen3-ASR-0.6B-4bit | ~600 MB |
| Silero VAD (CoreML) | ~50 MB |
| Sortformer Diarization | ~200 MB |
| Qwen3-4B-4bit (LLM) | ~2.5 GB |
| Qwen3-Embedding-0.6B-4bit | ~400 MB |
| **Total model memory** | **~3.75 GB** |

On a 16GB Mac with macOS using 4-6 GB, other apps using 3-5 GB, this leaves **≤4 GB headroom** — tight for MLX's Metal buffer allocation. On **8GB Macs** (still common, still the base M1 MacBook Air), this stack is **impossible**. The NATIVE doc (**line 247**) mentions "Test memory pressure on 8GB Macs" but doesn't provide a degradation strategy.

**Recommendation:** Define a tiered model loading strategy:
- 8GB: ASR only (Qwen3-ASR-0.6B-4bit), no local LLM, Python fallback for analysis
- 16GB: ASR + VAD + Diarization + small LLM (1.7B)
- 32GB+: Full stack

### 🔴 ANE vs GPU scheduling conflicts
Both FluidAudio (CoreML/ANE) and MLX (Metal/GPU) will compete for the Neural Engine and GPU. CoreML and MLX do **not** coordinate scheduling — they're separate frameworks with separate command queues. Running a CoreML diarization model on ANE while MLX runs ASR on GPU is fine, but if both try to use GPU (MLX + CoreML GPU fallback), Metal command queue contention can cause:
- Latency spikes during concurrent inference
- Memory fragmentation on unified memory
- Priority inversion (background diarization starving foreground ASR)

None of the three docs address this.

### 🟡 App Store sandbox constraints for model downloads
HuggingFace Hub downloads go to `~/.cache/huggingface/hub/`. In a sandboxed App Store app:
- The app cannot write to `~/.cache/` — only to its container (`~/Library/Containers/<bundle-id>/`)
- `mlx-audio-swift` and `mlx-swift-lm` use `huggingface_hub` (Python) or custom Swift downloaders — do they respect sandbox?
- Models totaling 3-5 GB in the sandbox container will count against the app's perceived storage
- App Review may reject if the app downloads multi-GB files on first launch without clear user consent

**This is not addressed in any of the three docs.**

### 🟡 Menu bar app background process limitations
EchoPanel is a menu bar app. On macOS:
- Menu bar apps (LSUIElement/LSBackgroundOnly) have **lower process priority** by default
- App Nap can suspend background audio processing if the app isn't actively presenting audio
- `beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled])` is needed to prevent throttling
- Metal GPU access from a background process may be deprioritized vs foreground apps

The research docs don't discuss these constraints at all.

### 🟢 No discussion of thermal throttling during sustained inference
A meeting can last 1+ hours. Sustained MLX inference on a MacBook (not plugged in) will thermal-throttle. The ASR fallback chain should consider "thermal throttle detected → fall back to smaller model" as a trigger.

---

## 6. Production-Ready NOW vs Experimental

### ✅ Production-ready (verified, widely deployed)
| Component | Package | Evidence |
|-----------|---------|----------|
| WhisperKit (open-source STT) | `argmaxinc/WhisperKit` | 4.9M CoreML model downloads, shipped in multiple apps |
| Silero VAD | `FluidInference/silero-vad-coreml` | Silero VAD is battle-tested (Python); CoreML port is newer but model is identical |
| GRDB.swift | `groue/GRDB.swift` | Mature, 7+ years, thousands of apps |
| Apple Vision OCR | `VNRecognizeTextRequest` | Apple framework, ships with macOS |
| mlx-lm (Python) | `ml-explore/mlx-lm` | Apple-maintained, well-tested |
| mlx-audio (Python) | `Blaizzy/mlx-audio` | 6K+ stars, active development |

### ⚠️ Early but usable (use with caution)
| Component | Package | Concern |
|-----------|---------|---------|
| mlx-audio-swift | `Blaizzy/mlx-audio-swift` | 360 stars, `branch: "main"` dependency (no stable release tag), API may change |
| MLXEmbedders | `ml-explore/mlx-swift-lm` | Part of a larger package, relatively new module |
| MLXLLM (Swift) | `ml-explore/mlx-swift-lm` | Works but streaming, memory management, and error handling are evolving |
| Qwen3-ASR-0.6B-4bit | `mlx-community/` | Only 1,052 downloads; limited community validation |
| Qwen3-ASR-1.7B-8bit | `mlx-community/` | Only 2,034 downloads |

### 🧪 Experimental / unverified
| Component | Package | Concern |
|-----------|---------|---------|
| FluidAudio | `FluidInference/FluidAudio` | API examples in NATIVE doc may be speculative; not in Package.swift |
| Argmax Pro SDK v2 | `argmaxinc` | Commercial, GA date uncertain, requires API key |
| MLXVLM (Swift OCR) | `ml-explore/mlx-swift-lm` | SmolVLM2-256M: 689 downloads |
| vDSP brute-force vector search | Hand-rolled | Works but not benchmarked for EchoPanel's corpus |
| Qwen3-TTS (Swift) | `mlx-audio-swift` | TTS is not currently in EchoPanel's scope; untested |

### 🚩 Key risk
**`mlx-audio-swift` is pinned to `branch: "main"`** (`Package.swift:15`). This means any commit to that repo can break the EchoPanel build. There are no stable release tags. This is the **single most critical dependency risk** in the current setup.

---

## 7. Recommended Verification Steps (Before Committing to Stack)

### Phase 1: ASR Validation (1-2 days) — BLOCKING

| # | Test | Method | Pass Criteria |
|---|------|--------|---------------|
| 1 | **Qwen3-ASR-0.6B-4bit WER on meeting audio** | Record 10 min of 2-person meeting, transcribe with Qwen3-ASR-0.6B-4bit and WhisperKit large-v3-turbo, compare WER | WER delta < 5% absolute |
| 2 | **Qwen3-ASR-0.6B-4bit RTF on M1 16GB** | Measure wall-clock time / audio duration for 5 min clip | RTF < 0.5 |
| 3 | **Qwen3-ASR-0.6B-4bit streaming latency** | Measure time from audio chunk → first token in `NativeMLXBackend` | < 500ms p95 |
| 4 | **8GB Mac feasibility** | Run NativeMLXBackend on M1 8GB MacBook Air with Safari + Zoom open | No OOM, ASR completes |
| 5 | **4-bit vs 8-bit quality delta** | Compare Qwen3-ASR-0.6B-4bit vs 0.6B-8bit WER on same audio | Quantify the accuracy cost of 4-bit |

### Phase 2: Concurrent Model Loading (1 day)

| # | Test | Method | Pass Criteria |
|---|------|--------|---------------|
| 6 | **Peak memory: ASR + VAD** | Load both, run 5 min audio, monitor `memory_footprint` | < 2 GB combined |
| 7 | **Peak memory: ASR + VAD + LLM** | Add Qwen3-4B-4bit, run analysis | < 5 GB combined on 16GB Mac |
| 8 | **Metal contention** | Run ASR (MLX) + diarization (CoreML) concurrently, check for latency spikes | No > 2x latency degradation |

### Phase 3: FluidAudio Evaluation (1 day)

| # | Test | Method | Pass Criteria |
|---|------|--------|---------------|
| 9 | **FluidAudio actually compiles** | Add to Package.swift, `swift build` | Builds without error |
| 10 | **FluidAudio API matches research doc** | Check for `DiarizerManager`, `VadManager` classes | APIs exist as documented |
| 11 | **FluidAudio diarization quality** | Run on 3-speaker meeting recording, compare with pyannote output | DER within 5% of pyannote |
| 12 | **FluidAudio license** | Read LICENSE file in repo | Compatible with commercial use |

### Phase 4: Sandbox & Distribution (0.5 day)

| # | Test | Method | Pass Criteria |
|---|------|--------|---------------|
| 13 | **Model download in sandbox** | Enable App Sandbox entitlement, attempt model download | Downloads succeed to container |
| 14 | **App Nap resilience** | Start transcription, switch to another app for 5 min, check for gaps | No audio gaps or missed segments |
| 15 | **First-launch experience** | Fresh install, measure time to first transcription (including model download) | < 3 min on 50 Mbps |

---

## 8. Missing Documentation

### 🔴 Must-write before implementation

| Document | Purpose |
|----------|---------|
| **`docs/MEMORY_BUDGET.md`** | RAM budget per Mac tier (8/16/24/32 GB), which models load, degradation strategy |
| **`docs/ASR_BENCHMARK_RESULTS.md`** | WER/RTF results from Phase 1 testing above — the data that justifies Qwen3-ASR over WhisperKit |
| **Updated `docs/DECISIONS.md`** | New entries for: (a) Qwen3-ASR as primary ASR, (b) FluidAudio replacing pyannote, (c) native Swift stack decision. Current DECISIONS.md contradicts the research. |

### 🟡 Should-write before shipping

| Document | Purpose |
|----------|---------|
| **`docs/MODEL_MANAGEMENT.md`** | How models are downloaded, cached, updated, and pinned. Sandbox behavior. First-launch UX spec. |
| **`docs/FALLBACK_CHAIN_SPEC.md`** | Formal spec for ASR fallback triggers, with measured thresholds (not the arbitrary "RTF > 2.0" currently in NATIVE doc) |
| **`docs/NATIVE_MIGRATION_PLAN.md`** | Ordered migration plan: which Python service to port first, acceptance criteria for each, rollback strategy |
| **`docs/research/FLUIDAUDIO_EVALUATION.md`** | Dedicated eval of FluidAudio: API verification, license, quality benchmarks, sandbox compatibility |

### 🟢 Nice-to-have

| Document | Purpose |
|----------|---------|
| **`docs/THERMAL_MANAGEMENT.md`** | Strategy for sustained inference (1hr+ meetings) on battery, thermal throttle detection |
| **`docs/ANE_GPU_SCHEDULING.md`** | How CoreML and MLX coexist: which models use ANE vs GPU, contention mitigation |

---

## Summary

The research is **comprehensive in breadth** — it covers the full landscape well. However, it is **weak on depth where it matters most**: the ASR accuracy/latency data that justifies the Qwen3-ASR choice, the memory budget analysis for concurrent models, and the macOS-specific constraints (sandbox, App Nap, Metal scheduling) that can make or break a menu bar app.

**Top 3 actions before any implementation:**
1. Run the Phase 1 ASR benchmarks (Section 7). If Qwen3-ASR-0.6B WER is materially worse than WhisperKit, the entire fallback chain needs redesign.
2. Update DECISIONS.md to resolve contradictions with pyannote and Faster-Whisper decisions.
3. Verify FluidAudio actually exposes the APIs documented in NATIVE — if those are speculative, the diarization story collapses.
