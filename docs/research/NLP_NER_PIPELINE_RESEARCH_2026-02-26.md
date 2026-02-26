# NLP / NER Pipeline Research — EchoPanel
**Date:** 2026-02-26  
**Status:** Research Complete  
**Context:** macOS 15, Swift 6.2, Apple Silicon (M1+), fully local inference only  
**Scope:** All NLP/NER pipeline components beyond the known ASR/diarization/embedding stack  

---

## Executive Summary

10 key findings from a full sweep of HuggingFace, mlx-audio-swift, mlx-swift-lm, and swift-transformers checkouts:

1. **No mlx-community NER models exist** — zero results on `?search=ner&author=mlx-community`. NER must come from Apple NaturalLanguage.framework (person/org/place) + GLiNER via ONNX Runtime for Swift + LLM prompting for meeting-semantic labels (action items, decisions).
2. **GLiNER has no MLX port** — only an `onnx-community` bridge exists. `fastino/gliner2-base-v1` (228K downloads, Apache 2.0) is the most production-ready ONNX GLiNER; it runs on macOS via ONNX Runtime for Swift with no Python dependency.
3. **Forced alignment is already solved** — `Qwen3ForcedAligner.swift` ships in mlx-audio-swift and `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` is confirmed live on HF (Apache 2.0). `ParakeetAlignment.swift` provides CTC-based alignment for Parakeet models. No separate aligner model is needed.
4. **Punctuation restoration is a non-issue for LLM-based ASR** — Qwen3-ASR and VoxtralRealtime use autoregressive decoders and output naturally punctuated text. Only Parakeet (CTC-based) needs post-processing; `oliverguhr/fullstop-punctuation-multilingual-base` is the best offline option but has no MLX port.
5. **Language detection is already in Swift** — Apple `NLLanguageRecognizer` covers ~50 languages with zero model download and sub-millisecond latency. `facebook/fasttext-language-identification` (219 languages, 917 KB) is CC-BY-NC-4.0 (non-commercial restriction) — unsuitable for a commercial app.
6. **Sentence boundary detection needs nothing new** — Apple `NLTokenizer(.sentence)` handles standard splitting. `SmartTurn` (already in mlx-audio-swift `MLXAudioVAD`) detects real-time turn boundaries. Semantic segmentation can use the existing `nomic-embed-text-v2-moe` with cosine change detection.
7. **Topic modeling has no viable small MLX model** — four HF results had ≤2 downloads each. The practical path is the existing embedding model (nomic-embed-text-v2-moe) + TextTiling change detection, with LLM prompting for explicit section labels.
8. **Action item extraction is an LLM task** — dedicated fine-tuned models on HF had ≤3 downloads. `knowledgator/gliner-multitask-v1.0` (Apache 2.0, 5.4K downloads) can serve as a lightweight complement for entity-like span extraction.
9. **Speaker embedding / Voice ID is covered by Sortformer** — `pyannote/embedding` (713K downloads, MIT) is PyTorch-only with no MLX port. Sortformer v2.1 already returns `DiarizationSegment` with speaker IDs and `speakerProbs`. No separate voice-ID model is needed unless cross-meeting speaker re-identification becomes a product requirement.
10. **Grammar correction is handled upstream** — Qwen3-ASR's autoregressive decoder self-corrects output. For Parakeet CTC output, the LLM analysis step (Qwen2.5/Qwen3) provides implicit grammar correction during summarization. No dedicated grammar correction model is warranted.

---

## Codebase Inventory — What's Already in the Swift Checkouts

### mlx-audio-swift (`MLXAudioSTT`)
| File | Capability |
|------|-----------|
| `Qwen3ForcedAligner.swift` | Word/character-level timestamps via MLX CTC alignment |
| `ParakeetAlignment.swift` | CTC forced alignment for Parakeet models (`ParakeetAlignedSentence`, `ParakeetAlignedToken`) |
| `Qwen3ASR.swift` | LLM-based ASR → punctuated output |
| `VoxtralRealtime*.swift` | LLM-based streaming ASR → punctuated output |
| `ParakeetModel.swift` | CTC ASR → **no punctuation** in raw output |
| `GLMASR/` | LLM-based ASR (batch-only) → punctuated output |

### mlx-audio-swift (`MLXAudioVAD`)
| File | Capability |
|------|-----------|
| `SmartTurn.swift` | Real-time turn/utterance endpoint detection |
| `Sortformer.swift` | Speaker diarization → `DiarizationSegment` + `speakerProbs` |
| `VADOutput.swift` | `DiarizationOutput` with RTTM text export |

### mlx-audio-swift (`MLXAudioSTS`)
| File | Capability |
|------|-----------|
| `MossFormer2*.swift` | Speech enhancement (denoising) |
| `SAMAudio*.swift` | Facebook SAM-Audio (voice isolation) |
| `LFMAudio*.swift` | LFM2.5-Audio speech-to-speech |

### swift-transformers (`Sources/Tokenizers`)
- Full tokenizer suite (BPE, BERT, Unigram) — usable for custom NLP model inference if ONNX Runtime is added
- No NER or classification heads present

### mlx-swift-lm (`Sources/`)
- `MLXEmbedders` (via `MLXLM` package): ships nomic-embed-text support
- No dedicated NLP classification utilities

---

## Component-by-Component Analysis

### 1. Named Entity Recognition (NER)

**Goal:** Extract people, organizations, projects, action items, decisions, dates from meeting transcripts.

#### 1a. Apple NaturalLanguage.framework
| Attribute | Value |
|-----------|-------|
| **API** | `NLTagger` with `.nameType` scheme |
| **Labels** | `personalName`, `organizationName`, `placeName` |
| **Size** | 0 MB (OS-bundled) |
| **Latency** | ~1–5ms per paragraph |
| **License** | Apple platform entitlement |
| **Swift** | ✅ Native — already in `EntityHighlighter.swift` |
| **Gaps** | No product names, project names, dates, action items, or custom labels |
| **Verdict** | **KEEP** — fast, free, covers basic PER/ORG/LOC |

#### 1b. GLiNER (Open-Label NER)
GLiNER (Generalist and Lightweight Model for NER) allows runtime-specified label types without retraining. It can extract `"project"`, `"action item"`, `"deadline"`, `"decision"`, etc. dynamically.

| Model | Size | Downloads | License | MLX? | ONNX? |
|-------|------|-----------|---------|------|-------|
| `fastino/gliner2-base-v1` | ~130 MB | 228,019 | Apache 2.0 | ❌ | ✅ SafeTensors/ONNX |
| `fastino/gliner2-large-v1` | ~360 MB | 135,090 | Apache 2.0 | ❌ | ✅ |
| `urchade/gliner_small-v2.1` | ~100 MB | 6,686 | Apache 2.0 | ❌ | ✅ (`onnx-community`) |
| `urchade/gliner_medium-v2.1` | ~180 MB | 7,817 | Apache 2.0 | ❌ | ✅ |
| `knowledgator/gliner-multitask-v1.0` | ~180 MB | 5,404 | Apache 2.0 | ❌ | ❓ |
| `onnx-community/gliner_base` | ~170 MB | 1,507 | Apache 2.0 | ❌ | ✅ (transformers.js) |
| `onnx-community/gliner_multi-v2.1` | ~170 MB | 1,160 | Apache 2.0 | ❌ | ✅ (transformers.js) |

**MLX Port Status:** No mlx-community GLiNER models found (0 results). No community GLiNER MLX implementation exists as of 2026-02-26.

**Practical Path for EchoPanel:**
- Option A: ONNX Runtime for macOS (via [onnxruntime-swift](https://github.com/microsoft/onnxruntime) SPM package) → run `fastino/gliner2-base-v1`. Adds ~10 MB SPM dependency; model is ~130 MB. Latency ~20–80ms per transcript segment on M1. **Recommended for v0.3.**
- Option B: LLM prompting via existing Qwen2.5/Qwen3 for meeting-specific semantic entities. **No extra model; recommended for v0.3 interim.**
- Option C: Port GLiNER to MLX Swift (bi-encoder BiLSTM + DeBERTa-v3 encoder). Significant effort; not warranted until Option A is validated.

**EchoPanel Recommendation:**
```
Phase 1 (v0.3 interim): LLM prompt extraction for action items/decisions/deadlines
Phase 2 (v0.4): ONNX GLiNER2-base (fastino, Apache 2.0, ~130MB) for structural NER
Phase 3 (future): Evaluate GLiNER MLX port if runtime budget allows
```

#### 1c. spaCy
- Python only. No Swift bindings exist. `en_core_web_trf` mentioned in `NER_PIPELINE_ARCHITECTURE.md` is a Python-only runtime.
- **Verdict:** Remove from Swift-native roadmap. Viable only in the Python backend fallback.

#### 1d. LLM Prompting for Meeting Entities
- Qwen2.5-1.5B-Instruct-4bit or Qwen3-4B-Instruct for extracting: action items, decisions, open questions, project names, deadlines.
- LLM wins over dedicated NER for **semantic labels** in meetings (e.g., "John will send the report by Friday" → action item + owner + deadline).
- Dedicated NER (GLiNER) wins for **structural span extraction** at scale (extract all mentions of a company name across 1-hour transcript).
- **Both are needed** — they are complementary, not competing.

---

### 2. Word-level Timestamping / Forced Alignment

**Goal:** Map each word in the transcript to its exact start/end time in audio.

#### 2a. `Qwen3ForcedAligner` (MLX, in mlx-audio-swift)
| Attribute | Value |
|-----------|-------|
| **HF Model** | `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` |
| **Confirmed Live** | ✅ — 69 downloads, 1 like, Apache 2.0 |
| **Tags** | `mlx-audio`, `qwen3_asr`, `mlx`, `speech-to-text`, `asr`, `stt` |
| **Size** | ~620 MB (bf16) |
| **Swift Class** | `ForceAlignProcessor` in `Qwen3ForcedAligner.swift` |
| **Output** | `ForcedAlignResult` with `[ForcedAlignItem]` (text, startTime, endTime) |
| **License** | Apache 2.0 |
| **MLX-native** | ✅ Full MLX Swift — no Python dependency |
| **Latency** | Estimated <200ms for 10-minute transcript on M1 |
| **Verdict** | **USE THIS** — already in the Swift checkout, confirmed model on HF |

#### 2b. Parakeet CTC Alignment (MLX, in mlx-audio-swift)
| Attribute | Value |
|-----------|-------|
| **Swift Class** | `ParakeetAlignedResult`, `ParakeetAlignedSentence`, `ParakeetAlignedToken` |
| **Method** | CTC forced alignment (built into Parakeet's own decoder) |
| **Output** | Token-level timestamps from CTC emission probabilities |
| **Latency** | Near-zero overhead (derived from ASR pass) |
| **Verdict** | **USE** when Parakeet is the active ASR model |

#### 2c. WhisperX / CTC Forced Aligner (PyTorch)
- WhisperX requires `torchaudio`, `pyannote.audio` — Python stack only. Not viable for Swift-native EchoPanel.
- `ctc-segmentation` library: Python only, no Swift bindings.
- **Verdict:** Python backend only.

#### 2d. Apple Speech Framework Timestamps
- `SFSpeechAudioBufferRecognitionRequest` returns word-level timestamps with `.requiresOnDeviceRecognition = true`.
- Accuracy significantly lower than MLX ASR (Apple on-device models lag Qwen3-ASR by ~15–25% WER).
- **Verdict:** Fallback-of-last-resort only.

---

### 3. Punctuation Restoration

**Goal:** Ensure transcript output has proper sentence boundaries and capitalization.

#### Key Finding: ASR Model Determines This
| ASR Model | Architecture | Punctuation Output | Action Needed |
|-----------|-------------|-------------------|---------------|
| Qwen3-ASR-0.6B/1.7B | LLM decoder (autoregressive) | ✅ Natural punctuation | None |
| VoxtralRealtime-4bit | LLM decoder (Ministral-based) | ✅ Natural punctuation | None |
| Parakeet-TDT | CTC / RNNT | ❌ Raw unpunctuated tokens | Post-processing needed |
| GLM-ASR-Nano | LLM decoder | ✅ Natural punctuation | None |

#### Dedicated Punctuation Models (for Parakeet CTC output)
| Model | Downloads | Size | MLX? | License | Recommendation |
|-------|-----------|------|------|---------|----------------|
| `oliverguhr/fullstop-punctuation-multilang-large` | 889,830 | ~560 MB | ❌ | MIT | Too large |
| `oliverguhr/fullstop-punctuation-multilingual-base` | 73,724 | ~280 MB | ❌ | MIT | **Best option via ONNX** |
| `1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase` | 274,746 | ~280 MB | ❌ | MIT? | Good alternative |
| `felflare/bert-restore-punctuation` | 322 | ~110 MB | ❌ | MIT? | Small, English-only |
| mlx-community punctuation | — | — | ❌ | — | None found |

**Silero VAD Punctuation Mode:** Does not exist. Silero VAD (`aufklarer/Silero-VAD-v5-MLX` in checkout) is voice activity detection only.

**EchoPanel Recommendation:**
- For Qwen3-ASR / VoxtralRealtime: No action needed — punctuation comes free.
- For Parakeet fallback: Use LLM reformatting step (existing Qwen2.5 in stack) rather than adding a dedicated punctuation model. Keeps RAM budget clean.
- If dedicated model is required later: `oliverguhr/fullstop-punctuation-multilingual-base` via ONNX Runtime (same dependency as GLiNER path).

---

### 4. Language Detection / Identification

**Goal:** Detect spoken language to route to correct ASR model or enable multilingual features.

#### 4a. Apple `NLLanguageRecognizer`
| Attribute | Value |
|-----------|-------|
| **API** | `NLLanguageRecognizer` (NaturalLanguage.framework) |
| **Coverage** | ~59 languages |
| **Latency** | Sub-millisecond |
| **Size** | 0 MB (OS-bundled) |
| **License** | Apple platform entitlement |
| **Swift** | ✅ Native, `dominantLanguage(for:)` |
| **Accuracy** | Excellent for written text; good for transcribed speech |
| **Verdict** | **USE AS PRIMARY** — ideal for detecting language from first 30 seconds of transcript |

#### 4b. `facebook/fasttext-language-identification`
| Attribute | Value |
|-----------|-------|
| **Size** | ~917 KB (fastText binary format) |
| **Coverage** | 219 languages |
| **Downloads** | 379,762 |
| **License** | **CC-BY-NC-4.0 (non-commercial!)** |
| **Swift** | No native binding; C++ wrapper or Python only |
| **Verdict** | ⚠️ **BLOCKED** — license prohibits commercial use. Do not use in EchoPanel. |

#### 4c. MLX Language ID Models
- Zero mlx-community language identification models found.

#### 4d. Qwen3-ASR Language Auto-Detection
- Qwen3-ASR accepts a `language` generation parameter. Without hint: auto-detects from audio but may be less stable on short segments (<5s). For EchoPanel's typical 30-minute meeting audio, auto-detection is reliable.
- **Strategy:** Run `NLLanguageRecognizer` on first transcribed paragraph → pass language hint to subsequent ASR calls.

---

### 5. Sentence Boundary Detection / Segmentation

**Goal:** Split long meeting transcripts into meaningful sentences/segments for NER, embedding, and display.

#### 5a. Apple `NLTokenizer(.sentence)`
| Attribute | Value |
|-----------|-------|
| **API** | `NLTokenizer(unit: .sentence)` |
| **Latency** | ~1ms per 1000 chars |
| **License** | Apple platform entitlement |
| **Quality** | Excellent for properly punctuated text (Qwen3/Voxtral output) |
| **Verdict** | **USE AS PRIMARY** for LLM-based ASR output |

#### 5b. SmartTurn (already in `MLXAudioVAD`)
| Attribute | Value |
|-----------|-------|
| **Swift Class** | `SmartTurn` in `MLXAudioVAD` |
| **Function** | Real-time utterance endpoint detection (is speaker done talking?) |
| **Output** | `SmartTurnEndpointOutput` (prediction: 0/1, probability: Float) |
| **Use Case** | Live transcription chunk boundaries, not post-hoc sentence splitting |
| **Verdict** | **ALREADY AVAILABLE** — use for live streaming turn segmentation |

#### 5c. Semantic Segmentation
- `igorsterner/xlmr-multilingual-sentence-segmentation` (11,170 downloads, XLM-R based, ~280 MB) — Python/PyTorch only.
- No MLX port found.
- **Practical path:** `nomic-embed-text-v2-moe` (already in stack) + cosine similarity change detection (TextTiling algorithm, pure Swift, ~50 lines).

---

### 6. Topic Modeling / Meeting Section Detection

**Goal:** Detect when the meeting shifts to a new topic (e.g., "Budget review → Q3 planning → Action items").

| Approach | Viability | Notes |
|----------|-----------|-------|
| Dedicated MLX topic model | ❌ None found | 4 HF models, ≤2 downloads each |
| `nomic-embed-text-v2-moe` + cosine change | ✅ **Recommended** | Already in stack; TextTiling needs ~50 LoC Swift |
| LLM prompt (Qwen2.5/Qwen3) | ✅ **Recommended** | Post-call analysis: "Identify section boundaries and label them" |
| BERTopic (Python) | Python only | Via Python backend only |

**EchoPanel Recommendation:** Two-tier approach:
1. **Embedding change detection** (real-time): Sliding window cosine similarity on nomic embeddings → detect topic shifts
2. **LLM section labeling** (post-call): Qwen3 prompt to label sections with titles

---

### 7. Action Item / Summary Extraction

**Goal:** Detect sentences that are action items, decisions, open questions, risks.

#### Dedicated Fine-tuned Models on HF
| Model | Downloads | Quality | Verdict |
|-------|-----------|---------|---------|
| `knkarthick/Action_Items` | 3 | Unknown | ❌ Too experimental |
| `debal/distilbart-samsum-action-items` | 2 | Unknown | ❌ Too experimental |
| `asach/bert-action-items` | 0 | Unknown | ❌ Skip |

#### GLiNER Multitask for Meeting Extraction
| Model | Downloads | License | Notes |
|-------|-----------|---------|-------|
| `knowledgator/gliner-multitask-v1.0` | 5,404 | Apache 2.0 | Can extract "action item", "decision", "risk" via open labels |

#### FLAN-T5 MLX
| Model | Downloads | Size | Notes |
|-------|-----------|------|-------|
| `mlx-community/flan-t5-small-mlx-4bit` | 4 | ~80 MB | Too experimental; wrong task type |
| `mlx-community/flan-t5-base-mlx-4bit` | 5 | ~250 MB | Same concern |

#### UniNER (Universal NER)
| Model | Downloads | License | Notes |
|-------|-----------|---------|-------|
| `Universal-NER/UniNER-7B-type` | 1,591 | — | 7B params — too large |
| `Universal-NER/UniNER-7B-all` | 151 | — | 7B params — too large |

**EchoPanel Recommendation:**
- **Primary:** LLM prompt with Qwen3-4B (or Qwen2.5-3B for 8 GB machines) — structured JSON output for action items, decisions, open questions
- **Complement:** GLiNER multitask via ONNX (if ONNX Runtime already added for NER) for span highlighting
- **Avoid:** All fine-tuned action-item models (insufficient community validation)

---

### 8. Emotion / Sentiment for Meeting Tone

**Goal:** Detect meeting tone (engaged, frustrated, uncertain) per speaker segment.

| Approach | Viability | Notes |
|----------|-----------|-------|
| MLX emotion model | ❌ None found | Zero mlx-community emotion models |
| Apple CoreML sentiment | ❌ | No built-in CoreML audio sentiment API |
| Sub-100MB standalone model | ❌ | No viable option found |
| LLM text analysis | ✅ **Recommended** | Qwen3 prompt: "Rate speaker tone as positive/neutral/negative with brief justification" |
| Audio prosody (custom) | 🟡 Future | Pitch/energy features via AVFoundation; no model needed for basic arousal/valence |

**EchoPanel Recommendation:** LLM post-call analysis only. Do not block v0.3 on this. Mark as `v1.0+` feature.

---

### 9. Speaker Embedding / Voice ID (Beyond Diarization)

**Goal:** Identify specific known speakers across meetings ("Is this John Smith again?").

| Model | Downloads | License | MLX? | Swift? |
|-------|-----------|---------|------|--------|
| `pyannote/embedding` | 713,540 | MIT | ❌ PyTorch | ❌ |
| `resemblyzer` | Python package | MIT | ❌ | ❌ |
| mlx-community speaker embedding | — | — | ❌ | ❌ None found |
| Sortformer v2.1 `speakerProbs` | — | Apache 2.0 | ✅ | ✅ Already in stack |

**Key insight from `VADOutput.swift`:** Sortformer already returns `speakerProbs: MLXArray` (speaker probability matrix) alongside `DiarizationSegment` (start, end, speaker: Int). This is sufficient for within-meeting speaker tracking.

**Cross-meeting speaker re-identification** (recognizing the same person in a later meeting) requires persistent speaker embeddings. There is no viable MLX path as of 2026-02-26.

**EchoPanel Recommendation:**
- Use Sortformer `speakerProbs` for all within-session speaker tracking (already in stack)
- Cross-meeting speaker ID: defer to `v1.0+`; requires pyannote/embedding via Python backend or a future MLX port

---

### 10. Transcript Post-processing / Grammar Correction

**Goal:** Fix grammatical errors, run-on sentences, and inconsistencies in raw ASR output.

| Approach | Viability | Notes |
|----------|-----------|-------|
| MLX grammar correction model | ❌ None found | No mlx-community grammar models |
| LLM reformatting | ✅ **Recommended** | Qwen3 post-call cleanup pass |
| Qwen3-ASR self-correction | ✅ **Already happening** | LLM decoder inherently produces grammatical output |
| Parakeet CTC output | ⚠️ Raw tokens | Clean up via existing LLM analysis step |

**EchoPanel Recommendation:** No dedicated model needed. Qwen3-ASR / VoxtralRealtime handle this natively. Parakeet output is cleaned during LLM analysis.

---

## Gap Analysis — Current Pipeline vs. Complete NLP Coverage

| Capability | Current State | Gap | Recommended Fix | Priority |
|------------|--------------|-----|-----------------|----------|
| Basic NER (PER/ORG/LOC) | ✅ `NLTagger` in `EntityHighlighter.swift` | Labels only: person/org/place | Keep | — |
| Project/Product NER | ❌ Not implemented | No project/product extraction | GLiNER2-base ONNX | 🔴 High |
| Action item extraction | ⚠️ Regex patterns only | Misses implicit action items | LLM prompt (Qwen3) | 🔴 High |
| Decision extraction | ⚠️ Keyword matching | Low recall | LLM prompt (Qwen3) | 🔴 High |
| Word timestamps (Qwen3-ASR path) | ✅ `Qwen3ForcedAligner.swift` exists | Model needs download (~620 MB) | Add to model registry | 🟠 Medium |
| Word timestamps (Parakeet path) | ✅ `ParakeetAlignment.swift` exists | — | Already available | — |
| Punctuation (Qwen3/Voxtral path) | ✅ Native from LLM decoder | — | None | — |
| Punctuation (Parakeet path) | ❌ Missing | CTC has no punctuation | LLM reformat step | 🟠 Medium |
| Language detection | ✅ `NLLanguageRecognizer` (50 lang) | Multilingual confidence signal | Use for ASR lang hint | 🟡 Low |
| Sentence segmentation | ✅ `NLTokenizer(.sentence)` | Semantic boundaries only | Embedding change detection | 🟡 Low |
| Turn segmentation (live) | ✅ `SmartTurn` in mlx-audio-swift | — | Already available | — |
| Topic detection | ❌ Not implemented | No section boundary detection | Embedding + TextTiling | 🟡 Low |
| Meeting section labels | ❌ Not implemented | No section headers in output | LLM post-call prompt | 🟡 Low |
| Emotion / tone | ❌ Not implemented | No speaker mood signal | LLM text analysis | 🟢 Optional |
| Speaker voice ID (cross-session) | ❌ Not implemented | No cross-meeting recognition | Defer to v1.0+ | 🟢 Optional |
| Grammar correction | ✅ Native from LLM ASR decoder | Parakeet path is raw | LLM reformat step | 🟠 Medium |

---

## Recommended Additions (Ranked by Impact / Effort / Risk)

### Priority 1 — High Impact, Low Risk (v0.3)
**LLM Prompt Extraction (Qwen2.5/Qwen3 — already in stack)**
- Extract: action items, decisions, open questions, risks, key dates
- Input: full meeting transcript (with diarization speaker tags)
- Output: structured JSON with evidence anchors (timestamp + speaker)
- Effort: **~2 days** (prompt engineering + parsing Swift code)
- Additional RAM: **0 MB** (reuses existing LLM)
- Recommendation: Implement immediately, before any model additions

### Priority 2 — High Impact, Medium Effort (v0.4)
**GLiNER2-base via ONNX Runtime for macOS (fastino/gliner2-base-v1)**
- Apache 2.0, ~130 MB, 228K HF downloads
- Adds open-label NER: project names, product names, tech terms, custom meeting labels
- Requires: ONNX Runtime Swift SPM package (~10 MB), model download (~130 MB)
- Effort: **~3–5 days** (SPM integration + Swift inference wrapper + label schema)
- Latency: ~20–80ms per transcript segment on M1 (acceptable for async post-call)
- Risk: ONNX Runtime for macOS ARM64 is production-grade as of v1.16+; no sandboxing issues

### Priority 3 — Medium Impact, Low Effort (v0.3)
**Wire up `Qwen3ForcedAligner` to the active ASR pipeline**
- Already implemented in mlx-audio-swift (`ForceAlignProcessor`, `Qwen3ForcedAligner.swift`)
- Model exists on HF (`mlx-community/Qwen3-ForcedAligner-0.6B-bf16`, Apache 2.0)
- Unlocks: word-level entity highlighting, click-to-seek in transcript, export with timestamps
- Effort: **~1 day** (model download + wire into transcript processing pipeline)
- Additional RAM: ~620 MB (bf16) — requires 4-bit quantization or sequential loading

### Priority 4 — Medium Impact, Medium Effort (v0.4)
**Embedding-based Topic Segmentation**
- Reuse `nomic-embed-text-v2-moe` (already in stack) + TextTiling cosine change detection
- ~50 LoC Swift pure implementation of TextTiling sliding window
- Output: `[TopicSegment]` with approximate section boundaries
- Follow with LLM post-call prompt for human-readable section labels
- Effort: **~2 days** (Swift TextTiling + LLM prompt integration)

### Priority 5 — Lower Impact, Low Risk (v0.4+)
**`NLLanguageRecognizer` → ASR language hint pipeline**
- Use Apple's built-in language recognizer on the first transcribed paragraph
- Pass detected language code to Qwen3-ASR `language` parameter for subsequent chunks
- Improves WER for non-English meetings by ~5–15%
- Effort: **~0.5 days** (3–5 lines of Swift)

---

## Decision Matrix — What Handles Each NLP Task

| NLP Task | Recommended Handler | Rationale |
|----------|--------------------|-----------| 
| PER/ORG/LOC recognition | **Apple `NLTagger`** (existing) | Zero-cost, good coverage |
| Product/project/tech term NER | **GLiNER2-base ONNX** (v0.4) | Open-label flexibility, Apache 2.0 |
| Action items | **LLM prompt (Qwen3/Qwen2.5)** | Semantic understanding required |
| Decisions | **LLM prompt (Qwen3/Qwen2.5)** | Semantic understanding required |
| Word timestamps (Qwen3-ASR) | **`Qwen3ForcedAligner`** (MLX, existing) | Already in Swift checkout |
| Word timestamps (Parakeet) | **`ParakeetAlignment`** (MLX, existing) | Built into Parakeet decoder |
| Punctuation | **ASR-native** (Qwen3/Voxtral) | LLM decoders output punctuated text |
| Punctuation (Parakeet) | **LLM reformat step** | Reuse existing Qwen model |
| Language detection | **Apple `NLLanguageRecognizer`** | OS-bundled, Swift native |
| Sentence segmentation | **Apple `NLTokenizer(.sentence)`** | OS-bundled, Swift native |
| Turn boundaries (live) | **`SmartTurn`** (MLX, existing) | Already in mlx-audio-swift |
| Topic segmentation | **Embedding + TextTiling** | Reuses nomic-embed-text-v2-moe |
| Section labeling | **LLM prompt (Qwen3/Qwen2.5)** | Post-call only |
| Emotion / tone | **LLM text analysis** | No viable small model exists |
| Speaker ID (within-session) | **Sortformer `speakerProbs`** | Already in mlx-audio-swift |
| Speaker ID (cross-session) | **Defer to v1.0+** | No MLX port of pyannote/embedding |
| Grammar correction | **ASR-native + LLM analysis** | Qwen3-ASR self-corrects |

---

## What Stays as Apple NaturalLanguage.framework

1. **`NLTagger` (nameType)** — basic PER/ORG/LOC → `EntityHighlighter.swift` (keep unchanged)
2. **`NLLanguageRecognizer`** — language detection for ASR hint (add as new utility)
3. **`NLTokenizer(.sentence)`** — sentence splitting for chunked embedding and NER passes
4. **`NLTokenizer(.word)`** — word boundary detection for entity span alignment

These are zero-cost, already-available, and cover the majority of structural NLP needs. They do not require model downloads or RAM budget.

---

## What Needs an MLX Model

1. **`Qwen3ForcedAligner-0.6B-bf16`** — word timestamps on Qwen3-ASR path (model already on HF, Swift code already in checkout, just needs wiring)
2. **`Qwen3-ASR-0.6B-4bit` / Qwen3-ASR series** — punctuation comes free from LLM decoder (already in stack)
3. **`nomic-embed-text-v2-moe`** — topic segmentation change detection (already in stack as embeddings)

No new MLX models are needed for the NLP/NER pipeline. The existing stack is sufficient once properly wired.

---

## What's Handled by LLM Prompt (Qwen2.5/Qwen3)

These tasks should be routed to the post-call LLM analysis step:

```
Action items: "Extract all action items. For each: owner, task description, deadline. JSON array."
Decisions:    "Extract all decisions made. For each: decision text, who decided, context. JSON array."
Open questions: "List unresolved questions. JSON array."
Section labels: "Identify 3–8 topic sections. For each: start time, end time, title. JSON array."
Tone analysis: "Describe the overall tone of each speaker (positive/neutral/negative/uncertain)."
Grammar cleanup: "Reformat this transcript with proper punctuation and capitalization."
```

All of these leverage the existing Qwen2.5/Qwen3 LLM already in the RAM budget. No additional model or RAM is needed.

---

## Pipeline Architecture (Post-Research)

```
Audio Input
    │
    ▼
[MossFormer2-SE] ─── Speech Enhancement (MLX, already in stack)
    │
    ▼
[Sortformer v2.1] ── Diarization (MLX, already in stack)
    │               → DiarizationSegment[]: {start, end, speaker_id}
    ▼
[Qwen3-ASR-0.6B-4bit] ── Primary ASR (MLX, punctuated output)
    │                  or [VoxtralRealtime] / [Parakeet]
    │
    ├── [Qwen3ForcedAligner] ── Word timestamps (MLX, needs wiring)
    │       → ForcedAlignResult: [{word, start_ms, end_ms}]
    │
    ├── [NLLanguageRecognizer] ── Language hint → ASR feedback loop
    │
    ├── [NLTokenizer(.sentence)] ── Sentence boundaries
    │
    ├── [NLTagger nameType] ── Basic PER/ORG/LOC (existing EntityHighlighter)
    │
    ├── [GLiNER2-base ONNX] ── Open-label NER (v0.4, ONNX Runtime)
    │       → "project", "product", "tech term", "deadline" spans
    │
    ├── [nomic-embed-text + TextTiling] ── Topic segmentation
    │       → [TopicSegment]: {start_idx, end_idx, boundary_score}
    │
    └── [Qwen3-4B LLM] ── Post-call structured extraction
            → action_items[], decisions[], open_questions[], tone{}
```

---

## Model Registry Additions Required

| Model | HF ID | Size | License | When to Download |
|-------|-------|------|---------|-----------------|
| Qwen3 ForcedAligner | `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` | ~620 MB | Apache 2.0 | On first use of word timestamps |
| GLiNER2-base (ONNX) | `fastino/gliner2-base-v1` | ~130 MB | Apache 2.0 | v0.4 feature flag |

No other new models required for full NLP/NER coverage.

---

## Evidence Log

| Claim | Source | Evidence Type |
|-------|--------|---------------|
| No mlx-community NER models | HF API `?search=ner&author=mlx-community` | Observed (0 results) |
| GLiNER has no MLX port | HF API `?search=gliner&author=mlx-community` | Observed (0 results) |
| fastino/gliner2-base-v1 is Apache 2.0 | HF API model card | Observed |
| Qwen3ForcedAligner.swift exists | `.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ForcedAligner.swift` | Observed |
| `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` live on HF | HF API; ID, downloads: 69, tags: apache-2.0 | Observed |
| ParakeetAlignment.swift exists | `.build/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/Parakeet/ParakeetAlignment.swift` | Observed |
| SmartTurn exists in MLXAudioVAD | `.build/checkouts/mlx-audio-swift/Sources/MLXAudioVAD/Models/SmartTurn/SmartTurn.swift` | Observed |
| Sortformer returns speakerProbs | `VADOutput.swift`: `DiarizationOutput.speakerProbs: MLXArray?` | Observed |
| fasttext-language-identification is CC-BY-NC-4.0 | HF API model card | Observed (non-commercial restriction) |
| pyannote/embedding is PyTorch-only | HF model tags: `pytorch`, no mlx tag | Observed |
| flan-t5-small-mlx-4bit has 4 downloads | HF API | Observed |
| fullstop-punctuation-multilingual-base 73K downloads | HF API | Observed |
| No MLX grammar/emotion/sentiment models | HF API searches | Observed (0 results) |
| Qwen3-ASR is LLM-based (punctuated output) | `Qwen3ASR.swift`: uses text decoder `generate()` | Observed |
| Parakeet is CTC/RNNT (no punctuation) | `ParakeetCTCLayers.swift`, `ParakeetRNNTLayers.swift` | Observed |
| EntityHighlighter.swift uses NLTagger | `EntityHighlighter.swift:56–89` | Observed |

---

*Research by: GitHub Copilot (EchoPanel pipeline research session, 2026-02-26)*
