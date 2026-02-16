# Voxtral Implementation Audit

**Date:** 2026-02-14  
**Auditor:** Agent Self-Audit  
**Severity:** HIGH

## Executive Summary

The current `provider_voxtral_realtime.py` implementation uses **antirez/voxtral.c** - an unofficial third-party C reimplementation - instead of the official **Mistral Voxtral** model (`mistralai/Voxtral-Mini-4B-Realtime-2602`).

This is a significant deviation from requirements and introduces unknown risks around accuracy, latency claims, and architectural compatibility.

---

## The Issue

### What's Implemented (WRONG)
```python
# File: server/services/provider_voxtral_realtime.py (lines 40-51)
_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

def _default_bin() -> Path:
    return Path(os.getenv(
        "ECHOPANEL_VOXTRAL_BIN",
        str(_PROJECT_ROOT.parent / "voxtral.c" / "voxtral"),  # ❌ antirez reimplementation
    ))

def _default_model() -> Path:
    return Path(os.getenv(
        "ECHOPANEL_VOXTRAL_MODEL",
        str(_PROJECT_ROOT.parent / "voxtral.c" / "voxtral-model"),  # ❌ Unknown model format
    ))
```

### What Should Be Used (CORRECT)
```python
# Official Mistral model
model_id = "mistralai/Voxtral-Mini-4B-Realtime-2602"

# Requirements per HF model card:
# - vLLM serving infrastructure: "vLLM is currently the only supported inference engine"
# - OR Mistral SDK: pip install mistralai[realtime]
# - Streaming delay: 240ms to 2.4s configurable (480ms recommended)
```

---

## Comparison: antirez vs Official

| Aspect | antirez/voxtral.c | mistralai/Voxtral-Mini-4B-Realtime-2602 |
|--------|-------------------|------------------------------------------|
| **Origin** | Third-party C port by @antirez | Official Mistral release |
| **Parameters** | Unknown | 4B (confirmed) |
| **Architecture** | Unknown implementation | Novel streaming architecture |
| **Latency Claim** | Unknown | <200ms to 2.4s configurable |
| **WER Benchmark** | Unknown | ~4% on FLEURS (documented) |
| **Inference Engine** | Custom C binary | vLLM (required per model card) |
| **Validation** | Community port | Production-tested by Mistral |
| **License** | Unknown | Apache 2.0 |

---

## Why This Matters

### 1. Accuracy Unknown
The antirez implementation is a port - there's no guarantee it matches the official model's 4% WER on FLEURS benchmark.

### 2. Latency Claims Unverified
The official model advertises sub-200ms streaming delay with 480ms recommended for 1-2% WER tradeoff. The antirez version has no documented latency characteristics.

### 3. Streaming Architecture
Official Voxtral uses a "novel streaming architecture" specifically designed for real-time transcription. The antirez version may use a chunked approach that doesn't support the configurable streaming delay.

### 4. Maintenance Risk
The antirez version is a community port that may not keep up with official model updates or bug fixes.

---

## Root Cause

**Timeline Analysis:**
- The antirez/voxtral.c repository was created as a quick C implementation
- It was adopted before the official Mistral model was fully understood
- No validation was done to confirm it matches official model behavior
- Documentation incorrectly cites "Voxtral" without clarifying it's an unofficial port

---

## Impact Assessment

| Area | Impact | Severity |
|------|--------|----------|
| Transcription Quality | Unknown accuracy vs official | MEDIUM |
| Latency Guarantees | No verified <200ms capability | HIGH |
| System Reliability | Unknown edge cases | MEDIUM |
| Documentation Accuracy | Misleading provider name | MEDIUM |

---

## Recommended Actions

### Immediate (P0)
1. **Rename** `provider_voxtral_realtime.py` to `provider_voxtral_antirez.py` to clarify it's unofficial
2. **Document** in code comments that this is NOT the official Mistral model
3. **Update** health metrics to indicate "unofficial implementation"

### Short-term (P1)
4. **Create** `provider_voxtral_official.py` using proper vLLM serving or Mistral SDK
5. **Benchmark** both implementations against same test set
6. **Validate** antirez accuracy before production use

### Long-term (P2)
7. **Deprecate** antirez version if official proves superior
8. **Implement** true streaming with configurable delay (240ms-2.4s)
9. **Add** native diarization support (available in official V2)

---

## Evidence

### Official Model Documentation
- **Model Card:** https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602
- **Key Quote:** *"Due to its novel architecture, Voxtral Realtime is currently only supported in vLLM."*
- **Streaming Delay:** *"delay of < 500 ms", "configurable transcription delays (240 ms to 2.4 s)"*

### Current Implementation
```bash
# File location
server/services/provider_voxtral_realtime.py

# Lines using antirez path
Line 43: _PROJECT_ROOT.parent / "voxtral.c" / "voxtral"
Line 50: _PROJECT_ROOT.parent / "voxtral.c" / "voxtral-model"

# Environment variables (misleading naming)
ECHOPANEL_VOXTRAL_BIN
ECHOPANEL_VOXTRAL_MODEL
```

---

## Appendix: Official Implementation Requirements

### Option A: vLLM Serving (Recommended for Production)
```bash
# Install vLLM
pip install vllm

# Serve model
vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 \
    --max-model-len 4096 \
    --tensor-parallel-size 1

# Connect via HTTP API
```

### Option B: Mistral SDK (Cloud API)
```python
from mistralai import Mistral
from mistralai.models import AudioFormat

client = Mistral(api_key=os.getenv("MISTRAL_API_KEY"))
audio_format = AudioFormat(encoding="pcm_s16le", sample_rate=16000)

async for event in client.audio.realtime.transcribe_stream(
    audio_stream=pcm_iterator,
    model="voxtral-mini-transcribe-realtime-2602",
    audio_format=audio_format,
):
    # Handle RealtimeTranscriptionSessionCreated,
    #        TranscriptionStreamTextDelta,
    #        TranscriptionStreamDone
    pass
```

### Option C: Local vLLM with Custom Provider
```python
# Custom provider that connects to local vLLM instance
# Requires implementing OpenAI-compatible client for vLLM's /v1/audio/transcriptions endpoint
```

---

## Conclusion

The current Voxtral provider is using an unofficial implementation that:
1. Has unknown accuracy characteristics
2. Cannot verify latency claims
3. Uses a different architecture than the official model
4. Introduces maintenance and reliability risks

**Recommendation:** Prioritize implementing the official model via vLLM serving or Mistral SDK, and clearly label the antirez version as experimental/community implementation.
