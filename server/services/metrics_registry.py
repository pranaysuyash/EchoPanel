"""
Metrics Registry for EchoPanel Server

Provides lightweight in-memory metrics collection for observability.
Designed for single-server deployments (no external dependencies).
"""

import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Callable
from collections import deque
import threading


@dataclass
class Counter:
    """Monotonically increasing counter."""
    name: str
    description: str
    value: int = 0
    labels: Dict[str, str] = field(default_factory=dict)
    
    def inc(self, amount: int = 1) -> None:
        self.value += amount
    
    def get(self) -> int:
        return self.value


@dataclass
class Gauge:
    """Value that can go up or down."""
    name: str
    description: str
    value: float = 0.0
    labels: Dict[str, str] = field(default_factory=dict)
    
    def set(self, value: float) -> None:
        self.value = value
    
    def inc(self, amount: float = 1.0) -> None:
        self.value += amount
    
    def dec(self, amount: float = 1.0) -> None:
        self.value -= amount
    
    def get(self) -> float:
        return self.value


@dataclass
class Histogram:
    """Distribution of values into buckets."""
    name: str
    description: str
    buckets: List[float] = field(default_factory=lambda: [100, 250, 500, 1000, 2000, 5000])
    counts: Dict[float, int] = field(default_factory=dict)
    sum_value: float = 0.0
    count: int = 0
    labels: Dict[str, str] = field(default_factory=dict)
    
    def __post_init__(self):
        for bucket in self.buckets:
            if bucket not in self.counts:
                self.counts[bucket] = 0
    
    def observe(self, value: float) -> None:
        self.sum_value += value
        self.count += 1
        for bucket in self.buckets:
            if value <= bucket:
                self.counts[bucket] += 1
    
    def get(self) -> Dict:
        return {
            "count": self.count,
            "sum": self.sum_value,
            "buckets": {str(k): v for k, v in self.counts.items()}
        }


class MetricsRegistry:
    """
    Central registry for all metrics.
    
    Thread-safe for concurrent access.
    """
    
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        
        self._counters: Dict[str, Counter] = {}
        self._gauges: Dict[str, Gauge] = {}
        self._histograms: Dict[str, Histogram] = {}
        self._lock = threading.Lock()
        
        # Initialize default metrics
        self._init_default_metrics()
        
        self._initialized = True
    
    def _init_default_metrics(self) -> None:
        """Initialize standard EchoPanel metrics."""
        # Counters
        self.counter("audio_bytes_received", "Total audio bytes received")
        self.counter("audio_frames_dropped", "Total audio frames dropped due to backpressure")
        self.counter("asr_chunks_processed", "Total ASR chunks processed")
        self.counter("asr_errors", "Total ASR processing errors")
        self.counter("ws_connections_total", "Total WebSocket connections")
        self.counter("ws_disconnects_total", "Total WebSocket disconnects")
        
        # Gauges
        self.gauge("queue_depth", "Current audio queue depth")
        self.gauge("active_sessions", "Number of active sessions")
        self.gauge("processing_lag_seconds", "Current processing lag behind realtime")
        
        # Histograms
        self.histogram("inference_time_ms", "ASR inference time in milliseconds", 
                      buckets=[50, 100, 250, 500, 1000, 2000, 5000])
        self.histogram("processing_time_ms", "Total processing time per chunk in milliseconds",
                      buckets=[100, 250, 500, 1000, 2000, 5000, 10000])
    
    def counter(self, name: str, description: str = "", labels: Optional[Dict[str, str]] = None) -> Counter:
        """Get or create a counter."""
        key = self._make_key(name, labels)
        with self._lock:
            if key not in self._counters:
                self._counters[key] = Counter(
                    name=name,
                    description=description,
                    labels=labels or {}
                )
            return self._counters[key]
    
    def gauge(self, name: str, description: str = "", labels: Optional[Dict[str, str]] = None) -> Gauge:
        """Get or create a gauge."""
        key = self._make_key(name, labels)
        with self._lock:
            if key not in self._gauges:
                self._gauges[key] = Gauge(
                    name=name,
                    description=description,
                    labels=labels or {}
                )
            return self._gauges[key]
    
    def histogram(self, name: str, description: str = "", 
                  buckets: Optional[List[float]] = None,
                  labels: Optional[Dict[str, str]] = None) -> Histogram:
        """Get or create a histogram."""
        key = self._make_key(name, labels)
        with self._lock:
            if key not in self._histograms:
                self._histograms[key] = Histogram(
                    name=name,
                    description=description,
                    buckets=buckets or [100, 250, 500, 1000, 2000, 5000],
                    labels=labels or {}
                )
            return self._histograms[key]
    
    def get_all_metrics(self) -> Dict:
        """Get all metrics as a dictionary."""
        with self._lock:
            return {
                "counters": {k: {"name": v.name, "value": v.value, "labels": v.labels} 
                            for k, v in self._counters.items()},
                "gauges": {k: {"name": v.name, "value": v.value, "labels": v.labels}
                          for k, v in self._gauges.items()},
                "histograms": {k: {"name": v.name, **v.get(), "labels": v.labels}
                              for k, v in self._histograms.items()}
            }
    
    def inc_counter(self, name: str, amount: int = 1, labels: Optional[Dict[str, str]] = None) -> None:
        """Increment a counter by name."""
        self.counter(name, labels=labels).inc(amount)
    
    def set_gauge(self, name: str, value: float, labels: Optional[Dict[str, str]] = None) -> None:
        """Set a gauge value by name."""
        self.gauge(name, labels=labels).set(value)
    
    def observe_histogram(self, name: str, value: float, labels: Optional[Dict[str, str]] = None) -> None:
        """Observe a value in a histogram."""
        self.histogram(name, labels=labels).observe(value)
    
    def _make_key(self, name: str, labels: Optional[Dict[str, str]]) -> str:
        """Create a unique key for a metric with labels."""
        if not labels:
            return name
        label_str = ",".join(f"{k}={v}" for k, v in sorted(labels.items()))
        return f"{name}{{{label_str}}}"


# Global registry instance
REGISTRY = MetricsRegistry()


def get_registry() -> MetricsRegistry:
    """Get the global metrics registry."""
    return REGISTRY
