# Gemma 4 / TranslateGemma / HF Transformers v5 — EchoPanel Research

**EchoPanel · Apple Silicon macOS Menu Bar App**
**Date:** 2026-02-26
**Researcher:** GitHub Copilot (pranaysuyash)
**Scope:** Gemma family (full sweep), TranslateGemma, HF Transformers versioning, viability for meeting summarization and multilingual transcription on Apple Silicon
**Status:** ✅ Complete (updated with TranslateGemma correction)

---

## Evidence Key

| Symbol | Meaning |
|--------|---------|
| ✅ Observed | Directly verified via HF API, web, or local codebase |
| ⚠️ Inferred | Reasonable conclusion; not directly runtime-tested |
| ❌ Not present | Explicitly absent from verified sources |

---

## TL;DR

1. **"Gemma 4" does not exist.** Google's latest Gemma family is **Gemma 3** (1B/4B/12B/27B) and **Gemma 3n** (E2B/E4B). There is no Gemma 4 on HuggingFace or from Google as of 2026-02-26.
2. **Gemma 3n IS the audio model.** `google/gemma-3n-E4B-it` supports ASR, audio-to-text, speech translation, and video-to-text natively. This is the "Gemma audio" model.
3. **"Transformers v4" is not a milestone — it's the old major version.** The `transformers` library is now at **v5.2.0** (stable, Feb 2026). The 4.x series ended at 4.56.0. Locally installed: 4.56.0.
4. **MLX quantized Gemma 3n audio models exist** in mlx-community, but **mlx-audio-swift has zero Gemma support** — only Whisper, Qwen3ASR, and Parakeet.
5. **Gemma license is NOT Apache 2.0** — it's the "Gemma Terms of Use" (free for commercial use with restrictions).
6. **⚠️ CORRECTION: TranslateGemma IS real.** `google/translategemma-4b-it` was released January 12, 2026 (121K downloads), with MLX 4-bit available. The user called it "GemmaTranslate" — the correct product name is **TranslateGemma**.

---

## 1. HuggingFace Model Sweep Results

### 1.1 Google Official Gemma Models (by downloads)

| Model | Downloads | Audio? | License |
|-------|-----------|--------|---------|
| google/gemma-3-1b-it | 2.4M | ❌ | gemma |
| google/gemma-3-4b-it | 1.8M | ❌ | gemma |
| google/gemma-3-27b-it | 1.6M | ❌ | gemma |
| google/gemma-3-12b-it | 1.2M | ❌ | gemma |
| google/gemma-3n-E2B-it | 276K | ✅ ASR, audio-to-text, speech translation | gemma |
| **google/gemma-3n-E4B-it** | **96K** | **✅ ASR, audio-to-text, speech translation, video-to-text** | **gemma** |

### 1.2 Gemma 3n Audio Capabilities (Observed via HF API tags)
- Tags: `automatic-speech-recognition`, `automatic-speech-translation`, `audio-text-to-text`, `video-text-to-text`
- Pipeline: `image-text-to-text` (multimodal)
- Library: `transformers`
- Audio format: 16 kHz mono PCM, 32-bit float, up to 30s per clip, ~6.25 tokens/sec
- Supports 100+ spoken languages for ASR ✅

### 1.3 MLX-Community Gemma Quantized Models (✅ Verified via HF API)

| Model | Downloads | Quant | Audio encoder included? |
|-------|-----------|-------|------------------------|
| mlx-community/gemma-3n-E2B-it-lm-4bit | 7,642 | 4-bit | ❌ Text LM only |
| mlx-community/gemma-3n-E4B-it-lm-4bit | 6,725 | 4-bit | ❌ Text LM only |
| mlx-community/gemma-3n-E2B-it-4bit | 531 | 4-bit | ⚠️ Full multimodal (needs mlx-vlm) |
| mlx-community/gemma-3n-E4B-it-4bit | 237 | 4-bit | ⚠️ Full multimodal (needs mlx-vlm) |
| lmstudio-community/gemma-3n-E4B-it-MLX-4bit | 132,245 | 4-bit | ⚠️ LM Studio multimodal |
| lmstudio-community/gemma-3n-E4B-it-MLX-8bit | 129,346 | 8-bit | ⚠️ LM Studio multimodal |

**Important:** The `-lm-4bit` variants strip the audio/vision encoders. They are text-only LLM exports usable with `mlx-lm`. For ASR, the full `-4bit` (not `-lm-4bit`) variant is needed, and it requires `mlx-vlm` (a different runtime from `mlx-audio-swift`). ⚠️ Inferred from mlx-community naming convention.

### 1.4 TranslateGemma — January 2026 (✅ Confirmed — CORRECTION to prior research)

> ⚠️ **CORRECTION:** An earlier version of this doc stated "No official Google model." This was wrong. `google/translategemma-4b-it` was released **January 12, 2026** and has **121,647 downloads**. The user's term "GemmaTranslate" refers to Google's product **TranslateGemma**.

| Model | Downloads | Created | License |
|-------|-----------|---------|---------|
| `google/translategemma-4b-it` | 121,647 | 2026-01-12 | gemma |
| `google/translategemma-12b-it` | 505,986 | 2026-01-12 | gemma |
| `google/translategemma-27b-it` | 11,570 | 2026-01-12 | gemma |

**MLX variants available (✅ Observed):**

| Model | Downloads |
|-------|-----------|
| `mlx-community/translategemma-4b-it-4bit` | 4,599 |
| `mlx-community/translategemma-4b-it-8bit` | 1,403 |
| `mlx-community/translategemma-12b-it-4bit` | 588 |
| `mlx-community/translategemma-12b-it-8bit` | 1,172 |
| `mlx-community/translategemma-27b-it-4bit` | 525 |

**What it is:**
- Fine-tune of Gemma 3 architecture (decoder-only, `image-text-to-text` tag)
- Trained on WMT24++, SMOL, GATITOS parallel corpora + RLHF with MetricX reward
- **55 languages** (high + low-resource)
- arxiv: 2601.09012 ✅ Verified in HF model tags
- Paper announced: January 15, 2026 (Google AI Blog)
- **Input: text (and images) — NOT audio.** Does NOT replace ASR.

### 1.5 "Gemma 4" Search
- Zero results for any `gemma-4-audio`, `gemma-4-speech`, or `gemma4` official models. ✅ Verified.
- Community fine-tunes labeled "gemma4b" are just Gemma 3 4B variants with misleading names.

---

## 2. Transformers Version Clarification

| Version | Status | Notes |
|---------|--------|-------|
| 4.56.0 | Installed locally (✅) | Last 4.x release; supports Gemma 3 and 3n |
| 5.0.0 | Released Dec 2025 | Major version bump; breaking changes |
| **5.2.0** | **Current stable (Feb 2026)** | Latest on PyPI; adds VoxtralRealtime, GLM-5, Qwen3.5 |

### What "Transformers v4" Means in 2026
- It's the **previous major version series** (4.0–4.56.0), now superseded by v5.x.
- It is NOT a specific milestone or separate "framework." Just the version number of `pip install transformers`.
- The 4.x series had ~56 minor releases over 2+ years. Gemma 3n support was added in late 4.x.
- The local install (4.56.0) is stale; v5.2.0 is current.

### Key Changes in v5 (Dec 2025 → Feb 2026)

| Change | Impact on EchoPanel |
|--------|---------------------|
| Breaking `from_pretrained()` rework | ⚠️ Existing Python conversion scripts may break |
| Unified `AutoProcessor` for multimodal | ✅ Simpler code for audio + vision models |
| PyTorch-primary; TF/Flax phased out | Neutral — EchoPanel uses MLX, not PyTorch at runtime |
| Native 4-bit/8-bit quantization loading | ✅ Cleaner than bitsandbytes hack |
| `transformers serve` (OpenAI-compatible) | ⚠️ Interesting for future server-side path |
| New models: VoxtralRealtime, GLM-5, Qwen3.5 | ✅ Relevant for future upgrades |

### Apple Silicon / EchoPanel Relevance
- EchoPanel runs native Swift + MLX on Apple Silicon — it does not use Python `transformers` at runtime.
- The `transformers` library is only relevant for model conversion/export workflows.
- If any server-side Python inference is added (e.g., FastAPI + TranslateGemma), pin to v5.2.x.
- Upgrade now if doing conversion work: `pip3 install --upgrade transformers`

---

## 3. MLX-Swift Ecosystem: Gemma Support Status

### mlx-audio-swift (checked in .build/checkouts/)
- **Zero Gemma references.** Grep for "gemma" returns nothing.
- Supported STT models: **Whisper**, **Qwen3ASR**, **Parakeet**
- Supported STS models: MossFormer2, SAMAudio, LFMAudio
- **Verdict: Gemma 3n audio is NOT usable via mlx-audio-swift today.** ❌

### Gap Analysis for Full Gemma 3n Audio on MLX
The mlx-community Gemma 3n 4-bit models (`gemma-3n-E4B-it-lm-4bit`) are **text-only LM exports** — the audio encoder is stripped. To use Gemma 3n for ASR on-device via MLX:
1. Someone would need to port the full multimodal pipeline (audio encoder + LM decoder) to mlx-audio-swift.
2. This is non-trivial — Gemma 3n's audio encoder is architecturally separate from the MatFormer LM backbone.
3. No one has done this yet. The lmstudio-community variants (132K downloads) suggest demand, which may drive future ecosystem support.

### Gemma 3n vs Qwen3-ASR-0.6B for EchoPanel

| Metric | Gemma 3n E2B-it (4-bit) | Qwen3-ASR-0.6B-4bit (current) |
|--------|-------------------------|-------------------------------|
| Memory (4-bit) | ~2 GB | ~1.2 GB |
| Effective params | 2B (5B raw with PLE) | 0.6B |
| ASR purpose-built | ❌ General LLM with audio | ✅ Dedicated ASR model |
| Published WER | Not reported for ASR | ~5.8% (LibriSpeech test-clean) |
| RTF on Apple Silicon | Not benchmarked | <0.1 (real-time) |
| Streaming | ❌ Clip-based (up to 30s) | ✅ Sliding window streaming |
| Timestamp output | ❌ Not reported | ✅ Via forced aligner |
| Spoken languages | ✅ 100+ | ✅ 52 |
| mlx-audio-swift support | ❌ Not integrated | ✅ Native `MLXAudioSTT` |
| Integration cost | High (new runtime: mlx-vlm) | Zero (already in use) |

**Verdict:** Gemma 3n is NOT a drop-in replacement for Qwen3-ASR in EchoPanel's streaming pipeline.

---

## 4. TranslateGemma — Detailed Analysis for EchoPanel

### What TranslateGemma Does
TranslateGemma is a translation-specialized fine-tune of Gemma 3. It accepts **text (and images) as input** and outputs **translated text**. It does NOT process audio.

**Use in EchoPanel pipeline:**
```
audio → Qwen3-ASR (transcript) → TranslateGemma-4b (translation to target language)
```

### Language Coverage
55 languages including low-resource coverage via GATITOS dataset. This is wider than Qwen3-ASR's 52 languages for the translation step specifically.

### Memory on Apple Silicon

| Model | Est. Memory (4-bit) | Fits 8 GB? | Fits 16 GB alongside ASR? |
|-------|---------------------|-----------|--------------------------|
| translategemma-4b-it-4bit | ~2.5 GB | ⚠️ load/unload | ✅ comfortably |
| translategemma-12b-it-4bit | ~7 GB | ❌ | ⚠️ tight on 16 GB |

### Feature: Could It Replace a FastAPI Translation Step?

| Consideration | Result |
|---------------|--------|
| Task fit | ✅ Dedicated translation, 55 languages |
| On-device (no cloud) | ✅ mlx-community 4-bit available |
| Streaming | ❌ Batch text input only |
| License | ⚠️ Gemma Terms — not Apache 2.0 |
| vs. Qwen3-ASR built-in multilingual | For transcription: Qwen3-ASR already outputs in source language natively |
| Unique value | ✅ Post-transcription translation, especially for low-resource language pairs |

**Bottom line:** TranslateGemma-4b-4bit is the best available on-device MLX option for a "Translate this meeting transcript" feature. It does not exist for the primary ASR pipeline.

---

## 5. Gemma License for Commercial macOS App

**License: Gemma Terms of Use** (not Apache 2.0)

Key points for EchoPanel:
- ✅ **Commercial use is permitted** (including in paid apps)
- ✅ **Redistribution of model weights is permitted** (can bundle in .app)
- ⚠️ **Must accept Gemma Terms** (gated model — requires HF sign-in to download)
- ⚠️ **Must include Gemma license notice** in your app/distribution
- ⚠️ **Cannot use Gemma name/trademark** to imply Google endorsement
- ⚠️ **Output restrictions**: cannot use outputs to train competing models
- ❌ **Not Apache 2.0** — more restrictive than typical open-source

**Practical impact:** You CAN ship Gemma 3n or TranslateGemma weights inside EchoPanel.app, but you need to include the Gemma Terms of Use notice and cannot claim Google endorsement.

---

## 6. Actionable Recommendations for EchoPanel

### 6.1 Priority Matrix

| Item | Recommendation | Priority |
|------|---------------|----------|
| "Gemma 4" adoption | ❌ Skip — does not exist | N/A |
| Gemma 3n as ASR replacement | ❌ Skip — no mlx-audio-swift support, no streaming, larger memory | None |
| Gemma 3n E2B for post-processing | 🔵 Evaluate Later — text-only `-lm-4bit` variant usable for summarization | Low |
| TranslateGemma-4b-4bit for translation | 🟡 Evaluate when "Translate Transcript" feature is requested | Medium |
| Gemma 3-4B for summarization | ❌ Skip — Qwen3 stack is better-licensed (Apache 2.0) and better-performing | Low |
| HF Transformers v5 migration | ⚠️ Watch — upgrade only if adding transformers-based server models | Medium |

### 6.2 Don't Wait for "Gemma 4"
There is no Gemma 4 on any announced roadmap. The correct audio target is **Gemma 3n E2B/E4B**. For summarization, Qwen3-4B-4bit is the better-licensed choice (Apache 2.0 vs Gemma Terms).

### 6.3 Gemma 3n Audio Is Not Ready for EchoPanel Today
- mlx-audio-swift doesn't support it ❌
- The highest-download mlx-community quants (`-lm-4bit`) have the audio encoder stripped ❌
- Would require significant porting effort to get Gemma 3n ASR running natively in Swift/MLX

### 6.4 Stick with Current ASR Stack
EchoPanel's Qwen3-ASR-0.6B-4bit via mlx-audio-swift is the mature, working path. Gemma 3n audio is interesting but not actionable without:
1. mlx-audio-swift adding a `Gemma3nModel` audio model class
2. Full multimodal pipeline (audio encoder + decoder) exported to MLX format

### 6.5 TranslateGemma Is Viable (Not Urgent)
If EchoPanel adds a "Translate Meeting Transcript" feature:
- `mlx-community/translategemma-4b-it-4bit` (4,599 downloads, Jan 2026) is ready to test
- Runs via `mlx-lm` (same runtime as current LLM tier)
- Load on demand (don't keep in memory alongside ASR model on 8 GB Mac)

### 6.6 Update Local Transformers
The installed transformers 4.56.0 is stale. If doing any Python-side model conversion work:
```bash
pip3 install --upgrade transformers  # → 5.2.0
```

### 6.7 Monitor These for Future Gemma 3n Audio on MLX
- `mlx-community/gemma-3n-E4B-it-*` — watch for full multimodal exports (not just LM)
- `mlx-audio-swift` GitHub releases — watch for Gemma3n model class
- `lmstudio-community/gemma-3n-E4B-it-MLX-*` — 132K downloads signals demand that may drive ecosystem

---

## Addendum: Direct Verification (2026-02-26, post-agent sweep)

### A1. Gemma 3n IS Natively Supported in mlx-swift-lm v2.30.6

**Confirmed via local checkout** (`Libraries/MLXLLM/Models/Gemma3nText.swift` exists).

Pre-registered `ModelConfiguration` entries in `LLMModelFactory`:
```swift
ModelConfiguration.gemma3n_E2B_it_lm_4bit  // mlx-community/gemma-3n-E2B-it-lm-4bit
ModelConfiguration.gemma3n_E4B_it_lm_4bit  // mlx-community/gemma-3n-E4B-it-lm-4bit
ModelConfiguration.gemma3n_E2B_it_lm_bf16
ModelConfiguration.gemma3n_E4B_it_lm_bf16
```
Model type key: `"gemma3n"`. Source: `Gemma3nText.swift` line 8 comment points to mlx-examples Python reference.

The `lm` variants remove all audio/vision heads — **text-only, compact**. Ideal for meeting analysis without the weight of multimodal heads.

### A2. FunctionGemma 270M — Structural Output at 270M Params

`google/functiongemma-270m-it` (47K downloads, Gemma ToU):
- 270M params — possibly ~150MB at 4bit quantization
- Designed for function calling / structured JSON output
- Same `gemma3` architecture, supported by `Gemma3TextModel` in mlx-swift-lm
- **EchoPanel use case**: structured extraction of action items, decisions, follow-ups without loading the full 1.5B Qwen model
- Not yet in `mlx-community` — would need conversion: `mlx_lm.convert --model google/functiongemma-270m-it -q`

### A3. Full mlx-community Gemma Inventory (by downloads, 2026-02-26)

| Model | Downloads | Notes |
|-------|-----------|-------|
| gemma-3-4b-it-qat-4bit | 610K | Most popular; QAT = better quality at 4bit |
| gemma-3-12b-it-qat-4bit | 148K | 16GB Mac tier |
| gemma-3-27b-it-qat-4bit | 112K | High-end |
| gemma-3-1b-it-qat-4bit | 47K | Sub-1GB, fast |
| gemma-3n-E2B-it-lm-4bit | 7.6K | **Native Swift via mlx-swift-lm** |
| gemma-3n-E4B-it-lm-4bit | 6.7K | **Native Swift via mlx-swift-lm** |
| translategemma-4b-it-8bit | 1.4K | Translation, on-demand |

### A4. Revised Gemma Relevance for EchoPanel

| Component | Current Plan | Gemma Alternative | Verdict |
|-----------|-------------|-------------------|---------|
| Meeting analysis (8GB) | Qwen2.5-1.5B-4bit | gemma-3n-E2B-it-lm-4bit (~1.1GB) | **Evaluate both** — Gemma 3n may have better instruction following |
| Meeting analysis (16GB) | Qwen2.5-7B-4bit | gemma-3-4b-it-qat-4bit (~2.2GB) | Gemma 3 QAT has 610K downloads, excellent quality. **Worth A/B** |
| Structured extraction | Qwen2.5-1.5B via prompt | functiongemma-270m-it (~150MB) | **Potential win** — dedicated function-calling model at 1/10th the size |
| Translation | Not planned | translategemma-4b-it | Optional future feature |
| ASR | Qwen3-ASR-0.6B | Gemma 3n audio (NOT in mlx-audio-swift yet) | **Stay with Qwen3-ASR** |
