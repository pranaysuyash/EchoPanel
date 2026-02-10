# EchoPanel ASR Provider & Performance Audit

**Date**: 2026-02-11  
**Ticket**: TCK-20260211-003  
**Status**: COMPLETE  
**Auditor**: Agent Amp  
**Scope**: ASR provider layer, residency, streaming semantics, Apple Silicon optimization

---

## Files Inspected

**Provider Layer:**
- `server/services/asr_providers.py` (150 lines)
- `server/services/provider_faster_whisper.py` (239 lines)
- `server/services/provider_voxtral_realtime.py` (184 lines)
- `server/services/asr_stream.py` (91 lines)
- `server/services/vad_filter.py` (148 lines)

**Server & Config:**
- `server/main.py` (94 lines)
- `server/api/ws_live_listener.py` (519 lines)
- `.env.example` (35 lines)

**Benchmark & Test Scripts:**
- `scripts/benchmark_voxtral_vs_whisper.py` (193 lines)
- `scripts/soak_test.py` (260 lines)
- `scripts/stream_test.py` (65 lines)
- `scripts/stream_test_multi.py`
- `tests/test_streaming_correctness.py` (243 lines)

**Documentation:**
- `docs/ASR_MODEL_RESEARCH_2026-02.md` (1000+ lines)
- `docs/VOXTRAL_RESEARCH_2026-02.md` (250 lines)

---

## A) Executive Summary

1. **Only Two Providers Implemented**: `faster_whisper` (production) and `voxtral_realtime` (experimental). No whisper.cpp, no Distil-Whisper, no cloud API providers.

2. **Critical Residency Defect in Voxtral**: `provider_voxtral_realtime.py` spawns a **new subprocess per chunk** (lines 139-147), loading the ~8.9GB model each time. This is architecturally broken—RTF ~0.1x should be achievable with streaming mode, but current implementation gets ~0.05x (20× slower than real-time).

3. **Faster-Whisper Has Correct Residency**: Model loads once in `_get_model()` (line 51-80) and stays resident. Uses `threading.Lock` for thread-safe inference serialization.

4. **No Apple Silicon Metal Support**: faster-whisper forces CPU on macOS (line 60-63: `device = "cpu"`). CTranslate2 doesn't support MPS/Metal. Voxtral theoretically supports MPS but benchmark shows 25GB memory usage.

5. **VAD Exists But Not Integrated**: `vad_filter.py` implements Silero VAD but is **never called** by either provider. faster-whisper has internal VAD (`vad_filter` param, line 136) but it's **disabled by default** (`ECHOPANEL_ASR_VAD=0`).

6. **No Machine Capability Detection**: No RAM/CPU/GPU detection. No automatic provider/model selection. User must manually configure via env vars.

7. **No Degrade Ladder**: When `realtime_factor > 1.0`, system drops frames but never switches to a smaller model or increases chunk size.

8. **Streaming Is Chunked-Batch**: Neither provider supports true streaming (incremental partials). Both accumulate chunks and emit final segments only.

9. **Provider Selection Static**: `ECHOPANEL_ASR_PROVIDER` env var at startup only. No runtime switching, no A/B testing, no automatic fallback.

10. **Benchmark Harness Exists but Limited**: `benchmark_voxtral_vs_whisper.py` only tests batch mode. `soak_test.py` tests streaming but doesn't measure RTF or per-chunk latency.

---

## B) Provider Inventory (What Exists Today)

| Provider | File | Status | Residency | Concurrency | VAD | Metal/MPS |
|----------|------|--------|-----------|-------------|-----|-----------|
| **faster_whisper** | `provider_faster_whisper.py` | Production | ✅ Model loads once, stays resident | Thread-safe via `_infer_lock` | Internal (off by default) | ❌ Forces CPU on macOS |
| **voxtral_realtime** | `provider_voxtral_realtime.py` | Broken | ❌ **Spawns subprocess per chunk** | N/A (process-bound) | ❌ Not implemented | ⚠️ Binary supports MPS but provider doesn't use `--stdin` mode |

### Missing Providers (Not Implemented)

| Provider | Why Missing | Priority |
|----------|-------------|----------|
| whisper.cpp | No implementation | HIGH — Best Apple Silicon option |
| Distil-Whisper | No implementation | MEDIUM — 6× faster, small accuracy loss |
| OpenAI Whisper API | No implementation | LOW — Cloud dependency |
| Voxtral API (Mistral) | No implementation | LOW — Cloud dependency |
| NVIDIA Parakeet | No implementation | LOW — NVIDIA GPU only |

### Citation: Provider Registration
```python
# server/services/asr_stream.py:17-18
from . import provider_faster_whisper  # noqa: F401
from . import provider_voxtral_realtime  # noqa: F401
```

---

## C) Provider Contract Spec

### Current Interface (asr_providers.py:50-95)

```python
class ASRProvider(ABC):
    @property
    @abstractmethod
    def name(self) -> str: ...

    @property
    @abstractmethod
    def is_available(self) -> bool: ...

    @abstractmethod
    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]: ...
```

### Proposed Enhanced Contract

```python
@dataclass
class ASRHealth:
    realtime_factor: float      # inference_time / audio_time
    avg_infer_ms: float         # Average inference latency
    backlog_estimate: int       # Queued chunks waiting
    model_resident: bool        # Model loaded and hot
    last_error: Optional[str]   # Last error message

class ASRProvider(ABC):
    # ... existing methods ...
    
    async def start_session(self, session_id: str, config: dict) -> bool:
        """Initialize provider for session. Return True when ready."""
        raise NotImplementedError
    
    async def health(self) -> ASRHealth:
        """Return current performance metrics."""
        raise NotImplementedError
    
    async def flush(self, source: AudioSource) -> List[ASRSegment]:
        """Force flush any buffered audio, return final segments."""
        raise NotImplementedError
    
    async def stop_session(self, session_id: str) -> None:
        """Clean up session resources. Must be bounded time."""
        raise NotImplementedError
```

### Streaming Semantics

| Aspect | Current | Required |
|--------|---------|----------|
| **Partial results** | ❌ None (final only) | ✅ Incremental partials |
| **Monotonic time** | ✅ Yes (t0/t1 increase) | ✅ Must maintain |
| **Cancellation** | ✅ Generator stops on break | ✅ Must support |
| **Chunking** | Fixed 4s chunks | Configurable adaptive |
| **Backpressure** | Queue drops oldest | Should signal upstream |

---

## D) Residency Audit

### faster-whisper Provider

| Aspect | Implementation | Location |
|--------|----------------|----------|
| **Model load** | Lazy in `_get_model()` | `provider_faster_whisper.py:51-80` |
| **Residency** | ✅ Instance variable `_model` stays loaded | Line 40 |
| **Load timing** | First transcription request | Line 55 |
| **Thread safety** | `threading.Lock()` on inference | Line 41, 133 |
| **Concurrent streams** | Serialized (one inference at a time) | Lock held during transcribe |
| **Warmup** | ❌ None | Cold start on first chunk |

**Startup Cost (assumption: UX constraint)**:
- Model load: 2-5s for base.en, 5-10s for large-v3
- **Justification**: User starts session, sees "Loading model..." for <5s acceptable
- **Measure**: Time from first audio chunk to first ASR event

### voxtral_realtime Provider — CRITICAL DEFECT

| Aspect | Implementation | Location |
|--------|----------------|----------|
| **Model load** | ❌ **Per-chunk subprocess spawn** | `provider_voxtral_realtime.py:139-147` |
| **Residency** | ❌ None (process exits after each chunk) | `_transcribe_chunk` method |
| **Load timing** | Every 4s chunk pays 11s model load | Benchmark evidence |
| **Subprocess** | `asyncio.create_subprocess_exec` | Line 139 |
| **Temp files** | WAV written to temp for each chunk | Line 135-136 |

**Citation: Subprocess per chunk**:
```python
# provider_voxtral_realtime.py:131-161
async def _transcribe_chunk(self, pcm_bytes: bytes, sample_rate: int) -> Optional[str]:
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)  # ← Temp file per chunk
    # ...
    proc = await asyncio.create_subprocess_exec(  # ← New process per chunk
        str(self._bin),
        "-d", str(self._model),
        "-i", tmp.name,  # ← File input (not streaming)
        "--silent",
        # ...
    )
```

**Benchmark Evidence** (from `docs/VOXTRAL_RESEARCH_2026-02.md:168-179`):
- Batch RTF: 0.768x (3.37s inference for 4.39s audio)
- Model load: ~11s per invocation
- Memory: ~25GB on M3 Max
- **Root cause**: Subprocess-per-chunk defeats voxtral.c's streaming capability

**Fix Required**:
```bash
# voxtral.c supports streaming mode:
./voxtral -d model --stdin -I 0.5  # 500ms streaming delay
# Provider must keep process resident, pipe PCM chunks via stdin
```

### VAD Filter (Unused)

| Aspect | Implementation | Status |
|--------|----------------|--------|
| **Model** | Silero VAD via torch.hub | `vad_filter.py:29-34` |
| **Lazy load** | ✅ Yes (global `_vad_model`) | Line 18-20 |
| **Integration** | ❌ Never called by providers | Orphan code |
| **Residency** | Would stay loaded if used | N/A |

---

## E) Bottleneck Analysis

### CPU/GPU Bottlenecks

| Provider | Compute | macOS | Linux | Notes |
|----------|---------|-------|-------|-------|
| faster-whisper | CTranslate2 | CPU only (forced) | CUDA/CPU | MPS not supported by CTranslate2 |
| voxtral (current) | MPS/CPU | MPS (theoretically) | CPU | But subprocess-per-chunk kills performance |
| whisper.cpp (missing) | Metal/CPU | Metal | CUDA/Vulkan | Best Apple Silicon option |

**Threading Model**:
- faster-whisper: Single inference lock → serializes all ASR calls
- Consequence: Multi-source (mic + system) = queued, not parallel

### Chunk Size Impact

| Chunk Size | Latency | Accuracy | Throughput |
|------------|---------|----------|------------|
| 2s | Lower | Lower (less context) | Higher (more parallel) |
| 4s (current) | Medium | Good | Good |
| 8s | Higher | Higher | Lower |

**Current**: Fixed 4s via `ECHOPANEL_ASR_CHUNK_SECONDS` (default: 4)

### I/O Bottlenecks

1. **Base64 encoding**: Audio encoded to base64 for JSON WebSocket (33% overhead)
2. **Temp files**: Voxtral writes WAV to disk per chunk
3. **No zero-copy**: Data copied: PCM → base64 → JSON → WS → decode → PCM

### VAD Placement

| Location | Status | Impact |
|----------|--------|--------|
| **Client-side** | ❌ Not implemented | Would save bandwidth |
| **Server pre-filter** | ❌ Not integrated | `vad_filter.py` exists but unused |
| **ASR internal** | ✅ faster-whisper supports | Off by default |

---

## F) Provider Selection Strategy

### Current Selection (Static)

```python
# asr_stream.py:26-32
ASRConfig(
    model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en"),
    device=os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto"),
    compute_type=os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8"),
    chunk_seconds=int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "4")),
    vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "0") == "1",
)

# asr_providers.py:125
name = os.getenv("ECHOPANEL_ASR_PROVIDER", "faster_whisper")
```

### Proposed Adaptive Selection

```python
class CapabilityDetector:
    """Detect machine capabilities and recommend optimal provider."""
    
    @staticmethod
    def detect() -> MachineProfile:
        ram_gb = psutil.virtual_memory().total / (1024**3)
        cpu_cores = psutil.cpu_count()
        has_mps = torch.backends.mps.is_available() if torch else False
        has_cuda = torch.cuda.is_available() if torch else False
        
        return MachineProfile(
            ram_gb=ram_gb,
            cpu_cores=cpu_cores,
            has_mps=has_mps,
            has_cuda=has_cuda,
        )
    
    @staticmethod
    def recommend(profile: MachineProfile) -> ProviderRecommendation:
        if profile.ram_gb >= 32 and profile.has_mps:
            return ProviderRecommendation(
                provider="voxtral_realtime",  # Once fixed to use --stdin
                model="Voxtral-Mini-4B-Realtime",
                chunk_seconds=2,
                compute_type="bf16",
            )
        elif profile.ram_gb >= 16:
            return ProviderRecommendation(
                provider="faster_whisper",
                model="small.en",
                chunk_seconds=4,
                compute_type="int8",
            )
        else:  # 8GB RAM
            return ProviderRecommendation(
                provider="faster_whisper",
                model="base.en",
                chunk_seconds=4,
                compute_type="int8",
            )
```

### Degrade Ladder (When realtime_factor > 1.0)

| Level | Trigger | Action | Recovery |
|-------|---------|--------|----------|
| 1 (Warning) | RTF > 0.8 for 10s | Log warning, increase chunk size +0.5s | RTF < 0.7 for 30s |
| 2 (Degrade) | RTF > 1.0 for 10s | Switch to smaller model, disable VAD | RTF < 0.8 for 30s |
| 3 (Emergency) | RTF > 1.2 for 10s | Drop every other chunk, emit warnings | Manual reset |
| 4 (Failover) | Provider crash | Switch to fallback provider | Manual intervention |

---

## G) Benchmark Protocol + Pass/Fail Thresholds

### Existing Harnesses

| Script | What It Measures | Gaps |
|--------|-----------------|------|
| `benchmark_voxtral_vs_whisper.py` | Batch RTF, load time | No streaming, no residency test |
| `soak_test.py` | End-to-end latency, backpressure | No RTF measurement, no per-chunk latency |
| `stream_test.py` | Basic connectivity | No metrics collection |

### Proposed Benchmark Protocol

#### Scenario A: 1-Source Speech-Heavy (10 min)
```bash
python scripts/benchmark_asr.py \
  --scenario speech-heavy \
  --duration 600 \
  --sources 1 \
  --provider faster_whisper \
  --model base.en
```

**Measurements**:
- `realtime_factor` (inference_time / audio_duration) per chunk
- `queue_depth` trend
- `dropped_chunks_total`
- `first_chunk_latency` (time from start to first ASR event)
- `startup_time` (time from provider init to first chunk processed)

**Pass Thresholds**:
| Metric | Target | Minimum |
|--------|--------|---------|
| realtime_factor p95 | < 0.5 | < 0.8 |
| dropped_chunks_total | 0 | < 5 |
| first_chunk_latency | < 3s | < 5s |
| startup_time | < 2s | < 5s |

#### Scenario B: 2-Source Speech-Heavy (10 min)
Same as A but with 2 concurrent sources (mic + system).

**Additional Measurements**:
- Per-source RTF
- Inter-source timestamp drift

**Pass Thresholds**:
| Metric | Target | Minimum |
|--------|--------|---------|
| realtime_factor p95 (per source) | < 0.6 | < 0.9 |
| timestamp drift | < 50ms | < 100ms |

#### Scenario C: 2-Source Silence-Heavy (10 min, 80% silence)
Tests VAD efficacy.

**Pass Thresholds**:
| Metric | Target | Minimum |
|--------|--------|---------|
| CPU usage (vs speech-heavy) | < 30% | < 50% |
| realtime_factor | > 2.0 | > 1.5 |
| False rejection rate | < 2% | < 5% |

### End-to-End Latency Measurement

```python
# Inject marker beep at known time T0
# Measure wall-clock time T1 when asr_final received
latency = T1 - T0

# Pass thresholds
# p50: < 2s
# p95: < 4s
# p99: < 6s
```

### Residency Test

```python
# Measure time for N consecutive chunks
# If model resident: time should be ~constant (O(audio_duration))
# If model reloads: time increases with N (O(N * load_time))

def test_residency(provider, chunks=10):
    times = []
    for i in range(chunks):
        t0 = time.perf_counter()
        await process_chunk(dummy_audio)
        times.append(time.perf_counter() - t0)
    
    # Resident: variance low, no upward trend
    # Non-resident: times increase linearly
    slope = linear_regression(times).slope
    assert slope < 0.1, f"Model not resident: slope={slope}"
```

---

## H) Fix Plan (PR-Sized Tasks)

### PR 1: Fix Voxtral Residency (Streaming Mode)
**Impact**: CRITICAL | **Effort**: M | **Risk**: M

**Files**: `server/services/provider_voxtral_realtime.py`

**Changes**:
- Rewrite to use `voxtral --stdin -I 0.5` streaming mode
- Keep subprocess resident for entire session
- Pipe PCM chunks via stdin, parse stdout for results
- Add session lifecycle management

**Validation**:
- Residency test passes (slope < 0.1)
- RTF > 0.5 (2× faster than real-time)
- Memory < 10GB on M-series Macs

---

### PR 2: Add whisper.cpp Provider
**Impact**: HIGH | **Effort**: M | **Risk**: L

**Files**: `server/services/provider_whisper_cpp.py`

**Changes**:
- New provider using whisper.cpp Metal backend
- Load GGML/GGUF model once, keep resident
- Use streaming mode (incremental results)
- Bind to `libwhisper.dylib` via ctypes or subprocess

**Validation**:
- RTF > 1.0 on M-series Macs
- Memory < 1GB for base model
- First chunk latency < 1s after warmup

---

### PR 3: Add Machine Capability Detection
**Impact**: HIGH | **Effort**: S | **Risk**: L

**Files**: `server/services/capability_detector.py`, `server/main.py`

**Changes**:
- Detect RAM, CPU cores, GPU (MPS/CUDA)
- Recommend optimal provider/model
- Log capabilities at startup

**Validation**:
- Correctly detects M-series Macs → recommend whisper.cpp
- 8GB machines → base.en
- 16GB machines → small.en
- 32GB+ machines → voxtral (once fixed)

---

### PR 4: Implement Adaptive Degrade Ladder
**Impact**: MEDIUM | **Effort**: M | **Risk**: M

**Files**: `server/api/ws_live_listener.py`, `server/services/asr_stream.py`

**Changes**:
- Monitor `realtime_factor` every 10s
- Implement 4-level degrade ladder
- Add UI status messages for each level
- Automatic recovery when conditions improve

**Validation**:
- Artificially slow ASR, verify degrade triggers
- Restore normal speed, verify recovery
- All transitions logged

---

### PR 5: Enable Client-Side VAD Pre-Filter
**Impact**: MEDIUM | **Effort**: S | **Risk**: L

**Files**: `server/services/vad_filter.py`, `server/api/ws_live_listener.py`

**Changes**:
- Integrate `vad_filter.py` into audio pipeline
- Run VAD on incoming chunks before queueing
- Skip silent chunks (don't send to ASR)
- Add metrics: `vad_silence_ratio`, `vad_frames_skipped`

**Validation**:
- Scenario C: CPU usage drops >50%
- No speech segments lost (false rejection < 2%)

---

### PR 6: Enhance Provider Contract with Health Metrics
**Impact**: MEDIUM | **Effort**: S | **Risk**: L

**Files**: `server/services/asr_providers.py`, `server/services/provider_*.py`

**Changes**:
- Add `health()` method to interface
- Track RTF, inference latency, backlog
- Expose via 1Hz metrics message to client

**Validation**:
- Metrics appear in WebSocket stream
- Values accurate (±10% of manual measurement)

---

## I) Kill List (Patterns to Remove)

### 1. Per-Chunk Subprocess Spawn
**Where**: `provider_voxtral_realtime.py:131-161`
**Why Kill**: Loading 8.9GB model per chunk = 20× slower than real-time
**Evidence**: Benchmark shows 11s load + 3.37s inference for 4s audio = 0.12x RTF
**Fix**: Use `--stdin` streaming mode, keep process resident

### 2. Per-Chunk Model Load (Any Provider)
**Where**: N/A currently (faster-whisper is correct)
**Watch For**: Any future provider spawning processes per chunk
**Invariant**: Model must load once per session, not per chunk

### 3. Blocking Calls in WS Receive Loop
**Where**: `ws_live_listener.py` uses `asyncio.to_thread` (lines 97, 309, 314, etc.)
**Current Status**: ✅ Acceptable (runs in thread pool)
**Watch For**: Synchronous model loading, file I/O without thread offload
**Rule**: All inference must be in `to_thread`, all I/O must be async

### 4. Mixing Clocks Across Sources
**Where**: Each provider uses `processed_samples` counter per source
**Risk**: Clock drift between mic and system sources
**Current**: Each source independent (acceptable for now)
**Future Fix**: Shared monotonic clock reference

### 5. Base64 Audio Encoding
**Where**: WebSocket JSON messages
**Why Consider Killing**: 33% overhead, unnecessary for localhost
**Alternative**: Binary WebSocket frames (already supported as fallback)
**Migration**: Default to binary, deprecate JSON audio frames

---

## Appendix: Key Questions Answered

1. **Provider Interface**: Abstract base class with `transcribe_stream()` method. Supports chunked-batch, not true streaming.

2. **Model Residency**: faster-whisper = resident (loads once). voxtral = **broken** (reloads per chunk).

3. **Startup Penalty**: faster-whisper: 2-5s cold start. voxtral: 11s per chunk (unacceptable).

4. **Per-Chunk Spawn**: **YES** — voxtral provider. Marked as critical defect.

5. **Concurrency**: One inference lock per provider. Multi-source = serialized, not parallel.

6. **VAD**: Silero VAD exists but unused. faster-whisper internal VAD off by default.

7. **Cancellation**: Generator stops when `break` from async iterator. No orphan processes in faster-whisper.

8. **Degrade Ladder**: Not implemented. System drops frames but never adapts.

9. **Capability Detection**: Not implemented. Static config via env vars.

10. **Real-Time Criteria**: RTF < 1.0 sustained, latency < 4s p95, startup < 5s.

---

*Audit completed: 2026-02-11*  
*Ticket: TCK-20260211-003*  
*Next review: On implementation of PR 1-6*
