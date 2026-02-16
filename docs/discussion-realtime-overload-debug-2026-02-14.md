# Discussion: Real-Time Transcription Overload & Frame Drops

**Date:** 2026-02-14  
**Participants:** User, Kimi Code CLI  
**Context:** User reports "failing to get the realtime stuff working, gets overloaded and frames being dropped"

---

## Problem Statement

The real-time audio transcription pipeline is experiencing overload and frame drops. Server logs show messages like:
- `Dropping system due to extreme overload`
- `Backpressure: dropped X frames for source Y`

---

## Current Architecture Analysis

### Audio Pipeline Flow

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Client    │────▶│  WebSocket Send  │────▶│  Server Queue    │
│  Capture    │     │  (Paced Drain)   │     │  (2s max buffer) │
│  (macOS)    │     │                  │     │                  │
└─────────────┘     └──────────────────┘     └────────┬─────────┘
                                                      │
                                                      ▼
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Client UI  │◀────│  ASR Results     │◀────│  ASR Provider    │
│  Display    │     │  (WebSocket)     │     │  (faster-whisper)│
└─────────────┘     └──────────────────┘     └──────────────────┘
```

### Key Configuration Values

| Parameter | Current Value | File |
|-----------|--------------|------|
| `QUEUE_MAX_SECONDS` | 2.0s | `ws_live_listener.py:30` |
| `QUEUE_MAX_BYTES` | 64,000 bytes | `ws_live_listener.py:34` |
| `chunk_seconds` | 4.0s (default) | `provider_faster_whisper.py:122` |
| `maxBufferedFramesPerSource` | 120 frames (~2.4s) | `WebSocketStreamer.swift:181` |
| Client pacing | 20ms per frame | `WebSocketStreamer.swift` drain loop |

---

## Root Causes Identified

### 1. **Chunk Size Mismatch** ⚠️ CRITICAL

**Observation:** The server queue (`QUEUE_MAX_SECONDS=2.0s`) is smaller than the ASR chunk size (`chunk_seconds=4.0s`).

**Impact:** The ASR provider accumulates 4 seconds of audio per chunk, but the queue only holds 2 seconds. This means:
- At steady state, the queue is always near-full
- Any processing delay causes immediate frame drops

**Evidence:**
```python
# ws_live_listener.py:30
QUEUE_MAX_SECONDS = float(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX_SECONDS", "2.0"))

# provider_faster_whisper.py:122-123
chunk_seconds = self.config.chunk_seconds  # defaults to 4.0
chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)  # 128KB
```

### 2. **ASR Processing Speed (RTF)** ⚠️ CRITICAL

**Observation:** The Real-Time Factor (RTF) determines if ASR can keep up with audio.

- RTF = processing_time / audio_duration
- RTF < 1.0: Faster than real-time (good)
- RTF > 1.0: Slower than real-time (backlog builds)

**Current State:**
- No global inference lock (removed for per-session concurrency)
- CTranslate2 models are thread-safe
- BUT: Dual-source sessions contend for CPU/GPU

**Code tracking RTF:**
```python
# provider_faster_whisper.py:197-203
audio_duration_sec = len(audio_bytes) / (sample_rate * bytes_per_sample)
rtf = (infer_ms / 1000.0) / audio_duration_sec if audio_duration_sec > 0 else 0.0
rtf_status = "OK" if rtf < 1.0 else ("WARN" if rtf < 1.5 else "CRITICAL")
```

### 3. **No Pause/Resume on Backpressure** ⚠️ HIGH

**Observation:** Client continues capturing even when server is overloaded.

**Current Behavior:**
- Server sends `backpressure` status when `fill_ratio > 0.85`
- Server sends `overloaded` status when `fill_ratio > 0.95`
- Client receives these but **does not pause capture**

**Evidence:**
```swift
// WebSocketStreamer.swift:685-698
switch state {
case "streaming", "backpressure", "warning", "buffering", "overloaded":
    self.serverStreamingAcked = true
    self.onStatus?(.streaming, message)
    // NOTE: No pause action on backpressure/overloaded
}
```

**Audit Reference:** `docs/audit/PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md` - PR2 marked as NOT STARTED

### 4. **Unbounded ASR Provider Buffer** ⚠️ MEDIUM

**Observation:** The ASR provider's internal buffer grows without limit if processing is slow.

```python
# provider_faster_whisper.py:124
buffer = bytearray()  # Grows as chunks arrive

# While loop processes chunks:
while len(buffer) >= chunk_bytes:
    # ... process one chunk
    del buffer[:chunk_bytes]  # Only removes processed data
```

**Risk:** Memory exhaustion on long sessions with slow ASR.

---

## Previously Fixed Issues

### Fixed: False "Overloaded" Signals

**File:** `docs/audit/asr-overload-drop-system-20260213.md`

**Problem:** `ConcurrencyController` internal queues were never drained by the ASR loop, causing false sustained "overloaded" signals.

**Fix:** Removed unused controller-owned audio queue path from `put_audio()`.

**Status:** ✅ Fixed on 2026-02-13

---

## Recommended Fixes (Priority Order)

### P0: Match Queue Size to Chunk Size

**Change:** Increase `QUEUE_MAX_SECONDS` from 2.0s to at least 6.0s (1.5x chunk size).

```python
# ws_live_listener.py:30
QUEUE_MAX_SECONDS = float(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX_SECONDS", "6.0"))
```

**Rationale:** Buffer should hold at least 1 full ASR chunk + headroom for processing jitter.

### P0: Reduce Default Chunk Size

**Change:** Reduce `chunk_seconds` from 4.0s to 2.0s for real-time mode.

```python
# server/services/asr_stream.py or config
ASRConfig(chunk_seconds=2.0)  # For streaming/real-time
```

**Trade-off:** Smaller chunks = more frequent inference = higher overhead, but lower latency.

### P1: Implement Pause/Resume on Backpressure

**Change:** When server sends `overloaded` status, pause capture; resume when `fill_ratio < 0.70`.

```swift
// WebSocketStreamer.swift - in handleJSON
if state == "overloaded" {
    self.pauseCapture()  // New method
} else if state == "streaming" && self.isCapturePaused {
    self.resumeCapture()  // New method
}
```

**Reference:** PR2 in `docs/audit/PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md`

### P1: Add ASR Buffer Cap

**Change:** Cap provider buffer at 30 seconds.

```python
# provider_faster_whisper.py
max_buffer_bytes = int(sample_rate * 30 * bytes_per_sample)  # 30s max
if len(buffer) > max_buffer_bytes:
    overflow = len(buffer) - max_buffer_bytes
    del buffer[:overflow]  # Drop oldest
    logger.warning(f"ASR buffer overflow, dropped {overflow} bytes")
```

### P2: Dynamic Chunk Size Based on RTF

**Change:** If RTF > 1.0 for sustained period, reduce chunk size to 1.0s or 0.5s.

```python
# In _asr_loop or DegradeLadder
if realtime_factor > 1.5 and chunk_seconds > 1.0:
    chunk_seconds = max(0.5, chunk_seconds / 2)
    logger.info(f"Reducing chunk size to {chunk_seconds}s due to high RTF")
```

---

## Workarounds (Immediate)

1. **Use smaller model:** Set `ECHOPANEL_WHISPER_MODEL=tiny` or `base` instead of `small`/`medium`
2. **Single source only:** Use only "System" or "Mic", not "Both"
3. **Increase queue via env:** `ECHOPANEL_AUDIO_QUEUE_MAX_SECONDS=6.0`
4. **Reduce chunk via env:** If config supports it: `ECHOPANEL_ASR_CHUNK_SECONDS=2.0`

---

## Evidence Citations

| File | Lines | Observation |
|------|-------|-------------|
| `ws_live_listener.py` | 30-36 | Queue sizing: 2s max, 500 frames |
| `provider_faster_whisper.py` | 122-124 | Chunk size: 4s, unbounded buffer |
| `WebSocketStreamer.swift` | 181, 374-439 | Client pacing: 20ms frames, 120 max buffered |
| `PHASE_1C_STREAMING_BACKPRESSURE_AUDIT.md` | 211-232 | Queue/buffer inventory and critical observations |
| `asr-overload-drop-system-20260213.md` | 35-41 | Previous false-drop bug fix |

---

## Open Questions

1. **Hardware:** What Mac model is being used? (Apple Silicon vs Intel affects inference speed)
2. **Model:** Which Whisper model is loaded? (`tiny`/`base`/`small`/`medium`)
3. **Sources:** Is the issue with single source or dual source (Both) mode?
4. **RTF Values:** What are the actual RTF values being logged?

---

*Next Step: Implement P0 fixes (queue size and chunk size alignment)*
