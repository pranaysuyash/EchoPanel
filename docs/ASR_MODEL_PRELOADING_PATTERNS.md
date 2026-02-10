# ML Model Preloading & Warming Patterns for Python ASR Services

**Research Document** | February 2026

---

## Executive Summary

This document provides comprehensive research on best practices for preloading and warming ML models in Python-based ASR (Automatic Speech Recognition) services. It covers model residency patterns, preloading strategies, Python-specific implementations, and ASR-specific considerations for frameworks like faster-whisper (CTranslate2), Whisper.cpp, and Silero VAD.

---

## Table of Contents

1. [Model Residency Patterns](#1-model-residency-patterns)
2. [Preloading Strategies](#2-preloading-strategies)
3. [Python-Specific Patterns](#3-python-specific-patterns)
4. [ASR-Specific Considerations](#4-asr-specific-considerations)
5. [Implementation Examples](#5-implementation-examples)
6. [Trade-off Analysis](#6-trade-off-analysis)
7. [References](#7-references)

---

## 1. Model Residency Patterns

### 1.1 Keeping Models Resident in Memory

The primary goal of model residency is to avoid the cost of loading models from disk on every request. For ASR services, model loading can take 5-30 seconds depending on model size and storage speed.

#### Pattern: Instance Caching with Thread-Safe Registry

**Concept**: Maintain a registry that caches model instances keyed by configuration parameters.

```python
"""
Thread-safe ASR Provider Registry Pattern
Supports multiple model configurations simultaneously.
"""
import threading
from typing import Optional, Dict
from dataclasses import dataclass


@dataclass(frozen=True)
class ModelConfig:
    """Immutable configuration for model caching."""
    model_name: str
    device: str
    compute_type: str
    language: Optional[str] = None


class ModelRegistry:
    """
    Thread-safe registry for model instance caching.
    
    Benefits:
    - Prevents duplicate model loads for identical configs
    - Thread-safe instance creation
    - Supports multiple model variants simultaneously
    """
    _instances: Dict[str, any] = {}
    _lock: threading.Lock = threading.Lock()
    
    @classmethod
    def get_model(cls, config: ModelConfig, loader: callable):
        """
        Get or create model instance thread-safely.
        
        Args:
            config: Model configuration (must be hashable)
            loader: Callable that returns a new model instance
        """
        # Create unique key from config
        key = f"{config.model_name}:{config.device}:{config.compute_type}:{config.language}"
        
        # Double-checked locking pattern
        if key not in cls._instances:
            with cls._lock:
                # Re-check after acquiring lock
                if key not in cls._instances:
                    cls._instances[key] = loader(config)
        
        return cls._instances[key]
    
    @classmethod
    def clear(cls):
        """Clear all cached instances (useful for testing/memory cleanup)."""
        with cls._lock:
            cls._instances.clear()
```

**Trade-offs**:
| Aspect | Pros | Cons |
|--------|------|------|
| Memory | Single instance per config | Baseline memory usage always present |
| Latency | Zero load time after first request | First request pays full load cost |
| Concurrency | Thread-safe access | Lock contention under high load |

#### Pattern: Singleton with Lazy Initialization

**Concept**: Ensure only one model instance exists globally, created on first access.

```python
"""
Singleton Pattern for Single-Model Deployments
Simplest pattern when only one model configuration is needed.
"""
import threading
from typing import Optional


class WhisperModelSingleton:
    """
    Thread-safe singleton for Whisper model.
    
    Note: This pattern is simpler but less flexible than registry pattern.
          Best for single-tenant deployments with fixed configuration.
    """
    _instance: Optional["WhisperModel"] = None
    _lock: threading.Lock = threading.Lock()
    _initialized: bool = False
    
    @classmethod
    def get_instance(cls, model_name: str = "base", device: str = "cpu") -> "WhisperModel":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    from faster_whisper import WhisperModel
                    cls._instance = WhisperModel(model_name, device=device)
                    cls._initialized = True
        return cls._instance
    
    @classmethod
    def is_initialized(cls) -> bool:
        """Check if model has been loaded (useful for health checks)."""
        return cls._initialized
```

### 1.2 Lazy Loading vs Eager Loading

#### Lazy Loading (On-Demand)

```python
"""
Lazy Loading Pattern
Model is loaded when first request arrives.
"""
class LazyASRProvider:
    def __init__(self, config: ASRConfig):
        self.config = config
        self._model: Optional[WhisperModel] = None
        self._load_lock = threading.Lock()
    
    @property
    def model(self) -> WhisperModel:
        """Thread-safe lazy model access."""
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._model = self._load_model()
        return self._model
    
    def _load_model(self) -> WhisperModel:
        """Actual model loading logic."""
        return WhisperModel(
            self.config.model_name,
            device=self.config.device,
            compute_type=self.config.compute_type
        )
```

**When to use Lazy Loading**:
- Development/testing environments
- Services with intermittent ASR usage
- Multi-tenant services where tenants use different models
- Memory-constrained environments

#### Eager Loading (Startup)

```python
"""
Eager Loading with FastAPI Lifespan
Model is loaded before server accepts any requests.
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI


# Global state for models (shared across requests)
models: dict[str, any] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Eager loading during application startup.
    
    Benefits:
    - First request has same latency as subsequent requests
    - Health check can verify model is ready
    - Predictable memory allocation at startup
    """
    # Startup: Load all required models
    models["whisper"] = WhisperModel("base", device="cpu")
    models["vad"] = load_silero_vad()
    
    # Optional: Warmup inference to initialize GPU kernels
    _warmup_model(models["whisper"])
    
    yield  # Server now accepts requests
    
    # Shutdown: Cleanup resources
    models.clear()


app = FastAPI(lifespan=lifespan)


def _warmup_model(model: WhisperModel):
    """
    Perform dummy inference to warm up the model.
    This initializes GPU kernels and prevents first-request latency spike.
    """
    import numpy as np
    dummy_audio = np.zeros(16000, dtype=np.float32)  # 1 second of silence
    list(model.transcribe(dummy_audio))
```

**When to use Eager Loading**:
- Production ASR services
- Real-time streaming applications
- Services with strict latency SLAs
- GPU deployments (kernel initialization is expensive)

### 1.3 Dependency Injection vs Singleton

#### Dependency Injection Pattern

```python
"""
Dependency Injection Pattern
Models are injected into request handlers, enabling testability and flexibility.
"""
from typing import Protocol
from fastapi import Depends


class ASRModel(Protocol):
    """Protocol for ASR model interface."""
    def transcribe(self, audio: np.ndarray) -> list: ...


class FasterWhisperModel:
    """Concrete implementation."""
    def __init__(self, model_name: str, device: str):
        self._model = WhisperModel(model_name, device=device)
    
    def transcribe(self, audio: np.ndarray) -> list:
        return list(self._model.transcribe(audio))


# Dependency provider
async def get_asr_model() -> ASRModel:
    """FastAPI dependency that provides the cached model."""
    return ModelRegistry.get_model(
        config=ModelConfig("base", "cpu", "int8"),
        loader=lambda c: FasterWhisperModel(c.model_name, c.device)
    )


@app.post("/transcribe")
async def transcribe(
    audio: UploadFile,
    model: ASRModel = Depends(get_asr_model)  # Injected dependency
):
    """Handler receives model via dependency injection."""
    audio_data = await audio.read()
    result = model.transcribe(audio_to_numpy(audio_data))
    return {"transcription": result}
```

**Comparison**:

| Pattern | Testability | Flexibility | Complexity | Best For |
|---------|-------------|-------------|------------|----------|
| Singleton | Low | Low | Low | Simple deployments |
| Registry | Medium | Medium | Medium | Multi-config services |
| Dependency Injection | High | High | High | Enterprise/microservices |

### 1.4 Warmup Strategies

#### Dummy Inference Warmup

```python
"""
Model Warmup Strategies
Prevents cold-start latency by running dummy inference.
"""
import numpy as np
import time
from typing import Callable


class ModelWarmer:
    """
    Handles model warmup with configurable strategies.
    """
    
    @staticmethod
    def warmup_whisper(
        model: WhisperModel,
        sample_rate: int = 16000,
        duration_seconds: float = 1.0,
        num_iterations: int = 1
    ) -> float:
        """
        Warmup Whisper model with dummy audio.
        
        Args:
            model: Loaded Whisper model
            sample_rate: Audio sample rate
            duration_seconds: Length of dummy audio
            num_iterations: Number of warmup runs (GPU benefits from multiple)
        
        Returns:
            Total warmup time in seconds
        """
        samples = int(sample_rate * duration_seconds)
        dummy_audio = np.zeros(samples, dtype=np.float32)
        
        start = time.perf_counter()
        for _ in range(num_iterations):
            # Force full forward pass by converting generator to list
            list(model.transcribe(dummy_audio))
        elapsed = time.perf_counter() - start
        
        return elapsed
    
    @staticmethod
    def warmup_vad(model, utils, sample_rate: int = 16000) -> float:
        """Warmup Silero VAD model."""
        import torch
        (get_speech_timestamps, _, _, _, _) = utils
        
        dummy_audio = torch.zeros(sample_rate)  # 1 second
        
        start = time.perf_counter()
        get_speech_timestamps(
            dummy_audio,
            model,
            sampling_rate=sample_rate,
            threshold=0.5
        )
        elapsed = time.perf_counter() - start
        
        return elapsed
```

#### Tiered Warmup Strategy

```python
"""
Tiered Warmup for Production Services
Different warmup levels based on deployment requirements.
"""
from enum import Enum


class WarmupLevel(Enum):
    NONE = "none"           # No warmup (fastest startup)
    MINIMAL = "minimal"     # Single inference pass
    STANDARD = "standard"   # Multiple passes + batched warmup
    FULL = "full"           # Comprehensive warmup with various input sizes


def tiered_warmup(model, level: WarmupLevel = WarmupLevel.STANDARD):
    """
    Execute warmup based on specified level.
    
    Use NONE for: Development, CI/CD
    Use MINIMAL for: Quick restarts, CPU-only deployments
    Use STANDARD for: Production GPU services
    Use FULL for: Services with strict latency requirements
    """
    if level == WarmupLevel.NONE:
        return
    
    if level == WarmupLevel.MINIMAL:
        ModelWarmer.warmup_whisper(model, num_iterations=1)
    
    elif level == WarmupLevel.STANDARD:
        # Multiple iterations for GPU kernel stabilization
        ModelWarmer.warmup_whisper(model, num_iterations=3)
        # Warmup with different chunk sizes
        for duration in [0.5, 1.0, 4.0]:
            ModelWarmer.warmup_whisper(model, duration_seconds=duration)
    
    elif level == WarmupLevel.FULL:
        # Comprehensive warmup
        ModelWarmer.warmup_whisper(model, num_iterations=5)
        # Warmup with various audio characteristics
        for duration in [0.1, 0.5, 1.0, 5.0, 10.0, 30.0]:
            ModelWarmer.warmup_whisper(model, duration_seconds=duration)
```

---

## 2. Preloading Strategies

### 2.1 Server Startup vs On-First-Request

#### Decision Matrix

| Factor | Startup Preloading | On-First-Request |
|--------|-------------------|------------------|
| **First Request Latency** | Low (model ready) | High (load + infer) |
| **Startup Time** | Slow (seconds to minutes) | Fast (instant) |
| **Resource Waste** | Higher (always loaded) | Lower (load on demand) |
| **Failure Mode** | Fails fast at startup | Fails on first request |
| **Auto-scaling** | Slower scale-out | Faster scale-out |
| **Memory Usage** | Constant baseline | Variable |

#### Hybrid Approach: Configurable Loading Strategy

```python
"""
Configurable Model Loading Strategy
Allows deployment-time selection of loading behavior.
"""
import os
from enum import Enum
from typing import Optional


class LoadingStrategy(Enum):
    EAGER = "eager"      # Load at startup
    LAZY = "lazy"        # Load on first request
    HYBRID = "hybrid"    # Background load with fallback


class ConfigurableModelLoader:
    """
    Model loader that supports multiple loading strategies.
    
    Environment variable: MODEL_LOADING_STRATEGY=[eager|lazy|hybrid]
    """
    
    def __init__(
        self,
        model_name: str,
        strategy: Optional[LoadingStrategy] = None
    ):
        self.model_name = model_name
        self.strategy = strategy or LoadingStrategy(
            os.getenv("MODEL_LOADING_STRATEGY", "lazy")
        )
        self._model: Optional[WhisperModel] = None
        self._loading = False
        self._load_event = asyncio.Event()
    
    async def initialize(self):
        """Called during application startup."""
        if self.strategy == LoadingStrategy.EAGER:
            await self._load_model()
        elif self.strategy == LoadingStrategy.HYBRID:
            # Start background loading
            asyncio.create_task(self._background_load())
    
    async def _background_load(self):
        """Background loading for hybrid strategy."""
        self._loading = True
        try:
            await self._load_model()
        finally:
            self._load_event.set()
            self._loading = False
    
    async def _load_model(self):
        """Actual model loading (async wrapper for sync load)."""
        self._model = await asyncio.to_thread(
            WhisperModel,
            self.model_name,
            device="auto"
        )
    
    async def get_model(self) -> WhisperModel:
        """Get model, handling all strategies."""
        if self._model is not None:
            return self._model
        
        if self.strategy == LoadingStrategy.HYBRID and self._loading:
            # Wait for background load to complete
            await self._load_event.wait()
            return self._model
        
        # Lazy loading path
        if self.strategy in (LoadingStrategy.LAZY, LoadingStrategy.HYBRID):
            await self._load_model()
            return self._model
        
        raise RuntimeError("Model not loaded and strategy doesn't permit lazy loading")
```

### 2.2 Health Check Patterns

#### Three-State Health Check

```python
"""
Health Check Patterns for Model-Backed Services
Provides visibility into model readiness state.
"""
from fastapi import FastAPI, HTTPException
from enum import Enum
from dataclasses import dataclass
from typing import Optional
import time


class ServiceState(Enum):
    STARTING = "starting"       # Server up, model not loaded
    WARMING_UP = "warming_up"   # Model loading in progress
    READY = "ready"             # Model loaded and warmed up
    DEGRADED = "degraded"       # Model loaded but errors detected
    UNAVAILABLE = "unavailable" # Model failed to load


@dataclass
class HealthStatus:
    state: ServiceState
    provider: Optional[str]
    model: Optional[str]
    latency_ms: Optional[float]  # Last inference latency
    uptime_seconds: float
    details: dict


class HealthMonitor:
    """
    Comprehensive health monitoring for ASR services.
    """
    _start_time: float = time.time()
    _state: ServiceState = ServiceState.STARTING
    _last_inference_time: Optional[float] = None
    _error_count: int = 0
    
    @classmethod
    def set_state(cls, state: ServiceState):
        cls._state = state
    
    @classmethod
    def record_inference(cls, latency_ms: float):
        cls._last_inference_time = latency_ms
        cls._error_count = 0  # Reset on success
    
    @classmethod
    def record_error(cls):
        cls._error_count += 1
        if cls._error_count > 5:
            cls._state = ServiceState.DEGRADED
    
    @classmethod
    def get_status(cls) -> HealthStatus:
        return HealthStatus(
            state=cls._state,
            provider=getattr(cls, '_provider', None),
            model=getattr(cls, '_model', None),
            latency_ms=cls._last_inference_time,
            uptime_seconds=time.time() - cls._start_time,
            details={"error_count": cls._error_count}
        )


@app.get("/health")
async def health_check():
    """
    Kubernetes-compatible health check endpoint.
    
    Returns:
        200: Service is ready to accept traffic
        503: Service is starting/warming (kubelet will retry)
    """
    status = HealthMonitor.get_status()
    
    if status.state == ServiceState.READY:
        return {
            "status": "healthy",
            "state": status.state.value,
            "provider": status.provider,
            "model": status.model,
            "uptime_seconds": status.uptime_seconds
        }
    
    elif status.state in (ServiceState.STARTING, ServiceState.WARMING_UP):
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "state": status.state.value,
                "message": "Model is still loading"
            }
        )
    
    elif status.state == ServiceState.DEGRADED:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "degraded",
                "state": status.state.value,
                "error_count": status.details["error_count"]
            }
        )
    
    else:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unavailable",
                "state": status.state.value
            }
        )


@app.get("/ready")
async def readiness_probe():
    """
    Kubernetes readiness probe endpoint.
    Simple pass/fail for traffic routing decisions.
    """
    if HealthMonitor._state == ServiceState.READY:
        return {"ready": True}
    raise HTTPException(status_code=503, detail="not ready")
```

#### Deep Health Check with Model Verification

```python
"""
Deep Health Check Pattern
Verifies model can actually perform inference, not just loaded.
"""
import numpy as np
from fastapi import HTTPException


async def deep_health_check(model_holder: ModelHolder) -> dict:
    """
    Performs actual inference to verify model health.
    
    Use sparingly - this consumes compute resources.
    Suitable for:
    - Startup verification
    - Periodic liveness checks (e.g., every 30s)
    - Before marking instance as ready in load balancer
    """
    model = model_holder.model
    if model is None:
        raise HTTPException(503, detail="Model not loaded")
    
    # Run test inference
    test_audio = np.zeros(8000, dtype=np.float32)  # 0.5s silence
    
    try:
        start = time.perf_counter()
        result = list(model.transcribe(test_audio))
        latency_ms = (time.perf_counter() - start) * 1000
        
        return {
            "status": "healthy",
            "inference_latency_ms": latency_ms,
            "test_result_empty": len(result) == 0  # Silence should produce no segments
        }
    except Exception as e:
        raise HTTPException(503, detail=f"Inference failed: {str(e)}")
```

### 2.3 Memory Management

#### LRU Cache for Multi-Model Services

```python
"""
LRU Cache Pattern for Multi-Model ASR Services
Automatically unloads least-recently-used models.
"""
from functools import lru_cache
from typing import Callable
import gc


class LRUModelCache:
    """
    LRU cache for model instances with memory-aware eviction.
    
    Useful for:
    - Multi-tenant SaaS with per-tenant custom models
    - Services supporting multiple languages with different models
    - Development environments with limited memory
    """
    
    def __init__(self, max_models: int = 3):
        self.max_models = max_models
        self._cache: OrderedDict[str, any] = OrderedDict()
        self._lock = threading.Lock()
    
    def get(self, key: str, loader: Callable[[], any]) -> any:
        """Get model from cache or load it."""
        with self._lock:
            if key in self._cache:
                # Move to end (most recently used)
                self._cache.move_to_end(key)
                return self._cache[key]
            
            # Evict oldest if at capacity
            while len(self._cache) >= self.max_models:
                self._evict_oldest()
            
            # Load new model
            model = loader()
            self._cache[key] = model
            return model
    
    def _evict_oldest(self):
        """Remove least recently used model."""
        oldest_key, oldest_model = self._cache.popitem(last=False)
        
        # Explicit cleanup for GPU models
        if hasattr(oldest_model, 'unload_model'):
            oldest_model.unload_model()
        
        # Force garbage collection
        del oldest_model
        gc.collect()
        
        # Clear CUDA cache if available
        try:
            import torch
            torch.cuda.empty_cache()
        except ImportError:
            pass
    
    def clear(self):
        """Clear all cached models."""
        with self._lock:
            self._cache.clear()
            gc.collect()
```

#### Memory-Pressure-Based Unloading

```python
"""
Memory-Pressure-Aware Model Management
Automatically unloads models when system memory is low.
"""
import psutil
import asyncio
from typing import Optional


class MemoryAwareModelManager:
    """
    Manages model residency based on system memory pressure.
    """
    
    def __init__(
        self,
        memory_threshold_percent: float = 85.0,
        check_interval_seconds: float = 30.0
    ):
        self.threshold = memory_threshold_percent
        self.interval = check_interval_seconds
        self._models: dict[str, any] = {}
        self._last_used: dict[str, float] = {}
        self._lock = asyncio.Lock()
    
    async def start_monitoring(self):
        """Start background memory monitoring task."""
        while True:
            await asyncio.sleep(self.interval)
            await self._check_memory_pressure()
    
    async def _check_memory_pressure(self):
        """Check memory and unload models if necessary."""
        memory = psutil.virtual_memory()
        
        if memory.percent > self.threshold:
            async with self._lock:
                # Unload least recently used models until memory is freed
                while memory.percent > self.threshold and self._models:
                    await self._unload_lru_model()
                    memory = psutil.virtual_memory()
    
    async def _unload_lru_model(self):
        """Unload the least recently used model."""
        if not self._last_used:
            return
        
        # Find LRU model
        lru_key = min(self._last_used, key=self._last_used.get)
        model = self._models.pop(lru_key)
        del self._last_used[lru_key]
        
        # Async cleanup
        await asyncio.to_thread(self._cleanup_model, model)
    
    def _cleanup_model(self, model):
        """Synchronous model cleanup."""
        if hasattr(model, 'unload_model'):
            model.unload_model()
        del model
        gc.collect()
```

---

## 3. Python-Specific Patterns

### 3.1 Using `@functools.lru_cache` for Model Instances

```python
"""
Using functools.lru_cache for Model Caching
Simple but effective for basic use cases.

WARNING: lru_cache is thread-safe for the cache structure itself,
but the cached function execution is not protected from concurrent calls.
"""
from functools import lru_cache
from typing import Optional


@lru_cache(maxsize=3)
def get_whisper_model_cached(
    model_name: str,
    device: str,
    compute_type: str
) -> "WhisperModel":
    """
    Cached model loader using lru_cache.
    
    IMPORTANT: Multiple concurrent calls with same args may result in
    multiple model loads. Use external locking for true singleton behavior.
    """
    return WhisperModel(model_name, device=device, compute_type=compute_type)


# Thread-safe wrapper with locking
_model_load_locks: dict[str, threading.Lock] = {}
_model_load_locks_lock = threading.Lock()


def get_whisper_model_threadsafe(
    model_name: str,
    device: str,
    compute_type: str
) -> "WhisperModel":
    """
    Thread-safe model loading with per-configuration locking.
    """
    cache_key = f"{model_name}:{device}:{compute_type}"
    
    # Get or create lock for this config
    with _model_load_locks_lock:
        if cache_key not in _model_load_locks:
            _model_load_locks[cache_key] = threading.Lock()
        lock = _model_load_locks[cache_key]
    
    # Double-checked locking
    cached = get_whisper_model_cached.cache_info()  # Can't check directly, rely on lru_cache
    
    with lock:
        return get_whisper_model_cached(model_name, device, compute_type)
```

**lru_cache Considerations**:

| Aspect | Behavior | Implication |
|--------|----------|-------------|
| Thread Safety | Cache structure is thread-safe | Concurrent calls with different args are safe |
| Function Execution | Not synchronized | Same-args concurrent calls execute in parallel |
| Cache Key | Based on hash of arguments | All args must be hashable |
| Memory | Never evicted until maxsize | Monitor cache_info() for fullness |

### 3.2 Thread-Safe Model Access

#### Lock-Based Serialization

```python
"""
Thread-Safe Model Access Patterns
Critical for ASR where model inference may not be thread-safe.
"""
import threading
from contextlib import contextmanager


class ThreadSafeASRProvider:
    """
    Provider with explicit inference locking.
    
    CTranslate2 models can be thread-safe with num_workers > 1,
    but explicit locking provides predictable behavior.
    """
    
    def __init__(self, config: ASRConfig):
        self.config = config
        self._model: Optional[WhisperModel] = None
        
        # Separate locks for loading vs inference
        self._load_lock = threading.Lock()
        self._infer_lock = threading.Lock()
    
    def _get_model(self) -> WhisperModel:
        """Thread-safe lazy loading."""
        if self._model is None:
            with self._load_lock:
                if self._model is None:
                    self._model = WhisperModel(
                        self.config.model_name,
                        device=self.config.device
                    )
        return self._model
    
    def transcribe(self, audio: np.ndarray) -> list:
        """
        Thread-safe transcription with serialized inference.
        
        Trade-off: Sequential processing vs result consistency.
        """
        model = self._get_model()
        
        with self._infer_lock:
            # Only one thread can inference at a time
            return list(model.transcribe(audio))


class ReaderWriterLockASRProvider:
    """
    Reader-Writer lock for scenarios with concurrent reads.
    
    Allows multiple concurrent inference calls (reader pattern)
    while still serializing model modifications (writer pattern).
    """
    
    def __init__(self):
        self._model: Optional[WhisperModel] = None
        self._rw_lock = threading.RLock()
        self._readers = 0
        self._readers_lock = threading.Lock()
    
    @contextmanager
    def _read_lock(self):
        """Acquire read lock (allows multiple readers)."""
        with self._readers_lock:
            self._readers += 1
            if self._readers == 1:
                self._rw_lock.acquire()
        try:
            yield
        finally:
            with self._readers_lock:
                self._readers -= 1
                if self._readers == 0:
                    self._rw_lock.release()
    
    def transcribe(self, audio: np.ndarray) -> list:
        with self._read_lock():
            return list(self._model.transcribe(audio))
```

#### Thread Pool for Model Inference

```python
"""
Thread Pool Pattern for Model Inference
Isolates model inference to dedicated worker threads.
"""
from concurrent.futures import ThreadPoolExecutor
import asyncio


class ThreadPoolASRProvider:
    """
    ASR provider using dedicated thread pool for inference.
    
    Benefits:
    - Limits concurrent inference to prevent resource exhaustion
    - Provides backpressure when overloaded
    - Isolates inference from async event loop
    """
    
    def __init__(
        self,
        config: ASRConfig,
        max_workers: int = 2  # Tune based on GPU memory
    ):
        self.config = config
        self._model: Optional[WhisperModel] = None
        self._executor = ThreadPoolExecutor(
            max_workers=max_workers,
            thread_name_prefix="asr_inference"
        )
        self._model_lock = threading.Lock()
    
    def _get_model(self) -> WhisperModel:
        """Thread-safe model loading."""
        if self._model is None:
            with self._model_lock:
                if self._model is None:
                    self._model = WhisperModel(
                        self.config.model_name,
                        device=self.config.device
                    )
        return self._model
    
    async def transcribe_async(self, audio: np.ndarray) -> list:
        """
        Async transcription using thread pool.
        
        The thread pool provides:
        - Limited concurrency (backpressure)
        - Non-blocking from async perspective
        """
        loop = asyncio.get_event_loop()
        
        # Submit to thread pool
        future = loop.run_in_executor(
            self._executor,
            self._transcribe_sync,
            audio
        )
        
        return await future
    
    def _transcribe_sync(self, audio: np.ndarray) -> list:
        """Synchronous transcription (runs in thread pool)."""
        model = self._get_model()
        return list(model.transcribe(audio))
    
    async def shutdown(self):
        """Graceful shutdown of thread pool."""
        self._executor.shutdown(wait=True)
```

### 3.3 Async-Friendly Model Loading

#### Loading in Thread Pool

```python
"""
Async-Friendly Model Loading
Model loading is typically synchronous and blocking.
"""
import asyncio


class AsyncModelLoader:
    """
    Handles synchronous model loading without blocking the event loop.
    """
    
    def __init__(self):
        self._model: Optional[WhisperModel] = None
        self._loading = False
        self._loaded_event = asyncio.Event()
    
    async def load_async(self, model_name: str, device: str = "cpu"):
        """
        Load model without blocking the event loop.
        
        Uses asyncio.to_thread (Python 3.9+) for offloading to thread pool.
        """
        if self._loading:
            raise RuntimeError("Model already loading")
        
        self._loading = True
        try:
            # Offload blocking model loading to thread pool
            self._model = await asyncio.to_thread(
                WhisperModel,
                model_name,
                device=device
            )
            self._loaded_event.set()
        finally:
            self._loading = False
    
    async def get_model(self) -> WhisperModel:
        """Get model, waiting for load if necessary."""
        if self._model is not None:
            return self._model
        
        # Wait for loading to complete
        await self._loaded_event.wait()
        return self._model


# Integration with FastAPI lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Non-blocking model loading during startup."""
    loader = AsyncModelLoader()
    
    # Start loading in background (doesn't block other startup tasks)
    load_task = asyncio.create_task(loader.load_async("base", device="cpu"))
    
    # Can perform other startup tasks here...
    
    # Wait for model to be ready
    await load_task
    
    app.state.model_loader = loader
    yield
    
    # Cleanup
    del app.state.model_loader
```

#### Concurrent Multi-Model Loading

```python
"""
Concurrent Loading of Multiple Models
Load multiple models in parallel during startup.
"""
import asyncio
from dataclasses import dataclass


@dataclass
class ModelSpec:
    name: str
    model_type: str
    device: str


async def load_models_concurrently(specs: list[ModelSpec]) -> dict[str, any]:
    """
    Load multiple models concurrently.
    
    Benefits:
    - Faster startup when loading multiple models
    - Parallel I/O (model file reads)
    - Efficient when models load to different GPUs
    """
    
    async def load_single(spec: ModelSpec) -> tuple[str, any]:
        """Load a single model asynchronously."""
        if spec.model_type == "whisper":
            model = await asyncio.to_thread(
                WhisperModel,
                spec.name,
                device=spec.device
            )
        elif spec.model_type == "vad":
            model = await asyncio.to_thread(load_silero_vad)
        else:
            raise ValueError(f"Unknown model type: {spec.model_type}")
        
        return spec.name, model
    
    # Load all models concurrently
    results = await asyncio.gather(*[
        load_single(spec) for spec in specs
    ])
    
    return dict(results)


# Usage in FastAPI startup
@asynccontextmanager
async def lifespan(app: FastAPI):
    specs = [
        ModelSpec("base", "whisper", "cuda:0"),
        ModelSpec("vad", "vad", "cpu"),
    ]
    
    models = await load_models_concurrently(specs)
    app.state.models = models
    
    yield
    
    # Cleanup
    app.state.models.clear()
```

---

## 4. ASR-Specific Considerations

### 4.1 Faster-Whisper (CTranslate2) Model Loading

```python
"""
Faster-Whisper (CTranslate2) Specific Patterns
CTranslate2 provides several configuration options affecting performance.
"""
from faster_whisper import WhisperModel
import os


class CTranslate2Config:
    """
    CTranslate2-specific configuration options.
    
    Key parameters for production deployment:
    - device: "cpu", "cuda", "auto"
    - device_index: GPU index for multi-GPU systems
    - compute_type: "int8", "float16", "int8_float16"
    - cpu_threads: Number of threads for CPU inference
    - num_workers: Thread pool size for parallel inference
    """
    
    def __init__(
        self,
        model_name: str = "base",
        device: str = "auto",
        compute_type: str = "int8",
        num_workers: int = 1,
        cpu_threads: int = 0,  # 0 = auto
    ):
        self.model_name = model_name
        self.device = device
        self.compute_type = compute_type
        self.num_workers = num_workers
        self.cpu_threads = cpu_threads


def create_optimized_model(config: CTranslate2Config) -> WhisperModel:
    """
    Create CTranslate2 model with production optimizations.
    
    Environment variables CTranslate2 respects:
    - CT2_USE_EXPERIMENTAL_PACKED_GEMM: Enable for faster inference on GPU
    - CT2_FORCE_CPU_ISA: Force specific CPU instruction set
    """
    
    # Auto-detect optimal settings
    if config.device == "auto":
        import torch
        config.device = "cuda" if torch.cuda.is_available() else "cpu"
    
    # CPU-specific optimizations
    cpu_threads = config.cpu_threads
    if config.device == "cpu" and cpu_threads == 0:
        import multiprocessing
        cpu_threads = max(1, multiprocessing.cpu_count() // 2)
    
    model = WhisperModel(
        config.model_name,
        device=config.device,
        device_index=0,  # Primary GPU
        compute_type=config.compute_type,
        cpu_threads=cpu_threads,
        num_workers=config.num_workers,
    )
    
    return model


class CTranslate2Provider:
    """
    Production-ready provider for faster-whisper.
    
    Handles CTranslate2-specific considerations:
    - num_workers for parallel processing
    - Thread-safety for concurrent inference
    - Proper GPU memory management
    """
    
    def __init__(self, config: CTranslate2Config):
        self.config = config
        self._model: Optional[WhisperModel] = None
        self._lock = threading.Lock()
        
        # CTranslate2 with num_workers > 1 can handle concurrent calls,
        # but we use a lock for predictable resource usage
        self._use_lock = config.num_workers == 1
    
    def _get_model(self) -> WhisperModel:
        if self._model is None:
            with self._lock:
                if self._model is None:
                    self._model = create_optimized_model(self.config)
                    # Warmup
                    self._warmup()
        return self._model
    
    def _warmup(self):
        """CTranslate2-specific warmup."""
        import numpy as np
        dummy = np.zeros(16000, dtype=np.float32)
        list(self._model.transcribe(dummy))
    
    async def transcribe(
        self,
        audio: np.ndarray,
        beam_size: int = 5,
        best_of: int = 5,
        vad_filter: bool = False
    ):
        """
        Transcribe with CTranslate2-specific optimizations.
        
        Args:
            beam_size: Beam search width (higher = better quality, slower)
            best_of: Number of candidates for temperature sampling
            vad_filter: Enable Silero VAD pre-filtering
        """
        model = self._get_model()
        
        def _infer():
            if self._use_lock:
                with self._lock:
                    return list(model.transcribe(
                        audio,
                        beam_size=beam_size,
                        best_of=best_of,
                        vad_filter=vad_filter
                    ))
            else:
                return list(model.transcribe(
                    audio,
                    beam_size=beam_size,
                    best_of=best_of,
                    vad_filter=vad_filter
                ))
        
        return await asyncio.to_thread(_infer)
```

**CTranslate2 Performance Considerations**:

| Parameter | Recommendation | Rationale |
|-----------|---------------|-----------|
| `num_workers` | 1 for GPU, 2-4 for CPU | GPU memory is limiting factor |
| `compute_type` | "int8" for CPU, "float16" for GPU | Balance speed vs accuracy |
| `cpu_threads` | Physical core count / 2 | Avoid hyperthreading contention |
| `beam_size` | 5 for production | Balance quality vs latency |

### 4.2 Whisper.cpp Server Patterns

```python
"""
Whisper.cpp Integration Patterns
Whisper.cpp runs as external process; communication via subprocess or HTTP.
"""
import subprocess
import tempfile
import os
from pathlib import Path


class WhisperCppServer:
    """
    Manages whisper.cpp server process.
    
    whisper.cpp server features:
    - HTTP API for transcription
    - Persistent model in memory
    - Multiple concurrent requests supported
    """
    
    def __init__(
        self,
        model_path: str,
        host: str = "127.0.0.1",
        port: int = 8080,
        threads: int = 4,
    ):
        self.model_path = model_path
        self.host = host
        self.port = port
        self.threads = threads
        self._process: Optional[subprocess.Popen] = None
    
    def start(self) -> None:
        """Start whisper.cpp server process."""
        cmd = [
            "./server",  # whisper.cpp server binary
            "-m", self.model_path,
            "--host", self.host,
            "--port", str(self.port),
            "-t", str(self.threads),
            "--convert",  # Convert audio automatically
        ]
        
        self._process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        
        # Wait for server to be ready
        self._wait_for_ready()
    
    def _wait_for_ready(self, timeout: float = 30.0):
        """Wait for HTTP server to accept connections."""
        import urllib.request
        import time
        
        start = time.time()
        while time.time() - start < timeout:
            try:
                urllib.request.urlopen(
                    f"http://{self.host}:{self.port}/health",
                    timeout=1
                )
                return
            except:
                time.sleep(0.1)
        
        raise TimeoutError("Server failed to start")
    
    def stop(self):
        """Gracefully stop the server."""
        if self._process:
            self._process.terminate()
            self._process.wait(timeout=5)
            self._process = None


class WhisperCppClient:
    """
    HTTP client for whisper.cpp server.
    
    Provides Pythonic interface to whisper.cpp HTTP API.
    """
    
    def __init__(self, base_url: str = "http://127.0.0.1:8080"):
        self.base_url = base_url
        import httpx
        self._client = httpx.AsyncClient()
    
    async def transcribe(
        self,
        audio_bytes: bytes,
        language: Optional[str] = None,
        response_format: str = "json"
    ) -> dict:
        """
        Transcribe audio using whisper.cpp server.
        
        Server keeps model resident; client just sends HTTP requests.
        """
        files = {"file": ("audio.wav", audio_bytes, "audio/wav")}
        data = {"response_format": response_format}
        if language:
            data["language"] = language
        
        response = await self._client.post(
            f"{self.base_url}/inference",
            files=files,
            data=data
        )
        response.raise_for_status()
        return response.json()
    
    async def health(self) -> dict:
        """Check server health."""
        response = await self._client.get(f"{self.base_url}/health")
        return response.json()
```

### 4.3 VAD Model Preloading

```python
"""
Silero VAD Preloading Patterns
VAD is often used as preprocessor for ASR.
"""
import torch
from typing import Tuple


class SileroVADManager:
    """
    Manages Silero VAD model with proper preloading.
    
    Key considerations:
    - torch.hub.load downloads model on first use
    - Model should be loaded once and reused
    - Thread-safe for concurrent VAD operations
    """
    
    _model: Optional[torch.nn.Module] = None
    _utils: Optional[tuple] = None
    _lock = threading.Lock()
    _loaded = False
    
    @classmethod
    def load(cls, force_reload: bool = False) -> Tuple[torch.nn.Module, tuple]:
        """
        Load Silero VAD model globally.
        
        Args:
            force_reload: Force re-download from torch hub
        
        Returns:
            Tuple of (model, utils)
        """
        if cls._loaded and not force_reload:
            return cls._model, cls._utils
        
        with cls._lock:
            if cls._loaded and not force_reload:
                return cls._model, cls._utils
            
            model, utils = torch.hub.load(
                repo_or_dir="snakers4/silero-vad",
                model="silero_vad",
                force_reload=force_reload,
                onnx=False,  # Use PyTorch version (faster on GPU)
            )
            
            cls._model = model
            cls._utils = utils
            cls._loaded = True
            
            # Set to eval mode (important for deterministic behavior)
            cls._model.eval()
            
            return cls._model, cls._utils
    
    @classmethod
    def warmup(cls):
        """Warmup VAD model with dummy audio."""
        model, utils = cls.load()
        (get_speech_timestamps, _, _, _, _) = utils
        
        # Dummy audio - 1 second
        dummy = torch.zeros(16000)
        
        # Warmup run
        with torch.no_grad():
            get_speech_timestamps(
                dummy,
                model,
                sampling_rate=16000,
                threshold=0.5
            )
    
    @classmethod
    def is_loaded(cls) -> bool:
        return cls._loaded


class VADPreloader:
    """
    Handles VAD preloading with configurable strategy.
    """
    
    def __init__(self, preload: bool = True):
        self.preload = preload
    
    async def initialize(self):
        """Async initialization for FastAPI lifespan."""
        if self.preload:
            # VAD loading can be slow (torch hub download)
            await asyncio.to_thread(self._load_and_warmup)
    
    def _load_and_warmup(self):
        """Synchronous loading."""
        SileroVADManager.load()
        SileroVADManager.warmup()
```

**Silero VAD Loading Considerations**:

| Aspect | Recommendation |
|--------|---------------|
| First load | Can take 10-30s (download + cache) |
| Subsequent loads | Near-instant (cached) |
| Thread safety | Model inference is thread-safe |
| GPU usage | Benefits from GPU for batch processing |
| Memory | ~50MB for model weights |

---

## 5. Implementation Examples

### 5.1 Complete FastAPI ASR Service

```python
"""
Complete Production-Ready FastAPI ASR Service
Combines all patterns discussed in this document.
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
import asyncio
import threading
import time
from typing import Optional, AsyncIterator
from dataclasses import dataclass
from enum import Enum


# ============================================================================
# Configuration
# ============================================================================

@dataclass
class ASRServiceConfig:
    whisper_model: str = "base"
    whisper_device: str = "auto"
    whisper_compute_type: str = "int8"
    whisper_num_workers: int = 1
    preload_models: bool = True
    warmup_level: str = "standard"
    max_concurrent_requests: int = 5


# ============================================================================
# Model Manager
# ============================================================================

class ModelLoadState(Enum):
    NOT_LOADED = "not_loaded"
    LOADING = "loading"
    READY = "ready"
    ERROR = "error"


class ASRModelManager:
    """
    Centralized model manager with:
    - Lazy/eager loading
    - Thread-safe access
    - Health monitoring
    - Resource cleanup
    """
    
    def __init__(self, config: ASRServiceConfig):
        self.config = config
        self._whisper_model: Optional[WhisperModel] = None
        self._vad_model: Optional[torch.nn.Module] = None
        self._vad_utils: Optional[tuple] = None
        
        self._whisper_state = ModelLoadState.NOT_LOADED
        self._vad_state = ModelLoadState.NOT_LOADED
        
        self._lock = threading.Lock()
        self._infer_semaphore = asyncio.Semaphore(config.max_concurrent_requests)
        
        self._last_inference_ms: Optional[float] = None
        self._error_count: int = 0
    
    async def initialize(self):
        """Initialize models (called during startup)."""
        if self.config.preload_models:
            await self._load_all_models()
    
    async def _load_all_models(self):
        """Load all models concurrently."""
        await asyncio.gather(
            self._load_whisper(),
            self._load_vad(),
            return_exceptions=True
        )
    
    async def _load_whisper(self):
        """Load Whisper model asynchronously."""
        self._whisper_state = ModelLoadState.LOADING
        try:
            self._whisper_model = await asyncio.to_thread(
                WhisperModel,
                self.config.whisper_model,
                device=self.config.whisper_device,
                compute_type=self.config.whisper_compute_type,
                num_workers=self.config.whisper_num_workers
            )
            
            if self.config.warmup_level != "none":
                await self._warmup_whisper()
            
            self._whisper_state = ModelLoadState.READY
        except Exception as e:
            self._whisper_state = ModelLoadState.ERROR
            raise
    
    async def _load_vad(self):
        """Load VAD model asynchronously."""
        self._vad_state = ModelLoadState.LOADING
        try:
            self._vad_model, self._vad_utils = await asyncio.to_thread(
                torch.hub.load,
                "snakers4/silero-vad",
                "silero_vad",
                force_reload=False,
                onnx=False
            )
            self._vad_model.eval()
            self._vad_state = ModelLoadState.READY
        except Exception as e:
            self._vad_state = ModelLoadState.ERROR
            raise
    
    async def _warmup_whisper(self):
        """Warmup Whisper with dummy inference."""
        dummy = np.zeros(16000, dtype=np.float32)
        await asyncio.to_thread(
            lambda: list(self._whisper_model.transcribe(dummy))
        )
    
    def get_whisper(self) -> WhisperModel:
        """Get Whisper model (sync, for thread pool)."""
        if self._whisper_model is None:
            raise RuntimeError("Whisper model not loaded")
        return self._whisper_model
    
    def get_vad(self) -> Tuple[torch.nn.Module, tuple]:
        """Get VAD model and utils."""
        if self._vad_model is None:
            raise RuntimeError("VAD model not loaded")
        return self._vad_model, self._vad_utils
    
    async def transcribe_with_limits(self, audio: np.ndarray) -> list:
        """
        Transcribe with concurrency limiting.
        
        Uses semaphore to prevent resource exhaustion under load.
        """
        async with self._infer_semaphore:
            start = time.perf_counter()
            try:
                model = self.get_whisper()
                result = await asyncio.to_thread(
                    lambda: list(model.transcribe(audio))
                )
                self._last_inference_ms = (time.perf_counter() - start) * 1000
                return result
            except Exception as e:
                self._error_count += 1
                raise
    
    @property
    def is_ready(self) -> bool:
        return (
            self._whisper_state == ModelLoadState.READY and
            self._vad_state == ModelLoadState.READY
        )
    
    def get_health(self) -> dict:
        return {
            "whisper_state": self._whisper_state.value,
            "vad_state": self._vad_state.value,
            "ready": self.is_ready,
            "last_inference_ms": self._last_inference_ms,
            "error_count": self._error_count,
        }


# ============================================================================
# FastAPI Application
# ============================================================================

# Global model manager (populated during lifespan)
model_manager: Optional[ASRModelManager] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    global model_manager
    
    config = ASRServiceConfig(
        whisper_model=os.getenv("WHISPER_MODEL", "base"),
        preload_models=os.getenv("PRELOAD_MODELS", "true").lower() == "true"
    )
    
    model_manager = ASRModelManager(config)
    await model_manager.initialize()
    
    yield
    
    # Cleanup
    model_manager = None


app = FastAPI(
    title="ASR Service",
    lifespan=lifespan
)


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    if model_manager is None:
        raise HTTPException(503, detail="Service initializing")
    
    health = model_manager.get_health()
    
    if health["ready"]:
        return {"status": "healthy", **health}
    
    raise HTTPException(503, detail={"status": "not_ready", **health})


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """Transcribe audio file."""
    if not model_manager or not model_manager.is_ready:
        raise HTTPException(503, detail="Model not ready")
    
    # Read audio
    audio_bytes = await file.read()
    audio = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
    
    # Transcribe with limits
    segments = await model_manager.transcribe_with_limits(audio)
    
    return {
        "text": " ".join(s.text for s in segments),
        "segments": [
            {"text": s.text, "start": s.start, "end": s.end}
            for s in segments
        ]
    }
```

---

## 6. Trade-off Analysis

### 6.1 Loading Strategy Comparison

| Strategy | Startup Time | First Request | Memory | Best For |
|----------|-------------|---------------|--------|----------|
| **Eager** | Slow (10-30s) | Fast | Always allocated | Production real-time |
| **Lazy** | Fast | Slow (+load time) | On-demand | Development, sporadic use |
| **Hybrid** | Medium | Medium | On-demand | Auto-scaling environments |
| **Background** | Fast | Medium | Grows gradually | Graceful degradation |

### 6.2 Threading Model Comparison

| Model | Concurrency | Complexity | Use Case |
|-------|-------------|------------|----------|
| **Single Lock** | Sequential | Low | CPU inference, simple deployments |
| **Read-Write Lock** | Parallel reads | Medium | Read-heavy workloads |
| **Thread Pool** | Limited parallel | Medium | Controlled concurrency |
| **No Locks (CT2)** | Full parallel | Low | GPU with num_workers > 1 |

### 6.3 Memory Management Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| **Always Resident** | Zero load latency | Baseline memory usage |
| **LRU Eviction** | Adapts to usage patterns | Reload latency on cache miss |
| **Memory Pressure** | Automatic adaptation | Unpredictable eviction |
| **TTL Expiration** | Predictable memory | Timer overhead |

---

## 7. References

### Official Documentation

1. **FastAPI Lifespan Events**: https://fastapi.tiangolo.com/advanced/events/
2. **CTranslate2 Python API**: https://opennmt.net/CTranslate2/python/ctranslate2.models.Whisper.html
3. **Faster-Whisper GitHub**: https://github.com/SYSTRAN/faster-whisper
4. **Silero VAD**: https://github.com/snakers4/silero-vad
5. **Whisper.cpp**: https://github.com/ggerganov/whisper.cpp

### Key Issues and Discussions

1. **faster-whisper Issue #133**: Multi-worker configuration for parallel processing
2. **faster-whisper Discussion #140**: GPU utilization optimization
3. **CPython Issue #141831**: `lru_cache` thread-safety documentation

### Python Documentation

1. **functools.lru_cache**: https://docs.python.org/3/library/functools.html
2. **asyncio.to_thread**: https://docs.python.org/3/library/asyncio-task.html#asyncio.to_thread
3. **threading module**: https://docs.python.org/3/library/threading.html

---

## Appendix: Decision Flowchart

```
Choosing a Preloading Strategy:

┌─────────────────────────────────────────────────────────────┐
│ Is this a production real-time service?                     │
└─────────────────────────────────────────────────────────────┘
         │
    Yes ─┼─► Eager Loading with FastAPI Lifespan
         │
    No ──┼───┐
         │   │
         ▼   ▼
┌─────────────────────────────────────────────────────────────┐
│ Is memory constrained or usage sporadic?                    │
└─────────────────────────────────────────────────────────────┘
         │
    Yes ─┼─► Lazy Loading or LRU Cache
         │
    No ──┼─► Hybrid Loading (background with fallback)
         
Choosing Thread Safety Model:

┌─────────────────────────────────────────────────────────────┐
│ Using GPU with CTranslate2 num_workers > 1?                 │
└─────────────────────────────────────────────────────────────┘
         │
    Yes ─┼─► No locks needed (CTranslate2 handles it)
         │
    No ──┼───┐
         │   │
         ▼   ▼
┌─────────────────────────────────────────────────────────────┐
│ Need controlled concurrency with backpressure?              │
└─────────────────────────────────────────────────────────────┘
         │
    Yes ─┼─► ThreadPool with Semaphore
         │
    No ──┼─► Simple Lock
```

---

*Document Version: 1.0*  
*Last Updated: February 2026*
