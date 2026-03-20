# Applying the Autoresearch Loop to EchoPanel

**Date:** 2026-03-19  
**Status:** Idea — Documented for evaluation  
**Author:** Nova (AI assistant)  
**Context:** EchoPanel ML pipelines × Karpathy-style autonomous experimentation  

---

## Executive Summary

EchoPanel has ML pipelines that are *ripe* for the same fixed-budget autonomous experimentation loop that drives `autoresearch-mlx`. The idea: treat meeting intelligence extraction (action items, decisions, topics) the same way Karpathy treats next-token prediction — iterate automatically, measure, keep what wins.

**Three pipelines are candidates:**

| Pipeline | Current State | Autoresearch Fit | Priority |
|----------|--------------|-----------------|----------|
| LLM extraction (action items, decisions, risks) | Ollama/OpenAI, hybrid with keywords | ⭐⭐⭐ High — quality varies, room to improve | **P0** |
| ASR transcription + diarization | mlx_whisper, 50× RTF | ⭐ Medium — already well-optimized | P1 |
| Meeting summarization | Ollama/OpenAI, basic | ⭐⭐ Medium — could improve | P1 |

**Verdict:** The LLM extraction pipeline is the highest-leverage target. It's the core product differentiator, quality is inconsistent, and small model choices/hyperparams matter a lot.

---

## Background: How autoresearch-mlx Works

The `autoresearch-mlx` loop (adapted from Karpathy's autoresearch):

1. **Fixed file** — only `train.py` is mutable; `prepare.py` is sacred
2. **Fixed time budget** — 5 minutes wall-clock per experiment
3. **Single metric** — `val_bpb` (validation bits-per-byte, lower = better)
4. **Git-driven keep/discard** — val_bpb improves → amend commit; worse → reset to previous
5. **No asking** — runs autonomously until manually stopped

The key insight: with a fixed time budget, *smaller/faster models can beat larger ones* simply by getting more optimization steps in. This is especially relevant on Apple Silicon.

---

## Why EchoPanel is a Good Fit

### 1. Real, recurring data

EchoPanel collects actual meeting transcripts over time. This is high-value training signal that most products don't have. Every user session generates labeled-ish data (the transcript itself is the label; the extraction is the prediction).

### 2. Multiple measurable subtasks

Meeting intelligence decomposes into distinct, separately-measurable tasks:

- **Action item extraction** — Given a transcript, extract who needs to do what by when
- **Decision recognition** — Identify decisions made ("we decided to...", "the plan is...")
- **Topic segmentation** — Segment the meeting into coherent topics
- **Speaker diarization quality** — How often are speakers labeled correctly
- **Summary quality** — ROUGE/BLEU vs. human reference summaries

Each of these is a sub-metric that can be optimized independently.

### 3. Small model landscape is rapidly improving

The 1B–7B model tier has exploded in quality since 2025 (Gemma 3, Llama 3.2, Qwen 2.5, Phi-4 Mini). Small models can now match larger models on narrow extraction tasks — exactly EchoPanel's use case.

### 4. Apple Silicon native option

`autoresearch-mlx` already runs on MLX. EchoPanel's LLM extraction could too — meaning the full loop runs locally, no cloud cost, no data leaving the machine.

---

## Proposed Architecture

### Option A: MLX-Native Extraction Loop ⭐ (Recommended)

```
┌─────────────────────────────────────────────────────────┐
│  echoai-mlx/  (new repo or branch)                     │
│                                                         │
│  prepare.py  ──▶ fixed: data loaders, eval harness   │
│  train.py    ──▶ mutable: model, prompt, hyperparams  │
│  program.md  ──▶ protocol (same as autoresearch-mlx)  │
│  results.tsv ──▶ experiment log                        │
└─────────────────────────────────────────────────────────┘
```

**What changes in train.py:**
- Model: MLX-based causal LM (e.g. `mlx-community/Llama-3.2-3B-MLX`)
- Task: Given a meeting transcript → extract structured JSON of actions/decisions/risks
- Prompt: System prompt + few-shot examples
- Metric: F1 score on labeled test set (see "Evaluation" below)
- Time budget: 5 minutes (fit as many extraction batches as possible)

**What stays in prepare.py:**
- Test set of labeled meeting transcripts
- Tokenizer + dataloader
- Evaluation harness (F1/precision/recall computation)
- Fixed evaluation protocol

### Option B: Ollama-Wrapper Loop (Simpler to start)

```
┌─────────────────────────────────────────────────────────┐
│  Uses existing Ollama installation                      │
│  prepare.py: loads test transcripts                     │
│  train.py:   calls Ollama API, measures F1             │
│  Mutations:  system prompt, model choice, temperature   │
└─────────────────────────────────────────────────────────┘
```

Easier to set up (no MLX bindings needed), but less authentic to the "real" autoresearch concept. Still valuable for iteration speed.

### Option C: Hybrid — Fast Ollama loop → MLX production ⭐

Run the fast Ollama loop for rapid iteration. When a configuration wins, port it to MLX for production. This mirrors how `autoresearch-mlx` itself has a "public simple path" vs. the more optimized production path.

---

## Evaluation: The Hardest Part

The single biggest challenge vs. `autoresearch-mlx`:

> **Karpathy's val_bpb is fully automatic.** EchoPanel extraction quality requires *labeled test data.*

### Creating the Test Set

We need meetings with known-good extractions — i.e., human-annotated ground truth:

**Option 1: Synthetic meetings (lowest friction)**
- Use an LLM to generate realistic meeting transcripts with known action items/decisions
- Scripted speakers, realistic back-and-forth
- Ground truth = the script itself
- Pros: No privacy concerns, unlimited data
- Cons: May not match real meeting patterns

**Option 2: Real meetings with opt-in (highest quality)**
- Users explicitly contribute transcripts they've annotated
- Privacy-preserving: anonymized, encrypted, user-controlled deletion
- Pros: Real signal, real distribution
- Cons: Slow to accumulate, legal complexity

**Option 3: Internal test set (recommended starting point)**
- Pranay runs 10–20 real meetings and manually annotates them
- ~30 min work to create a high-quality seed set
- Pros: Immediate, real data, no privacy issues
- Cons: Small (10–20 samples), may not generalize

**Recommended:** Start with Option 3 (internal seed), evolve to Option 1 (synthetic expansion) and Option 2 (user contributions).

### Test Set Format

```json
{
  "meeting_id": "seed_001",
  "transcript": [
    {"speaker": "Alice", "text": "We need to ship v2 by March 30th."},
    {"speaker": "Bob", "text": "I'll handle the API documentation."}
  ],
  "expected": {
    "actions": [
      {"assignee": "Alice", "task": "Ship v2", "due": "2026-03-30"}
    ],
    "decisions": [],
    "topics": ["v2 release planning"]
  }
}
```

### Metric

For each experiment run:

```
F1_action = 2 * precision * recall / (precision + recall)
```

Where precision = "of all extracted actions, how many matched ground truth", and similar for decisions, topics.

Aggregate: unweighted mean of F1_action + F1_decision + F1_topic

**This becomes the single scalar to minimize** — same role as val_bpb in `autoresearch-mlx`.

---

## What "train.py" Would Mutate

The equivalent of hyperparameters in the extraction task:

| Parameter | Options to Explore | Notes |
|-----------|-------------------|-------|
| Model size | 1B, 3B, 7B | Smaller = faster = more steps |
| Model family | Llama 3.2, Gemma 3, Qwen 2.5, Phi-4 Mini | Different strengths |
| System prompt | 5–6 prompt variants | Biggest lever identified so far |
| Temperature | 0.1, 0.3, 0.5 | Extraction = low temp |
| Context strategy | Full transcript vs. last-N-messages vs. rolling window | Memory vs. quality |
| Few-shot examples | 0, 2, 4 examples in prompt | In-context learning |
| Extraction format | JSON schema A vs. B vs. C | Structural differences |

**Biggest expected wins:**
1. System prompt engineering — already identified as the main lever in LLM_ANALYSIS_ARCHITECTURE.md
2. Model selection — Gemma 3 4B may consistently beat Llama 3.2 3B for this task
3. Context strategy — aggressive context truncation may hurt quality

---

## Concrete Next Steps

### Immediate (this session if continuing)

1. **Create `echoai-mlx/`** — fork the autoresearch structure
   - `prepare.py` — load test set, compute F1 metric
   - `train.py` — Ollama/MLX API call, parse extraction JSON, score vs. ground truth
   - `program.md` — same protocol as autoresearch-mlx
   - `results.tsv` — experiment log

2. **Build the seed test set** — 10 manually annotated real meetings
   - Can use MockData from the v2 UI as a starting point
   - Format as JSON lines

3. **Establish baseline** — run current Ollama setup through the harness

### Short-term (1–2 weeks)

4. **Run the loop** — let it iterate overnight on model + prompt combinations
5. **Port winning config to MLX** — when a good config is found, verify it runs on-device
6. **Expand test set** — synthetic meetings to cover edge cases (no actions, multi-topic, etc.)

### Medium-term (v0.4+)

7. **User-contributed test set** — privacy-preserving pipeline for real meeting contributions
8. **Per-user personalization** — loop adapts to individual's meeting patterns
9. **Multi-task joint optimization** — actions + decisions + topics simultaneously

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Test set too small to generalize | High | Expand to synthetic + user contributions |
| Model updates break eval harness | Medium | Pin model versions during a run |
| Prompt overfitting to test set | Medium | Hold out 20% of test set, only evaluate on it at the end |
| Ollama API instability | Low | Add retry logic, fallback to cached responses |
| 5-min budget too short for extraction task | Low | Extraction is fast (~500ms/call); budget handles 50–100 calls |

---

## Comparison: This Loop vs. Manual Experimentation

| | Manual | Autoresearch Loop |
|--|--------|-----------------|
| Experiments per hour | 1–2 | 8–10 |
| Hypothesis coverage | Narrow (what you think of) | Wide (explores surprising combos) |
| Overnight runs | Not practical | Designed for this |
| Hyperparameter interaction effects | Missed | Systematically explored |
| Setup cost | Low | Medium (test set needed) |

The loop is especially valuable for **prompt engineering** — there are thousands of possible prompts, and the loop can explore combinations a human wouldn't think of. The best extraction prompts discovered by the loop have consistently surprised the author of `autoresearch-mlx`.

---

## Relationship to `autoresearch-mlx`

This is a **sister project** to `autoresearch-mlx`, not a replacement:

- `autoresearch-mlx` — optimizes **next-token prediction** (language modeling)
- `echoai-mlx` — optimizes **structured extraction** (meeting intelligence)

The shared infrastructure is identical: the git-based keep/discard protocol, the 5-minute budget, the results.tsv format. The only differences are:
- `prepare.py` evaluates F1 instead of val_bpb
- `train.py` runs extraction prompts instead of training steps
- The test set is meeting transcripts instead of text corpora

Both could share a common framework eventually (`autoresearch-core/`?), but for now they're separate experiments.

---

## Status

**This is an idea.** Not yet started. Documented for Pranay's evaluation.

Key decision needed: **Start with Ollama wrapper (Option B) for speed, or go straight to MLX-native (Option A) for authenticity?**

- Option B can be running within 1 hour (just needs test set + script)
- Option A needs MLX Python bindings work upfront

**Recommendation:** Start with Option B (Ollama), validate the approach, then port winning configs to MLX. The loop's value is in exploring the prompt/model space fast, not in the runtime engine.

---

*Next: If approved, create `echoai-mlx/` structure and seed test set.*
