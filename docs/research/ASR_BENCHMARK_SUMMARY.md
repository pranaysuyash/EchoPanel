# ASR Model Decision Summary for EchoPanel

## TL;DR: Recommendations

| Decision | Model | Rationale |
|----------|-------|-----------|
| 🟢 **PRIMARY (Now)** | Qwen3-ASR-0.6B-4bit | 5.8% WER, RTF<0.1 on M1, streaming, 1.2GB memory |
| 🟡 **FALLBACK** | Qwen3-ASR-1.7B-8bit | 4.2% WER, but needs M2/M3 + 16GB RAM |
| 🟢 **FUTURE (Q2 2026)** | Parakeet-TDT-0.6B-v3 | 4.8% WER, 10x faster than Whisper, needs validation |
| 🔴 **NOT RECOMMENDED** | Whisper small.en | No streaming, RTF 0.4-0.6 (too slow) |
| 🔴 **NOT RECOMMENDED** | distil-small.en | 12% WER (poor accuracy) |
| 🟡 **ALTERNATIVE** | WhisperKit (Swift) | If all-Swift app needed; lower accuracy (8.4-12% WER) |

---

## Quick Facts

### Qwen3-ASR-0.6B-4bit (CURRENT CHOICE) ⭐
- **WER:** 5.8% (LibriSpeech)
- **Speed:** RTF < 0.1 on M1/M2 (faster than real-time)
- **Memory:** 1.2GB (fits M1 with 8GB)
- **Streaming:** ✅ Yes (real-time transcription)
- **Languages:** 52 languages + 22 Chinese dialects
- **Status:** ✅ Already integrated in EchoPanel

### Parakeet-TDT-0.6B-v3 (WATCH THIS) 🚀
- **WER:** 4.8% (1% better than Qwen3)
- **Speed:** RTF ~0.18-0.25 on Apple Silicon (estimated; not published)
- **Streaming:** ✅ Yes, optimized for low-latency first-token (<150ms)
- **Languages:** 25 EU languages only (no Mandarin/Cantonese)
- **Status:** ⚠️ New (Sept 2025); not yet validated on Apple Silicon
- **Next step:** Benchmark on real meeting recordings (Q2 2026)

### Key Meeting Audio Challenges

| Challenge | Status | Solution |
|-----------|--------|----------|
| Multiple speakers | ❌ No model has diarization | Use external: Sortformer v2.1 |
| Overlapping speech | ⚠️ Models transcribe but lose speaker boundaries | Combine with diarization |
| Background noise | ✅ All handle OK | Parakeet > Qwen3 ≈ Whisper |
| Domain vocabulary | ⚠️ Models may miss rare terms | Post-process with LLM correction |
| Streaming latency | ✅ Qwen3/Parakeet good | Parakeet: 50-150ms, Qwen3: 200-400ms |

---

## Decision Timeline

### ✅ Now (Q1 2026)
- Keep **Qwen3-ASR-0.6B-4bit** as primary
- No code changes needed (already integrated)
- Complement with Sortformer for speaker diarization

### 🔄 Q2 2026
- Benchmark Parakeet-TDT-0.6B-v3 on 10-15 real EchoPanel meeting recordings
- Measure: WER, RTF, first-token latency, memory, CPU load
- Pass criteria: WER < 5.0%, RTF < 0.2, first-token < 150ms

### 📋 Q3 2026
- **If Parakeet passes:** Create parallel code path for opt-in users
- **If Parakeet fails:** Stay with Qwen3; revisit in Q4 2026

---

## Why Each Model Was Ruled Out

| Model | Why Not? |
|-------|----------|
| **Whisper-small.en** | RTF 0.4-0.6 (no streaming) = unacceptable for real-time UX |
| **distil-small.en** | 12% WER (1 error per 8 words) = poor quality |
| **Qwen3-1.7B** | Requires M2/M3 + 16GB; 5.8% (0.6B) good enough for live |
| **WhisperKit (primary)** | Lower accuracy (8.4% for large); limited languages |
| **Parakeet (now)** | Not validated on Apple Silicon; too risky without benchmarks |

---

## Meeting Audio: Special Considerations

### Separate Tools Needed (ASR + Speaker Diarization)
```
EchoPanel Architecture:
┌─────────────────────────┐
│  Audio Input (meeting)  │
└────────────┬────────────┘
             │
      ┌──────┴──────┐
      ▼             ▼
   ASR Model    Diarization Model
  (Qwen3-0.6B)  (Sortformer v2.1)
      │             │
      └──────┬──────┘
             ▼
   Transcription + Speaker Labels
             │
             ▼
   Post-processing (domain vocab correction, LLM cleanup)
             │
             ▼
   Final Transcript (human-readable, speaker-attributed)
```

### Recommended Complementary Tools
1. **Speaker Diarization:** `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp32`
2. **Post-processing LLM:** Qwen2.5-7B, Llama 3.1-8B, or local ollama
3. **Domain Vocabulary:** Build custom term dictionary per team/org

---

## Sources

**Benchmark documents:**
- Full analysis: `docs/research/ASR_BENCHMARK_COMPARISON_2026-02-26.md`

**Model papers:**
- Parakeet & Canary: https://arxiv.org/abs/2509.14128 (Sept 2025)
- Whisper: https://arxiv.org/abs/2212.04356 (Dec 2022)
- Distil-Whisper: https://arxiv.org/abs/2311.00430 (Nov 2023)

**Model cards & repos:**
- Qwen3-ASR: https://huggingface.co/Qwen/Qwen3-ASR-0.6B
- Parakeet-TDT: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- MLX Audio: https://github.com/Blaizzy/mlx-audio
- WhisperKit: https://github.com/argmaxinc/WhisperKit

---

## Action Items for EchoPanel Team

### Immediate (Q1 2026)
- [ ] Review this summary with team
- [ ] Confirm Qwen3-0.6B remains appropriate for current user base
- [ ] Plan Parakeet evaluation (Q2)

### Q2 2026 (If proceeding with Parakeet eval)
- [ ] Collect 10-15 representative meeting recordings
- [ ] Generate ground-truth transcriptions
- [ ] Benchmark Parakeet-TDT-0.6B-v3 on M1/M2 hardware
- [ ] Compare metrics head-to-head with Qwen3-0.6B
- [ ] Make go/no-go decision for Q3 migration

### Q3 2026+ (If Parakeet passes)
- [ ] Integrate parallel code path for Parakeet
- [ ] Gradual rollout to opt-in beta users
- [ ] Monitor WER, latency, memory in production
- [ ] Collect user feedback on transcription quality

---

**Last updated:** 2026-02-26  
**Status:** Ready for team review  
**Owner:** ASR Benchmark Research Task
