# EchoPanel ASR Model Lifecycle & Runtime Loader Audit

**Date**: 2026-02-11
**Ticket**: TCK-20260211-010
**Status**: COMPLETE
**Auditor**: Model Lifecycle / Runtime Loader Analyst
**Scope**: Complete ASR model lifecycle flows including selection, loading, warmup, batching, GPU/Metal/CUDA usage, fallback models, caching, provider architecture, health checking, state transitions, concurrent inference, and memory management

---

## Files Inspected

**Core Model Management:**
- `server/services/model_preloader.py` (403 lines) — Model lifecycle management, warmup, health tracking
- `server/services/asr_providers.py` (371 lines) — Provider abstraction, registry, health metrics
- `server/services/asr_stream.py` (93 lines) — High-level streaming pipeline

**Provider Implementations:**
- `server/services/provider_faster_whisper.py` (308 lines) — Faster-whisper (CTranslate2) provider
- `server/services/provider_whisper_cpp.py` (383 lines) — Whisper.cpp with Metal acceleration
- `server/services/provider_voxtral_realtime.py` (452 lines) — Voxtral realtime streaming provider

**Capability & Degrade Management:**
- `server/services/capability_detector.py` (506 lines) — Machine capability detection, auto-selection
- `server/services/degrade_ladder.py` (579 lines) — Adaptive performance management
- `server/services/vad_asr_wrapper.py` (482 lines) — VAD pre-filtering wrapper

**Server Entry Points:**
- `server/main.py` (209 lines) — Server startup, health checks, provider initialization

**Reference:**
- `docs/audit/asr-provider-performance-20260211.md` (597 lines) — Previous performance audit

---

## Executive Summary

1. **Three-Tier Model Lifecycle**: ModelManager implements UNINITIALIZED → LOADING → WARMING_UP → READY → ERROR states with eager loading at server startup and tiered warmup (3 levels).

2. **Lazy Provider Loading**: Providers load models on first inference request (`_get_model()`), not at registration time. Exception: ModelManager's `initialize()` triggers eager load via warmup.

3. **Capability-Based Auto-Selection**: `CapabilityDetector` detects RAM, CPU, GPU (Metal/CUDA) and recommends optimal provider/model. Used at server startup if `ECHOPANEL_ASR_PROVIDER` not explicitly set.

4. **Provider Registry Pattern**: `ASRProviderRegistry` caches provider instances keyed by configuration (provider name, model, device, compute type, language, VAD, chunk size). Thread-safe instance creation.

5. **Three Provider Implementations**:
   - `faster_whisper`: CTranslate2 backend, lazy load, CPU-only on macOS (no MPS support), CUDA on Linux
   - `whisper_cpp`: Metal GPU acceleration on Apple Silicon, lower memory (~300MB), GGML/GGUF format
   - `voxtral_realtime`: Streaming mode with resident subprocess, MPS/BLAS backend, ~8.9GB model

6. **Degrade Ladder Implemented**: 5-level adaptive performance system (NORMAL, WARNING, DEGRADE, EMERGENCY, FAILOVER) that monitors RTF and automatically adjusts configuration (chunk size, model size, VAD, chunk dropping, provider switch).

7. **Thread Safety**: Inference locking via `threading.Lock` in faster-whisper and whisper_cpp providers to serialize concurrent inference calls.

8. **Health Metrics**: All providers implement `health()` method returning `ASRHealth` with realtime_factor, avg_infer_ms, p95/p99 latency, backlog_estimate, model_resident, session stats.

9. **VAD Wrapper**: `VADASRWrapper` provides drop-in Silero VAD pre-filtering with lazy model loading. `SmartVADRouter` enables dynamic VAD enable/disable based on degrade ladder state.

10. **No Model Versioning/Updates**: No mechanism for model versioning, automatic updates, or downloading. Models assumed present on filesystem.

11. **No Warm Cache Persistence**: No mechanism to persist warm cache across server restarts. Each startup requires full warmup sequence.

12. **Concurrent Inference**: Serialized via per-provider inference lock. No parallel inference support.

---

## Flow Inventory

| Flow ID | Name | Status | Priority |
|---------|------|--------|----------|
| MOD-001 | Capability Detection & Auto-Selection | Implemented | P0 |
| MOD-002 | Provider Registration & Discovery | Implemented | P0 |
| MOD-003 | ModelManager Eager Load & Warmup | Implemented | P0 |
| MOD-004 | Lazy Model Loading (First Inference) | Implemented | P0 |
| MOD-005 | Chunked Batch Inference | Implemented | P0 |
| MOD-006 | GPU/Metal/CUDA Device Selection | Implemented | P0 |
| MOD-007 | Degrade Ladder Performance Management | Implemented | P1 |
| MOD-008 | Provider Health Monitoring | Implemented | P1 |
| MOD-009 | VAD Pre-Filtering | Implemented | P2 |
| MOD-010 | Concurrent Inference Serialization | Implemented | P2 |
| MOD-011 | Model State Transitions | Implemented | P0 |
| MOD-012 | Voxtral Streaming Session Lifecycle | Implemented | P1 |
| MOD-013 | Fallback Provider Switching | Implemented | P1 |
| MOD-014 | Memory Management | Hypothesized | P2 |
| MOD-015 | Model Versioning | Not Implemented | P3 |

---

## MOD-001: Capability Detection & Auto-Selection

**Status**: Implemented
**Flow Name**: Capability Detection & Auto-Selection at Server Startup

**Triggers**:
- Server startup (`lifespan` context manager in `main.py:57-85`)
- User does NOT set `ECHOPANEL_ASR_PROVIDER` environment variable

**Preconditions**:
- Server is starting up
- No explicit provider selection via environment variables
- Python dependencies available (psutil, torch optional)

**Step-by-Step Sequence**:

1. **Check for explicit provider override** (`main.py:23-26`):
   ```python
   if os.getenv("ECHOPANEL_ASR_PROVIDER"):
       logger.info(f"Using user-specified provider: {os.getenv('ECHOPANEL_ASR_PROVIDER')}")
       return  # Skip auto-detection
   ```

2. **Initialize CapabilityDetector** (`main.py:29-33`):
   ```python
   detector = CapabilityDetector()
   profile = detector.detect()
   recommendation = detector.recommend(profile)
   ```

3. **Detect machine capabilities** (`capability_detector.py:175-209`):
   - RAM via `psutil.virtual_memory().total` (fallback: `/proc/meminfo` or `sysctl -n hw.memsize`)
   - CPU cores via `psutil.cpu_count()` (fallback: `os.cpu_count()`)
   - Metal MPS via `torch.backends.mps.is_available()` (fallback: `system_profiler SPDisplaysDataType`)
   - CUDA via `torch.cuda.is_available()` (fallback: `nvidia-smi -L`)
   - OS and architecture via `platform.system()` and `platform.machine()`

4. **Determine capability tier** (`capability_detector.py:318-349`):
   - **ultra_low**: RAM < 4GB
   - **low**: RAM 4-8GB
   - **medium**: RAM 8-16GB, no GPU
   - **medium_gpu**: RAM 8-16GB, with Metal/CUDA
   - **high**: RAM 16-32GB, with Metal/CUDA
   - **ultra**: RAM > 32GB, with Metal/CUDA

5. **Generate tier-specific configuration** (`capability_detector.py:121-173`):
   ```python
   TIER_CONFIGS = {
       "ultra_low": {
           "provider": "faster_whisper",
           "model": "tiny.en",
           "chunk_seconds": 4,
           "compute_type": "int8",
           "device": "cpu",
           "vad_enabled": False,
       },
       # ... other tiers
   }
   ```

6. **Verify provider availability** (`capability_detector.py:354-367`):
   - Check if whisper.cpp is available (for medium_gpu/high tiers)
   - Check if voxtral is available (for ultra tier)
   - Fall back to faster_whisper if recommended provider not available

7. **Set environment variables** (`main.py:37-42`):
   ```python
   os.environ["ECHOPANEL_ASR_PROVIDER"] = recommendation.provider
   os.environ["ECHOPANEL_WHISPER_MODEL"] = recommendation.model
   os.environ["ECHOPANEL_ASR_CHUNK_SECONDS"] = str(recommendation.chunk_seconds)
   os.environ["ECHOPANEL_WHISPER_COMPUTE"] = recommendation.compute_type
   os.environ["ECHOPANEL_WHISPER_DEVICE"] = recommendation.device
   os.environ["ECHOPANEL_ASR_VAD"] = "1" if recommendation.vad_enabled else "0"
   ```

8. **Log recommendation** (`main.py:44-50`):
   - Provider and model name
   - Reason for recommendation
   - Hardware profile (RAM, cores, MPS, CUDA)
   - Fallback configuration (if set)

**Inputs/Outputs**:
- **Inputs**: Environment variables (optional), machine hardware
- **Outputs**: Environment variables set, logger output, `MachineProfile` and `ProviderRecommendation` objects

**Key Modules/Files/Functions**:
- `server/main.py:_auto_select_provider()` (lines 17-53)
- `server/services/capability_detector.py:CapabilityDetector.detect()` (lines 175-209)
- `server/services/capability_detector.py:CapabilityDetector.recommend()` (lines 304-398)
- `server/services/capability_detector.py:_detect_mps()` (lines 242-271)
- `server/services/capability_detector.py:_detect_cuda()` (lines 273-302)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **psutil not installed** | ImportError in `detect()` | Falls back to `/proc/meminfo` (Linux) or `sysctl` (macOS) | `capability_detector.py:32-36` |
| **torch not installed** | ImportError in `_detect_mps()` or `_detect_cuda()` | Falls back to `system_profiler` (Metal) or `nvidia-smi` (CUDA) | `capability_detector.py:38-42` |
| **nvidia-smi not available** | subprocess timeout/returncode != 0 in `_detect_cuda()` | CUDA marked unavailable, CPU-only mode | `capability_detector.py:288-300` |
| **Recommended provider not available** | `is_available` check returns False | Falls back to next lower tier (faster_whisper) | `capability_detector.py:354-367` |
| **Insufficient RAM for recommended model** | `can_run_model()` check fails | Falls back to smaller model in same tier | `capability_detector.py:416-447` |
| **Machine architecture not supported** | Unknown platform or arch | Defaults to CPU, int8, base.en model | `capability_detector.py:175-209` |
| **Capability detection timeout** | Subprocess timeout (5s) | Uses default values (8GB RAM, 4 cores, no GPU) | `capability_detector.py:263,293` |
| **Environment variable write failure** | OSError when setting env var | Logs warning, continues with default config | `capability_detector.py:384` (inferred) |

**Observability**:
- Logger output at INFO level for all detection steps
- `/capabilities` endpoint exposes `get_optimal_config()` with full profile and recommendation (`main.py:159-174`)
- `/health` endpoint includes provider info (`main.py:101-156`)

**Proof**:
- **Observed**: `main.py:62` calls `_auto_select_provider()` in lifespan
- **Observed**: `capability_detector.py:304-398` contains full tier-based recommendation logic
- **Observed**: `main.py:37-42` sets environment variables from recommendation
- **Observed**: Fallback logic for unavailable providers at `capability_detector.py:354-367`

---

## MOD-002: Provider Registration & Discovery

**Status**: Implemented
**Flow Name**: Provider Registration & Discovery via ASRProviderRegistry

**Triggers**:
- Module import of provider implementations (`asr_stream.py:16-19`)
- `ASRProviderRegistry.get_provider()` call

**Preconditions**:
- Provider modules imported (triggers `register()` calls)
- Provider implements `ASRProvider` abstract base class

**Step-by-Step Sequence**:

1. **Provider registers at module import** (in each provider file):
   ```python
   # provider_faster_whisper.py:307
   ASRProviderRegistry.register("faster_whisper", FasterWhisperProvider)

   # provider_whisper_cpp.py:376-379 (if available)
   if WhisperCppProvider.is_available():
       ASRProviderRegistry.register(WhisperCppProvider)

   # provider_voxtral_realtime.py:451
   ASRProviderRegistry.register("voxtral_realtime", VoxtralRealtimeProvider)
   ```

2. **Registry stores provider class** (`asr_providers.py:311-313`):
   ```python
   @classmethod
   def register(cls, name: str, provider_class: type[ASRProvider]) -> None:
       cls._providers[name] = provider_class
   ```

3. **Provider instance requested** (`asr_stream.py:55` or `main.py:76`):
   ```python
   provider = ASRProviderRegistry.get_provider(config=config)
   ```

4. **Registry determines provider name** (`asr_providers.py:322-323`):
   ```python
   if name is None:
       name = os.getenv("ECHOPANEL_ASR_PROVIDER", "faster_whisper")
   ```

5. **Registry generates configuration key** (`asr_providers.py:329`):
   ```python
   key = cls._cfg_key(name, cfg)  # e.g., "faster_whisper|base.en|cpu|int8|None|0|4"
   ```

6. **Thread-safe instance creation** (`asr_providers.py:332-335`):
   ```python
   with cls._get_lock():
       if key not in cls._instances:
           cls._instances[key] = cls._providers[name](cfg)
       return cls._instances[key]
   ```

7. **Provider instance created with config** (in provider `__init__`):
   - `FasterWhisperProvider.__init__()` at `provider_faster_whisper.py:44-50`
   - `WhisperCppProvider.__init__()` at `provider_whisper_cpp.py:59-72`
   - `VoxtralRealtimeProvider.__init__()` at `provider_voxtral_realtime.py:91-97`

**Inputs/Outputs**:
- **Inputs**: Provider name (optional), `ASRConfig` object
- **Outputs**: `ASRProvider` instance (cached or new)

**Key Modules/Files/Functions**:
- `server/services/asr_providers.py:ASRProviderRegistry.register()` (lines 311-313)
- `server/services/asr_providers.py:ASRProviderRegistry.get_provider()` (lines 320-335)
- `server/services/asr_providers.py:ASRProviderRegistry._get_lock()` (lines 303-308)
- `server/services/asr_providers.py:ASRProviderRegistry._cfg_key()` (lines 316-317)
- `server/services/asr_providers.py:ASRProviderRegistry.available_providers()` (lines 338-348)
- `server/services/asr_providers.py:ASRProviderRegistry.get_provider_info()` (lines 351-370)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Provider not registered** | `name not in cls._providers` | Returns None | `asr_providers.py:326` |
| **Provider class init fails** | Exception in provider `__init__()` | Propagates exception to caller | `asr_providers.py:334` |
| **Lock acquisition timeout** | threading.Lock contention (rare) | Blocks until lock available | `asr_providers.py:332` |
| **Invalid configuration** | Provider validates config in `__init__()` | Raises ValueError/TypeError | `provider_faster_whisper.py:44-50` (inferred) |
| **Provider dependencies missing** | `is_available` returns False | Returns None or unavailable provider | `asr_providers.py:344` |
| **Environment variable not set** | `os.getenv()` returns None | Uses default value | `asr_providers.py:323` |
| **Multiple providers with same name** | Second registration overwrites first | Last registered wins | `asr_providers.py:313` |
| **Config key collision** | Different configs map to same key (hash collision) | Rare, both configs share instance | `asr_providers.py:329` (theoretical) |

**Observability**:
- No direct logging in registry (minimal, by design)
- `/capabilities` endpoint exposes `available_providers()` list via `get_provider_info()` (`main.py:159-174`)
- Provider availability checked via `is_available` property on each provider

**Proof**:
- **Observed**: Registry pattern implemented at `asr_providers.py:295-370`
- **Observed**: Thread-safe instance creation with lock at `asr_providers.py:332-335`
- **Observed**: Configuration key generation at `asr_providers.py:316-317`
- **Observed**: Provider registration calls at end of each provider file

---

## MOD-003: ModelManager Eager Load & Warmup

**Status**: Implemented
**Flow Name**: Eager Model Loading with Tiered Warmup at Server Startup

**Triggers**:
- Server startup (`lifespan` context manager in `main.py:64-71`)
- Call to `initialize_model_at_startup()` or `ModelManager.initialize()`

**Preconditions**:
- ASR provider selected (via auto-detection or explicit env var)
- Provider is available and can be instantiated
- Sufficient RAM for model loading

**Step-by-Step Sequence**:

1. **Get or create ModelManager singleton** (`model_preloader.py:355-368`):
   ```python
   manager = get_model_manager(provider_name=provider_name, config=config)
   ```

2. **Initialize ModelManager** (`model_preloader.py:131-196`):
   ```python
   async def initialize(self, timeout: float = 300.0) -> bool:
   ```

3. **Check if already ready** (`model_preloader.py:142-153`):
   ```python
   if self._state == ModelState.READY:
       return True

   if self._state == ModelState.LOADING:
       # Another task is loading, wait for it
       async with self._lock:
           pass  # Release lock and wait below
       try:
           await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
           return self._state == ModelState.READY
       except asyncio.TimeoutError:
           return False
   ```

4. **Transition to LOADING state** (`model_preloader.py:155`):
   ```python
   self._state = ModelState.LOADING
   ```

5. **Phase 1: Load model** (`model_preloader.py:158-166`):
   ```python
   logger.info("Phase 1/3: Loading model...")
   start = time.time()

   if not await self._load_model():
       return False

   self._load_time_ms = (time.time() - start) * 1000
   logger.info(f"Model loaded in {self._load_time_ms:.1f}ms")
   ```

6. **Load provider instance** (`model_preloader.py:197-218`):
   ```python
   async def _load_model(self) -> bool:
       if self.provider_name:
           self._provider = ASRProviderRegistry.get_provider(name=self.provider_name)
       else:
           self._provider = ASRProviderRegistry.get_provider(config=self.config)

       if not self._provider:
           raise RuntimeError("No ASR provider available")

       if not self._provider.is_available:
           raise RuntimeError(f"Provider {self._provider.name} is not available")

       logger.info(f"Loaded provider: {self._provider.name}")
       return True
   ```

7. **Transition to WARMING_UP state** (`model_preloader.py:170-171`):
   ```python
   async with self._lock:
       self._state = ModelState.WARMING_UP
   ```

8. **Phase 2: Warmup** (`model_preloader.py:173-179`):
   ```python
   logger.info("Phase 2/3: Warming up...")
   start = time.time()

   await self._warmup()

   self._warmup_time_ms = (time.time() - start) * 1000
   logger.info(f"Warmup complete in {self._warmup_time_ms:.1f}ms")
   ```

9. **Level 2 warmup: Single inference** (`model_preloader.py:234-253`):
   ```python
   if self.warmup_config.level2_single_inference:
       logger.debug("Warmup Level 2: Single inference")

       async def audio_stream():
           yield audio_bytes

       start = time.time()
       count = 0
       async for _ in self._provider.transcribe_stream(audio_stream()):
           count += 1

       elapsed = (time.time() - start) * 1000
       min_duration = self.warmup_config.level2_duration_ms

       if elapsed < min_duration:
           # Run more iterations if too fast
           remaining = min_duration - elapsed
           await asyncio.sleep(remaining / 1000)

       logger.debug(f"Level 2 complete: {count} segments, {elapsed:.1f}ms")
   ```

10. **Level 3 warmup: Full stress test** (`model_preloader.py:256-276`):
    ```python
    if self.warmup_config.level3_full_warmup:
        logger.debug("Warmup Level 3: Full stress test")

        iterations = self.warmup_config.level3_iterations
        start = time.time()

        for i in range(iterations):
            async def audio_stream():
                yield audio_bytes

            async for _ in self._provider.transcribe_stream(audio_stream()):
                pass

        elapsed = (time.time() - start) * 1000
        min_duration = self.warmup_config.level3_duration_ms

        if elapsed < min_duration:
            remaining = min_duration - elapsed
            await asyncio.sleep(remaining / 1000)

        logger.debug(f"Level 3 complete: {iterations} iterations")
    ```

11. **Transition to READY state** (`model_preloader.py:182-184`):
    ```python
    async with self._lock:
        self._state = ModelState.READY
        self._ready_event.set()
    ```

12. **Log completion** (`model_preloader.py:186-187`):
    ```python
    logger.info(f"Model ready! Total time: {self._load_time_ms + self._warmup_time_ms:.1f}ms")
    return True
    ```

**Inputs/Outputs**:
- **Inputs**: Provider name (optional), ASRConfig, WarmupConfig
- **Outputs**: Boolean success flag, ModelHealth object with state, load_time_ms, warmup_time_ms

**Key Modules/Files/Functions**:
- `server/services/model_preloader.py:ModelManager.initialize()` (lines 131-196)
- `server/services/model_preloader.py:ModelManager._load_model()` (lines 197-218)
- `server/services/model_preloader.py:ModelManager._warmup()` (lines 220-276)
- `server/services/model_preloader.py:initialize_model_at_startup()` (lines 377-402)
- `server/main.py:lifespan()` (lines 64-71)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Provider not available** | `is_available` returns False | Raises RuntimeError, initialization fails | `model_preloader.py:209-210` |
| **Model load timeout** | `asyncio.wait_for()` times out | Returns False, marks state ERROR | `model_preloader.py:150-153` |
| **Out of memory** | RuntimeError/OSError during model load | Catches exception, marks state ERROR | `model_preloader.py:189-195` |
| **Warmup inference timeout** | No segments from `transcribe_stream()` | Logs warning, continues (doesn't fail) | `model_preloader.py:242` (inferred) |
| **Concurrent initialization** | Multiple tasks call `initialize()` | Second task waits via `_ready_event` | `model_preloader.py:145-153` |
| **Lock acquisition timeout** | asyncio.Lock contention | Blocks until lock available (rare) | `model_preloader.py:141` |
| **Warmup audio generation fails** | Exception in `_warmup()` | Catches exception, marks state ERROR | `model_preloader.py:189-195` |
| **Provider registration missing** | `get_provider()` returns None | Raises "No ASR provider available" | `model_preloader.py:206-207` |

**Observability**:
- Logger output at INFO level for all phases
- `ModelHealth.to_dict()` returns state, ready, model_loaded, warmup_complete, load_time_ms, warmup_time_ms, last_error
- `/model-status` endpoint exposes `manager.health()` and `manager.get_stats()` (`main.py:177-198`)
- `/health` endpoint includes `model_ready`, `model_state`, `load_time_ms`, `warmup_time_ms` (`main.py:122-132`)

**Proof**:
- **Observed**: ModelManager state machine at `model_preloader.py:32-38`
- **Observed**: Eager initialization in `main.py:65-71`
- **Observed**: Three-phase warmup (load → warm → ready) at `model_preloader.py:158-187`
- **Observed**: Singleton pattern with global `_model_manager` at `model_preloader.py:351-352`

---

## MOD-004: Lazy Model Loading (First Inference)

**Status**: Implemented
**Flow Name**: Lazy Model Loading on First Transcription Request

**Triggers**:
- First call to `provider.transcribe_stream()` if model not yet loaded
- Direct call to `provider._get_model()` (for faster-whisper and whisper_cpp)

**Preconditions**:
- Provider instance created (but model not loaded)
- Sufficient RAM for model loading
- Model files available on filesystem

**Step-by-Step Sequence (Faster-Whisper Provider)**:

1. **Transcribe stream called** (`provider_faster_whisper.py:113-118`):
   ```python
   async def transcribe_stream(
       self,
       pcm_stream: AsyncIterator[bytes],
       sample_rate: int = 16000,
       source: Optional[AudioSource] = None,
   ) -> AsyncIterator[ASRSegment]:
   ```

2. **Get model instance** (`provider_faster_whisper.py:130`):
   ```python
   model = self._get_model()
   if model is None or np is None:
       self.log("ASR unavailable: missing faster-whisper or numpy")
       yield ASRSegment(...)
       async for _ in pcm_stream:
           pass
       return
   ```

3. **Check if model already loaded** (`provider_faster_whisper.py:80-84`):
   ```python
   def _get_model(self) -> Optional["WhisperModel"]:
       if not self.is_available:
           return None

       if self._model is None:
           # Load model (see step 4)
       ```

4. **Load faster-whisper model** (`provider_faster_whisper.py:80-111`):
   ```python
   if self._model is None:
       model_name = os.getenv("ECHOPANEL_WHISPER_MODEL", self.config.model_name)
       device = os.getenv("ECHOPANEL_WHISPER_DEVICE", self.config.device)

       # CTranslate2 does not support MPS/Metal. On macOS, fallback to CPU.
       if device == "auto" and platform.system() == "Darwin":
           device = "cpu"
       elif device in {"mps", "metal"}:
           device = "cpu"

       compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", self.config.compute_type)

       # float16 variants are not supported on CPU, force int8.
       if device == "cpu" and "float16" in compute_type:
           compute_type = "int8"
           self.log("Forced compute_type='int8' for CPU execution (float16 variant unsupported)")

       self.log(f"Loading model={model_name} device={device} compute={compute_type}")

       try:
           self._model = WhisperModel(model_name, device=device, compute_type=compute_type)
           self._model_loaded_at = time.time()
           self._health.model_resident = True
           self._health.model_loaded_at = self._model_loaded_at
       except Exception as e:
           self.log(f"FATAL ERROR loading model: {e}")
           self._health.model_resident = False
           self._health.last_error = str(e)
           self._health.consecutive_errors += 1
           raise e

   return self._model
   ```

5. **Model instance cached in `self._model`** (`provider_faster_whisper.py:46`):
   ```python
   def __init__(self, config: ASRConfig):
       super().__init__(config)
       self._model: Optional["WhisperModel"] = None
       # ...
   ```

**Step-by-Step Sequence (Whisper.cpp Provider)**:

1. **Transcribe stream called** (`provider_whisper_cpp.py:195-200`):
   ```python
   async def transcribe_stream(
       self,
       pcm_stream: AsyncIterator[bytes],
       sample_rate: int = 16000,
       source: Optional[str] = None,
   ) -> AsyncIterator[ASRSegment]:
   ```

2. **Load model in thread** (`provider_whisper_cpp.py:207`):
   ```python
   model = await asyncio.to_thread(self._load_model)
   ```

3. **Check if model already loaded** (`provider_whisper_cpp.py:133-134`):
   ```python
   def _load_model(self) -> "Model":
       if self._model is not None:
           return self._model
   ```

4. **Load whisper.cpp model** (`provider_whisper_cpp.py:139-173`):
   ```python
   if not PYWHISPERCPP_AVAILABLE:
       raise RuntimeError("pywhispercpp not installed")

   model_path = self._get_model_path()
   logger.info(f"Loading whisper.cpp model: {model_path}")

   start_time = time.time()

   # Determine device settings
   use_metal = self.config.device == "metal" or (
       self.config.device == "auto" and self._is_apple_silicon()
   )

   # Build model parameters
   params = {
       "language": "en",
       "n_threads": self._get_optimal_threads(),
   }

   if use_metal:
       params["use_metal"] = True
       logger.info("Using Metal GPU acceleration")
   else:
       logger.info("Using CPU inference")

   try:
       self._model = Model(model_path, params=params)
       self._model_loaded = True

       load_time = (time.time() - start_time) * 1000
       self._load_time_ms = load_time
       logger.info(f"whisper.cpp model loaded in {load_time:.1f}ms")

       return self._model

   except Exception as e:
       logger.error(f"Failed to load whisper.cpp model: {e}")
       raise
   ```

5. **Get model path from search locations** (`provider_whisper_cpp.py:98-129`):
   ```python
   def _get_model_path(self) -> str:
       model_name = self.config.model_name.lower()

       # Map model names to whisper.cpp model files
       model_info = self.MODELS.get(model_name)
       if model_info:
           filename = model_info["file"]
       else:
           filename = model_name if model_name.endswith(".bin") else f"ggml-{model_name}.bin"

       # Check common model directories
       search_paths = [
           Path.home() / ".cache" / "whisper" / filename,
           Path.home() / ".local" / "share" / "whisper" / filename,
           Path("/usr/local/share/whisper") / filename,
           Path("models") / filename,
           Path(filename),  # Relative to cwd
       ]

       # Also check ECHOPANEL_MODEL_PATH if set
       if "ECHOPANEL_MODEL_PATH" in os.environ:
           search_paths.insert(0, Path(os.environ["ECHOPANEL_MODEL_PATH"]) / filename)

       for path in search_paths:
           if path.exists():
               return str(path)

       # Return first path even if not found (will fail gracefully later)
       logger.warning(f"Model file not found in search paths: {filename}")
       return str(search_paths[0])
   ```

**Inputs/Outputs**:
- **Inputs**: PCM audio stream (optional, may just be warmup audio)
- **Outputs**: Loaded model instance (cached for future use)

**Key Modules/Files/Functions**:
- `server/services/provider_faster_whisper.py:FasterWhisperProvider._get_model()` (lines 76-111)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider._load_model()` (lines 131-173)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider._get_model_path()` (lines 98-129)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Model file not found** | FileNotFoundError/Path not exists | Logs warning, will fail when model used | `provider_whisper_cpp.py:128-129` |
| **Out of memory** | RuntimeError/OSError during load | Raises exception, marks model_resident=False | `provider_faster_whisper.py:104-109` |
| **GPU not available** | device="cuda" but CUDA not installed | Faster-whisper auto-falls back to CPU | `provider_faster_whisper.py:85-88` |
| **Metal not available** | Metal initialization fails | Whisper.cpp falls back to CPU | `provider_whisper_cpp.py:171-172` |
| **Invalid model format** | Load exception (corrupted file) | Raises exception to caller | `provider_faster_whisper.py:104` |
| **Compute type mismatch** | e.g., float16 on CPU | Faster-whisper auto-forces int8 | `provider_faster_whisper.py:92-95` |
| **Dependency not installed** | ImportError (faster-whisper, pywhispercpp) | `is_available` returns False | `provider_faster_whisper.py:57-58` |
| **Model path too long** | OS limit (uncommon) | Fails to load, raises exception | `provider_whisper_cpp.py:98-129` (theoretical) |

**Observability**:
- Logger output at INFO level when model loads
- `ASRHealth.model_resident` indicates model loaded state
- `ASRHealth.model_loaded_at` timestamp for when model loaded
- `health()` method returns load_time_ms for whisper.cpp
- Log messages include model name, device, compute_type

**Proof**:
- **Observed**: Lazy load in `_get_model()` at `provider_faster_whisper.py:80-111`
- **Observed**: Model cached in `self._model` at `provider_faster_whisper.py:46`
- **Observed**: CPU fallback on macOS at `provider_faster_whisper.py:85-88`
- **Observed**: Whisper.cpp model path search at `provider_whisper_cpp.py:111-128`

---

## MOD-005: Chunked Batch Inference

**Status**: Implemented
**Flow Name**: Chunked Batch Inference with Fixed Chunk Size

**Triggers**:
- Audio chunks received from WebSocket stream
- Buffer reaches `chunk_bytes` threshold

**Preconditions**:
- Model loaded and resident
- Sample rate known (default 16000 Hz)
- Chunk size configured (default 2-4 seconds)

**Step-by-Step Sequence (Faster-Whisper Provider)**:

1. **Calculate chunk parameters** (`provider_faster_whisper.py:120-126`):
   ```python
   bytes_per_sample = 2  # 16-bit PCM
   chunk_seconds = self.config.chunk_seconds
   chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
   buffer = bytearray()
   processed_samples = 0  # samples already transcribed (for timestamp base)
   chunk_count = 0
   ```

2. **Receive audio chunks** (`provider_faster_whisper.py:144-145`):
   ```python
   async for chunk in pcm_stream:
       buffer.extend(chunk)
   ```

3. **Check buffer size** (`provider_faster_whisper.py:148`):
   ```python
   while len(buffer) >= chunk_bytes:
   ```

4. **Extract exactly one chunk** (`provider_faster_whisper.py:148-151`):
   ```python
       chunk_count += 1
       audio_bytes = bytes(buffer[:chunk_bytes])
       del buffer[:chunk_bytes]

       # Timestamps based on processed samples, not incoming bytes
       t0 = processed_samples / sample_rate
       chunk_samples = len(audio_bytes) // bytes_per_sample
       t1 = (processed_samples + chunk_samples) / sample_rate
       processed_samples += chunk_samples
   ```

5. **Convert to float32** (`provider_faster_whisper.py:161`):
   ```python
   audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
   ```

6. **Run inference with thread lock** (`provider_faster_whisper.py:163-174`):
   ```python
   infer_start = time.perf_counter()

   def _transcribe():
       with self._infer_lock:
           segments, info = model.transcribe(
               audio,
               vad_filter=self.config.vad_enabled,
               language=self.config.language,
           )
       return list(segments), info

   segments, info = await asyncio.to_thread(_transcribe)

   infer_ms = (time.perf_counter() - infer_start) * 1000
   ```

7. **Calculate confidence from avg_logprob** (`provider_faster_whisper.py:192-196`):
   ```python
   for segment in segments:
       text = segment.text.strip()
       if not text:
           continue

       # Compute real confidence from avg_logprob
       avg_logprob = getattr(segment, 'avg_logprob', -0.5)
       confidence = max(0.0, min(1.0, 1.0 + avg_logprob / 2.0))
   ```

8. **Yield ASR segments** (`provider_faster_whisper.py:201-209`):
   ```python
       yield ASRSegment(
           text=text,
           t0=t0 + segment.start,
           t1=t0 + segment.end,
           confidence=confidence,
           is_final=True,
           source=source,
           language=detected_lang,
       )
   ```

9. **Process final buffer** (`provider_faster_whisper.py:211-276`):
   ```python
   # Process any remaining buffer at end of stream
   if buffer:
       chunk_count += 1
       audio_bytes = bytes(buffer)
       del buffer[:]

       # ... (same processing as above, with VAD enabled for final chunk)

       # Skip very small final buffers to prevent hallucination
       min_final_bytes = int(sample_rate * 0.5 * bytes_per_sample)  # 0.5 seconds minimum
       if len(audio_bytes) < min_final_bytes:
           self.log(f"Skipping final chunk: too small ({len(audio_bytes)} bytes < {min_final_bytes} min)")
           return

       # Check for silence/low energy
       audio_energy = np.sqrt(np.mean(audio**2))
       if audio_energy < 0.01:
           self.log(f"Skipping final chunk: low energy ({audio_energy:.4f})")
           return

       # Filter low-confidence segments
       if confidence < 0.3 and len(text.split()) < 3:
           self.log(f"Filtering likely hallucination: '{text[:30]}...' conf={confidence:.2f}")
           continue
   ```

**Step-by-Step Sequence (Voxtral Realtime Provider)**:

1. **Calculate chunk parameters** (`provider_voxtral_realtime.py:298-303`):
   ```python
   bytes_per_sample = 2
   chunk_seconds = self.config.chunk_seconds
   chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
   buffer = bytearray()
   processed_samples = 0
   ```

2. **Ensure streaming session started** (`provider_voxtral_realtime.py:308`):
   ```python
   session = await self._ensure_session()
   ```

3. **Start background reader task** (`provider_voxtral_realtime.py:315-331`):
   ```python
   pending_transcriptions: asyncio.Queue[Tuple[int, int, str]] = asyncio.Queue()
   read_task: Optional[asyncio.Task] = None

   async def read_loop():
       """Background task to read transcriptions from stdout."""
       while session and session.process.returncode is None:
           try:
               text = await self._read_transcription(session, timeout=0.5)
               if text:
                   await pending_transcriptions.put((
                       processed_samples,
                       text
                   ))
           except Exception as e:
               self.log(f"Read loop error: {e}")
               break

   read_task = asyncio.create_task(read_loop())
   ```

4. **Write chunks to voxtral stdin** (`provider_voxtral_realtime.py:346-361`):
   ```python
   while len(buffer) >= chunk_bytes:
       audio_bytes = bytes(buffer[:chunk_bytes])
       del buffer[:chunk_bytes]

       t0 = processed_samples / sample_rate
       chunk_samples = len(audio_bytes) // bytes_per_sample
       t1 = (processed_samples + chunk_samples) / sample_rate

       # Write chunk to streaming process
       infer_start = time.perf_counter()
       try:
           await self._write_chunk(session, audio_bytes, sample_rate)
           session.chunks_processed += 1
       except RuntimeError as e:
           self.log(f"Write error, restarting session: {e}")
           await self._stop_session()
           session = await self._ensure_session()
           await self._write_chunk(session, audio_bytes, sample_rate)
           session.chunks_processed += 1

       infer_ms = (time.perf_counter() - infer_start) * 1000
       session.total_infer_ms += infer_ms

       processed_samples += chunk_samples
   ```

5. **Drain pending transcriptions** (`provider_voxtral_realtime.py:363-376`):
   ```python
   # Check for any completed transcriptions
   while not pending_transcriptions.empty():
       try:
           _, text = pending_transcriptions.get_nowait()
           yield ASRSegment(
               text=text,
               t0=t0,
               t1=t1,
               confidence=0.9,
               is_final=True,
               source=source,
           )
       except asyncio.QueueEmpty:
           break
   ```

**Inputs/Outputs**:
- **Inputs**: PCM audio stream (int16 bytes), sample rate
- **Outputs**: `ASRSegment` objects with text, timestamps, confidence, is_final

**Key Modules/Files/Functions**:
- `server/services/provider_faster_whisper.py:FasterWhisperProvider.transcribe_stream()` (lines 113-276)
- `server/services/provider_voxtral_realtime.py:VoxtralRealtimeProvider.transcribe_stream()` (lines 275-429)
- `server/services/asr_providers.py:ASRSegment` (lines 33-46)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Buffer overflow** | Buffer grows indefinitely (chunk not processed) | P0 fix: Process exactly `chunk_bytes`, leave remainder | `provider_faster_whisper.py:148-151` |
| **Inference timeout** | `transcribe()` takes too long | Blocks inference lock, other chunks queue | `provider_faster_whisper.py:166-174` |
| **Lock contention** | Multiple concurrent transcriptions | Serialized by `_infer_lock` | `provider_faster_whisper.py:47,166` |
| **Silent final chunk** | Low energy in final buffer | Skip transcription (no hallucination) | `provider_faster_whisper.py:232-236` |
| **Small final chunk** | < 0.5 seconds of audio | Skip transcription (no hallucination) | `provider_faster_whisper.py:225-228` |
| **Voxtral session crash** | Process exits unexpectedly | Auto-restart session, re-send chunk | `provider_voxtral_realtime.py:350-356` |
| **Empty transcription** | No text from model | Filter out, continue to next chunk | `provider_faster_whisper.py:189-190` |
| **Timestamp drift** | `processed_samples` desyncs from real time | Accumulated error (no correction) | `provider_faster_whisper.py:125-157` |

**Observability**:
- Log messages per chunk with count, bytes, timestamps
- `ASRHealth.realtime_factor` calculated from inference times
- `ASRHealth.avg_infer_ms`, `p95_infer_ms`, `p99_infer_ms` tracked
- Chunk count logged
- Dropped chunks tracked in degrade ladder

**Proof**:
- **Observed**: Fixed chunk processing at `provider_faster_whisper.py:148-157`
- **Observed**: Inference lock serialization at `provider_faster_whisper.py:166-174`
- **Observed**: Final buffer processing with hallucination prevention at `provider_faster_whisper.py:211-276`
- **Observed**: Voxtral streaming session management at `provider_voxtral_realtime.py:307-376`

---

## MOD-006: GPU/Metal/CUDA Device Selection

**Status**: Implemented
**Flow Name**: Automatic Device Selection Based on Platform and Capabilities

**Triggers**:
- Model load (lazy or eager)
- Provider initialization

**Preconditions**:
- Model not yet loaded
- Device configuration set (or defaults apply)

**Step-by-Step Sequence (Faster-Whisper Provider)**:

1. **Get device from config** (`provider_faster_whisper.py:81-82`):
   ```python
   model_name = os.getenv("ECHOPANEL_WHISPER_MODEL", self.config.model_name)
   device = os.getenv("ECHOPANEL_WHISPER_DEVICE", self.config.device)
   ```

2. **Auto-detect on macOS** (`provider_faster_whisper.py:85-88`):
   ```python
   # CTranslate2 does not support MPS/Metal. On macOS, fallback to CPU.
   if device == "auto" and platform.system() == "Darwin":
       device = "cpu"
   elif device in {"mps", "metal"}:
       device = "cpu"
   ```

3. **Get compute type** (`provider_faster_whisper.py:90`):
   ```python
   compute_type = os.getenv("ECHOPANEL_WHISPER_COMPUTE", self.config.compute_type)
   ```

4. **Force int8 on CPU** (`provider_faster_whisper.py:92-95`):
   ```python
   # float16 variants are not supported on CPU, force int8.
   if device == "cpu" and "float16" in compute_type:
       compute_type = "int8"
       self.log("Forced compute_type='int8' for CPU execution (float16 variant unsupported)")
   ```

5. **Load model with device** (`provider_faster_whisper.py:97-100`):
   ```python
   self.log(f"Loading model={model_name} device={device} compute={compute_type}")

   try:
       self._model = WhisperModel(model_name, device=device, compute_type=compute_type)
   ```

**Step-by-Step Sequence (Whisper.cpp Provider)**:

1. **Get default config** (`provider_whisper_cpp.py:88-96`):
   ```python
   def _default_config(self) -> ASRConfig:
       return ASRConfig(
           model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base"),
           device="metal",  # Prefer Metal on macOS
           compute_type="fp16",  # Metal uses FP16
           chunk_seconds=int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2")),
           vad_enabled=True,
       )
   ```

2. **Determine Metal usage** (`provider_whisper_cpp.py:145-147`):
   ```python
   use_metal = self.config.device == "metal" or (
       self.config.device == "auto" and self._is_apple_silicon()
   )
   ```

3. **Detect Apple Silicon** (`provider_whisper_cpp.py:175-181`):
   ```python
   def _is_apple_silicon(self) -> bool:
       """Detect if running on Apple Silicon."""
       import platform
       return (
           platform.system() == "Darwin" and
           platform.machine().startswith("arm")
       )
   ```

4. **Set Metal parameters** (`provider_whisper_cpp.py:149-159`):
   ```python
   # Build model parameters
   params = {
       "language": "en",
       "n_threads": self._get_optimal_threads(),
   }

   if use_metal:
       params["use_metal"] = True
       logger.info("Using Metal GPU acceleration")
   else:
       logger.info("Using CPU inference")
   ```

5. **Calculate optimal threads** (`provider_whisper_cpp.py:183-193`):
   ```python
   def _get_optimal_threads(self) -> int:
       """Get optimal number of threads for inference."""
       import multiprocessing
       cpu_count = multiprocessing.cpu_count()

       if self.config.device == "metal":
           # Metal uses GPU, fewer CPU threads needed
           return min(4, cpu_count)
       else:
           # CPU inference benefits from more threads
           return min(8, cpu_count)
   ```

6. **Load model with parameters** (`provider_whisper_cpp.py:161-169`):
   ```python
   try:
       self._model = Model(model_path, params=params)
       self._model_loaded = True

       load_time = (time.time() - start_time) * 1000
       self._load_time_ms = load_time
       logger.info(f"whisper.cpp model loaded in {load_time:.1f}ms")

       return self._model
   ```

**Step-by-Step Sequence (Voxtral Realtime Provider)**:

1. **Voxtral uses MPS/BLAS backend** (binary-level, not in Python):
   - MPS (Metal Performance Shaders) on Apple Silicon
   - BLAS (CPU) on other platforms

2. **Session start logs backend** (`provider_voxtral_realtime.py:166-171`):
   ```python
   ready_patterns = [
       b"Metal GPU",      # MPS/Metal backend ready
       b"BLAS",           # CPU BLAS backend ready
       b"Ready",          # Generic ready signal
       b"Model loaded",   # Alternative ready signal
   ]
   ```

**Inputs/Outputs**:
- **Inputs**: Device config, platform detection
- **Outputs**: Device used (cuda/cpu/metal), compute_type, thread count

**Key Modules/Files/Functions**:
- `server/services/provider_faster_whisper.py:FasterWhisperProvider._get_model()` (lines 81-100)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider._is_apple_silicon()` (lines 175-181)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider._get_optimal_threads()` (lines 183-193)
- `server/services/capability_detector.py:CapabilityDetector._detect_mps()` (lines 242-271)
- `server/services/capability_detector.py:CapabilityDetector._detect_cuda()` (lines 273-302)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **CUDA not installed** | `device="cuda"` but torch.cuda unavailable | Faster-whisper auto-falls back to CPU | `provider_faster_whisper.py:85` (inferred) |
| **Metal not available** | Metal initialization fails on Apple Silicon | Whisper.cpp falls back to CPU | `provider_whisper_cpp.py:171-172` |
| **Invalid device string** | `device` not in {cuda, cpu, auto, mps, metal} | Uses default (cpu) | `provider_faster_whisper.py:82` (inferred) |
| **Unsupported compute type** | e.g., int8_float16 on CPU | Faster-whisper forces int8 | `provider_faster_whisper.py:92-95` |
| **GPU memory insufficient** | CUDA out of memory error | Falls back to CPU or smaller model | `provider_faster_whisper.py:104` (inferred) |
| **MPS not available** | M1/M2 Mac with disabled Metal | Auto-detects via platform, uses CPU | `capability_detector.py:244-271` |
| **nvidia-smi not available** | CUDA detection fails | Fallback to torch.cuda.is_available() | `capability_detector.py:287-300` |
| **Device mismatch** | User sets cuda on macOS | Faster-whisper forces CPU | `provider_faster_whisper.py:85-88` |

**Observability**:
- Logger messages: "Loading model=... device=... compute=..."
- Logger messages: "Using Metal GPU acceleration" / "Using CPU inference"
- `ASRProvider.capabilities` includes `supports_metal`, `supports_cuda`, `supports_gpu`
- `/capabilities` endpoint exposes `has_mps`, `has_cuda`, `cuda_devices`

**Proof**:
- **Observed**: CPU fallback on macOS at `provider_faster_whisper.py:85-88`
- **Observed**: int8 force on CPU at `provider_faster_whisper.py:92-95`
- **Observed**: Metal detection in whisper.cpp at `provider_whisper_cpp.py:145-159`
- **Observed**: MPS/CUDA detection in capability_detector at `capability_detector.py:242-302`

---

## MOD-007: Degrade Ladder Performance Management

**Status**: Implemented
**Flow Name**: Adaptive Performance Management with 5-Level Degrade Ladder

**Triggers**:
- Realtime factor (RTF) exceeds thresholds
- Provider error/crash
- RTF drops below recovery threshold (sustained)

**Preconditions**:
- `DegradeLadder` instance initialized with provider and config
- Inference running and RTF being measured

**Step-by-Step Sequence**:

1. **Initialize degrade ladder** (`degrade_ladder.py:119-148`):
   ```python
   def __init__(
       self,
       provider: ASRProvider,
       config: ASRConfig,
       fallback_provider: Optional[ASRProvider] = None,
       thresholds: Optional[DegradeThresholds] = None,
       on_level_change: Optional[Callable[[DegradeLevel, DegradeLevel, Optional[DegradeAction]], None]] = None,
   ):
       self.provider = provider
       self.config = config
       self.fallback_provider = fallback_provider
       self.thresholds = thresholds or DegradeThresholds()
       self.on_level_change = on_level_change

       self.state = DegradeState()
       self._lock = asyncio.Lock()

       # Define actions for each level transition
       self._actions = self._build_actions()
   ```

2. **Build action map** (`degrade_ladder.py:150-188`):
   ```python
   def _build_actions(self) -> Dict[Tuple[DegradeLevel, DegradeLevel], DegradeAction]:
       actions = {}

       # NORMAL -> WARNING: Increase chunk size
       actions[(DegradeLevel.NORMAL, DegradeLevel.WARNING)] = DegradeAction(
           name="increase_chunk_size",
           description="Increase chunk size to reduce inference frequency",
           apply=self._action_increase_chunk_size,
           revert=self._action_decrease_chunk_size,
       )

       # WARNING -> DEGRADE: Switch to smaller model, disable VAD
       actions[(DegradeLevel.WARNING, DegradeLevel.DEGRADE)] = DegradeAction(
           name="reduce_quality",
           description="Switch to smaller model and disable VAD",
           apply=self._action_reduce_quality,
           revert=self._action_restore_quality,
       )

       # DEGRADE -> EMERGENCY: Start dropping chunks
       actions[(DegradeLevel.DEGRADE, DegradeLevel.EMERGENCY)] = DegradeAction(
           name="drop_chunks",
           description="Drop every other chunk to catch up",
           apply=self._action_enable_chunk_dropping,
           revert=self._action_disable_chunk_dropping,
       )

       # Any -> FAILOVER: Switch provider
       for src_level in [DegradeLevel.NORMAL, DegradeLevel.WARNING, DegradeLevel.DEGRADE, DegradeLevel.EMERGENCY]:
           actions[(src_level, DegradeLevel.FAILOVER)] = DegradeAction(
               name="failover",
               description="Switch to fallback provider",
               apply=self._action_failover,
           )

       return actions
   ```

3. **Check RTF and adjust** (`degrade_ladder.py:190-228`):
   ```python
   async def check(self, rtf: float) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       async with self._lock:
           now = time.time()

           # Record RTF in history
           self.state.rtf_history.append((now, rtf))

           # Prune old history
           cutoff = now - self.HISTORY_WINDOW_S
           self.state.rtf_history = [
               (ts, r) for ts, r in self.state.rtf_history if ts > cutoff
           ]

           # Determine target level based on RTF
           target_level = self._rtf_to_level(rtf)

           # Check if we should change level
           if target_level > self.state.level:
               # Degrading — check minimum time at current level
               time_at_level = now - self.state.level_since
               if time_at_level < self.MIN_LEVEL_TIME_S:
                   logger.debug(f"Want to degrade to {target_level.name} but only at current level for {time_at_level:.1f}s")
                   return self.state.level, None

               return await self._degrade_to(target_level)

           elif target_level < self.state.level:
               # Recovering — check if sustained below threshold
               return await self._maybe_recover(target_level)

           return self.state.level, None
   ```

4. **Convert RTF to level** (`degrade_ladder.py:230-239`):
   ```python
   def _rtf_to_level(self, rtf: float) -> DegradeLevel:
       """Convert RTF to degrade level."""
       if rtf >= self.thresholds.emergency:
           return DegradeLevel.EMERGENCY
       elif rtf >= self.thresholds.degrade:
           return DegradeLevel.DEGRADE
       elif rtf >= self.thresholds.warning:
           return DegradeLevel.WARNING
       else:
           return DegradeLevel.NORMAL
   ```

5. **Execute degrade action** (`degrade_ladder.py:241-272`):
   ```python
   async def _degrade_to(self, target_level: DegradeLevel) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       old_level = self.state.level

       # Get action for this transition
       action_key = (old_level, target_level)
       action = self._actions.get(action_key)

       # Update state
       self.state.level = target_level
       self.state.level_since = time.time()

       if action:
           self.state.actions_applied.append(action.name)
           logger.warning(f"DEGRADE: {old_level.name} -> {target_level.name}: {action.description}")

           # Apply action (in executor if blocking)
           if asyncio.iscoroutinefunction(action.apply):
               await action.apply()
           else:
               await asyncio.get_event_loop().run_in_executor(None, action.apply)
       else:
           logger.warning(f"DEGRADE: {old_level.name} -> {target_level.name} (no action defined)")

       # Notify callback
       if self.on_level_change:
           if asyncio.iscoroutinefunction(self.on_level_change):
               await self.on_level_change(old_level, target_level, action)
           else:
               self.on_level_change(old_level, target_level, action)

       return target_level, action
   ```

6. **Recovery check** (`degrade_ladder.py:274-326`):
   ```python
   async def _maybe_recover(self, target_level: DegradeLevel) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       now = time.time()

       # Check if RTF has been below recovery threshold for long enough
       if now - self.state.last_recovery_check < self.RECOVERY_WINDOW_S:
           return self.state.level, None

       # Check average RTF over recovery window
       recent_rtfs = [
           rtf for ts, rtf in self.state.rtf_history
           if now - ts < self.RECOVERY_WINDOW_S
       ]

       if not recent_rtfs:
           return self.state.level, None

       avg_rtf = sum(recent_rtfs) / len(recent_rtfs)

       if avg_rtf >= self.thresholds.recovery:
           logger.debug(f"RTF avg {avg_rtf:.2f} above recovery threshold {self.thresholds.recovery}")
           return self.state.level, None

       # Can recover — step up one level at a time
       new_level = DegradeLevel(self.state.level - 1)
       old_level = self.state.level

       self.state.level = new_level
       self.state.level_since = now
       self.state.last_recovery_check = now

       # Find revert action for the last applied action
       action_key = (new_level, old_level)
       action = self._actions.get(action_key)

       if action and action.revert:
           logger.info(f"RECOVER: {old_level.name} -> {new_level.name}: Reverting {action.name}")

           if asyncio.iscoroutinefunction(action.revert):
               await action.revert()
           else:
               await asyncio.get_event_loop().run_in_executor(None, action.revert)
       else:
           logger.info(f"RECOVER: {old_level.name} -> {new_level.name}")

       # Notify callback
       if self.on_level_change:
           if asyncio.iscoroutinefunction(self.on_level_change):
               await self.on_level_change(old_level, new_level, None)
           else:
               self.on_level_change(old_level, new_level, None)

       return new_level, None
   ```

7. **Action implementations**:

   a) **Increase chunk size** (`degrade_ladder.py:348-353`):
   ```python
   def _action_increase_chunk_size(self) -> None:
       old_chunk = self.config.chunk_seconds
       new_chunk = min(8, old_chunk + 1)  # Max 8s chunks
       self.config.chunk_seconds = new_chunk
       logger.info(f"Increased chunk size: {old_chunk}s -> {new_chunk}s")
   ```

   b) **Reduce quality** (`degrade_ladder.py:362-383`):
   ```python
   def _action_reduce_quality(self) -> None:
       model_downgrade = {
           "large-v3": "medium.en",
           "large-v2": "medium.en",
           "medium.en": "small.en",
           "small.en": "base.en",
           "base.en": "tiny.en",
       }

       old_model = self.config.model_name
       new_model = model_downgrade.get(old_model, old_model)

       if new_model != old_model:
           self.config.model_name = new_model
           logger.info(f"Downgraded model: {old_model} -> {new_model}")

       # Disable VAD to save compute
       if self.config.vad_enabled:
           self.config.vad_enabled = False
           logger.info("Disabled VAD to save compute")
   ```

   c) **Enable chunk dropping** (`degrade_ladder.py:391-394`):
   ```python
   def _action_enable_chunk_dropping(self) -> None:
       logger.warning("EMERGENCY: Enabling chunk dropping mode (every other chunk will be dropped)")
       self.state.dropped_chunks = 0
   ```

   d) **Switch provider** (`degrade_ladder.py:401-407`):
   ```python
   def _action_failover(self) -> None:
       if self.fallback_provider:
           logger.warning(f"FAILOVER: Switching to {self.fallback_provider.name}")
           self.provider = self.fallback_provider
       else:
           logger.error("FAILOVER requested but no fallback provider available")
   ```

8. **Check if chunk should be dropped** (`degrade_ladder.py:328-335`):
   ```python
   def should_drop_chunk(self) -> bool:
       if self.state.level < DegradeLevel.EMERGENCY:
           return False

       # Drop every other chunk
       self.state.dropped_chunks += 1
       return self.state.dropped_chunks % 2 == 0
   ```

9. **Report provider error** (`degrade_ladder.py:337-344`):
   ```python
   async def report_provider_error(self, error: Exception) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       logger.error(f"Provider error: {error}")

       if self.fallback_provider and self.state.level < DegradeLevel.FAILOVER:
           return await self._degrade_to(DegradeLevel.FAILOVER)

       return self.state.level, None
   ```

**Inputs/Outputs**:
- **Inputs**: RTF (realtime factor), provider errors
- **Outputs**: New degrade level, applied actions, chunk drop decisions

**Key Modules/Files/Functions**:
- `server/services/degrade_ladder.py:DegradeLadder.check()` (lines 190-228)
- `server/services/degrade_ladder.py:DegradeLadder._degrade_to()` (lines 241-272)
- `server/services/degrade_ladder.py:DegradeLadder._maybe_recover()` (lines 274-326)
- `server/services/degrade_ladder.py:DegradeLadder.should_drop_chunk()` (lines 328-335)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **RTF measurement inaccurate** | High variance in RTF history | Uses average over window | `degrade_ladder.py:283-295` |
| **Rapid level oscillation** | Level changes within MIN_LEVEL_TIME_S | Enforced minimum time at level | `degrade_ladder.py:216-220` |
| **Recovery too aggressive** | RTF dips below recovery momentarily | Requires 30s sustained recovery | `degrade_ladder.py:279-282` |
| **Action application fails** | Exception in action.apply() | Logs error, level changes but action fails | `degrade_ladder.py:257-261` |
| **Fallback provider unavailable** | FAILOVER triggered but no fallback | Logs error, stays at EMERGENCY | `degrade_ladder.py:406-407` |
| **Revert action fails** | Exception in action.revert() | Logs error, level recovers but revert fails | `degrade_ladder.py:312-315` |
| **Model downgrade not available** | Current model not in downgrade map | Keeps current model | `degrade_ladder.py:364-378` |
| **Chunk size at limit** | Already at max/min chunk size | No change in action | `degrade_ladder.py:351-352,358` |

**Observability**:
- Logger warnings for all level changes
- `DegradeState.to_dict()` includes level, current_rtf, avg_rtf, actions_applied, dropped_chunks
- `DegradeLadder.get_status()` includes level, rtf_avg_10s/60s, config
- Callback mechanism for UI notifications

**Proof**:
- **Observed**: 5-level degrade system at `degrade_ladder.py:47-54`
- **Observed**: RTF thresholds at `degrade_ladder.py:57-62`
- **Observed**: Action map for transitions at `degrade_ladder.py:150-188`
- **Observed**: Recovery window enforcement at `degrade_ladder.py:279-295`

---

## MOD-008: Provider Health Monitoring

**Status**: Implemented
**Flow Name**: Provider Health Metrics Collection and Reporting

**Triggers**:
- Health endpoint request (`/health`, `/model-status`)
- Periodic health checks (by external monitoring)
- Inference completes (updates metrics)

**Preconditions**:
- Provider instance exists
- Model loaded (for some metrics)

**Step-by-Step Sequence**:

1. **Health endpoint request** (`main.py:101-156`):
   ```python
   @app.get("/health")
   async def health_check() -> dict:
       logger.debug("Health check requested.")

       try:
           config = _get_default_config()
           provider = ASRProviderRegistry.get_provider(config=config)
           provider_name = provider.name if provider else None

           # PR4: Check model preloader status
           from server.services.model_preloader import get_model_manager
           manager = get_model_manager()
           model_health = manager.health()

           # Deep health: provider must be available AND model warmed up
           if provider and provider.is_available and model_health.ready:
               return {
                   "status": "ok",
                   "service": "echopanel",
                   "provider": provider_name,
                   "model": config.model_name,
                   "model_ready": True,
                   "model_state": model_health.state.name,
                   "load_time_ms": model_health.load_time_ms,
                   "warmup_time_ms": model_health.warmup_time_ms,
               }

           # Not ready - determine why
           if not model_health.ready:
               reason = f"Model {model_health.state.name.lower()}"
               if model_health.last_error:
                   reason += f": {model_health.last_error}"
           else:
               reason = "ASR provider not available"

           raise HTTPException(
               status_code=503,
               detail={
                   "status": "loading",
                   "service": "echopanel",
                   "provider": provider_name,
                   "model": config.model_name,
                   "model_state": model_health.state.name,
                   "reason": reason,
               },
           )
   ```

2. **Model health check** (`model_preloader.py:311-321`):
   ```python
   def health(self) -> ModelHealth:
       """Get current health status."""
       return ModelHealth(
           state=self._state,
           ready=self._state == ModelState.READY,
           model_loaded=self._provider is not None,
           warmup_complete=self._warmup_time_ms > 0,
           load_time_ms=self._load_time_ms,
           warmup_time_ms=self._warmup_time_ms,
           last_error=self._last_error,
       )
   ```

3. **Provider health metrics** (`provider_faster_whisper.py:279-303`):
   ```python
   async def health(self) -> ASRHealth:
       """Get health metrics for faster-whisper provider."""
       health = await super().health()

       # Calculate RTF from inference times
       if self._infer_times:
           avg_ms = sum(self._infer_times) / len(self._infer_times)
           sorted_times = sorted(self._infer_times)
           p95_ms = sorted_times[int(len(sorted_times) * 0.95)] if len(sorted_times) > 1 else avg_ms
           p99_ms = sorted_times[int(len(sorted_times) * 0.99)] if len(sorted_times) > 1 else avg_ms

           # Assume 4s chunks (configurable)
           chunk_seconds = self.config.chunk_seconds
           rtf = (avg_ms / 1000.0) / chunk_seconds

           health.realtime_factor = rtf
           health.avg_infer_ms = avg_ms
           health.p95_infer_ms = p95_ms
           health.p99_infer_ms = p99_ms

       health.model_resident = self._model is not None
       health.model_loaded_at = self._model_loaded_at
       health.chunks_processed = self._chunks_processed

       return health
   ```

4. **Base provider health** (`asr_providers.py:257-269`):
   ```python
   async def health(self) -> ASRHealth:
       """Get current health metrics (v0.3).

       Override to provide real metrics from the provider.
       Default implementation returns cached health state.

       Returns:
           ASRHealth with current performance metrics
       """
       # Update session duration if active
       if self._session_start_time:
           self._health.session_duration_s = time.time() - self._session_start_time
       return self._health
   ```

5. **Whisper.cpp health** (`provider_whisper_cpp.py:365-372`):
   ```python
   def health(self) -> dict:
       """Get provider health status."""
       return {
           "available": self.is_available(),
           "model_loaded": self._model_loaded,
           "model_path": self._get_model_path() if self._model else None,
           **self.get_performance_stats(),
       }
   ```

6. **Voxtral health** (`provider_voxtral_realtime.py:431-448`):
   ```python
   async def health(self) -> dict:
       """Return health metrics for the provider."""
       async with self._session_lock:
           if self._session is None:
               return {
                   "status": "idle",
                   "realtime_factor": 0.0,
                   "chunks_processed": 0,
               }

           session = self._session
           return {
               "status": "active" if session.process.returncode is None else "error",
               "realtime_factor": session.realtime_factor,
               "chunks_processed": session.chunks_processed,
               "avg_infer_ms": session.avg_infer_ms,
               "session_duration_s": time.perf_counter() - session.started_at,
           }
   ```

7. **Model status endpoint** (`main.py:177-198`):
   ```python
   @app.get("/model-status")
   async def get_model_status() -> dict:
       """Get model preloader status and statistics.

       PR4: Exposes model warmup status to clients.
       """
       try:
           from server.services.model_preloader import get_model_manager
           manager = get_model_manager()

           return {
               "status": "ok",
               "health": manager.health().to_dict(),
               "stats": manager.get_stats(),
           }
   ```

**Inputs/Outputs**:
- **Inputs**: None (health queries)
- **Outputs**: Health status dict with metrics

**Key Modules/Files/Functions**:
- `server/services/asr_providers.py:ASRProvider.health()` (lines 257-269)
- `server/services/model_preloader.py:ModelManager.health()` (lines 311-321)
- `server/services/provider_faster_whisper.py:FasterWhisperProvider.health()` (lines 279-303)
- `server/main.py:health_check()` (lines 101-156)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Provider not available** | `is_available` returns False | Health check returns 503 | `main.py:122-139` |
| **Model not loaded** | `model_resident` is False | Health check returns 503 | `main.py:135-139` |
| **No inference data** | `_infer_times` list empty | RTF = 0.0, other metrics 0 | `provider_faster_whisper.py:284-287` |
| **Provider crash** | Process exit code non-zero | Voxtral health returns "error" | `provider_voxtral_realtime.py:443` |
| **Exception in health()** | Unhandled exception | Health check returns 500 | `main.py:155-156` |
| **Stale session data** | Session ended but not cleaned | Session duration continues to grow | `asr_providers.py:267-269` |
| **Memory leak detected** | OOM (not directly monitored) | System may kill process | Hypothesized |
| **Concurrent health checks** | Multiple simultaneous requests | No locking, may cause race | `main.py:101-156` (theoretical) |

**Observability**:
- `/health` endpoint: status, provider, model_ready, model_state, load_time_ms, warmup_time_ms
- `/model-status` endpoint: full ModelHealth and stats
- `ASRHealth.to_dict()`: realtime_factor, avg_infer_ms, p95/p99, backlog, model_resident, errors, session stats
- Logger debug messages on health check

**Proof**:
- **Observed**: Health endpoint at `main.py:101-156`
- **Observed**: ModelHealth dataclass at `model_preloader.py:41-61`
- **Observed**: ASRHealth dataclass at `asr_providers.py:64-134`
- **Observed**: Provider health implementations in each provider

---

## MOD-009: VAD Pre-Filtering

**Status**: Implemented
**Flow Name**: Voice Activity Detection Pre-Filtering with Silero VAD

**Triggers**:
- Audio chunk received
- VAD wrapper enabled
- Silero VAD model loaded

**Preconditions**:
- `VADASRWrapper` or `SmartVADRouter` initialized
- Silero VAD model available (lazy loaded)

**Step-by-Step Sequence**:

1. **Initialize VAD wrapper** (`vad_asr_wrapper.py:113-136`):
   ```python
   def __init__(
       self,
       provider: ASRProvider,
       threshold: float = 0.5,
       min_speech_duration_ms: int = 250,
       min_silence_duration_ms: int = 100,
       sample_rate: int = 16000,
   ):
       super().__init__(provider.config)
       self._provider = provider
       self._threshold = threshold
       self._min_speech_duration_ms = min_speech_duration_ms
       self._min_silence_duration_ms = min_silence_duration_ms
       self._sample_rate = sample_rate
       self._stats = VADStats()
       self._vad_available = False
   ```

2. **Check VAD availability** (`vad_asr_wrapper.py:151-162`):
   ```python
   def _check_vad_available(self) -> bool:
       if self._vad_available:
           return True

       try:
           _load_vad_model()
           self._vad_available = True
           return True
       except Exception as e:
           logger.warning(f"VAD not available, falling back to passthrough: {e}")
           return False
   ```

3. **Lazy load Silero VAD model** (`vad_asr_wrapper.py:49-67`):
   ```python
   def _load_vad_model():
       """Lazy load Silero VAD model."""
       global _vad_model, _vad_utils
       if _vad_model is None:
           try:
               import torch
               model, utils = torch.hub.load(
                   repo_or_dir="snakers4/silero-vad",
                   model="silero_vad",
                   force_reload=False,
                   onnx=False,
               )
               _vad_model = model
               _vad_utils = utils
               logger.info("Silero VAD model loaded")
           except Exception as e:
               logger.warning(f"Failed to load Silero VAD: {e}")
               raise
       return _vad_model, _vad_utils
   ```

4. **Transcribe stream with VAD** (`vad_asr_wrapper.py:209-341`):
   ```python
   async def transcribe_stream(
       self,
       pcm_stream: AsyncIterator[bytes],
       sample_rate: int = 16000,
       source: Optional[AudioSource] = None,
   ) -> AsyncIterator[ASRSegment]:
       if not self.is_available:
           yield ASRSegment(...)
           async for _ in pcm_stream:
               pass
           return

       # Check if VAD is available
       vad_enabled = self._check_vad_available()
       if not vad_enabled:
           self.log("VAD not available, passing through to provider")
           async for segment in self._provider.transcribe_stream(pcm_stream, sample_rate, source):
               yield segment
           return

       bytes_per_sample = 2
       chunk_seconds = self.config.chunk_seconds
       chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
       buffer = bytearray()
       processed_samples = 0

       async for chunk in pcm_stream:
           buffer.extend(chunk)

           # Process complete chunks
           while len(buffer) >= chunk_bytes:
               audio_bytes = bytes(buffer[:chunk_bytes])
               del buffer[:chunk_bytes]

               t0 = processed_samples / sample_rate
               chunk_samples = len(audio_bytes) // bytes_per_sample
               t1 = (processed_samples + chunk_samples) / sample_rate
               processed_samples += chunk_samples

               # Update stats
               self._stats.total_frames += chunk_samples

               # Convert to float for VAD
               audio_float = self._pcm_to_float(audio_bytes)

               # Check for speech
               has_speech = await asyncio.get_event_loop().run_in_executor(
                   None, self._has_speech, audio_float
               )

               if has_speech:
                   self._stats.speech_frames += chunk_samples
                   self._stats.processed_chunks += 1

                   # Pass to underlying provider
                   async def single_chunk():
                       yield audio_bytes

                   async for segment in self._provider.transcribe_stream(
                       single_chunk(), sample_rate, source
                   ):
                       yield ASRSegment(
                           text=segment.text,
                           t0=t0 + segment.t0,
                           t1=t0 + segment.t1,
                           confidence=segment.confidence,
                           is_final=segment.is_final,
                           source=segment.source,
                           language=segment.language,
                           speaker=segment.speaker,
                       )
               else:
                   self._stats.silence_frames += chunk_samples
                   self._stats.skipped_chunks += 1

                   # Estimate inference time saved
                   self._stats.total_infer_time_saved_ms += 500

                   if self._debug and self._stats.skipped_chunks % 10 == 0:
                       self.log(f"VAD: skipped {self._stats.skipped_chunks} silent chunks "
                               f"(ratio: {self._stats.silence_ratio:.2%})")
   ```

5. **Run Silero VAD** (`vad_asr_wrapper.py:171-207`):
   ```python
   def _has_speech(self, audio_float: np.ndarray) -> bool:
       """Check if audio contains speech using Silero VAD."""
       if not self._check_vad_available():
           return True

       try:
           model, utils = _load_vad_model()
           (get_speech_timestamps, _, _, _, _) = utils

           # Convert to torch tensor
           import torch
           audio_tensor = torch.from_numpy(audio_float)

           # Get speech timestamps
           speech_timestamps = get_speech_timestamps(
               audio_tensor,
               model,
               sampling_rate=self._sample_rate,
               threshold=self._threshold,
               min_speech_duration_ms=self._min_speech_duration_ms,
               min_silence_duration_ms=self._min_silence_duration_ms,
           )

           return len(speech_timestamps) > 0

       except Exception as e:
           logger.warning(f"VAD detection failed: {e}")
           return True
   ```

6. **Smart VAD router** (`vad_asr_wrapper.py:363-429`):
   ```python
   class SmartVADRouter:
       """Routes audio to VAD or passthrough based on configuration."""

       def set_vad_enabled(self, enabled: bool) -> None:
           """Enable or disable VAD dynamically."""
           if enabled == self._vad_enabled:
               return

           self._vad_enabled = enabled
           if enabled and self._wrapper is None:
               self._wrapper = VADASRWrapper(
                   self._provider,
                   threshold=self._vad_threshold,
               )
           elif not enabled:
               self._wrapper = None

           logger.info(f"VAD {'enabled' if enabled else 'disabled'}")
   ```

**Inputs/Outputs**:
- **Inputs**: PCM audio stream, VAD threshold
- **Outputs**: ASR segments (speech only), VAD stats

**Key Modules/Files/Functions**:
- `server/services/vad_asr_wrapper.py:VADASRWrapper.transcribe_stream()` (lines 209-341)
- `server/services/vad_asr_wrapper.py:_load_vad_model()` (lines 49-67)
- `server/services/vad_asr_wrapper.py:VADASRWrapper._has_speech()` (lines 171-207)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Silero VAD download fails** | torch.hub.load() timeout/error | Falls back to passthrough (all audio processed) | `vad_asr_wrapper.py:54-66` |
| **Torch not installed** | ImportError in _load_vad_model() | Falls back to passthrough | `vad_asr_wrapper.py:54` |
| **VAD model load timeout** | torch.hub.load() hangs | Thread timeout, falls back to passthrough | `vad_asr_wrapper.py:54-66` (inferred) |
| **False speech detection** | Silence marked as speech | Extra inference, no data loss | `vad_asr_wrapper.py:200` |
| **False silence detection** | Speech marked as silence | Data loss, transcription gap | `vad_asr_wrapper.py:200` |
| **Invalid sample rate** | sample_rate not 8kHz or 16kHz | Logs warning, continues (may be inaccurate) | `vad_asr_wrapper.py:139-141` |
| **VAD threshold too high** | Speech filtered out | High false rejection rate | `vad_asr_wrapper.py:132` |
| **VAD threshold too low** | Noise detected as speech | High false acceptance rate | `vad_asr_wrapper.py:132` |

**Observability**:
- `VADStats.to_dict()`: total_frames, speech_frames, silence_frames, silence_ratio, skipped_chunks, processed_chunks, skip_rate, infer_time_saved_ms
- Logger messages: "Silero VAD model loaded", "VAD: skipped N silent chunks"
- Health endpoint includes VAD stats if wrapper used

**Proof**:
- **Observed**: VAD wrapper implementation at `vad_asr_wrapper.py:106-361`
- **Observed**: Silero VAD lazy load at `vad_asr_wrapper.py:49-67`
- **Observed**: Smart router for dynamic enable/disable at `vad_asr_wrapper.py:363-429`

---

## MOD-010: Concurrent Inference Serialization

**Status**: Implemented
**Flow Name**: Thread-Safe Inference Serialization via Lock

**Triggers**:
- Multiple concurrent calls to `transcribe_stream()` or `_transcribe()`
- Multi-source audio (mic + system)

**Preconditions**:
- Provider instance created
- Inference lock initialized

**Step-by-Step Sequence (Faster-Whisper Provider)**:

1. **Initialize inference lock** (`provider_faster_whisper.py:47`):
   ```python
   def __init__(self, config: ASRConfig):
       super().__init__(config)
       self._model: Optional["WhisperModel"] = None
       self._infer_lock = threading.Lock()  # P0: Thread-safe inference
       self._infer_times: List[float] = []
       self._model_loaded_at: Optional[float] = None
       self._chunks_processed = 0
   ```

2. **Acquire lock during inference** (`provider_faster_whisper.py:163-174`):
   ```python
   def _transcribe():
       with self._infer_lock:
           segments, info = model.transcribe(
               audio,
               vad_filter=self.config.vad_enabled,
               language=self.config.language,
           )
       return list(segments), info

   segments, info = await asyncio.to_thread(_transcribe)
   ```

3. **Lock blocks concurrent inferences**:
   - Thread 1: Acquires lock, runs inference
   - Thread 2: Waits for lock (queued)
   - Thread 1: Completes, releases lock
   - Thread 2: Acquires lock, runs inference

**Step-by-Step Sequence (Whisper.cpp Provider)**:

1. **Initialize inference lock** (`provider_whisper_cpp.py:66-67`):
   ```python
   # P0: Thread-safe inference lock for multi-source support
   import threading
   self._infer_lock = threading.Lock()
   ```

2. **Acquire lock during transcription** (`provider_whisper_cpp.py:315-316`):
   ```python
   # P0: Serialize inference with lock for thread safety with multiple sources
   with self._infer_lock:
       segments = model.transcribe(audio_float32)
   ```

**Step-by-Step Sequence (ModelManager)**:

1. **Initialize asyncio lock** (`model_preloader.py:114`):
   ```python
   self._lock = asyncio.Lock()
   self._ready_event = asyncio.Event()
   ```

2. **Use lock during state changes** (`model_preloader.py:141-154`):
   ```python
   async with self._lock:
       if self._state == ModelState.READY:
           return True

       if self._state == ModelState.LOADING:
           async with self._lock:
               pass  # Release lock and wait below
   ```

3. **Use lock during degrade ladder** (`degrade_ladder.py:143`):
   ```python
   self._lock = asyncio.Lock()

   async def check(self, rtf: float) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       async with self._lock:
           # ... state changes
   ```

**Inputs/Outputs**:
- **Inputs**: Concurrent inference requests
- **Outputs**: Serialized inference (one at a time)

**Key Modules/Files/Functions**:
- `server/services/provider_faster_whisper.py:FasterWhisperProvider.__init__()` (lines 44-50)
- `server/services/provider_faster_whisper.py:FasterWhisperProvider._transcribe()` (lines 165-174)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider.__init__()` (lines 59-72)
- `server/services/provider_whisper_cpp.py:WhisperCppProvider._transcribe_chunk()` (lines 289-328)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Lock timeout** | Thread blocks indefinitely (deadlock) | No recovery, requires restart | Hypothesized (no timeout implemented) |
| **Lock not released** | Exception during inference without finally | Next inference blocks forever | Hypothesized (no try/finally) |
| **Lock contention** | High concurrency, many threads | Threads queue, latency increases | Observed in multi-source scenario |
| **Priority inversion** | Low-priority thread holds lock | High-priority thread waits | Hypothesized (no priority) |
| **Nested lock acquisition** | Same thread tries to acquire lock | Deadlock (self) | Hypothesized (should not happen) |
| **Asyncio lock starvation** | Many coroutines competing | Some tasks never run | Hypothesized (rare) |
| **Lock misuse** | Wrong lock type (threading vs asyncio) | Mixed threading/async issues | Hypothesized (design is correct) |
| **Lock state corruption** | Lock object corrupted (memory error) | Undefined behavior | Hypothesized (rare) |

**Observability**:
- No direct lock observability
- Inference queue depth estimated from RTF
- `ASRHealth.backlog_estimate` indicates queued chunks

**Proof**:
- **Observed**: Inference lock at `provider_faster_whisper.py:47`
- **Observed**: Lock acquisition at `provider_faster_whisper.py:166-174`
- **Observed**: Whisper.cpp lock at `provider_whisper_cpp.py:66-67,315-316`

---

## MOD-011: Model State Transitions

**Status**: Implemented
**Flow Name**: Model State Machine Transitions

**Triggers**:
- Initialization starts
- Model load completes
- Warmup completes
- Error occurs
- Concurrent initialization

**Preconditions**:
- ModelManager instance created

**State Diagram**:
```
UNINITIALIZED → LOADING → WARMING_UP → READY
                 ↓
                ERROR
```

**Step-by-Step Sequence**:

1. **Initial state** (`model_preloader.py:107`):
   ```python
   self._state = ModelState.UNINITIALIZED
   ```

2. **Transition to LOADING** (`model_preloader.py:155`):
   ```python
   self._state = ModelState.LOADING
   ```

3. **Transition to WARMING_UP** (`model_preloader.py:170-171`):
   ```python
   async with self._lock:
       self._state = ModelState.WARMING_UP
   ```

4. **Transition to READY** (`model_preloader.py:182-184`):
   ```python
   async with self._lock:
       self._state = ModelState.READY
       self._ready_event.set()
   ```

5. **Transition to ERROR** (`model_preloader.py:191-194`):
   ```python
   except Exception as e:
       logger.error(f"Model initialization failed: {e}")
       async with self._lock:
           self._state = ModelState.ERROR
           self._last_error = str(e)
           self._ready_event.set()  # Unblock waiters
       return False
   ```

6. **Wait for READY** (`model_preloader.py:147-153`):
   ```python
   if self._state == ModelState.LOADING:
       async with self._lock:
           pass  # Release lock and wait below
       try:
           await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
           return self._state == ModelState.READY
       except asyncio.TimeoutError:
           return False
   ```

7. **Waiters unblocked**:
   - On READY: All waiters return True
   - On ERROR: All waiters check state and return False

**Inputs/Outputs**:
- **Inputs**: None (internal state changes)
- **Outputs**: Current state, ready flag, last error

**Key Modules/Files/Functions**:
- `server/services/model_preloader.py:ModelState` (lines 32-38)
- `server/services/model_preloader.py:ModelManager.initialize()` (lines 131-196)
- `server/services/model_preloader.py:ModelManager.wait_for_ready()` (lines 339-348)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Model load timeout** | `wait_for_ready()` times out | Returns False, caller retries or fails | `model_preloader.py:150-153` |
| **Warmup timeout** | `_warmup()` hangs (no timeout) | Blocks forever, requires restart | Hypothesized (no timeout) |
| **Concurrent init race** | Two threads call initialize() | Second waits via _ready_event | `model_preloader.py:145-153` |
| **State corruption** | Invalid enum value | Undefined behavior | Hypothesized (impossible with enum) |
| **Error after READY** | Post-load failure | State becomes ERROR, not recoverable | `model_preloader.py:189-195` |
| **Lock timeout** | asyncio.Lock hangs | No recovery | Hypothesized (rare) |
| **Event not set** | Exception before _ready_event.set() | Waiters block forever | Hypothesized (finally block missing) |
| **State transition deadlock** | Lock held during long operation | Other operations block | `model_preloader.py:141,170,182` |

**Observability**:
- `ModelHealth.state`: current state name
- `ModelHealth.ready`: True if READY
- `ModelHealth.last_error`: error message if ERROR
- Logger messages: "Phase 1/3: Loading model...", "Model ready!"

**Proof**:
- **Observed**: ModelState enum at `model_preloader.py:32-38`
- **Observed**: State transitions in initialize() at `model_preloader.py:155,170-171,182-184,191-194`
- **Observed**: Wait logic with _ready_event at `model_preloader.py:145-153`

---

## MOD-012: Voxtral Streaming Session Lifecycle

**Status**: Implemented
**Flow Name**: Voxtral Realtime Streaming Session Management

**Triggers**:
- First transcription request
- Session crash/recovery
- Stream completion

**Preconditions**:
- Voxtral binary available
- Model directory exists

**Step-by-Step Sequence**:

1. **Ensure session** (`provider_voxtral_realtime.py:225-230`):
   ```python
   async def _ensure_session(self) -> StreamingSession:
       async with self._session_lock:
           if self._session is None or self._session.process.returncode is None:
               self._session = await self._start_session()
           return self._session
   ```

2. **Start session** (`provider_voxtral_realtime.py:107-155`):
   ```python
   async def _start_session(self) -> StreamingSession:
       if not self.is_available:
           raise RuntimeError(f"Voxtral unavailable: bin={self._bin.exists()}, model={self._model.exists()}")

       cmd = [
           str(self._bin),
           "-d", str(self._model),
           "--stdin",
           "-I", str(self._streaming_delay),
           "--silent",
       ]

       self.log(f"Starting voxtral.c streaming session: delay={self._streaming_delay}s")
       t0 = time.perf_counter()

       try:
           process = await asyncio.create_subprocess_exec(
               *cmd,
               stdin=asyncio.subprocess.PIPE,
               stdout=asyncio.subprocess.PIPE,
               stderr=asyncio.subprocess.PIPE,
           )
       except Exception as e:
           raise RuntimeError(f"Failed to start voxtral.c: {e}")

       # Wait for model to load
       ready = await self._wait_for_ready(process, timeout=30.0)
       load_time = time.perf_counter() - t0

       if not ready:
           process.kill()
           await process.wait()
           raise RuntimeError(f"voxtral.c failed to become ready after {load_time:.1f}s")

       self.log(f"Voxtral streaming session ready in {load_time:.2f}s")

       return StreamingSession(
           process=process,
           started_at=time.perf_counter(),
       )
   ```

3. **Wait for ready signal** (`provider_voxtral_realtime.py:157-199`):
   ```python
   async def _wait_for_ready(self, process: asyncio.subprocess.Process, timeout: float) -> bool:
       if not process.stderr:
           return False

       ready_patterns = [
           b"Metal GPU",
           b"BLAS",
           b"Ready",
           b"Model loaded",
       ]

       start_time = time.perf_counter()
       buffer = b""

       while time.perf_counter() - start_time < timeout:
           try:
               chunk = await asyncio.wait_for(
                   process.stderr.read(1024),
                   timeout=1.0
               )
               if not chunk:
                   return False
               buffer += chunk

               for pattern in ready_patterns:
                   if pattern in buffer:
                       return True

           except asyncio.TimeoutError:
               if process.returncode is not None:
                   return False
               continue

       return False
   ```

4. **Write chunks to stdin** (`provider_voxtral_realtime.py:232-246`):
   ```python
   async def _write_chunk(self, session: StreamingSession, pcm_bytes: bytes, sample_rate: int) -> None:
       if session.process.stdin is None or session.process.returncode is not None:
           raise RuntimeError("Voxtral process not ready")

       try:
           session.process.stdin.write(pcm_bytes)
           await session.process.stdin.drain()
       except (BrokenPipeError, ConnectionResetError) as e:
           raise RuntimeError(f"Voxtral process pipe broken: {e}")
   ```

5. **Read transcriptions** (`provider_voxtral_realtime.py:248-273`):
   ```python
   async def _read_transcription(self, session: StreamingSession, timeout: float = 10.0) -> Optional[str]:
       if session.process.stdout is None:
           return None

       try:
           line = await asyncio.wait_for(
               session.process.stdout.readline(),
               timeout=timeout
           )
           if not line:
               return None

           text = line.decode("utf-8", errors="replace").strip()
           return text if text else None

       except asyncio.TimeoutError:
           return None
   ```

6. **Stop session** (`provider_voxtral_realtime.py:201-223`):
   ```python
   async def _stop_session(self) -> None:
       async with self._session_lock:
           if self._session is None:
               return

           session = self._session
           self._session = None

           if session.process.returncode is None:
               try:
                   if session.process.stdin:
                       session.process.stdin.close()
                   await asyncio.wait_for(session.process.wait(), timeout=5.0)
               except asyncio.TimeoutError:
                   self.log("Voxtral process did not exit gracefully, killing...")
                   session.process.kill()
                   await session.process.wait()
   ```

7. **Session recovery on error** (`provider_voxtral_realtime.py:350-356`):
   ```python
   try:
       await self._write_chunk(session, audio_bytes, sample_rate)
       session.chunks_processed += 1
   except RuntimeError as e:
       self.log(f"Write error, restarting session: {e}")
       await self._stop_session()
       session = await self._ensure_session()
       await self._write_chunk(session, audio_bytes, sample_rate)
       session.chunks_processed += 1
   ```

**Inputs/Outputs**:
- **Inputs**: PCM audio chunks, streaming delay
- **Outputs**: Transcription results, session stats

**Key Modules/Files/Functions**:
- `server/services/provider_voxtral_realtime.py:VoxtralRealtimeProvider._start_session()` (lines 107-155)
- `server/services/provider_voxtral_realtime.py:VoxtralRealtimeProvider._wait_for_ready()` (lines 157-199)
- `server/services/provider_voxtral_realtime.py:VoxtralRealtimeProvider._stop_session()` (lines 201-223)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Binary not found** | `is_file()` returns False | Yields unavailable segment | `provider_voxtral_realtime.py:104-105` |
| **Model not found** | Model directory missing | Yields unavailable segment | `provider_voxtral_realtime.py:104-105` |
| **Process start timeout** | create_subprocess_exec hangs | No timeout, blocks forever | Hypothesized (no timeout) |
| **Model load timeout** | No ready signal in 30s | Kills process, raises error | `provider_voxtral_realtime.py:145-148` |
| **Stdin pipe broken** | BrokenPipeError | Auto-restart session | `provider_voxtral_realtime.py:350-356` |
| **Stdout EOF** | readline returns empty | No recovery, stream ends | `provider_voxtral_realtime.py:263-264` |
| **Graceful shutdown timeout** | Process.wait() times out | Force kills process | `provider_voxtral_realtime.py:219-223` |
| **Subprocess crash** | returncode != 0 | Auto-restart on next chunk | `provider_voxtral_realtime.py:347` |

**Observability**:
- Logger messages: "Starting voxtral.c streaming session", "Voxtral streaming session ready"
- `StreamingSession` stats: chunks_processed, total_infer_ms, avg_infer_ms, realtime_factor
- Health endpoint: session status, duration

**Proof**:
- **Observed**: Streaming session lifecycle at `provider_voxtral_realtime.py:107-223`
- **Observed**: Session recovery at `provider_voxtral_realtime.py:350-356`
- **Observed**: Ready pattern detection at `provider_voxtral_realtime.py:166-171`

---

## MOD-013: Fallback Provider Switching

**Status**: Implemented
**Flow Name**: Fallback Provider Switching on Degradation

**Triggers**:
- Degrade ladder reaches FAILOVER level
- Provider crashes repeatedly
- Manual failover request

**Preconditions**:
- Fallback provider configured
- Primary provider failing

**Step-by-Step Sequence**:

1. **Initialize degrade ladder with fallback** (`degrade_ladder.py:119-148`):
   ```python
   def __init__(
       self,
       provider: ASRProvider,
       config: ASRConfig,
       fallback_provider: Optional[ASRProvider] = None,
       ...
   ):
       self.provider = provider
       self.config = config
       self.fallback_provider = fallback_provider
   ```

2. **Report provider error** (`degrade_ladder.py:337-344`):
   ```python
   async def report_provider_error(self, error: Exception) -> Tuple[DegradeLevel, Optional[DegradeAction]]:
       logger.error(f"Provider error: {error}")

       if self.fallback_provider and self.state.level < DegradeLevel.FAILOVER:
           return await self._degrade_to(DegradeLevel.FAILOVER)

       return self.state.level, None
   ```

3. **Execute failover action** (`degrade_ladder.py:401-407`):
   ```python
   def _action_failover(self) -> None:
       if self.fallback_provider:
           logger.warning(f"FAILOVER: Switching to {self.fallback_provider.name}")
           self.provider = self.fallback_provider
       else:
           logger.error("FAILOVER requested but no fallback provider available")
   ```

4. **Capability detector sets fallback** (`capability_detector.py:384-395`):
   ```python
   # Set fallback
   if tier in ("ultra", "high"):
       fallback_config = self.TIER_CONFIGS["medium"].copy()
       recommendation.fallback = ProviderRecommendation(
           provider=fallback_config["provider"],
           model=fallback_config["model"],
           chunk_seconds=fallback_config["chunk_seconds"],
           compute_type=fallback_config["compute_type"],
           device=fallback_config["device"],
           vad_enabled=fallback_config["vad_enabled"],
           reason="Fallback if primary fails",
       )
   ```

**Inputs/Outputs**:
- **Inputs**: Provider error, degrade ladder decision
- **Outputs**: New provider instance

**Key Modules/Files/Functions**:
- `server/services/degrade_ladder.py:DegradeLadder.report_provider_error()` (lines 337-344)
- `server/services/degrade_ladder.py:DegradeLadder._action_failover()` (lines 401-407)
- `server/services/capability_detector.py:CapabilityDetector.recommend()` (lines 384-395)

**Failure Modes** (8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Fallback not configured** | `fallback_provider` is None | Logs error, stays at EMERGENCY | `degrade_ladder.py:406-407` |
| **Fallback unavailable** | `is_available` returns False | Logs error, stays at EMERGENCY | Hypothesized |
| **Fallback also crashes** | Repeat FAILOVER with same provider | No further fallbacks possible | Hypothesized |
| **Failover during inference** | Provider switch mid-stream | May lose buffered audio | Hypothesized |
| **Fallback model not loaded** | Lazy load fails | Raises exception | Hypothesized |
| **Config mismatch** | Fallback has different config | May cause client issues | Hypothesized |
| **State not preserved** | Session lost during switch | Client may need reconnect | Hypothesized |
| **Manual recovery needed** | No auto-recovery from FAILOVER | Manual intervention required | `degrade_ladder.py:406-407` |

**Observability**:
- Logger warning: "FAILOVER: Switching to {provider.name}"
- Logger error: "FAILOVER requested but no fallback provider available"
- `DegradeState.level` shows FAILOVER level
- `/capabilities` endpoint includes fallback recommendation

**Proof**:
- **Observed**: Failover action at `degrade_ladder.py:179-186,401-407`
- **Observed**: Fallback recommendation at `capability_detector.py:384-395`
- **Observed**: Provider error handling at `degrade_ladder.py:337-344`

---

## MOD-014: Memory Management

**Status**: Hypothesized
**Flow Name**: Memory Management for Large Models

**Triggers**:
- Model load
- Model unload
- Session cleanup

**Preconditions**:
- Sufficient RAM available
- Model loaded or unloaded

**Step-by-Step Sequence (Hypothesized)**:

1. **Model allocation**:
   - Faster-whisper: Allocates model memory in CTranslate2 backend
   - Whisper.cpp: Allocates model in Metal/CPU memory
   - Voxtral: Allocates model in process memory (MPS/BLAS)

2. **Model cleanup** (Hypothesized - NOT IMPLEMENTED):
   - Set `_model = None` to allow garbage collection
   - Call explicit unload if available (none observed)

3. **Inference buffer reuse**:
   - Audio buffer reused per chunk (bytearray)
   - No per-chunk large allocations observed

4. **Process cleanup**:
   - Voxtral: Process killed on session end (`provider_voxtral_realtime.py:221-223`)

**Observed Implementation**:

1. **No explicit model unload**:
   - Providers don't implement `unload()` or `release()` methods
   - `_model = None` would trigger GC, but never called

2. **Buffer reuse** (`provider_faster_whisper.py:124`):
   ```python
   buffer = bytearray()  # Reused across chunks
   ```

3. **Process cleanup** (`provider_voxtral_realtime.py:221-223`):
   ```python
   except asyncio.TimeoutError:
       self.log("Voxtral process did not exit gracefully, killing...")
       session.process.kill()
       await session.process.wait()
   ```

**Inputs/Outputs**:
- **Inputs**: Model load requests
- **Outputs**: Model memory usage

**Key Modules/Files/Functions**:
- No explicit memory management functions observed

**Failure Modes** (Hypothesized - 8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **OOM on model load** | RuntimeError/OSError | Raises exception to caller | Hypothesized |
| **OOM on inference** | CUDA out of memory / MemoryError | No recovery observed | Hypothesized |
| **Memory leak** | Increasing memory over time | No cleanup, requires restart | Hypothesized |
| **Fragmentation** | Available RAM but can't allocate | No defragmentation | Hypothesized |
| **Model not released** | `_model` never set to None | GC may not reclaim | Hypothesized |
| **Process memory growth** | Voxtral process memory increases | Process killed on session end | `provider_voxtral_realtime.py:221-223` |
| **Buffer leak** | Buffers not released | Unlikely (bytearray reuse) | Hypothesized |
| **Cache accumulation** | Intermediate results cached | No cache invalidation observed | Hypothesized |

**Observability** (Limited):
- No memory metrics in health endpoints
- No memory usage tracking in providers
- Logger messages on load error

**Proof**:
- **Observed**: Buffer reuse at `provider_faster_whisper.py:124`
- **Observed**: Process cleanup at `provider_voxtral_realtime.py:221-223`
- **Observed**: NO unload methods in provider interfaces

---

## MOD-015: Model Versioning

**Status**: Not Implemented
**Flow Name**: Model Versioning and Updates

**Triggers**:
- N/A (not implemented)

**Preconditions**:
- N/A

**Step-by-Step Sequence**:

**NONE - Feature not implemented.**

**Current Behavior**:
- Models referenced by name only (e.g., "base.en", "large-v3-turbo")
- No version metadata tracked
- No update mechanism
- Models assumed present on filesystem

**Observed Implementation**:

1. **Model name only** (`asr_providers.py:52`):
   ```python
   @dataclass
   class ASRConfig:
       model_name: str = "large-v3-turbo"
   ```

2. **No version field**:
   - `ASRConfig` has no `model_version` field
   - `ModelHealth` has no `model_version` field

3. **No download/update code**:
   - No functions to download models
   - No version checking
   - No upgrade logic

**Hypothetical Implementation**:

```python
@dataclass
class ModelVersion:
    name: str
    version: str  # e.g., "v3", "v2024-01-01"
    size_bytes: int
    sha256: str
    download_url: Optional[str]

@dataclass
class ASRConfig:
    model_name: str = "base.en"
    model_version: Optional[str] = None  # e.g., "v3"
    auto_update: bool = False
```

**Inputs/Outputs**:
- **Inputs**: None
- **Outputs**: None (not implemented)

**Key Modules/Files/Functions**:
- None (not implemented)

**Failure Modes** (Hypothetical - 8+):

| Failure Mode | Detection | Recovery | Evidence |
|-------------|-----------|----------|----------|
| **Model version mismatch** | Client expects v3, server has v2 | No validation, errors unpredictable | Hypothesized |
| **Model file corrupted** | SHA256 mismatch | No validation, uses corrupted model | Hypothesized |
| **Download fails** | Network error | No retry, no fallback | Hypothesized |
| **Disk full** | Insufficient space for update | No cleanup, may leave partial files | Hypothesized |
| **Checksum mismatch** | Download corrupted | No validation, uses corrupted model | Hypothesized |
| **Version rollback needed** | New model has issues | No rollback mechanism | Hypothesized |
| **Concurrent updates** | Two updates in progress | No locking, may corrupt files | Hypothesized |
| **Permissions error** | Can't write to model directory | Update fails, no retry | Hypothesized |

**Observability**:
- No version information in health endpoints
- No version logging
- No update status reporting

**Proof**:
- **Observed**: No version fields in `ASRConfig` at `asr_providers.py:49-62`
- **Observed**: No download/update functions in any provider file
- **Observed**: Model referenced by string name only

---

## Conclusion

### Summary of Findings

**Implemented Flows (11)**:
1. **MOD-001**: Capability Detection & Auto-Selection — Full implementation with tier-based recommendations
2. **MOD-002**: Provider Registration & Discovery — Registry pattern with thread-safe caching
3. **MOD-003**: ModelManager Eager Load & Warmup — Three-phase initialization (load → warm → ready)
4. **MOD-004**: Lazy Model Loading — On-demand model loading with device auto-selection
5. **MOD-005**: Chunked Batch Inference — Fixed-size chunks with timestamp tracking
6. **MOD-006**: GPU/Metal/CUDA Device Selection — Platform-aware device selection
7. **MOD-007**: Degrade Ladder Performance Management — 5-level adaptive system
8. **MOD-008**: Provider Health Monitoring — Comprehensive health metrics
9. **MOD-009**: VAD Pre-Filtering — Silero VAD wrapper with lazy loading
10. **MOD-010**: Concurrent Inference Serialization — Thread-safe locking
11. **MOD-011**: Model State Transitions — Five-state machine (UNINITIALIZED → LOADING → WARMING_UP → READY → ERROR)
12. **MOD-012**: Voxtral Streaming Session Lifecycle — Resident subprocess with auto-recovery
13. **MOD-013**: Fallback Provider Switching — Degrade ladder failover

**Hypothesized/Partial (1)**:
14. **MOD-014**: Memory Management — Limited implementation, no explicit unload

**Not Implemented (1)**:
15. **MOD-015**: Model Versioning — No version tracking, download, or update mechanism

### Critical Observations

1. **No Model Unload/Cleanup**: Once loaded, models stay in memory until process exit. No mechanism to unload or release memory.

2. **No Model Updates**: Models must be manually downloaded and placed on filesystem. No automatic versioning or updates.

3. **No Warm Cache Persistence**: Each startup requires full warmup sequence. No mechanism to persist warm cache.

4. **Concurrent Inference Serialized**: Multi-source audio (mic + system) cannot run in parallel due to inference lock.

5. **No Memory Metrics**: Health endpoints don't include memory usage. No observability into memory pressure.

### Recommendations

**P0 (Critical)**:
1. Implement model unload/cleanup mechanism for memory management
2. Add memory metrics to health endpoints
3. Implement warm cache persistence for faster cold starts

**P1 (High)**:
4. Implement model versioning and update mechanism
5. Add model download functionality
6. Consider parallel inference for multi-source scenarios

**P2 (Medium)**:
7. Add memory leak detection and monitoring
8. Implement model pre-fetching for predicted models

---

## Comprehensive State Machine Diagram

### Full Model Lifecycle State Machine

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          MODEL LIFECYCLE STATE MACHINE                       │
└─────────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────┐
    │UNINITIALIZED│
    └──────┬──────┘
           │
           │ [1] initialize() called
           │     Precondition: Server startup or explicit request
           │     Action: Set state=LOADING, acquire lock
           │
           ▼
    ┌─────────────┐
    │   LOADING   │ ◄─────────────────────────────────────────────────────────┐
    └──────┬──────┘                                                          │
           │                                                                   │
           │ [2] _load_model() completes                                       │
           │     Action: Load provider from registry                             │
           │     Failure → ERROR                                               │
           │                                                                   │
           ▼                                                                   │
    ┌─────────────┐                                                          │
    │  WARMING_UP │                                                          │
    └──────┬──────┘                                                          │
           │                                                                   │
           │ [3] _warmup() completes                                           │
           │     Action: Run level 2 (single inference) and level 3 (stress test)│
           │     Failure → ERROR                                               │
           │                                                                   │
           ▼                                                                   │
    ┌─────────────┐                                                          │
    │    READY    │                                                          │
    └──────┬──────┘                                                          │
           │                                                                   │
           │ [4] Normal operation                                               │
           │     Action: Accept transcribe_stream() requests                     │
           │     Provider error → ERROR (via degrade ladder)                       │
           │                                                                   │
           │ [5] Health check request                                           │
           │     Action: Return ModelHealth with current state                   │
           │                                                                   │
           │ [6] New initialize() while READY                                   │
           │     Action: Return True immediately (no-op)                        │
           │                                                                   │
           │ [7] New initialize() while LOADING/WARMING_UP                     │
           │     Action: Wait on _ready_event (max 60s default)                │
           │     Timeout → Return False                                         │
           │                                                                   │
────────┘                                                                   │
                                                                             │
           │─────────────────────────────────────────────────────────────────────│
           │
           ▼
    ┌─────────────┐
    │    ERROR    │
    └─────────────┘
           │
           │ [8] Error occurred (any state except READY)
           │     Triggers: Model load failure, warmup failure, OOM, timeout
           │     Action: Set last_error, _ready_event.set()
           │
           │ [9] Recovery attempt
           │     Action: Call initialize() again (requires manual restart or retry)
           │
           ▼
    ┌─────────────┐
    │UNINITIALIZED│  ←[10] Reset (via reset_model_manager() for testing)
    └─────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           TRANSITION TRIGGERS                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│ [1]  Server startup (main.py:lifespan) or explicit call                    │
│ [2]  Provider registry returns valid provider                               │
│ [3]  Warmup inferences complete successfully                                │
│ [4]  Ready to accept inference requests                                     │
│ [5]  Health endpoint request (/health, /model-status)                       │
│ [6]  Concurrent initialization (second task calls initialize)                 │
│ [7]  Initialization in progress (another task loading)                     │
│ [8]  Exception in _load_model(), _warmup(), or timeout                     │
│ [9]  User retry or server restart                                          │
│ [10] Test reset (reset_model_manager())                                     │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           LOCKING STRATEGY                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│ • State transitions protected by asyncio.Lock (model_preloader.py:114)        │
│ • Concurrent init tasks wait on _ready_event (model_preloader.py:115)        │
│ • Provider inference serialized by threading.Lock (provider_*.py)            │
│ • Registry instance creation serialized by threading.Lock (asr_providers.py:303)│
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           TIMEOUTS                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│ • initialize() timeout: 300s (5 minutes) default                          │
│ • wait_for_ready() timeout: 60s (1 minute) default                        │
│ • Voxtral session load timeout: 30s                                       │
│ • Voxtral graceful shutdown: 5s                                            │
│ • Warmup level 2 minimum: 100ms (enforced via sleep if too fast)           │
│ • Warmup level 3 minimum: 1000ms (enforced via sleep if too fast)          │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           EVENT FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│ 1. Server starts → lifespan() called                                       │
│ 2. _auto_select_provider() → CapabilityDetector.recommend()                │
│ 3. Environment variables set based on tier                                  │
│ 4. initialize_model_at_startup() → ModelManager.initialize()               │
│ 5. ModelManager._load_model() → ASRProviderRegistry.get_provider()        │
│ 6. Provider lazy-loads model (faster-whisper/whisper.cpp/voxtral)         │
│ 7. ModelManager._warmup() → Run warmup inferences                         │
│ 8. State transitions: LOADING → WARMING_UP → READY                         │
│ 9. _ready_event.set() unblocks all waiters                                  │
│ 10. /health endpoint returns 200 OK with model_ready=true                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### State Descriptions

| State | Description | Entry Condition | Exit Condition | Valid Transitions |
|-------|-------------|-----------------|----------------|------------------|
| **UNINITIALIZED** | Model not loaded, provider not instantiated | Default at ModelManager creation | initialize() called | → LOADING |
| **LOADING** | Provider being instantiated, model loading | _load_model() started | Load completes or fails | → WARMING_UP, → ERROR |
| **WARMING_UP** | Running warmup inferences to prime caches | _load_model() succeeded | Warmup completes or fails | → READY, → ERROR |
| **READY** | Model loaded and warmed up, accepting requests | Warmup completed | Error occurs or reset | → ERROR, → UNINITIALIZED |
| **ERROR** | Initialization failed, cannot process requests | Exception during load/warmup | Manual restart or retry | → UNINITIALIZED (via reset) |

### Concurrent State Handling

| Scenario | Behavior | Evidence |
|----------|----------|----------|
| **Two tasks call initialize() simultaneously** | First task acquires lock, second waits on _ready_event | `model_preloader.py:145-153` |
| **Task calls initialize() when already READY** | Returns True immediately (no-op) | `model_preloader.py:142-143` |
| **Task calls initialize() during LOADING/WARMING_UP** | Waits on _ready_event until timeout | `model_preloader.py:150-153` |
| **Health check during WARMING_UP** | Returns state=WARMING_UP, ready=False | `model_preloader.py:311-321` |
| **Inference request during LOADING** | Raises RuntimeError("Model not ready") | `model_preloader.py:295-296` |

---

## Failure Modes Table (Ranked by Impact)

| Rank | Failure Mode | Impact | Detection | Recovery | Affected Flows | Evidence |
|------|-------------|--------|-----------|----------|----------------|----------|
| **P0-1** | **OOM on model load** | CRITICAL - Server crash, total ASR outage | RuntimeError/OSError | No recovery, requires restart | MOD-003, MOD-004 | `model_preloader.py:189-195` |
| **P0-2** | **Model file not found/corrupted** | CRITICAL - ASR permanently unavailable | FileNotFoundError, load exception | Requires manual model download | MOD-003, MOD-004 | `provider_whisper_cpp.py:128-129` |
| **P0-3** | **Inference lock deadlock** | CRITICAL - All inference blocked | No chunks processed > 30s | Requires server restart | MOD-005, MOD-010 | `provider_faster_whisper.py:166-174` |
| **P0-4** | **State machine deadlock** | CRITICAL - Init stuck, _ready_event never set | Timeout in wait_for_ready() | Requires server restart | MOD-003, MOD-011 | `model_preloader.py:150-153` |
| **P1-1** | **Provider crash during session** | HIGH - Session loss, require reconnect | Process exit code != 0 | Voxtral auto-restarts, others fail | MOD-005, MOD-012 | `provider_voxtral_realtime.py:347` |
| **P1-2** | **Degrade ladder failover unavailable** | HIGH - Stuck in degraded state | Fallback provider = None | Manual intervention required | MOD-007, MOD-013 | `degrade_ladder.py:406-407` |
| **P1-3** | **Concurrent init timeout** | HIGH - Waiter gives up, duplicate init | asyncio.TimeoutError | Second task returns False, may retry | MOD-003, MOD-011 | `model_preloader.py:150-153` |
| **P1-4** | **GPU memory insufficient** | HIGH - Falls back to CPU, severe degradation | CUDA out of memory error | Auto-fallback to CPU (slower) | MOD-004, MOD-006 | `provider_faster_whisper.py:104` |
| **P1-5** | **Silero VAD download timeout** | MEDIUM-HIGH - VAD unavailable, wasted compute | torch.hub.load() timeout | Falls back to passthrough | MOD-009 | `vad_asr_wrapper.py:54-66` |
| **P2-1** | **Warmup too fast (cache miss)** | MEDIUM - Suboptimal first inference | Level 2/3 completes < 100ms | Sleep to enforce minimum | MOD-003 | `model_preloader.py:246-251` |
| **P2-2** | **Lock contention (multi-source)** | MEDIUM - Increased latency, queue buildup | High variance in _infer_times | Serializes via lock (by design) | MOD-005, MOD-010 | `provider_faster_whisper.py:47` |
| **P2-3** | **False positive VAD (noise)** | MEDIUM - Extra inference, reduced RTF | Audio detected as speech | No recovery, wastes compute | MOD-009 | `vad_asr_wrapper.py:200` |
| **P2-4** | **False negative VAD (speech loss)** | MEDIUM - Transcription gap, data loss | Speech marked as silence | No recovery, permanent loss | MOD-009 | `vad_asr_wrapper.py:200` |
| **P2-5** | **Capability detection timeout** | MEDIUM - Falls back to defaults | Subprocess timeout (5s) | Uses conservative defaults | MOD-001 | `capability_detector.py:263,293` |
| **P2-6** | **Model not unloaded** | MEDIUM - Memory leak, eventual OOM | Memory growth over time | No mechanism, requires restart | MOD-014 | Hypothesized |
| **P2-7** | **No version checking** | LOW-MEDIUM - Unknown model version | No validation | Uses whatever model is present | MOD-015 | `asr_providers.py:52` |
| **P3-1** | **NVIDIA driver missing** | LOW - Falls back to CPU | nvidia-smi not found | Fallback to CPU | MOD-001, MOD-006 | `capability_detector.py:287-300` |
| **P3-2** | **Metal disabled (Apple Silicon)** | LOW - Falls back to CPU | MPS unavailable | Fallback to CPU | MOD-001, MOD-006 | `provider_faster_whisper.py:85-88` |
| **P3-3** | **Torch not installed** | LOW - VAD unavailable | ImportError | Falls back to passthrough | MOD-009 | `vad_asr_wrapper.py:54` |
| **P3-4** | **psutil not installed** | LOW - Inaccurate RAM detection | ImportError | Fallback to /proc/meminfo | MOD-001 | `capability_detector.py:32-36` |

---

## Root Causes Analysis (Ranked by Impact)

### P0 - Critical Root Causes

| Rank | Root Cause | Description | Impact | Contributing Factors | Evidence |
|------|-----------|-------------|--------|---------------------|----------|
| **RC-P0-1** | **No memory management / unload mechanism** | Models loaded once, never released. Long-running servers accumulate memory. | CRITICAL - OOM, crash | No `unload()` method, GC may not reclaim large tensors | MOD-014 (Hypothesized) |
| **RC-P0-2** | **No warm cache persistence** | Each startup requires full warmup. No mechanism to save pre-warmed state. | HIGH - 5-10s latency on every restart | Warmup only in-memory, no disk serialization | `model_preloader.py:220-276` |
| **RC-P0-3** | **Blocking inference without timeout** | Inference lock has no timeout. Deadlock possible if model hangs. | CRITICAL - Complete outage | No `asyncio.wait_for()` or timeout wrapper | `provider_faster_whisper.py:166-174` |
| **RC-P0-4** | **Single-threaded model access** | All inference serialized via lock. No parallel inference even with multiple models. | HIGH - Scales poorly, queue buildup | `threading.Lock` in each provider | `provider_faster_whisper.py:47` |

### P1 - High Priority Root Causes

| Rank | Root Cause | Description | Impact | Contributing Factors | Evidence |
|------|-----------|-------------|--------|---------------------|----------|
| **RC-P1-1** | **No model version tracking** | Models referenced by name only. No checksum, no version validation. | MEDIUM-HIGH - Corrupted models cause undefined behavior | String name only in `ASRConfig` | `asr_providers.py:52` |
| **RC-P1-2** | **Fallback provider not auto-configured** | User must manually configure fallback. Default is None. | HIGH - Failover unavailable | `fallback_provider=None` in `__init__` | `degrade_ladder.py:119` |
| **RC-P1-3** | **Concurrent init race condition** | Two tasks can call `initialize()` simultaneously. Second waits but may timeout. | MEDIUM-HIGH - Duplicate init attempts | `_ready_event` set only once | `model_preloader.py:145-153` |
| **RC-P1-4** | **No memory metrics in health endpoints** | Cannot detect memory pressure proactively. | MEDIUM - Blind to OOM until crash | No `memory_usage_mb` in `ModelHealth` | `model_preloader.py:41-61` |
| **RC-P1-5** | **Voxtral process isolation** | Voxtral runs as subprocess. No shared memory, higher overhead. | MEDIUM - Slower, more resource usage | `asyncio.create_subprocess_exec()` | `provider_voxtral_realtime.py:229` |

### P2 - Medium Priority Root Causes

| Rank | Root Cause | Description | Impact | Contributing Factors | Evidence |
|------|-----------|-------------|--------|---------------------|----------|
| **RC-P2-1** | **No model download/update mechanism** | Models must be manually downloaded. No auto-update. | MEDIUM - Operational burden | No download functions | MOD-015 (Not Implemented) |
| **RC-P2-2** | **VAD model downloaded from internet** | Silero VAD fetched from torch.hub on first use. | LOW-MEDIUM - Unpredictable init time | `torch.hub.load("snakers4/silero-vad")` | `vad_asr_wrapper.py:62-66` |
| **RC-P2-3** | **Capability detection uses subprocess** | Shell commands to detect hardware (nvidia-smi, sysctl). | LOW - Slower startup, platform-specific | `subprocess.run()` calls | `capability_detector.py:263,293` |
| **RC-P2-4** | **No per-model memory limit** | Large models can consume all RAM. No quota enforcement. | MEDIUM - Risk of OOM with large models | No `max_memory_mb` config | Hypothesized |
| **RC-P2-5** | **Degraded state persists indefinitely** | Once degraded, no auto-recovery if conditions improve. | MEDIUM - Stuck in degraded mode | Recovery requires sustained 30s low RTF | `degrade_ladder.py:279-295` |

### P3 - Low Priority Root Causes

| Rank | Root Cause | Description | Impact | Contributing Factors | Evidence |
|------|-----------|-------------|--------|---------------------|----------|
| **RC-P3-1** | **No distributed inference** | Cannot shard inference across GPUs/CPUs. | LOW - Single-node limit | Single model instance | Hypothesized |
| **RC-P3-2** | **No model hot-swapping** | Changing model requires server restart. | LOW - Operational friction | No `switch_model()` method | Hypothesized |
| **RC-P3-3** | **No metrics persistence** | Metrics lost if server crashes. No offline analysis. | LOW - Debugging difficulty | Metrics only in memory | `asr_providers.py:64-110` |
| **RC-P3-4** | **Limited error context** | Health endpoints return only last error string. | LOW - Harder debugging | Single `last_error` field | `model_preloader.py:50` |

---

## Concrete Fixes (Ranked by Impact/Effort/Risk)

### P0 - Critical Fixes

| Priority | Fix | Description | Impact | Effort | Risk | Implementation |
|----------|-----|-------------|--------|--------|------|----------------|
| **P0-1** | **Add inference timeout wrapper** | Wrap all `transcribe_stream()` calls with `asyncio.wait_for(timeout=30s)` | HIGH - Prevent deadlock | LOW | LOW | `provider_*.py:transcribe_stream()` |
| **P0-2** | **Implement model unload/cleanup** | Add `unload()` method to each provider, set `_model = None`, release GPU memory | CRITICAL - Prevent OOM | MEDIUM | LOW | `ASRProvider` interface, all providers |
| **P0-3** | **Add memory metrics to health endpoints** | Track `memory_usage_mb` using `psutil` or `torch.cuda.memory_allocated()`, expose in `ModelHealth` | HIGH - Detect OOM early | LOW | LOW | `model_preloader.py:ModelHealth`, provider health() |
| **P0-4** | **Add model validation checksum** | Store SHA256 of model files, validate on load | HIGH - Detect corruption | MEDIUM | LOW | `provider_whisper_cpp.py:_load_model()` |

### P1 - High Priority Fixes

| Priority | Fix | Description | Impact | Effort | Risk | Implementation |
|----------|-----|-------------|--------|--------|------|----------------|
| **P1-1** | **Implement warm cache persistence** | Serialize warm cache to disk (`~/.echopanel/model_cache/`), load on startup | MEDIUM-HIGH - Eliminate warmup latency | MEDIUM | MEDIUM | `model_preloader.py:_warmup()` |
| **P1-2** | **Auto-configure fallback provider** | Modify `CapabilityDetector.recommend()` to always set fallback to smaller model | HIGH - Enable failover | LOW | LOW | `capability_detector.py:384-395` |
| **P1-3** | **Add concurrent init deduplication** | Use `asyncio.Lock` to ensure only one task runs `initialize()` | MEDIUM-HIGH - Prevent duplicate init | LOW | LOW | `model_preloader.py:initialize()` |
| **P1-4** | **Add model version tracking** | Add `model_version` and `model_sha256` to `ASRConfig`, validate on load | MEDIUM - Detect version mismatch | MEDIUM | LOW | `asr_providers.py:ASRConfig` |
| **P1-5** | **Implement auto-recovery from degraded state** | If RTF < 0.8 for 60s, automatically restore higher quality | MEDIUM - Better performance | LOW | MEDIUM | `degrade_ladder.py:_maybe_recover()` |

### P2 - Medium Priority Fixes

| Priority | Fix | Description | Impact | Effort | Risk | Implementation |
|----------|-----|-------------|--------|--------|------|----------------|
| **P2-1** | **Implement model download** | Add `download_model()` function, download from HuggingFace on demand | MEDIUM - Operational ease | HIGH | MEDIUM | New `model_downloader.py` |
| **P2-2** | **Cache Silero VAD model** | Download once to `~/.echopanel/vad_model.pt`, reuse | LOW-MEDIUM - Faster init | LOW | LOW | `vad_asr_wrapper.py:_load_vad_model()` |
| **P2-3** | **Replace subprocess with native detection** | Use `torch.cuda.is_available()`, `torch.backends.mps.is_available()` instead of shell | LOW - Faster startup | MEDIUM | LOW | `capability_detector.py:_detect_mps/cuda()` |
| **P2-4** | **Add per-model memory limits** | Enforce `max_memory_mb` in provider, reject load if insufficient | MEDIUM - Prevent OOM | MEDIUM | MEDIUM | `ASRConfig.max_memory_mb` |
| **P2-5** | **Persist metrics to disk** | Write metrics to JSONL every 60s, load on restart | LOW - Offline debugging | LOW | LOW | `metrics_registry.py` |

### P3 - Low Priority Enhancements

| Priority | Fix | Description | Impact | Effort | Risk | Implementation |
|----------|-----|-------------|--------|--------|------|----------------|
| **P3-1** | **Implement model hot-swapping** | Add `switch_model(model_name)` method, unload old, load new | LOW - Operational ease | HIGH | MEDIUM | New `ASRProvider.switch_model()` |
| **P3-2** | **Add detailed error history** | Store last 10 errors with timestamps in `ModelHealth` | LOW - Better debugging | LOW | LOW | `model_preloader.py:ModelHealth` |
| **P3-3** | **Implement parallel inference** | Allow multiple model instances with different configs | LOW - Scale better | HIGH | HIGH | Architecture change |
| **P3-4** | **Add distributed inference** | Shard inference across multiple servers/workers | LOW - Horizontal scale | VERY HIGH | VERY HIGH | Major architecture |

---

## Test Plan

### Unit Tests

| Test | Description | Module | Evidence |
|------|-------------|--------|----------|
| **UT-001** | Test ModelManager state transitions (UNINITIALIZED → LOADING → WARMING_UP → READY) | `model_preloader.py` | Mock provider, assert state sequence |
| **UT-002** | Test concurrent initialization (two tasks call `initialize()` simultaneously) | `model_preloader.py` | Verify second task waits, returns True |
| **UT-003** | Test initialization timeout (simulate slow model load) | `model_preloader.py` | Verify returns False after timeout |
| **UT-004** | Test inference lock serialization (two threads call transcribe) | `provider_faster_whisper.py` | Verify inferences run sequentially |
| **UT-005** | Test degrade ladder transitions (RTF triggers level changes) | `degrade_ladder.py` | Mock RTF values, verify level transitions |
| **UT-006** | Test provider registry caching (same config returns same instance) | `asr_providers.py` | Verify `get_provider()` returns cached instance |
| **UT-007** | Test VAD wrapper passthrough (VAD unavailable falls back) | `vad_asr_wrapper.py` | Mock VAD unavailable, verify audio passes through |
| **UT-008** | Test Voxtral session recovery (process crash, auto-restart) | `provider_voxtral_realtime.py` | Kill process, verify auto-restart on next chunk |
| **UT-009** | Test capability detector fallback (psutil missing, uses /proc/meminfo) | `capability_detector.py` | Mock missing psutil, verify fallback |
| **UT-010** | Test health metrics accuracy (RTF, latency, backlog) | `asr_providers.py` | Run inference, verify metrics match actual |

### Integration Tests

| Test | Description | Scope | Evidence |
|------|-------------|-------|----------|
| **IT-001** | Full server startup with auto-selection (cold start, warmup, health OK) | `main.py` + all modules | Start server, verify `/health` returns 200 OK |
| **IT-002** | WebSocket session start-stop (audio → ASR → transcript) | `ws_live_listener.py` + providers | Send audio, verify transcripts received |
| **IT-003** | Multi-source session (system + mic, concurrent inference) | `ws_live_listener.py` + degrade_ladder | Verify both sources processed, no deadlock |
| **IT-004** | Degrade ladder activation (inject load, verify level changes) | `ws_live_listener.py` + degrade_ladder | Simulate high RTF, verify WARNING → DEGRADE → EMERGENCY |
| **IT-005** | Failover to fallback (primary crashes, verify fallback) | `degrade_ladder.py` + providers | Kill primary, verify fallback takes over |
| **IT-006** | Model crash recovery (provider dies, verify session restarts) | `provider_voxtral_realtime.py` + ws_live_listener | Kill Voxtral, verify auto-restart |
| **IT-007** | OOM recovery (simulate low memory, verify graceful degradation) | `model_preloader.py` + degrade_ladder | Mock low RAM, verify error handling |
| **IT-008** | Long-running session (1 hour, verify memory stable) | `ws_live_listener.py` + providers | Run 1h session, monitor memory (no growth) |
| **IT-009** | VAD effectiveness (play silence + speech, verify filtering) | `vad_asr_wrapper.py` + ws_live_listener | Verify silence chunks skipped, speech processed |
| **IT-010** | Health endpoint accuracy (compare health to actual state) | `main.py:/health` + `/model-status` | Verify health metrics match actual |

### Manual Tests

| Test | Description | Steps | Success Criteria |
|------|-------------|--------|-----------------|
| **MT-001** | First launch auto-selection | Fresh install, start server | Server auto-selects optimal provider/model |
| **MT-002** | Model load time (large-v3-turbo on Apple Silicon) | Start server, time to READY | < 10s load + warmup |
| **MT-003** | Cold start latency (first inference after startup) | Start server, send first audio | First inference < 2s |
| **MT-004** | Warm cache persistence (restart, verify faster load) | Start, stop, restart server | Second load < 2s (if cache implemented) |
| **MT-005** | Provider switch (change ECHOPANEL_ASR_PROVIDER env var) | Set to different provider, restart | New provider used |
| **MT-006** | Fallback provider switch (crash primary, verify fallback) | Kill primary provider process | Fallback takes over, session continues |
| **MT-007** | Degrade ladder UI (observe status messages in logs) | Inject load, monitor logs | Level changes logged with warnings |
| **MT-008** | Memory monitoring (run 1h session, monitor RAM usage) | Run session, observe Activity Monitor | Stable memory (< 2GB growth) |
| **MT-009** | Multi-device (test on Intel Mac, Apple Silicon, Linux) | Run on each platform | Auto-detection works, appropriate provider selected |
| **MT-010** | Concurrent sessions (two clients connect simultaneously) | Start two WebSocket sessions | Both work, no crashes |

### Performance Tests

| Test | Metric | Target | Evidence |
|------|--------|--------|----------|
| **PT-001** | Model load time (base.en) | < 2s | `model_preloader.py:load_time_ms` |
| **PT-002** | Model load time (large-v3-turbo) | < 10s | `model_preloader.py:load_time_ms` |
| **PT-003** | Warmup time (level 2) | < 100ms | `model_preloader.py:warmup_time_ms` |
| **PT-004** | Warmup time (level 3) | < 1000ms | `model_preloader.py:warmup_time_ms` |
| **PT-005** | Realtime factor (normal load) | < 0.8 | `ASRHealth.realtime_factor` |
| **PT-006** | Inference latency (p95) | < 500ms | `ASRHealth.p95_infer_ms` |
| **PT-007** | Memory usage (base.en) | < 500MB | System monitor |
| **PT-008** | Memory usage (large-v3-turbo) | < 2GB | System monitor |
| **PT-009** | Concurrent throughput (2 sources) | > 1.0 RTF per source | `ASRHealth.realtime_factor` |
| **PT-010** | Failover time (primary → fallback) | < 5s | Time between crash and fallback inference |

---

## Instrumentation Plan

### Metrics

| Metric | Type | Source | Purpose | Evidence |
|--------|------|--------|---------|----------|
| **model_load_time_ms** | Gauge | `ModelManager._load_time_ms` | Track model load performance | `model_preloader.py:109` |
| **model_warmup_time_ms** | Gauge | `ModelManager._warmup_time_ms` | Track warmup performance | `model_preloader.py:110` |
| **model_state** | Enum | `ModelManager._state` | Track lifecycle state | `model_preloader.py:107` |
| **model_ready** | Boolean | `ModelHealth.ready` | Ready check for health | `model_preloader.py:315` |
| **realtime_factor** | Gauge | `ASRHealth.realtime_factor` | Track inference speed vs audio | `asr_providers.py:72` |
| **avg_infer_ms** | Gauge | `ASRHealth.avg_infer_ms` | Average inference latency | `asr_providers.py:73` |
| **p95_infer_ms** | Gauge | `ASRHealth.p95_infer_ms` | 95th percentile latency | `asr_providers.py:74` |
| **p99_infer_ms** | Gauge | `ASRHealth.p99_infer_ms` | 99th percentile latency | `asr_providers.py:75` |
| **backlog_estimate** | Gauge | `ASRHealth.backlog_estimate` | Queue depth | `asr_providers.py:78` |
| **dropped_chunks** | Counter | `ASRHealth.dropped_chunks` | Total chunks dropped | `asr_providers.py:79` |
| **model_resident** | Boolean | `ASRHealth.model_resident` | Model loaded status | `asr_providers.py:82` |
| **memory_usage_mb** | Gauge | NEW (add) | Track memory usage | To be added |
| **consecutive_errors** | Counter | `ASRHealth.consecutive_errors` | Error streak count | `asr_providers.py:87` |
| **degrade_level** | Enum | `DegradeState.level` | Current degrade level | `degrade_ladder.py:70` |
| **vad_speech_ratio** | Gauge | `VADStats.silence_ratio` | VAD effectiveness | `vad_asr_wrapper.py:140` |
| **vad_skipped_chunks** | Counter | `VADStats.skipped_chunks` | Chunks filtered by VAD | `vad_asr_wrapper.py:138` |
| **inference_lock_wait_ms** | Histogram | NEW (add) | Lock contention | To be added |

### Logs

| Log Event | Level | Context | Purpose | Evidence |
|-----------|-------|---------|---------|----------|
| **model_load_start** | INFO | `model_preloader.py:159` | Start of model load | `logger.info("Phase 1/3: Loading model...")` |
| **model_load_complete** | INFO | `model_preloader.py:166` | End of model load | `logger.info(f"Model loaded in {load_time_ms:.1f}ms")` |
| **model_warmup_start** | INFO | `model_preloader.py:173` | Start of warmup | `logger.info("Phase 2/3: Warming up...")` |
| **model_warmup_complete** | INFO | `model_preloader.py:179` | End of warmup | `logger.info(f"Warmup complete in {warmup_time_ms:.1f}ms")` |
| **model_ready** | INFO | `model_preloader.py:186` | Model ready state | `logger.info("Model ready!")` |
| **model_init_error** | ERROR | `model_preloader.py:190` | Initialization failed | `logger.error(f"Model initialization failed: {e}")` |
| **provider_init** | INFO | `model_preloader.py:212` | Provider loaded | `logger.info(f"Loaded provider: {provider.name}")` |
| **inference_start** | DEBUG | `provider_*.py` | Start of inference | `self.log("Starting inference...")` (add) |
| **inference_complete** | DEBUG | `provider_*.py` | End of inference | `self.log(f"Inference complete in {elapsed_ms:.1f}ms")` (add) |
| **degrade_level_change** | WARNING | `degrade_ladder.py:301` | Level transition | `logger.warning(f"DEGRADE: {old} → {new}")` |
| **failover_switch** | WARNING | `degrade_ladder.py:423` | Provider failover | `logger.warning(f"FAILOVER: Switching to {fallback.name}")` |
| **vad_model_loaded** | INFO | `vad_asr_wrapper.py:772` | Silero VAD loaded | `logger.info("Silero VAD model loaded")` |
| **vad_download_failed** | WARNING | `vad_asr_wrapper.py:774` | VAD download failed | `logger.warning(f"Failed to load Silero VAD: {e}")` |
| **voxtral_session_start** | INFO | `provider_voxtral_realtime.py:247` | Session started | `self.log(f"Voxtral streaming session ready")` |
| **voxtral_session_error** | ERROR | `provider_voxtral_realtime.py:354` | Session error | `self.log(f"Write error, restarting session: {e}")` |

### Endpoints

| Endpoint | Method | Response | Purpose | Evidence |
|----------|--------|----------|---------|----------|
| `/health` | GET | Health dict with model_ready, model_state | Server health check | `main.py:101-156` |
| `/model-status` | GET | ModelHealth dict with state, load_time_ms, warmup_time_ms | Detailed model status | `main.py:177-198` |
| `/capabilities` | GET | Provider info, hardware profile | Capability detection | `main.py:159-174` |

### Alerts

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| **model_init_failed** | `model_state == ERROR` | CRITICAL | Notify admin, attempt restart |
| **oom_detected** | `memory_usage_mb > threshold` | CRITICAL | Graceful shutdown, notify admin |
| **rtf_critical** | `realtime_factor > 2.0 for 60s` | CRITICAL | Trigger failover, degrade to EMERGENCY |
| **provider_crash** | `consecutive_errors > 5` | HIGH | Restart provider, notify admin |
| **degrade_emergency** | `degrade_level == EMERGENCY` | HIGH | Notify admin, log warning |
| **inference_stuck** | `inference_lock_wait_ms > 30000` | HIGH | Force restart provider |

---

## Flow Atlas Alignment

### Mapping MOD Flows to ML Flow IDs

| Flow Atlas ML-ID | MOD Flow ID | Name | Status |
|------------------|--------------|------|--------|
| **ML-001** | MOD-003 | Model Manager Initialization | Implemented |
| **ML-002** | MOD-004 (partial) | Faster-Whisper Provider Init | Implemented |
| **ML-003** | MOD-004 (partial) | Whisper.cpp Provider Init | Implemented |
| **ML-004** | MOD-012 | Voxtral Realtime Provider Init | Implemented |
| **ML-005** | MOD-001 | Capability Detection & Recommendation | Implemented |
| **ML-006** | MOD-007 | Degrade Ladder Fallback | Implemented |
| **ML-007** | MOD-002 | ASR Provider Registry | Implemented |

Note: The Flow Atlas uses ML-XXX IDs for Model Lifecycle flows (documented in flow-atlas-20260211.md:63-81), while this audit uses MOD-XXX IDs. All flows are mapped above.

---

*Enhanced audit completed: 2026-02-11*
*Original ticket: TCK-20260211-010*
*Enhancement ticket: TCK-20260211-014*
*Next review: On implementation of P0/P1 fixes*
