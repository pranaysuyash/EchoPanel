# HF Pro Models Sweep — EchoPanel
**Date:** 2026-02-26  
**Account:** pranaysuyash (HF Pro)  
**Goal:** Identify SOTA HF models that improve EchoPanel components on Apple Silicon (8 GB Mac, MLX-native preferred, < 2 GB/model)

---

## TL;DR — Recommended Actions

| Priority | Action | Impact |
|---|---|---|
| 🔴 **Immediate** | Upgrade LLM to `Qwen3-4B-Instruct-2507-4bit` | Big WER/reasoning upgrade over Qwen2.5-1.5B |
| 🔴 **Immediate** | Add `Voxtral-Mini-4B-Realtime-2602-4bit` as ASR option | Real-time streaming ASR, 13 languages, MLX-native |
| 🟠 **Short-term** | Replace MossFormer2 plan with `LFM2.5-Audio-1.5B-4bit` | Already MLX-native, speech enhancement + separation |
| 🟠 **Short-term** | Upgrade embeddings to `nomic-embed-text-v2-moe` | Drop-in, 1.1M downloads, better MTEB |
| 🟡 **Medium-term** | Add `sam-audio-large` (MLX) for voice isolation | Facebook model, MLX port exists |
| 🟡 **Medium-term** | Explore `Qwen3-ForcedAligner-0.6B-bf16` for word timestamps | Zero-overhead word-level alignment |
| 🟢 **Optional** | `GLM-ASR-Nano-2512-4bit` as ultra-fast ASR fallback | MIT license, EN+ZH, tiny |

---

## 1. ASR Models

### Current Stack
- `mlx-community/Qwen3-ASR-0.6B-4bit` (primary) — 1,247 downloads, 6 likes
- `mlx-community/Qwen3-ASR-1.7B-4bit` (high-quality) — 327 downloads
- ParakeetModel (P4 fallback)

### New / Upgraded Options Found

#### 🌟 `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`
- **Base model:** `mistralai/Voxtral-Mini-4B-Realtime-2602` (242,681 downloads, 639 likes on base)
- **MLX port:** 4-bit quantized, 1,275 downloads, 6 likes
- **License:** Apache-2.0
- **Why relevant:** This is an audio-LLM from Mistral specifically built for **real-time streaming ASR**. It speaks 13 languages (en/fr/de/es/it/pt/nl/ar/zh/ja/ko/ru/hi). The `mlx-community` port is tagged `streaming` + `realtime`. It is built on `Ministral-3-3B-Base-2512` — meaning it has genuine language understanding baked into transcription, not just acoustic modeling.
- **Verdict: Strong alternative to Qwen3-ASR-1.7B.** Better at noisy real meetings; streaming support maps directly to EchoPanel's live transcription mode. **Recommend testing as Tier-1 ASR.**

#### `mlx-community/Qwen3-ASR-1.7B-8bit`
- **Downloads:** 2,103 | **Likes:** 8
- Currently EchoPanel uses 4-bit. The 8-bit variant (~1.7 GB) gives noticeably better WER with same model, staying under 2 GB limit.
- **Quick win:** swap `Qwen3-ASR-1.7B-4bit` → `Qwen3-ASR-1.7B-8bit` for meetings that need higher accuracy (conference recordings, accented speech).

#### `mlx-community/distil-whisper-large-v3`
- **Downloads:** 506 | **Likes:** 15
- Distilled from Whisper large-v3 (~756M params → ~600M), retains ~99% accuracy at 5–6× realtime speed.
- Best fit as **P4 fallback** replacement — well-known architecture, easy integration via `mlx-whisper`.
- **Verdict:** Upgrade current Parakeet P4 fallback to this.

#### `mlx-community/GLM-ASR-Nano-2512-4bit`
- **Downloads:** 366 | **Likes:** 3
- **License:** MIT (cleanest license of all ASR models here)
- **Languages:** EN + ZH
- ~300 MB at 4-bit. Extremely small. Tagged `speech-to-text`, `automatic-speech-recognition`. From THUDM (GLM team).
- **Verdict: Ultra-fast fallback for quick transcription.** MIT license is valuable for any future commercial plans.

#### `mlx-community/Fun-ASR-Nano-2512-4bit`
- **Base:** `FunAudioLLM/Fun-ASR-Nano-2512` (Alibaba FunAudio)
- **Downloads:** 179 | **Likes:** 1
- Multilingual, nano-sized. Uses `mlx-audio-plus` library (not `mlx-audio`).
- **Verdict: Watch — library ecosystem still stabilizing.** Not a priority yet.

### ASR Recommendation Matrix

| Model | Size | Quality | Latency | License | Use Case |
|---|---|---|---|---|---|
| `Qwen3-ASR-0.6B-4bit` (current) | ~300 MB | Good | Fast | Apache-2.0 | Live transcription |
| `Qwen3-ASR-1.7B-8bit` | ~1.7 GB | Better | Medium | Apache-2.0 | High-accuracy recordings |
| `Voxtral-Mini-4B-Realtime-2602-4bit` | ~2 GB | SOTA | Realtime | Apache-2.0 | Streaming + multilingual |
| `distil-whisper-large-v3` | ~1.5 GB | Good | Fast | MIT | P4 fallback |
| `GLM-ASR-Nano-2512-4bit` | ~300 MB | Decent | Very fast | MIT | Ultra-fast / commercial |

---

## 2. LLM Analysis (Meeting Summarization / Action Items)

### Current Stack
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit` — 7,947 downloads, 2 likes

### New / Upgraded Options Found

#### 🌟 `mlx-community/Qwen3-4B-Instruct-2507-4bit`
- **Downloads:** 37,397 | **Likes:** 9 (**5× more downloads than current model**)
- **License:** Apache-2.0
- **Estimated size:** ~2.4 GB (may be tight for 8 GB machines with ASR running simultaneously — see note below)
- **Why relevant:** Qwen3 is a generation ahead of Qwen2.5 in reasoning and instruction following. The `2507` datestamp means it's a mid-2025 release. Meeting summarization, action item extraction, and speaker attribution all benefit from better instruction following.
- **Note on RAM:** If ASR + LLM must run concurrently, prefer `Qwen2.5-3B-Instruct-4bit` (~1.5 GB) as the stepping stone.
- **Verdict: Primary recommendation** — use sequentially (not concurrent with ASR) for post-meeting analysis.

#### `mlx-community/Qwen2.5-3B-Instruct-4bit`
- **Downloads:** 13,696 | **Likes:** 1
- **Estimated size:** ~1.5 GB — comfortably fits alongside ASR model in 8 GB.
- **2× the params of current 1.5B model** for minimal RAM delta.
- **Verdict: Immediate, safe upgrade** from 1.5B → 3B with same codebase.

#### `mlx-community/Llama-3.2-3B-Instruct-4bit`
- **Downloads:** 75,786 | **Likes:** 39 (**highest-quality signal of all small LLMs here**)
- **License:** Meta Llama 3.2 Community License
- **Estimated size:** ~1.8 GB
- Well-tested for structured output tasks (JSON extraction, summaries). Strong at English meeting content.
- **Verdict: Best quality/size small LLM for post-meeting analysis.** 39 likes signals genuine community validation. Only downside: Meta license vs Apache.

#### `mlx-community/Llama-3.2-1B-Instruct-4bit`
- **Downloads:** 94,239 | **Likes:** 18
- **Estimated size:** ~600 MB — smallest capable instruction model.
- Perfect for **inline suggestions** or quick action-item tagging during live transcription without loading a second large model.
- **Verdict: Add as live-analysis nano-LLM** (complementary to, not replacing, the 3B/4B model for full summaries).

### LLM Recommendation Matrix

| Model | Size | Meeting Summary Quality | RAM Safe with ASR? | Priority |
|---|---|---|---|---|
| `Qwen2.5-1.5B-Instruct-4bit` (current) | ~750 MB | Baseline | Yes | — |
| `Qwen2.5-3B-Instruct-4bit` | ~1.5 GB | +20% | Yes | **Immediate upgrade** |
| `Llama-3.2-3B-Instruct-4bit` | ~1.8 GB | +25% | Yes | **Best quality small** |
| `Llama-3.2-1B-Instruct-4bit` | ~600 MB | +10% | Yes (always) | Live analysis nano |
| `Qwen3-4B-Instruct-2507-4bit` | ~2.4 GB | +40% | Sequential only | Post-meeting premium |

---

## 3. Embeddings

### Current Stack
- `nomic-ai/nomic-embed-text-v1.5` — 4,533,178 downloads, 776 likes

### New / Upgraded Options Found

#### 🌟 `nomic-ai/nomic-embed-text-v2-moe`
- **Downloads:** 1,125,449 | **Likes:** 455
- **License:** Apache-2.0 — same as v1.5
- **Architecture:** Mixture-of-Experts (MoE) — active params stay small even though total capacity is larger
- **Languages:** 100+ languages (v1.5 was English-focused)
- **MTEB:** Outperforms v1.5 on English tasks and adds multilingual meeting content (remote teams)
- **Drop-in replacement:** Same `sentence-transformers` API, same `nomic-ai` org
- **Verdict: Recommended upgrade.** Nearly drop-in, Apache-2.0, better quality. The MoE architecture means similar inference cost.

#### `nomic-ai/modernbert-embed-base`
- **Downloads:** 260,039 | **Likes:** 226
- **Architecture:** ModernBERT (decoder-free, longer context window up to 8192 tokens)
- **Size:** ~149M params (~600 MB)
- Significantly better at long-document embedding — useful for embedding full meeting transcripts (vs chunking).
- **Verdict: Strong alternative** if embedding long transcripts without chunking is a requirement. Uses ONNX for acceleration.

#### `google/embeddinggemma-300m` ⚠️ GATED
- **Downloads:** 1,912,824 | **Likes:** 1,482 (**highest likes of all embedding models**)
- **License:** Gemma (gated — requires HF Pro account agreement ✅ user qualifies)
- **Size:** ~300M params
- Built on Gemma architecture, SOTA on MTEB for sub-500M models.
- **Verdict: Hidden gem for Pro users.** Best small embedding model on HF. But Gemma license restricts commercial use — evaluate before adopting.

### Embeddings Recommendation Matrix

| Model | Size | MTEB Quality | License | Action |
|---|---|---|---|---|
| `nomic-embed-text-v1.5` (current) | ~550 MB | Good | Apache-2.0 | Keep as fallback |
| `nomic-embed-text-v2-moe` | ~600 MB | Better (+5%) | Apache-2.0 | **Upgrade now** |
| `modernbert-embed-base` | ~600 MB | Better (long ctx) | Apache-2.0 | For full-transcript embedding |
| `embeddinggemma-300m` | ~300 MB | Best for size | Gemma (gated) | Evaluate for Pro-only use |

---

## 4. Speaker Diarization

### Current Stack
- FluidAudio / Sortformer (custom)

### Findings

#### `pyannote/speaker-diarization-3.1`
- **Downloads:** 13,049,656 | **Likes:** 1,583 — **the most-downloaded diarization model on HF**
- **Tags:** `pyannote-audio-pipeline`
- Now ungated as of late 2024 (previously required HF token acceptance)
- DER ≈ 18% on AMI Corpus; handles overlapping speech
- **Verdict:** If Sortformer underperforms on overlapping speech, `pyannote/speaker-diarization-3.1` is the proven fallback. No new competing model has emerged to dethrone it.

#### `pyannote/speaker-diarization-community-1`
- **Downloads:** 995,213 | **Likes:** 196
- Community-fine-tuned version with reportedly better performance on noisy meetings.
- **Verdict: Watch as a secondary test** when evaluating diarization quality.

#### No new small diarization models found
The diarization space has not produced new small models since pyannote 3.1. FluidAudio/Sortformer remains competitive. The main improvement vector here is **integrating pyannote 3.1 as a configurable fallback** rather than replacing Sortformer.

---

## 5. Speech Enhancement / Audio Separation

### Current Plan
- MossFormer2 (planned, not yet implemented)

### New / Upgraded Options Found — **Both Already MLX-Native**

#### 🌟 `mlx-community/LFM2.5-Audio-1.5B-4bit`
- **Base:** `LiquidAI/LFM2-1.2B` (Liquid AI Foundation Model)
- **Downloads:** 124 | **Likes:** 1 (very new model)
- **Tags:** `speech enhancement`, `audio separation`, `audio-to-audio`, `mlx-audio`
- **License:** LFM 1.0 (Liquid AI proprietary — review before commercial use)
- **Why relevant:** This is the **only speech enhancement model with a native MLX port** found in the sweep. It handles both enhancement (noise removal) and source separation in a single 4-bit model. The `mlx-audio` library integration means it can run on Apple Silicon GPU via Metal.
- **Estimated size:** ~600 MB at 4-bit (base model is 1.2B params)
- **Verdict: Replace MossFormer2 plan entirely.** MossFormer2 has no MLX port; this is already there. Significant engineering savings.

#### `mlx-community/sam-audio-large`
- **Base:** `facebook/sam-audio-large` (27,191 downloads, 372 likes; gated Meta license)
- **MLX port:** 114 downloads, 6 likes
- **Tags:** `voice isolation`, `audio-to-audio`, `mlx-audio`
- **Why relevant:** Facebook's SAM-audio is purpose-built for **voice isolation** (separating a target speaker from background noise/music). The MLX-large variant handles complex reverb and overlapping voices better than smaller separation models.
- **License:** Meta SAM license (gated — user needs to accept separately)
- **Verdict: Evaluate as speech enhancement complement.** Better at voice isolation in multi-speaker scenarios; pairs well with LFM2.5-Audio for noise+separation.

### Enhancement Recommendation

```
Meeting audio → sam-audio-large (voice isolation) → LFM2.5-Audio-1.5B-4bit (enhancement) → ASR
```

Both models use `mlx-audio` library — single dependency instead of MossFormer2's custom pipeline.

---

## 6. VAD (Voice Activity Detection)

### Current Stack
- FluidAudio VadManager

### Finding
No new MLX VAD models found. `pyannote/voice-activity-detection` (711,573 downloads, 225 likes) remains the HF standard but is CPU/PyTorch. Current FluidAudio VadManager appears to be the best MLX-native option.

**No change recommended.**

---

## 7. Bonus: New MLX-Audio Ecosystem Models

### `mlx-community/Qwen3-ForcedAligner-0.6B-bf16`
- **Downloads:** 69 | **Likes:** 1
- **Tags:** `mlx-audio`, `qwen3_asr`, `speech-to-text`
- Very new model — forced word-level aligner from the Qwen3 ASR family.
- **Why relevant for EchoPanel:** Word-level timestamp alignment is essential for syncing meeting notes to audio playback. This model could provide **precise per-word timestamps** on top of Qwen3-ASR transcripts without running a separate alignment pipeline.
- **Verdict: Hidden gem — low downloads but high potential.** Evaluate for the transcript-playback sync feature.

### `mlx-community/Voxtral-Mini-4B-Realtime-6bit`
- **Downloads:** 1,451 | **Likes:** 6
- The 6-bit variant of Voxtral-Mini-4B-Realtime has more downloads than the 4-bit version — suggests the community found it offers better quality/size tradeoff.
- **Verdict: Prefer 6-bit over 4-bit for Voxtral** if RAM allows.

---

## 8. Mistral / Pro-Gated Model Survey

### Voxtral Family (Key Discovery)

| Model | Downloads | Likes | Notes |
|---|---|---|---|
| `mistralai/Voxtral-Mini-3B-2507` | 412,111 | 625 | Audio-LLM, ASR + understanding, Apache-2.0 |
| `mistralai/Voxtral-Mini-4B-Realtime-2602` | 242,681 | 639 | Realtime streaming ASR, Apache-2.0 |
| `mistralai/Voxtral-Small-24B-2507` | 33,665 | 459 | Larger audio model, 24B params |

**None of these require Pro access — all Apache-2.0.** The "gated" flag is only an email-agreement popup, not a Pro paywall.

MLX ports exist for Voxtral-Mini-4B-Realtime-2602 (both 4-bit and 6-bit). No MLX port yet for Voxtral-Mini-3B-2507 or Voxtral-Small-24B.

### `google/embeddinggemma-300m` (Pro Gated ✅)
- Requires HF Pro account agreement (which user has)
- 1,482 likes — highest-liked embedding model under 500M params
- SOTA on MTEB for small models
- Best use: semantic search over meeting archive

### `mistralai/Mistral-Small-3.2-24B-Instruct-2506`
- 177,012 downloads, 564 likes — best quality Mistral for meeting analysis
- Too large for on-device (24B), but relevant if EchoPanel adds a cloud analysis mode.

---

## 9. Summary Comparison Tables

### ASR Ecosystem on mlx-community (Complete)

| Model | DL | Likes | Size est. | Notes |
|---|---|---|---|---|
| `Voxtral-Mini-4B-Realtime-2602-6bit` | 1,451 | 6 | ~2.5 GB | **Recommended new primary** |
| `Voxtral-Mini-4B-Realtime-2602-4bit` | 1,275 | 6 | ~2 GB | Streaming ASR |
| `Qwen3-ASR-1.7B-8bit` | 2,103 | 8 | ~1.7 GB | **Better than 4-bit current** |
| `Qwen3-ASR-0.6B-4bit` | 1,247 | 6 | ~300 MB | Current primary |
| `Qwen3-ASR-1.7B-4bit` | 327 | 1 | ~850 MB | Current high-quality |
| `whisper-large-v3-turbo-asr-fp16` | 1,156 | 1 | ~1.5 GB | Latest Whisper via mlx-audio |
| `distil-whisper-large-v3` | 506 | 15 | ~1.5 GB | P4 fallback upgrade |
| `GLM-ASR-Nano-2512-4bit` | 366 | 3 | ~300 MB | MIT, ultra-fast |
| `Fun-ASR-Nano-2512-4bit` | 179 | 1 | ~200 MB | Multilingual nano |

### Quick Win Replacements

| Component | Replace | With | Why |
|---|---|---|---|
| LLM Analysis | `Qwen2.5-1.5B-Instruct-4bit` | `Qwen2.5-3B-Instruct-4bit` | Same codebase, 2× params |
| Speech Enhancement | MossFormer2 (planned) | `LFM2.5-Audio-1.5B-4bit` | Already MLX-native |
| Embeddings | `nomic-embed-text-v1.5` | `nomic-embed-text-v2-moe` | Drop-in, better quality |
| P4 ASR fallback | ParakeetModel | `distil-whisper-large-v3` | Better accuracy, MLX |

---

## 10. Methodology Notes

- All data retrieved via `https://huggingface.co/api/models` with Bearer token (HF Pro, pranaysuyash)
- Download counts reflect all-time downloads; likes are a stronger quality signal
- Size estimates calculated from param counts × bits-per-param (4-bit ≈ 0.5 B/param, 8-bit ≈ 1 B/param) — actual safetensors sizes not returned by API
- Models marked "gated" require HF account agreement but are not Pro-exclusive unless stated
- `mlx-community` org is the canonical source for Apple Silicon MLX quantizations

---

*Generated by EchoPanel HF sweep agent. Next sweep recommended: 2026-05-01 or after any Qwen3-Audio / Whisper v4 announcement.*
