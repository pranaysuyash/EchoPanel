<overview>
EchoPanel is a macOS-only menu bar meeting transcription app (Apple Silicon) that the user is building pre-launch. This session had two parallel tracks: (1) completing a Wave 3 multi-agent research sprint covering audio models, Gemma family, NLP/NER pipeline gaps, TranslateGemma, and Transformers.js v4; and (2) beginning an Audit-Doc Work Planner analysis pass (Step 0–1 orient + inventory). The user's core principle throughout: Mac-only = go fully native Swift/MLX; FastAPI is fallback only; document everything before implementing.
</overview>

<history>

1. **Session resumed mid-research — agents 7/8/9 still running**
   - Read completed agents: agent-7 (VoxtralRealtime), agent-8 (HF Pro sweep), agent-9 (MossFormer2+Sortformer)
   - Fixed Package.swift: swift-tools-version 6.0→6.2, `branch: "main"` → `from: "0.1.0"` for mlx-audio-swift, added mlx-swift-lm from "2.30.6"
   - Verified mlx-audio-swift v0.1.0 tag exists on remote, mlx-swift-lm 2.30.6 resolves correctly
   - Build confirmed passing: `Build complete! (0.45s)`
   - Appended DEC-035 through DEC-039 to DECISIONS.md
   - Committed all Wave 3 research docs + Package.swift changes

2. **User asked about Gemma 4 series**
   - Web searched: Gemma 4 does NOT exist as of 2026-02-26. Latest is Gemma 3 + Gemma 3n (E2B/E4B)
   - HF API sweep: confirmed Gemma 3n tags include `automatic-speech-recognition`, `audio-text-to-text`
   - Key discovery: `Gemma3nTextModel` already in mlx-swift-lm v2.30.6 (`Libraries/MLXLLM/Models/Gemma3nText.swift`)
   - Pre-registered ModelConfigurations: `gemma3n_E2B_it_lm_4bit`, `gemma3n_E4B_it_lm_4bit`, etc.
   - `FunctionGemma-270m-it` (47K downloads): structured JSON output at ~150MB
   - TranslateGemma (4B/12B/27B): released Jan 12 2026, 55 languages, MLX 4bit exists
   - Launched agents 10 (Sonnet) and 11 (Opus) for deep dives
   - Appended DEC-040 through DEC-045; committed

3. **User asked about Transformers.js v4**
   - Web fetched official HF blog post: confirmed C++ WebGPU runtime rewrite, 30× faster, Node/Bun/Deno support, Feb 10 2026 preview
   - Checked landing page: `landing/app.js` is waitlist-only, no AI yet
   - Checked server: full FastAPI with `services/llm_providers.py`, `diarization.py`, `provider_voxtral_realtime.py`, etc.
   - Documented 3 Transformers.js v4 paths: landing page demo, Bun server alternative, web companion
   - All documented in GEMMA4_TRANSFORMERS_RESEARCH_2026-02-26.md sections 2+3

4. **User clarified: "not necessarily MLX Swift, can we use TranslateGemma?"**
   - Documented 3 full integration paths: Python FastAPI (Path A), Native Swift MLXLLM (Path B, zero new code since `gemma3` type registered), Transformers.js v4 (Path C)
   - Verified: `translategemma-4b-it-4bit` = 2.18 GB disk, COMET22 80.1
   - Appended DEC-044 (Path B preferred) and DEC-045 (landing page demo)
   - Committed

5. **User said "document everything I gave you, you searched etc"**
   - Read all 4 remaining agents (10, 11, 12, 13) — all completed
   - Created `docs/research/RESEARCH_MASTER_INDEX.md`: canonical index of all 20 research docs
   - Appended DEC-046 through DEC-053 (NLP/NER gaps + audio pipeline gaps)
   - Added TCK-20260226-001 to WORKLOG_TICKETS.md (Wave 3 14-agent sprint ticket, DONE)
   - Committed: "docs: master research index + DEC-046→053 + Wave 3 ticket"

6. **User triggered Audit-Doc Work Planner agent prompt**
   - Launched explore agent + bash inventory in parallel
   - Completed Steps 0 (orient) and 1 (find audit docs): found 100+ audit/review/research docs
   - Key audit docs identified: `full-repo-review-20260226.md`, `SENIOR_STAKEHOLDER_RED_TEAM_REVIEW_20260214.md`, `AUDIO_PIPELINE_GAPS_2026-02-26.md`, `NLP_NER_PIPELINE_RESEARCH_2026-02-26.md`, `NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`
   - Session compacted before Steps 2–9 were completed

</history>

<work_done>

**Files modified:**
- `macapp/MeetingListenerApp/Package.swift` — swift-tools-version 6.0→6.2, mlx-audio-swift branch→v0.1.0, added mlx-swift-lm from "2.30.6"
- `macapp/MeetingListenerApp/Package.resolved` — updated resolution (mlx-swift-lm 2.30.6 added)
- `docs/DECISIONS.md` — DEC-035 through DEC-053 appended (19 new decisions)
- `docs/WORKLOG_TICKETS.md` — TCK-20260226-001 added (Wave 3 research sprint, DONE)

**Files created:**
- `docs/research/VOXTRAL_LFM_RESEARCH_2026-02-26.md` (500 lines) — VoxtralRealtime + LFM-2.5-Audio
- `docs/research/HF_PRO_MODELS_SWEEP_2026-02-26.md` (310 lines) — Full HF Pro model sweep
- `docs/research/MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md` (646 lines) — MossFormer2 + Sortformer
- `docs/research/RESEARCH_SUMMARY_MOSSFORMER2_SORTFORMER.md` (141 lines) — Quick reference
- `docs/research/GEMMA4_TRANSFORMERS_RESEARCH_2026-02-26.md` (380+ lines) — Gemma family + TranslateGemma + Transformers.js v4
- `docs/research/NLP_NER_PIPELINE_RESEARCH_2026-02-26.md` (556 lines) — NLP/NER 10-component gap analysis
- `docs/research/AUDIO_PIPELINE_GAPS_2026-02-26.md` (479 lines) — 8 audio pipeline gap analyses
- `docs/research/RESEARCH_MASTER_INDEX.md` — Canonical index of all 20 research docs

**Git commits (4 in this session):**
1. `research: Wave 3 findings — VoxtralRealtime, HF Pro sweep, MossFormer2+Sortformer; fix Package.swift`
2. `research: Gemma family sweep + Transformers versioning (DEC-040→043)`
3. `research: TranslateGemma + Transformers.js v4 integration analysis (DEC-044, DEC-045)`
4. `docs: master research index + DEC-046→053 + Wave 3 ticket (TCK-20260226-001)`

**Current state:**
- [x] All 14 agents read and documented
- [x] Package.swift pinned to stable versions (no more branch: "main")
- [x] Build passes: `Build complete! (0.45s)`, all 163 tests pass
- [x] 53 decisions documented (DEC-001→053)
- [x] 20 research docs with master index
- [ ] Audit-Doc Work Planner: Steps 0–1 complete, Steps 2–9 NOT YET DONE
- [ ] TCK-20260225-001 implementation not yet started

</work_done>

<technical_details>

**Package.swift critical facts:**
- `swift-tools-version: 6.2` required (mlx-audio-swift v0.1.0 uses 6.2 in its own manifest; our toolchain is Swift 6.2.3)
- mlx-audio-swift tag is `v0.1.0` (with `v` prefix) but SPM resolves `from: "0.1.0"` correctly
- mlx-swift-lm URL: `https://github.com/ml-explore/mlx-swift-lm.git` (separate from mlx-swift-examples)

**Gemma 3n — already in mlx-swift-lm v2.30.6:**
- `Libraries/MLXLLM/Models/Gemma3nText.swift` exists in local checkout
- Model type key: `"gemma3n"` registered in `LLMModelFactory.swift` line 34
- Pre-registered configs: `gemma3n_E2B_it_lm_4bit`, `gemma3n_E4B_it_lm_4bit` (both mlx-community, ~1.1–2.2GB)
- The `-lm` suffix = text-only (audio/vision heads stripped) — lighter for meeting analysis

**TranslateGemma:**
- Model type: `gemma3` (uses `Gemma3TextModel` in mlx-swift-lm — zero new code needed)
- `mlx-community/translategemma-4b-it-4bit` = 2.18 GB, COMET22 80.1, 55 core languages
- License: Gemma Terms of Use (commercial use permitted for non-Google-competing apps)
- Path B (native Swift) = call `ModelConfiguration(id: "mlx-community/translategemma-4b-it-4bit")` — loads like any MLXLLM model

**Transformers.js v4:**
- Released Feb 10, 2026 as `@huggingface/transformers@next` on NPM
- C++ WebGPU runtime rewrite: 30× faster than WASM for some models
- Runs in browsers, Node.js, Bun, Deno with same code
- 53% smaller default bundle (`transformers.web.js`)
- NOT used in macOS app — relevant only for landing page demo + future Bun server

**ASR fallback chain (final, as of this session):**
```
P1: Qwen3-ASR-0.6B-4bit    (~720MB, default, StreamingInferenceSession-native)
P2: Qwen3-ASR-1.7B-4bit    (~1.6GB)
P3: VoxtralRealtime-4bit   (~3.5GB, opt-in ≥8GB, needs custom adapter)
P4: Parakeet-TDT v2        (~1.2GB)
P5: PythonBackend          (ultimate fallback)
```

**NLP/NER gaps (from agent-12):**
- Zero mlx-community NER models exist — Apple NaturalLanguage.framework is the only native option
- `Qwen3ForcedAlignerModel.swift` already in mlx-audio-swift checkout — just needs wiring (~2 days, P0)
- `facebook/fasttext-language-identification` is CC-BY-NC-4.0 — REJECTED. Use Apple NLLanguageRecognizer.
- GLiNER: no MLX port; ONNX Runtime Swift path is viable (P2)

**Audio pipeline gaps (from agent-13):**
- Overlap-add streaming already implemented: `encoderWindowOverlapSeconds: 1.0`
- Min chunk floor: 1s hard-coded in `STTGenerateParameters` — do not reduce without WER testing
- AUVoiceIO for AEC: OS-provided, zero model cost — add to AudioCaptureManager audio graph
- ACM already handles 44.1kHz → 16kHz conversion via AVAudioConverter
- SRT/VTT export: exists and passes tests
- Regex ITN covers ~85% meeting vocabulary in ~1 day

**VoxtralRealtime blocker:**
- `StreamingInferenceSession` is hardcoded to `Qwen3ASRModel` — needs custom `VoxtralRealtimeStreamingAdapter`
- Medium effort to implement; gate behind ≥8GB RAM + user opt-in

**MossFormer2 clarification:**
- It is speech ENHANCEMENT (mono in → mono out), NOT source separation
- `numSpks=2` in config is internal architecture detail only
- Pipeline position: before ASR (denoising), not after

**HF Transformers version:**
- v5.2.0 is current stable (Feb 2026). v4.x series ended at 4.56.0.
- Local install is stale at 4.56.0 — upgrade with `pip3 install --upgrade transformers`
- NOT used at runtime in EchoPanel (Swift+MLX app)

**Gemma 4:** Does not exist as of 2026-02-26. Community expects Q1–Q2 2026. All current Gemma is Gemma 3 / Gemma 3n.

</technical_details>

<important_files>

- `macapp/MeetingListenerApp/Package.swift`
  - Defines all deps, platform target, Swift tools version
  - Changed: swift-tools-version 6.0→6.2, mlx-audio-swift branch→v0.1.0, added mlx-swift-lm from "2.30.6"
  - URGENT: mlx-swift-lm added as package dep but no products yet used in targets — add MLXLLM/MLXEmbedders products when implementing Week 3

- `docs/research/RESEARCH_MASTER_INDEX.md`
  - NEW: Canonical index of all 20 research docs, decision registry, open questions tracker
  - Key reference for any agent starting new work on this repo

- `docs/DECISIONS.md`
  - DEC-001 through DEC-053 — 53 architectural decisions
  - Most recent (DEC-046→053): NLP/NER gaps + audio pipeline gaps
  - Key decisions for implementation: DEC-031 (never run ASR+LLM simultaneously), DEC-036 (Sortformer primary diarization), DEC-048 (Qwen3-ForcedAligner wiring P0), DEC-050 (AUVoiceIO for AEC)

- `docs/WORKLOG_TICKETS.md`
  - TCK-20260225-001: Native Swift ASR + Backend Migration (P0, IN_PROGRESS) — main implementation ticket
  - TCK-20260226-001: Wave 3 research sprint (DONE)

- `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`
  - Q1/Q3/Q4/Q6/Q7 fully resolved; Q5/Q8/Q9/Q10 still open
  - Q5: first-run UX product decision; Q8: diarization accuracy parity; Q9: ANE vs GPU profiling; Q10: HF token in production

- `docs/research/AUDIO_PIPELINE_GAPS_2026-02-26.md` (479 lines)
  - Gap 1 (word timestamps): Qwen3ForcedAlignerModel in checkout, just needs wiring — P0
  - Gap 4 (audio preprocessing): AUVoiceIO for AEC, ACM handles sample rate
  - Critical implementation guide for TCK-20260225-001

- `docs/research/NLP_NER_PIPELINE_RESEARCH_2026-02-26.md` (556 lines)
  - 10-component gap analysis; fasttext rejected (NC license); GLiNER ONNX path; Apple NLP defaults

- `docs/research/GEMMA4_TRANSFORMERS_RESEARCH_2026-02-26.md`
  - Sections 2+3 added in this session: TranslateGemma full integration analysis + Transformers.js v4
  - Path B (native Swift): `gemma3` model type already registered → zero new code

- `Sources/ASR/NativeMLXBackend.swift`
  - Primary native ASR implementation
  - Still needs: Parakeet P4, VoxtralRealtime P3 adapter, Qwen3-ForcedAligner wiring

- `docs/audit/full-repo-review-20260226.md`
  - Most recent comprehensive audit (2026-02-26) — high leverage for Audit-Doc Work Planner task
  - NOT YET read/analyzed — this is the chosen doc for Steps 2–9

</important_files>

<next_steps>

**Immediate — Audit-Doc Work Planner (in progress, Steps 2–9 not done):**

The user triggered the full Audit-Doc Work Planner prompt. Steps 0–1 are complete:
- Step 0 (orient): ✅ Done — Swift 6.2, macOS 15, Apple Silicon, FastAPI fallback, 63 Swift source files, 19 test files
- Step 1 (inventory): ✅ Done — 100+ audit docs found, catalogued

Steps still needed:
1. **Step 2** — Pick ONE doc to focus on (best candidate: `docs/audit/full-repo-review-20260226.md` — most recent comprehensive repo audit, 2026-02-26, cross-cutting)
2. **Step 3** — Read + map the chosen doc (outline, key claims tagged Observed/Inferred/Unknown, open questions)
3. **Step 4** — Translate into prioritized worklist (explicit + implicit items with full metadata)
4. **Step 5** — PR Plan (implementation units in dependency order)
5. **Step 6** — Research TODOs (external validation needed)
6. **Final deliverable** — Single markdown report with all 9 sections

**Implementation queue (TCK-20260225-001, Week 1–4):**
- Week 1: FluidAudio VAD using `VadManager` actor API; wire Qwen3-ForcedAligner (~2 days P0)
- Week 1: Add `AUVoiceIO` to AudioCaptureManager for AEC
- Week 1: Add Parakeet P4 + VoxtralRealtime P3 (with adapter) to NativeMLXBackend
- Week 2: MossFormer2 pre-ASR denoising pipeline
- Week 2: SortformerModel replace FluidAudio diarization wiring
- Week 3: Add MLXLLM products to Package.swift targets; wire nomic-embed-v2-moe
- Week 3: Gemma 3n-E2B A/B benchmark vs Qwen2.5-1.5B
- Week 4: Sequential phase scheduler + `MLX.GPU.clearCache()` hook
- Week 4: Hardware tier detection (16GB → Qwen2.5-7B unlock)

**Open questions still blocking:**
- Q5: First-run model download UX (product decision — show progress UI or silent background?)
- Q8: Diarization accuracy parity benchmarks (FluidAudio vs Sortformer on AMI test set)
- Q9: ANE vs GPU profiling (needs Instruments run on real hardware)
- Q10: HF token distribution in production app (rate limits, bundling policy)

</next_steps>