# Research Synthesis: PR4-PR6 + ASR Provider Improvements

**Date**: 2026-02-11  
**Scope**: Model Preloading, Concurrency Limiting, Reconnect Resilience, ASR Provider Architecture  
**Status**: Research Complete → Ready for Implementation Planning

---

## Executive Summary

Four research documents were produced analyzing best practices for EchoPanel's next phase of improvements:

| Document | Focus | Key Finding |
|----------|-------|-------------|
| `ASR_MODEL_PRELOADING_PATTERNS.md` | Model residency & warming | Hybrid eager/lazy loading with warmup is optimal |
| `ASR_CONCURRENCY_PATTERNS_RESEARCH.md` | Concurrent processing limits | Semaphore + priority queues per source |
| `WEBSOCKET_RECONNECTION_RESILIENCE_RESEARCH.md` | Reconnect resilience | Exponential backoff + circuit breaker + message buffering |
| `whisper_cpp_integration_research.md` | New ASR provider | pywhispercpp with Metal is 3-5× faster on Apple Silicon |

---

## 1. PR4: Model Preloading (Keep ASR Warm)

### Current State (Problems)
- **faster-whisper**: 2-5s cold start on first chunk (lazy loading)
- **voxtral**: 11s model load per chunk (subprocess-per-chunk pattern)
- **No warmup**: First user pays the load penalty
- **No health verification**: Can't distinguish "starting" from "ready"

### Research Findings: Optimal Approach

**Recommended Pattern**: Hybrid Eager + Lazy with Tiered Warmup

```python
class ModelPreloader:
    """
    Three-state model lifecycle:
    STARTUP → WARMING_UP → READY
    
    - Load model at server startup (eager)
    - Run dummy inference to warm caches (warmup)
    - Health check verifies actual readiness
    """
    
    async def initialize(self):
        # Phase 1: Load model (blocking, in thread)
        self._model = await asyncio.to_thread(self._load_model)
        
        # Phase 2: Warmup (dummy inference)
        await asyncio.to_thread(self._warmup, self._model)
        
        # Phase 3: Mark ready
        self._state = ModelState.READY
```

**Implementation Options Compared**:

| Approach | Cold Start | Memory | Complexity | Best For |
|----------|-----------|--------|------------|----------|
| Lazy (current) | 2-5s | Low | Low | Dev/test |
| Eager + Warmup | <100ms | Medium | Medium | **Production** |
| Always-resident | 0ms | High | Low | High-traffic |
| LRU cache | Variable | Configurable | High | Multi-model |

**Recommended for EchoPanel**:

1. **Server startup loading** (eager)
   - Load model when FastAPI starts, not on first request
   - Block startup until loaded (fail fast if broken)

2. **Tiered warmup** (3 levels)
   - Level 1: Model load (5s)
   - Level 2: Single inference (1s) - warms caches
   - Level 3: Full warmup (5s) - optional, for benchmarking

3. **Deep health checks**
   - `/health` returns `{"status": "ready", "model_loaded": true}`
   - Verify model can actually produce output

4. **Voxtral fix: Streaming mode** (critical)
   - Current: Spawns subprocess per chunk → 11s load each time
   - Fix: Use `voxtral --stdin -I 0.5` streaming mode
   - Keep process resident, pipe audio via stdin

### Implementation Sketch

```python
# server/services/model_preloader.py
class ASRModelManager:
    """Manages ASR model lifecycle: load → warmup → ready."""
    
    def __init__(self, config: ASRConfig):
        self.config = config
        self._model = None
        self._state = ModelState.UNINITIALIZED
        self._lock = asyncio.Lock()
    
    async def initialize(self) -> bool:
        """Eager initialization with warmup. Called at server startup."""
        async with self._lock:
            if self._state != ModelState.UNINITIALIZED:
                return True
            
            self._state = ModelState.LOADING
            
            # Load model in thread (blocks)
            self._model = await asyncio.to_thread(
                self._load_model, self.config
            )
            
            # Warmup: dummy inference (ensures caches hot)
            await asyncio.to_thread(self._warmup, self._model)
            
            self._state = ModelState.READY
            return True
    
    def health(self) -> ModelHealth:
        """Deep health check - verifies model is actually working."""
        return ModelHealth(
            state=self._state,
            model_loaded=self._model is not None,
            last_error=self._last_error,
        )
```

### Effort Estimate
- **faster-whisper warmup**: 2-3 hours
- **Voxtral streaming fix**: 6-8 hours (architectural change)
- **Health check integration**: 2 hours
- **Total**: 10-13 hours

---

## 2. PR5: Analysis Concurrency Limiting

### Current State (Problems)
- **No explicit limits**: Can spawn unlimited analysis tasks
- **Single inference lock**: faster-whisper serializes anyway, but not enforced at session level
- **No backpressure**: Queue fills silently, then drops
- **No priority**: Mic and system audio compete equally

### Research Findings: Optimal Approach

**Recommended Pattern**: Semaphore + Priority Queues per Source

```python
class ASRConcurrencyController:
    """
    Multi-level concurrency control:
    1. Global session limit (max concurrent sessions)
    2. Per-source chunk queues (bounded, with priority)
    3. Inference semaphore (max concurrent ASR calls)
    """
    
    def __init__(self, config: ConcurrencyConfig):
        # Global limits
        self._session_semaphore = asyncio.Semaphore(config.max_sessions)
        self._infer_semaphore = asyncio.Semaphore(config.max_concurrent_inference)
        
        # Per-source queues (bounded for natural backpressure)
        self._queues = {
            "mic": asyncio.PriorityQueue(maxsize=config.queue_size),
            "system": asyncio.PriorityQueue(maxsize=config.queue_size),
        }
```

**Architecture Comparison**:

| Pattern | Pros | Cons | Use Case |
|---------|------|------|----------|
| **Semaphore** | Simple, low overhead | No prioritization | Single-source |
| **Token Bucket** | Burst handling | Complex | Rate limiting |
| **Priority Queue** | Source prioritization | Higher overhead | **Multi-source (best)** |
| **Circuit Breaker** | Fail-fast | Requires tuning | Cloud providers |

**Recommended for EchoPanel**:

1. **Global session semaphore** (5-10 concurrent sessions)
   - Prevents resource exhaustion
   - Fast fail with clear error message

2. **Per-source bounded queues** (mic: 100, system: 50)
   - Natural backpressure (QueueFull exception)
   - Different limits per source priority

3. **Priority processing** (mic > system)
   - User's own voice more important
   - System audio can drop more aggressively

4. **Adaptive chunk sizing**
   - Normal: 2s chunks (fast response)
   - Under load: 4s chunks (batch more, less overhead)
   - Critical: 8s chunks (survival mode)

### Implementation Sketch

```python
# server/services/concurrency_controller.py
class ConcurrencyController:
    """Manages ASR concurrency with backpressure."""
    
    def __init__(self):
        # Global limits
        self._max_sessions = 10
        self._max_inference = 2  # faster-whisper lock anyway
        
        # Per-source bounded queues
        self._queues: Dict[str, asyncio.Queue] = {
            "mic": asyncio.Queue(maxsize=100),
            "system": asyncio.Queue(maxsize=50),
        }
    
    async def submit_chunk(
        self, 
        chunk: AudioChunk, 
        source: str
    ) -> bool:
        """
        Submit chunk for processing.
        Returns False if queue full (caller should drop).
        """
        queue = self._queues[source]
        
        try:
            # Non-blocking put with timeout
            await asyncio.wait_for(
                queue.put(chunk),
                timeout=0.1
            )
            return True
        except (asyncio.QueueFull, asyncio.TimeoutError):
            # Backpressure: drop this chunk
            return False
    
    async def process_loop(self, source: str):
        """Worker loop for a source. Respects priority."""
        queue = self._queues[source]
        
        while True:
            chunk = await queue.get()
            
            # Semaphore limits concurrent inference
            async with self._infer_semaphore:
                await self._transcribe(chunk)
```

### Effort Estimate
- **Semaphore integration**: 2-3 hours
- **Priority queues**: 3-4 hours
- **Adaptive chunk sizing**: 2-3 hours
- **Metrics integration**: 2 hours
- **Total**: 9-12 hours

---

## 3. PR6: Reconnect Cap (WebSocket Resilience)

### Current State (Problems)
- **No reconnect limit**: Will retry forever during outages
- **No jitter**: Exponential backoff without randomization (thundering herd)
- **No circuit breaker**: Keeps trying broken server
- **No message buffering**: Audio lost during disconnect

### Research Findings: Optimal Approach

**Recommended Pattern**: Exponential Backoff + Jitter + Circuit Breaker + Message Buffering

```swift
class ResilientWebSocket {
    /**
     * Three-layer resilience:
     * 1. Exponential backoff with jitter (prevents thundering herd)
     * 2. Circuit breaker (fail fast after repeated failures)
     * 3. Message buffering (queue while disconnected)
     */
    
    // Layer 1: Backoff
    func calculateBackoff(attempt: Int) -> TimeInterval {
        let base = min(pow(2.0, Double(attempt)), maxDelay)
        let jitter = Double.random(in: 0...1) * base * 0.2  // 20% jitter
        return base + jitter
    }
    
    // Layer 2: Circuit breaker
    enum CircuitState { case closed, open, halfOpen }
    func shouldAttemptReconnect() -> Bool {
        switch circuitState {
        case .closed: return true
        case .open where lastFailureTime > 60s ago: 
            circuitState = .halfOpen
            return true
        case .open, .halfOpen: return false
        }
    }
    
    // Layer 3: Message buffer
    let messageQueue = CircularBuffer<Message>(capacity: 1000)
}
```

**Resilience Patterns Compared**:

| Pattern | Protects Against | Implementation |
|---------|-----------------|----------------|
| **Exponential Backoff** | Server overload | 1s → 2s → 4s → 8s... |
| **Jitter** | Thundering herd | ±20% randomization |
| **Circuit Breaker** | Cascading failures | Open after 5 failures |
| **Message Buffer** | Data loss | Queue while offline |
| **Max Retry Limit** | Infinite loops | Stop after 15 attempts |

**Recommended for EchoPanel**:

1. **Exponential backoff with jitter**
   - Base: 1s, Max: 60s
   - Jitter: ±20% random
   - Formula: `min(2^attempt, 60) * (0.8 + random(0, 0.4))`

2. **Circuit breaker** (3 states)
   - CLOSED: Normal operation
   - OPEN: After 5 consecutive failures (60s timeout)
   - HALF_OPEN: Test connection after timeout

3. **Max reconnect attempts**
   - Default: 15 attempts (~5 minutes with backoff)
   - Then: Stop reconnecting, show "Connection lost" error
   - Manual retry: User clicks "Reconnect"

4. **Message buffering** (client-side)
   - Circular buffer: 500-1000 audio chunks
   - TTL: 30 seconds max
   - Flush on reconnect
   - Drop oldest when full

5. **Server-side session affinity**
   - Reconnect returns to same session (if within timeout)
   - Session timeout: 60 seconds
   - Continue from last acknowledged chunk

### Implementation Sketch

```swift
// macapp/ResilientWebSocket.swift
class ResilientWebSocket: NSObject, URLSessionWebSocketDelegate {
    // Configuration
    private let maxReconnectAttempts = 15
    private let maxBackoffDelay: TimeInterval = 60
    private let circuitBreakerThreshold = 5
    private let messageBufferSize = 1000
    
    // State
    private var reconnectAttempt = 0
    private var circuitState: CircuitState = .closed
    private var messageBuffer = CircularBuffer<Data>(capacity: messageBufferSize)
    
    func connect() {
        guard canAttemptReconnect() else {
            notifyConnectionFailedPermanently()
            return
        }
        
        // Connect with timeout
        // ...
    }
    
    private func onDisconnect(error: Error?) {
        recordFailure()
        
        if shouldRetry(error: error) {
            let delay = calculateBackoff(attempt: reconnectAttempt)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.connect()
            }
        } else {
            notifyConnectionFailedPermanently()
        }
    }
    
    func sendAudio(_ data: Data) {
        if state == .connected {
            send(data)
        } else {
            // Buffer while disconnected
            messageBuffer.append(data)
        }
    }
}
```

### Effort Estimate
- **Backoff + jitter**: 2 hours
- **Circuit breaker**: 3-4 hours
- **Message buffering**: 3-4 hours
- **Session affinity (server)**: 4-5 hours
- **Total**: 12-15 hours

---

## 4. ASR Provider Improvements (Beyond PR4-PR6)

### 4.1 whisper.cpp Provider (High Priority)

**Why**: 3-5× faster on Apple Silicon, lower memory, true streaming

**Integration Approach**:
- **Method**: `pywhispercpp` Python bindings (best balance)
- **Metal**: Enable for 3-5× speedup on M-series Macs
- **CoreML**: Alternative using Neural Engine

**Performance Comparison**:

| Provider | RTF (M1 Pro) | Memory | Streaming | Status |
|----------|--------------|--------|-----------|--------|
| faster-whisper (CPU) | 0.5x | 500MB | Chunked | Current |
| whisper.cpp (Metal) | 2.0x | 300MB | **Yes** | **Recommended** |
| Voxtral (if fixed) | 1.5x | 10GB | Yes | TBD |

**Implementation Sketch**:

```python
# server/services/provider_whisper_cpp.py
from pywhispercpp.model import Model

class WhisperCppProvider(ASRProvider):
    """whisper.cpp provider with Metal acceleration."""
    
    def __init__(self, model_path: str):
        # Load with Metal backend
        self._model = Model(
            model_path,
            params={
                "n_threads": 4,
                "use_metal": True,  # Key: Metal for Apple Silicon
            }
        )
    
    async def transcribe_stream(self, pcm_stream):
        """True streaming transcription."""
        buffer = AudioBuffer()
        
        async for chunk in pcm_stream:
            buffer.add(chunk)
            
            # Check for speech (VAD)
            if buffer.has_speech():
                # Transcribe with partial results
                result = self._model.transcribe(
                    buffer.audio,
                    partial=True  # Streaming mode
                )
                yield ASRSegment(...)
```

**Effort**: 8-12 hours

### 4.2 Capability Detection (Medium Priority)

**Why**: Auto-select optimal provider based on hardware

**Detection Logic**:

```python
class CapabilityDetector:
    def detect(self) -> MachineProfile:
        return MachineProfile(
            ram_gb=psutil.virtual_memory().total / (1024**3),
            cpu_cores=psutil.cpu_count(),
            has_mps=torch.backends.mps.is_available(),
            has_cuda=torch.cuda.is_available(),
        )
    
    def recommend(self, profile: MachineProfile) -> ProviderConfig:
        if profile.has_mps and profile.ram_gb >= 8:
            return ProviderConfig(
                provider="whisper_cpp",  # Metal-accelerated
                model="base",
                chunk_seconds=2,
            )
        elif profile.ram_gb >= 16:
            return ProviderConfig(
                provider="faster_whisper",
                model="small.en",
                chunk_seconds=4,
            )
        else:
            return ProviderConfig(
                provider="faster_whisper",
                model="base.en",
                chunk_seconds=4,
            )
```

**Effort**: 4-6 hours

### 4.3 Degrade Ladder (Medium Priority)

**Why**: Automatic quality reduction when overloaded

**Levels**:

| Level | Trigger | Action |
|-------|---------|--------|
| 0 | Normal | Full quality |
| 1 | RTF > 0.8 | Increase chunk size (+0.5s) |
| 2 | RTF > 1.0 | Switch to smaller model |
| 3 | RTF > 1.2 | Disable secondary source |
| 4 | Crash | Failover to fallback provider |

**Effort**: 6-8 hours

---

## 5. Implementation Priority Matrix

| Feature | Impact | Effort | Risk | Priority |
|---------|--------|--------|------|----------|
| **PR6: Reconnect Cap** | High | Medium | Low | **P1** (safety) |
| **whisper.cpp Provider** | High | Medium | Medium | **P1** (performance) |
| **PR5: Concurrency Limit** | High | Medium | Low | **P2** |
| **PR4: Model Preloading** | Medium | Medium | Low | **P2** |
| **Capability Detection** | Medium | Low | Low | **P3** |
| **Degrade Ladder** | Medium | Medium | Medium | **P3** |
| **Voxtral Fix** | High | High | High | **P4** (wait for validation) |

---

## 6. Recommended Implementation Order

### Phase 1: Safety & Stability (1 week)
1. **PR6: Reconnect Cap** - Prevent infinite loops
2. **PR5: Concurrency Limit** - Prevent overload

### Phase 2: Performance (1 week)
3. **whisper.cpp Provider** - 3-5× speedup on Apple Silicon
4. **Capability Detection** - Auto-select optimal provider

### Phase 3: Polish (3-4 days)
5. **PR4: Model Preloading** - Better UX
6. **Degrade Ladder** - Graceful degradation

### Phase 4: Experimental (Future)
7. **Voxtral Fix** - If benchmarks validate

---

## 7. References

- `docs/ASR_MODEL_PRELOADING_PATTERNS.md` (57KB)
- `docs/ASR_CONCURRENCY_PATTERNS_RESEARCH.md` (45KB)
- `docs/WEBSOCKET_RECONNECTION_RESILIENCE_RESEARCH.md` (52KB)
- `docs/whisper_cpp_integration_research.md` (38KB)
- `docs/audit/asr-provider-performance-20260211.md`
- `docs/architecture/DUAL_PIPELINE_ASR.md`

---

**Next Step**: Review this synthesis, then create implementation tickets for chosen priorities.
