> **⚠️ SUPERSEDED (2026-02-16):** Gap analysis superseded by `SENIOR_STAKEHOLDER_RED_TEAM_REVIEW_20260214.md`.
> Resolved gaps: GAP 9 (.app bundle built), ASR providers expanded (4 providers), capability detection added.
> Known v0.2 limitations tracked in red-team review: keyword-only NLP (GAP 1), VAD off by default (GAP 2),
> code signing not done (GAP 9 partial). Moved to archive.

# EchoPanel — Gap Analysis (Cross-Referenced with Model-Lab + Online Research)

**Date**: 2026-02-06
**Sources**: EchoPanel repo, `speech_experiments/model-lab` repo, `docs/ASR_MODEL_RESEARCH_2026-02.md` (60+ model audit)
**Evidence labels**: Observed (O) / Inferred (I) / Unknown (U)

---

## Summary of Gaps

EchoPanel has a functional v0.2 pipeline (capture → stream → ASR → NLP → UI → export) but has **12 material gaps** across 5 categories that separate it from a competitive product. The gaps are ordered by impact on user value.

---

## GAP 1: NLP Quality — Keyword Matching vs LLM-Powered Analysis

**Severity**: 🔴 CRITICAL
**Evidence level**: Observed

**Current state** (`server/services/analysis_stream.py` L113–151):
- Action detection: simple keyword list (`"i will"`, `"we will"`, `"todo"`, `"send"`, `"schedule"`)
- Decision detection: keyword list (`"decide"`, `"agreed"`, `"ship"`, `"launch"`)
- Risk detection: keyword list (`"risk"`, `"blocker"`, `"concern"`, `"delay"`)
- Entity extraction: regex for capitalized tokens + hardcoded name list (`analysis_stream.py` L222–227)
- Rolling summary: extractive (just re-extracts cards + entities), no generative summary

**What competitors do** (Inferred):
- Granola, Otter, Fireflies use GPT-4/Claude to generate structured meeting notes
- LLM-powered extraction catches implicit actions ("I guess I should probably reach out to them" → Action: Reach out to [person])
- Competitors produce publication-quality summaries, not keyword-matched fragments

**What model-lab proves**:
- `model-lab/harness/nlp.py` and `model-lab/harness/llm_provider.py` exist — model-lab has LLM integration infrastructure already built
- `model-lab/EVALUATION_MATRIX.md` L27–34: GPT-4o Mini scored 8.8/10, Llama 4 Scout 8.4/10 for analysis tasks
- `model-lab/docs/audit/COMPANION_VISION.md` already envisions LLM integration for "chat with meeting"

**Gap closure plan** (decided 2026-02-06 — see `docs/DECISIONS.md` for full rationale):

Recommended approach: **Hybrid (Option D+B)** — keyword extraction stays as default, LLM is opt-in via user's own API key.

| Option | Approach | Verdict |
|--------|----------|---------|
| A: Ollama (local) | User installs Ollama + 2-4GB model | Rejected for now — 6-8GB RAM total (Whisper + LLM) exceeds 8GB M1 Air capacity |
| B: User's cloud API key | User enters OpenAI/Anthropic key in Settings | **Selected** — no infra needed, ~$0.01-0.05/meeting, audio never leaves Mac |
| C: Our hosted API | We run the LLM, user connects to us | Rejected — requires servers, auth, billing, GDPR, on-call |
| D: Hybrid default | Keyword fallback + optional LLM | **Selected** — preserves "works offline" |

Key insight: **The LLM never touches audio.** It only processes transcript text that ASR already produced locally. Privacy story: "Audio never leaves your Mac. Transcript text can optionally be sent to your own LLM provider for enhanced analysis."

Implementation:
1. Add `ECHOPANEL_LLM_PROVIDER` setting (`none` | `openai` | `ollama`) — default `none`
2. Add `ECHOPANEL_OPENAI_API_KEY` stored in macOS Keychain (not env var)
3. `analysis_stream.py`: add LLM path alongside keyword path for `extract_cards()`, `extract_entities()`, `generate_rolling_summary()`
4. Port `model-lab/harness/llm_provider.py` abstraction
5. No changes to ASR pipeline, WebSocket protocol, audio capture, deployment, pricing, user accounts, or licensing

**Impact**: This is the #1 gap between "toy" and "product." Without LLM analysis, the structured artifacts (actions/decisions/risks) are unreliable and users will dismiss them.

---

## GAP 2: No Voice Activity Detection (VAD)

**Severity**: 🔴 CRITICAL
**Evidence level**: Observed

**Current state**:
- `provider_faster_whisper.py` L137: `vad_filter=self.config.vad_enabled` — VAD is **off by default** (`asr_stream.py` L30: `vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "0") == "1"`)
- No standalone VAD — relies entirely on faster-whisper's built-in VAD filter (crude, batch-only)
- No silence detection at the ASR level — the silence banner is purely client-side (`CHANGELOG.md` L30: "Silence Detection: Banner after 10s of no audio")

**What model-lab has**:
- `model-lab/models/silero_vad/` — Silero VAD model folder exists in model-lab
- `model-lab/harness/metrics_vad.py` — VAD evaluation metrics exist
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L875: Silero VAD is Tier 1 ("Immediate implementation")
- Silero VAD: <1MB model, 0.5ms inference, MIT license, works on CPU — ideal for EchoPanel

**Why this matters**:
- Without VAD, EchoPanel sends **silence** to the ASR model, wasting CPU/GPU cycles and producing hallucination-prone output
- Whisper is notorious for hallucinating text during silence ("Thank you for watching", repeated phrases)
- VAD enables: skip silent chunks, detect speech boundaries, improve chunking, reduce latency
- Every production ASR pipeline uses VAD (Deepgram, AssemblyAI, Otter — all confirm this)

**Gap closure plan**:
1. **Add Silero VAD** as a pre-filter in `provider_faster_whisper.py` before `model.transcribe()`
2. Port `model-lab/models/silero_vad/` configuration and integrate
3. Add VAD-based chunking: only send speech segments to ASR, skip silence
4. Emit `silence_detected` / `speech_resumed` events to the client for UI feedback
5. Estimated effort: 4–8 hours

---

## GAP 3: No True Streaming ASR (Batch-Chunked Only)

**Severity**: 🟡 HIGH
**Evidence level**: Observed

**Current state** (`provider_faster_whisper.py` L93):
- Audio is buffered in 4-second chunks (`chunk_seconds = 4`)
- Each chunk is transcribed as a **batch** via `model.transcribe(audio)`
- No true streaming / partial results — only "finals" emitted (`L161: is_final=True`)
- Minimum latency = chunk_seconds (4s) + inference time (~0.5–2s on M-series) = **4.5–6s**

**What's possible (from model research)**:
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L194: **Voxtral-Mini-4B-Realtime** — sub-200ms streaming, Apache 2.0
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L162: **whisper.cpp** — real-time microphone streaming, Metal/CoreML acceleration
- Distil-Whisper: smaller models that enable faster chunking (2s chunks with acceptable quality)
- `model-lab/STREAMING_ASR_PORT_NOTES.md`: streaming pipeline already ported to model-lab for benchmarking

**What model-lab proves**:
- `model-lab/harness/streaming_asr/stream.py` — streaming pipeline exists and is benchmarked
- `model-lab/harness/streaming_asr/provider_faster_whisper.py` — faster-whisper streaming provider tested
- `model-lab/PERFORMANCE_RESULTS.md` L182+: streaming benchmark infrastructure exists with per-chunk latency metrics

**Gap closure plan**:
1. **Short-term**: Reduce chunk size to 2s (trade accuracy for latency) — env var already supports this
2. **Medium-term**: Add Voxtral-Mini-4B-Realtime as a second ASR provider (sub-200ms, Apache 2.0)
3. **Long-term**: Integrate whisper.cpp for native Metal acceleration on Apple Silicon
4. **Port from model-lab**: Use `harness/streaming_asr/` benchmark infrastructure to compare chunk sizes and providers

---

## GAP 4: No Audio Pre-Processing Pipeline

**Severity**: 🟡 HIGH
**Evidence level**: Observed

**Current state**:
- Raw PCM16 is sent directly to the ASR model — no preprocessing
- No noise reduction, normalization, or enhancement
- Audio quality indicator exists client-side (RMS, clipping) but is informational only
- System audio captured via ScreenCaptureKit may include notification sounds, music, typing

**What model-lab has**:
- `model-lab/harness/preprocess_ops.py` — preprocessing operations module exists
- `model-lab/harness/audio_io.py` — consistent audio loading/preprocessing
- `model-lab/COMPREHENSIVE_AUDIO_MODEL_ROADMAP_2026.md` L14–21: SEGAN speech enhancement model planned as Phase 1
- `model-lab/ADVANCED_FEATURES_ROADMAP.md` L29–34: word correction and post-processing planned

**What the research says**:
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L841–843: DeepFilterNet2 (MIT, CPU-feasible), Demucs (MIT, 4–8GB VRAM), RNNoise (BSD, 60K params)
- DeepFilterNet2 is the best candidate: MIT license, CPU-feasible, designed for speech enhancement in real-time
- RNNoise is the lightest: 60K parameters, minimal CPU, BSD license — can run as a pre-filter with zero performance impact

**Gap closure plan**:
1. **Immediate**: Add RNNoise or basic spectral gating as a pre-filter (almost zero CPU cost)
2. **Medium-term**: Add DeepFilterNet2 for real-time noise suppression
3. **Long-term**: Add Demucs for source separation (isolate speech from music/background)

---

## GAP 5: No Real-Time Diarization

**Severity**: 🟡 HIGH
**Evidence level**: Observed

**Current state**:
- Diarization runs **only at session end** (batch mode, `ws_live_listener.py` L314–316 — currently commented out)
- Requires HuggingFace token for pyannote model (`docs/STATUS_AND_ROADMAP.md` L99)
- "Pseudo-diarization" labels "You" vs "System" based on audio source tag — not real speaker identification
- Diarization code exists (`server/services/diarization.py`) but is disabled

**What model-lab has**:
- `model-lab/models/pyannote_diarization/` — pyannote model folder
- `model-lab/models/heuristic_diarization/` — heuristic diarization model folder
- `model-lab/harness/diarization.py` — diarization harness module
- `model-lab/harness/metrics_diarization.py` — diarization metrics (DER, etc.)
- `model-lab/ADVANCED_FEATURES_ROADMAP.md` L6–22: named speaker recognition roadmap

**What the research says**:
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L876: pyannote.audio is Tier 1, MIT license
- WhisperX combines Whisper + pyannote for "who said what when" — EchoPanel should replicate this pattern
- Streaming diarization is hard (pyannote is batch) — but pseudo-diarization from multi-source (system vs mic) is a reasonable intermediate step

**Gap closure plan**:
1. **Immediate**: Re-enable batch diarization at session end (uncomment the code)
2. **Short-term**: Improve pseudo-diarization: label mic source as "You," system as "Others"
3. **Medium-term**: Add pyannote streaming chunked diarization (run on rolling 60s windows)
4. **Port from model-lab**: Use `harness/diarization.py` + `metrics_diarization.py` for evaluation
5. **Long-term**: Named speaker recognition with voice enrollment (model-lab roadmap)

---

## GAP 6: Single ASR Provider (No Fallback or Selection)

**Severity**: 🟡 MEDIUM
**Evidence level**: Observed

**Current state**:
- Only `faster_whisper` provider registered (`provider_faster_whisper.py` L222)
- Provider abstraction exists (`asr_providers.py` — clean interface) but only one implementation
- `docs/STATUS_AND_ROADMAP.md` L49: "Cloud ASR provider: Implement OpenAI Whisper API provider (4h)" — planned but not implemented
- Default model is `base` — the smallest useful Whisper model (10% WER)

**What model-lab has tested**:
- `model-lab/PERFORMANCE_RESULTS.md`: Whisper (28.5% WER), Faster-Whisper (24.1% WER), LFM-2.5-Audio (137.8% — not viable), SeamlessM4T (97.8% — not viable)
- `model-lab/EVALUATION_MATRIX.md` L41–63: Whisper.cpp scored 9.0/10, Distil-Whisper 8.8/10 — both viable alternatives
- `model-lab/models/distil_whisper/`, `model-lab/models/whisper_cpp/` — model folders exist (experimental status)

**What the research recommends**:
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L893–911: Phase 1 = faster-whisper base.en (done), Phase 2 = Voxtral-Mini-4B-Realtime + faster-whisper large-v3-turbo
- Voxtral-Mini-4B-Realtime: 4B params, <200ms streaming, Apache 2.0 — top candidate for v0.3
- OpenAI Whisper API ($0.006/min): good cloud fallback for users without GPU headroom

**Gap closure plan**:
1. **Immediate (4h)**: Add OpenAI Whisper API provider (cloud fallback)
2. **Short-term**: Upgrade default model from `base` to `base.en` (better English WER: ~8% vs ~10%)
3. **Medium-term**: Add Voxtral-Mini-4B-Realtime provider for true streaming
4. **Long-term**: Add whisper.cpp provider for native Metal acceleration
5. **Settings UI**: Let user choose model size + local vs cloud in the macOS app

---

## GAP 7: No Confidence-Based Quality Gating

**Severity**: 🟡 MEDIUM
**Evidence level**: Observed

**Current state**:
- Confidence is computed from `avg_logprob` (`provider_faster_whisper.py` L154–155)
- Confidence is **displayed** in the UI but **not used for filtering**
- Low-confidence segments (hallucinations, background noise transcribed as speech) pollute the transcript
- "Needs review" label exists (`CHANGELOG.md` L30) but thresholds are unclear

**What model-lab has**:
- `model-lab/harness/metrics_asr.py` — WER, CER calculation with error breakdown
- `model-lab/harness/evals.py` — evaluation framework
- `model-lab/harness/gate.py` — quality gating module exists

**Gap closure plan**:
1. Filter out segments with confidence < 0.3 (likely hallucinations)
2. Mark segments with confidence 0.3–0.6 as "low confidence" in the transcript
3. Exclude low-confidence segments from card/entity extraction
4. Port `model-lab/harness/gate.py` gating logic

---

## GAP 8: No Punctuation or Formatting Post-Processing

**Severity**: 🟡 MEDIUM
**Evidence level**: Observed

**Current state**:
- Whisper produces punctuated text natively, but quality varies with model size
- No post-processing for: sentence boundary detection, paragraph breaks, capitalization normalization
- No text normalization before entity extraction (causes duplicate entities: "EchoPanel" vs "echopanel")
- `model-lab/ADVANCED_FEATURES_ROADMAP.md` L28–34: word correction and post-processing planned

**What the research says**:
- `docs/ASR_MODEL_RESEARCH_2026-02.md` L170–173: stable-ts for timestamp stabilization, WhisperX for word-level timestamps
- Text post-processing (punctuation, truecasing) is standard in production ASR pipelines

**Gap closure plan**:
1. Add text normalization to entity extraction (case-folding, deduplication)
2. Add sentence boundary detection for better card extraction
3. Consider stable-ts integration for timestamp alignment

---

## GAP 9: Distribution Blockers (Non-Model Gaps)

**Severity**: 🔴 CRITICAL (launch blocker)
**Evidence level**: Observed

These are not model gaps but are included because they block all user-facing value:

| Blocker | Current State | Effort |
|---------|--------------|--------|
| No `.app` bundle | Swift Package Manager CLI only | 4–6h |
| No bundled Python runtime | Requires user to install Python 3.11+ | 4h (PyInstaller) |
| No code signing / notarization | Gatekeeper blocks the app | 2–3h + $99 Apple Dev Program |
| No model download UX | 1.5–3.2GB downloads with no progress bar | 2h |
| No DMG installer | No drag-to-Applications experience | 1–2h |
| **Total** | | **~13–17h** |

Source: `docs/DISTRIBUTION_PLAN_v0.2.md` L47–497

---

## GAP 10: No Multi-Language Support

**Severity**: 🟢 LOW (for v0.2 English-first)
**Evidence level**: Observed

**Current state**:
- Whisper supports 99 languages, but EchoPanel defaults to auto-detect with no language selection UI
- Entity extraction uses English-only keyword lists and name patterns
- NLP analysis is English-only
- `docs/STATUS_AND_ROADMAP.md` L53: "Multi-language UI: Localization support (4h)" — planned

**What the research says**:
- Voxtral supports 13 languages; Paraformer excels at Mandarin + code-switching
- For English-first MVP, this is fine — but it limits TAM

---

## GAP 11: No Meeting Template System

**Severity**: 🟢 LOW
**Evidence level**: Observed

**Current state**:
- One-size-fits-all analysis for all meeting types
- `docs/STATUS_AND_ROADMAP.md` L113: "Meeting templates (standup, 1:1, retrospective)" — v0.3 idea

**What would help**:
- Different meeting types need different extraction: standups focus on blockers, 1:1s on decisions, retrospectives on risks
- Templates could guide LLM prompts for better extraction quality

---

## GAP 12: No Cross-Project Model Sharing (EchoPanel ↔ Model-Lab)

**Severity**: 🟡 MEDIUM (developer productivity gap)
**Evidence level**: Observed

**Current state**:
- Model-lab's streaming ASR pipeline was **ported** from EchoPanel (`STREAMING_ASR_PORT_NOTES.md` L1–4)
- Both projects have independent `provider_faster_whisper.py` implementations
- Model-lab has richer infrastructure: `harness/gate.py`, `harness/nlp.py`, `harness/llm_provider.py`, `harness/preprocess_ops.py`, `harness/metrics_*` modules
- None of this flows back into EchoPanel

**What should happen**:
- EchoPanel should consume model-lab as a dependency or share a common library
- Model-lab benchmarks should directly inform EchoPanel's model selection
- New providers tested in model-lab should be deployable in EchoPanel with minimal adaptation

**Gap closure plan**:
1. Extract shared ASR/NLP interfaces into a common package (or use model-lab as a git submodule/dependency)
2. Use model-lab's benchmark results to set EchoPanel's default model and configuration
3. Port model-lab's `gate.py`, `nlp.py`, `llm_provider.py` to EchoPanel's `server/services/`

---

## Priority Matrix

| Gap | Severity | Effort | Impact on Users | Recommendation |
|-----|----------|--------|----------------|----------------|
| **G1: NLP Quality** | 🔴 Critical | M (1–3 days) | Determines if output is useful | **Do first** — add LLM via user's API key (hybrid, see `DECISIONS.md`) |
| **G2: No VAD** | 🔴 Critical | S (4–8 hours) | Prevents hallucinations during silence | **Do second** — add Silero VAD |
| **G9: Distribution** | 🔴 Critical | L (13–17 hours) | Blocks all external users | **Do third** — DMG + signing |
| **G3: No Streaming** | 🟡 High | M (1–2 weeks) | Reduces perceived latency | Phase 2 (v0.3) |
| **G4: No Preprocessing** | 🟡 High | S (4–8 hours) | Improves ASR in noisy environments | Phase 2 |
| **G5: No Real-Time Diar** | 🟡 High | M (1–2 weeks) | Enables "who said what" | Phase 2 |
| **G6: Single Provider** | 🟡 Medium | S (4 hours) | Adds cloud fallback | Quick win |
| **G7: No Quality Gating** | 🟡 Medium | S (2–4 hours) | Reduces noise in output | Quick win |
| **G8: No Post-Processing** | 🟡 Medium | S (2–4 hours) | Cleaner transcript | Quick win |
| **G12: No Model Sharing** | 🟡 Medium | M (1 week) | Developer productivity | Phase 2 |
| **G10: No Multi-Language** | 🟢 Low | S (4 hours) | Expands market | Phase 3 |
| **G11: No Templates** | 🟢 Low | M (1 week) | Better extraction per meeting type | Phase 3 |

---

## Model Upgrade Path (from Model-Lab Benchmarks + ASR Research)

### Current: faster-whisper `base` on CPU/int8
- WER: ~10% (English clean speech), ~24% (technical audio per model-lab)
- Latency: 4s chunk + ~0.5s inference = ~4.5s
- Size: ~150MB model

### Phase 1 Upgrade: faster-whisper `base.en` + Silero VAD
- WER: ~8% (English-only model is better for English)
- Latency: Same but skip silence chunks → perceived faster
- Size: ~150MB model + <1MB VAD
- Effort: 2–4 hours

### Phase 2 Upgrade: faster-whisper `large-v3-turbo` + VAD + LLM analysis
- WER: ~3% (state-of-the-art)
- Latency: 4s chunk + ~1–2s inference = ~5–6s
- Size: ~1.6GB model
- Requires: 16GB+ RAM, M1 Pro+ recommended
- Effort: 4–8 hours (model already supported via env var)

### Phase 3 Upgrade: Voxtral-Mini-4B-Realtime (streaming)
- WER: Claimed better than Whisper large-v3+ on some benchmarks
- Latency: Sub-200ms (true streaming)
- License: Apache 2.0 (full commercial freedom)
- Size: ~4B params
- Effort: 1–2 weeks (new provider implementation)
- Source: `ASR_MODEL_RESEARCH_2026-02.md` L187–206

### Phase 4 (Speculative): whisper.cpp with Metal acceleration
- WER: Same as Whisper (same weights, different runtime)
- Latency: Near-native C speed with Metal GPU acceleration
- Size: GGUF format, ~1–3GB depending on quant
- Benefit: Native macOS integration, no Python dependency for ASR
- Source: `ASR_MODEL_RESEARCH_2026-02.md` L162; `model-lab/models/whisper_cpp/` exists
- Effort: 2–4 weeks (significant architecture change)

---

## Online Research Gaps (Verification Needed)

> Web tools were unavailable. These items should be verified online:

| Item | Why it matters | Verification method |
|------|---------------|-------------------|
| Voxtral-Mini-4B-Realtime actual benchmarks | Claimed sub-200ms + better-than-Whisper — needs independent verification | Run in model-lab; check HF leaderboard |
| Silero VAD v5 features | May have improved since training data cutoff | Check github.com/snakers4/silero-vad |
| faster-whisper versions after 1.0.3 | EchoPanel pins v1.0.3; may miss bug fixes or features | Check github.com/SYSTRAN/faster-whisper/releases |
| Apple Intelligence meeting features | macOS 16 may add native transcription | Monitor WWDC 2026 |
| Moonshine Tiny (27M params) | Could enable <50MB first-run bundle | Check github.com/usefulsensors/moonshine |
| DeepFilterNet2 latest release | Best noise suppression candidate | Check github.com/Rikorose/DeepFilterNet |
| Granola technical architecture | Closest competitor — how do they do local processing? | Reverse engineer or read their blog |

---

*End of gap analysis.*
