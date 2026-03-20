# EchoPanel Complete ML Pipeline — Full Architecture RFC

> **Version:** 1.0  
> **Date:** 2026-03-20  
> **Author:** Nova (AI assistant)  
> **Status:** Living document — updated as pipeline evolves  
> **Purpose:** Definitive reference for every ML/NLP stage in EchoPanel — current, planned, and speculative. Every stage with a model, a metric, and a testing plan.

---

## Overview

EchoPanel is a meeting intelligence product. Its core function is:

```
Meeting Audio → Structured Meeting Intelligence
```

Between those two poles lies a pipeline of ML/NLP stages. This document maps every stage — what it does, what runs it, what the output is, what could run it, and how to measure if it's good.

**Assumptions:**
- All local models run on Apple Silicon via MLX unless noted
- HF Pro access provides GPU endpoints for large models
- Local inference preferred for speed + privacy
- Cloud inference used for quality-critical production decisions

---

## Complete Stage Registry

All stages are numbered sequentially. Stages marked ✅ exist in current code. Stages marked 📋 are planned. Stages marked 💡 are speculative/optional.

---

## PHASE 1: INPUT PROCESSING

---

### Stage A0: Acoustic Signal Processing

**What it does:** Receives raw audio bytes, prepares them for ASR.

**Sub-stages:**

**A0a. Echo Cancellation**  
Removes acoustic echo (speaker bleed into microphone). Critical for speakerphone recordings.

- **Current:** None
- **Candidates:**
  - `speex` (DSP library, open source) ✅ Available
  - `python-echo-cancellation` ✅ Available
  - macOS built-in `AudioToolbox` echo cancellation ✅ Available
  - `deepspeech` style neural echo cancellation 💡 Future

**A0b. Noise Profiling & Reduction**  
Identifies and removes background noise (HVAC, keyboard, fan noise).

- **Current:** None (assumes clean recordings)
- **Candidates:**
  - `snakers4/silero-vad` has noise detection ✅ Use now
  - `facebook/denoiser` (CNN-based, CPU) ⭐ Try
  - `microsoft/speech-enhancement` (speech-focused denoising) ⭐ Try
  - `DNS9` (Deep Noise Suppression challenge winners) 💡

**A0c. Voice Activity Detection (VAD)**  
Identifies where speech occurs (vs. silence/noise). Prevents ASR from wasting compute on silence.

- **Current:** `silero-vad` ✅ In use
- **Candidates:**
  - `webrtc-vad` (WebRTC open-source VAD) ✅ Available
  - `pyannote/voice-activity-detection` ⭐ Try
  - `facebook/wav2vec2-base-vad` ⭐ Try

**A0d. Smart Chunking**  
Splits long recordings into manageable segments. Must not split mid-sentence.

- **Current:** Silence-based splitting (basic)
- **Candidates:**
  - Whisper's built-in chunking with overlap ✅ Enhance
  - Semantic chunking (embed sentences, split at topic boundaries) ⭐📋
  - Turn-taking based splitting (split on speaker pause > threshold) ⭐📋

**A0e. Audio Normalization**  
Ensures consistent volume levels across input.

- **Current:** None
- **Candidates:**
  - `pyloudnorm` (LUFS normalization) ✅ Available
  - `ffmpeg` loudnorm filter ✅ Available
  - Per-channel normalization for multi-mic setups 💡

**A0f. Room Impulse Response / Reverb Detection** 💡  
Detects conference room acoustic signatures and flags for enhanced processing.

**Metric:** VAD recall (should not miss speech). False positive rate (should not flag silence as speech). SNR improvement after denoising.

**Hardware:** CPU for most. Denoiser can run on MLX.

---

### Stage A1: Speech-to-Text (ASR) ⭐ PRIMARY STAGE

**What it does:** Converts audio to text with timestamps and language detection.

**This is the biggest single point of failure in the pipeline.** Better ASR → better transcription → better extraction → better meeting intelligence. Every downstream stage benefits from better ASR.

**Current state:**
- **Primary:** `faster-whisper` (Distil-Whisper variant, 769M params, CPU int8)
- **MLX option:** `mlx_whisper` with `mlx-community/Whisper-small-mlx`
- **Fallback:** `whisper-timestamped` + `whisper.cpp`

**Output fields:**
```json
{
  "text": "full transcript",
  "segments": [
    {
      "start": 0.0, "end": 5.2,
      "speaker": "Speaker 1",  // from diarization if available
      "text": "Let's start with updates from the backend team."
    }
  ],
  "language": "en",
  "confidence": 0.94
}
```

**Candidate models:**

| Model | Size | WER | RTF | Hardware | Priority |
|-------|------|-----|-----|----------|----------|
| `openai/whisper-large-v3` | 1.56B | 11.3% | Slow | HF Pro ⭐⭐⭐ | Test |
| `mlx-community/Qwen3-ASR-1.7B` | 1.7B | ~13% | Medium | MLX ⭐⭐⭐ | Test |
| `mlx-community/Whisper-small-mlx` | 244M | ~17% | Fast | MLX ⭐⭐⭐ | Test |
| `mlx-community/voxtral-medium-en-2.5B` | 2.5B | ~12% | Medium | MLX ⭐⭐ | Test |
| `mlx-community/Qwen3-ASR-0.6B` | 600M | ~15% | Fast | MLX ⭐⭐ | Test |
| `mlx-community/parakeet-tdt-0.6b-v3` | 600M | ~14% | Fast | MLX ⭐ | Test |
| `openai/whisper-medium` | 769M | 15.4% | Medium | CPU ⭐ | Compare |
| `faster-whisper-small` (current) | 244M | ~16% | Fast | CPU | Baseline |

**Language detection:** `fasttext/language-identification` or Whisper's built-in.

**Multi-speaker transcription:** Whisper can handle 2-3 speakers. Beyond that, requires Stage A2 (diarization).

**Metric:** WER (Word Error Rate) against reference. Downstream extraction F1 (best proxy for end quality). RTF (Real-Time Factor = latency / audio duration).

**Autoresearch applicable:** ✅ Yes — test set is audio+transcript pairs, metric is downstream extraction F1.

---

## PHASE 2: SPEAKER UNDERSTANDING

---

### Stage A2: Speaker Diarization

**What it does:** Determines *who* spoke *when*, independent of ASR labels. Maps "Speaker 1" to real identities across meetings.

**Current state:**
- **No dedicated model** — speaker labels come from ASR output
- ASR labels "Speaker 1", "Speaker 2" — not linked to known identities
- Cannot handle overlapping speech

**Why it matters:** Wrong speaker → action items assigned to wrong person → broken workflow.

**Output fields:**
```json
{
  "speaker_segments": [
    {"start": 0.0, "end": 5.2, "speaker_id": "SPEAKER_001", "confidence": 0.92},
    {"start": 5.3, "end": 12.1, "speaker_id": "SPEAKER_002", "confidence": 0.88}
  ],
  "num_speakers": 4
}
```

**Candidate models:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `pyannote/segmentee-3.0` | Segmentation | HF Pro ⭐⭐⭐ | Get access |
| `pyannote/EBR-0.1` | Diarization | HF Pro ⭐⭐⭐ | Get access |
| `pyannote/spkinet-2.1` | Speaker recognition | HF Pro ⭐⭐ | Get access |
| `resemble-ai/resemblyzer` | Voice embedding | CPU ⭐⭐ | Try |
| `nvidia/Moscoto` | Joint ASR+diarization | T4+ 💡 | Future |

**Test set requirement:** 5+ meetings with manually annotated speaker boundaries and names.

**Metric:** DER (Diarization Error Rate) = speaker_error + miss + false_alarm. Target: DER < 10%.

**Autoresearch applicable:** ✅ Yes — once annotated test set exists.

---

### Stage A3: Voice Biometrics & Speaker Linking 💡

**What it does:** Links the same speaker across different meetings. "Speaker 2 in meeting 47" = "Pranay" who we know from previous meetings.

**Current state:** None — speakers are anonymous across meetings.

**Why it matters:** If Alice appears in 20 meetings, we should track her across all of them, not treat her as a new speaker each time.

**Candidates:**
- Speaker embeddings from Stage A2 (pyannote models produce embeddings)
- `resemble-ai/resemblyzer` for embedding comparison
- Vector similarity clustering (UMAP/HDBSCAN on speaker embeddings)

**Output:** Speaker registry with known identities, linked across meetings.

---

### Stage A4: Overlap Detection 💡

**What it does:** Identifies when speakers talk over each other. Critical for meeting dynamics analysis.

**Current state:** None.

**Candidates:** Built into some diarization models. Can also post-process with `pyannote/overlap-detector`.

**Use cases:**
- Tension indicators (lots of overlap = heated discussion)
- Dominance metrics (corrected for overlap)

---

## PHASE 3: TRANSCRIPT PROCESSING

---

### Stage T1: Punctuation Restoration

**What it does:** Adds punctuation and capitalization to ASR output (which is typically punctuation-free).

**Current state:** None — raw ASR output goes directly to LLM.

**Why it matters:** "we need to ship it by march thirty first" vs. "We need to ship it by March 31st." Both parse differently in downstream extraction.

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `burkazero/transformers-punct` | Punct restoration | CPU ⭐⭐⭐ | Try now |
| `sagorsarker/biosutvc` | Punct + casing | CPU ⭐⭐ | Try |
| `LiheAIl/DeepPF-Large` | Punct + prosody | T4+ 💡 | Future |
| LLM-based (Ollama/MLX) | Any LLM | Ollama/MLX ⭐⭐⭐ | Use now |

**Metric:** Punctuation accuracy (F1 on punctuation marks). Human readability score.

---

### Stage T2: Capitalization & Proper Noun Recovery

**What it does:** Capitalizes sentence starts and proper nouns.

**Current state:** None.

**Candidates:** Often bundled with punctuation restoration. `sagorsarker/biosutvc` handles both. LLM-based as fallback.

---

### Stage T3: PII Redaction & Privacy

**What it does:** Detects and redacts personally identifiable information.

**Current state:** None — transcripts may contain names, emails, phone numbers, addresses.

**Why it matters:** GDPR, HIPAA, CCPA compliance. Also: privacy for meeting attendees who didn't consent to being recorded.

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `qrocher/presidio-ner-pii` | PII detection | CPU ⭐⭐⭐ | Deploy now |
| `dslim/bert-base-NER` | Person/Org/Location | CPU ⭐⭐ | Try |
| Microsoft Presidio (full) | PII detection | CPU ⭐⭐ | Deploy |
| Rule-based + regex | Names, emails, phones | CPU ⭐⭐⭐ | Use now |

**Output:** Redacted transcript (PII replaced with `[REDACTED]` or `[PERSON_NAME]`). Audit log of what was redacted.

**Metric:** Recall on PII detection (don't miss anything). Precision (don't over-redact).

---

### Stage T4: Profanity & Content Filtering 💡

**What it does:** Detects and flags/strips profanity and harmful content.

**Current state:** None.

**Candidates:**
- `paxton615/profanity-detector` ⭐ Try
- Simple word list + regex ✅ Use now
- LLM-based detection ⭐ Use now

---

### Stage T5: Text Normalization & Cleaning

**What it does:** Cleans ASR artifacts from transcript.

**Sub-stages:**

**T5a. Filler word removal**
- Removes "um", "uh", "you know", "like", "I mean"
- `pynisher/filler-word-removal` ⭐ Try
- Regex + word list ✅ Use now

**T5b. Stuttering / Repeated word handling**
- "I I I need to to to" → "I need to"
- Rule-based ✅ Use now

**T5c. Laughter and non-speech detection**
- "[laughter]", "[applause]", "[cough]"
- `pyannote/non-speech-detection` ⭐ Try

**T5d. Partial word handling**
- ASR sometimes cuts words: " ship-" at chunk boundary
- Rule-based cleanup ✅ Use now

**T5e. Disfluency Detection** 💡
- More sophisticated than filler words: self-corrections, restarts
- "The the API - I mean the backend API" → clean version
- LLM-based approach ⭐📋

---

### Stage T6: Coreference Resolution

**What it does:** Resolves pronouns to their referents.

**Example:** "Alice said she'd handle it. She'll do it by Friday."
→ Resolves "she" → "Alice", "it" → "the API documentation"

**Current state:** None.

**Why it matters:** Action item extraction is better when "she" is resolved to "Alice" before analysis.

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `Mingходикин/stackmix-ner` | NER + coref | T4+ 💡 | Future |
| `苍梧/CoRef-Resolver-BERT` | Coreference | T4+ 💡 | Future |
| LLM-based (chain-of-thought) | Any LLM | Ollama/MLX ⭐⭐⭐ | Use now |
| Simple rule-based (speaker mapping) | Rule-based | CPU ⭐⭐ | Use now |

**LLM approach:** Prompt the extraction LLM to resolve coreferences before extracting. "First identify who 'she' and 'it' refer to, then extract actions."

**Metric:** Coreference F1 (on annotated test set). Downstream extraction F1 improvement.

---

### Stage T7: Sentence Segmentation & Topic Boundary Detection

**What it does:** Segments transcript into sentences and detects topic shifts.

**Current state:** Implicit in Stage 4 (LLM handles it).

**Candidates:**
- `NLP4J/CoreNLP` sentence splitter ✅ Available
- LLM-based topic segmentation ⭐ Use now
- Embedding-based semantic chunking ⭐📋

**Use cases:**
- Better segment-level citations
- Meeting section navigation
- "What was discussed about X" query handling

---

## PHASE 4: MEETING INTELLIGENCE EXTRACTION

---

### Stage L1: Core Structured Extraction ⭐ THE CORE LOOP

**What it does:** Extracts actions, decisions, risks, topics from transcript.

**Current state:**
- **Model:** Ollama (unconfigured, any model)
- **Prompt:** Single hardcoded variant
- **Output:** actions, decisions, risks, topics

**Current best result:** val_f1 = **0.9630** (+7.6% from baseline via prompt engineering)

**Candidate models (MLX):**

| Model | Size | val_f1 (est.) | Priority |
|-------|------|--------------|----------|
| `Llama-3.2-1B-Instruct-4bit` | 1B | 0.9630 ⭐ | ✅ Best found |
| `Llama-3.2-3B-Instruct-4bit` | 3B | 0.9328 | ✅ Tested |
| `gemma-3-4b-it-qat-4bit` | 4B | 0.9300 | ✅ Tested |
| `Qwen3-4B-Q4_K_XL` | 4B | ? | ⭐ Try |
| `google/gemma-3-1b-it-qat-4bit` | 1B | ? | ⭐ Try |
| `microsoft/Phi-4-mini-instruct` | 3.8B | ? | ⭐ Try |

**Candidate models (HF Pro cloud):**

| Model | Size | Expected | Priority |
|-------|------|----------|----------|
| `mistralai/Mistral-Small-3.1-24B-Instruct` | 24B | Best | ⭐ HF Pro |
| `deepseek-ai/DeepSeek-V3-0324` | 236B | Best overall | ⭐ HF Pro |
| `google/gemma-3-27b-it` | 27B | Strong | ⭐ HF Pro |

**Output:**
```json
{
  "actions": [
    {
      "assignee": "Alice",
      "task": "Complete API migration testing",
      "due": "2026-02-28",
      "confidence": 0.94,
      "speaker": "Sarah Chen"
    }
  ],
  "decisions": [
    {
      "description": "Target completion date: end of next week",
      "who": ["Sarah Chen", "Alex Kim", "Mike Johnson"],
      "confidence": 0.91
    }
  ],
  "risks": [
    {
      "description": "Search feature performance issues before release",
      "severity": "medium",
      "mentioned_by": "Alex Kim"
    }
  ],
  "topics": ["API migration", "Frontend integration", "Database review"],
  "summary": "The team reviewed the API migration status and agreed to target end of next week for full integration. Sarah will schedule a database migration review for Thursday. Alex will profile the search feature performance before release."
}
```

**Metric:** val_f1 = aggregate F1 on actions + decisions + topics.

**Autoresearch applicable:** ✅ **YES — ALREADY RUNNING.**

---

### Stage L2: Meeting Narrative / Abstract Generation

**What it does:** Generates a prose paragraph summary, not bullet points.

**Current state:** None — summary is included in L1 output.

**Why it matters:** Bullet points are great for reference. A narrative paragraph is better for email digests, Slack summaries, and executive briefings.

**Candidates:**
- LLM-based (Ollama/MLX) ⭐ Use now
- `google/pegasus-xsum` model (abstractive summarization) 💡 Future

**Metric:** ROUGE-L vs. human-written reference summaries. Human readability rating.

---

### Stage L3: Sentiment & Emotion Analysis

**What it does:** Measures sentiment and emotion per speaker and per meeting segment.

**Current state:** None.

**Why it matters:** "The meeting ended positively" is useful metadata. Detecting frustration, excitement, uncertainty — these signal engagement and decision quality.

**Per-speaker sentiment over time:**
```json
{
  "speaker_sentiment": {
    "Alice": [
      {"start": 0.0, "end": 60.0, "sentiment": "neutral", "score": 0.5},
      {"start": 60.0, "end": 120.0, "sentiment": "positive", "score": 0.7},
      {"start": 120.0, "end": 180.0, "sentiment": "frustrated", "score": 0.3}
    ]
  },
  "meeting_tone": "productive with tension around API timeline",
  "emotional_peaks": [
    {"time": 45.0, "emotion": "excitement", "speaker": "Bob", "context": "announced v2 launch date"}
  ]
}
```

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `SamLowe/roberta-base-uncased-go_emotions` | 28 emotions | CPU ⭐⭐ | Try |
| `nlptown/bert-base-multilingual-uncased-sentiment` | 5 stars | CPU ⭐⭐ | Try |
| LLM-based | Any LLM | Ollama/MLX ⭐⭐⭐ | Use now |

**Metric:** Accuracy vs. human-labeled sentiment. Cohen's kappa for inter-annotator agreement.

---

### Stage L4: Question Detection & Answerability

**What it does:** Identifies questions asked, whether they were answered, and what the answer was.

**Why it matters:** Unanswered questions are open threads. Questions signal information gaps.

**Candidates:**
- Regex patterns for question marks + helper verbs ✅ Use now
- `lfcc/spanish-question-detection` (adapt for English) 💡
- LLM-based ⭐ Use now

**Output:**
```json
{
  "questions_asked": [
    {
      "speaker": "Mike",
      "text": "What's the timeline for the API migration?",
      "start": 45.2,
      "answered": true,
      "answer_speaker": "Alex",
      "answer_text": "Should be ready for testing by Friday."
    },
    {
      "speaker": "Priya",
      "text": "Are we still on for the March 30 launch?",
      "start": 120.5,
      "answered": false,
      "unanswered_topic": "launch date confirmation"
    }
  ]
}
```

---

### Stage L5: Action Item Urgency & Priority Scoring

**What it does:** Scores each action item by urgency.

**Current state:** None — all actions are treated equally.

**Why it matters:** Not all actions are equal. "Ship by March 30" is urgent. "Schedule a follow-up" is not.

**Scoring dimensions:**
- **Deadline proximity:** Due within 24h = high urgency
- **Explicit urgency language:** "ASAP", "urgent", "critical" = high
- **Business impact:** Revenue-impacting = high
- **Blocking:** Other tasks depend on this = high

**Candidates:**
- Rule-based (deadline keywords + date extraction) ⭐⭐⭐ Use now
- LLM-based scoring ⭐⭐⭐ Use now
- Fine-tuned urgency classifier 💡 Future

---

### Stage L6: Key Phrase & Vocabulary Extraction

**What it does:** Extracts important bigrams, trigrams, and phrases from the meeting.

**Why it matters:** Complement to topic extraction. Captures specific terminology that TF-IDF-style analysis finds.

**Candidates:**
- `BertKeywordsExtractor` ⭐ Try
- KeyBERT (embedding-based keyphrase extraction) ⭐ Try
- LLM-based ⭐⭐⭐ Use now

---

### Stage L7: Meeting Quality & Engagement Scoring

**What it does:** Scores the meeting on participation balance, decision velocity, and overall quality.

**Why it matters:** Not all meetings are equally useful. This gives teams feedback on their meeting health.

**Metrics:**
```json
{
  "participation_balance": {
    "score": 0.73,
    "most_talkative": "Alice (42%)",
    "least_talkative": "Priya (8%)",
    "balance_rating": "moderate imbalance"
  },
  "decision_velocity": {
    "decisions_made": 3,
    "time_to_first_decision": "12 minutes",
    "rating": "high"
  },
  "engagement": {
    "question_count": 7,
    "cross_team_interaction": true,
    "rating": "engaged"
  },
  "overall_quality_score": 0.81
}
```

**Candidates:** Rule-based metrics (easy to compute) + LLM-based quality assessment ⭐ Use now.

---

### Stage L8: Intent Classification 💡

**What it does:** Classifies the type/purpose of the meeting from the transcript.

**Why it matters:** Different meeting types need different analysis frames.

**Types:**
- Standup / status update
- Decision-making
- Brainstorming
- 1-on-1
- Client/customer call
- Incident response
- Planning / roadmap

**Candidates:** LLM-based classification ⭐ Use now.

---

### Stage L9: Action Item Dependency Graph 💡

**What it does:** Builds a graph of dependencies between action items across meetings.

**Why it matters:** "Alice can't start on X until Bob finishes Y." Track across meetings.

**Candidates:** LLM-based dependency extraction + topological sort ⭐📋.

---

## PHASE 5: ENTITY & KNOWLEDGE

---

### Stage E1: Named Entity Recognition (NER)

**What it does:** Extracts specific entity types from transcript.

**Current state:** Partially in L1 (LLM extracts entities as part of actions/decisions).

**Dedicated NER (separate from LLM):**

**E1a. Speaker Identity Resolution** ⭐⭐⭐  
Links "Alice" across meetings to a canonical speaker profile.

**E1b. Organization Extraction**  
"Orion Labs", "the backend team", "DevOps" — extracts and normalizes org names.

**E1c. Project & Code Name Extraction**  
Meeting-specific project names, code names, feature identifiers.

**E1d. Date & Deadline Extraction**  
Natural language dates → ISO format. "next Friday" → "2026-03-27".

**E1e. Metric & Number Extraction**  
"2.2x forecast", "200 users affected", "15 minute window" — quantifies claims.

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `dslim/bert-base-NER` | Person/Org/Location | CPU ⭐⭐⭐ | Try now |
| `qrocher/presidio-ner-pii` | PII + custom | CPU ⭐⭐ | Use now |
| `tomaarsen/spacy-lookup-loc` | Location NER | CPU ⭐ | Try |
| LLM-based extraction | Any LLM | Ollama/MLX ⭐⭐⭐ | Use now |

**Metric:** Entity-level F1 vs. annotated test set.

---

### Stage E2: Knowledge Graph Construction 💡

**What it does:** Builds a graph of entities and relationships from meetings.

**Nodes:** People, projects, organizations, decisions, action items
**Edges:** "works on", "decided", "reports to", "depends on"

**Why it matters:** Enables "Who made this decision?", "What projects is Alice working on?", "What decisions have we made about X?"

**Candidates:** LLM-based extraction + NetworkX or Neo4j for storage ⭐📋.

---

### Stage E3: Cross-Meeting Identity Resolution

**What it does:** Links speakers, projects, and topics across meetings over time.

**Current state:** None.

**This is the key to EchoPanel's competitive moat.** The longer you use it, the smarter it gets about your organization's meeting patterns.

**Candidates:**
- Speaker embedding clustering ⭐📋
- LLM-based entity linking ⭐📋
- Rule-based (email matching, name normalization) ⭐ Use now

---

## PHASE 6: STORAGE & RETRIEVAL

---

### Stage R1: Semantic Embedding Generation

**What it does:** Generates vector embeddings of transcript segments for semantic search.

**Current state:**
- **Model:** `sentence-transformers/all-MiniLM-L6-v2` (384 dims, CPU)
- **Storage:** ChromaDB
- **Index:** Per-segment, full transcript, summary

**Output:** 384-dimensional vector per segment, stored with metadata (speaker, meeting_id, timestamp).

**Candidate models:**

| Model | Dims | MTEB Score | Context | Hardware | Priority |
|-------|------|-----------|---------|----------|----------|
| `BAAI/bge-m3` | 1024 | 64.2% ⭐ | 8K | T4+ | ⭐⭐⭐ Benchmark |
| `intfloat/e5-base-v2` | 768 | 62.5% | 512 | CPU | ⭐⭐ Benchmark |
| `sentence-transformers/all-mpnet-base-v2` | 768 | 62.3% | 384 | CPU | ⭐⭐ Benchmark |
| `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | 384 | 57.0% | 128 | CPU | ⭐⭐ |
| `mlx-community/all-MiniLM-L6-v2-4bit` | 384 | ~57% | 256 | MLX ⭐⭐⭐ | ⭐⭐⭐ Benchmark |
| `mlx-community/e5-base-4bit` | 768 | ~62% | 512 | MLX | ⭐⭐ |

**What bge-m3 unlocks:**
- 8K token context (vs 256 for MiniLM) — embed entire long transcripts as one vector
- Best MTEB benchmark score by wide margin
- Excellent multilingual support

**Embedding types to generate:**
- Segment embeddings (per sentence/paragraph)
- Full transcript embedding
- Summary embedding
- Action items embedding
- Speaker persona embedding (average of a speaker's contributions)

**Metric:** MRR@10 and Recall@K on retrieval test set.

**Autoresearch applicable:** ✅ Yes — for model selection.

---

### Stage R2: Hybrid Search

**What it does:** Combines keyword (BM25) + semantic search for robust retrieval.

**Current state:**
- `hybrid_search.py` exists with RRF (Reciprocal Rank Fusion)
- BM25 via `rank_bm25`

**Enhancements:**
- Learn-to-rank model (LTR) using click data ⭐📋
- Query-type-aware fusion (questions → semantic, fact lookups → keyword) ⭐📋

---

### Stage R3: Cross-Encoder Reranking

**What it does:** Refines top-K retrieval results using a cross-encoder for precision.

**Current state:** None — only embedding-based retrieval.

**Candidates:**

| Model | Type | Hardware | Priority |
|-------|------|----------|----------|
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | Reranker | CPU ⭐⭐⭐ | Try now |
| `cross-encoder/ms-marco-MiniLM-L-12-v2` | Reranker | CPU ⭐⭐ | Try |
| `cross-encoder/quora-roberta-base` | Similarity | CPU ⭐⭐ | Try |

**Two-stage retrieval:**
1. **Dense retrieval** (embedding): Get top-50 results fast
2. **Cross-encoder reranking**: Re-score top-50 with cross-encoder → return top-10

**Metric:** NDCG@10 on retrieval test set.

**Autoresearch applicable:** ✅ Yes — for model selection.

---

### Stage R4: Query Understanding & Expansion

**What it does:** Improves search by understanding what the user is actually asking.

**Sub-stages:**

**R4a. Intent Detection**  
"Is this a question, a command, or a topic search?"

**R4b. Query Expansion / Rewriting**  
"what did alice say about the q1 roadmap" → ["Alice Q1 roadmap discussion", "Alice roadmap decisions", "Q1 planning Alice input"]

**R4c. Query Decomposition**  
Complex query → multiple sub-queries → merge results.

**R4d. Citation Linking**  
Each search result links to exact transcript location (speaker + timestamp).

**Candidates:** LLM-based ⭐ Use now for all sub-stages.

---

## PHASE 7: OUTPUT & DELIVERY

---

### Stage O1: Structured Output Formatting

**What it does:** Formats extraction results for different consumers.

**Current state:** Basic JSON output.

**Formats needed:**
- JSON (API consumers)
- Markdown (Notion, Obsidian)
- HTML (email)
- Plain text (SMS, Slack)
- Action items as ICS (calendar events)
- Action items as Trello/Linear/Jira tasks ⭐📋

---

### Stage O2: Text-to-Speech (Read-Aloud)

**What it does:** Converts text output to audio for voice delivery.

**Current state:** None — all output is text.

**Why it matters:**
- Read-aloud of meeting summary during commute
- Action item notification as audio
- Briefing audio for busy executives

**Candidates:**

| Model | Quality | Latency | Hardware | Priority |
|-------|---------|---------|----------|----------|
| `suno-ai/bark-ultra` | ⭐⭐⭐⭐ | Medium | HF Pro ⭐⭐⭐ | Get access |
| `suno-ai/bark` | ⭐⭐⭐ | Slow | CPU (slow) | Try |
| `xtts` | ⭐⭐⭐ | Fast | CPU/ONNX ⭐⭐⭐ | Try now |
| macOS `say` | ⭐ | Instant | Built-in ⭐ | Use for prototyping |

**xtts is the priority open-source option.** Runs locally, good quality, reasonable speed.

**Voice cloning:** xtts supports voice cloning from a 30-second sample — could use this to clone meeting participants' voices for attribution in read-aloud ⭐💡.

**Metric:** MOS (Mean Opinion Score) — human listening test.

---

### Stage O3: Notification & Alerting

**What it does:** Sends notifications when meeting intelligence is ready.

**Current state:** None.

**Channels:**
- Email digest
- Slack/Teams webhook
- Push notification (mobile)
- Calendar invite (for action items with deadlines)

**Smart routing:**
- Urgent action items → SMS/push
- Regular summaries → email/Slack
- Meeting completed → calendar update

---

## PHASE 8: QUALITY & IMPROVEMENT

---

### Stage Q1: Per-Stage Confidence Scoring

**What it does:** Every stage outputs a confidence score alongside its result.

**Why it matters:** Enables fallback routing. Low confidence → upgrade to better model.

**Confidence signals per stage:**
- ASR: average token probability, language detection confidence
- Diarization: speaker embedding similarity scores
- Extraction: LLM log probability, semantic consistency check
- Embeddings: cosine similarity of top result

**Output:**
```json
{
  "extraction_confidence": 0.94,
  "low_confidence_signals": [],
  "fallback_triggered": false
}
```

---

### Stage Q2: User Correction Feedback Loop ⭐⭐⭐

**What it does:** Logs when users correct meeting intelligence. Uses corrections to improve.

**This is the key to a self-improving system.**

**Loop:**
1. User corrects "Alice didn't say she'd do that, Bob did"
2. Correction logged with full context (meeting_id, segment, original, correction)
3. Periodic: run echoai-mlx loop with corrections as test set additions
4. Updated production model → fewer corrections next time

**What to log:**
- Corrected action assignments
- Corrected decision descriptions
- Corrected topic labels
- Missed actions/decisions
- False positive actions/decisions

**Metric:** Correction rate (lower = better). Target: < 5% of extractions corrected.

---

### Stage Q3: A/B Testing Framework 💡

**What it does:** Systematically tests model changes before full deployment.

**How:** Route 10% of meetings to new model → compare correction rates.

**Needs:** Traffic splitting infrastructure, correction rate tracking, statistical significance testing.

---

### Stage Q4: Model Versioning & Rollback

**What it does:** Every production model version is tracked. Bad output → instant rollback.

**What to track per version:**
- Model weights / config
- System prompt version
- Test set score (val_f1)
- Production correction rate
- Deployment date

---

## PHASE 9: META & INFRASTRUCTURE

---

### Stage M1: Meeting Ingestion Pipeline

**What it does:** Orchestrates the entire pipeline from audio upload to intelligence output.

**Current state:** Basic orchestration in server code.

**What it should do:**
- Queue management (Celery/Redis or similar)
- Parallel stage execution where possible (ASR + diarization can run in parallel)
- Timeout handling per stage
- Fallback routing on low confidence
- Partial output delivery (give what we have, mark what's pending)

---

### Stage M2: Storage Architecture

**Current state:**
- Transcripts → file storage / SQLite
- Embeddings → ChromaDB
- Meeting metadata → SQLite

**What should exist:**
- **Transcripts:** PostgreSQL (full-text search via pgvector)
- **Embeddings:** ChromaDB (or pgvector for production scale)
- **Meeting metadata:** PostgreSQL
- **User corrections:** PostgreSQL (for feedback loop)
- **Model versions:** PostgreSQL or DVC
- **Audit logs:** S3 or similar

---

### Stage M3: Metrics & Observability

**What it does:** Tracks pipeline health and quality metrics.

**Metrics to track:**
- Per-stage latency (p50, p95, p99)
- Per-stage error rate
- ASR WER (on sampled meetings)
- Extraction F1 (on ground-truth meetings)
- Correction rate (per user, per meeting type)
- Search result CTR (did users click results?)

---

## Priority Summary Table

All stages, ranked by: **impact × feasibility × data availability**

| Rank | Stage | What | Metric | Priority | Status |
|------|-------|------|--------|----------|--------|
| 1 | L1 | Extraction loop | val_f1 | ⭐⭐⭐ | ✅ Running |
| 2 | A1 | ASR benchmark | Downstream F1 | ⭐⭐⭐ | 📋 Ready |
| 3 | R1 | Embedding benchmark | MRR@10 | ⭐⭐⭐ | 📋 Ready |
| 4 | E1 | NER / speaker resolution | Entity F1 | ⭐⭐⭐ | 📋 Ready |
| 5 | R3 | Cross-encoder reranking | NDCG@10 | ⭐⭐ | 📋 Ready |
| 6 | T3 | PII redaction | Recall | ⭐⭐⭐ | 📋 Ready |
| 7 | A2 | Diarization | DER | ⭐⭐⭐ | 📋 Need test set |
| 8 | O2 | TTS (xtts) | MOS | ⭐⭐ | 📋 Ready |
| 9 | L3 | Sentiment analysis | Accuracy | ⭐⭐ | 📋 Ready |
| 10 | T1 | Punctuation | Accuracy | ⭐⭐ | 📋 Ready |
| 11 | L4 | Question detection | F1 | ⭐⭐ | 📋 Ready |
| 12 | T6 | Coreference resolution | F1 | ⭐⭐ | 📋 Future |
| 13 | R4 | Query expansion | MRR improvement | ⭐⭐ | 📋 Future |
| 14 | L5 | Urgency scoring | Accuracy | ⭐⭐ | 📋 Future |
| 15 | L7 | Meeting quality | Score accuracy | ⭐⭐ | 📋 Future |
| 16 | A3 | Voice biometrics | Linking accuracy | ⭐⭐ | 📋 Future |
| 17 | E2 | Knowledge graph | Recall | ⭐ | 📋 Future |
| 18 | Q2 | Feedback loop | Correction rate | ⭐⭐⭐ | 📋 Design |
| 19 | Q1 | Confidence scoring | Coverage | ⭐⭐ | 📋 Future |
| 20 | L9 | Dependency graph | Accuracy | ⭐ | 📋 Future |
| 21 | O3 | Notification routing | Delivery rate | ⭐ | 📋 Future |
| 22 | A0b | Noise reduction | SNR improvement | ⭐⭐ | 📋 Future |
| 23 | M3 | Observability | Coverage | ⭐⭐ | 📋 Future |

---

## Complete Model ↔ Stage Matrix

| Model | Stage(s) | Hardware | HF Pro? | Priority |
|-------|---------|----------|---------|----------|
| `openai/whisper-large-v3` | A1 ASR | HF Pro | ✅ | ⭐⭐⭐ |
| `mlx-community/Qwen3-ASR-1.7B` | A1 ASR | MLX | ❌ | ⭐⭐⭐ |
| `mlx-community/Whisper-small-mlx` | A1 ASR | MLX | ❌ | ⭐⭐⭐ |
| `mlx-community/Qwen3-ASR-0.6B` | A1 ASR | MLX | ❌ | ⭐⭐ |
| `mlx-community/voxtral-medium-en-2.5B` | A1 ASR | MLX | ❌ | ⭐⭐ |
| `pyannote/segmentee-3.0` | A2 Diarization | HF Pro | ✅ | ⭐⭐⭐ |
| `pyannote/EBR-0.1` | A2 Diarization | HF Pro | ✅ | ⭐⭐⭐ |
| `burkazero/transformers-punct` | T1 Punct | CPU | ❌ | ⭐⭐⭐ |
| `qrocher/presidio-ner-pii` | T3 PII | CPU | ❌ | ⭐⭐⭐ |
| `dslim/bert-base-NER` | E1 NER | CPU | ❌ | ⭐⭐⭐ |
| `Llama-3.2-1B-Instruct-4bit` | L1 Extraction | MLX | ❌ | ⭐⭐⭐ |
| `gemma-3-4b-it-qat-4bit` | L1 Extraction | MLX | ❌ | ⭐⭐ |
| `mistralai/Mistral-Small-3.1-24B-Instruct` | L1 Extraction | HF Pro | ✅ | ⭐⭐⭐ |
| `deepseek-ai/DeepSeek-V3-0324` | L1 Extraction | HF Pro | ✅ | ⭐⭐ |
| `BAAI/bge-m3` | R1 Embeddings | T4+ | ❌ | ⭐⭐⭐ |
| `mlx-community/all-MiniLM-L6-v2-4bit` | R1 Embeddings | MLX | ❌ | ⭐⭐⭐ |
| `cross-encoder/ms-marco-MiniLM-L-6-v2` | R3 Reranking | CPU | ❌ | ⭐⭐⭐ |
| `SamLowe/roberta-base-uncased-go_emotions` | L3 Sentiment | CPU | ❌ | ⭐⭐ |
| `suno-ai/bark-ultra` | O2 TTS | HF Pro | ✅ | ⭐⭐⭐ |
| `xtts` | O2 TTS | CPU/ONNX | ❌ | ⭐⭐⭐ |
| `snakers4/silero-vad` | A0c VAD | CPU | ❌ | ⭐⭐ |
| `facebook/denoiser` | A0b Denoise | CPU | ❌ | ⭐⭐ |
| `NLPA4A/phishing-url-detector` | T4 Profanity | CPU | ❌ | ⭐ |
| `xtts` | O2 Voice cloning | CPU/ONNX | ❌ | ⭐⭐ |

---

*This document is the definitive reference for EchoPanel's ML pipeline.*  
*Maintained in: `~/Projects/EchoPanel/docs/research/ECHO_PANEL_COMPLETE_PIPELINE_RFC.md`*  
*Companion: `~/Projects/EchoPanel/docs/research/ECHO_PANEL_STAGE_MAP.md`*  
*Companion: `~/Projects/EchoPanel/docs/research/MODEL_BENCHMARKING_PLAN.md`*
