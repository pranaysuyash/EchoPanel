# EchoPanel Model Benchmarking Master Plan

**Date:** 2026-03-20  
**Status:** Planning  
**Author:** Nova (AI assistant)  
**Context:** Pranay has HuggingFace Pro access + 82+ documented models. This is the plan to systematically test all relevant models across every EchoPanel ML pipeline stage.  
**Reference:** `docs/research/HF_PRO_MODELS_SWEEP_2026-02-26.md` (82+ model documentation)

---

## Executive Summary

EchoPanel has **4 ML pipeline stages**, each with model choices. This plan benchmarks all relevant models across all stages, creating a data-driven model selection guide that's tested, not guessed.

**Current best extraction result:** val_f1 = **0.9328** (+4.2% from baseline) via prompt engineering alone — no model change yet.

**Estimated time to full benchmark:** 2–3 weeks of autonomous loop runs.

---

## The 4 Pipeline Stages

```
Audio Recording
    ↓
[1] ASR / Transcription        ← faster-whisper / mlx_whisper
    ↓
[2] Speaker Diarization        ← Basic (no dedicated model yet)
    ↓
[3] LLM Extraction            ← Ollama + system prompt
    ↓  structured: actions, decisions, topics
[4] Semantic Search / RAG     ← all-MiniLM-L6-v2 embeddings
    ↓
Search Results + Meeting Intelligence UI
```

Each stage can be independently benchmarked and optimized.

---

## Stage 1: ASR / Transcription

### Current State
- **Primary:** `faster-whisper` (Distil-Whisper variant) — 769M params, CPU/CUVN inference
- **MLX alternative:** `mlx-community/Whisper-small-mlx` — 244M params, Apple Silicon native
- **Context:** EchoPanel also tested `whisper-timestamped` and `whisper.cpp`

### What matters for ASR

ASR quality is measured by **downstream extraction F1** — a better transcript leads to better extraction. However, we can also measure:
- **WER (Word Error Rate)** — standard ASR metric, requires reference transcripts
- **Speaker timestamp accuracy** — critical for diarization
- **RTF (Real-Time Factor)** — how fast vs. audio duration (lower is better)

### Candidate Models (from HF Pro model sweep + mlx-community)

| Model | Size | Type | Hardware | Status in HF Sweep |
|-------|------|------|----------|-------------------|
| `SunoAI/bark-ultra` | — | ASR | CUDA | Not tested |
| `openai/whisper-large-v3` | 1.56B | ASR | T4+ | ✅ WER 11.3% |
| `openai/whisper-medium` | 769M | ASR | T4 | ✅ WER 15.4% |
| `openai/whisper-small` | 244M | ASR | T4 | ✅ WER 17.6% |
| `mlx-community/Whisper-small-mlx` | 244M | ASR | MLX (Apple Silicon) | ⭐ Priority test |
| `mlx-community/parakeet-tdt-0.6b-v3` | 600M | ASR | CUDA | Partially tested |
| `mlx-community/Qwen3-ASR-0.6B` | 600M | ASR | MLX | ⭐ Priority test |
| `mlx-community/Qwen3-ASR-1.7B` | 1.7B | ASR | MLX | ⭐ High priority |
| `mlx-community/faster-whisper-small` | — | ASR | MLX | ⭐ Test |
| `mlx-community/voxtral-medium-en-2.5B` | 2.5B | ASR | MLX | 7K downloads |

### Benchmark Protocol for ASR

```python
# scripts/benchmark_asr.py
# 1. Load reference transcripts (already have in meetings.jsonl)
# 2. For each ASR model:
#    a. Run transcription on the audio version of test meetings
#    b. Compute WER against reference text
#    c. Measure RTF
# 3. Run extraction downstream on ASR output → measure val_f1
# 4. Rank by: val_f1 (primary), WER (secondary), RTF (tertiary)
```

**Note:** We need audio files for the test meetings to benchmark ASR directly. Current test set (meetings.jsonl) has transcripts only.

### ASR Test Set Requirement

To benchmark ASR models, we need audio recordings paired with transcripts. Options:
1. **Synthetic audio** — generate TTS audio from existing transcripts (using Bark or XTTS)
2. **Real meeting audio** — Pranay records/collects real meeting audio with transcripts
3. **VoxPopuli** — open-source multilingual speech dataset (has meeting-like data)

### Priority ASR Experiments

1. **`mlx-community/Whisper-small-mlx`** — direct drop-in for faster-whisper, native MLX
2. **`mlx-community/Qwen3-ASR-1.7B`** — 1.7B, multilingual, MLX-native
3. **`mlx-community/Qwen3-ASR-0.6B`** — 600M, fastest MLX ASR, good for short meetings
4. **`openai/whisper-large-v3`** — via HF Inference API (Pro endpoint) for cloud comparison

---

## Stage 2: Speaker Diarization

### Current State
- **Basic implementation** — speaker labels from ASR output, no dedicated model
- **Challenge:** Meetings have overlapping speech, speaker changes, background noise

### Candidate Models (from HF Pro model sweep)

| Model | Size | Type | Hardware | Status |
|-------|------|------|----------|--------|
| `pyannote/segmentee-3.0` | — | Speaker Diarization | T4+ | ⭐ Priority |
| `pyannote/EBR-0.1` | — | Speaker Diarization | T4+ | ⭐ Priority |
| `pyannote/spkinet-2.1` | — | Speaker Diarization | T4+ | ⭐ Priority |
| `pyannote/NeMo-TitaNet-L-112d` | — | Speaker Embeddings | T4+ | Medium |
| `pyannote/NeMo-TitaNet-BL-112d` | 77M | Speaker Embeddings | T4+ | Medium |

### Benchmark Protocol for Diarization

Diarization quality is harder to measure in isolation. Options:
1. **Downstream task metric** — if speaker attribution in extracted actions is correct, diarization is "good enough"
2. **Diarization Error Rate (DER)** — requires annotated speaker boundaries (time-stamped speaker segments)
3. **Practical test** — run full pipeline, measure how often action items are attributed to the wrong speaker

### Recommended Approach

Create a small annotated test set of 5 meetings with known speaker segments. Measure DER (diarization error rate). Run pyannote models via HF Inference API.

---

## Stage 3: LLM Extraction (echoai-mlx Loop)

### Current State
- **Loop status:** Running. Current best: **val_f1 = 0.9328** (system_prompt=4, top_p=0.8, few_shot=1)
- **Improvement from baseline:** +4.2% (0.895 → 0.9328)
- **Model:** Llama-3.2-3B-Instruct-4bit (MLX-native)

### What the echoai-mlx Loop Still Needs to Test

The loop has run 10 experiments so far. Still to try:

| Experiment | Description | Expected Impact |
|-----------|-------------|----------------|
| Gemma-3-4b | Try Google's model | Unknown — may beat Llama on extraction |
| Qwen3-4B | Qwen's model | Strong on structured output |
| Temperature sweep | 0.02, 0.05, 0.3 | May find better extraction temp |
| Max_tokens | 256, 768 | May affect truncated outputs |
| Smaller models | Llama-3.2-1B-Instruct | May match 3B at lower memory |
| Phi-4-mini | Microsoft's model | Strong on reasoning tasks |

### Full Extraction Model Candidates (from HF Pro sweep)

From `HF_PRO_MODELS_SWEEP_2026-02-26.md`, relevant extraction models:

| Model | Size | Strengths | Hardware |
|-------|------|-----------|----------|
| `google/gemma-3-4b-it-qat-4bit` | 4B | Multilingual, strong reasoning | MLX ⭐ |
| `google/gemma-3-1b-it-qat-4bit` | 1B | Fast, local | MLX ⭐ |
| `Qwen/Qwen3-4B` | 4B | Code + math + reasoning | T4+ |
| `Qwen/Qwen3-1.5B` | 1.5B | Fast, strong | T4+ |
| `microsoft/Phi-4-mini-instruct` | 3.8B | Reasoning, small footprint | T4+ |
| `meta-llama/Llama-3.2-3B-Instruct` | 3B | Current baseline | MLX |
| `meta-llama/Llama-3.2-1B-Instruct` | 1B | Smaller, faster | MLX |
| `mistralai/Mistral-Small-3.1-24B-Instruct` | 24B | Best open-weights overall | T4+ |
| `deepseek-ai/DeepSeek-V3-0324` | 236B | Best open-weights overall | T4+ |

### HF Pro Cloud Inference for Extraction

With HuggingFace Pro, can test **T4/GPU endpoints** for larger models:

```python
from huggingface_hub import InferenceClient

client = InferenceClient(model="meta-llama/Llama-3.2-70B-Instruct", token=HF_TOKEN)
# Works for: Mistral-Small-3.1-24B, Qwen3-72B, Gemma-3-27B, DeepSeek-V3
```

**Key insight:** Larger models via HF Pro cloud might dramatically outperform MLX-local smaller models for extraction. Need to test both.

### Priority Extraction Experiments

1. **`mlx-community/gemma-3-4b-it-qat-4bit`** — 4B, Google, MLX-native
2. **`mlx-community/Qwen3-4B-Q4_K_XL`** — 4B, Qwen, MLX-native
3. **Llama-3.2-1B-Instruct** — smaller model, may match 3B
4. **HF Pro: Mistral-Small-3.1-24B-Instruct** — cloud, 24B
5. **HF Pro: Gemma-3-27B-it** — cloud, 27B

---

## Stage 4: Semantic Search / Embeddings

### Current State
- **Model:** `all-MiniLM-L6-v2` (sentence-transformers, 384 dims)
- **Storage:** ChromaDB vector store
- **Search:** Reciprocal Rank Fusion (RRF) combining keyword + semantic

### What matters for embeddings

- **Retrieval accuracy** — does the right document rank highest?
- **Embedding dimension** — affects storage and search speed
- **Inference speed** — embeddings generated per-query and per-document

### Candidate Embedding Models (from HF Pro sweep)

From `HF_PRO_MODELS_SWEEP_2026-02-26.md`:

| Model | Dims | Max Tokens | MTEB Score | Hardware |
|-------|------|-----------|-----------|----------|
| `BAAI/bge-m3` | 1024 | 8192 | 64.2% | T4+ |
| `sentence-transformers/all-MiniLM-L6-v2` | 384 | 256 | 57.5% | CPU ⭐ (current) |
| `sentence-transformers/all-mpnet-base-v2` | 768 | 384 | 62.3% | CPU |
| `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | 384 | 128 | 57.0% | CPU |
| `intfloat/e5-mistral-7b-instruct` | 1024 | — | 66.4% | T4+ (too large) |
| `intefloat/e5-base-v2` | 768 | 512 | 62.5% | CPU |

MLX embedding models (Apple Silicon native):

| Model | Dims | Hardware |
|-------|------|----------|
| `mlx-community/all-MiniLM-L6-v2-4bit` | 384 | MLX ⭐ |
| `mlx-community/e5-base-4bit` | 768 | MLX |

### Benchmark Protocol for Embeddings

Create a retrieval test set:
```json
{
  "query": "What was decided about the v2 launch?",
  "relevant_segments": ["We decided to ship by March 30th", "Launch date is March 30"],
  "irrelevant_segments": ["The API docs are ready", "Mike will handle testing"]
}
```

Measure:
- **Recall@K** — is the relevant segment in top-K results?
- **MRR (Mean Reciprocal Rank)** — where does the first relevant result rank?
- **NDCG** — normalized discounted cumulative gain

### Priority Embedding Experiments

1. **`BAAI/bge-m3`** — 1024 dims, best MTEB score, supports 8K context
2. **`mlx-community/all-MiniLM-L6-v2-4bit`** — native MLX, no CPU overhead
3. **`intfloat/e5-base-v2`** — strong CPU option, 768 dims
4. **`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`** — multilingual support (future)

---

## Full Benchmark Architecture

### Project Structure

```
~/Projects/echoai-mlx/
├── prepare.py              # Fixed: data, eval harness (sacred)
├── train.py                # Mutable: extraction model + prompt
├── results.tsv             # Experiment log
│
# ASR benchmarking (NEW)
├── benchmark_asr.py        # ASR model benchmark script
├── data/asr/               # Audio + transcript pairs for ASR testing
│
# Diarization benchmarking (NEW)
├── benchmark_diarization.py
├── data/diarization/       # Annotated speaker segments
│
# Embedding benchmarking (NEW)
├── benchmark_embeddings.py
├── data/retrieval/         # Query + relevant + irrelevant segments
│
# Extraction (existing, running)
├── echoai-mlx/             # The LLM extraction loop
└── results/
    └── MODEL_BENCHMARK_SUMMARY.tsv
```

### Test Set Requirements

| Stage | What we have | What we need |
|-------|-------------|-------------|
| ASR | Transcripts (4 meetings) | Audio files + transcripts |
| Extraction | ✅ Full ground truth (4 meetings) | Expand to 20+ meetings |
| Embeddings | None yet | 50+ query/segment triples |
| Diarization | None | 5+ meetings with speaker annotations |

### Creating Expanded Test Sets

**For extraction (high priority, easiest):**
```bash
# Run LLM to generate synthetic meetings
python scripts/generate_synthetic_meetings.py --count 20 --domain tech --output data/test/expand.jsonl
```

**For retrieval (medium priority):**
```bash
# Generate query/segment pairs from existing meeting transcripts
python scripts/generate_retrieval_test_set.py --meetings data/test/meetings.jsonl --output data/retrieval/test.jsonl
```

**For ASR (requires audio):**
```bash
# Use Bark/XTTS to generate TTS audio from existing transcripts
python scripts/tts_from_transcript.py --input data/test/meetings.jsonl --output data/asr/
```

---

## HF Pro Integration

### Setting Up HF Pro Credentials

```bash
export HF_TOKEN="hf_xxxx"  # from huggingface.co/settings/tokens
```

### Inference API Access

With HF Pro, you get:
- **Priority access** to T4/H100 endpoints
- **Higher rate limits** for API calls
- **Private model access**

```python
from huggingface_hub import InferenceClient

client = InferenceClient(
    model="mistralai/Mistral-Small-3.1-24B-Instruct",
    token=HF_TOKEN,
    timeout=120
)

# Test large models via cloud
response = client.chat_completion(
    messages=[{"role": "user", "content": prompt}],
    max_tokens=512
)
```

### Recommended HF Pro Cloud Models to Test

| Model | Why |
|-------|-----|
| `mistralai/Mistral-Small-3.1-24B-Instruct` | Best quality/speed for extraction |
| `deepseek-ai/DeepSeek-V3-0324` | Best overall open-weights |
| `google/gemma-3-27b-it` | Google's best, strong reasoning |
| `Qwen/Qwen3-72B-Instruct` | Qwen's largest, multilingual |
| `meta-llama/Llama-3.1-70B-Instruct` | Meta's large model |
| `openai/whisper-large-v3` | Best ASR, via HF endpoint |
| `SunoAI/bark-ultra` | Best TTS for synthetic audio generation |

---

## Master Results Summary Table

Will be populated after benchmarks complete.

### Extraction Results (echoai-mlx loop)

| Commit | Model | Prompt | Temp | Few-shot | top_p | val_f1 | Status |
|--------|-------|--------|------|----------|-------|--------|--------|
| c6e2e9e | Llama-3.2-3B | 0 | 0.1 | 0 | 0.9 | 0.8950 | baseline |
| ... | ... | ... | ... | ... | ... | ... | ... |

### ASR Results (to be populated)

| Model | WER | RTF | Downstream val_f1 | Notes |
|-------|-----|-----|------------------|-------|
| faster-whisper (current) | — | — | — | baseline |
| ... | ... | ... | ... | ... |

### Embedding Results (to be populated)

| Model | MRR@10 | Recall@5 | Dims | Hardware |
|-------|--------|---------|------|----------|
| all-MiniLM-L6-v2 (current) | — | — | 384 | CPU |
| ... | ... | ... | ... | ... |

---

## How to Run the Full Benchmark

### Phase 1: Extraction Loop (NOW — already running)
```bash
# Continue the echoai-mlx loop
cd ~/Projects/echoai-mlx
# Agent continues: mutate, test, keep/discard
```

### Phase 2: Embedding Benchmark (Day 2–3)
```bash
# Create retrieval test set
python scripts/generate_retrieval_test_set.py

# Run embedding benchmark
python benchmark_embeddings.py --output results/embedding_results.tsv
```

### Phase 3: ASR Benchmark (Day 4–7)
```bash
# Generate synthetic audio for test meetings
python scripts/tts_from_transcript.py

# Run ASR models through extraction pipeline
python benchmark_asr.py --models mlx-community/Whisper-small-mlx,openai/whisper-large-v3

# Measure WER and downstream extraction quality
```

### Phase 4: Cloud Model Testing (Day 7–14)
```bash
# Test large models via HF Pro
HF_TOKEN=hf_xxx python scripts/test_cloud_models.py --models mistralai/Mistral-Small-3.1-24B-Instruct,google/gemma-3-27b-it
```

---

## Decision Framework

When the benchmarks are done, the decision framework is:

### For ASR
- **Best quality:** whisper-large-v3 (via HF Pro) or Qwen3-ASR-1.7B
- **Best speed:** mlx-community/Whisper-small-mlx
- **Best quality/speed balance:** mlx-community/Qwen3-ASR-0.6B

### For Extraction
- **Best local (MLX):** whichever model the loop finds with highest val_f1
- **Best cloud (HF Pro):** Mistral-Small-3.1-24B-Instruct vs. Gemma-3-27B vs. DeepSeek-V3

### For Embeddings
- **Best overall:** BAAI/bge-m3 (1024 dims, best MTEB)
- **Best local MLX:** mlx-community/all-MiniLM-L6-v2-4bit
- **Best multilingual:** paraphrase-multilingual-MiniLM-L12-v2

---

## What the 82+ Model Research Tells Us

From the HF Pro model sweep document, key findings already established:

**ASR:**
- `openai/whisper-large-v3` — WER 11.3% (T4, cloud)
- `openai/whisper-medium` — WER 15.4% (T4, cloud)
- `openai/whisper-small` — WER 17.6% (T4, cloud)
- MLX versions untested — need to measure ourselves

**Extraction (LLM):**
- No direct extraction benchmarks exist — this is why the loop is needed
- General: larger models are better, but smaller models can match with better prompts
- gemma-3-4b-qat-4bit showed strong reasoning — likely good for extraction

**Embeddings:**
- bge-m3 leads with 64.2% on MTEB (vs 57.5% for MiniLM)
- All-MiniLM is fast and good enough for most use cases
- MLX versions not tested — bge-m3 is too large for Apple Silicon at 1024 dims

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| ASR needs audio files we don't have | High | Generate synthetic TTS audio from transcripts |
| Test set too small to generalize | High | Expand to 20+ meetings |
| Embedding retest set is subjective | Medium | Use MTEB standard benchmarks instead |
| HF Pro rate limits during benchmark | Low | Add delays between calls, use batch inference |
| mlx_lm API changes | Low | Pin mlx-lm version in pyproject.toml |

---

## Status

- [x] Extraction loop running (val_f1: 0.895 → 0.9328 in 10 experiments)
- [ ] Embedding benchmark script written
- [ ] Retrieval test set created
- [ ] ASR benchmark script + synthetic audio pipeline
- [ ] Cloud model testing via HF Pro
- [ ] Full results documented in MODEL_BENCHMARK_SUMMARY.md

*Maintained in: `~/Projects/EchoPanel/docs/research/MODEL_BENCHMARKING_PLAN.md`*
*Companion: `~/Projects/EchoPanel/docs/research/AUTORESEARCH_ON_ECHOPANEL.md`* 
*HF Reference: `~/Projects/EchoPanel/docs/research/HF_PRO_MODELS_SWEEP_2026-02-26.md`*
