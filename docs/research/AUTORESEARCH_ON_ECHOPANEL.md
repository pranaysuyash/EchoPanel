# AUTORESEARCH ON ECHOPANEL — Full Session Report

**Date:** 2026-03-19 → 2026-03-20  
**Session:** Pranay + Nova (AI assistant)  
**Goal:** Apply the Karpathy-style autonomous research loop to EchoPanel's meeting intelligence extraction  
**Status:** Loop running. Baseline established.

---

## What This Document Covers

1. [Context: What is the autoresearch loop?](#background)
2. [Why EchoPanel is a perfect target](#why-echopanel)
3. [What was built: `echoai-mlx/](#what-was-built)
4. [The seed test set](#seed-test-set)
5. [Baseline results](#baseline-results)
6. [What the loop explored](#loop-results)
7. [How to integrate winning configs into EchoPanel](#integration)
8. [Opportunities not yet explored](#future-opportunities)
9. [How this idea was identified and why now](#how-it-was-identified)
10. [What changed and what it means](#what-changed)

---

## <a name="background"></a> 1. Context: What is the Autoresearch Loop?

The "autoresearch" concept comes from [Andrej Karpathy's experiments](https://github.com/karpathy/autoresearch) in 2024-2025. The core idea:

> **Run a fixed-budget evaluation loop, automatically. Mutate one thing. Measure. Keep what wins. Discard what doesn't. Repeat.**

The specific variant we're using is `autoresearch-mlx` — Karpathy's adaptation that runs on Apple Silicon via the MLX framework, with a git-based keep/discard protocol.

### How it works (the protocol):

```
FOREVER:
  1. Edit the ONE mutable file (train.py)
  2. Run the evaluation (fixed time budget, fixed data)
  3. If results improved → amend commit
     If results worsened → git reset --hard to last winning commit
  4. Repeat
```

The genius is in the constraints:
- **Only ONE file is editable** (`train.py`). This forces focus and prevents going down rabbit holes.
- **Fixed data, fixed metric.** The test set doesn't change mid-run. The score is the score.
- **Git as experiment tracker.** Every change is a commit. The history IS the lab notebook.
- **Time budget.** 5 minutes per run. Small models can iterate faster and often beat larger ones.

### Why it's powerful:

Humans test ideas sequentially — maybe 1-2 experiments per hour. The loop runs 8-10 per hour. More importantly, the loop explores *combinations* a human wouldn't think to try, and finds *surprising wins* in the dark corners of the hyperparameter space.

---

## <a name="why-echopanel"></a> 2. Why EchoPanel is a Perfect Target

EchoPanel's core value proposition is turning meeting audio into structured intelligence:

```
Meeting Audio → Transcript → Action Items + Decisions + Topics
```

This is a **structured extraction** task — not text generation, not classification, but extracting specific structured facts from unstructured input. Three properties make it ideal for the loop:

### Property 1: Real, recurring data

Every EchoPanel user session generates a transcript. Every transcript is a potential training data point. The more meetings, the better the test set.

### Property 2: Measurable sub-tasks

Meeting intelligence decomposes into distinct dimensions:
- **Action item extraction** (F1 vs. ground truth)
- **Decision recognition** (F1 vs. ground truth)
- **Topic identification** (F1 vs. ground truth)

Each is independently measurable. Each can be optimized separately.

### Property 3: Small models have closed the gap

In 2025-2026, the 1B–7B model tier improved dramatically. Gemma 3, Llama 3.2, Qwen 2.5, and Phi-4 Mini all achieve near-SOTA on narrow extraction tasks. The loop naturally discovers which model is best for *this specific task* on *Pranay's specific hardware* — something no benchmark can tell you.

---

## <a name="what-was-built"></a> 3. What Was Built: `echoai-mlx/`

### Directory Structure

```
~/Projects/echoai-mlx/
├── prepare.py           # Fixed: data loading, F1 scoring, eval harness
├── train.py             # Mutable: model config, system prompts, generation params
├── program.md           # Loop protocol (mirrors autoresearch-mlx)
├── AGENTS.md            # Agent instructions for autonomous running
├── README.md            # Project overview
├── results.tsv          # Experiment log (commit | val_f1 | status | description)
├── data/
│   └── test/meetings.jsonl   # Seed test set (4 meetings)
└── scripts/
    └── build_test_set.py     # Converts source transcripts → JSONL format
```

### `prepare.py` (Sacred — do not edit)

Handles everything data and evaluation:
- Loads test meetings from `meetings.jsonl`
- Parses model JSON output (with fallback heuristics)
- Computes F1 for actions, decisions, topics separately
- Aggregates into `aggregate_f1` (unweighted mean of three F1s)

**Key design decisions:**
- Uses Jaccard character overlap (|A∩B|/|A∪B|) for fuzzy string matching
- Precision capped at 1.0 (prevents one prediction from counting twice)
- Heuristic fallback when model doesn't output valid JSON

### `train.py` (Mutable — the loop edits this)

Handles model loading and generation:
- Loads MLX models via `mlx_lm.load()`
- Builds chat prompts with `tokenizer.apply_chat_template()`
- Samples with `mlx_lm.generate()` + sampler
- Runs `evaluate_all()` from `prepare.py`

**Mutable hyperparameters:**

| Parameter | Baseline Value | Range to Explore |
|-----------|---------------|-----------------|
| `MODEL_REPO` | Llama-3.2-3B-Instruct-4bit | Llama-3.2-1B, Gemma-3-4b, Qwen3-4B |
| `SYSTEM_PROMPT_VARIANT` | 0 | 0–5 (different prompt styles) |
| `TEMPERATURE` | 0.1 | 0.05, 0.1, 0.2 |
| `MAX_TOKENS` | 512 | 256, 768 |
| `FEW_SHOT_K` | 0 | 0, 1, 2, 4 |
| `TOP_P` | 0.9 | 0.8, 0.95 |

### Why MLX-native?

The loop runs via `mlx_lm` — Apple's MLX framework bindings for HuggingFace models. This means:
- Models run on Apple Silicon GPU (Metal)
- No cloud API calls (fully local)
- No data leaves the machine
- Fast iteration (1.7–2.1 seconds per meeting)

---

## <a name="seed-test-set"></a> 4. The Seed Test Set

Built from EchoPanel's existing mock data (`MockData.swift`), converted to structured JSONL format.

### 4 Meetings, 17 Actions, 6 Decisions, 16 Topics

| ID | Meeting | Actions | Decisions | Topics |
|----|---------|---------|-----------|--------|
| seed_001 | Team Standup (12 turns) | 5 | 1 | 4 |
| seed_002 | Customer Escalation — Orion Labs (15 turns) | 5 | 2 | 4 |
| seed_003 | Hiring Debrief (20 turns) | 3 | 1 | 4 |
| seed_004 | Launch War Room (12 turns) | 4 | 2 | 4 |

**Total: 4 meetings, 17 action items, 6 decisions, 16 topics**

### Ground Truth Format

```json
{
  "meeting_id": "seed_001_team_standup",
  "transcript": [
    {"speaker": "Sarah Chen", "text": "Good morning everyone. Let's start with updates."}
  ],
  "expected": {
    "actions": [
      {"assignee": "Alex Kim", "task": "Complete API migration testing", "due": "2026-02-28"}
    ],
    "decisions": [
      {"description": "Target completion date: end of next week (February 28)"}
    ],
    "topics": ["API migration progress", "Frontend integration timeline"]
  }
}
```

### Why this format matters

The ground truth is the single source of truth for evaluation. Getting it right is the most important step — bad ground truth means optimizing for the wrong thing.

**Limitations of the current seed set:**
- Only 4 meetings (too small to generalize broadly)
- All meetings are synthetic/mock data (don't reflect real speech patterns)
- Meetings are in English only
- Topics tend to be multi-word phrases (harder to match with Jaccard similarity)
- No meetings with "no actions" or "no decisions" (edge cases missing)

**Recommended expansion (future):**
1. Synthetic meeting generator (LLM-generated transcripts with known ground truth)
2. Real meeting contributions (opt-in, privacy-preserving)
3. Edge case meetings: 1-person, 10+ people, all action items, no action items

---

## <a name="baseline-results"></a> 5. Baseline Results

**Model:** `mlx-community/Llama-3.2-3B-Instruct-4bit`  
**System Prompt:** Variant 0 (strict JSON schema)  
**Temperature:** 0.1, Top-p: 0.9, Max tokens: 512, Few-shot: 0

### Per-Meeting Scores

| Meeting | F1 Action | F1 Decision | F1 Topic | Aggregate |
|---------|-----------|-------------|----------|----------|
| seed_001 (Team Standup) | 1.000 | 0.667 | 1.000 | 0.889 |
| seed_002 (Customer Escalation) | 0.750 | 1.000 | 1.000 | 0.917 |
| seed_003 (Hiring Debrief) | 0.800 | 1.000 | 1.000 | 0.933 |
| seed_004 (Launch War Room) | 0.857 | 1.000 | 0.667 | 0.841 |

### Aggregate: **val_f1 = 0.8950**

| Metric | Score |
|--------|-------|
| F1 Action (mean) | 0.8518 |
| F1 Decision (mean) | 0.9167 |
| F1 Topic (mean) | 0.9167 |
| **Aggregate F1** | **0.8950** |
| Time per meeting | ~1.7s |
| Total eval time | 6.8s |

### Where it's weak

**Topics (seed_004: 0.667):** The launch war room has long, specific topic strings ("Personalization vs conversion rate tradeoff"). Jaccard matching at 0.5 threshold misses when topics share <50% character overlap.

**Actions (seed_002: 0.750):** Customer escalation has 5 fine-grained action items. The model occasionally misses assignee-task pairs that are implied but not explicitly stated.

**Decisions (seed_001: 0.667):** One meeting had 1 decision but the model found it in a different phrasing, getting partial credit.

---

## <a name="loop-results"></a> 6. What the Loop Explored

*(To be updated after loop completes — baseline is the first commit)*

The loop ran autonomously overnight (or until manually stopped). Results are in `results.tsv`.

### Experiment Log

| Commit | val_f1 | Δ | Status | What changed |
|--------|--------|---|--------|-------------|
| c6e2e9e | **0.8950** | — | keep | baseline: Llama-3.2-3B, system_prompt=0 |
| ... | ... | ... | ... | ... |

### Key Findings (to be filled in after loop)

*Placeholder — update after loop completes.*

---

## <a name="integration"></a> 7. How to Integrate Winning Configs into EchoPanel

When the loop finds a winning configuration, here's how to ship it:

### 7a. Replace the Ollama provider's extraction prompt

EchoPanel's LLM analysis runs through `server/services/llm_providers.py`. The extraction prompt is currently hardcoded. The winning `SYSTEM_PROMPT_VARIANT` from the loop maps to a prompt string to copy.

**Steps:**
1. Copy the winning prompt from `train.py` `SYSTEM_PROMPTS[N]`
2. Paste into `server/services/llm_providers.py` as the extraction system prompt
3. Test with real meeting data

### 7b. Replace the Ollama model

If the loop finds a smaller model (e.g., Llama-3.2-1B) that beats Llama-3.2-3B:

**Steps:**
1. Pull the winning model: `ollama pull mlx-community/Llama-3.2-1B-Instruct-4bit`
2. Update `provider_ollama.py` to use the new model name
3. Verify quality on real meetings

**Expected benefit:** Smaller model = faster inference, lower memory, potentially same quality for this narrow task.

### 7c. Use MLX-native in-process (no Ollama)

`mlx_lm` can be called directly from Python — no Ollama server needed. This removes the HTTP overhead.

**Steps:**
1. In `llm_providers.py`, add a new `provider_mlx_extraction.py`
2. Load the winning model with `mlx_lm.load("mlx-community/...")`
3. Call `generate()` directly — no API call, no network

**Expected benefit:** ~2-3x faster extraction, zero network latency, fully offline.

### 7d. Production pipeline with EchoPanel's real transcripts

Once the test set is expanded, the winning model becomes the production extraction model:

```
Meeting Recording → mlx_whisper (transcription)
                               ↓
              Winning extraction model (MLX-native)
                               ↓
              Action items + Decisions + Topics → EchoPanel UI
```

---

## <a name="future-opportunities"></a> 8. Opportunities Not Yet Explored

### High Priority

**1. ASR model selection via the loop**

EchoPanel currently uses `faster-whisper` for transcription. But mlx-community has alternative ASR models that could be better on meeting audio:

| Model | Size | Notes |
|-------|------|-------|
| `mlx-community/parakeet-tdt-0.6b-v3` | 600M | 286K downloads, NVIDIA-optimized but MLX available |
| `mlx-community/whisper-small-mlx` | — | Native MLX Whisper |
| `mlx-community/Qwen3-ASR-0.6B` | 600M | Multilingual, 177K downloads |
| `mlx-community/Qwen3-ASR-1.7B` | 1.7B | Best multilingual ASR |

**How to loop it:** ASR quality is measured by downstream extraction F1 — if better ASR produces better transcripts, the extraction score goes up. Run the full pipeline through the loop.

**2. Embedding model for semantic search**

EchoPanel has a RAG pipeline (`hybrid_search.py`) that uses embeddings for semantic search. `all-MiniLM-L6-v2-4bit` is the current mlx-community embedding model, but alternatives exist.

**How to loop it:** Measure retrieval accuracy on a curated set of (query, relevant_docs, irrelevant_docs) triples.

**3. Speaker diarization model**

The loop could optimize the diarization step — which speakers are in the meeting and when do they speak. Ground truth would be manually annotated speaker segments.

### Medium Priority

**4. Summary quality optimization**

Currently uses a basic prompt. The loop could find a prompt that produces more useful, action-oriented summaries.

**5. Temperature/repetition tuning for extraction**

Extraction is a near-deterministic task. Very low temperature (0.02–0.05) might produce more consistent results than 0.1.

**6. Context window strategies**

Full transcript vs. last-N-messages vs. rolling window. The loop can find the optimal context strategy for accuracy vs. speed.

### Longer Term

**7. Per-user personalization**

Run a mini-loop per user — adapt to their meeting patterns, terminology, and extraction preferences over time.

**8. Multi-task joint optimization**

Actions + decisions + topics optimized simultaneously. Could find a single prompt that's good at all three, or find that separate models are better for separate tasks.

---

## <a name="how-it-was-identified"></a> 9. How This Idea Was Identified

### The insight

Looking at the EchoPanel codebase in early 2026, two things became clear:

**1. EchoPanel has a multi-stage ML pipeline:**

```
Audio → ASR (whisper) → Transcript → LLM Extraction → Structured Output
                                              ↓
                                    Action items + Decisions + Topics
```

Each stage has model choices. Each choice has hyperparameters. The pipeline is only as good as its weakest link.

**2. The extraction stage was being hand-tuned:**

The system prompt for LLM extraction was written once and never systematically tested against alternatives. No one knew if Llama 3.2 1B could match 3B on this task. No one knew if prompt variant B was better than variant A.

The autoresearch loop was the obvious answer: **let the machine find what works best**.

### Why now

Three conditions converged in March 2026:

1. **MLX maturity:** `mlx_lm` is stable and well-documented. Pre-trained MLX models are widely available. The infrastructure Just Works™ on Apple Silicon.

2. **Autoresearch-mlx validated:** Pranay had already run `autoresearch-mlx` for 10 experiments on next-token prediction. The pattern was proven. The git protocol was understood.

3. **EchoPanel v2 UI complete:** The HIG audit was done, the build was passing, the app was in a "good enough to ship" state. This freed mental bandwidth to think about the next layer.

### The specific moment

Nova (the assistant) was reviewing `LLM_ANALYSIS_ARCHITECTURE.md` and noticed this passage:

> "The primary lever is the system prompt. A better system prompt matters more than a better model."

That sentence — "the primary lever is the system prompt" — is precisely the signal that the autoresearch loop is designed to exploit. When something is "the primary lever" but hasn't been systematically explored, that's the moment to loop it.

---

## <a name="what-changed"></a> 10. What Changed and What It Means

### What changed

Before this session, EchoPanel's extraction pipeline was:

```
Hardcoded system prompt → Ollama (any local model) → hope for good results
```

After this session:

```
Hardcoded system prompt → Ollama (untested model)  → still hope
                                    ↓
         echoai-mlx loop (NEW) → MLX-native extraction → validated config
                                    ↓
                         Winning model + prompt → production
```

The loop creates a **continuous improvement engine** for the extraction stage. Every experiment is logged. Every win is kept. The system gets steadily better without requiring manual experimentation.

### What it means for EchoPanel

**1. The extraction quality is now measurable.**

Before: "seems to work okay."  
After: "val_f1 = 0.895, with concrete weak points identified."

**2. Model choices are now data-driven.**

Before: pick a model and hope.  
After: the loop finds the best model *for this task* on this hardware.

**3. The door is open for the same approach on other stages.**

ASR quality → embedding quality → diarization quality. The loop is task-agnostic. Any stage with a measurable output and a fixed test set can be looped.

**4. The test set becomes a strategic asset.**

A high-quality test set of real meeting data is worth more than any model. It lets you measure improvement. It lets you detect regressions. It lets you compare models fairly. Building and curating the test set is the highest-leverage activity in the entire pipeline.

---

## Technical Notes

### MLX Version Compatibility

```
mlx==0.31.0 (from uv environment)
mlx_lm==0.31.0 (added via uv add mlx-lm)

Important API notes:
- mlx_lm.generate() uses 'sampler' kwarg, NOT 'temp' or 'top_p'
- Build sampler with: make_sampler(temp=0.1, top_p=0.9)
- Build repetition penalty with: make_logits_processors(repetition_penalty=1.1, repetition_context_size=20)
- Model IDs must include -4bit suffix: e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
```

### Git Protocol

```bash
# Commit format for experiments
git commit -m "experiment: system prompt variant 3 — explicit schema"

# Keep: val_f1 improved
git add results.tsv && git commit --amend --no-edit

# Discard: val_f1 worsened  
git reset --hard HEAD~1

# Branch for new idea
git checkout -b echoai/prompt-variants
```

### Running the Loop

```bash
cd ~/Projects/echoai-mlx

# Verify setup
uv run python prepare.py

# Run one eval
uv run python train.py

# Start the loop (agent-driven)
# See AGENTS.md for instructions
```

---

*Document version 1.0 — baseline only. Update with loop results when available.*
*Maintained in: `~/Projects/EchoPanel/docs/research/AUTORESEARCH_ON_ECHOPANEL.md`*
