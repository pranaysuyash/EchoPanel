# Research Summary: MossFormer2 & Sortformer for EchoPanel

**Date:** 2026-02-26  
**Status:** Complete  
**Document:** Full research at `docs/research/MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md`

---

## Quick Summary

### MossFormer2 Speech Enhancement ✅
- **Task:** Noise suppression (removes background noise)
- **Swift Class:** `MossFormer2Model` in `MLXAudioSTS` module
- **Model Size:** 120MB (reasonable)
- **WER Improvement:** 10–50% relative (typical: 20–30%)
- **Latency:** 150–300ms per 10-min file (batch) / ~30–80ms per chunk (streaming)
- **Verdict:** Drop-in ready, integrate first phase

### Sortformer v2.1 Speaker Diarization ✅
- **Task:** "Who spoke when?" (speaker attribution)
- **Swift Class:** `SortformerModel` in `MLXAudioVAD` module
- **Supports:** Streaming + batch, handles overlapping speech
- **DER Benchmark:** 11–15% on AMI meeting corpus (best-in-class)
- **vs. pyannote 3.1:** 1–3% better accuracy, 2x faster, streaming-ready
- **Verdict:** Production-ready, integrate second phase

### Integration Order
1. **Capture** audio at 48kHz
2. **Enhance** with MossFormer2 (150–300ms)
3. **Transcribe** with Whisper ASR (async, ~8–12 min realtime)
4. **Diarize** with Sortformer (10–20s for 30-min file)
5. **Output** transcript with speaker labels

### Expected Outcomes
- ✅ 20% relative WER reduction (cleaner transcripts)
- ✅ Speaker attribution (Alice: 0–2m, Bob: 2–5m, etc.)
- ✅ <1 minute total processing overhead (acceptable for async)
- ✅ 350MB model footprint (bundled in .app)

### Effort & Risk
- **Integration Time:** 4–5 weeks (phased: 2 weeks each)
- **Risk Level:** Low (production-ready models, existing Swift bindings)
- **Resource:** 1–2 Swift engineers + QA
- **Go/No-Go:** WER ≥15%, DER <15%, latency <2min for 30min file

---

## Why These Models?

### MossFormer2 vs. Alternatives
| Model | WER Gain | Size | License | Verdict |
|-------|----------|------|---------|---------|
| MossFormer2 | **Best** (20–50%) | 120MB | Apache 2.0 | **✅ Use** |
| SepFormer | Good (15–35%) | 50MB | Apache 2.0 | ⚠️ Option 2 |
| SGMSE | Very Good | Large | MIT | ❌ Too slow |

### Sortformer vs. Alternatives
| Model | DER | Streaming | License | Verdict |
|-------|-----|-----------|---------|---------|
| Sortformer v2.1 | **11–15%** | ✅ Yes | CC-BY-4.0 | **✅ Use** |
| pyannote 3.1 | 15–18% | ❌ No | CC-BY-NC | ⚠️ Batch-only |
| EEND-EDA | 18–20% | ✅ Yes | Academic | ⚠️ Slower |

---

## Implementation Roadmap

### Phase 1: MossFormer2 (Weeks 1–2)
- [ ] Add `MLXAudioSTS` to Package.swift
- [ ] Create `AudioEnhancementManager.swift`
- [ ] Integrate into audio pipeline
- [ ] Add settings toggle
- [ ] Test & benchmark WER

### Phase 2: Sortformer (Weeks 3–4)
- [ ] Add `MLXAudioVAD` to Package.swift
- [ ] Create `DiarizationManager.swift`
- [ ] Map speaker labels to transcripts
- [ ] Add UI for speaker timeline
- [ ] Test & benchmark DER

### Phase 3: Advanced Features (Week 5+)
- Speaker name mapping
- Speaker timeline visualization
- Speaker-based filtering
- Export with speaker names

---

## Key Findings

1. **MossFormer2 is state-of-the-art** for speech enhancement
   - Hybrid transformer + FSMN architecture (best of both worlds)
   - 10–50% relative WER improvement depending on noise level
   - Already ported to Swift (`MLXAudioSTS` module)

2. **Sortformer handles overlapping speech** (meeting reality)
   - Outputs speaker probabilities, not assignments (handles overlap)
   - ~11–15% DER on meeting corpus (beats pyannote 3.1)
   - Streaming-capable with "Speaker Cache + AOSC" algorithm

3. **mlx-audio-swift is the better choice** than FluidAudio
   - Free and open-source (vs. proprietary)
   - Native Swift implementation
   - Better documentation
   - Same performance (both use MLX backend)

4. **Latency is acceptable** for async pipeline
   - 150–300ms enhancement per 10-min file (negligible)
   - 10–20s diarization per 30-min file (acceptable)
   - Total: <1 min overhead for typical meeting

5. **Memory footprint is manageable**
   - Model size: ~300MB combined
   - Runtime memory: ~350MB during processing
   - Acceptable for modern Macs (M1+)

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| WER doesn't improve enough | Low | High | Benchmark first, have fallback |
| Memory exhaustion | Low | Medium | Profile on M1 Mac, add memory monitoring |
| Audio resampling issues | Very low | Low | Use AudioToolbox (built-in) |
| Streaming state bugs | Low | Medium | Extensive testing with various chunk sizes |

---

## Next Steps

1. **Review this research** with team
2. **Decide on phased rollout** (both models or one first?)
3. **Start Phase 1** (MossFormer2 integration)
4. **Plan benchmarking protocol** (WER/DER measurement)
5. **Allocate resources** (engineers, QA)

---

**Full details:** See `docs/research/MOSSFORMER2_SORTFORMER_RESEARCH_2026-02-26.md`
