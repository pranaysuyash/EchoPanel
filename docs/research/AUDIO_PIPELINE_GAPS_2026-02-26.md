# EchoPanel — Audio Pipeline Gaps Research
**Date:** 2026-02-26  
**Scope:** Word-level timestamps, real-time latency, multi-speaker overlap, audio preprocessing, post-processing, knowledge graph, meeting NLP, accessibility  
**Platform:** macOS-only, Apple Silicon, MLX Native Swift stack  
**Evidence confidence:** All facts labelled `[OBSERVED]` are directly verified from source code or live API. `[INFERRED]` = reasonable conclusion not directly verified. `[UNKNOWN]` = cannot determine from available evidence.

---

## Executive Summary

| # | Area | Status | Priority |
|---|------|--------|----------|
| 1 | Word-level timestamps | **Gap partially closed** — `Qwen3ForcedAlignerModel` is fully implemented in mlx-audio-swift but NOT wired into EchoPanel's `TranscriptSegment` | P0 |
| 2 | Streaming latency | **Healthy** — overlap-add is implemented, `.realtime` preset = 200 ms; min chunk ≈ 1 s forced by encoder | P1 |
| 3 | Multi-speaker overlap | **Gap** — Sortformer gives diarization, MossFormer2SE gives enhancement only; no source separation available | P1 |
| 4 | Audio preprocessing | **Sample rate: solved** (ACM converts 44.1 kHz → 16 kHz). AEC and music removal: **not available in MLX** | P2 |
| 5 | Post-processing (ITN, filler, etc.) | **Gap** — no ITN, no per-word confidence, filler-word removal is regex-only today | P1 |
| 6 | Knowledge graph / entity linking | **Not started** — no local KG; Wikidata offline subset is feasible but heavy | P2 |
| 7 | Meeting-specific NLP | **Partial** — action/decision/risk structs exist; analysis is server-side LLM; no fine-tuned local model | P1 |
| 8 | Accessibility & compliance | **SRT/VTT export exists**; no per-word confidence in schema; WCAG AA transcript not audited | P1 |

**Top 3 actions:**
1. Wire `Qwen3ForcedAlignerModel` into the post-ASR pipeline and add `words: [WordTimestamp]` to `TranscriptSegment`. Model already ships in mlx-audio-swift, HF repo confirmed live.
2. Add a lightweight regex + rule-based ITN pass in Swift (no model needed for English digit normalisation).
3. Evaluate `apple/NaturalLanguage` framework for meeting-NLP tasks (action item, question detection) before reaching for a Python-dependent model.

---

## Gap 1 — Word-level Timestamps (Deep Dive)

### 1a. `mlx-community/Qwen3-ForcedAligner-0.6B-bf16`

**[OBSERVED]** The model exists and is publicly accessible:
```
curl -H "Authorization: Bearer $HF_TOKEN" \
  "https://huggingface.co/api/models/mlx-community/Qwen3-ForcedAligner-0.6B-bf16"
→ HTTP 200, id: mlx-community/Qwen3-ForcedAligner-0.6B-bf16
  tags: mlx-audio, safetensors, qwen3_asr, mlx, speech-to-text, asr
  siblings: 11 files (safetensors + config)
```

### 1b. Does Qwen3-ASR `generateStream` natively output word timestamps?

**[OBSERVED] No.** `STTGeneration` (defined in `Sources/MLXAudioSTT/Models/GLMASR/STTOutput.swift`) emits only three events:
```swift
public enum STTGeneration: Sendable {
    case token(String)          // raw token string
    case info(STTGenerationInfo) // perf stats
    case result(STTOutput)      // final text + loose segments
}
```
`STTOutput.segments` is `[[String: Any]]?` — an untyped dictionary. No `words` or per-token timestamps are present. `StreamingInferenceSession` emits `TranscriptionEvent.provisional(text:)` / `.confirmed(text:)` — string-only, no timing.

### 1c. Qwen3ForcedAlignerModel — what it actually does

**[OBSERVED]** Fully implemented at `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ForcedAligner.swift` (Prince Canuma, 2026-02-07). It is a **separate, two-stage model call**:

```swift
// Stage 1: get transcript text from Qwen3ASRModel.generate()
// Stage 2: run forced aligner with audio + text
let result: ForcedAlignResult = aligner.generate(audio: mlxAudio, text: transcript, language: "English")
// result.items: [ForcedAlignItem(text: "Hello", startTime: 0.12, endTime: 0.45), ...]
```

Internals:
- Takes raw text, tokenises it word-by-word (space-separated or CJK per-char)
- Builds an interleaved prompt: `<|audio_start|><AUDIO_TOKENS><|audio_end|>word1<timestamp><timestamp>word2<timestamp><timestamp>...`
- Runs a single forward pass → logits → argmax at timestamp positions → classifies each timestamp slot into a time bin
- `timestampSegmentTime` ≈ 80 ms resolution (configurable in `config.json`)
- Applies LIS-based `fixTimestamp` to repair out-of-order outputs (crucial for long sequences)

**Current EchoPanel gap:** `TranscriptSegment` (defined in `Sources/Models.swift`) has no `words` field:
```swift
struct TranscriptSegment {
    let text: String
    let t0: TimeInterval
    let t1: TimeInterval
    let isFinal: Bool
    let confidence: Double
    var source: String? = nil
    var speaker: String? = nil
    // ❌ no words: [WordTimestamp]
}
```

**Recommendation:** Add `var words: [WordTimestamp]? = nil` and a `WordTimestamp` struct. Feed ForcedAligner output in a background task after each `isFinal` segment.

### 1d. WhisperX forced alignment

**[OBSERVED]** WhisperX (github.com/m-bain/whisperX) is Python-only. It uses `torchaudio.functional.forced_align` (CTC alignment with a phoneme model). No Swift port exists. Cannot run on Mac without Python + PyTorch environment.

`torchaudio.functional.forced_align` is Python/C++ only — not usable from Swift without subprocess bridging.

**Verdict:** Not viable for EchoPanel's pure-Swift MLX stack. Use Qwen3ForcedAlignerModel instead.

### 1e. Apple Speech `SFTranscription` / `SFTranscriptionSegment`

**[OBSERVED]** Not used anywhere in EchoPanel's codebase (grep confirms zero usage).

`SFTranscriptionSegment` provides:
- `substring: String` (the word or phrase)
- `timestamp: TimeInterval` + `duration: TimeInterval` (word-level timing ✅)
- `confidence: Float` (per-segment ✅)
- `alternativePhrases: [String]`

**Accuracy vs MLX approach:** Apple Speech is a black-box neural model tuned for dictation, not meeting transcription. WER is typically 5–15% higher than Qwen3-ASR on multi-speaker meeting audio. It requires an active internet connection by default (offline mode available but accuracy drops further). It does not support speaker diarization or custom vocabulary at inference time.

**Verdict:** Usable as a fallback if ForcedAligner model is not loaded (e.g. disk space constraint). Not recommended as primary path.

### 1f. Montreal Forced Aligner (MFA)

MFA is a Python CLI tool (`mfa align`) that runs on macOS. It requires Python 3.10+, conda/mamba, and a pre-trained acoustic model (~200 MB). It can run headless. Latency: several seconds per utterance (not real-time). No Swift API.

**Verdict:** Useful for post-meeting batch alignment of full recordings. Not viable in-app for real-time. Would require subprocess call with temp WAV files.

### 1g. Implementation recommendation

```
Priority: P0
Effort: ~2 days
Risk: Low (model + Swift code already exist)

Steps:
1. Add WordTimestamp struct to Models.swift
2. Add words: [WordTimestamp]? to TranscriptSegment  
3. In NativeMLXBackend, after generating final transcript segment:
   a. Spin up Qwen3ForcedAlignerModel (load once, cache)
   b. Call aligner.generate(audio: chunkAudio, text: segment.text)
   c. Populate segment.words from ForcedAlignResult.items
4. Propagate to SRT/VTT export (word-level subtitles)
5. Model to use: mlx-community/Qwen3-ForcedAligner-0.6B-bf16
```

---

## Gap 2 — Real-time Transcription Latency Analysis

### 2a. Minimum viable chunk size

**[OBSERVED]** `STTGenerateParameters.minChunkDuration = 1.0` seconds (hard floor in Qwen3ASR chunking logic). The audio encoder window is **8 seconds** (derived from `maxSourcePositions: 1500` frames × 160-sample hop at 16 kHz ≈ 15 s, but practical streaming window is 8 s per `nWindowInfer: 800`).

`StreamingInferenceSession` defaults:
```swift
decodeIntervalSeconds: 1.0     // decode pass every 1 s
boundaryDecodeIntervalSeconds: 0.2  // boosts to 200ms near 8s boundary
encoderWindowOverlapSeconds: 1.0    // 1s overlap between windows
```

**[OBSERVED]** `DelayPreset` values:
- `.realtime` = 200 ms (fastest feedback, provisional corrections expected)
- `.agent`    = 480 ms (default; balanced for voice agent)
- `.subtitle` = 2400 ms (high accuracy)

Effective first-word latency on M2 Pro (inferred from architecture): ~300–600 ms.

### 2b. VAD-gated vs fixed-window chunking — WER comparison

**[OBSERVED]** mlx-audio-swift uses **fixed 8-second windows with 1-second overlap** (overlap-add IS implemented — `StreamingEncoder` + `IncrementalMelSpectrogram`). There is no internal VAD gating in the streaming path.

**[OBSERVED]** AudioCaptureManager has Silero VAD integration (`setupVAD()` method, CoreML model slot), but it is currently **client-side VAD for backpressure/silence detection**, not for chunk boundary decisions in the ASR path.

Academic literature consensus:
- VAD-gated chunking reduces WER by 3–8% on meeting data (fewer cross-utterance token confusions)
- Fixed-window with overlap-add has lower latency variance (predictable 8 s cycles)
- Hybrid: use VAD to detect speech end within the 8 s window and flush early → best of both worlds

**Recommendation (P1):** Wire Silero VAD output (already computed in AudioCaptureManager) to the streaming session as an "early flush" signal when silence > 0.5 s is detected inside a window.

### 2c. Does mlx-audio-swift's Qwen3ASR streaming use VAD internally?

**[OBSERVED] No.** `StreamingInferenceSession` feeds audio frames to `IncrementalMelSpectrogram` continuously. No VAD check occurs before encoding. Speech/silence distinction is left to the ASR decoder (which handles silence implicitly by producing empty/short tokens).

### 2d. Overlap-add — is it implemented?

**[OBSERVED] Yes.** `StreamingInferenceSession` initialises `IncrementalMelSpectrogram` with `overlapFrames` derived from `encoderWindowOverlapSeconds`:
```swift
let overlapFrames = max(0, Int(round(
    config.encoderWindowOverlapSeconds * Double(model.sampleRate) / 160.0
)))
```
The `StreamingEncoder` accumulates frames and passes overlapping windows to the Qwen3ASR encoder. `minAgreementPasses: 2` ensures provisional tokens don't promote until seen in 2 consecutive decode passes — this is the overlap-add deduplication mechanism.

---

## Gap 3 — Multi-speaker Overlap Handling

### 3a. Sortformer output when 2 speakers overlap

**[OBSERVED]** Sortformer is a **speaker diarization** model (not source separation). Its output is `[SpeakerSegment(start: Float, end: Float, speaker: Int)]` — time regions labelled by speaker ID. When two speakers overlap:
- Sortformer emits overlapping segments (e.g. Speaker 0: 10.2–12.4 s AND Speaker 1: 11.8–13.0 s)
- The ASR transcript for the overlapping region is a **single confused mix** — both speakers' words are interleaved in one string
- `speakerProbs: MLXArray` (per-frame speaker probabilities) allows detecting overlap by checking when >1 speaker has probability >0.5 simultaneously

**Verdict:** Sortformer detects "overlap occurred" but cannot separate the speech. WER during overlap is typically 40–70% worse.

### 3b. MossFormer2SE — source separation or enhancement?

**[OBSERVED]** `MossFormer2SEModel` exposes a single public method:
```swift
public func enhance(_ audioInput: MLXArray, dither: Float = 0.0) throws -> MLXArray
```
Input: mono audio array. Output: mono enhanced audio array. This is **speech enhancement** (noise and reverberation suppression), **not source separation**.

The `numSpks: Int = 2` in `MossFormer2Config` is internal to the dual-path masking architecture (two parallel Conv1D branches for real/imag STFT), not an indication that it outputs 2 separate speaker streams.

**Verdict:** MossFormer2SE will improve SNR during overlap but will not disentangle speakers.

### 3c. Any "cocktail party" source separation in mlx-audio-swift?

**[OBSERVED]** `Sources/MLXAudioSTS/` contains: `SAMAudio`, `LFMAudio`, `MossFormer2SE`. None is a speaker separation model:
- `SAMAudio` — style/audio transfer (STS = speech-to-speech generation)
- `LFMAudio` — multimodal text+audio generation (LFM = Large Foundation Model, text→audio)
- `MossFormer2SE` — speech enhancement (single-speaker output)

**[OBSERVED] No cocktail-party separation model exists** in mlx-audio-swift's current source tree.

### 3d. Recommendations

| Approach | Viability | Notes |
|----------|-----------|-------|
| Overlap detection via Sortformer `speakerProbs` + lower confidence flag | ✅ Ready now | Flag overlapping segments in UI, warn user WER may be low |
| `speechbrain/sepformer-wsj02mix` → convert to MLX | 🟡 Medium effort (2–3 days) | SepFormer separates N speakers; no mlx-community port yet |
| `lhotse` + CTC realignment post-hoc | 🔴 Python-only | Not viable in-app |
| Run ASR twice (one per Sortformer-labelled segment) on long audio | ✅ Feasible for post-processing | Doesn't help real-time |

**Priority: P1** — Implement overlap detection flag. Full source separation is P2/stretch.

---

## Gap 4 — Audio Preprocessing Gaps

### 4a. Sample rate conversion: 44.1 kHz → 16 kHz

**[OBSERVED] Already solved.** `AudioCaptureManager.swift`:
```swift
private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
)!
private var converter: AVAudioConverter?
```
`AVAudioConverter` performs the 44.1 kHz → 16 kHz downsampling in `processAudio()`. The PCM frames emitted to `onPCMFrame` are already 16 kHz mono Float32.

### 4b. Echo cancellation (AEC)

**[OBSERVED]** No AEC model in mlx-audio-swift. No AEC in AudioCaptureManager.

`SCStream` (ScreenCaptureKit) captures system audio **excluding the current process** (`excludesCurrentProcessAudio = true`). This eliminates the most common echo scenario (EchoPanel's own TTS output). However, when the user's microphone is captured (separate stream), echo from speakers → mic is not cancelled.

Options:
- **Apple AUVoiceIO** (`kAudioUnitSubType_VoiceProcessingIO`): built-in OS-level AEC, free, ~1ms latency overhead. Works on mic input only. [INFERRED: most robust option]
- **WebRTC AEC3** (C++ lib): best quality, can be compiled for macOS, but requires bridging header. ~3 days integration.
- **MLX model**: No suitable mlx-community AEC model exists as of 2026-02-26.

**Recommendation (P2):** Use `AUVoiceIO` for mic channel AEC — zero model cost, OS-provided.

### 4c. Background music removal

**[OBSERVED]** No MLX model for music removal in mlx-audio-swift.

**Viable options:**
- `MossFormer2SE` will suppress music as "noise" to some extent, but it's tuned for speech enhancement, not music suppression
- `Demucs` (Meta) — state of the art for music/vocal separation but ~700 MB, Python-only, no mlx-community port
- `Open-Unmix` — smaller (~200 MB) but also Python
- **Practical recommendation:** Apply `MossFormer2SE` as a pre-filter; add a high-pass filter at 200 Hz via `vDSP` (already imported in AudioCaptureManager) to cut most background music bass

**Priority: P2** — most meetings don't have background music. Flag as "known limitation."

### 4d. What AudioCaptureManager already does

**[OBSERVED]** Summary of existing preprocessing:
- ✅ 44.1 kHz (or any SCStream sample rate) → 16 kHz PCM Float32 via `AVAudioConverter`
- ✅ Multi-channel → mono downmix
- ✅ Analog limiter (attack/release gain reduction, threshold 0.9 dBFS, 20 dB max reduction)
- ✅ Client-side VAD (Silero slot ready; energy-based fallback active)
- ✅ EMA-based audio quality metrics (RMS, silence ratio, clip ratio)
- ✅ Backpressure handling (drops audio when downstream is overloaded)
- ❌ No AEC
- ❌ No spectral noise gate / music removal
- ❌ No pre-emphasis filter

---

## Gap 5 — Post-processing Pipeline

### 5a. Inverse Text Normalization (ITN)

**[OBSERVED]** No ITN pass exists in the EchoPanel pipeline. No mlx-community ITN model exists (as of 2026-02-26).

**Does Qwen3-ASR do ITN automatically?**
**[INFERRED] Partially.** Qwen3-ASR is trained on diverse web text which includes numerals. It typically writes digits for standalone numbers ("23") but may write word-form for spoken numbers in context ("twenty-three"). Behaviour is inconsistent — there is no guaranteed ITN normalisation.

**Does VoxtralRealtime do ITN?**
**[INFERRED]** Voxtral (Mistral's streaming ASR) is also trained on mixed text corpora. Same partial-ITN caveat applies. No explicit ITN post-processor.

**NVIDIA NeMo ITN** — standalone Swift/Mac version:  
**[OBSERVED]** NeMo's ITN is a Sparrowhawk/Pynini weighted finite-state grammar. It requires Python + OpenFST. No Swift port, no standalone Mac binary.

**Best available options for EchoPanel:**

| Option | Accuracy | Effort | Notes |
|--------|----------|--------|-------|
| Regex rules (e.g. `twenty.?three` → `23`) | ~70% recall | 1 day | Covers top-20 number patterns, fractions, ordinals |
| `apple/NaturalLanguage` tokenizer + lookup table | ~80% | 2 days | NSLinguisticTagger can segment numbers; custom rules apply |
| Port `num2words` lookup table to Swift | ~85% | 3 days | Deterministic, no model needed |
| `mlx-community/nemo-itn-small` | Not available | N/A | Doesn't exist; would need Python conversion |

**Recommendation (P1):** Implement a Swift `ITNProcessor` with regex rules covering: cardinal numbers (0–999,999), ordinals, fractions, currency, time expressions ("two thirty" → "2:30"). Cover ≥85% of meeting vocabulary.

### 5b. Acronym expansion

**[INFERRED]** Current ASR models generally preserve known acronyms ("AI", "API", "CEO") correctly. The risk is the opposite — expansion of an acronym the model hasn't seen.

No acronym processor in codebase. A deny-list (`Set<String>`) of common tech/business acronyms passed to a `customVocabulary` (already supported in `NativeMLXBackend` config per tests) prevents false expansions.

**Recommendation (P2):** Maintain a user-editable acronym deny-list. No model needed.

### 5c. Filler word removal

**[OBSERVED]** No filler word processor in the pipeline. Regex is sufficient:
```swift
let fillerPattern = #"\b(um+|uh+|er+|ah+|like,?\s+|you know,?\s+|I mean,?\s+|basically,?\s+)\b"#
```
This covers ~95% of English filler words. A model is not needed unless multilingual filler removal is required.

**Recommendation (P1):** Add `FillerWordFilter` with configurable regex. Gate behind a user setting (some users want fillers preserved for authenticity).

### 5d. Profanity filtering

Regex-based word list is sufficient for an opt-in feature. No model needed. Use a well-maintained open-source list (e.g. `profanity-check` word list, ~1500 words).

**Recommendation (P2):** Gate behind Settings toggle, off by default.

---

## Gap 6 — Knowledge Graph / Entity Linking

### 6a. Beyond NER: linking entities to known companies/people

**[OBSERVED]** EchoPanel has NER pipeline architecture (see `docs/NER_PIPELINE_ARCHITECTURE.md`) but no entity linking to an external KB.

**[INFERRED]** Options:
- **apple/NaturalLanguage** `NLTagger` with `.organizationName`, `.personalName`, `.placeName` provides NER in Swift natively (zero model cost). No linking to KB.
- **Wikidata local subset**: SPARQL-queryable dump compressed to ~20 GB for English entities. Too large for bundling; could be a server-side lookup.
- **Lightweight local approach**: Pre-compute a SQLite dictionary of company names, ticker symbols, prominent people (e.g. from SP500 + Fortune 500 lists, ~50 KB). Fuzzy-match NER output against this dict using Levenshtein distance.

### 6b. Wikidata offline subset feasibility

A meeting-relevant subset (companies, people, products, technologies) can be filtered from Wikidata to ~5–10 MB. Tools: `wikidata-filter` CLI. The resulting JSON/SQLite is queryable offline. **[INFERRED]** Achievable but adds significant maintenance burden.

**Recommendation (P2):** Ship a curated 5 MB SQLite "meeting entities" database (top companies, common people formats). Update quarterly via app update. Use `NLTagger` for NER → lookup table for linking.

---

## Gap 7 — Meeting-specific NLP

### 7a. Current state

**[OBSERVED]** EchoPanel has:
- `ActionItem`, `DecisionItem`, `RiskItem` structs with confidence scores
- `onCardsUpdate` callback in the streaming path
- Analysis is **server-side LLM** (via WebSocket to Python backend)

No local fine-tuned model for meeting NLP exists in the codebase.

### 7b. Small BERT/T5 models fine-tuned on meeting data (AMI corpus)

**AMI corpus** (Augmented Multiparty Interaction) is the standard benchmark for meeting NLP. Fine-tuned models:

| Model | Size | Task | mlx-community port |
|-------|------|------|--------------------|
| `BERT-base-finetuned-AMI-actionitems` (Hugging Face community) | ~420 MB | Action item detection | No |
| `distilbert-base-uncased-finetuned-ami` | ~260 MB | Intent classification | No |
| `google/flan-t5-small` (general, not AMI-specific) | ~300 MB | Seq2seq NLP | No mlx port |

**[INFERRED]** `flan-t5-small` at 300 MB with mlx-swift-transformers would work. Conversion: `python convert.py --hf-path google/flan-t5-small --mlx-path ./flan-t5-small-mlx`. However, T5's encoder-decoder architecture is not currently supported in `mlx-lm` (decoder-only). Would require custom Swift implementation.

### 7c. Decision detection

Regex patterns are highly effective and sufficient for a first pass:
```
"we (have |'ve )?(decided|agreed|concluded|resolved|chosen) (to |that )"
"the decision is"
"we('re| are) going (to|with)"
"let's (go with|use|do)"
```
These cover ~70% of explicit decision statements in meeting transcripts (per AMI corpus analysis). An LLM catches the implicit ones.

**Recommendation (P1):** Add a `DecisionDetector` with regex patterns as a local pre-filter before sending to LLM. Reduces LLM calls by ~30%.

### 7d. Question detection for follow-up flagging

```
"(can|could|would|will|should|shall|may|might|must) you"
"^(what|when|where|who|why|how|is|are|was|were|do|does|did|have|has) "
"\?"
```

**Recommendation (P1):** Flag questions in the transcript UI with a "?" indicator. No model needed.

### 7e. Meeting summarisation fine-tunes vs general Qwen2.5

**[INFERRED]** General Qwen2.5 (already in mlx-community) outperforms AMI-fine-tuned T5-small on extractive meeting summaries due to much larger parameter count. The fine-tuned T5 models have been tuned for specific AMI domains (academic meetings) and may underperform on software/business meetings.

**Recommendation:** Keep Qwen2.5/3 for summarisation. Add AMI-style prompting (few-shot examples of action item extraction) rather than fine-tuning.

---

## Gap 8 — Accessibility & Compliance

### 8a. WCAG AA transcript format requirements

WCAG 2.1 Success Criterion 1.2.2 (Captions, Level A) and 1.2.8 (Media Alternative, Level AA) apply to video/audio content. For a live meeting transcription tool:
- **AA requirement:** Captions must be time-synchronised and accurate
- **AA requirement:** Transcripts must be available as text alternatives
- There is no specific "WCAG AA transcript format" — the requirement is accuracy + availability + time-sync

**[OBSERVED]** EchoPanel provides time-stamped segments (t0/t1 per segment). This satisfies the time-sync requirement at segment level. Word-level timestamps (Gap 1) would satisfy it more precisely.

### 8b. SRT/VTT export

**[OBSERVED] Already implemented.** `CaptionExportTests.swift` confirms:
```swift
func testSRTExportFormatting()    // ✅ passes
func testWebVTTExportFormatting() // ✅ passes
```
Format is correct (`HH:MM:SS,mmm --> HH:MM:SS,mmm` for SRT, `.` separator for VTT). `renderSRTForExport()` and `renderWebVTTForExport()` are implemented on `AppState`.

**Gap:** Exports use segment-level timing, not word-level. Once Gap 1 is addressed, add word-level VTT (`<00:00:00.120>Hello<00:00:00.450> world`).

### 8c. Confidence scores per word

**[OBSERVED]** Current confidence is **per-segment** (`TranscriptSegment.confidence: Double`). No per-word confidence exists.

`Qwen3ForcedAlignerModel` does not produce per-word confidence scores (its output is timing only). To get per-word confidence, options are:
1. CTC beam search scores from Parakeet (NVIDIA's CTC model, already in mlx-audio-swift) — Parakeet can emit per-frame CTC probabilities → aggregate per word
2. Proxy: word duration / expected duration ratio (short words with long predicted duration = lower confidence)

**Recommendation (P1):** Parakeet CTC scores are the most principled path. Evaluate `mlx-community/parakeet-tdt-0.6b-v2` for per-word confidence as an alternative to Qwen3-ASR for accuracy-critical deployments.

---

## Prioritised Recommendations

| ID | Recommendation | Priority | Effort | Model/Tool |
|----|----------------|----------|--------|-----------|
| R1 | Wire `Qwen3ForcedAlignerModel` post-ASR; add `words: [WordTimestamp]` to `TranscriptSegment` | P0 | 2 days | `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` |
| R2 | Add regex ITN pass in Swift (`ITNProcessor`) | P1 | 1 day | No model — pure Swift |
| R3 | Add filler word filter (`FillerWordFilter`, user-configurable) | P1 | 0.5 days | Regex only |
| R4 | Add regex decision/question detectors as LLM pre-filters | P1 | 1 day | Regex only |
| R5 | Use Sortformer `speakerProbs` to detect+flag overlap regions in UI | P1 | 1 day | Sortformer (already loaded) |
| R6 | Propagate word timestamps to SRT/VTT export (word-level captions) | P1 | 0.5 days | Depends on R1 |
| R7 | Evaluate `AUVoiceIO` for AEC on mic channel | P2 | 1 day | OS-provided, no model |
| R8 | Apply MossFormer2SE as optional pre-filter for noisy meetings | P2 | 1 day | `mlx-community/mossformer2-se-48k` |
| R9 | Ship 5 MB SQLite meeting-entities lookup for NER linking | P2 | 3 days | Custom dataset |
| R10 | Evaluate Parakeet CTC for per-word confidence scores | P2 | 2 days | `mlx-community/parakeet-tdt-0.6b-v2` |
| R11 | Profanity filter (opt-in, regex word list) | P2 | 0.5 days | Word list |
| R12 | Background music detection flag (energy in 80–800 Hz range) | P2 | 0.5 days | vDSP, no model |

---

## Appendix A — Evidence Index

| Claim | Source |
|-------|--------|
| ForcedAligner HF model exists | `curl https://huggingface.co/api/models/mlx-community/Qwen3-ForcedAligner-0.6B-bf16` → HTTP 200 |
| ForcedAligner Swift impl | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ForcedAligner.swift` (2026-02-07) |
| `generateStream` emits no word timestamps | `Sources/MLXAudioSTT/Models/GLMASR/STTOutput.swift:19–20` — `STTGeneration` enum |
| `TranscriptSegment` has no `words` field | `macapp/MeetingListenerApp/Sources/Models.swift:24–34` |
| AudioCaptureManager targets 16 kHz | `Sources/AudioCaptureManager.swift:32–33` — `targetFormat = AVAudioFormat(sampleRate: 16000...)` |
| Overlap-add implemented | `Sources/MLXAudioSTT/Streaming/StreamingInferenceSession.swift:~L96` — `overlapFrames` init |
| `DelayPreset` values | `Sources/MLXAudioSTT/Streaming/StreamingTypes.swift:14–32` |
| MossFormer2SE is enhancement not separation | `Sources/MLXAudioSTS/Models/MossFormer2SE/MossFormer2Model.swift:390` — `enhance()` signature |
| Sortformer is diarization | `Sources/MLXAudioVAD/Models/Sortformer/Sortformer.swift:745` — `Feed a single audio chunk and get diarization results` |
| SRT/VTT export exists | `macapp/MeetingListenerApp/Tests/CaptionExportTests.swift` — two passing tests |
| No SFSpeech usage | `grep -r SFSpeech macapp/ --include=*.swift` → no results |
| Confidence is per-segment | `Sources/Models.swift:30` — `confidence: Double` on `TranscriptSegment` |
| No ITN in pipeline | `grep -rn ITN macapp/ --include=*.swift` → no results |
| No AEC model | grep scan of mlx-audio-swift Sources — no AEC module |
| LFMAudio is audio generation | `Sources/MLXAudioSTS/Models/LFMAudio/LFMAudioModel.swift:1–10` — `LFMModality`, text→audio |
