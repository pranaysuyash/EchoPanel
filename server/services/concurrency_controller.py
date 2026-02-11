"""
PR5: Analysis Concurrency Limiting + Backpressure

Implements multi-level concurrency control:
1. Global session semaphore (max concurrent sessions)
2. Per-source bounded priority queues (mic > system priority)
3. Inference semaphore (respects ASR threading constraints)
4. Adaptive chunk sizing based on load
"""

import asyncio
import time
from dataclasses import dataclass, field
from typing import Dict, Optional, Callable, Any
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class BackpressureLevel(Enum):
    """Backpressure severity levels"""
    NORMAL = 0
    WARNING = 1      # queue_fill > 0.70
    DEGRADED = 2     # queue_fill > 0.85 or RTF > 1.0
    CRITICAL = 3     # queue_fill > 0.95
    OVERLOADED = 4   # sustained overload


@dataclass
class ConcurrencyMetrics:
    """Real-time concurrency metrics"""
    active_sessions: int
    max_sessions: int
    queue_depths: Dict[str, int]
    queue_max: Dict[str, int]
    queue_fill_ratios: Dict[str, float]
    backpressure_level: BackpressureLevel
    dropped_frames_total: int
    dropped_frames_recent: int
    avg_wait_ms: float
    timestamp: float = field(default_factory=time.time)


@dataclass
class AudioChunk:
    """Audio chunk with priority metadata"""
    data: bytes
    source: str
    timestamp: float
    sequence: int
    priority: int = 0  # Lower = higher priority (mic=1, system=2)
    
    def __lt__(self, other):
        # For priority queue: lower priority value = processed first
        return self.priority < other.priority


class ConcurrencyController:
    """
    Multi-level concurrency controller for ASR processing.
    
    Features:
    - Global session limiting (prevent resource exhaustion)
    - Per-source bounded queues (natural backpressure)
    - Priority processing (mic > system)
    - Adaptive chunk sizing (load-based)
    - Metrics emission for monitoring
    """
    
    def __init__(
        self,
        max_sessions: int = 10,
        max_inference: int = 1,  # faster-whisper needs single-thread
        queue_sizes: Optional[Dict[str, int]] = None,
        adaptive_sizing: bool = True,
    ):
        self.max_sessions = max_sessions
        self.max_inference = max_inference
        self.adaptive_sizing = adaptive_sizing
        
        # Global session semaphore
        self._session_sem = asyncio.Semaphore(max_sessions)
        
        # Inference semaphore (protects ASR provider)
        self._infer_sem = asyncio.Semaphore(max_inference)
        
        # Per-source bounded queues
        default_queue_sizes = {"mic": 100, "system": 50}
        self._queue_sizes = {**default_queue_sizes, **(queue_sizes or {})}
        
        # Priority queues: mic (priority=1) > system (priority=2)
        self._queues: Dict[str, asyncio.PriorityQueue] = {
            source: asyncio.PriorityQueue(maxsize=size)
            for source, size in self._queue_sizes.items()
        }
        
        # Source priority mapping
        self._source_priority = {"mic": 1, "system": 2}
        
        # Metrics tracking
        self._dropped_frames_total = 0
        self._dropped_frames_recent = 0
        self._last_metrics_reset = time.time()
        self._wait_times: list = []
        
        # Adaptive chunk sizing state
        self._current_chunk_size = 2.0  # Start at 2s
        self._load_history: list = []
        
        # Backpressure state
        self._backpressure_level = BackpressureLevel.NORMAL
        self._overload_start_time: Optional[float] = None
        
        logger.info(
            f"ConcurrencyController initialized: "
            f"max_sessions={max_sessions}, "
            f"max_inference={max_inference}, "
            f"queues={self._queue_sizes}"
        )
    
    async def acquire_session(self, timeout: float = 5.0) -> bool:
        """
        Acquire a session slot. Returns False if max sessions reached.
        
        Args:
            timeout: How long to wait for a slot
            
        Returns:
            True if slot acquired, False if timed out
        """
        try:
            await asyncio.wait_for(
                self._session_sem.acquire(),
                timeout=timeout
            )
            logger.debug(f"Session acquired, available: {self._session_sem._value}")
            return True
        except asyncio.TimeoutError:
            logger.warning(f"Session acquisition timeout after {timeout}s")
            return False
    
    def release_session(self):
        """Release a session slot"""
        self._session_sem.release()
        logger.debug(f"Session released, available: {self._session_sem._value}")
    
    async def submit_chunk(
        self,
        chunk: bytes,
        source: str,
        timeout: float = 0.1
    ) -> tuple[bool, bool]:
        """
        Submit an audio chunk for processing.
        
        Args:
            chunk: Raw PCM audio data
            source: Audio source ("mic" or "system")
            timeout: How long to wait if queue is full
            
        Returns:
            Tuple of (success, dropped_oldest):
            - success: True if chunk was queued
            - dropped_oldest: True if an old chunk was dropped to make room
        """
        if source not in self._queues:
            logger.warning(f"Unknown source '{source}', using 'system' queue")
            source = "system"
        
        queue = self._queues[source]
        priority = self._source_priority.get(source, 2)
        
        audio_chunk = AudioChunk(
            data=chunk,
            source=source,
            timestamp=time.time(),
            sequence=self._dropped_frames_total + self._get_queue_depth(),
            priority=priority,
        )
        
        dropped_oldest = False
        
        try:
            # Non-blocking put with timeout
            await asyncio.wait_for(
                queue.put(audio_chunk),
                timeout=timeout
            )
            return True, dropped_oldest
            
        except (asyncio.QueueFull, asyncio.TimeoutError):
            # Backpressure: drop oldest and add new (keep newest)
            try:
                dropped = queue.get_nowait()
                self._dropped_frames_total += 1
                self._dropped_frames_recent += 1
                dropped_oldest = True
                
                logger.warning(
                    f"Dropped oldest {dropped.source} chunk "
                    f"(total_dropped={self._dropped_frames_total})"
                )
                
                # Try again with space now available
                await queue.put(audio_chunk)
                return True, dropped_oldest
                
            except asyncio.QueueEmpty:
                # Shouldn't happen, but handle gracefully
                logger.error(f"Queue full but get_nowait failed for {source}")
                return False, dropped_oldest
    
    async def get_chunk(self, source: str) -> Optional[AudioChunk]:
        """
        Get next chunk from queue.
        
        Args:
            source: Audio source to get from
            
        Returns:
            AudioChunk or None if shutdown
        """
        if source not in self._queues:
            return None
        
        queue = self._queues[source]
        
        try:
            chunk = await queue.get()
            
            # Track wait time
            wait_time = (time.time() - chunk.timestamp) * 1000
            self._wait_times.append(wait_time)
            if len(self._wait_times) > 100:
                self._wait_times.pop(0)
            
            return chunk
            
        except asyncio.CancelledError:
            return None
    
    async def process_with_inference_lock(
        self,
        processor: Callable[[], Any]
    ) -> Any:
        """
        Execute processor with inference semaphore held.
        
        This ensures ASR inference is single-threaded (required by faster-whisper).
        
        Args:
            processor: Async callable that performs ASR inference
            
        Returns:
            Result from processor
        """
        async with self._infer_sem:
            return await processor()
    
    def get_chunk_size(self) -> float:
        """
        Get current chunk size based on load.
        
        Returns:
            Chunk size in seconds (2.0, 4.0, or 8.0)
        """
        if not self.adaptive_sizing:
            return 2.0
        
        # Calculate load factor from queue fill ratios
        fill_ratios = [
            self._get_queue_fill_ratio(source)
            for source in self._queues.keys()
        ]
        avg_fill = sum(fill_ratios) / len(fill_ratios) if fill_ratios else 0
        
        # Track load history
        self._load_history.append(avg_fill)
        if len(self._load_history) > 10:
            self._load_history.pop(0)
        
        # Use smoothed average
        smoothed_load = sum(self._load_history) / len(self._load_history)
        
        # Adjust chunk size based on load
        if smoothed_load < 0.5:
            self._current_chunk_size = 2.0  # Fast response
        elif smoothed_load < 0.8:
            self._current_chunk_size = 4.0  # Batch more
        else:
            self._current_chunk_size = 8.0  # Survival mode
        
        return self._current_chunk_size
    
    def get_backpressure_level(self) -> BackpressureLevel:
        """
        Determine current backpressure level.
        
        Returns:
            BackpressureLevel based on queue fill and load
        """
        fill_ratios = [
            self._get_queue_fill_ratio(source)
            for source in self._queues.keys()
        ]
        max_fill = max(fill_ratios) if fill_ratios else 0
        
        # Check for sustained overload
        if max_fill > 0.95:
            if self._overload_start_time is None:
                self._overload_start_time = time.time()
            elif time.time() - self._overload_start_time > 5:
                # Sustained overload for 5+ seconds
                self._backpressure_level = BackpressureLevel.OVERLOADED
                return self._backpressure_level
            self._backpressure_level = BackpressureLevel.CRITICAL
            
        elif max_fill > 0.85:
            self._overload_start_time = None
            self._backpressure_level = BackpressureLevel.DEGRADED
            
        elif max_fill > 0.70:
            self._overload_start_time = None
            self._backpressure_level = BackpressureLevel.WARNING
            
        else:
            self._overload_start_time = None
            self._backpressure_level = BackpressureLevel.NORMAL
        
        return self._backpressure_level
    
    def get_metrics(self) -> ConcurrencyMetrics:
        """
        Get current concurrency metrics.
        
        Returns:
            ConcurrencyMetrics snapshot
        """
        # Reset recent dropped counter periodically
        now = time.time()
        if now - self._last_metrics_reset > 10:
            self._dropped_frames_recent = 0
            self._last_metrics_reset = now
        
        return ConcurrencyMetrics(
            active_sessions=self.max_sessions - self._session_sem._value,
            max_sessions=self.max_sessions,
            queue_depths={
                source: self._get_queue_depth(source)
                for source in self._queues.keys()
            },
            queue_max=self._queue_sizes,
            queue_fill_ratios={
                source: self._get_queue_fill_ratio(source)
                for source in self._queues.keys()
            },
            backpressure_level=self.get_backpressure_level(),
            dropped_frames_total=self._dropped_frames_total,
            dropped_frames_recent=self._dropped_frames_recent,
            avg_wait_ms=sum(self._wait_times) / len(self._wait_times)
            if self._wait_times else 0,
        )
    
    def _get_queue_depth(self, source: Optional[str] = None) -> int:
        """Get current queue depth"""
        if source:
            return self._queues.get(source, asyncio.Queue()).qsize()
        return sum(q.qsize() for q in self._queues.values())
    
    def _get_queue_fill_ratio(self, source: str) -> float:
        """Get queue fill ratio (0.0 to 1.0)"""
        if source not in self._queues:
            return 0.0
        
        depth = self._queues[source].qsize()
        max_size = self._queue_sizes.get(source, 1)
        return depth / max_size
    
    def should_drop_source(self, source: str) -> bool:
        """
        Determine if a source should be dropped under extreme load.
        
        In critical overload, we drop system audio but keep mic.
        
        Args:
            source: Audio source to check
            
        Returns:
            True if this source should be dropped
        """
        level = self.get_backpressure_level()
        
        if level == BackpressureLevel.OVERLOADED:
            # Keep only mic audio
            return source != "mic"
        
        if level == BackpressureLevel.CRITICAL:
            # Drop system audio if mic is prioritized
            return source == "system"
        
        return False


# Global controller instance (singleton)
_concurrency_controller: Optional[ConcurrencyController] = None


def get_concurrency_controller() -> ConcurrencyController:
    """Get or create the global concurrency controller"""
    global _concurrency_controller
    if _concurrency_controller is None:
        _concurrency_controller = ConcurrencyController()
    return _concurrency_controller


def reset_concurrency_controller():
    """Reset the global controller (for testing)"""
    global _concurrency_controller
    _concurrency_controller = None
