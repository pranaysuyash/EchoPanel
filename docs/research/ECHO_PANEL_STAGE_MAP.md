# EchoPanel ML Pipeline — Complete Stage Map & Optimization Plan

**Date:** 2026-03-20  
**Author:** Nova (AI assistant)  
**Context:** Systematic mapping of every ML/NLP stage in EchoPanel — what exists, what's missing, what could exist — with model benchmarking plan for every stage that can use a local model.  
**Reference:** `HF_PRO_MODELS_SWEEP_2026-02-26.md` (82+ documented models) · `AUTORESEARCH_BEFORE_AFTER.md` · `MODEL_BENCHMARKING_PLAN.md`

---

## Executive Summary

EchoPanel has **6 active pipeline stages** and **14+ potential enhancement stages**, each with model choices, hyperparameters, and optimization opportunities. This document maps every stage — current state, candidate models, metric to optimize, and whether the autoresearch loop applies.

**Current best extraction result:** val_f1 = **0.9630** (+7.6% from baseline) via prompt engineering, no model change.

**This document covers:**
- Every ML/NLP stage, current and planned
- Every candidate model for every stage
- The metric to measure success at each stage
- Whether the autoresearch loop applies
- Priority ordering for benchmarking work

---

## Complete Pipeline Stage Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ECHOPANEL COMPLETE ML PIPELINE                       │
│                                                                             │
│  AUDIO INPUT                                                                │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 0: AUDIO PREPROCESSING                                       │   │
│  │  • Voice Activity Detection (VAD) — silero-vad                       │   │
│  │  • Noise reduction                                                  │   │
│  │  • Audio chunking / smart silence split                              │   │
│  │  • Sample rate normalization                                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 1: SPEECH-TO-TEXT (ASR)                                       │   │
│  │  • Current: faster-whisper (Distil-Whisper)                         │   │
│  │  • MLX options: Whisper-small-mlx, Qwen3-ASR, Voxtral               │   │
│  │  • Cloud: whisper-large-v3 via HF Pro                               │   │
│  │  OUTPUT: text + word-level timestamps                               │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 2: SPEAKER DIARIZATION                                        │   │
│  │  • Current: implicit from ASR labels (no dedicated model)           │   │
│  │  • Candidates: pyannote/segmentee-3.0, EBR-0.1, spkinet-2.1        │   │
│  │  OUTPUT: speaker segments with timestamps                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 3: TRANSCRIPT POST-PROCESSING                                 │   │
│  │  • Punctuation restoration                                           │   │
│  │  • Capitalization                                                   │   │
│  │  • PII redaction                                                    │   │
│  │  • Text normalization                                               │   │
│  │  • Coreference resolution                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 4: LLM ANALYSIS — EXTRACTION ⭐ (loop running)               │   │
│  │  • Current: Ollama + hardcoded prompt                               │   │
│  │  • Best found: val_f1=0.9630 via prompt engineering               │   │
│  │  • OUTPUT: actions, decisions, risks, topics, summary                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 5: ADDITIONAL LLM ANALYSIS                                   │   │
│  │  • Meeting narrative / abstract                                      │   │
│  │  • Sentiment analysis (per speaker, per segment)                     │   │
│  │  • Question detection                                               │   │
│  │  • Key phrase extraction                                            │   │
│  │  • Action item urgency scoring                                      │   │
│  │  • Meeting quality / engagement scoring                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 6: NAMED ENTITY RECOGNITION (NER)                           │   │
│  │  • Speaker identification (which Alice? — resolves across meetings)   │   │
│  │  • Organization extraction                                          │   │
│  │  • Project/code name extraction                                     │   │
│  │  • Date/deadline extraction                                        │   │
│  │  • Custom entity types per domain                                   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 7: SEMANTIC EMBEDDINGS + SEARCH                              │   │
│  │  • Current: all-MiniLM-L6-v2 (384 dims, CPU)                       │   │
│  │  • Candidates: bge-m3, mlx-native variants, e5-base                │   │
│  │  • OUTPUT: meeting segments indexed for semantic search              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 8: RERANKING + RETRIEVAL                                    │   │
│  │  • Cross-encoder reranking                                          │   │
│  │  • Hybrid search (keyword + semantic, RRF)                           │   │
│  │  • Query expansion / decomposition                                   │   │
│  │  • Citation linking (segment → transcript)                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 9: TEXT-TO-SPEECH OUTPUT                                     │   │
│  │  • Read-aloud of transcript segments                                │   │
│  │  • Action item notification reading                                  │   │
│  │  • Summary audio briefing                                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 10: QUALITY ASSESSMENT (META)                               │   │
│  │  • Per-stage confidence scores                                      │   │
│  │  • Fallback routing when confidence is low                         │   │
│  │  • User correction feedback loop                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  STAGE 11: CROSS-MEETING INTELLIGENCE                              │   │
│  │  • Recurring decision tracking                                      │   │
│  │  • Cross-meeting action item status                                 │   │
│  │  • Project momentum indicators                                      │   │
│  │  • Team dynamics over time                                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│       │                                                                     │
│       ▼                                                                     │
│  MEETING INTELLIGENCE UI + DATA EXPORT                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Stage-by-Stage Breakdown

---

### STAGE 0: Audio Preprocessing

**What it does:** Cleans and prepares raw audio before ASR.

**Current state:**
- **VAD:** `silero-vad` — detects speech segments, filters silence
- **No active noise reduction** — assumes clean recordings
- **Basic chunking** — splits on silence using `whisper-timestamped`'s internal logic

**What it should do:**
- Aggressive noise profiling and reduction
- Reverb removal for conference room recordings
- Music/sound effect detection and handling
- Smart chunking that doesn't split mid-sentence

**Candidate models:**

| Model | Type | Hardware | Status | Notes |
|-------|------|----------|--------|-------|
| `snakers4/silero-vad` | VAD | CPU/ONNX ⭐ | ✅ Current | Industry standard for VAD |
| `pyannote/speechbrain-mtl-utils` | Enhancement | T4+ | ⭐ Try | Multi-task: denoise + dereverb + VAD |
| `microsoft/speech-enhancement` | Enhancement | CPU | ⭐ Try | Speech enhancement + noise suppression |
| `facebook/denoiser` | Enhancement | CPU | ⭐ Try | Open-source audio denoiser |

**Metric to optimize:** VAD recall (don't miss speech), false positive rate (don't hallucinate speech in silence). Downstream: ASR WER.

**Autoresearch applicable:** Partial — VAD threshold tuning per domain (meeting room vs. phone call).

---

### STAGE 1: Speech-to-Text (ASR)

**What it does:** Converts audio to text with word-level timestamps.

**Current state:**
- **Primary:** `faster-whisper` (Distil-Whisper variant, 769M params, CPU)
- **MLX alternative:** `mlx_whisper` (mlx-community/Whisper-small-mlx, 244M params)
- **Fallback:** whisper-timestamped + whisper.cpp

**The biggest single point of failure in the entire pipeline.** Better ASR → better everything downstream.

**Candidate models (from HF Pro model sweep + mlx-community):**

| Model | Size | WER (est.) | RTF (est.) | Hardware | Priority |
|-------|------|-----------|-----------|----------|----------|
| `openai/whisper-large-v3` | 1.56B | 11.3% | Slow | T4+ via HF Pro ⭐ | ⭐⭐⭐ Test |
| `mlx-community/Qwen3-ASR-1.7B` | 1.7B | ~13% | Medium | MLX ⭐⭐ | ⭐⭐⭐ Test |
| `mlx-community/Whisper-small-mlx` | 244M | ~17% | Fast | MLX ⭐ | ⭐⭐⭐ Test |
| `mlx-community/Qwen3-ASR-0.6B` | 600M | ~15% | Fast | MLX ⭐ | ⭐⭐ Test |
| `mlx-community/voxtral-medium-en-2.5B` | 2.5B | ~12% | Medium | MLX ⭐ | ⭐⭐ Test |
| `mlx-community/parakeet-tdt-0.6b-v3` | 600M | ~14% | Fast | MLX ⭐ | ⭐ Test |
| `faster-whisper (current)` | 769M | ~16% | Fast | CPU | ✅ Baseline |

**Metric to optimize:**
- **Primary:** Downstream extraction F1 (val_f1 from echoai-mlx loop)
- **Secondary:** WER against reference transcripts
- **Tertiary:** RTF (real-time factor — lower is faster)

**Autoresearch applicable:** ✅ Yes — test set is audio+transcript pairs, metric is downstream F1.

**How to test ASR:**
```bash
# Generate synthetic audio from existing transcripts
python scripts/generate_asr_audio.py

# Benchmark ASR models
python scripts/benchmark_asr.py \
    --models mlx-community/Whisper-small-mlx,mlx-community/Qwen3-ASR-0.6B,mlx-community/Qwen3-ASR-1.7B
```

---

### STAGE 2: Speaker Diarization

**What it does:** Identifies *who* spoke when, independent of ASR labels.

**Current state:**
- **No dedicated model** — speaker labels come from ASR output
- ASR labels "Speaker 1", "Speaker 2" — not linked to real identities
- Cannot handle overlapping speech

**Why it matters:** Wrong speaker attribution → action items assigned to the wrong person.

**Candidate models (from HF Pro model sweep):**

| Model | Type | Hardware | Status | Notes |
|-------|------|----------|--------|-------|
| `pyannote/segmentee-3.0` | Speaker segmentation | T4+ via HF Pro ⭐ | ⭐⭐⭐ Priority | New, state-of-the-art |
| `pyannote/EBR-0.1` | Diarization | T4+ via HF Pro ⭐ | ⭐⭐⭐ Priority | Best open-source DER |
| `pyannote/spkinet-2.1` | Speaker recognition | T4+ via HF Pro | ⭐⭐ | Speaker embeddings |
| `pyannote/NeMo-TitaNet-L-112d` | Speaker embeddings | T4+ | ⭐ | Large Nemo model |
| `resemble-ai//resemblyzer` | Speaker embeddings | CPU | ⭐ | Lightweight voice similarity |
| `nvidia/Moscoto` | Diarization + ASR joint | T4+ | ⭐ | Joint model |

**Metric to optimize:** DER (Diarization Error Rate) = Speaker error + Missed speech + False alarm speech. Requires annotated test set with ground-truth speaker boundaries.

**Autoresearch applicable:** ✅ Yes — once annotated test set exists.

**Test set requirement:** 5+ meetings with manually annotated speaker segments (time boundaries + speaker names).

---

### STAGE 3: Transcript Post-Processing

**What it does:** Cleans ASR output before LLM analysis.

**Current state:** None — raw ASR output goes directly to LLM.

**What it should do:**

**3a. Punctuation restoration**

ASR often outputs: "we need to ship it by march thirty-first" → "we need to ship it by March 31st."

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `burkazero/transformers-punct` | Punct restoration | CPU ⭐ | ⭐⭐⭐ Try |
| `sagorsarker/biosutvc` | Punct + casing | CPU | ⭐⭐ |
| Custom LLM-based | Any LLM | Ollama/MLX | ⭐⭐ |

**3b. Capitalization**

No capitalization on proper nouns, sentence starts.

**3c. PII Redaction**

Names, emails, phone numbers — privacy-sensitive. GDPR/HIPAA consideration.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `qrocher/presidio-ner-pii` | PII detection | CPU ⭐ | ⭐⭐⭐ Try |
| `dslim/bert-base-NER` | NER for names | CPU | ⭐⭐ |
| Custom rules + regex | Rule-based | CPU | ✅ Use now |

**3d. Text Normalization**

- "um", "uh", filler words removal
- Repeated word handling
- Stuttered word correction

**3e. Coreference Resolution** ⭐

"Alice said she'd handle it. She'll do it by Friday." → resolve "she" → "Alice".

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `(coreference resolution)` | Neural coref | T4+ | ⭐ Future |
| `Mingходикин/stackmix-ner` | NER + coref | T4+ | ⭐ Future |
| LLM-based resolution | Any LLM | Ollama/MLX ⭐ | ⭐⭐ Try now |

**Metric to optimize:** Downstream extraction F1 (post-processed → better extraction). Human readability score for transcripts.

**Autoresearch applicable:** ✅ Yes — metric is downstream extraction F1.

---

### STAGE 4: LLM Analysis — Extraction ⭐ (LOOP RUNNING)

**What it does:** Extracts structured intelligence from transcript.

**Current state:**
- **Model:** Ollama (any available model, default)
- **Prompt:** Hardcoded, single variant
- **Output:** actions, decisions, risks, topics, summary

**Best result so far:** val_f1 = **0.9630** (+7.6% from baseline) — from prompt engineering alone.

**Candidate models (from HF Pro sweep):**

| Model | Size | Performance | Hardware | Status |
|-------|------|------------|----------|--------|
| `Llama-3.2-1B-Instruct` | 1B | ⭐⭐⭐ Matches 3B | MLX | ✅ Tested |
| `Llama-3.2-3B-Instruct` | 3B | Baseline | MLX | ✅ Tested |
| `gemma-3-4b-it-qat-4bit` | 4B | Same as 1B | MLX | ✅ Tested |
| `gemma-3-27b-it` | 27B | Expected better | HF Pro cloud ⭐ | ⭐ Do test |
| `Qwen3-4B` | 4B | Expected strong | MLX ⭐ | ⭐ Do test |
| `mistralai/Mistral-Small-3.1-24B-Instruct` | 24B | Expected best | HF Pro cloud ⭐ | ⭐ Do test |
| `deepseek-ai/DeepSeek-V3-0324` | 236B | Best overall | HF Pro cloud ⭐ | ⭐ Do test |

**Metric to optimize:** val_f1 = aggregate F1 (actions + decisions + topics)

**Autoresearch applicable:** ✅ **YES — ALREADY RUNNING** (val_f1 0.895 → 0.9630 in 17 experiments)

---

### STAGE 5: Additional LLM Analysis

**What it does:** Extracts richer signals from transcript beyond core extraction.

**What's here or should be:**

**5a. Meeting Narrative / Abstract**

A prose paragraph summary, not just bullet points. Useful for email digests.

**5b. Sentiment Analysis**

- Per-speaker sentiment (positive/negative/neutral over time)
- Meeting overall tone (heated vs. calm, decisive vs. uncertain)
- Tension indicators (overlap detection, interruption counts)

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `nlptown/bert-base-multilingual-uncased-sentiment` | Sentiment | CPU ⭐ | ⭐⭐ Try |
| `SamLowe/roberta-base-uncased-go_emotions` | Emotion | CPU | ⭐⭐ |
| LLM-based | Any LLM | Ollama/MLX ⭐ | ⭐⭐⭐ Use now |

**5c. Question Detection**

Identifies questions asked (not answered) — these often indicate open decisions or needed follow-ups.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `lfcc/spanish-question-detection` | Question detection | CPU | ⭐ |
| Custom regex + LLM | Hybrid | Ollama/MLX ⭐ | ⭐⭐⭐ Use now |

**5d. Action Item Urgency Scoring**

Not all action items are equal. Score: "ship by March 30" is urgent. "schedule a follow-up" is not.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| Custom rules | Keyword + regex | CPU ⭐ | ⭐⭐⭐ Use now |
| LLM-based scoring | Any LLM | Ollama/MLX ⭐ | ⭐⭐⭐ Use now |

**5e. Key Phrase Extraction**

Bigrams/trigrams that capture meeting essence. Complement to topic extraction.

**5f. Meeting Quality / Engagement Scoring**

- Talk-to-listen ratio per speaker
- Dominance detection (one person talks 80% of meeting)
- Participation balance

**Metric to optimize:** Task-specific. Sentiment accuracy vs. human-labeled test set. Engagement metrics vs. ground truth.

**Autoresearch applicable:** ✅ Yes — for LLM-based stages, metric is task accuracy.

---

### STAGE 6: Named Entity Recognition (NER)

**What it does:** Extracts and resolves specific entity types from transcript.

**Current state:** Implicit in Stage 4 (LLM extraction handles it).

**What should be a dedicated stage:**

**6a. Speaker Identity Resolution ⭐⭐⭐**

"Alice mentioned..." in meeting 3 is the same Alice from meeting 1? Resolves across meetings.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `dslim/bert-base-NER` | Person/Org/Location | CPU ⭐ | ⭐⭐⭐ Try |
| `tomaarsen/spacy-lookup-loc` | Location NER | CPU | ⭐⭐ |
| LLM-based extraction | Any LLM | Ollama/MLX ⭐ | ⭐⭐⭐ Use now |

**6b. Project / Code Name Extraction**

Meetings reference projects that may not be in any database. Extract and link.

**6c. Date and Deadline Extraction**

Natural language dates → structured ISO dates.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `amazon/Informers_entity_extraction` | Date/Time | CPU ⭐ | ⭐⭐ Try |
| LLM-based | Any LLM | Ollama/MLX ⭐ | ⭐⭐⭐ Use now |

**6d. Custom Entity Types**

Domain-specific: bug IDs, feature flags, PR numbers, SLA terms.

**Metric to optimize:** Entity-level F1 vs. annotated test set (NER-style evaluation).

**Autoresearch applicable:** ✅ Yes — for model selection, metric is entity F1.

---

### STAGE 7: Semantic Embeddings + Indexing

**What it does:** Indexes meeting content for semantic search.

**Current state:**
- **Model:** `sentence-transformers/all-MiniLM-L6-v2` (384 dims, CPU)
- **Storage:** ChromaDB
- **Index type:** Per-segment embedding

**Candidate models:**

| Model | Dims | MTEB Score | RTF | Hardware | Priority |
|-------|------|-----------|-----|----------|----------|
| `BAAI/bge-m3` | 1024 | 64.2% ⭐ | Slow | T4+ | ⭐⭐⭐ Benchmark |
| `intfloat/e5-base-v2` | 768 | 62.5% | Medium | CPU | ⭐⭐ Benchmark |
| `sentence-transformers/all-mpnet-base-v2` | 768 | 62.3% | Medium | CPU ⭐ | ⭐⭐ Benchmark |
| `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | 384 | 57.0% | Fast | CPU | ⭐⭐ |
| `mlx-community/all-MiniLM-L6-v2-4bit` | 384 | ~57% | Fast | MLX ⭐ | ⭐⭐⭐ Benchmark |
| `mlx-community/e5-base-4bit` | 768 | ~62% | Medium | MLX | ⭐⭐ |

**What bge-m3 unlocks:**
- 8K token context (vs 256 for MiniLM)
- Much better multilingual support
- Best MTEB score by a wide margin

**Metric to optimize:** MRR@10 and Recall@K on retrieval test set.

**Autoresearch applicable:** ✅ Yes — for embedding model selection.

---

### STAGE 8: Reranking + Retrieval

**What it does:** Improves search result ranking beyond raw embedding similarity.

**Current state:**
- **Hybrid search:** Reciprocal Rank Fusion (RRF) combining keyword + semantic
- **No reranking model**

**What should be added:**

**8a. Cross-Encoder Reranking ⭐⭐**

First-stage retrieval (embedding) → rerank top-K with cross-encoder for precision.

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | Reranker | CPU ⭐ | ⭐⭐⭐ Try |
| `cross-encoder/ms-marco-MiniLM-L-12-v2` | Reranker | CPU | ⭐⭐ |
| `cross-encoder/ms-marco-electra-base` | Reranker | CPU | ⭐⭐ |
| `cross-encoder/quora-roberta-base` | Reranker | CPU | ⭐⭐ |

**8b. Query Expansion / Decomposition**

Complex query: "what did Alice say about the Q1 roadmap decisions?" → decompose into sub-queries.

**8c. Citation Linking**

When search returns a segment, link back to exact transcript location with speaker + timestamp.

**Metric to optimize:** NDCG@K on retrieval test set.

**Autoresearch applicable:** ✅ Yes — for reranker model selection.

---

### STAGE 9: Text-to-Speech Output

**What it does:** Converts text output to audio for read-aloud features.

**Current state:** None — all output is text/UI only.

**What it enables:**
- Read-aloud of transcript segments
- Action item notification audio
- Summary audio briefing

| Model | Type | Quality | Hardware | Priority |
|-------|------|---------|----------|----------|
| `suno-ai/bark-ultra` | TTS | ⭐⭐⭐⭐ Best | HF Pro ⭐ | ⭐⭐⭐ Get access |
| `suno-ai/bark` | TTS | ⭐⭐⭐ | CPU (slow) | ⭐⭐ Try |
| `xtts` | TTS | ⭐⭐⭐ | CPU/ONNX ⭐ | ⭐⭐⭐ Try (open source) |
| macOS `say` | TTS | ⭐ | Built-in ⭐ | ✅ Use now (prototyping) |

**Bark ultra is on HF Pro.** With HF Pro access, this becomes available.

**Metric to optimize:** MOS (Mean Opinion Score) — human listening test. Downstream: task completion rate.

---

### STAGE 10: Quality Assessment (Meta)

**What it does:** Monitors quality across all stages, flags uncertainty.

**Current state:** None.

**What it should do:**

**10a. Per-Stage Confidence Scores**

Every stage outputs a confidence alongside its result:
- ASR: average token probability
- Extraction: LLM logprob or semantic confidence
- Embedding: cosine similarity of top result

**10b. Fallback Routing**

Low confidence → route to better (but slower/expensive) model:
- ASR low confidence → upgrade to whisper-large-v3
- Extraction low confidence → upgrade to Mistral-24B

**10c. User Correction Feedback Loop ⭐⭐⭐**

User corrects an action item attribution → store correction → retrain/adapt.

This is the key to a self-improving system:
1. User says "that's not what Alice said"
2. Correction logged with context
3. Periodic retraining/fine-tuning with corrected examples
4. Next meeting → better extraction

**Metric to optimize:** Correction rate (lower = better). User satisfaction score.

**Autoresearch applicable:** Indirect — the feedback data becomes the test set for fine-tuning.

---

### STAGE 11: Cross-Meeting Intelligence

**What it does:** Connects insights across multiple meetings over time.

**Current state:** None.

**What should exist:**

**11a. Recurring Decision Tracking**

"We decided to use Postgres in meeting 1. Confirming that decision in meeting 3." → tracked as "decided: use Postgres" with evidence across meetings.

**11b. Cross-Meeting Action Item Status**

Alice had an action from last week → appears in this week's meeting context.

**11c. Project Momentum Indicators**

Meeting frequency, discussion volume, decision velocity — across a project timeline.

**11d. Team Dynamics Over Time**

Who talks to whom. Who raises concerns. Who drives decisions. Heat maps over quarters.

**11e. Meeting Preparation Brief**

Before a meeting: "Last time you met with Bob, you discussed X. Action item Y was assigned. Bob owes you Z."

**Metric to optimize:** Recall of cross-meeting connections (did we surface the right prior context?). User rating of briefing quality.

---

## Model Master Table

Every model from `HF_PRO_MODELS_SWEEP_2026-02-26.md` mapped to EchoPanel stages:

| Model | Stage | Priority | Status |
|-------|-------|----------|--------|
| `openai/whisper-large-v3` | 1 ASR | ⭐⭐⭐ | To test |
| `mlx-community/Qwen3-ASR-1.7B` | 1 ASR | ⭐⭐⭐ | To test |
| `mlx-community/Whisper-small-mlx` | 1 ASR | ⭐⭐⭐ | To test |
| `mlx-community/Qwen3-ASR-0.6B` | 1 ASR | ⭐⭐ | To test |
| `mlx-community/voxtral-medium-en-2.5B` | 1 ASR | ⭐⭐ | To test |
| `pyannote/segmentee-3.0` | 2 Diarization | ⭐⭐⭐ | HF Pro needed |
| `pyannote/EBR-0.1` | 2 Diarization | ⭐⭐⭐ | HF Pro needed |
| `burkazero/transformers-punct` | 3 Punct | ⭐⭐ | To test |
| `qrocher/presidio-ner-pii` | 3 PII | ⭐⭐⭐ | To test |
| `dslim/bert-base-NER` | 6 NER | ⭐⭐⭐ | To test |
| `google/gemma-3-27b-it` | 4 Extraction | ⭐⭐⭐ | HF Pro |
| `mistralai/Mistral-Small-3.1-24B-Instruct` | 4 Extraction | ⭐⭐⭐ | HF Pro |
| `deepseek-ai/DeepSeek-V3-0324` | 4 Extraction | ⭐⭐⭐ | HF Pro |
| `Qwen/Qwen3-4B` | 4 Extraction | ⭐⭐ | To test |
| `microsoft/Phi-4-mini-instruct` | 4 Extraction | ⭐⭐ | To test |
| `BAAI/bge-m3` | 7 Embeddings | ⭐⭐⭐ | To benchmark |
| `mlx-community/all-MiniLM-L6-v2-4bit` | 7 Embeddings | ⭐⭐⭐ | To benchmark |
| `intfloat/e5-base-v2` | 7 Embeddings | ⭐⭐ | To benchmark |
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | 8 Reranking | ⭐⭐⭐ | To test |
| `suno-ai/bark-ultra` | 9 TTS | ⭐⭐⭐ | HF Pro |
| `xtts` | 9 TTS | ⭐⭐⭐ | To test |
| `snakers4/silero-vad` | 0 VAD | ⭐⭐ | To test |
| `nlptown/bert-base-multilingual-uncased-sentiment` | 5 Sentiment | ⭐⭐ | To test |
| `SamLowe/roberta-base-uncased-go_emotions` | 5 Emotion | ⭐⭐ | To test |

---

## Priority Order for Benchmarking

Based on: impact × ease of testing × data requirements

### NOW (this week)

| # | Stage | What | Metric | Effort |
|---|-------|------|--------|--------|
| 1 | **4 Extraction loop** | Continue echoai-mlx loop | val_f1 | Low ✅ Running |
| 2 | **7 Embeddings** | Benchmark bge-m3 vs. MiniLM vs. e5 | MRR@10 | Medium |
| 3 | **1 ASR (synthetic audio)** | Test Whisper-small MLX, Qwen3-ASR | WER + downstream F1 | Medium |
| 4 | **6 NER** | Test dslim/bert-base-NER for speaker resolution | Entity F1 | Low |

### NEXT (weeks 2-3)

| # | Stage | What | Metric | Effort |
|---|-------|------|--------|--------|
| 5 | **1 ASR (real audio)** | Test with real meeting recordings | WER + downstream F1 | High |
| 6 | **8 Reranking** | Test cross-encoder reranking | NDCG@10 | Medium |
| 7 | **3 PII redaction** | Deploy Presidio NER | PII detection rate | Low |
| 8 | **9 TTS** | Test xtts locally, bark via HF Pro | MOS | Low |

### LATER (weeks 4+)

| # | Stage | What | Metric | Effort |
|---|-------|------|--------|--------|
| 9 | **2 Diarization** | Build diarization test set, test pyannote | DER | High |
| 10 | **5 Sentiment** | Deploy sentiment scoring | Accuracy vs. labels | Medium |
| 11 | **0 VAD** | Test silero-vad + denoising | VAD recall | Low |
| 12 | **5 LLM enrichment** | Narrative summary, question detection | Human rating | Medium |
| 13 | **10 Feedback loop** | Build correction logging system | Correction rate | High |

---

## The Universal Benchmarking Template

For every stage, the pattern is identical:

```
┌─────────────────────────────────────────┐
│  1. Build test set (ground truth)       │  ← Hardest part
│  2. Write benchmark script               │  ← prepare.py equivalent
│  3. Define metric                        │  ← F1, WER, MRR, DER, MOS
│  4. Run models through pipeline          │  ← train.py equivalent
│  5. Compare, keep best                   │
│  6. Integrate into EchoPanel            │
└─────────────────────────────────────────┘
```

The test set is always the bottleneck. Every stage needs ground-truth annotated data.

**Test set types:**
- ASR: audio + transcript pairs
- Diarization: speaker time-boundary annotations
- NER: token-level entity annotations
- Extraction: structured output annotations (already have)
- Retrieval: query + relevant + irrelevant segments
- Sentiment: speaker-level sentiment labels

---

## HF Pro Access Changes Everything

With HuggingFace Pro, you have GPU endpoint access for models too large to run locally:

| Model | Size | What it unlocks |
|-------|------|----------------|
| `mistralai/Mistral-Small-3.1-24B-Instruct` | 24B | Best extraction quality |
| `deepseek-ai/DeepSeek-V3-0324` | 236B | Best overall open-weights |
| `google/gemma-3-27b-it` | 27B | Google's best |
| `openai/whisper-large-v3` | 1.56B | Best ASR (WER 11.3%) |
| `pyannote/segmentee-3.0` | — | State-of-the-art diarization |
| `pyannote/EBR-0.1` | — | Best open-source DER |
| `suno-ai/bark-ultra` | — | Best TTS quality |

**Strategy:**
- Local MLX for speed and iteration (looping)
- HF Pro cloud for production quality on hard cases
- Benchmark both → decide per-stage based on quality/speed tradeoff

---

## Summary: What's Done, What's Next

### Already Done
- [x] Extraction loop running (val_f1 0.895 → 0.9630, +7.6%)
- [x] ASR benchmark script written (`benchmark_asr.py`)
- [x] Synthetic audio generation script written (`generate_asr_audio.py`)
- [x] Embedding benchmark plan documented
- [x] Full stage map documented (this document)

### In Progress
- [ ] Extraction loop completing overnight
- [ ] Synthetic audio generation for ASR test set
- [ ] ASR model benchmarking (Whisper-small MLX, Qwen3-ASR)

### Next Up
- [ ] Embedding benchmark (bge-m3 vs. MiniLM vs. e5)
- [ ] NER model test (speaker resolution)
- [ ] ASR with real meeting audio
- [ ] PII redaction with Presidio

---

*Maintained in: `~/Projects/EchoPanel/docs/research/ECHO_PANEL_STAGE_MAP.md`*  
*Companion: `~/Projects/EchoPanel/docs/research/AUTORESEARCH_BEFORE_AFTER.md`*  
*Companion: `~/Projects/EchoPanel/docs/research/MODEL_BENCHMARKING_PLAN.md`*  
*HF Reference: `~/Projects/EchoPanel/docs/research/HF_PRO_MODELS_SWEEP_2026-02-26.md`*
