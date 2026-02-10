# Concurrency Control Patterns for Python ASR Services

**Research Document**  
**Date**: 2026-02-10  
**Scope**: Best practices for limiting concurrent analysis/ASR processing in Python asyncio services

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Concurrency Control Patterns](#1-concurrency-control-patterns)
3. [Per-Provider vs Global Limits](#2-per-provider-vs-global-limits)
4. [Python Implementation Patterns](#3-python-implementation-patterns)
5. [ASR-Specific Considerations](#4-asr-specific-considerations)
6. [Current EchoPanel Implementation](#5-current-echopanel-implementation)
7. [Recommendations](#6-recommendations)

---

## Executive Summary

This document surveys concurrency control patterns for ASR (Automatic Speech Recognition) services built with Python asyncio. Key findings:

- **Semaphore-based limiting** is the most common and Pythonic approach for bounding concurrent operations
- **Token bucket algorithms** excel at rate smoothing and burst handling
- **Queue-based worker pools** provide natural backpressure but require more boilerplate
- **Circuit breakers** prevent cascade failures but are rarely used in single-tenant ASR services
- **Per-provider limits** are preferred for multi-tenant scenarios; **global limits** work for resource-constrained deployments
- **Inference serialization** (single-lock) is currently the safest pattern for local GPU/CPU ASR

---

## 1. Concurrency Control Patterns

### 1.1 Semaphore-Based Limiting (`asyncio.Semaphore`)

The most idiomatic Python approach for limiting concurrent operations.

**How it works:**
- Maintains an internal counter starting at `N` (the limit)
- `acquire()` decrements; blocks when counter reaches 0
- `release()` increments; wakes waiting coroutines

**Basic Implementation:**

```python
import asyncio

class BoundedASRProcessor:
    """ASR processor with concurrency limit via semaphore."""
    
    def __init__(self, max_concurrent: int = 3):
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self.metrics = {"active": 0, "queued": 0}
    
    async def transcribe(self, audio_stream: AsyncIterator[bytes]) -> list[str]:
        async with self.semaphore:
            self.metrics["active"] += 1
            try:
                # Actual ASR work here
                return await self._do_transcription(audio_stream)
            finally:
                self.metrics["active"] -= 1
```

**Timeout-Enabled Semaphore (Critical for ASR):**

```python
import asyncio
from contextlib import asynccontextmanager

class TimeoutSemaphore:
    """Semaphore with timeout to prevent indefinite queuing."""
    
    def __init__(self, max_concurrent: int, acquire_timeout: float = 30.0):
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self.acquire_timeout = acquire_timeout
    
    @asynccontextmanager
    async def acquire_with_timeout(self, operation_id: str = ""):
        acquired = False
        try:
            acquired = await asyncio.wait_for(
                self.semaphore.acquire(),
                timeout=self.acquire_timeout
            )
            if not acquired:
                raise asyncio.TimeoutError(
                    f"Could not acquire semaphore for {operation_id}"
                )
            yield
        finally:
            if acquired:
                self.semaphore.release()

# Usage
semaphore = TimeoutSemaphore(max_concurrent=2, acquire_timeout=10.0)

async def transcribe(audio):
    async with semaphore.acquire_with_timeout(operation_id="session_123"):
        return await run_asr(audio)
```

**Pros:**
- Simple, Pythonic API (`async with`)
- Low overhead (just counter + waiters queue)
- Built into standard library
- Works with any async context

**Cons:**
- No prioritization (FIFO only)
- No dynamic limit adjustment
- No burst handling (unlike token bucket)

**When to use:**
- Local ASR with known resource constraints
- Simple concurrency bounds (e.g., "max 2 concurrent transcriptions")
- When queue depth should be explicitly bounded

---

### 1.2 Token Bucket Algorithm

Ideal for API-based ASR providers (OpenAI Whisper API, etc.) where rate limits matter.

**How it works:**
- Bucket holds `capacity` tokens
- Tokens refill at `refill_rate` per second
- Each request consumes `tokens` (usually 1)
- Requests wait or fail if bucket empty

**Async Implementation:**

```python
import asyncio
import time
from dataclasses import dataclass
from typing import Tuple

@dataclass
class AsyncTokenBucket:
    """Async-safe token bucket for rate limiting."""
    
    capacity: float        # Maximum tokens (burst size)
    refill_rate: float     # Tokens per second
    
    def __post_init__(self):
        self.tokens = self.capacity
        self.last_refill = time.monotonic()
        self.lock = asyncio.Lock()
    
    async def consume(self, tokens: float = 1.0) -> Tuple[bool, float]:
        """
        Try to consume tokens.
        
        Returns: (allowed, wait_time)
        - allowed: True if tokens were consumed
        - wait_time: seconds to wait if not allowed (0 if allowed)
        """
        async with self.lock:
            # Refill based on elapsed time
            now = time.monotonic()
            elapsed = now - self.last_refill
            self.tokens = min(
                self.capacity,
                self.tokens + elapsed * self.refill_rate
            )
            self.last_refill = now
            
            if self.tokens >= tokens:
                self.tokens -= tokens
                return True, 0.0
            else:
                # Calculate wait time for enough tokens
                tokens_needed = tokens - self.tokens
                wait_time = tokens_needed / self.refill_rate
                return False, wait_time
    
    async def wait_and_consume(
        self, 
        tokens: float = 1.0,
        max_wait: float = 30.0
    ) -> bool:
        """Block until tokens available or max_wait exceeded."""
        allowed, wait_time = await self.consume(tokens)
        
        if allowed:
            return True
        
        if wait_time > max_wait:
            return False
        
        await asyncio.sleep(wait_time)
        allowed, _ = await self.consume(tokens)
        return allowed


class ASRRateLimiter:
    """Rate limiter for API-based ASR providers."""
    
    def __init__(self, requests_per_minute: int = 50, burst: int = 10):
        # Convert RPM to RPS
        self.bucket = AsyncTokenBucket(
            capacity=burst,
            refill_rate=requests_per_minute / 60.0
        )
        self.semaphore = asyncio.Semaphore(burst)  # Also limit concurrency
    
    async def transcribe_with_rate_limit(
        self, 
        audio: bytes,
        cost_tokens: float = 1.0
    ) -> dict:
        """
        Transcribe with both rate limiting and concurrency control.
        Uses both token bucket (rate) and semaphore (concurrency).
        """
        # First: check rate limit
        allowed, wait_time = await self.bucket.consume(cost_tokens)
        if not allowed:
            raise RateLimitExceeded(f"Rate limit exceeded. Retry after {wait_time:.1f}s")
        
        # Second: limit concurrent executions
        async with self.semaphore:
            return await call_asr_api(audio)
```

**Variable-Cost Requests:**

```python
# Different operations have different "costs"
OPERATION_COSTS = {
    "transcribe_short": 1.0,   # < 30s audio
    "transcribe_long": 5.0,    # > 30s audio  
    "diarize": 10.0,           # Speaker diarization
    "translate": 3.0,          # Translation
}

async def process_request(operation: str, audio: bytes):
    cost = OPERATION_COSTS.get(operation, 1.0)
    allowed, _ = await bucket.consume(cost)
    # ...
```

**Pros:**
- Allows controlled bursts
- Smooths traffic over time
- Natural fit for API rate limits
- Supports variable-cost operations

**Cons:**
- More complex than semaphore
- Requires ongoing token management task for precise timing
- Not ideal for local GPU inference (which needs hard concurrency limits)

**When to use:**
- Cloud ASR APIs (Whisper API, Google Speech, etc.)
- When you need to respect external rate limits
- Bursty traffic patterns that need smoothing

---

### 1.3 Queue-Based Worker Pools

Natural backpressure through bounded queues. Best for producer-consumer scenarios.

**Pattern:**

```python
import asyncio
from typing import Callable, TypeVar

T = TypeVar('T')
R = TypeVar('R')

class WorkerPool:
    """
    Fixed-size worker pool with bounded queue.
    Provides natural backpressure when queue fills.
    """
    
    def __init__(
        self, 
        worker_count: int,
        queue_size: int = 100,
        name: str = "worker_pool"
    ):
        self.queue: asyncio.Queue[tuple] = asyncio.Queue(maxsize=queue_size)
        self.workers: list[asyncio.Task] = []
        self.worker_count = worker_count
        self.name = name
        self._shutdown = False
    
    async def start(self):
        """Start worker tasks."""
        for i in range(self.worker_count):
            task = asyncio.create_task(
                self._worker_loop(i),
                name=f"{self.name}_worker_{i}"
            )
            self.workers.append(task)
    
    async def _worker_loop(self, worker_id: int):
        """Worker that processes tasks from queue."""
        while not self._shutdown:
            try:
                # Wait for work with timeout to allow shutdown checks
                task_data = await asyncio.wait_for(
                    self.queue.get(),
                    timeout=1.0
                )
                coro, future, args, kwargs = task_data
                
                try:
                    result = await coro(*args, **kwargs)
                    future.set_result(result)
                except Exception as e:
                    future.set_exception(e)
                finally:
                    self.queue.task_done()
                    
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                break
    
    async def submit(
        self, 
        coro: Callable[..., T], 
        *args,
        timeout: float = 30.0,
        **kwargs
    ) -> T:
        """
        Submit work to pool.
        
        Raises:
            asyncio.QueueFull: If queue is at capacity (backpressure)
            asyncio.TimeoutError: If task doesn't complete in time
        """
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        
        # put_nowait raises QueueFull if queue is full (backpressure)
        self.queue.put_nowait((coro, future, args, kwargs))
        
        return await asyncio.wait_for(future, timeout=timeout)
    
    async def submit_wait(
        self,
        coro: Callable[..., T],
        *args,
        **kwargs
    ) -> T:
        """Submit work, waiting if queue is full."""
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        
        # put waits if queue is full
        await self.queue.put((coro, future, args, kwargs))
        
        return await future
    
    async def shutdown(self, wait: bool = True):
        """Graceful shutdown."""
        self._shutdown = True
        
        if wait:
            await self.queue.join()  # Wait for all tasks to complete
        
        for worker in self.workers:
            worker.cancel()
        
        await asyncio.gather(*self.workers, return_exceptions=True)


# ASR-specific usage
class ASRWorkerPool:
    """Worker pool for ASR processing with prioritization support."""
    
    def __init__(self, max_workers: int = 2, max_queue: int = 10):
        # Use PriorityQueue for urgent transcriptions
        self.queue: asyncio.PriorityQueue = asyncio.PriorityQueue(maxsize=max_queue)
        self.max_workers = max_workers
        self.workers: list[asyncio.Task] = []
        self.active_tasks: dict[str, asyncio.Task] = {}
    
    async def transcribe(
        self,
        session_id: str,
        audio: bytes,
        priority: int = 5,  # Lower = higher priority
        timeout: float = 30.0
    ) -> str:
        """
        Submit transcription request.
        
        Priority levels:
        1-2: Real-time streaming (highest)
        3-5: Interactive requests
        6-9: Batch processing
        10: Background tasks
        """
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        
        # (priority, sequence, future, audio)
        # sequence ensures FIFO for same priority
        item = (priority, time.monotonic(), future, audio)
        
        await self.queue.put(item)
        
        return await asyncio.wait_for(future, timeout=timeout)
```

**Pros:**
- Natural backpressure (QueueFull exception)
- Decouples producers from consumers
- Supports prioritization (PriorityQueue)
- Clean shutdown semantics (queue.join())

**Cons:**
- More boilerplate code
- Requires careful worker lifecycle management
- Task results need Future objects for return values

**When to use:**
- Complex pipelines with multiple stages
- When you need prioritization
- Producer-consumer scenarios
- Long-running services with graceful shutdown requirements

---

### 1.4 Circuit Breakers (Fail-Fast When Overloaded)

Prevents cascade failures by rejecting requests when downstream is unhealthy.

**States:**
- **CLOSED**: Normal operation, requests pass through
- **OPEN**: Failure threshold exceeded, requests fail fast
- **HALF_OPEN**: Testing if downstream recovered

**Implementation:**

```python
import asyncio
import time
from enum import Enum, auto
from typing import Callable, Optional

class CircuitState(Enum):
    CLOSED = auto()      # Normal operation
    OPEN = auto()        # Failing fast
    HALF_OPEN = auto()   # Testing recovery

class CircuitBreaker:
    """
    Circuit breaker for ASR providers.
    Prevents overwhelming failing services.
    """
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 30.0,
        half_open_max_calls: int = 3,
        expected_exception: type = Exception
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls
        self.expected_exception = expected_exception
        
        self.state = CircuitState.CLOSED
        self.failures = 0
        self.last_failure_time: Optional[float] = None
        self.half_open_calls = 0
        self.lock = asyncio.Lock()
    
    async def call(self, coro: Callable, *args, **kwargs):
        """Execute coro with circuit breaker protection."""
        async with self.lock:
            if self.state == CircuitState.OPEN:
                if time.monotonic() - self.last_failure_time >= self.recovery_timeout:
                    self.state = CircuitState.HALF_OPEN
                    self.half_open_calls = 0
                else:
                    raise CircuitBreakerOpen("Circuit breaker is OPEN")
            
            if self.state == CircuitState.HALF_OPEN:
                if self.half_open_calls >= self.half_open_max_calls:
                    raise CircuitBreakerOpen("Circuit breaker is HALF_OPEN (max calls reached)")
                self.half_open_calls += 1
        
        # Execute outside lock
        try:
            result = await coro(*args, **kwargs)
            await self._on_success()
            return result
        except self.expected_exception as e:
            await self._on_failure()
            raise
    
    async def _on_success(self):
        async with self.lock:
            if self.state == CircuitState.HALF_OPEN:
                self.state = CircuitState.CLOSED
                self.failures = 0
                self.half_open_calls = 0
            else:
                self.failures = max(0, self.failures - 1)
    
    async def _on_failure(self):
        async with self.lock:
            self.failures += 1
            self.last_failure_time = time.monotonic()
            
            if self.failures >= self.failure_threshold:
                self.state = CircuitState.OPEN
    
    @property
    def is_closed(self) -> bool:
        return self.state == CircuitState.CLOSED


# ASR Provider with circuit breaker
class ResilientASRProvider:
    """ASR provider wrapped with circuit breaker."""
    
    def __init__(self, provider: ASRProvider):
        self.provider = provider
        self.circuit = CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=30.0,
            expected_exception=(ASRError, asyncio.TimeoutError)
        )
    
    async def transcribe(self, audio: bytes) -> str:
        return await self.circuit.call(
            self.provider.transcribe,
            audio
        )
```

**Pros:**
- Prevents cascade failures
- Fast failure when downstream unhealthy
- Automatic recovery detection
- Protects resources from being wasted on doomed requests

**Cons:**
- Adds complexity
- Requires tuning thresholds
- Not typically needed for single-tenant local ASR

**When to use:**
- Cloud ASR APIs that can fail or throttle
- Multi-provider failover scenarios
- Services with multiple downstream dependencies

---

## 2. Per-Provider vs Global Limits

### 2.1 Decision Framework

| Scenario | Recommended Limit | Rationale |
|----------|------------------|-----------|
| Single local ASR (faster-whisper) | Global | Single resource pool |
| Multiple cloud providers | Per-provider + Global | Isolation + overall protection |
| Multi-tenant (per-user) | Per-user | Fairness, prevents one user monopolizing |
| Mixed local + cloud | Per-provider type | Different constraints |

### 2.2 Per-Provider Limits

Use when providers have different constraints:

```python
class ProviderLimits:
    """Resource limits per provider type."""
    
    def __init__(self):
        # Local GPU inference: limited by VRAM
        self.local = asyncio.Semaphore(1)
        
        # Cloud API: limited by rate limits
        self.cloud_api = AsyncTokenBucket(
            capacity=50,      # burst
            refill_rate=1.0   # per second
        )
        
        # Edge/on-device: limited by CPU
        self.edge = asyncio.Semaphore(2)

class MultiProviderASR:
    """ASR that routes to different providers with separate limits."""
    
    def __init__(self):
        self.limits = ProviderLimits()
        self.providers = {
            "local": LocalWhisperProvider(),
            "cloud": CloudWhisperProvider(),
            "edge": EdgeWhisperProvider(),
        }
    
    async def transcribe(
        self,
        audio: bytes,
        provider: str = "local"
    ) -> str:
        p = self.providers[provider]
        
        if provider == "local":
            async with self.limits.local:
                return await p.transcribe(audio)
        
        elif provider == "cloud":
            await self.limits.cloud_api.wait_and_consume()
            return await p.transcribe(audio)
        
        elif provider == "edge":
            async with self.limits.edge:
                return await p.transcribe(audio)
```

### 2.3 Resource-Aware Limiting

Dynamic limits based on system load:

```python
import psutil
import asyncio

class AdaptiveConcurrencyLimiter:
    """
    Adjusts concurrency limits based on system resources.
    """
    
    def __init__(
        self,
        min_concurrent: int = 1,
        max_concurrent: int = 4,
        cpu_threshold: float = 80.0,
        memory_threshold: float = 85.0
    ):
        self.min_concurrent = min_concurrent
        self.max_concurrent = max_concurrent
        self.cpu_threshold = cpu_threshold
        self.memory_threshold = memory_threshold
        
        self.current_limit = max_concurrent
        self.semaphore = asyncio.Semaphore(self.current_limit)
        self.monitor_task: Optional[asyncio.Task] = None
    
    async def start_monitoring(self, interval: float = 5.0):
        """Start background monitoring task."""
        self.monitor_task = asyncio.create_task(
            self._monitor_loop(interval)
        )
    
    async def _monitor_loop(self, interval: float):
        """Adjust limits based on system load."""
        while True:
            await asyncio.sleep(interval)
            
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            
            # Reduce limits if overloaded
            if cpu_percent > self.cpu_threshold or memory.percent > self.memory_threshold:
                if self.current_limit > self.min_concurrent:
                    self.current_limit -= 1
                    # Note: Can't shrink semaphore, would need reconstruction
                    # In practice, you'd use a more sophisticated pattern
                    logger.warning(f"Reducing concurrency to {self.current_limit}")
            
            # Increase limits if underutilized
            elif cpu_percent < self.cpu_threshold * 0.5 and memory.percent < self.memory_threshold * 0.5:
                if self.current_limit < self.max_concurrent:
                    self.current_limit += 1
                    logger.info(f"Increasing concurrency to {self.current_limit}")
    
    async def acquire(self):
        """Acquire with current limit."""
        # Implementation would track active count and enforce current_limit
        pass
```

### 2.4 GPU Memory-Aware Limiting

For GPU-based ASR, monitor VRAM:

```python
import torch

class GPUMemoryLimiter:
    """
    Limits concurrent inference based on available GPU memory.
    Essential for multi-stream ASR on shared GPU.
    """
    
    def __init__(
        self,
        device: str = "cuda",
        memory_buffer_gb: float = 1.0,  # Leave this much free
        max_streams: int = 4
    ):
        self.device = device
        self.memory_buffer = memory_buffer_gb * (1024 ** 3)  # Convert to bytes
        self.max_streams = max_streams
        self.active_streams = 0
        self.lock = asyncio.Lock()
    
    def _get_free_memory(self) -> int:
        """Get free GPU memory in bytes."""
        if self.device == "cuda" and torch.cuda.is_available():
            return torch.cuda.mem_get_info(self.device)[0]
        return float('inf')  # No limit for CPU
    
    async def can_start_stream(self, estimated_memory_gb: float) -> bool:
        """Check if new stream can be started."""
        async with self.lock:
            if self.active_streams >= self.max_streams:
                return False
            
            free_memory = self._get_free_memory()
            required_memory = estimated_memory_gb * (1024 ** 3)
            
            return free_memory - required_memory > self.memory_buffer
    
    async def start_stream(self) -> "GPUStreamContext":
        """Context manager for GPU stream."""
        async with self.lock:
            self.active_streams += 1
        
        return GPUStreamContext(self)
    
    async def end_stream(self):
        """Signal stream completion."""
        async with self.lock:
            self.active_streams = max(0, self.active_streams - 1)
```

---

## 3. Python Implementation Patterns

### 3.1 Semaphore with Timeout Handling

```python
import asyncio
from contextlib import asynccontextmanager
from typing import Optional

class TimedSemaphore:
    """
    Semaphore with timeout and optional priority handling.
    """
    
    def __init__(
        self,
        max_value: int,
        default_timeout: float = 30.0,
        on_timeout: Optional[Callable] = None
    ):
        self.semaphore = asyncio.Semaphore(max_value)
        self.default_timeout = default_timeout
        self.on_timeout = on_timeout
        self.metrics = {
            "acquired": 0,
            "timed_out": 0,
            "waiting": 0
        }
    
    @asynccontextmanager
    async def acquire(
        self,
        timeout: Optional[float] = None,
        operation_id: str = ""
    ):
        timeout = timeout or self.default_timeout
        acquired = False
        
        self.metrics["waiting"] += 1
        try:
            acquired = await asyncio.wait_for(
                self.semaphore.acquire(),
                timeout=timeout
            )
            
            if not acquired:
                self.metrics["timed_out"] += 1
                if self.on_timeout:
                    await self.on_timeout(operation_id)
                raise asyncio.TimeoutError(
                    f"Failed to acquire semaphore within {timeout}s"
                )
            
            self.metrics["acquired"] += 1
            yield
            
        finally:
            self.metrics["waiting"] -= 1
            if acquired:
                self.semaphore.release()
```

### 3.2 Queue with Worker Pattern

```python
import asyncio
from dataclasses import dataclass
from typing import Any, Callable, Coroutine

@dataclass
class Task:
    id: str
    priority: int
    coro: Coroutine
    future: asyncio.Future
    created_at: float

class PriorityWorkerPool:
    """
    Worker pool with priority queue and backpressure.
    """
    
    def __init__(
        self,
        num_workers: int,
        max_queue_size: int = 100,
        task_timeout: float = 60.0
    ):
        self.queue: asyncio.PriorityQueue[Tuple[int, Task]] = asyncio.PriorityQueue(
            maxsize=max_queue_size
        )
        self.num_workers = num_workers
        self.task_timeout = task_timeout
        self.workers: list[asyncio.Task] = []
        self.running = False
        self._seq = 0  # For FIFO within same priority
    
    async def start(self):
        """Start worker tasks."""
        self.running = True
        for i in range(self.num_workers):
            worker = asyncio.create_task(
                self._worker_loop(i),
                name=f"worker_{i}"
            )
            self.workers.append(worker)
    
    async def _worker_loop(self, worker_id: int):
        """Process tasks from queue."""
        while self.running:
            try:
                priority, task = await asyncio.wait_for(
                    self.queue.get(),
                    timeout=1.0
                )
                
                try:
                    result = await asyncio.wait_for(
                        task.coro,
                        timeout=self.task_timeout
                    )
                    task.future.set_result(result)
                except asyncio.TimeoutError:
                    task.future.set_exception(
                        asyncio.TimeoutError(f"Task {task.id} timed out")
                    )
                except Exception as e:
                    task.future.set_exception(e)
                finally:
                    self.queue.task_done()
                    
            except asyncio.TimeoutError:
                continue
    
    async def submit(
        self,
        coro: Coroutine,
        task_id: str = "",
        priority: int = 5,
        block: bool = True
    ) -> Any:
        """
        Submit task to pool.
        
        Args:
            coro: Coroutine to execute
            task_id: Optional task identifier
            priority: Lower = higher priority (1-10)
            block: If True, wait for queue space; if False, raise QueueFull
        
        Returns:
            Task result
        
        Raises:
            asyncio.QueueFull: If queue full and block=False
            asyncio.TimeoutError: If task times out
        """
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        
        self._seq += 1
        task = Task(
            id=task_id or f"task_{self._seq}",
            priority=priority,
            coro=coro,
            future=future,
            created_at=asyncio.get_event_loop().time()
        )
        
        if block:
            await self.queue.put((priority, task))
        else:
            self.queue.put_nowait((priority, task))
        
        return await future
    
    async def shutdown(self, wait: bool = True):
        """Graceful shutdown."""
        self.running = False
        
        if wait:
            await self.queue.join()
        
        for worker in self.workers:
            worker.cancel()
        
        await asyncio.gather(*self.workers, return_exceptions=True)
```

### 3.3 Backpressure Propagation

Backpressure should flow from slowest to fastest component:

```python
class BackpressurePipeline:
    """
    Pipeline stage with backpressure handling.
    Each stage pulls from previous, applies backpressure naturally.
    """
    
    def __init__(
        self,
        input_queue: asyncio.Queue,
        output_queue: asyncio.Queue,
        processor: Callable,
        max_pending: int = 5
    ):
        self.input = input_queue
        self.output = output_queue
        self.processor = processor
        self.max_pending = max_pending
        self.pending = 0
        self.lock = asyncio.Lock()
    
    async def run(self):
        """Process items from input to output."""
        while True:
            item = await self.input.get()
            
            if item is None:  # Shutdown sentinel
                await self.output.put(None)
                return
            
            # Apply backpressure: wait if output queue filling
            while self.output.qsize() >= self.max_pending:
                await asyncio.sleep(0.01)  # Small backoff
            
            result = await self.processor(item)
            await self.output.put(result)
```

---

## 4. ASR-Specific Considerations

### 4.1 Single Inference Lock (Current Faster-Whisper Pattern)

The current EchoPanel implementation uses a threading lock for model inference:

```python
class FasterWhisperProvider:
    def __init__(self, config: ASRConfig):
        self._infer_lock = threading.Lock()
    
    async def transcribe_stream(self, pcm_stream, ...):
        async for chunk in pcm_stream:
            def _transcribe():
                with self._infer_lock:  # Serialize inference
                    segments, info = model.transcribe(audio, ...)
                return list(segments), info
            
            segments, info = await asyncio.to_thread(_transcribe)
```

**Why this pattern:**
- CTranslate2 (backend for faster-whisper) has internal threading
- Multiple concurrent calls can cause race conditions
- GPU memory is often the bottleneck, not CPU

**Trade-offs:**
| Pros | Cons |
|------|------|
| Prevents model corruption | No concurrent inference on multi-GPU |
| Simple and safe | Underutilizes GPU for large batches |
| Deterministic | Adds queuing latency |

### 4.2 Multi-Stream Handling (Mic + System Audio)

For dual-pipeline (microphone + system audio) ASR:

```python
class DualStreamASR:
    """
    Handle multiple concurrent audio streams with shared resource limits.
    """
    
    def __init__(self):
        # One inference lock for the model
        self.inference_lock = asyncio.Lock()
        
        # Per-source queues with different priorities
        self.mic_queue: asyncio.Queue = asyncio.PriorityQueue(maxsize=50)
        self.system_queue: asyncio.Queue = asyncio.PriorityQueue(maxsize=100)
        
        # Mic gets priority (lower number = higher priority)
        self.mic_priority = 1
        self.system_priority = 2
    
    async def process_mic_stream(self, audio_chunks):
        """Process microphone audio with high priority."""
        async for chunk in audio_chunks:
            await self.mic_queue.put((self.mic_priority, chunk))
    
    async def process_system_stream(self, audio_chunks):
        """Process system audio with lower priority."""
        async for chunk in audio_chunks:
            await self.system_queue.put((self.system_priority, chunk))
    
    async def _inference_loop(self):
        """Single inference loop that pulls from both queues."""
        while True:
            # Try mic queue first (priority)
            try:
                _, chunk = self.mic_queue.get_nowait()
                source = "mic"
            except asyncio.QueueEmpty:
                try:
                    _, chunk = self.system_queue.get_nowait()
                    source = "system"
                except asyncio.QueueEmpty:
                    await asyncio.sleep(0.001)
                    continue
            
            async with self.inference_lock:
                result = await self._transcribe(chunk)
                await self._emit_result(result, source)
```

### 4.3 Chunk-Level vs Session-Level Limiting

| Level | Description | Use Case |
|-------|-------------|----------|
| **Session** | Limit concurrent transcription sessions | Multi-user services |
| **Chunk** | Limit concurrent chunk processing within a session | Streaming ASR |
| **Global** | Limit total concurrent chunks across all sessions | Resource protection |

**Session-Level Limiting:**

```python
class SessionManager:
    def __init__(self, max_sessions: int = 10):
        self.session_semaphore = asyncio.Semaphore(max_sessions)
        self.active_sessions: dict[str, SessionState] = {}
    
    async def create_session(self, session_id: str) -> SessionState:
        async with self.session_semaphore:
            session = SessionState(session_id)
            self.active_sessions[session_id] = session
            return session
```

**Chunk-Level with Stream Prioritization:**

```python
class ChunkLimiter:
    """
    Limit concurrent chunk processing with priority-based preemption.
    """
    
    def __init__(
        self,
        max_concurrent_chunks: int = 2,
        high_priority_preempt: bool = True
    ):
        self.semaphore = asyncio.Semaphore(max_concurrent_chunks)
        self.high_priority_preempt = high_priority_preempt
        self.active_chunks: dict[str, dict] = {}
    
    async def process_chunk(
        self,
        chunk: bytes,
        stream_id: str,
        priority: int = 5
    ) -> str:
        """
        Process chunk, potentially preempting lower priority work.
        """
        # For high priority with preemption enabled
        if priority <= 2 and self.high_priority_preempt:
            # Find and cancel lowest priority active chunk
            lowest_priority = min(
                self.active_chunks.items(),
                key=lambda x: x[1]["priority"],
                default=None
            )
            if lowest_priority and lowest_priority[1]["priority"] > priority:
                # Cancel and free slot
                lowest_priority[1]["task"].cancel()
        
        async with self.semaphore:
            task = asyncio.current_task()
            self.active_chunks[stream_id] = {
                "task": task,
                "priority": priority,
                "started": time.monotonic()
            }
            try:
                return await self._transcribe_chunk(chunk)
            finally:
                del self.active_chunks[stream_id]
```

---

## 5. Current EchoPanel Implementation

### 5.1 Existing Patterns

From code review of `server/services/provider_faster_whisper.py`:

```python
class FasterWhisperProvider(ASRProvider):
    def __init__(self, config: ASRConfig):
        self._infer_lock = threading.Lock()  # Single inference lock
    
    async def transcribe_stream(...):
        async for chunk in pcm_stream:
            def _transcribe():
                with self._infer_lock:  # Serializes model access
                    segments, info = model.transcribe(audio, ...)
                return list(segments), info
            
            # Run in thread pool to not block event loop
            segments, info = await asyncio.to_thread(_transcribe)
```

From `server/api/ws_live_listener.py`:

```python
# Per-source bounded queues
state.queues: Dict[str, asyncio.Queue] = field(default_factory=dict)

# Queue creation with maxsize
state.queues[source] = asyncio.Queue(maxsize=QUEUE_MAX)  # default 48

# Backpressure: drop oldest when full
try:
    q.put_nowait(chunk)
except asyncio.QueueFull:
    _ = q.get_nowait()  # Drop oldest
    q.put_nowait(chunk)
    state.dropped_frames += 1
```

### 5.2 Identified Gaps

1. **No analysis task limiting** (Fixed in PR3)
   ```python
   # Before: Fire-and-forget
   state.analysis_tasks.append(asyncio.create_task(_analysis_loop(...)))
   
   # After: Should use semaphore
   analysis_semaphore = asyncio.Semaphore(1)
   ```

2. **No timeout on queue operations**
   - Current code can block indefinitely on `await queue.get()`

3. **No prioritization between sources**
   - Mic and system audio treated equally
   - Should prioritize mic for user experience

4. **No metrics on queue depth/utilization**
   - Hard to tune limits without data

---

## 6. Recommendations

### 6.1 Immediate (High Impact, Low Effort)

1. **Add analysis task semaphore** (already in audit recommendations)
   ```python
   class SessionState:
       analysis_semaphore: asyncio.Semaphore = field(
           default_factory=lambda: asyncio.Semaphore(1)
       )
   ```

2. **Add queue timeout handling**
   ```python
   try:
       chunk = await asyncio.wait_for(queue.get(), timeout=5.0)
   except asyncio.TimeoutError:
       logger.warning(f"Queue timeout for {source}")
       continue
   ```

3. **Add queue metrics**
   ```python
   metrics = {
       "queue_depth": queue.qsize(),
       "queue_max": queue.maxsize,
       "fill_ratio": queue.qsize() / queue.maxsize,
       "dropped_frames": state.dropped_frames
   }
   ```

### 6.2 Short-Term (Medium Effort)

1. **Implement priority queue for multi-source**
   - Mic priority = 1, System priority = 2
   - Process higher priority chunks first during backpressure

2. **Add adaptive chunk sizing**
   ```python
   if queue_fill_ratio > 0.8:
       # Increase chunk size to reduce inference frequency
       chunk_seconds = min(chunk_seconds * 1.5, 4.0)
   ```

3. **Implement per-session limits**
   - Prevent one session from monopolizing resources
   - Especially important if supporting multiple concurrent sessions

### 6.3 Long-Term (Higher Effort)

1. **GPU memory-aware scheduling**
   - Monitor VRAM before starting new streams
   - Queue streams when GPU memory constrained

2. **Circuit breaker for cloud providers**
   - If using cloud ASR APIs
   - Fail fast when provider is unhealthy

3. **Distributed rate limiting**
   - Redis-backed token bucket for multi-instance deployments

---

## 7. Code Examples Summary

### Complete ASR Concurrency Controller

```python
import asyncio
import time
from dataclasses import dataclass, field
from typing import Optional, AsyncIterator
import logging

logger = logging.getLogger(__name__)

@dataclass
class ASRConcurrencyConfig:
    """Configuration for ASR concurrency control."""
    # Global limits
    max_concurrent_sessions: int = 10
    max_concurrent_chunks: int = 2
    
    # Per-source limits
    max_mic_streams: int = 1
    max_system_streams: int = 2
    
    # Queue settings
    queue_max_size: int = 48
    queue_timeout: float = 5.0
    
    # Priority levels (lower = higher priority)
    mic_priority: int = 1
    system_priority: int = 2
    
    # Backpressure
    drop_oldest_on_full: bool = True
    adaptive_chunk_sizing: bool = True


class ASRConcurrencyController:
    """
    Comprehensive concurrency control for ASR services.
    Combines multiple patterns: semaphore, queue, priority.
    """
    
    def __init__(self, config: Optional[ASRConcurrencyConfig] = None):
        self.config = config or ASRConcurrencyConfig()
        
        # Global session limit
        self.session_sem = asyncio.Semaphore(
            self.config.max_concurrent_sessions
        )
        
        # Chunk processing limit (serialization for local ASR)
        self.chunk_sem = asyncio.Semaphore(
            self.config.max_concurrent_chunks
        )
        
        # Per-source queues with priority
        self.mic_queue: asyncio.PriorityQueue = asyncio.PriorityQueue(
            maxsize=self.config.queue_max_size
        )
        self.system_queue: asyncio.PriorityQueue = asyncio.PriorityQueue(
            maxsize=self.config.queue_max_size
        )
        
        # Metrics
        self.metrics = {
            "sessions_active": 0,
            "chunks_processed": 0,
            "chunks_dropped": 0,
            "queue_wait_ms": []
        }
    
    async def acquire_session(self, timeout: float = 10.0) -> bool:
        """Acquire session slot."""
        try:
            await asyncio.wait_for(
                self.session_sem.acquire(),
                timeout=timeout
            )
            self.metrics["sessions_active"] += 1
            return True
        except asyncio.TimeoutError:
            logger.warning("Session acquisition timeout")
            return False
    
    def release_session(self):
        """Release session slot."""
        self.session_sem.release()
        self.metrics["sessions_active"] -= 1
    
    async def enqueue_audio(
        self,
        audio_chunk: bytes,
        source: str = "system",
        sequence: int = 0
    ) -> bool:
        """
        Enqueue audio chunk with backpressure.
        
        Returns:
            True if enqueued, False if dropped
        """
        priority = (
            self.config.mic_priority 
            if source == "mic" 
            else self.config.system_priority
        )
        
        queue = self.mic_queue if source == "mic" else self.system_queue
        
        try:
            # (priority, sequence, timestamp, data)
            queue.put_nowait((
                priority,
                sequence,
                time.monotonic(),
                audio_chunk
            ))
            return True
            
        except asyncio.QueueFull:
            if self.config.drop_oldest_on_full:
                # Drop oldest
                try:
                    dropped = queue.get_nowait()
                    self.metrics["chunks_dropped"] += 1
                    logger.debug(f"Dropped chunk, queue full for {source}")
                    
                    # Put new chunk
                    queue.put_nowait((
                        priority,
                        sequence,
                        time.monotonic(),
                        audio_chunk
                    ))
                    return True
                except asyncio.QueueEmpty:
                    pass
            
            self.metrics["chunks_dropped"] += 1
            return False
    
    async def process_next_chunk(
        self,
        transcribe_fn: callable,
        timeout: float = 5.0
    ) -> Optional[dict]:
        """
        Process next chunk from highest priority queue.
        
        Returns:
            Transcription result or None if timeout
        """
        chunk = None
        source = None
        
        # Try mic queue first (higher priority)
        try:
            priority, seq, enqueued_at, chunk = self.mic_queue.get_nowait()
            source = "mic"
            self.mic_queue.task_done()
        except asyncio.QueueEmpty:
            # Try system queue
            try:
                priority, seq, enqueued_at, chunk = self.system_queue.get_nowait()
                source = "system"
                self.system_queue.task_done()
            except asyncio.QueueEmpty:
                return None
        
        # Record queue wait time
        wait_time = (time.monotonic() - enqueued_at) * 1000
        self.metrics["queue_wait_ms"].append(wait_time)
        
        # Process with concurrency limit
        async with self.chunk_sem:
            result = await asyncio.wait_for(
                transcribe_fn(chunk, source),
                timeout=timeout
            )
            self.metrics["chunks_processed"] += 1
            return result
    
    def get_metrics(self) -> dict:
        """Get current metrics."""
        avg_wait = (
            sum(self.metrics["queue_wait_ms"][-100:]) / 
            min(100, len(self.metrics["queue_wait_ms"]))
            if self.metrics["queue_wait_ms"]
            else 0
        )
        
        return {
            "sessions_active": self.metrics["sessions_active"],
            "chunks_processed": self.metrics["chunks_processed"],
            "chunks_dropped": self.metrics["chunks_dropped"],
            "queue_mic_depth": self.mic_queue.qsize(),
            "queue_system_depth": self.system_queue.qsize(),
            "avg_queue_wait_ms": round(avg_wait, 2),
            "chunk_sem_value": self.chunk_sem._value,
        }
```

---

## References

1. Python asyncio documentation: https://docs.python.org/3/library/asyncio-sync.html
2. "Mastering Asyncio Semaphores" - Medium (2024)
3. Token bucket implementation patterns - OneUptime (2026)
4. "7 AsyncIO Patterns for Concurrency-Friendly Python" - Hash Block (2025)
5. OpenAI Community: Best strategy for managing concurrent Whisper calls
6. StackOverflow: How to limit concurrency with Python asyncio

---

**Document Status**: Research Complete  
**Next Steps**: Implementation planning for identified recommendations
