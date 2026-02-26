# EchoPanel Research Master Index

**Last updated:** 2026-02-26  
**Total research documents:** 20  
**Total decisions recorded:** DEC-001 through DEC-045  
**Research sessions:** 3 waves across 2026-02-25 and 2026-02-26

---

## How to use this index

Each row links to a research document with a one-line summary and the decisions it produced. When adding new research, append a row here and create a ticket in `docs/WORKLOG_TICKETS.md`.

---

## Wave 1 — 2026-02-25: Mac Local Inference Foundations

| Doc | Summary | Decisions produced |
|-----|---------|-------------------|
| `MLX_ECOSYSTEM_RESEARCH_2026-02-25.md` | Full MLX stack survey: mlx-swift, mlx-audio-swift, mlx-swift-lm, FluidAudio, WhisperKit, ArgMax SDK v2. Architecture overview, API patterns, dependency graph. | DEC-001 through DEC-015 (in DECISIONS.md pre-sprint) |
| `MAC_LOCAL_INFERENCE_COMPLETE_GUIDE_2026-02-25.md` | Comprehensive SOTA model guide: Qwen3-ASR, Parakeet-TDT, MLX memory model, Apple Silicon perf tiers, model selection matrix for 8GB/16GB/24GB Macs. | Informs DEC-026→DEC-034 |
| `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md` | FluidAudio deep dive, diarization options, VAD comparison, SortformerDiarizer vs pyannote. **Note:** Some API signatures in this doc are outdated — see FLUIDAUDIO_API_VERIFICATION_2026-02-26.md for corrections. | DEC-016 through DEC-025 |
| `RESEARCH_REVIEW_2026-02-25.md` | Cross-cutting review of Wave 1 findings. Identified 4 red gaps: FluidAudio API unverified, RAM budget unknown, Parakeet Swift status unknown, WhisperKit pool compatibility. | Prompted Wave 2 sprint |
| `OCR_SOTA_RESEARCH_2026-02-14.md` | OCR pipeline: SmolVLM, PaddleOCR, ScreenCaptureKit, hybrid architecture. Pre-Swift-6 era. | Archived |
| `OCR_HYBRID_ARCHITECTURE_PLAN.md` | Hybrid OCR architecture plan (SmolVLM + PaddleOCR fallback). Implementation blueprint. | Archived — see TCK-20260218 series |

---

## Wave 2 — 2026-02-26 Morning: P0 Blocker Resolution (5-agent sprint)

| Doc | Summary | Decisions produced |
|-----|---------|-------------------|
| `FLUIDAUDIO_API_VERIFICATION_2026-02-26.md` | **Corrected** FluidAudio API: `DiarizerManager(config:)` synchronous init, `VadManager` is an `actor`. 3 pipelines: online, offline VBx batch, SortformerDiarizer streaming. Source code (MIT), not XCFramework. | DEC-026, DEC-027 |
| `RAM_BUDGET_ANALYSIS_2026-02-26.md` | 8GB Mac memory budget: full stack peaks 2.3–2.6GB (ASR 720MB + FluidAudio 300MB + system 1.5GB). Sequential phase scheduling is mandatory. 16GB unlocks concurrent resident models. | DEC-028, DEC-031 |
| `ASR_BENCHMARK_COMPARISON_2026-02-26.md` | WER/latency benchmarks: Qwen3-ASR-0.6B (5.8% WER), Parakeet-TDT (4.8%), VoxtralRealtime (4.9% English / 15.05% AMI), Whisper large-v3 (8.4%). Full comparison table + meeting audio (AMI) results. | DEC-029, DEC-030, DEC-033 |
| `ASR_BENCHMARK_SUMMARY.md` | Quick-reference 1-page summary of ASR_BENCHMARK_COMPARISON. | — |
| `README_ASR_BENCHMARK.md` | How to reproduce ASR benchmarks locally. | — |
| `MLX_SWIFT_LIBS_UPDATE_2026-02-26.md` | mlx-audio-swift v0.1.0 changelog (Feb 23 2026): Parakeet in Swift (PR #51), Qwen3ASR streaming fixed (PR #32), new: VoxtralRealtime (PR #52), LFM-2.5-Audio (PR #53), Sortformer (PR #33), MossFormer2 (PR #29, #44). mlx-swift-lm at v2.30.6 with Gemma3n support. | DEC-027, DEC-032, DEC-033, DEC-034 |
| `RESEARCH_SPRINT_2026-02-26.md` | **Master synthesis** of Wave 2. Updated ASR fallback chain, 4-week implementation plan for TCK-20260225-001, 11 prioritized action items, memory budget table. | DEC-026 through DEC-034 |

---

## Wave 3 — 2026-02-26 Afternoon: Audio Models + NLP + Gemma Family (9-agent sprint)

| Doc | Summary | Decisions produced |
|-----|---------|-------------------|
| `VOXTRAL_LFM_RESEARCH_2026-02-26.md` | VoxtralRealtime (Mistral 4B): confirmed `VoxtralRealtimeModel` in mlx-audio-swift PR #52, streaming via `generateStream()`, 4.90% WER English, 3.15GB 4bit. Custom adapter needed. LFM-2.5-Audio rejected (proprietary license). | DEC-035, DEC-037 |
| `HF_PRO_MODELS_SWEEP_2026-02-26.md` | Full HF Pro sweep across all categories: Qwen3-4B-Instruct (37K downloads), LFM2.5-Audio, nomic-embed-v2-moe, Qwen3-ForcedAligner, Llama-3.2-1B-Instruct-4bit (nano-LLM), embeddinggemma-300m. | DEC-038, DEC-039 |
| `MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md` | MossFormer2 (120MB, speech enhancement, 20-30% WER improvement). Sortformer v2.1 (185MB, 11-15% DER on AMI, beats pyannote 3.1, streaming-ready). Both in mlx-audio-swift. | DEC-036 |
| `RESEARCH_SUMMARY_MOSSFORMER2_SORTFORMER.md` | Quick-reference summary of above. | — |
| `GEMMA4_TRANSFORMERS_RESEARCH_2026-02-26.md` | Gemma 4 doesn't exist (as of 2026-02-26). Full Gemma family map: Gemma 3, Gemma 3n (E2B/E4B, ASR-capable, native in mlx-swift-lm v2.30.6), TranslateGemma (4b/12b/27b, released Jan 2026), FunctionGemma 270M, MedGemma. HF Transformers now at v5.2.0. Transformers.js v4 (WebGPU, Feb 2026). Full TranslateGemma integration analysis (3 paths). | DEC-040 through DEC-045 |
| `NLP_NER_PIPELINE_RESEARCH_2026-02-26.md` | 10-component NLP gap analysis: NER, timestamps, punctuation, language detection, segmentation, topic modeling, action items, emotion, speaker embeddings, grammar. Critical: Qwen3-ForcedAligner confirmed live. GLiNER has no MLX port (ONNX path). Apple NLLanguageRecognizer preferred over fasttext (NC license). | DEC-046 through DEC-049 (see below) |
| `AUDIO_PIPELINE_GAPS_2026-02-26.md` | 8 audio pipeline gap analyses: word timestamps (aligner already in checkout — just needs wiring), streaming latency (overlap-add implemented, min 1s chunk), multi-speaker overlap (Sortformer flags, no separation), audio preprocessing (ACM handles SR conversion, AUVoiceIO for AEC), ITN (regex covers 85%), SRT/VTT export (exists and passes tests). | DEC-050 through DEC-053 (see below) |

---

## Decision Registry Summary

| Range | Theme | Date |
|-------|-------|------|
| DEC-001 to DEC-025 | Wave 1 — Native stack architecture, model selection, API design | 2026-02-25 |
| DEC-026 to DEC-034 | Wave 2 — P0 blockers resolved, RAM budget, ASR chain, WhisperKit rejected | 2026-02-26 |
| DEC-035 to DEC-039 | Wave 3a — VoxtralRealtime premium tier, Sortformer/MossFormer2, nomic-v2-moe | 2026-02-26 |
| DEC-040 to DEC-045 | Wave 3b — Gemma family, TranslateGemma, Transformers.js v4 | 2026-02-26 |
| DEC-046 to DEC-053 | Wave 3c — NLP/NER gaps, audio pipeline gaps (see DECISIONS.md) | 2026-02-26 |

Full decision text: `docs/DECISIONS.md`

---

## Open Questions Tracker

See `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md` for the canonical list.

Current status (as of 2026-02-26):
- ✅ Q1: Parakeet in Swift — confirmed (PR #51)
- ✅ Q3: FluidAudio source type — confirmed (MIT source code)
- ✅ Q4: RAM budget — confirmed fits 8GB
- ✅ Q6: mlx-audio-swift version — pinned to v0.1.0
- ✅ Q7: mlx-swift-lm version — v2.30.6
- ⚠️ Q2: Streaming API shape — partially resolved (generateStream confirmed)
- ⚠️ Q5: First-run UX — product decision pending
- ⚠️ Q8: Diarization accuracy parity — needs benchmarks
- ⚠️ Q9: ANE vs GPU profiling — needs Instruments run
- ⚠️ Q10: HF token in production — product/legal decision pending

---

## What's NOT yet documented (future research needed)

| Topic | Priority | Notes |
|-------|----------|-------|
| Gemma 4 (actual release) | Watch | Expected Q1–Q2 2026. Revisit when announced. |
| ANE profiling (Q9) | P1 | Instruments traces needed on real hardware |
| Diarization accuracy parity (Q8) | P1 | Run FluidAudio vs Sortformer on AMI test set |
| GLiNER ONNX Swift integration | P2 | `fastino/gliner2-base-v1` — no mlx port, ONNX Runtime Swift path |
| Transformers.js v4 stable release | Watch | Currently `@next` tag on NPM; full release TBD |
| Bun server alternative | P3 | Post-launch: replace Python FastAPI fallback with Bun+Transformers.js v4 |
| FunctionGemma 270M MLX conversion | P2 | `mlx_lm.convert --model google/functiongemma-270m-it -q` |
| embeddinggemma-300m (gated) | P2 | HF Pro access should work; test with token |
