# Doc Review Report: ASR_MODEL_RESEARCH_2026-02.md

**Reviewer**: Doc-to-Code Audit Agent  
**Review Date**: 2026-03-05  
**Target Doc**: [`docs/ASR_MODEL_RESEARCH_2026-02.md`](../ASR_MODEL_RESEARCH_2026-02.md)  
**Phase**: Phase 1 — Read-only review (no implementation)

---

## 1. Doc Summary

| Field | Value |
|-------|-------|
| **Purpose** | Research-grade landscape survey of 60+ audio AI models for use as an implementation guide for EchoPanel's "Speech Experiments Model Lab" feature |
| **Audience** | EchoPanel engineers / product owners deciding which ASR/TTS/audio models to adopt |
| **Scope** | ASR, TTS, voice cloning, music, audio classification, neural codecs, forensics, multimodal LLMs, VAD/diarization, APIs, cost models |
| **Status** | Active — references v0.3 of the codebase; Voxtral providers are already implemented |
| **Call to action** | Use the Implementation Roadmap (§13) and Database Schema (§12.2) to drive feature work through Phase 1–4 |

---

## 2. Explicit Claims & Requirements

1. **EchoPanel default model = `base`** (§2.1.4, Whisper table, row "base") marked "**Current EchoPanel default**"
2. **Tier 1 Immediate models**: wav2vec 2.0, Whisper, Demucs, CosyVoice2-0.5B, YAMNet, Silero VAD, pyannote.audio
3. **Voxtral-Mini-4B-Realtime is the top v0.3 streaming candidate** (§2.1.5), citing Apache 2.0 and <200ms latency
4. **Phase 1 roadmap calls for** `faster-whisper base.en` as P0-1 and `Silero VAD` as P0-2 (§13)
5. **Unified audio-LLMs (gpt-audio, Qwen2-Audio, Step-Audio 2 mini) displace pipeline architectures** as a strategic insight (§1.1)
6. **Whisper is 20+ language-specific checkpoints and supports ONNX export** (§2.1.4)
7. **API cost break-even for local ASR**: `base.en` already "bundled" at zero cost (§14.1)
8. **Database schema** proposed for tracking 1-row-per-deployable-variant (§12.2)
9. **Voxtral-Mini-3B, 4B-Realtime, 24B** all claimed Apache 2.0 (§2.1.5)
10. **CTranslate2/faster-whisper is 4× faster** than baseline Transformers (§2.1.4 runtime table)
11. **PyAnnote.audio is Tier 1** in the master database table (§12.1, row "pyannote.audio")
12. **Silero VAD is Tier 1** (§12.1, row "Silero VAD")

---

## 3. Implicit Assumptions & Inferred Intent

- EchoPanel should prefer **local-first** models for privacy and latency
- The "Speech Experiments Model Lab" is likely a provider-switcher UI not yet shown in the public codebase
- **faster-whisper** is assumed to be the current/incumbent production provider
- The doc treats the macOS Apple Silicon deployment constraint as implicit (whisper.cpp/MLX are mentioned as alternatives but not explicitly called out for the EchoPanel mac app context — the code addresses this explicitly, the doc does not)
- Breaking the doc out by "Tier" is meant to drive sprint planning, but there's no explicit ticket/issue system referenced
- The statement "base.en already bundled" (§14.1) implies the model is pre-packaged or auto-downloaded — the code does lazy-load on first request, not truly bundled at install time (important distinction)

---

## 4. Questions the Doc Asks (Direct + Implied)

| # | Question | Context |
|---|----------|---------|
| Q1 | Which Whisper variant is optimal for EchoPanel's meeting-length recordings? | Implied by the detailed Whisper matrix (§2.1.4) |
| Q2 | Should Voxtral-Mini-4B-Realtime replace faster-whisper in v0.3? | §2.1.5 "top candidate for v0.3 streaming upgrade" |
| Q3 | Is Paraformer viable for non-English / mixed meeting content? | §2.1.6 suggests Mandarin/Asian-language focus |
| Q4 | Should the Model Lab track variants at the level of `weights × runtime × quantization × fork`? | §12.2 database schema proposal |
| Q5 | At what usage level does local ASR become strictly cheaper than APIs? | §14 break-even analysis — currently pegged at 10K–50K hours/month |
| Q6 | What is the blast radius of adopting CC-BY-NC models (wav2vec 2.0 large, SeamlessM4T)? | Licensing column in §12.1 |

---

## 5. Tasks Mentioned

### 5a. Open Tasks

| ID | Task | Source |
|----|------|--------|
| T-01 | Implement `faster-whisper base.en` as P0-1 baseline provider | §13 Phase 1 |
| T-02 | Implement `Silero VAD` for streaming chunking (P0-2) | §13 Phase 1 |
| T-03 | Evaluate WhisperX for diarization glue (P0-3, optional) | §13 Phase 1 |
| T-04 | Implement pyannote.audio for "who said what" (P0-4) | §13 Phase 1 |
| T-05 | Evaluate Voxtral-Mini-4B-Realtime for Phase 2 streaming | §13 Phase 2 |
| T-06 | Evaluate faster-whisper large-v3-turbo int8 quality upgrade | §13 Phase 2 |
| T-07 | Build model tracking database (CSV schema §12.2) | §12.2 |
| T-08 | Evaluate CLAP for zero-shot audio search | §13 Phase 3 |
| T-09 | Integrate DeepFilterNet2 for real-time noise suppression | §13 Phase 3 |
| T-10 | Evaluate AudioSeal for deepfake detection | §13 Phase 4 |
| T-11 | Evaluate Qwen2-Audio for audio reasoning | §13 Phase 4 |

### 5b. Completed / Claimed Tasks

| ID | Claim | Validation Result |
|----|-------|-------------------|
| C-01 | `faster-whisper base.en` is "Current EchoPanel default" | ✅ **Verified** — `asr_stream.py:30` defaults to `base.en`; `provider_faster_whisper.py` is registered and auto-loaded |
| C-02 | Silero VAD is integrated for streaming chunking | ✅ **Verified (partially)** — `vad_asr_wrapper.py` wraps any provider with Silero VAD; enabled by default (`ECHOPANEL_ASR_VAD=1`). However, `asr_stream.py` only auto-registers `faster_whisper`, `voxtral_realtime`, and `whisper_cpp` — not mlx_whisper and onnx_whisper (registered only via `__init__.py`) |
| C-03 | Voxtral-Mini-4B-Realtime provider exists for Phase 2 evaluation | ✅ **Verified** — `provider_voxtral_official.py` uses `mistralai/Voxtral-Mini-4B-Realtime-2602` via vLLM; `provider_voxtral_realtime.py` uses `voxtral.c` binary for Metal-native streaming |
| C-04 | Degrade ladder exists for adaptive performance management | ✅ **Verified** — `degrade_ladder.py` with 5-level RTF-based ladder, chunk dropping, failover, and recovery logic |
| C-05 | "base" labelled as current default in Whisper table | ⚠️ **Partially correct** — Doc says `base` (multilingual); code uses `base.en` (English-only). Functionally equivalent for English but different model weights. The doc's table does show `base.en` in a separate row without the "current EchoPanel default" tag |

---

## 6. Confusions, Contradictions & Suspect Parts

1. **"base" vs "base.en" mislabel** (§2.1.4 Whisper table): The "Current EchoPanel default" tag is on the `base` row (multilingual, 74M, ~10% WER), but the code (`asr_stream.py:30`) defaults to `base.en` (English-only, ~8% WER). Minor but confusing if someone reads the doc to reconfigure the system.

2. **"base.en already bundled" cost claim** (§14.1): The doc says `base.en` is at "$0 (base.en already bundled)". In practice, `_get_model()` in `provider_faster_whisper.py` lazy-downloads from Hugging Face on first call — it is **not shipped in the container/binary**. This is potentially misleading for someone calculating cold-start behavior or offline deployment.

3. **Voxtral section missing platform caveat** (§2.1.5): The doc presents Voxtral-Mini-4B-Realtime as ideal with "sub-200ms latency, Apache 2.0". It does not mention the critical mac/vLLM constraint. `provider_voxtral_official.py:296-300` explicitly warns: "vLLM does not support Apple Silicon GPUs, Voxtral will run on CPU which is very slow." This is not surfaced in the doc at all.

4. **Two Voxtral providers exist, doc treats it as one** (§2.1.5): The codebase has *two* completely different Voxtral implementations — `voxtral_official` (vLLM HTTP, Linux/CUDA) and `voxtral_realtime` (voxtral.c binary, Metal). The doc references only the conceptual model, not the split architecture.

5. **Roadmap Phase 2 is partially already done** (§13 Phase 2): Doc places Voxtral-Mini-4B-Realtime in "Phase 2 (Months 3-4)", but two Voxtral providers are already committed. Phase 2 should be updated to reflect current state.

6. **Phase 1 items fully implemented but not marked as done** (§13 Phase 1):
   - P0-1 `faster-whisper base.en`: ✅ Done
   - P0-2 `Silero VAD`: ✅ Done (VAD wrapper)
   - P0-3 WhisperX (optional): ❓ Not implemented (pyannote via WhisperX not found)
   - P0-4 pyannote.audio: ⚠️ `diarization.py` exists but is not default-registered as an ASR pipeline component

7. **Twitter/X Section (§10) is not repo-grounded**: The section covers xAI Grok 3, ByteDance Seed, DeepSeek V4, etc. These are LLM/text models and have **no relevance to the audio AI scope** of the document. This creates scope confusion for anyone reading the doc as a roadmap input.

8. **Provider registration inconsistency** (`asr_stream.py` vs `__init__.py`): `asr_stream.py` explicitly imports only 3 providers (`faster_whisper`, `voxtral_realtime`, `whisper_cpp`) to trigger registration. The `__init__.py` imports all 6. If code uses `asr_stream.py` as entry point (it does for WebSocket), `mlx_whisper` and `voxtral_official` won't be in registry unless `__init__.py` is also imported first.

9. **Roadmap has no acceptance criteria validation mechanism**: The success criteria in §13 (e.g., "<10% WER clean") are not tied to any automated test or benchmark script in the repo.

---

## 7. Validation Against Code

### ✅ Verified Items

| Claim | Code Evidence |
|-------|--------------|
| `faster_whisper` is default provider | `asr_stream.py:30` — `model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en")` |
| Silero VAD is integrated | `vad_asr_wrapper.py` — lazy-loads `snakers4/silero-vad` via torch.hub, wraps any ASRProvider |
| Degrade ladder exists | `degrade_ladder.py` — 5-level RTF ladder: NORMAL/WARNING/DEGRADE/EMERGENCY/FAILOVER |
| Voxtral-Mini-4B-Realtime implemented | `provider_voxtral_official.py` — MODEL_ID = `mistralai/Voxtral-Mini-4B-Realtime-2602`; vLLM HTTP backend |
| Metal/whisper.cpp alternate provider | `provider_whisper_cpp.py` exists and is registered |
| MLX Apple Silicon provider | `provider_mlx_whisper.py` — uses `mlx-community/whisper-*` models, Metal GPU |
| LRU provider cache | `asr_providers.py:312-461` — `ASRProviderRegistry` with `OrderedDict` LRU, max instances env-controlled |
| VAD enabled by default | `asr_stream.py:27` — `vad_default = os.getenv("ECHOPANEL_ASR_VAD", "1") == "1"` |
| Provider capability reporting | `ProviderCapabilities` dataclass in `asr_providers.py:144`, implemented per provider |

### ❌ Mismatches & Gaps

| Mismatch | Doc Says | Code Says | Evidence |
|----------|----------|-----------|----------|
| Default model label | "base" (multilingual) | `base.en` (English-only) | `asr_stream.py:30` |
| "base.en bundled" | Zero cost, pre-packaged | Lazy-downloaded from HF on first call | `provider_faster_whisper.py:100` — `WhisperModel(model_name, ...)` |
| vLLM macOS limitation | Not mentioned | Explicitly warned and handled | `provider_voxtral_official.py:296-300` |
| Phase 1 completion | All marked open | P0-1, P0-2 implemented; P0-3, P0-4 unclear | `asr_stream.py`, `vad_asr_wrapper.py` |
| Phase 2 completion | Open future work | Two Voxtral providers already committed | `provider_voxtral_official.py`, `provider_voxtral_realtime.py` |
| Provider auto-registration | Implied uniform | 3 providers registered in `asr_stream.py`, 6 in `__init__.py` | `asr_stream.py:17-19` vs `__init__.py:32-60` |
| WhisperX for diarization (P0-3) | Listed as optional P0-3 | Not found in services; `diarization.py` exists but uses pyannote directly | `diarization.py` not wired into main ASR pipeline |
| pyannote.audio P0-4 | Listed in Phase 1 | `diarization.py` exists but not integrated as default ASR pipeline step | `services/diarization.py` |

### Missing Tests / Missing Repro Steps

- No automated WER benchmark test exists (doc specifies `<10% WER clean` as success criterion)
- `tests/test_voxtral_provider_metrics.py` is 674 bytes — likely minimal; Voxtral vLLM path is hard to test without a running vLLM server
- No test for `degrade_ladder.py` step-up/step-down behavior in continuous streaming (only unit-level demo)
- No integration test verifying `mlx_whisper` or `voxtral_official` registration via `asr_stream.py` (they are not imported there)

---

## 8. Findings Backlog

---

### F-001 — Default Model Label Mismatch in Whisper Table

| Field | Value |
|-------|-------|
| **Type** | Docs gap |
| **Evidence** | Doc §2.1.4 marks `base` row as "Current EchoPanel default"; `asr_stream.py:30` uses `base.en` |
| **Impact** | Misleads readers into thinking the multilingual model is default; potential for incorrect config when deploying non-English |
| **Confidence** | High — single-line check confirms the mismatch |
| **Resolution** | Change the label in the Whisper table to `base.en` |
| **Acceptance Criteria** | Doc table row for `base.en` shows "**Current EchoPanel default**"; `base` row has no such label |

---

### F-002 — Misleading "Already Bundled, $0" Cost Claim

| Field | Value |
|-------|-------|
| **Type** | Docs gap / Risk |
| **Evidence** | §14.1 "base.en already bundled"; code does runtime HuggingFace download (`provider_faster_whisper.py:100`) |
| **Impact** | Engineers expect offline-capable deployment; cold-start latency and offline support are unknown to doc readers |
| **Confidence** | High — code clearly shows lazy download, no bundled weights |
| **Resolution** | Clarify §14.1 to say "base.en auto-downloaded on first launch (~150MB)"; add note on offline-mode requirements |
| **Acceptance Criteria** | Doc §14.1 accurately describes first-run download behavior |

---

### F-003 — Voxtral Section Missing Mac/vLLM Platform Constraint

| Field | Value |
|-------|-------|
| **Type** | Docs gap / Risk |
| **Evidence** | §2.1.5 omits platform limitation; `provider_voxtral_official.py:6-8` states vLLM does not support Apple Silicon |
| **Impact** | Mac Apple Silicon engineers may attempt vLLM Voxtral and waste time debugging GPU fallback; critical for EchoPanel mac app |
| **Confidence** | High |
| **Resolution** | Add a warning box in §2.1.5: "macOS/Apple Silicon: vLLM does not support Metal GPU. Use `voxtral_realtime` (voxtral.c binary) or `mlx_whisper` instead." |
| **Dependencies** | Links to `VOXTRAL_VLLM_SETUP_GUIDE.md` which exists |
| **Acceptance Criteria** | §2.1.5 contains a platform compatibility table or callout covering Linux+CUDA vs macOS+Metal path |

---

### F-004 — Two Voxtral Providers Not Distinguished in Doc

| Field | Value |
|-------|-------|
| **Type** | Docs gap |
| **Evidence** | §2.1.5 treats "Voxtral" as singular; codebase has `voxtral_official` (vLLM/CUDA) and `voxtral_realtime` (voxtral.c/Metal) |
| **Impact** | Engineers don't know which provider to select; integration complexity is hidden |
| **Confidence** | High |
| **Resolution** | Add a "EchoPanel Provider Mapping" subsection in §2.1.5 or §13 showing the two provider identifiers, their platform requirements, and env var to select them |
| **Acceptance Criteria** | Doc explains `ECHOPANEL_ASR_PROVIDER=voxtral_official` (Linux/CUDA) vs `voxtral_realtime` (macOS/Metal) |

---

### F-005 — Phase 1 and Phase 2 Roadmap Stale (Already Implemented)

| Field | Value |
|-------|-------|
| **Type** | Docs gap / Tech debt |
| **Evidence** | §13 Phase 1 and Phase 2 list work as open; code confirms P0-1, P0-2, and Phase 2 Voxtral providers are implemented |
| **Impact** | Roadmap is misleading as planning input; sprint planning may re-work completed items |
| **Confidence** | High for P0-1/P0-2; Medium for P0-3/P0-4 (partially unclear) |
| **Resolution** | Update §13 to mark P0-1 and P0-2 as ✅ complete; annotate Phase 2 Voxtral as ✅ implemented (evaluation still needed); clarify P0-3/P0-4 status |
| **Acceptance Criteria** | Each Phase 1-2 row has a status indicator (✅/⚠️/❌) and current state description |

---

### F-006 — Provider Auto-Registration Gap in `asr_stream.py`

| Field | Value |
|-------|-------|
| **Type** | Bug / Tech debt |
| **Evidence** | `asr_stream.py:17-19` imports only 3 providers; `mlx_whisper` and `voxtral_official` only registered if `__init__.py` is imported first |
| **Impact** | `ECHOPANEL_ASR_PROVIDER=mlx_whisper` or `voxtral_official` silently falls back to None if WebSocket handler uses `asr_stream.py` as entry without going through the package `__init__` |
| **Confidence** | High — code clearly shows the import gap |
| **Resolution** | Add `from . import provider_mlx_whisper, provider_voxtral_official, provider_onnx_whisper` to `asr_stream.py` imports (following the pattern of existing imports) |
| **Dependencies** | None; safe additive change |
| **Acceptance Criteria** | `ECHOPANEL_ASR_PROVIDER=mlx_whisper` works when `asr_stream.py` is the entry point without requiring package-level import |

---

### F-007 — Twitter/X LLM Section Out of Scope

| Field | Value |
|-------|-------|
| **Type** | Docs gap / Maintainability |
| **Evidence** | §10 covers Grok 3, ByteDance Seed, DeepSeek V4 — all general-purpose LLMs with no audio capability described |
| **Impact** | Inflates the document by ~10% with off-topic content; dilutes the audio AI focus; could mislead readers about EchoPanel's scope |
| **Confidence** | High |
| **Resolution** | Move §10 (Twitter/X LLM discoveries) to a separate `LLM_LANDSCAPE_2026-02.md` and replace with a focused summary of audio-relevant community signals only |
| **Acceptance Criteria** | §10 in the audio doc contains only audio-AI community signals; LLM discoveries exist in a separate document |

---

### F-008 — No WER Benchmark Test Infrastructure

| Field | Value |
|-------|-------|
| **Type** | Missing feature / Research needed |
| **Evidence** | §13 specifies `<10% WER clean, <15% noisy` for P0-1; no WER test found in `tests/` |
| **Impact** | Success criteria for Phase 1 cannot be verified; model changes could regress quality without automated detection |
| **Confidence** | High that test is missing; Medium on exact right approach (LibriSpeech subset or custom meeting clips?) |
| **Resolution** | Create `tests/benchmark_asr_wer.py` that downloads a small LibriSpeech sample and runs the current active provider; record results in `docs/asr_benchmark_results.md` |
| **Dependencies** | Requires download of LibriSpeech test-clean subset (~1GB) or use of existing test WAVs in repo |
| **Acceptance Criteria** | `pytest tests/benchmark_asr_wer.py` produces a WER report; CI runs it nightly or per provider change |

---

### F-009 — `diarization.py` Not Wired Into Main ASR Pipeline

| Field | Value |
|-------|-------|
| **Type** | Missing feature |
| **Evidence** | §13 lists pyannote.audio as P0-4; `services/diarization.py` exists but `asr_stream.py` has no diarization hook; `ASRSegment.speaker` field exists but is never populated in current pipeline |
| **Impact** | "Who said what" feature (P0-4) is present in the data model but not functional end-to-end |
| **Confidence** | High — `ASRSegment.speaker` is always `None` in all current providers |
| **Resolution** | Wire `diarization.py` as a post-processing step in `asr_stream.py` or `main.py`; populate `ASRSegment.speaker` |
| **Acceptance Criteria** | WebSocket output includes `speaker` field when diarization is enabled |

---

### F-010 — Silero VAD Has Better Open-Source Replacements (TEN VAD + FireRedVAD)

> **Added 2026-03-05** — Post-audit research finding; updated same day with FireRedVAD discovery.

| Field | Value |
|-------|-------|
| **Type** | Tech debt / Missing feature |
| **Evidence** | Two new Apache 2.0 VADs beat Silero across all dimensions; user community confirms real-world TEN VAD wins |
| **Impact** | Current `vad_asr_wrapper.py` uses Silero which has: (1) PyTorch cold-start (~1–3s), (2) 200–500ms end-of-speech latency, (3) missed short intra-utterance pauses — all increasing E2E latency |
| **Confidence** | High — both benchmarks independently reproducible; real-world confirmation provided |

**Model Rankings:**

| Rank | Model | Why |
|------|-------|-----|
| 🥇 **Primary** | **FireRedVAD** | SOTA on FLEURS-VAD-102 (F1 97.57%, AUC 99.60%), Apache 2.0, 100+ languages, streaming + AED. Pure Python, no platform restriction |
| 🥈 **Secondary / edge** | **TEN VAD** | 306KB, Apache 2.0, 48% faster CPU than Silero, real-world validated (3.61% WER on EN qwen3asr, wins 3/4 JP engines). Best for ultra-low-resource / edge deployments |
| ⚠️ **Fallback** | **Silero** | Retain for macOS if Python bindings for FireRedVAD cause issues |
| ❌ **Ruled out** | **Cobra VAD** | Proprietary, $6K/yr commercial license |

**Proposed resolution:**
1. Add `ECHOPANEL_VAD_BACKEND=firered|ten_vad|silero` env toggle to `vad_asr_wrapper.py`
2. Default to `firered` (FireRedVAD) — platform-agnostic Python, most accurate
3. `ten_vad` as option for edge/lightweight scenarios
4. `silero` as last-resort fallback

| **Risk** | FireRedVAD requires `git clone` + HF model download (no pip package yet); setup heavier than TEN VAD |
| **Dependencies** | `pip install -r requirements.txt` from `FireRedTeam/FireRedVAD`; HuggingFace `FireRedTeam/FireRedVAD` model download |
| **Acceptance Criteria** | `ECHOPANEL_VAD_BACKEND=firered` works end-to-end; VAD benchmark shows ≥F1 improvement over Silero; macOS CI passes with `silero` fallback |

---

## 9. Recommendations for Next Step Discussion

Ranked by leverage × confidence:

1. **Fix the provider registration gap (F-006)** — Low risk, one-line additive fix, immediate impact for anyone trying `mlx_whisper` or `voxtral_official` from the WebSocket handler.

2. **Evaluate and integrate FireRedVAD / TEN VAD as Silero replacements (F-010)** — Both Apache 2.0, both exceed Silero accuracy, real-world confirmed. FireRedVAD is the primary pick (best accuracy, platform-agnostic Python), TEN VAD for edge.

3. **Update §13 roadmap to reflect current implementation state (F-005)** — Avoids duplicate sprinting; sets correct baseline for Phase 3 planning.

4. **Add the Mac/vLLM platform caveat and two-provider distinction to §2.1.5 (F-003 + F-004)** — Most dangerous knowledge gap given EchoPanel is a macOS app.

5. **Fix the `base` vs `base.en` label in the Whisper table (F-001)** — Two-minute doc fix.

6. **Clarify the "bundled" cost claim (F-002)** — Important for offline deployment planning.

7. **Scope the Twitter/X section to audio-only (F-007)** — Document hygiene.

8. **Design and implement WER benchmark test (F-008)** — Highest effort, needed to validate success criteria.

---

## Appendix: File Evidence Index

| File | Relevance |
|------|-----------|
| `server/services/asr_stream.py` | Default config (`base.en`), VAD-on-by-default, limited provider imports |
| `server/services/asr_providers.py` | ASRProvider ABC, ASRConfig, ASRHealth, ASRProviderRegistry (LRU cache) |
| `server/services/provider_faster_whisper.py` | FasterWhisperProvider — current default, lazy HF download |
| `server/services/provider_voxtral_official.py` | VoxtralOfficialProvider — vLLM HTTP, macOS CPU-only warning |
| `server/services/provider_voxtral_realtime.py` | VoxtralRealtimeProvider — voxtral.c binary, Metal GPU, streaming |
| `server/services/provider_mlx_whisper.py` | MLXWhisperProvider — mlx-community models, Metal, Apple Silicon |
| `server/services/vad_asr_wrapper.py` | VADASRWrapper + SmartVADRouter — Silero VAD (upgrade candidate to FireRedVAD / TEN VAD) |
| `server/services/degrade_ladder.py` | DegradeLadder — RTF-based adaptive performance management |
| `server/services/diarization.py` | Diarization service — exists but not wired into streaming pipeline |
| `server/services/__init__.py` | Full provider registration (6 providers) |
| `docs/VOXTRAL_VLLM_SETUP_GUIDE.md` | Companion doc for vLLM Voxtral setup |
| `docs/ASR_MODEL_RESEARCH_2026-02.md §8` | FireRedVAD + TEN VAD + Cobra VAD benchmarks and EchoPanel verdicts |


