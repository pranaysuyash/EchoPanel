# Discussion: Real-Time Transcription Overload Analysis

**Date:** 2026-02-14  
**Participants:** Pranay (Product Owner), AI Agent  
**Status:** Analysis Complete - Action Items Identified

---

## Part 1: The Core Question

**Pranay:** "are there no apps that do real time transcription? how do they process it?"

### Answer: Yes, Many Apps Do Real-Time Transcription

| App | Platform | Approach |
|-----|----------|----------|
| Otter.ai | Web, iOS, Android | Cloud ASR with speaker diarization |
| Apple Live Captions | iOS/macOS | On-device Neural Engine |
| Google Live Transcribe | Android | On-device for supported languages |
| Whisper Streaming | Cross-platform | Local GPU or cloud |
| Descript | Desktop | Local + cloud hybrid |

### How They Process It (The Pipeline)

```
Audio Capture → VAD (Voice Activity Detection) → ASR Model → Text Output
      ↑                                              ↓
   100ms-1s chunks                            Post-processing
```

**Key Techniques:**
1. **Sliding window** - Process overlapping windows (e.g., 30s sliding)
2. **Endpointing** - Detect pauses to commit finalized text
3. **Two-pass** - Fast first pass for display, refined second pass for final
4. **Streaming architectures** - RNN-T, CTC models that output incrementally

---

## Part 2: Documentation Requirement

**Pranay:** "any discussion that happens has to be documented"

**Principle Established:** All technical discussions affecting product decisions must be archived.

---

## Part 3: The Overload Problem

**Pranay:** "we are failing to get the realtime stuff working, gets overloaded and frames being dropped"

### Investigation Results

#### Hardware Context
- **Machine:** Mac M3 Max, 96GB RAM (very high-end)
- **Model:** base (faster-whisper)
- **Expected RTF:** < 0.2 (5x faster than real-time)
- **Actual:** Frame drops occurring

#### Root Cause Discovered

**The Smoking Gun:** faster-whisper forces CPU on macOS:

```python
# server/services/provider_faster_whisper.py:84-88
if device == "auto" and platform.system() == "Darwin":
    device = "cpu"  # ← M3 Max GPU sitting idle!
elif device in {"mps", "metal"}:
    device = "cpu"
```

**Why:** CTranslate2 (faster-whisper's backend) doesn't support Metal/MPS.

### Provider Comparison on macOS

| Provider | Metal/GPU | Speed on M3 Max | Status |
|----------|-----------|-----------------|--------|
| faster-whisper | ❌ CPU only | ~0.5-1.0x RTF | **Currently Used** |
| whisper.cpp | ✅ Metal | ~2-5x RTF | Available, Recommended |
| voxtral_realtime | ✅ Metal | ~3-8x RTF | Available, Needs Opt-in |

### Audit Findings Summary

From comprehensive audit review:

1. **asr-streaming-model-matrix-20260213.md:**
   - `base.en` + CPU = marginal real-time performance
   - `tiny.en` + Metal = reliable real-time
   - RTF scales linearly with model size on CPU

2. **asr-provider-performance-20260211.md:**
   - faster-whisper uses `_infer_lock` (serialized inference)
   - Multiple sources compound the problem
   - Voxtral subprocess-per-chunk is broken

3. **streaming-reliability-dual-pipeline-20260210.md:**
   - Client doesn't pause on server overload
   - Queue sizing is time-based (2s) but chunks are 2-4s
   - Recording lane exists for lossless capture

---

## Part 4: HF Pro Usage Clarification

**Pranay:** "hf pro to not only use cloud models but test local models, becuase i dont plan to launch cloud models as of now"

### HF Pro Strategy (Local Models Only)

| Use Case | How HF Pro Helps |
|----------|------------------|
| Download large models | Faster download, no rate limits |
| Test SOTA models | Access gated models (Voxtral, etc.) |
| Model research | Use HF Hub for model comparison |
| **NOT** cloud inference | Staying local-only per product decision |

### SOTA Models to Test with HF Pro

| Model | Size | Real-Time? | Access |
|-------|------|------------|--------|
| distil-whisper/distil-large-v3 | 756M | ✅ Yes | Public |
| voxtral/Voxtral-Mini-4B-Realtime | 4B | ✅ Yes | **Gated** - needs HF Pro |
| voxtral/Voxtral-Small-8B-Realtime | 8B | ✅ Yes | **Gated** - needs HF Pro |
| openai/whisper-large-v3-turbo | 809M | ⚠️ Borderline | Public |

---

## Part 5: Action Items

### Immediate (Today)

1. **Switch to whisper.cpp for Metal GPU support:**
   ```bash
   export ECHOPANEL_ASR_PROVIDER=whisper_cpp
   export ECHOPANEL_WHISPER_MODEL=base.en
   export ECHOPANEL_WHISPER_DEVICE=gpu
   export ECHOPANEL_WHISPER_COMPUTE=q5_0
   ```

2. **Verify whisper.cpp is available:**
   ```bash
   python -c "from server.services.provider_whisper_cpp import WhisperCppProvider; print(WhisperCppProvider.is_available)"
   ```

### This Week

3. **Fix Voxtral provider** - subprocess-per-chunk is broken (AUDIT-TODO)
4. **Enable Voxtral auto-select** for high-end Macs:
   ```bash
   export ECHOPANEL_AUTO_SELECT_VOXTRAL=1
   ```

5. **Increase queue buffer** for dual-source:
   ```bash
   export ECHOPANEL_AUDIO_QUEUE_MAX_SECONDS=6.0
   ```

### With HF Pro (Before March 1st)

6. **Download and test Voxtral Mini:**
   ```python
   from huggingface_hub import snapshot_download
   snapshot_download("voxtral/Voxtral-Mini-4B-Realtime", local_dir="./models/voxtral-mini")
   ```

7. **Benchmark comparison:**
   - faster-whisper base (CPU) - baseline
   - whisper.cpp base (Metal) - target
   - Voxtral Mini (Metal) - premium option

---

## Part 6: Key Insights

1. **faster-whisper is NOT faster on Apple Silicon** - it's CPU-bound
2. **whisper.cpp is the correct choice** for local-first macOS app
3. **Voxtral is SOTA** but needs HF Pro access and provider fixes
4. **Frame drops on M3 Max = wrong provider**, not weak hardware
5. **HF Pro = local model testing**, not cloud inference (product decision)

---

## References

- `docs/audit/asr-streaming-model-matrix-20260213.md` - Model benchmarks
- `docs/audit/asr-provider-performance-20260211.md` - Provider analysis
- `docs/audit/streaming-reliability-dual-pipeline-20260210.md` - Pipeline architecture
- `server/services/provider_faster_whisper.py` - CPU-only macOS code
- `server/services/capability_detector.py` - Provider recommendations

---

## Related Discussions

- `docs/discussion-realtime-transcription-apps-2026-02-14.md` - Initial question about real-time apps
- `docs/discussion-realtime-overload-debug-2026-02-14.md` - Overload debugging analysis
- `docs/COMPREHENSIVE_ASR_OVERLOAD_ANALYSIS_2026-02-14.md` - Full technical deep-dive
