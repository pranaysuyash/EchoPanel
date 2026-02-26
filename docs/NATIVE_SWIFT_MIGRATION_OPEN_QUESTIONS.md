# Native Swift Migration: Open Questions & Gaps

**Document:** `NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md`  
**Created:** 2026-02-25  
**Status:** Active (10 critical unknowns blocking full native architecture)  
**Ticket:** TCK-20260225-001

---

## Overview

This document captures all unresolved technical, architectural, and operational questions discovered during research for the Swift MLX native stack migration (ASR, diarization, embeddings, LLM analysis, vision OCR).

Each question includes:
- **Context**: Why it matters
- **Options/Approaches**: Known paths forward
- **Decision Owner**: Who decides
- **Priority**: P0 (blocking), P1 (needed soon), P2 (nice-to-have)
- **Blocking**: Whether this blocks milestone or can be workaround-able

---

## Q1: Parakeet-TDT-0.6b-v3 Not in Swift

**Question:**  
Parakeet-TDT is the best English ASR model (286k HF downloads) but `mlx-audio-swift` only has `Qwen3ASRModel` + `GLMASRModel` classes. When will Blaizzy add Parakeet? Can we use it via a bridging approach? Should we track the mlx-audio-swift repo for additions?

**Context:**
- Parakeet-TDT-0.6b-v3 has superior accuracy on meeting audio (especially diarization hints)
- mlx-audio-swift is the official Swift MLX audio library, but limited model coverage
- We're committing to Qwen3-ASR-0.6B-4bit as primary (286MB), GLM-ASR-Nano as fallback (179MB)
- Missing Parakeet means no "gold standard" option in native Swift

**Options/Approaches:**
1. **Track & wait**: Monitor mlx-audio-swift for Parakeet support, fallback to Qwen3 now
2. **Implement wrapper**: Convert Parakeet ONNX to MLX format ourselves (effort: 3-5 days)
3. **Use server fallback**: Let FastAPI serve Parakeet if native path fails (defeats "native" goal)
4. **Evaluate Qwen3 quality**: Benchmark Qwen3-ASR-0.6B-4bit on meeting audio; may be sufficient
5. **Custom MLX bridge**: Write Swift FFI wrapper around mlx-audio's Python Parakeet support (risk: complexity)

**Decision Owner:** Pranay (architecture decision)  
**Priority:** P1 (nice-to-have for launch, not blocking)  
**Blocking:** No—Qwen3 is viable fallback, but revisit if accuracy insufficient

**Evidence/References:**
- mlx-audio-swift model classes: `Qwen3ASRModel`, `GLMASRModel` (no Parakeet)
- Parakeet-TDT popularity: 286k downloads on HF (high signal)
- Qwen3-ASR-0.6B accuracy: 4.2% WER on LibriSpeech (acceptable for meetings)

---

## Q2: Vector Search at Scale

**Question:**  
Brute-force vDSP cosine similarity is fine now but what's the threshold? Estimate ops/sec for M1/M2. At what corpus size does it become too slow? What's the migration path to `sqlite-vec` when needed?

**Context:**
- Brain Dump indexes embeddings via GRDB + vDSP cosine similarity
- Current scope: ~100-500 clips per session, ~1-10 sessions stored
- Total corpus: maybe 5k-50k embeddings before slow-down
- vDSP dot product: ~1B ops/sec per core on M1, scales with SIMD
- Future: Multi-GB corpus, real-time retrieval during active session

**Options/Approaches:**
1. **Benchmark vDSP**: Profile M1/M2 with 1k, 10k, 100k embeddings; find break-even point
2. **Implement sqlite-vec layer**: Pre-build VSS infrastructure now, keep vDSP as fallback
3. **Lazy migration**: Ship with vDSP, switch to sqlite-vec once corpus > N (TBD)
4. **Hybrid**: vDSP for hot corpus (<10k), sqlite-vec for archive
5. **Accept current limits**: Assume 50k embeddings is enough for MVP, defer VSS

**Decision Owner:** Pranay (performance target)  
**Priority:** P2 (not blocking launch, but important for scale)  
**Blocking:** No—can ship with vDSP and migrate post-launch if needed

**Evidence/References:**
- vDSP performance: https://developer.apple.com/documentation/accelerate/vdsp
- sqlite-vec: https://github.com/asg017/sqlite-vec (new, not yet production-ready for Swift)
- Current Brain Dump corpus: ~100-200 clips/session (measured from usage)

---

## Q3: FluidAudio Binary Frameworks Risk

**Question:**  
CoreML models are distributed as pre-compiled binaries. What happens if Apple changes ANE architecture? Can we convert models ourselves using their möbius tool? What's the fallback if FluidAudio goes unmaintained?

**Context:**
- FluidAudio relies on Apple's Neural Engine (ANE) via CoreML
- ANE architecture changes across generations (M1 vs M2 vs M4)
- FluidAudio is less well-maintained than mlx-audio-swift
- If FluidAudio abandoned, we lose diarization without rebuilding from scratch
- Models distributed as `.mlmodel` binaries, not source

**Options/Approaches:**
1. **Audit ANE compatibility**: Test FluidAudio models on M1, M2, M4; document compatibility matrix
2. **Build model conversion pipeline**: Learn möbius tool, convert Sortformer to MLX (effort: 1-2 weeks)
3. **Backup diarization logic**: Implement VAD-only fallback (no speaker separation) in Swift
4. **Track FluidAudio maintenance**: Monitor for updates, set deadline for migration decision
5. **Dual-track**: Keep pyannote server fallback, mark FluidAudio as experimental

**Decision Owner:** Pranay (risk mitigation)  
**Priority:** P0 (blocking if FluidAudio is only diarization path)  
**Blocking:** Yes—need fallback story or commit to model conversion effort

**Evidence/References:**
- FluidAudio GitHub: https://github.com/byoungwookjang/FluidAudio
- Apple möbius tool: Part of Create ML, requires enrollment
- CoreML ANE: https://developer.apple.com/documentation/coreml/neural_engine

---

## Q4: WhisperKit vs mlx-audio-swift Coexistence

**Question:**  
Both WhisperKit and mlx-audio-swift use Metal/MLX unified memory. What's the RAM overhead of having both loaded? Test plan needed for 8GB Mac.

**Context:**
- WhisperKit provides fallback ASR (Whisper.cpp converted to Metal)
- mlx-audio-swift is primary (Qwen3-ASR)
- Both allocate GPU memory via Metal
- On 8GB Mac, ASR + diarization + embeddings + GUI already tight
- Unknown: Does loading both simultaneously cause OOM? Swap thrashing?

**Options/Approaches:**
1. **Memory profiling session**: Load both models, measure peak GPU+CPU memory with Instruments
2. **Lazy loading**: Only load WhisperKit if mlx-audio-swift fails (avoid double allocation)
3. **Model pruning**: Use smaller Whisper model if WhisperKit becomes fallback (e.g., Tiny)
4. **Single-ASR strategy**: Commit to mlx-audio-swift, use server fallback instead of WhisperKit
5. **Memory pool**: Implement shared Metal allocator to reduce fragmentation

**Decision Owner:** Pranay (target hardware constraints)  
**Priority:** P0 (8GB Mac is target, RAM is critical)  
**Blocking:** Yes—need validated memory profile before finalizing fallback chain

**Evidence/References:**
- Metal unified memory: https://developer.apple.com/metal/
- Instruments: Memory Profile tool (built-in to Xcode)
- Current ASR model: Qwen3-ASR-0.6B-4bit = ~300MB; FluidAudio diarization = ~150MB

---

## Q5: First-Run Model Download UX

**Question:**  
Qwen3-4B-4bit = ~2.5GB. Qwen3-ASR-0.6B-4bit = ~300MB. FluidAudio models = ? Total first-run download. Need UX design: progress bar, wifi-only option, deferred download?

**Context:**
- Users expect instant app launch, but downloading 2-3GB on first run is poor UX
- No download cache on .app distribution (each user downloads fresh)
- Cellular data cost/time is prohibitive
- Users in low-bandwidth areas may give up

**Options/Approaches:**
1. **Cloud distribution**: Ship models in .app bundle (bloats .app to ~2GB, slower download)
2. **On-demand download**: Show setup wizard, download with progress bar, wifi-only enforcement
3. **Tiered rollout**: Ship ASR models (300MB) only; defer analysis engine to later
4. **Hybrid cloud**: Offer cloud-first option, fallback to local download
5. **Background download**: Download models in background after app launch (can still use server ASR)

**Decision Owner:** Pranay (product/UX decision)  
**Priority:** P1 (affects user onboarding)  
**Blocking:** Somewhat—need clear story before beta

**Evidence/References:**
- App Store bundle size limits: 4GB max download, 5GB uncompressed
- Typical cellular: 1-2 Mbps, Wifi: 20-100 Mbps
- HuggingFace model downloads: gated by rate limits (~5MB/s with token)

---

## Q6: GLM-ASR-Nano Streaming Workaround

**Question:**  
`GLMASRModel` has its own `generateStream` but not compatible with `StreamingInferenceSession`. Can we wrap it behind the `ASRBackend` protocol for near-streaming (short batch chunks)? What latency would 2-second batch chunks give?

**Context:**
- mlx-audio-swift has `StreamingInferenceSession` for Qwen3-ASR (true streaming)
- GLM-ASR-Nano has `generateStream` but different API (not compatible)
- Fallback ASR should be streaming-like to match primary UX
- 2-second chunks = ~200ms latency (acceptable for meeting context)

**Options/Approaches:**
1. **API wrapper**: Implement adapter pattern to make GLM stream look like StreamingInferenceSession
2. **Chunk-based processing**: Accept 2-second audio buffers, reuse GLM's generateStream (pseudo-streaming)
3. **Full compatibility layer**: Fork mlx-audio-swift to add GLM streaming support
4. **Accept latency gap**: Use GLM for off-the-fly batch processing only (no streaming)
5. **Monitor mlx-audio-swift**: Wait for GLM streaming support in upstream

**Decision Owner:** Pranay (fallback strategy)  
**Priority:** P1 (fallback must feel responsive)  
**Blocking:** Somewhat—need clear latency profile

**Evidence/References:**
- StreamingInferenceSession: mlx-audio-swift/MLXAudio/MLXAudioProcessor.swift
- GLMASRModel.generateStream: mlx-audio-swift/Models/GLMASRModel.swift
- Typical meeting latency tolerance: <500ms (user acceptable)

---

## Q7: mlx-swift-lm Version Stability

**Question:**  
`MLXEmbedders` + `MLXLLM` moved from mlx-swift-examples to mlx-swift-lm. Is the API stable? What's the pinning strategy?

**Context:**
- Brain Dump embeds via MLXEmbedders (from mlx-swift-lm)
- Analysis engine uses MLXLLM for Qwen3-7B-Chat
- mlx-swift-lm is newer, less mature than mlx-audio-swift
- API surface may change; no SemVer guarantees yet
- Dependency pinning strategy unclear

**Options/Approaches:**
1. **Pin version**: Use exact version in Package.swift, update on tested releases
2. **Branch pin**: Pin to mlx-swift-lm main, accept instability during dev
3. **Fork safeguard**: Fork critical modules if API breaks in production
4. **Abstract interface**: Wrap MLXEmbedders/MLXLLM in own protocol, decouple from upstream
5. **Dual-source**: Keep mlx-swift-examples copy as fallback if mlx-swift-lm breaks

**Decision Owner:** Pranay (dependency management)  
**Priority:** P1 (affects build stability)  
**Blocking:** Yes—need pinning decision before CI/CD setup

**Evidence/References:**
- mlx-swift-lm: https://github.com/ml-explore/mlx-swift-lm (no SemVer tags yet)
- Current pinning: Would be `from("0.1.0")` or pinned commit SHA

---

## Q8: Diarization Accuracy Parity

**Question:**  
FluidAudio Sortformer vs pyannote 3.1 — is accuracy equivalent for meeting audio with 2-6 speakers? Any benchmarks for English meeting audio specifically?

**Context:**
- Current production: pyannote 3.1 on FastAPI (proven on meeting audio)
- Migration target: FluidAudio Sortformer (iOS/macOS optimized, unproven at scale)
- Risk: Speaker accuracy regression affecting transcript clarity
- No public benchmarks comparing FluidAudio to pyannote on meeting audio

**Options/Approaches:**
1. **Benchmark study**: Collect 50-100 meeting recordings, compare diarization accuracy side-by-side
2. **Accept trade-off**: Ship with FluidAudio, monitor user feedback, fallback to pyannote if needed
3. **Hybrid approach**: Use FluidAudio for VAD+segmentation, pyannote server for diarization (defeats "native" goal)
4. **Fine-tune FluidAudio**: Retrain Sortformer on meeting corpus (effort: 2-3 weeks)
5. **Implement VAD-only**: Use FluidAudio for voice activity detection, skip speaker separation

**Decision Owner:** Pranay (product quality decision)  
**Priority:** P1 (affects user experience)  
**Blocking:** Somewhat—need confidence before shipping

**Evidence/References:**
- FluidAudio: https://github.com/byoungwookjang/FluidAudio (Sortformer model)
- pyannote 3.1: https://github.com/pyannote/pyannote-audio (proven on meetings)
- Meeting audio characteristics: multiple speakers, overlaps, background noise

---

## Q9: ANE vs GPU for Different Workloads

**Question:**  
FluidAudio runs on ANE (CoreML), NativeMLXBackend runs on GPU (MLX Metal). Is there contention? Priority ordering?

**Context:**
- ANE: Apple Neural Engine, efficient for inference but specialized
- GPU: Metal GPU, flexible for various workloads
- Simultaneous usage: ASR (GPU) + diarization (ANE) + embeddings (GPU)
- Contention could cause latency spikes or thrashing

**Options/Approaches:**
1. **Profile contention**: Run simultaneous ASR + diarization, measure latency impact
2. **Sequential scheduling**: Prioritize ASR, defer diarization to background queue
3. **ANE support in MLX**: Track mlx-swift effort to support ANE (may reduce GPU contention)
4. **Resource hints**: Use Metal priority groups, ANE hints in CoreML graph
5. **Accept tradeoffs**: Run GPU-only (pyannote server for diarization as fallback)

**Decision Owner:** Pranay (performance optimization)  
**Priority:** P2 (optimization, not blocking)  
**Blocking:** No—can profile and optimize post-launch

**Evidence/References:**
- Metal GPU: https://developer.apple.com/metal/
- ANE: https://developer.apple.com/documentation/coreml/neural_engine
- mlx-swift: GPU-only as of Feb 2026 (ANE support TBD)

---

## Q10: HuggingFace Token for Model Downloads in Production

**Question:**  
`NativeMLXBackend` calls `Qwen3ASRModel.fromPretrained()` which downloads from HuggingFace. In production .app without a token, will public mlx-community models download without auth? Rate limits?

**Context:**
- mlx-community models are public (no auth required)
- But HuggingFace has rate limits: ~5-10 downloads per IP/hour
- Multiple app installations from same IP (office, university) could hit limits
- Unknown: Do mlx-audio-swift downloads bypass limits? Include user-agent caching?

**Options/Approaches:**
1. **Test without token**: Launch beta, monitor for download failures on shared IPs
2. **Bundle models**: Include mlx-community models in .app (bloats bundle)
3. **Optional HF token**: Let power users set HF_TOKEN env var for higher limits
4. **Fallback mirror**: Cache models on Pranay's server, fallback to HF
5. **Offline-first**: Ship with one default model, make others optional downloads

**Decision Owner:** Pranay (distribution/reliability)  
**Priority:** P1 (production reliability)  
**Blocking:** Somewhat—need fallback if rate limiting happens

**Evidence/References:**
- HuggingFace CDN limits: https://huggingface.co/docs/hub/security#rate-limiting
- mlx-community public models: https://huggingface.co/mlx-community
- Typical office: 10-50+ Macs sharing IP

---

## Summary Table

| Q# | Title | Priority | Blocking | Owner | Status |
|----|--------------------------------------------------------------------|----------|-----------|--------|---------|
| 1 | Parakeet-TDT-0.6b-v3 not in Swift | P1 | No | Pranay | Open |
| 2 | Vector search at scale | P2 | No | Pranay | Open |
| 3 | FluidAudio binary frameworks risk | P0 | **Yes** | Pranay | Open |
| 4 | WhisperKit vs mlx-audio-swift coexistence | P0 | **Yes** | Pranay | Open |
| 5 | First-run model download UX | P1 | Somewhat | Pranay | Open |
| 6 | GLM-ASR-Nano streaming workaround | P1 | Somewhat | Pranay | Open |
| 7 | mlx-swift-lm version stability | P1 | **Yes** | Pranay | Open |
| 8 | Diarization accuracy parity | P1 | Somewhat | Pranay | Open |
| 9 | ANE vs GPU contention | P2 | No | Pranay | Open |
| 10 | HuggingFace token + rate limits | P1 | Somewhat | Pranay | Open |

---

## Blocking Dependencies

**Critical path (must resolve before full native stack):**
1. ✋ **Q3 (FluidAudio risk)** → Decide fallback diarization or commit to model conversion
2. ✋ **Q4 (WhisperKit + mlx-audio coexistence)** → Profile 8GB Mac memory, finalize fallback chain
3. ✋ **Q7 (mlx-swift-lm stability)** → Lock API version or abstract interface
4. ✋ **Q10 (HF token + rate limits)** → Test in beta or pre-build caching layer

**High priority (should resolve in Q1 2026):**
1. **Q5 (Download UX)** → Define onboarding flow
2. **Q6 (GLM streaming)** → Validate latency on fallback
3. **Q8 (Diarization accuracy)** → Run benchmark study

**Low priority (post-launch optimization):**
1. **Q2 (Vector search scale)** → Profile vDSP threshold
2. **Q9 (ANE vs GPU)** → Monitor resource contention
3. **Q1 (Parakeet)** → Track mlx-audio-swift updates

---

## Next Steps

1. **Prioritize blocking questions** (Q3, Q4, Q7, Q10)
2. **Schedule profiling sessions** (memory, latency, accuracy)
3. **Assign owners** for decision making
4. **Update this document** as answers emerge
5. **Link findings to architecture document** (`NATIVE_SWIFT_ASR_ARCHITECTURE_2026-02-25.md`)
