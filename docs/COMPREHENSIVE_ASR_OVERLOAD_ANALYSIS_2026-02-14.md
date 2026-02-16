# Comprehensive ASR Overload & Frame Drop Analysis

**Date:** 2026-02-14  
**Status:** CRITICAL - Hardware Underutilization  
**Root Cause:** CPU-only inference on Apple Silicon (GPU sitting idle)

---

## 1. Executive Summary

### The Real Problem

Your **M3 Max with 96GB RAM** is using **CPU-only inference** while the **Neural Engine and GPU sit idle**. This is why you're seeing frame drops even on high-end hardware.

| Hardware | Current Usage | Potential | Wasted |
|----------|--------------|-----------|--------|
| M3 Max CPU (12-core) | 100% (bottleneck) | - | - |
| M3 Max GPU (40-core) | **0%** (idle) | 10-20× faster | **100%** |
| Neural Engine | **0%** (idle) | 5-10× faster | **100%** |

### Why "Faster-Whisper" Isn't Faster on macOS

```python
# provider_faster_whisper.py:84-88 - THE PROBLEM
if device == "auto" and platform.system() == "Darwin":
    device = "cpu"  # ← M3 Max GPU NEVER used!
```

**CTranslate2** (the backend for faster-whisper) **does not support Metal/MPS**. It only supports:
- ✅ CUDA (NVIDIA GPUs on Linux/Windows)
- ✅ CPU (all platforms)
- ❌ Metal/MPS (macOS) - NOT SUPPORTED

---

## 2. Current Provider Status (As of 2026-02-14)

### Implemented Providers

| Provider | File | Metal/GPU | Status | RTF on M3 Max | Issue |
|----------|------|-----------|--------|---------------|-------|
| **faster_whisper** | `provider_faster_whisper.py` | ❌ CPU only | Production | ~0.7-1.0× | Uses CPU on macOS |
| **voxtral_realtime** | `provider_voxtral_realtime.py` | ⚠️ Broken | **BROKEN** | N/A | Subprocess-per-chunk |
| **whisper_cpp** | `provider_whisper_cpp.py` | ✅ Metal | **MISSING** | N/A | Not implemented |

### Provider Architecture Gap

```
ASRProviderRegistry.get_provider() 
    ↓
Only TWO providers registered:
    1. faster_whisper (CPU on macOS)
    2. voxtral_realtime (broken)
    
MISSING:
    3. whisper_cpp (Metal GPU - best for macOS)
    4. hf_inference_api (cloud fallback)
```

---

## 3. Voxtral Implementation is BROKEN

### Critical Defect: Subprocess-per-Chunk

The voxtral provider loads the **8.9GB model for EVERY chunk**:

```python
# provider_voxtral_realtime.py:131-161 (OLD VERSION - FIXED in v0.2)
async def _transcribe_chunk(self, pcm_bytes: bytes, sample_rate: int) -> Optional[str]:
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)  # ← Temp file per chunk
    # ...
    proc = await asyncio.create_subprocess_exec(  # ← NEW PROCESS per chunk
        str(self._bin),
        "-d", str(self._model),
        "-i", tmp.name,  # ← File input (not streaming)
        # ...
    )
```

**Performance Impact:**
- Model load: **~11 seconds** per chunk
- Inference: ~3.4 seconds for 4.4s audio
- Effective RTF: **~0.12×** (8× slower than real-time!)

### Fixed in v0.2 (Streaming Mode)

The current code shows v0.2 with `--stdin` streaming mode, but **availability check may fail**:

```python
# provider_voxtral_realtime.py:103-104
@property
def is_available(self) -> bool:
    return self._bin.is_file() and (self._model / "consolidated.safetensors").is_file()
```

**Requirements to use Voxtral:**
1. Build voxtral.c binary from source
2. Download 8.9GB model
3. Set env vars:
   ```bash
   export ECHOPANEL_VOXTRAL_BIN=/path/to/voxtral
   export ECHOPANEL_VOXTRAL_MODEL=/path/to/voxtral-model
   export ECHOPANEL_AUTO_SELECT_VOXTRAL=1  # Required!
   ```

---

## 4. Capability Detection Exists But Doesn't Help

The `capability_detector.py` correctly identifies your hardware:

```python
# capability_detector.py:168-176
"ultra": {  # 32GB+ RAM, Apple Silicon or CUDA
    "provider": "voxtral_realtime",
    "model": "Voxtral-Mini-4B-Realtime",
    "chunk_seconds": 2,
    "compute_type": "bf16",
    "device": "mps",
    # ...
}
```

**BUT:** Voxtral auto-select is **disabled by default**:

```python
# capability_detector.py:357-364
if config.get("provider") == "voxtral_realtime":
    auto_voxtral = os.getenv("ECHOPANEL_AUTO_SELECT_VOXTRAL", "0").strip().lower()
    if auto_voxtral in {"0", "false", "no", "off", ""}:
        logger.info("Voxtral auto-select disabled")
        config = self.TIER_CONFIGS["high"].copy()  # Falls back to whisper_cpp... wait
```

**Problem:** The "high" tier recommends `whisper_cpp`, but **whisper.cpp provider doesn't exist!**

```python
# capability_detector.py:150-158
"high": {  # 16-32GB RAM
    "provider": "whisper_cpp",  # ← NOT IMPLEMENTED!
    "model": "medium.en",
    # ...
}
```

---

## 5. HF Pro Usage Strategy (LOCAL Models Only)

Since you don't plan to launch cloud models, use HF Pro for:

### 5.1 Faster Model Downloads

```python
# main.py already propagates HF token
export ECHOPANEL_HF_TOKEN=hf_...
# Automatically sets HF_TOKEN and HUGGINGFACE_HUB_TOKEN
```

**Benefit:** Avoids rate limits, faster downloads for local models.

### 5.2 Local Models to Test with HF Pro

| Model | Size | Use Case | Speed vs base.en |
|-------|------|----------|------------------|
| **distil-whisper/distil-small.en** | 322MB | 6× faster, slight accuracy loss | 6× faster |
| **openai/whisper-large-v3-turbo** | 1.6GB | Better accuracy, similar speed | Similar |
| **mistralai/Voxtral-Mini-4B-Realtime** | 8.9GB | Best quality + streaming | 2-3× faster |

### 5.3 Models NOT to Test (Cloud Only)

| Model | Type | Reason Excluded |
|-------|------|-----------------|
| `openai/whisper-api` | Cloud API | You don't want cloud dependency |
| `hf-inference-api` | Cloud API | You don't want cloud dependency |

---

## 6. Audit Document Inventory

### Critical Audit Files (Read These)

| File | Key Finding | Status |
|------|-------------|--------|
| `asr-streaming-model-matrix-20260213.md` | base.en RTF ~0.73×, small.en RTF ~1.29× | ✅ Validated |
| `asr-provider-performance-20260211.md` | faster-whisper CPU-only on macOS | ⚠️ Confirmed |
| `streaming-reliability-dual-pipeline-20260210.md` | Queue size < chunk size issue | ⚠️ Partially fixed |
| `PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md` | PR2 pause/resume not implemented | ❌ Still open |
| `AUDIO_RATE_LIMITING_ISSUE_2026-02-13.md` | Rate limiting attempts made | ✅ Fixed |
| `asr-overload-drop-system-20260213.md` | False overload bug fixed | ✅ Fixed |

### All Related Documentation

```
docs/
├── audit/
│   ├── asr-streaming-model-matrix-20260213.md      ✅ Model benchmark results
│   ├── asr-provider-performance-20260211.md        ⚠️ Provider analysis
│   ├── asr-overload-drop-system-20260213.md        ✅ False-drop bug fix
│   ├── audio-pipeline-audit-20260211.md            ⚠️ Pipeline audit
│   ├── audio-pipeline-deep-dive-20260211.md        📋 Deep dive
│   ├── audio-industry-code-review-20260211.md      📋 Code review
│   ├── streaming-reliability-dual-pipeline-20260210.md  ⚠️ Reliability audit
│   ├── PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md    ⚠️ Backpressure analysis
│   ├── AUDIO_RATE_LIMITING_ISSUE_2026-02-13.md     ✅ Recent fixes
│   ├── asr-model-lifecycle-20260211.md             📋 Model lifecycle
│   └── PHASE_2D_ASR_PROVIDER_AUDIT.md              📋 Provider audit
├── ASR_MODEL_RESEARCH_2026-02.md                   📋 60+ model research
├── VOXTRAL_RESEARCH_2026-02.md                     📋 Voxtral research
├── REALTIME_STREAMING_ARCHITECTURE.md              📋 Architecture doc
├── ASR_CONCURRENCY_PATTERNS_RESEARCH.md            📋 Concurrency research
└── whisper_cpp_integration_research.md             📋 whisper.cpp research
```

---

## 7. Immediate Actions Required

### P0: Implement whisper.cpp Provider (CRITICAL)

**Why:** Only way to use Metal GPU on macOS.

```python
# New file: server/services/provider_whisper_cpp.py
# Use libwhisper.dylib via ctypes or subprocess with --stream
# Metal backend: -ng 1 (GPU layers)
# GGML model: ggml-base.en.bin (~150MB)
```

**Expected Performance:**
- base.en on Metal: **RTF ~0.1-0.2×** (5-10× faster than CPU)
- Memory: ~500MB (vs 460MB for faster-whisper)

### P1: Fix Queue Size Mismatch

```python
# ws_live_listener.py:30
QUEUE_MAX_SECONDS = 6.0  # Was 2.0, should be > chunk_seconds (4.0)
```

### P1: Enable Voxtral (Optional)

```bash
# Build voxtral.c
export ECHOPANEL_VOXTRAL_BIN=/path/to/voxtral
export ECHOPANEL_VOXTRAL_MODEL=/path/to/voxtral-model
export ECHOPANEL_AUTO_SELECT_VOXTRAL=1
export ECHOPANEL_ASR_PROVIDER=voxtral_realtime
```

### P2: Implement Pause/Resume on Backpressure

```swift
// WebSocketStreamer.swift - when receiving "overloaded" status
if state == "overloaded" {
    self.pauseCapture()  // Stop sending audio
} else if state == "streaming" {
    self.resumeCapture()  // Resume sending
}
```

---

## 8. Tested Configurations (From Audit)

### Configuration That Works (base.en)

```bash
export ECHOPANEL_ASR_PROVIDER=faster_whisper
export ECHOPANEL_WHISPER_MODEL=base.en
export ECHOPANEL_WHISPER_DEVICE=cpu
export ECHOPANEL_WHISPER_COMPUTE=int8
export ECHOPANEL_ASR_CHUNK_SECONDS=2
export ECHOPANEL_ASR_VAD=1
export ECHOPANEL_HF_TOKEN=hf_...  # For faster downloads
```

**Performance:**
- RTF: ~0.73× (faster than real-time)
- Drops: 0 (with 2s chunks)
- Memory: ~460MB

### Configuration That FAILS (small.en)

```bash
export ECHOPANEL_WHISPER_MODEL=small.en
```

**Performance:**
- RTF: ~1.29× (slower than real-time)
- Drops: 22+ frames
- Queue fill: 100%

---

## 9. Hardware-Specific Recommendations

### For M3 Max Users (Your Machine)

| Priority | Action | Expected RTF | Effort |
|----------|--------|--------------|--------|
| 1 | Implement whisper.cpp provider | 0.1-0.2× | 1-2 days |
| 2 | Use Voxtral (if available) | 0.1-0.15× | Setup heavy |
| 3 | Stick with base.en + 2s chunks | 0.7-0.8× | Now |

### For 8GB Mac Users (Minimum Spec)

```bash
export ECHOPANEL_WHISPER_MODEL=tiny.en
export ECHOPANEL_ASR_CHUNK_SECONDS=4
```

### For Intel Mac Users

```bash
export ECHOPANEL_WHISPER_MODEL=base.en  # or tiny.en
export ECHOPANEL_WHISPER_COMPUTE=int8   # CPU-only
```

---

## 10. Evidence Citations

### Code Citations

| File | Lines | Observation |
|------|-------|-------------|
| `provider_faster_whisper.py` | 84-88 | CPU forced on macOS |
| `provider_faster_whisper.py` | 46-47 | Global inference lock removed for "per-session concurrency" |
| `capability_detector.py` | 150-158 | Recommends whisper_cpp (not implemented) |
| `capability_detector.py` | 357-364 | Voxtral auto-select disabled by default |
| `asr_stream.py` | 31 | VAD enabled by default (fixed 2026-02-11) |
| `ws_live_listener.py` | 30-36 | Queue sizing: 2s max, should be 6s |

### Audit Citations

| Document | Date | Key Finding |
|----------|------|-------------|
| `asr-streaming-model-matrix-20260213.md` | 2026-02-13 | base.en RTF 0.73×, small.en RTF 1.29× |
| `asr-provider-performance-20260211.md` | 2026-02-11 | "No Apple Silicon Metal Support: faster-whisper forces CPU on macOS" |
| `PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md` | 2026-02-10 | "PR2: Pause/Resume Capture on Backpressure - NOT STARTED" |
| `AUDIO_RATE_LIMITING_ISSUE_2026-02-13.md` | 2026-02-13 | "Debug why rate-limited client still causes server overload" |

---

## 11. Summary

### Root Cause

Your M3 Max is using **faster-whisper on CPU** while the **GPU sits idle**. CTranslate2 doesn't support Metal, so you're getting ~0.7× RTF instead of ~0.1× with Metal acceleration.

### Immediate Workaround

Use **base.en with 2s chunks** - this maintains RTF < 1.0 even on CPU:

```bash
export ECHOPANEL_WHISPER_MODEL=base.en
export ECHOPANEL_ASR_CHUNK_SECONDS=2
```

### Real Fix

Implement **whisper.cpp provider** with Metal backend:
- 5-10× faster than faster-whisper on macOS
- Uses GPU instead of CPU
- RTF ~0.1-0.2× expected on M3 Max

### HF Pro Strategy

Use for **downloading local models faster**, not cloud inference:
1. Set `ECHOPANEL_HF_TOKEN=hf_...`
2. Test distil-whisper (6× faster)
3. Test Voxtral (best quality + speed)
4. Download models once, run locally forever

---

*Analysis completed: 2026-02-14*  
*Next action: Implement whisper.cpp provider OR verify Voxtral availability*
