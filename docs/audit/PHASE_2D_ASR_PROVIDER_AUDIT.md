# Phase 2D Audit: ASR Provider Layer (Residency, Streaming Semantics, Apple Silicon Throughput)

**Date:** 2026-02-11
**Auditor:** Multi-Persona Analysis (ASR Architect, Apple Silicon Specialist, Streaming Systems, Reliability, MLOps)
**Scope:** ASR provider layer and its integration with streaming pipeline
**Status:** OPEN
**Last reviewed:** 2026-02-11 (Audit Queue Runner)

---

## Update (2026-02-13)

- ✅ PR1 (Whisper.cpp inference lock) is already implemented: `server/services/provider_whisper_cpp.py` has `_infer_lock = threading.Lock()` and serializes `model.transcribe(...)` under the lock.
- ✅ PR3 (provider health metrics) implemented: `server/api/ws_live_listener.py` now calls `provider.health()` and includes `provider_health` in each `metrics` message payload.
- ✅ Hardened `whisper_cpp` provider contract/registration: `server/services/provider_whisper_cpp.py` now conforms to `ASRProvider` v0.3 and registers via `ASRProviderRegistry.register("whisper_cpp", WhisperCppProvider)`; added a unit test that stubs pywhispercpp.

## A) Files Inspected

### Core Provider Interface
| Path | Lines | Purpose |
|------|-------|---------|
| `server/services/asr_providers.py` | 1-150 | Abstract base class `ASRProvider`, `ASRConfig`, `ASRSegment`, `ASRProviderRegistry` |
| `server/services/asr_stream.py` | 1-92 | High-level streaming interface `stream_asr()` |

### Provider Implementations
| Path | Lines | Purpose |
|------|-------|---------|
| `server/services/provider_faster_whisper.py` | 1-239 | Faster-Whisper provider (CTranslate2, CPU) |
| `server/services/provider_whisper_cpp.py` | 1-482 | Whisper.cpp provider (Metal GPU, ctypes) |
| `server/services/provider_voxtral_realtime.py` | 1-451 | Voxtral.c provider (streaming subprocess) |

### Integration Points
| Path | Lines | Purpose |
|------|-------|---------|
| `server/api/ws_live_listener.py` | 279-301 | `_asr_loop()` per-source invocation |
| `server/services/degrade_ladder.py` | 1-578 | Adaptive performance management |
| `server/services/vad_filter.py` | 1-148 | Silero VAD pre-filter |
| `server/main.py` | 16-34 | Provider initialization in lifespan |

### Benchmarking
| Path | Lines | Purpose |
|------|-------|---------|
| `scripts/benchmark_voxtral_vs_whisper.py` | 1-193 | Head-to-head ASR comparison |
| `scripts/soak_test.py` | 1-260 | End-to-end streaming soak test |

---

## B) Provider Inventory (CURRENT)

| Provider ID | Local/Cloud | Implementation | Init Path | Invocation Pattern | Stop/Cleanup | Evidence |
|-------------|-------------|----------------|-----------|-------------------|--------------|----------|
| `faster_whisper` | Local | `provider_faster_whisper.py` | Lazy on first `_get_model()` call | `transcribe_stream()` → chunked batch | None explicit (model stays in `_model`) | L35-41, L51-80 |
| `whisper_cpp` | Local | `provider_whisper_cpp.py` | Lazy on first `_get_context()` call | `transcribe_stream()` → chunked batch | `ctx.close()` on provider destruction | L271-285, L303-326, L236-246 |
| `voxtral_realtime` | Local | `provider_voxtral_realtime.py` | Per-session `_start_session()` | `transcribe_stream()` → streaming subprocess | `_stop_session()` closes process | L84-97, L107-155, L201-223 |

### Key Observations

1. **Two residency patterns exist:**
   - **True residency:** `faster_whisper`, `whisper_cpp` — model loads once, stays hot
   - **Session-based:** `voxtral_realtime` — subprocess per `transcribe_stream()` call (streaming mode keeps it resident within session)

2. **No explicit cleanup for faster_whisper:** The `WhisperModel` object remains in `_model` indefinitely. No `close()` or `__del__` method.

3. **Voxtral v0.2 rewrite:** Previously spawned subprocess-per-chunk (catastrophic). Now uses `--stdin` streaming mode with session lifecycle (L16-20).

---

## C) Provider Invocation Map (CURRENT)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WebSocket Audio Ingest (ws_live_listener.py)                                │
│  └── _asr_loop(websocket, state, queue, source)                              │
│      └── stream_asr(_pcm_stream(queue), sample_rate, source)                 │
│          │                                                                   │
│          ▼                                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  ASR Streaming Pipeline (asr_stream.py)                                      │
│  ├── _get_default_config() → ASRConfig from env vars                         │
│  ├── ASRProviderRegistry.get_provider(config) → Provider instance            │
│  │   └── Thread-safe singleton per config key                                │
│  └── provider.transcribe_stream(pcm_stream, sample_rate, audio_source)       │
│      │                                                                       │
│      ▼                                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  Provider Implementations (3 variants)                                       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Faster-Whisper (provider_faster_whisper.py)                        │    │
│  │  ├── _get_model() [lazy, once] → WhisperModel                       │    │
│  │  ├── Accumulate chunks → chunk_bytes buffer                         │    │
│  │  ├── await asyncio.to_thread(_transcribe) [thread pool]             │    │
│  │  │   └── with _infer_lock: model.transcribe() [SERIALIZED]          │    │
│  │  └── yield ASRSegment(is_final=True)                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Whisper.cpp (provider_whisper_cpp.py)                              │    │
│  │  ├── _get_context() [lazy, once] → WhisperContext                   │    │
│  │  ├── Accumulate chunks → chunk_bytes buffer                         │    │
│  │  ├── await asyncio.to_thread(_transcribe) [thread pool]             │    │
│  │  │   └── ctx.transcribe() [NO LOCK — assumes GIL/thread-safe]       │    │
│  │  └── yield ASRSegment(is_final=True)                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Voxtral Realtime (provider_voxtral_realtime.py)                    │    │
│  │  ├── _ensure_session() → StreamingSession (subprocess)              │    │
│  │  │   ├── create_subprocess_exec(voxtral --stdin)                   │    │
│  │  │   └── _wait_for_ready() [parses stderr for Metal/BLAS]          │    │
│  │  ├── For each complete chunk:                                       │    │
│  │  │   ├── _write_chunk() → stdin                                     │    │
│  │  │   └── _read_transcription() ← stdout [background task]           │    │
│  │  ├── yield ASRSegment(is_final=True)                                │    │
│  │  └── finally: _stop_session() [graceful → kill]                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Evidence Citations

| Component | File | Lines | Key Code |
|-----------|------|-------|----------|
| Per-source ASR loop | `ws_live_listener.py` | 279-301 | `async for event in stream_asr(...)` |
| Provider registry | `asr_providers.py` | 122-137 | `get_provider()` with thread-safe singleton |
| Faster-Whisper inference lock | `provider_faster_whisper.py` | 41, 132-133 | `threading.Lock()`, `with self._infer_lock` |
| Whisper.cpp ctypes binding | `provider_whisper_cpp.py` | 101-246 | `WhisperContext` class with `ctypes.CDLL` |
| Voxtral session lifecycle | `provider_voxtral_realtime.py` | 59-82, 225-229 | `StreamingSession` dataclass, `_ensure_session()` |

---

## D) Residency Audit (CURRENT, CRITICAL)

### D1. Faster-Whisper Provider

| Aspect | Finding | Evidence |
|--------|---------|----------|
| **Model load location** | `_get_model()` method | L51-80 |
| **Frequency** | Per unique config key (singleton via registry) | `asr_providers.py` L134-136 |
| **Stays resident?** | YES — `_model` held in instance | L40: `self._model: Optional["WhisperModel"] = None` |
| **Startup cost** | ~2-5s first call (model download/load) | Comment at L11: "P1: Model loaded at first _get_model call" |
| **Risk points** | Registry key includes all config → multiple instances for different configs | `asr_providers.py` L119: `_cfg_key()` includes 7 parameters |
| **Subprocess?** | NO — in-process CTranslate2 | L134-138: `model.transcribe()` called directly |
| **Cleanup** | NONE — no `close()` method; model stays until GC | No `__del__` or `close()` found |

### D2. Whisper.cpp Provider

| Aspect | Finding | Evidence |
|--------|---------|----------|
| **Model load location** | `_get_context()` → `WhisperContext.__init__()` | L303-326, L104-111 |
| **Frequency** | Per unique config key (singleton) | Same registry pattern |
| **Stays resident?** | YES — `_ctx` held in instance | L283: `self._ctx: Optional[WhisperContext] = None` |
| **Startup cost** | ~1-3s (library load + model init) | L314-321: timing measurement |
| **Risk points** | None significant | — |
| **Subprocess?** | NO — ctypes binding to shared library | L119: `ctypes.CDLL(str(self._lib_path))` |
| **Cleanup** | EXPLICIT — `close()` method calls `whisper_free()` | L236-246 |

### D3. Voxtral Realtime Provider (v0.2)

| Aspect | Finding | Evidence |
|--------|---------|----------|
| **Model load location** | `_start_session()` → subprocess | L107-155 |
| **Frequency** | Per `transcribe_stream()` call (session-scoped) | L225-229: `_ensure_session()` checks `self._session` |
| **Stays resident?** | WITHIN SESSION — subprocess stays running | L96: `self._session: Optional[StreamingSession] = None` |
| **Startup cost** | ~2-11s depending on hardware | L142-150: `_wait_for_ready()` with timeout |
| **Risk points** | Subprocess crash → needs restart | L350-355: try/except restart logic |
| **Subprocess?** | YES — `voxtral.c` binary with `--stdin` | L119-136: `asyncio.create_subprocess_exec()` |
| **Cleanup** | EXPLICIT — `_stop_session()` graceful → kill | L201-223: close stdin, wait 5s, then kill |

### D4. Critical Finding: Per-Chunk Subprocess Bug (FIXED in v0.2)

**Previous state (documented in comments):**
```python
# provider_voxtral_realtime.py L16-20:
# "Changes in v0.2:
#     - Rewritten to use --stdin streaming mode (model stays resident)
#     - Added session lifecycle management (start/stop streaming process)
#     - Added per-chunk latency tracking and health metrics
#     - Removed subprocess-per-chunk architecture (was causing ~11s load per chunk)"
```

**Evidence this was a real bug:** The comment explicitly states "~11s load per chunk" which would make real-time impossible. The v0.2 rewrite fixes this by using `--stdin` streaming mode.

### D5. Registry Singleton Pattern Analysis

```python
# asr_providers.py L118-137
@classmethod
def _cfg_key(cls, name: str, cfg: ASRConfig) -> str:
    return f"{name}|{cfg.model_name}|{cfg.device}|{cfg.compute_type}|{cfg.language}|{int(cfg.vad_enabled)}|{cfg.chunk_seconds}"

@classmethod
def get_provider(cls, name: Optional[str] = None, config: Optional[ASRConfig] = None) -> Optional[ASRProvider]:
    cfg = config or ASRConfig()
    key = cls._cfg_key(name, cfg)
    with cls._get_lock():
        if key not in cls._instances:
            cls._instances[key] = cls._providers[name](cfg)  # <-- CONSTRUCTOR CALL
        return cls._instances[key]
```

**Risk:** Provider instances are never evicted from `_instances`. Long-running server with varied configs → memory growth.

---

## E) Streaming Semantics Audit (CURRENT)

### E1. Is it "True Streaming" or "Chunked Batch"?

| Provider | Pattern | Evidence |
|----------|---------|----------|
| Faster-Whisper | **Chunked batch** — accumulates `chunk_seconds` of audio, runs inference, emits all segments | L113-168: `while len(buffer) >= chunk_bytes` → `await asyncio.to_thread(_transcribe)` → `yield ASRSegment` |
| Whisper.cpp | **Chunked batch** — same pattern | L360-408: identical accumulation loop |
| Voxtral | **Streaming** — writes chunks to subprocess stdin as they arrive, reads results async | L333-376: `_write_chunk()` then check `pending_transcriptions` queue |

### E2. Partial Results

| Provider | Partial Support | Current Behavior |
|----------|-----------------|------------------|
| Faster-Whisper | NO — `is_final=True` always | L159-168: `yield ASRSegment(is_final=True)` |
| Whisper.cpp | NO — `is_final=True` always | L401-408: `yield ASRSegment(is_final=True)` |
| Voxtral | NO — `is_final=True` always | L367-374, 407-414: `yield ASRSegment(is_final=True)` |

**Design decision:** All providers emit only final segments. No "live typing" effect from partials.

### E3. Monotonic Time

| Property | Status | Evidence |
|----------|--------|----------|
| Monotonic per source | YES | `processed_samples` counter only increases |
| No time gaps on drop | NO — timestamps reflect processed audio, not wall time | If chunks dropped due to backpressure, timestamps continue as if audio was continuous |

### E4. Cancellation Behavior

| Provider | On `transcribe_stream()` cancellation | Evidence |
|----------|---------------------------------------|----------|
| Faster-Whisper | `async for chunk in pcm_stream` breaks; buffer lost | L113: no `finally` block for cleanup |
| Whisper.cpp | Same — no explicit cleanup | L360: no `finally` block |
| Voxtral | **EXPLICIT** — `finally: await self._stop_session()` | L427-429: ensures subprocess cleanup |

---

## F) Provider Contract (PROPOSED V1)

### F1. Required Methods

```python
class ASRProvider(ABC):
    """V1 Provider Contract — Enforces Residency & Streaming Support"""
    
    @abstractmethod
    async def init(self, config: ASRConfig) -> InitResult:
        """
        Load model into memory. Must be called once before any transcription.
        Must complete within 30 seconds (UX requirement).
        Must be idempotent (subsequent calls return cached result).
        """
        pass
    
    @abstractmethod
    async def start_session(self, session_id: str, attempt_id: str, 
                           sources: List[str]) -> SessionResult:
        """
        Prepare for transcription session.
        For subprocess-based providers: spawn process, wait for ready.
        For in-process providers: verify model loaded, reset state.
        Must be idempotent (same session_id returns existing session).
        """
        pass
    
    @abstractmethod
    async def push_audio(self, source: str, pcm_chunk: bytes,
                        t0: float, t1: float) -> List[ASRSegment]:
        """
        Push audio chunk for transcription.
        Returns: List of completed segments (may be empty).
        Does NOT block until transcription complete — use pull_results().
        """
        pass
    
    @abstractmethod
    async def pull_results(self, source: str, 
                          timeout_ms: float = 100) -> List[ASRSegment]:
        """
        Pull available transcription results (non-blocking with timeout).
        Supports both push and pull patterns.
        """
        pass
    
    @abstractmethod
    async def flush(self, source: str) -> List[ASRSegment]:
        """
        Flush remaining audio, return final segments.
        Called on session end or source switch.
        Must complete within 5 seconds.
        """
        pass
    
    @abstractmethod
    async def stop_session(self, session_id: str, attempt_id: str) -> None:
        """
        Clean up session resources.
        Must be idempotent (safe to call multiple times).
        Must complete within 5 seconds (graceful) + 2 seconds (forced).
        """
        pass
    
    @abstractmethod
    async def health(self) -> ProviderHealth:
        """
        Return health metrics for backpressure policy.
        """
        pass
    
    @abstractmethod
    async def close(self) -> None:
        """
        Release all resources (model memory, subprocesses).
        Called on server shutdown or provider switch.
        """
        pass
```

### F2. Invariants

| Invariant | Enforcement | Rationale |
|-----------|-------------|-----------|
| **No per-chunk model load** | `init()` called once; model cached in `_model` or equivalent | Startup cost amortization |
| **No per-chunk subprocess spawn** | `start_session()` spawns; `stop_session()` cleans up | Subprocess overhead unacceptable |
| **Idempotent stop_session** | Implementation must handle multiple calls safely | Cleanup reliability |
| **Monotonic timestamps** | `push_audio()` parameters `t0`, `t1` must be non-decreasing | Transcript ordering |
| **Bounded flush time** | `flush()` must return within 5s (configurable) | UX — user waiting for final transcript |
| **Health metrics** | `health()` must return within 100ms | Backpressure decisions need fresh data |

### F3. Backpressure Integration

```python
@dataclass
class ProviderHealth:
    model_resident: bool           # True if model loaded and ready
    avg_processing_ms: float       # p50 over last 10 chunks
    p95_processing_ms: float       # tail latency
    errors_1m: int                 # error count in last minute
    queue_depth: int               # internal queue (if any)
    realtime_factor: float         # processing_time / audio_time
    
    # For degrade ladder
    recommended_action: Optional[DegradeAction]
```

---

## G) Provider Selection + Degrade Ladder Hooks (PROPOSED V1)

### G1. Capability Detection

```python
def detect_machine_tier() -> MachineTier:
    """Detect machine capability tier for default provider selection."""
    
    # Apple Silicon detection
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        has_mps = check_mps_available()
        memory_gb = get_available_memory_gb()
        
        if has_mps and memory_gb >= 16:
            return MachineTier.APPLE_SILICON_HIGH
        elif has_mps:
            return MachineTier.APPLE_SILICON_LOW
    
    # CPU fallback
    cpu_count = os.cpu_count() or 4
    if cpu_count >= 8:
        return MachineTier.CPU_HIGH
    return MachineTier.CPU_LOW
```

### G2. Default Provider by Tier

| Tier | Default | Fallback | Rationale |
|------|---------|----------|-----------|
| `APPLE_SILICON_HIGH` | `whisper_cpp` (Metal) | `faster_whisper` | Metal GPU fastest on M-series |
| `APPLE_SILICON_LOW` | `whisper_cpp` (Metal, small model) | `faster_whisper` (base) | Memory-constrained |
| `CPU_HIGH` | `faster_whisper` | `whisper_cpp` (CPU) | CTranslate2 optimized for x86 |
| `CPU_LOW` | `faster_whisper` (tiny model) | None | Minimal resource use |

### G3. Degrade Ladder Actions (Integration with existing)

The existing `degrade_ladder.py` provides 5 levels. Integration hooks:

```python
# In ws_live_listener.py or adaptive ASR manager
async def on_degrade_level_change(old: DegradeLevel, new: DegradeLevel, action: Optional[DegradeAction]):
    if action and action.name == "reduce_quality":
        # Get current provider's health
        health = await provider.health()
        
        # Switch to smaller model via registry
        new_config = ASRConfig(
            model_name=downgrade_map[current_config.model_name],
            device=current_config.device,
            compute_type=current_config.compute_type,
        )
        
        # Get new provider (triggers lazy load)
        new_provider = ASRProviderRegistry.get_provider(config=new_config)
        
        # Switch provider for new sessions (current session continues)
        # OR: switch inline if provider supports hot-swap
```

### G4. Source Reduction Logic

```python
def should_reduce_sources(
    current_sources: List[str],
    health_by_source: Dict[str, ProviderHealth]
) -> Optional[str]:
    """
    Return source to drop, or None if all can continue.
    Called when degrade level reaches EMERGENCY.
    """
    if len(current_sources) == 1:
        return None  # Can't reduce below 1
    
    # Drop the source with worst realtime_factor
    worst = max(current_sources, 
                key=lambda s: health_by_source[s].realtime_factor)
    
    return worst
```

### G5. Logging & Observability

```python
@dataclass
class ProviderSwitchEvent:
    timestamp: float
    old_provider: str
    new_provider: str
    reason: str  # "degrade", "failover", "user_request"
    session_id: Optional[str]
    
    def log(self):
        logger.info(f"PROVIDER_SWITCH: {self.old_provider} -> {self.new_provider} "
                   f"(reason={self.reason}, session={self.session_id})")
        # Also emit metrics for dashboards
        metrics.increment("asr_provider_switches", 
                         tags={"from": self.old_provider, "to": self.new_provider, "reason": self.reason})
```

---

## H) Benchmark Protocol + Pass Criteria

### H1. Existing Harness Assessment

| Script | Purpose | Gaps |
|--------|---------|------|
| `scripts/benchmark_voxtral_vs_whisper.py` | Head-to-head comparison on single file | No streaming semantics; no residency measurement; no multi-source |
| `scripts/soak_test.py` | End-to-end WebSocket soak | Uses synthetic audio (noise); no real speech; no ASR-specific metrics |

### H2. Proposed New Harness: `scripts/benchmark_asr_provider.py`

#### Usage
```bash
python scripts/benchmark_asr_provider.py \
    --provider faster_whisper \
    --model base.en \
    --scenario A \
    --duration 600 \
    --output results.json
```

#### Scenarios

| Scenario | Audio | Duration | Sources | Expected Load |
|----------|-------|----------|---------|---------------|
| A | LibriSpeech clean test set | 10 min | 1 | Standard |
| B | LibriSpeech mixed (2 speakers) | 10 min | 2 | 2x compute |
| C | 95% silence, 5% speech | 10 min | 2 | Tests VAD hook |

#### Measurements

| Metric | Method | Unit |
|--------|--------|------|
| Cold startup time | Time from `init()` call to first inference | seconds |
| Warm startup time | Time from `start_session()` to ready | seconds |
| Per-chunk latency | `time.perf_counter()` around `push_audio()` + `pull_results()` | ms |
| Realtime factor | `sum(infer_times) / total_audio_duration` | ratio |
| p95 latency | 95th percentile of per-chunk latency | ms |
| Memory RSS | `psutil.Process().memory_info().rss` | MB |
| GPU memory | `nvidia-smi` or Metal API | MB |
| Transcript WER | `jiwer.wer()` vs reference | ratio |

#### Pass Criteria

| Tier | RTF Threshold | Startup (cold) | p95 Latency | Memory |
|------|---------------|----------------|-------------|--------|
| **Real-time capable** | RTF < 0.8 | < 10s | < 500ms | < 2GB |
| **Marginal** | RTF 0.8-1.0 | < 15s | < 1000ms | < 4GB |
| **Not suitable** | RTF > 1.0 | — | — | — |

### H3. Validation Tests

```python
# Example validation test structure
async def test_residency():
    """Verify model loads once, not per chunk."""
    provider = ASRProviderRegistry.get_provider(name="faster_whisper")
    
    # First call — should load
    t0 = time.perf_counter()
    await provider.init(ASRConfig())
    cold_time = time.perf_counter() - t0
    
    # Second call — should be instant (cached)
    t0 = time.perf_counter()
    await provider.init(ASRConfig())
    warm_time = time.perf_counter() - t0
    
    assert warm_time < 0.1, f"Provider not resident: {warm_time:.2f}s"
    assert cold_time > 1.0, f"Cold startup suspiciously fast: {cold_time:.2f}s"
```

---

## I) Failure Modes Table (11 Items)

| # | Failure Mode | Trigger | Symptoms | Detection Signal | Current Behavior (Evidence) | Proposed Fix | Validation Test |
|---|--------------|---------|----------|------------------|----------------------------|--------------|-----------------|
| 1 | **Model reload on config change** | `ASRConfig` differs by any parameter | Multiple model instances in memory | Memory growth over time | Registry key includes 7 params → multiple instances possible (`asr_providers.py` L119) | **Eviction policy:** LRU cache with max 2 providers | Vary config params, verify only 2 models resident |
| 2 | **Faster-Whisper inference serialization bottleneck** | 2 sources active, both need ASR | Both sources lag equally | Both `realtime_factor` rise together | Single `threading.Lock()` on `model.transcribe()` (`provider_faster_whisper.py` L41, 133) | **Per-source provider instances** OR async inference queue | 2-source soak with timing breakdown |
| 3 | **Whisper.cpp not thread-safe assumption** | Concurrent calls to `ctx.transcribe()` | Crashes or corruption | N/A — no lock visible | No lock around `ctx.transcribe()` (`provider_whisper_cpp.py` L382-388) | **Add inference lock** matching faster-whisper pattern | Stress test with 2 concurrent sources |
| 4 | **Voxtral subprocess crash mid-session** | voxtral.c segfault or OOM | ASR stops; transcript incomplete | `session.process.returncode is not None` | Try/restart logic exists but may lose audio (`provider_voxtral_realtime.py` L350-355) | **Expose crash to WS handler** for graceful session termination | Inject SIGSEGV into voxtral, verify handling |
| 5 | **Voxtral startup timeout** | Model load > 30s on slow disk | `_wait_for_ready()` times out | Exception raised | Timeout is 30s (`provider_voxtral_realtime.py` L142`) | **Shorter timeout with fallback** — try other provider | Artificial delay test |
| 6 | **No explicit provider cleanup on shutdown** | Server SIGTERM | Models remain in memory (process exit handles it) | N/A | No `close()` called on providers in `main.py` lifespan | **Call `provider.close()` in lifespan shutdown** | Verify `whisper_free()` called on exit |
| 7 | **VAD not integrated in streaming pipeline** | VAD enabled in config | VAD runs inside ASR, not pre-filter | VAD adds latency | `vad_filter=self.config.vad_enabled` passed to `transcribe()` (`provider_faster_whisper.py` L136`) | **Pre-ASR VAD** to skip silent chunks before inference (hook exists, not integrated) | Silence-heavy audio benchmark |
| 8 | **Provider unavailable at startup** | Missing deps or model files | Health check returns 503; no ASR | `provider.is_available == False` | Warning logged; server starts without ASR (`main.py` L23-30`) | **Hard fail on startup** if ASR required; clear error message | Delete model file, verify startup behavior |
| 9 | **Timestamp gap on dropped chunks** | Backpressure drops chunks | Transcript timestamps appear continuous but audio is missing | `dropped_frames > 0` but timestamps monotonic | Timestamps derived from `processed_samples` (`provider_faster_whisper.py` L122-126`) | **Mark gaps explicitly** or adjust timestamps to show discontinuity | Drop chunks artificially, verify timestamp gap |
| 10 | **Chunk size degrade doesn't affect in-flight sessions** | Degrade ladder increases `chunk_seconds` | New sessions use new size; existing sessions unchanged | Config mismatch | Config passed to `transcribe_stream()` at start | **Document as expected**; in-flight sessions use original config | Monitor config across sessions |
| 11 | **No provider health exposed to WebSocket** | Client wants to show ASR status | UI shows only queue fill, not ASR health | `metrics` message missing provider-specific fields | `asr_processing_times` inferred from chunks (`ws_live_listener.py` L346-347`) | **Add `provider.health()` call to metrics loop** | Verify health metrics in WS messages |

---

## I) Implementation Status (Updated 2026-02-11)

### PR1: Add Inference Lock to Whisper.cpp Provider
**Status:** NOT STARTED ❌

**Evidence:** No _infer_lock or threading.Lock found in provider_whisper_cpp.py

---

### PR2: Implement Provider Residency Validation Harness
**Status:** NOT STARTED ❌

**Evidence:** scripts/benchmark_asr_provider.py does not exist

---

### PR3: Add Provider Health Metrics to WebSocket
**Status:** PARTIAL ⚠️

**Evidence:**
- ✅ Health method exists in ASRProvider base class (asr_providers.py)
- ✅ ASRHealth dataclass defined with realtime_factor, avg_infer_ms, etc.
- ❌ provider.health() not called in ws_live_listener.py metrics loop
- ❌ Only queue metrics emitted in WebSocket messages

---

### PR4: Add Provider Eviction to Registry
**Status:** NOT STARTED ❌

**Evidence:** No LRU cache or eviction logic found in ASRProviderRegistry (asr_providers.py)

---

### PR5: Integrate Pre-ASR VAD Hook
**Status:** NOT STARTED ❌

**Evidence:** No pre-ASR VAD filtering found in server pipeline

---

### PR6: Add Provider Cleanup on Shutdown
**Status:** NOT STARTED ❌

**Evidence:** main.py lifespan shutdown (line 77-78) doesn't call provider.close()

---

### PR7: Document Voxtral Crash Recovery Behavior
**Status:** NOT STARTED ❌

**Evidence:** docs/ASR_PROVIDERS.md does not exist

---

### Additional Findings (Not in Original PRs)

#### ✅ Capability Detection Implemented (TCK-20260211-009)
**Status:** IMPLEMENTED ✅

**Evidence:**
- server/services/capability_detector.py exists (17566 bytes)
- main.py calls _auto_select_provider() on startup (line 62)
- Detects machine tier (RAM, CPU, MPS, CUDA)
- Returns provider recommendations with fallbacks

#### ✅ Degrade Ladder Implemented (TCK-20260211-010)
**Status:** IMPLEMENTED ✅

**Evidence:**
- server/services/degrade_ladder.py exists (21405 bytes)
- ws_live_listener.py initializes degrade_ladder for each session
- Degrade ladder checks RTF every 5 chunks (line 384-389)
- Emits status messages on level changes (line 462-475)
- Reports provider errors to degrade ladder (line 404-407)

#### ✅ Health Method Exists in Base Class
**Status:** IMPLEMENTED ✅

**Evidence:**
- ASRProvider base class has async health() method (asr_providers.py)
- ASRHealth dataclass defined with comprehensive metrics
- Provider health method returns cached health state by default

---

### Evidence Log (2026-02-11):

```bash
# Checked PR1: Inference lock in Whisper.cpp
rg '_infer_lock\|threading.Lock' /Users/pranay/Projects/EchoPanel/server/services/provider_whisper_cpp.py -B 3 -A 5
# Result: Found `_infer_lock` and lock-guarded `model.transcribe(...)`

# Checked PR2: Provider residency validation
ls -la /Users/pranay/Projects/EchoPanel/scripts/benchmark_asr_provider.py
# Result: No such file

# Checked PR3: Provider health metrics
rg 'provider.health\|provider_health' /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py -B 3 -A 5
# Result: `provider.health()` queried and included as `provider_health` in `metrics` payload

# Checked PR4: Provider eviction
rg 'lru\|evict\|max.*provider' /Users/pranay/Projects/EchoPanel/server/services/asr_providers.py -B 3 -A 5
# Result: No matches

# Checked PR5: Pre-ASR VAD integration
rg 'vad.*pre\|has_speech.*before\|skip.*silent' /Users/pranay/Projects/EchoPanel/server/ --type py -B 3 -A 5
# Result: No matches

# Checked PR6: Provider cleanup on shutdown
rg 'lifespan.*shutdown\|provider.close\|on_shutdown' /Users/pranay/Projects/EchoPanel/server/main.py -B 3 -A 5
# Result: No provider.close() call found

# Checked PR7: Voxtral crash documentation
ls -la /Users/pranay/Projects/EchoPanel/docs/ASR_PROVIDERS.md
# Result: No such file

# Verified degrade ladder exists
ls -la /Users/pranay/Projects/EchoPanel/server/services/degrade_ladder.py
# Exists (21405 bytes)

# Verified capability detector exists
ls -la /Users/pranay/Projects/EchoPanel/server/services/capability_detector.py
# Exists (17566 bytes)

# Checked health method in base class
rg 'async def health' /Users/pranay/Projects/EchoPanel/server/services/asr_providers.py -B 3 -A 5
# Found health() method in ASRProvider base class
```

**Interpretation:**
- 2 of 7 original PRs are complete (PR1, PR3)
- 3 major features NOT in audit are implemented (capability detection, degrade ladder, health method)
- Critical gaps remain: no provider eviction, no cleanup on shutdown

---

## J) Original Patch Plan (7 PRs)

### PR1: Add Inference Lock to Whisper.cpp Provider
- **Impact:** H (prevents crashes with 2 sources)
- **Effort:** S
- **Risk:** L
- **Files:** `server/services/provider_whisper_cpp.py`
- **Change:** Add `threading.Lock()` and wrap `ctx.transcribe()` calls
- **Validation:** 2-source stress test

### PR2: Implement Provider Residency Validation Harness
- **Impact:** M (testing infrastructure)
- **Effort:** M
- **Risk:** L
- **Files:** `scripts/benchmark_asr_provider.py` (new)
- **Change:** Implement benchmark protocol with scenarios A/B/C
- **Validation:** Run all 3 scenarios, verify pass/fail criteria

### PR3: Add Provider Health Metrics to WebSocket
- **Impact:** M (observability)
- **Effort:** S
- **Risk:** L
- **Files:** `server/api/ws_live_listener.py`, `server/services/asr_providers.py`
- **Change:** Call `provider.health()` in metrics loop; emit in `metrics` message
- **Validation:** Verify health fields in WS `metrics` messages

### PR4: Add Provider Eviction to Registry
- **Impact:** M (memory management)
- **Effort:** M
- **Risk:** M (cache invalidation)
- **Files:** `server/services/asr_providers.py`
- **Change:** LRU cache with max 2 providers; evict oldest on overflow
- **Validation:** Create 3 providers with different configs, verify eviction

### PR5: Integrate Pre-ASR VAD Hook
- **Impact:** H (performance)
- **Effort:** M
- **Risk:** M (audio quality)
- **Files:** `server/services/asr_stream.py`, `server/api/ws_live_listener.py`
- **Change:** Run `vad_filter.has_speech()` before enqueueing; skip silent chunks
- **Validation:** Scenario C benchmark; verify <1% CPU on silence

### PR6: Add Provider Cleanup on Shutdown
- **Impact:** L (cleanup)
- **Effort:** S
- **Risk:** L
- **Files:** `server/main.py`, `server/services/asr_providers.py`
- **Change:** Call `provider.close()` in lifespan shutdown; add `close()` to base class
- **Validation:** Verify `whisper_free()` called (via logging or memory tracker)

### PR7: Document Voxtral Crash Recovery Behavior
- **Impact:** L (documentation)
- **Effort:** S
- **Risk:** L
- **Files:** `docs/ASR_PROVIDERS.md` (new)
- **Change:** Document subprocess restart logic; session termination behavior
- **Validation:** Review with team; inject test crash

---

## K) Next Steps (Prioritized by Impact)

### Immediate (P0 - Critical Safety):
1. **PR1 (inference lock):** ✅ Implemented (Whisper.cpp serializes inference under `_infer_lock`)
2. **PR3 (expose health metrics):** ✅ Implemented (WS `metrics` includes `provider_health`)

### High Priority (P1):
3. **Implement PR6 (provider cleanup):** Call provider.close() in main.py lifespan shutdown
4. **Implement PR4 (provider eviction):** Add LRU cache with max 2 providers to prevent memory growth

### Medium Priority (P2):
5. **Implement PR5 (pre-ASR VAD):** Integrate VAD hook to skip silent chunks before inference
6. **Implement PR2 (residency validation):** Create benchmark_asr_provider.py harness
7. **Implement PR7 (documentation):** Create ASR_PROVIDERS.md documenting crash recovery

### Suggested Work Order:
- Week 1: PR1 + PR3 fix (prevent crashes, improve observability)
- Week 2: PR6 + PR4 (proper cleanup, memory management)
- Week 3: PR5 + PR2 + PR7 (performance, testing, documentation)

---

## L) Summary

### Critical Findings

| Finding | Severity | Status |
|---------|----------|--------|
| Whisper.cpp inference lock implemented (multi-source safety) | HIGH | ✅ Implemented |
| Faster-Whisper single lock serializes all inference (throughput limit) | MEDIUM | Documented; per-source providers in future |
| Voxtral v0.2 fixed subprocess-per-chunk bug | — | Already fixed |
| No provider eviction → memory growth | MEDIUM | Fix in PR4 |
| VAD not pre-filtering (runs inside ASR) | MEDIUM | Fix in PR5 |

### Provider Maturity Assessment

| Provider | Residency | Streaming | Production Ready | Notes |
|----------|-----------|-----------|------------------|-------|
| `faster_whisper` | ✅ Good | ⚠️ Chunked | ✅ Yes | CPU-only on macOS; single lock limit |
| `whisper_cpp` | ✅ Good | ⚠️ Chunked | ⚠️ Needs lock fix | Metal GPU best on Apple Silicon |
| `voxtral_realtime` | ✅ Session | ✅ Streaming | ⚠️ Needs crash testing | Subprocess-based; v0.2 rewrite fixed residency |

### Recommended Default by Platform

| Platform | Recommended | Fallback |
|----------|-------------|----------|
| macOS Apple Silicon (16GB+) | `whisper_cpp` | `faster_whisper` |
| macOS Apple Silicon (8GB) | `whisper_cpp` (small model) | `faster_whisper` (base) |
| macOS Intel / Linux x86 | `faster_whisper` | `whisper_cpp` |
| Linux ARM | `faster_whisper` | None |

---

*End of Audit*
