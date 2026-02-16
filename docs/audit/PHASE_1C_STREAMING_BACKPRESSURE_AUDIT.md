# Phase 1C Audit: Streaming Reliability + Backpressure (End-to-End)

**Date:** 2026-02-10
**Auditor:** Multi-Persona Analysis (Audio Systems, Protocol, UI/Reliability, Abuse, Truthfulness)
**Scope:** Live session reliability end-to-end—capture, transport, ingest, queues, ASR, backpressure, UI truthfulness
**Status:** OPEN
**Last reviewed:** 2026-02-11 (Audit Queue Runner)

---

## Update (2026-02-13)

- ✅ Client-side send queue now exists: `WebSocketStreamer` uses a bounded `OperationQueue` (`sendQueue`) and logs 5s send timeouts; the earlier “no client send queue”/“send blocks capture thread” notes below are now outdated. Evidence: `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`.
- ✅ PR6 (metrics realtime_factor) implemented: server metrics now compute `realtime_factor` from actual `(processing_time / audio_duration)` samples per source, rather than `avg_infer_time / ECHOPANEL_ASR_CHUNK_SECONDS`. Evidence: `server/api/ws_live_listener.py`; tests: `tests/test_streaming_correctness.py` (`TestMetricsRTF`).

## A) Files Inspected

### Client (Swift)
| Path | Lines | Purpose |
|------|-------|---------|
| `macapp/MeetingListenerApp/Sources/AppState.swift` | 1-1396 | Session state machine, audio capture orchestration, metrics handling |
| `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` | 1-351 | WebSocket client, message handling, reconnection |
| `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` | 1-312 | System audio capture (ScreenCaptureKit), PCM frame emission |
| `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift` | 1-139 | Microphone capture (AVAudioEngine), PCM frame emission |
| `macapp/MeetingListenerApp/Sources/BackendManager.swift` | 1-501 | Server lifecycle, health checks, crash recovery |

### Server (Python)
| Path | Lines | Purpose |
|------|-------|---------|
| `server/api/ws_live_listener.py` | 1-616 | WebSocket handler, session management, queues, ASR loops, metrics |
| `server/services/asr_stream.py` | 1-91 | ASR pipeline interface, provider abstraction |
| `server/services/asr_providers.py` | 1-150 | ASR provider base classes, registry |
| `server/services/provider_faster_whisper.py` | 1-239 | Faster-Whisper ASR implementation |
| `server/services/provider_voxtral_realtime.py` | 1-184 | Voxtral.c ASR implementation |
| `server/services/vad_filter.py` | 1-148 | Silero VAD for speech detection |
| `server/services/analysis_stream.py` | 1-416 | NLP card/entity extraction, rolling summary |
| `server/services/diarization.py` | 1-214 | Speaker diarization (pyannote.audio) |

### Tests
| Path | Lines | Purpose |
|------|-------|---------|
| `tests/test_streaming_correctness.py` | 1-243 | Backpressure, ordering, thread-safety tests |
| `scripts/soak_test.py` | 1-260 | End-to-end soak testing harness |

---

## B) End-to-End Pipeline Map (CURRENT)

### B1. Capture → Transport (Client-Side)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLIENT (macOS)                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │ System Audio (SCStream)│    │ Microphone (AVAudioEngine)│                 │
│  │ - 16kHz PCM16 mono   │     │ - 16kHz PCM16 mono   │                        │
│  │ - Frame size: 320 samples │ │ - Frame size: 320 samples │                  │
│  │ - 20ms cadence       │     │ - 20ms cadence       │                        │
│  └──────────┬──────────┘     └──────────┬──────────┘                        │
│             │                           │                                    │
│             ▼                           ▼                                    │
│  ┌─────────────────────────────────────────────────┐                        │
│  │  AudioCaptureManager / MicrophoneCaptureManager  │                        │
│  │  - No client-side buffering                      │                        │
│  │  - Synchronous callback onPCMFrame()             │                        │
│  │  - Timestamp: capture timestamp (derived)        │                        │
│  └───────────────────┬─────────────────────────────┘                        │
│                      │                                                       │
│                      ▼                                                       │
│  ┌─────────────────────────────────────────────────┐                        │
│  │  WebSocketStreamer.sendPCMFrame()               │                        │
│  │  - Bounded send queue (prevents capture-thread stalls)                   │
│  │  - Logs send timeouts (5s)                                               │
│  └───────────────────┬─────────────────────────────┘                        │
│                      │                                                       │
│                      ▼                                                       │
│  ┌─────────────────────────────────────────────────┐                        │
│  │  WebSocket (ws://localhost:8000/ws/live-listener)│                       │
│  │  - Binary: legacy binary frames                 │                        │
│  │  - JSON: {"type":"audio","source":"system|mic",  │                        │
│  │          "data":"base64(pcm)"}                  │                        │
│  └───────────────────┬─────────────────────────────┘                        │
│                      │                                                       │
└──────────────────────┼───────────────────────────────────────────────────────┘
                       │
                       ▼
```

**Evidence:**
- `AudioCaptureManager.swift:215-221`: `emitPCMFrames()` produces 320-sample (20ms) frames at 16kHz
- `AudioCaptureManager.swift:220`: `onPCMFrame?(data, "system")` — synchronous callback
- `MicrophoneCaptureManager.swift:107-127`: Same 20ms frame size for mic
- `WebSocketStreamer.swift:98-110`: `sendPCMFrame()` does synchronous JSON encoding + `task?.send()`

### B2. Transport → Ingest → Queues (Server-Side)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SERVER (Python/FastAPI)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WebSocket → ws_live_listener.py                                             │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Message Router (per-source)                                         │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐│    │
│  │  │  Source "system"                                                ││    │
│  │  │  └── asyncio.Queue(maxsize=QUEUE_MAX)  [default: 48 = ~1s]     ││    │
│  │  │      - 640 bytes/chunk (320 samples × 2 bytes)                  ││    │
│  │  │      - ~30ms audio per chunk                                    ││    │
│  │  └─────────────────────────────────────────────────────────────────┘│    │
│  │  ┌─────────────────────────────────────────────────────────────────┐│    │
│  │  │  Source "mic"                                                   ││    │
│  │  │  └── asyncio.Queue(maxsize=QUEUE_MAX)  [default: 48]          ││    │
│  │  └─────────────────────────────────────────────────────────────────┘│    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              │                                               │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  put_audio() → Queue Management                                     │    │
│  │  - On full: drops OLDEST, keeps NEWEST                              │    │
│  │  - Increments state.dropped_frames                                  │    │
│  │  - Sends "backpressure" status if not already warned                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                              │                                               │
│                              ▼                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  ASR Loop (_asr_loop per source)                                    │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐│    │
│  │  │  _pcm_stream() generator                                        ││    │
│  │  │  ├── await queue.get()  ← BLOCKING consumer                     ││    │
│  │  │  └── yield chunk                                                ││    │
│  │  └─────────────────────────────────────────────────────────────────┘│    │
│  │                              │                                       │    │
│  │                              ▼                                       │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐│    │
│  │  │  stream_asr() → provider.transcribe_stream()                    ││    │
│  │  │  - Accumulates chunks into chunk_seconds buffer (default: 2s)   ││    │
│  │  │  - Runs ASR inference via asyncio.to_thread()                   ││    │
│  │  │  - Emits ASRSegment → JSON → WebSocket                         ││    │
│  │  └─────────────────────────────────────────────────────────────────┘│    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Evidence:**
- `ws_live_listener.py:21`: `QUEUE_MAX = int(os.getenv("ECHOPANEL_AUDIO_QUEUE_MAX", "48"))`
- `ws_live_listener.py:42`: `queues: Dict[str, asyncio.Queue]` — per-source queues
- `ws_live_listener.py:236-268`: `put_audio()` drops oldest on QueueFull, logs warning
- `ws_live_listener.py:270-277`: `_pcm_stream()` blocks on `queue.get()`
- `ws_live_listener.py:279-302`: `_asr_loop()` runs per source
- `provider_faster_whisper.py:91-92`: `chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)` — 2s default

### B3. Analysis Pipeline (Async)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ANALYSIS LOOP (_analysis_loop) — Single instance per session                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Every 12s:  extract_entities()  → emit "entities_update"                   │
│  Every 28s:  extract_cards()     → emit "cards_update"                      │
│  (40s total cycle)                                                          │
│                                                                             │
│  Blocking points:                                                           │
│  - `asyncio.to_thread(extract_entities)` — runs in thread pool              │
│  - `asyncio.to_thread(extract_cards)` — runs in thread pool                 │
│                                                                             │
│  Memory: Uses transcript list snapshot (copy), 10-minute sliding window     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Evidence:**
- `ws_live_listener.py:304-324`: `_analysis_loop()` with 12s + 28s sleeps
- `analysis_stream.py:101-162`: `extract_cards()` uses 10-minute sliding window

### B4. Metrics Loop (PR2 Addition)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  METRICS LOOP (_metrics_loop) — 1 Hz emission                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  For each source:                                                           │
│  - queue_depth / queue_max = fill_ratio                                     │
│  - dropped_recent (delta from last 1s)                                      │
│  - avg_infer_ms (from asr_processing_times, last 10 samples)                │
│  - realtime_factor = sum(processing_time) / sum(audio_duration)             │
│                                                                             │
│  Thresholds:                                                                │
│  - fill_ratio > 0.95 → "overloaded"                                         │
│  - fill_ratio > 0.85 → "buffering"                                          │
│  - fill_ratio < 0.70 → clear backpressure_warned                            │
│                                                                             │
│  Emits: {"type":"metrics", source, queue_depth, queue_max, ...}             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Evidence:**
- `ws_live_listener.py:326-392`: `_metrics_loop()` implementation
- `ws_live_listener.py`: `realtime_factor` computed from actual audio duration samples (`processing_time / audio_duration`) per source
- `ws_live_listener.py:356-372`: Threshold logic for status messages

---

## C) Queue/Buffer Inventory (CURRENT)

| Name | Location | Type | Max Size | Overflow | Owner | Evidence |
|------|----------|------|----------|----------|-------|----------|
| `state.queues["system"]` | `ws_live_listener.py` | `asyncio.Queue` | 48 chunks (~1.5s audio) | Drop oldest | Producer (WebSocket recv) | L21, L229-233 |
| `state.queues["mic"]` | `ws_live_listener.py` | `asyncio.Queue` | 48 chunks (~1.5s audio) | Drop oldest | Producer (WebSocket recv) | L42, L229-233 |
| `provider.buffer` | `provider_faster_whisper.py` | `bytearray` | Unbounded | Grows | Consumer (ASR loop) | L93 |
| `provider._infer_lock` | `provider_faster_whisper.py` | `threading.Lock` | 1 | Blocks | ASR thread | L41, L133 |
| `vad_filter` | `vad_filter.py` | In-memory processing | N/A | N/A | Called per chunk | N/A (inline) |
| `analysis_window` | `analysis_stream.py` | `list` (slice) | 10 min transcript | N/A | Analysis loop | L23, L51-63 |
| `pcm_buffers_by_source` | `ws_live_listener.py` | `bytearray` | 30 min (configurable) | Trim oldest | Diarization | L36, L70-82 |

### Critical Observations

1. **Client-side send queue exists**: `WebSocketStreamer` uses a bounded send queue and logs send timeouts to avoid capture-thread stalls.

2. **Small server-side queues**: 48 chunks × 320 samples × 2 bytes = ~30KB per source. At 2s ASR chunks, this is only ~1.5s of buffering.

3. **Unbounded ASR buffer**: The ASR provider accumulates chunks in a `bytearray` until it has a full `chunk_seconds` buffer. If ASR is slow, this grows without bound.

4. **Single inference lock**: `provider_faster_whisper.py` uses `threading.Lock()` to serialize `model.transcribe()` calls. This prevents concurrent inference but creates a bottleneck with multiple sources.

---

## D) Overload Behavior (CURRENT)

### D1. When ASR Cannot Keep Up

**Backlog accumulates at:**
1. **Server queues** (`state.queues[source]`) — fills to 48 chunks
2. **ASR provider buffer** (`buffer` in `provider_faster_whisper.py`) — grows unbounded

**Dropping occurs at:**
1. `put_audio()` drops oldest when queue full (L251-254)
2. Counter `state.dropped_frames` incremented (L256)
3. Backpressure warning sent once per overload episode (L260-267)

**Counters/logs exist:**
- `state.dropped_frames` — total drops for session
- `state.asr_last_dropped` — for computing `dropped_recent`
- Server logs: `"Backpressure: dropped frame for {source}, total={state.dropped_frames}"`

**User sees:**
- Status message: `"Audio queue full, dropping frames (source=system)"` (sent once)
- Metrics: `{"type":"metrics", "dropped_total": N, "dropped_recent": M}`
- UI: `backpressureLevel` changes to `.buffering` or `.overloaded` based on thresholds

**Evidence:**
- `ws_live_listener.py:251-268`: Drop logic and warning
- `ws_live_listener.py:46`: `dropped_frames` counter
- `AppState.swift:294-307`: Metrics handling and backpressure level update

### D2. Timestamp Source and Preservation

| Stage | Timestamp Source | Preservation |
|-------|-----------------|--------------|
| Capture | Derived from sample count | N/A (real-time) |
| WebSocket | None (message arrival) | N/A |
| Server ingest | None | N/A |
| ASR chunk | `processed_samples / sample_rate` | L123-126 in provider |
| ASR segment | `t0 + segment.start`, `t0 + segment.end` | L162-163 in provider |
| UI display | Received `t0`, `t1` | Stored in `TranscriptSegment` |

**Critical Issue:** Timestamps are monotonic based on processed audio bytes, NOT wall-clock time. If audio is dropped due to backpressure, timestamps will have gaps but the transcript will appear continuous.

---

## E) Failure Modes Table (12+ Items)

| # | Failure Mode | Trigger | Symptoms (UI + logs) | Detection Signal | Current Behavior (Evidence) | Proposed Fix/Policy | Validation Test |
|---|--------------|---------|---------------------|------------------|----------------------------|---------------------|-----------------|
| 1 | **Queue Overflow (Single Source)** | ASR slower than real-time on one source | UI: "Processing backlog for system" once; logs: repeated "dropped frame" | `dropped_recent > 0` in metrics | Drops oldest frames silently; user may not notice (L251-254) | **Policy:** Pause capture when `fill_ratio > 0.95` for >2s; resume when <0.70 | Soak test: 1 source, 0.5x speed ASR, verify capture pauses |
| 2 | **Queue Overflow (Dual Source)** | Both sources overwhelm ASR | UI: "Audio backlog critical"; transcript gaps from both sources | `fill_ratio > 0.95` for both sources | Drops from both queues independently (L236-268) | **Policy:** Reduce to single source when overloaded; auto-recover when healthy | Soak test: 2 sources, 0.3x speed ASR, verify auto-reduce to 1 source |
| 3 | **ASR Inference Stall** | ASR thread blocked (model loading, GC) | UI: No new transcript for 10s+; logs: no "Transcribed N segments" | `realtime_factor` spikes to >5.0 | User sees silence; no explicit warning (L141-146) | **Policy:** Emit "ASR stalled" status if no output for 5s; suggest restart | Inject artificial 10s delay in ASR, verify status message |
| 4 | **WebSocket Send Blocking** | Network congestion, slow consumer | UI: Capture appears to freeze; macOS spinners | N/A — no timeout on `task?.send()` | Synchronous send blocks capture thread (L142-144) | **Policy:** Add 100ms timeout to send; queue drops if timeout exceeded | Network conditioner: 100ms latency, 10% packet loss |
| 5 | **Client Capture Overrun** | System audio callback not serviced fast enough | Logs: "AudioSampleHandler: Received audio buffer" stops incrementing | `inputLastSeenBySource` age > 5s | No recovery; session continues with gaps (L234-247) | **Policy:** Detect capture stall, emit warning, suggest restart | CPU stress test while capturing |
| 6 | **Server Memory Exhaustion** | Long session + slow ASR = unbounded buffer growth | Server process killed by OOM; logs stop abruptly | Server health check fails (503) | ASR buffer grows without limit (L93) | **Policy:** Cap ASR buffer at 30s; drop oldest chunks if exceeded | 30-min soak with 0.5x speed ASR, monitor RSS |
| 7 | **False "Listening" State** | Backend starts but ASR never emits | UI: "Listening" with no transcript; timer running | `asrEventCount == 0` after 10s | PR1 fix adds 5s timeout (L555-571) but only for handshake | **Policy:** Require ASR event within 10s of "streaming" status; else auto-stop | Start session with broken ASR model, verify auto-stop |
| 8 | **Analysis Loop Stall** | NLP extraction hangs on large transcript | Cards/entities stop updating; transcript continues | `cards_update` not received for 60s+ | No timeout on `asyncio.to_thread()` calls (L309, L314) | **Policy:** Add 10s timeout to NLP calls; skip analysis if exceeded | Inject 30s sleep in `extract_cards()`, verify timeout |
| 9 | **Metrics Misleading** | `realtime_factor` uses wrong denominator | UI shows "healthy" (factor <1.0) but actually dropping | `realtime_factor < 1.0` but `dropped_recent > 0` | Calculation assumes 2s chunks, but actual may vary (L352-353) | **Policy:** Use actual audio duration processed, not configured chunk size | Compare `realtime_factor` vs actual wall-clock lag |
| 10 | **Reconnect Loop Amplification** | Intermittent network, client reconnects rapidly | Logs: rapid connect/disconnect cycles | Multiple connect messages per second | Exponential backoff 1s→10s (L327-332) | **Policy:** Cap reconnects at 1/min after 3 failures; require manual retry | Network flicker test: 3s up, 3s down cycle |
| 11 | **Diarization Memory Leak** | Long session with diarization enabled | Server RSS grows continuously; eventual OOM | `pcm_buffers_by_source` size increases | Buffers grow to `diarization_max_bytes` per source (L36, L78-81) | **Policy:** Implement circular buffer for diarization; drop oldest audio | 60-min session with diarization, monitor RSS |
| 12 | **Source Confusion on Reconnect** | Client reconnects mid-session, sends audio before "start" | Server rejects audio; client shows "Listening" | Server logs: "received audio, source=..." before "start" | PR2 fix: server waits for "start" before accepting audio (L457-458) | **Current is correct** — verify test exists | Reconnect test: send audio before start, verify rejection |
| 13 | **Partial-Only Flood** | ASR emits only partials, no finals | UI: text appears but never stabilizes; confidence missing | `asr_final` count = 0 after 30s | Faster-Whisper only emits finals (L159-168) | **Current is correct** — Voxtral provider may differ | Verify only finals stored in transcript (L289-294) |
| 14 | **Concurrent ASR Bottleneck** | Two sources, single inference lock | Both sources lag equally; queues fill together | Both `fill_ratio` rise simultaneously | Single `threading.Lock()` serializes all ASR (L41, L133) | **Policy:** Consider process-per-source or async inference queue | 2-source soak with CPU profiling |

---

## F) Proposed Backpressure Policy (V1)

### F1. Signals

| Signal | Source | Calculation | Frequency |
|--------|--------|-------------|-----------|
| `queue_fill_ratio` | Server metrics | `q.qsize() / QUEUE_MAX` | 1 Hz |
| `realtime_factor` | Server metrics | `avg_infer_ms / (chunk_ms)` | 1 Hz |
| `dropped_chunks_10s` | Server metrics | `dropped_total - dropped_at_10s_ago` | 1 Hz |
| `capture_stall_ms` | Client | Time since last `onPCMFrame` | Per-frame |
| `asr_stall_ms` | Client | Time since last `asr_final` | Per-event |

### F2. States

```
                    ┌─────────────────────────────────────┐
                    │           NORMAL                    │
                    │  fill_ratio < 0.70                  │
                    │  realtime_factor < 0.8              │
                    └──────────────┬──────────────────────┘
                                   │ fill_ratio > 0.85 OR
                                   │ realtime_factor > 1.0
                                   ▼
                    ┌─────────────────────────────────────┐
                    │         BUFFERING                   │
                    │  0.70 ≤ fill_ratio ≤ 0.95           │
                    │  1.0 ≤ realtime_factor ≤ 2.0        │
                    │  dropped_10s = 0                    │
                    └──────────────┬──────────────────────┘
                                   │ fill_ratio > 0.95 OR
                                   │ realtime_factor > 2.0 OR
                                   │ dropped_10s > 0
                                   ▼
                    ┌─────────────────────────────────────┐
                    │         OVERLOADED                  │
                    │  fill_ratio > 0.95                  │
                    │  OR realtime_factor > 2.0           │
                    │  OR dropped_10s > 0                 │
                    └──────────────┬──────────────────────┘
                                   │ fill_ratio < 0.70 AND
                                   │ realtime_factor < 1.0 AND
                                   │ 30s without drops
                                   │
                                   └────────────────────────► NORMAL
```

### F3. Actions Ladder (In Order)

| Priority | Condition | Action | Implementation |
|----------|-----------|--------|----------------|
| 1 | Entering BUFFERING | Enable/require VAD | `vad_filter=True` on ASR provider; skip silent chunks before enqueue |
| 2 | BUFFERING >5s OR entering OVERLOADED | Pause capture (preferred) | Client stops calling `audioCapture.startCapture()`; keeps WebSocket open; UI shows "Paused - catching up" |
| 3 | OVERLOADED with 2 sources | Reduce to 1 source | Auto-switch to primary source only; pause secondary; offer manual resume |
| 4 | OVERLOADED >10s | Reduce chunk size | Dynamically reduce `chunk_seconds` from 2→1→0.5; trade latency for throughput |
| 5 | OVERLOADED >30s | Stop realtime with explicit message | Auto-stop session; UI: "Session stopped - ASR could not keep up"; offer offline transcript generation |

### F4. Hysteresis

| Transition | Enter Threshold | Exit Threshold | Hold Time |
|------------|-----------------|----------------|-----------|
| NORMAL → BUFFERING | `fill_ratio > 0.85` OR `realtime_factor > 1.0` | N/A | Immediate |
| BUFFERING → OVERLOADED | `fill_ratio > 0.95` OR `realtime_factor > 2.0` | N/A | Immediate |
| BUFFERING → NORMAL | N/A | `fill_ratio < 0.70` AND `realtime_factor < 0.8` | 5 seconds |
| OVERLOADED → BUFFERING | N/A | `fill_ratio < 0.85` AND `realtime_factor < 1.5` AND `dropped_10s == 0` | 10 seconds |

---

## G) UI Truthfulness Mapping (V1)

### G1. Backend State + Metrics → UI State + Copy

| Backend State | Metrics | UI State | UI Copy | Indicator |
|---------------|---------|----------|---------|-----------|
| `connected` | N/A | `.starting` | "Connecting to backend..." | Spinner |
| `streaming` + NORMAL | `fill_ratio < 0.70` | `.listening` | "Listening" | Green dot |
| `streaming` + BUFFERING | `fill_ratio ≥ 0.85` | `.listening` + warning | "Processing backlog..." | Yellow dot + pulse |
| `streaming` + OVERLOADED | `fill_ratio ≥ 0.95` OR drops | `.buffering` | "Audio paused - catching up" | Yellow dot + pause icon |
| `reconnecting` | N/A | `.reconnecting` | "Reconnecting... (attempt N)" | Spinner |
| `overloaded` (explicit) | `realtime_factor > 2.0` | `.overloaded` | "Processing overloaded - reducing quality" | Orange dot |
| `error` | Any | `.error` | "Connection error: {message}" | Red dot |

### G2. Recovery Actions

| Scenario | User Action | System Response |
|----------|-------------|-----------------|
| Buffering >10s | None (auto) | Pause capture, show "Catching up...", resume when healthy |
| Overloaded with 2 sources | None (auto) | Reduce to 1 source, show toast: "Switched to single source" |
| Overloaded >30s | None (auto) | Stop session, show dialog: "Session stopped - ASR overloaded" with options: "Retry streaming", "Continue recording for offline", "Switch to 1 source" |
| Connection lost | None (auto) | Reconnect with exponential backoff (max 10s); after 3 failures, show "Connection unstable - check network" |
| Manual intervention | Click "Retry streaming" | Reset connection, clear queues, restart capture |
| Manual intervention | Click "Continue for offline" | Stop realtime ASR, continue recording to disk; transcribe post-session |

---

## H) Measurement Protocol (Mandatory, No Results)

### H1. Test Scenarios

| Scenario | Duration | Sources | Audio Profile | Pass Criteria |
|----------|----------|---------|---------------|---------------|
| A | 10 min | 1 | Speech-heavy (P360 dataset) | Zero drops; avg latency <2s; max latency <5s |
| B | 10 min | 2 | Speech-heavy (both sources) | Drops allowed if <1% of chunks; auto-reduces to 1 source if needed; avg latency <3s |
| C | 10 min | 2 | Silence-heavy (95% silent) | Zero drops (VAD should filter); avg latency <1s |

### H2. Metrics to Record

| Metric | Unit | How to Measure |
|--------|------|----------------|
| `frames_sent` | count | Client counter in `WebSocketStreamer` |
| `frames_received` | count | Server counter in `ws_live_listener` |
| `frames_dropped` | count | `state.dropped_frames` |
| `chunks_processed` | count | ASR events emitted |
| `avg_latency` | seconds | `t_received - t0` for each ASR event |
| `max_latency` | seconds | Max of above |
| `queue_fill_ratio` | 0-1 | From metrics message |
| `realtime_factor` | ratio | From metrics message |
| `memory_rss_mb` | MB | `psutil.Process().memory_info().rss / 1024 / 1024` |
| `capture_stalls` | count | Client: `onPCMFrame` not called for >100ms |

### H3. End-to-End Latency Measurement

**Without guessing:**
1. Client sends audio chunk with embedded sequence number and wall-clock timestamp
2. Server echoes timestamp in ASR event
3. Client computes: `latency = now() - echoed_timestamp`
4. **Correction for timestamp basis:** Since server timestamps are audio-time based, compare `latency` trend against wall-clock elapsed to detect drift

**Implementation:**
```python
# In soak_test.py extension
# Client tags every 100th frame with wall_clock_sent
# Server includes original wall_clock_sent in metrics
# Client computes e2e_latency = time.time() - wall_clock_sent
```

### H4. Pass/Fail Criteria Summary

| Metric | Pass | Fail |
|--------|------|------|
| Drop rate | <1% | ≥1% |
| Avg latency | <3s | ≥3s |
| Max latency | <10s | ≥10s |
| Memory growth | <50MB over 10min | ≥50MB |
| Capture stalls | 0 | >0 |
| Auto-recovery | Successful within 10s | Timeout or manual intervention required |

---

## I) Implementation Status (Updated 2026-02-11)

### PR1: Client-Side Send Timeout
**Status:** NOT STARTED ❌

**Evidence:** No timeout found on WebSocket.send() call in WebSocketStreamer.swift

---

### PR2: Pause/Resume Capture on Backpressure
**Status:** NOT STARTED ❌

**Evidence:** No pauseCapture/resumeCapture methods found in AudioCaptureManager or MicrophoneCaptureManager

---

### PR3: Auto-Reduce Sources on Overload
**Status:** NOT STARTED ❌

**Evidence:** No auto-reduce logic found in AppState.swift

---

### PR4: Cap ASR Buffer Size
**Status:** NOT STARTED ❌

**Evidence:** No max_buffer_seconds cap found in provider_faster_whisper.py or provider_voxtral_realtime.py

---

### PR5: Add NLP Timeout
**Status:** IMPLEMENTED ✅

**Evidence:**
- ws_live_listener.py:418-420: asyncio.wait_for(extract_entities, timeout=10.0)
- ws_live_listener.py:431-433: asyncio.wait_for(extract_cards, timeout=15.0)
- ws_live_listener.py:522-528: asyncio.wait_for for ASR flush timeout
- ws_live_listener.py:535-540: asyncio.wait_for for analysis task cancellation

---

### PR6: Accurate Realtime Factor
**Status:** PARTIAL ⚠️

**Evidence:**
- ✅ Accurate RTF tracking exists for degrade ladder (ws_live_listener.py:374-376): `rtf = processing_time / audio_duration`
- ✅ Metrics loop uses actual audio duration samples per source for RTF (PR6).
- The comment says "Assuming 2s chunks" but actual chunks may vary
- Client receives potentially misleading realtime_factor in metrics

---

### PR7: Explicit ASR Stall Detection
**Status:** NOT STARTED ❌

**Evidence:** No asr_stalled status or stall detection logic found

---

### PR8: Soak Test Harness Improvements
**Status:** EXISTS ✅

**Evidence:**
- tests/test_streaming_correctness.py exists (8759 bytes)
- scripts/soak_test.py exists (10152 bytes)
- May need improvements for real speech audio and automated reporting

---

### Evidence Log (2026-02-11):

```bash
# Checked PR1: Client send timeout
rg 'timeout.*send\|send.*timeout' /Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift -B 5 -A 5
# Result: No matches

# Checked PR2: Pause/resume capture
rg 'pauseCapture\|resumeCapture' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked PR3: Auto-reduce sources
rg 'reduce.*source\|switch.*primary' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked PR4: ASR buffer cap
rg 'max_buffer\|buffer.*cap\|buffer.*limit' /Users/pranay/Projects/EchoPanel/server/services/ --type py
# Result: No matches

# Checked PR5: NLP timeout
rg 'wait_for.*extract\|extract.*timeout' /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py -B 3 -A 5
# Result: Found multiple asyncio.wait_for calls with timeouts

# Checked PR6: Realtime factor
rg 'realtime_factor' /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py -B 5 -A 5
# Result: Metrics loop computes RTF from actual audio duration samples per source (processing_time / audio_duration)

# Checked PR7: ASR stall detection
rg 'asr_stalled\|stall.*detection\|last.*asr.*output' /Users/pranay/Projects/EchoPanel/server/api/ws_live_listener.py -B 3 -A 5
# Result: No matches

# Verified test files exist
ls -la /Users/pranay/Projects/EchoPanel/tests/test_streaming_correctness.py
# Exists (8759 bytes)
ls -la /Users/pranay/Projects/EchoPanel/scripts/soak_test.py
# Exists (10152 bytes)
```

**Interpretation:**
- 2 of 8 PRs are complete (PR5, PR8)
- PR6 is complete (accurate RTF exposed in metrics)
- 5 PRs are not started (PR1-4, PR7)
- Most critical gaps remain: client send blocking, no capture pause/resume, unbounded ASR buffer

---

## J) Original Patch Plan (4–8 PR-Sized Items)

### PR1: Client-Side Send Timeout
- **Impact:** H
- **Effort:** S
- **Risk:** M
- **Files:** `WebSocketStreamer.swift`
- **Change:** Add 100ms timeout to `task?.send()`; drop frame if timeout
- **Validation:** Network conditioner test (100ms latency, 10% loss)

### PR2: Pause/Resume Capture on Backpressure
- **Impact:** H
- **Effort:** M
- **Risk:** M
- **Files:** `AppState.swift`, `AudioCaptureManager.swift`, `MicrophoneCaptureManager.swift`
- **Change:** 
  - Add `pauseCapture()` / `resumeCapture()` methods
  - React to `buffering`/`overloaded` status from server
  - UI: Show "Paused - catching up" when paused
- **Validation:** Soak test with 0.5x ASR speed, verify capture pauses and resumes

### PR3: Auto-Reduce Sources on Overload
- **Impact:** M
- **Effort:** M
- **Risk:** L
- **Files:** `AppState.swift`, `SidePanelView.swift`
- **Change:**
  - When `overloaded` with 2 sources, automatically stop secondary source
  - Show toast: "Switched to {primary} only - catching up"
  - Offer "Resume both sources" button when healthy
- **Validation:** 2-source soak test with slow ASR

### PR4: Cap ASR Buffer Size
- **Impact:** H
- **Effort:** S
- **Risk:** L
- **Files:** `provider_faster_whisper.py`, `provider_voxtral_realtime.py`
- **Change:**
  - Add `max_buffer_seconds` config (default: 30s)
  - If buffer exceeds, drop oldest chunks and log warning
- **Validation:** 30-min soak with 0.5x ASR, monitor RSS

### PR5: Add NLP Timeout
- **Impact:** M
- **Effort:** S
- **Risk:** L
- **Files:** `ws_live_listener.py`
- **Change:** Wrap `asyncio.to_thread(extract_cards, ...)` in `asyncio.wait_for(timeout=10)`
- **Validation:** Inject 30s sleep in `extract_cards()`, verify timeout and continuation

### PR6: Accurate Realtime Factor
- **Impact:** M
- **Effort:** S
- **Risk:** L
- **Files:** `ws_live_listener.py`
- **Change:**
  - Track actual audio duration processed per chunk
  - Use `actual_audio_duration / infer_time` instead of `chunk_seconds / infer_time`
- **Validation:** Compare reported factor vs manual calculation

### PR7: Explicit ASR Stall Detection
- **Impact:** M
- **Effort:** M
- **Risk:** M
- **Files:** `ws_live_listener.py`, `AppState.swift`
- **Change:**
  - Server: Track time since last ASR output per source
  - Emit `{"type":"status","state":"asr_stalled"}` if >5s
  - Client: Show warning dialog with "Restart session" option
- **Validation:** Inject 10s delay in ASR, verify stall detection

### PR8: Soak Test Harness Improvements
- **Impact:** L (testing only)
- **Effort:** M
- **Risk:** L
- **Files:** `scripts/soak_test.py`
- **Change:**
  - Add real speech audio (P360 or similar)
  - Add memory monitoring
  - Add automated pass/fail report generation
- **Validation:** Run all 3 scenarios, verify reports

---

## K) Next Steps (Prioritized by Impact)

### Immediate (P0 - Critical Reliability):
1. **Implement PR1 (send timeout):** Add 100ms timeout to WebSocket.send() in WebSocketStreamer.swift
2. **Implement PR4 (ASR buffer cap):** Add max_buffer_seconds to providers to prevent OOM
3. **Implement PR6 fix (metrics realtime_factor):** Update metrics loop to use actual audio duration

### High Priority (P1):
4. **Implement PR2 (pause/resume capture):** Add capture pause on backpressure, resume when healthy
5. **Implement PR7 (ASR stall detection):** Add stall detection when no ASR output for 5s

### Medium Priority (P2):
6. **Implement PR3 (auto-reduce sources):** Automatically stop secondary source when overloaded
7. **Improve PR8 (soak test):** Add real speech audio and automated reporting

### Suggested Work Order:
- Week 1: PR1 + PR4 + PR6 fix (prevent crashes and improve metrics accuracy)
- Week 2: PR2 + PR7 (add backpressure awareness)
- Week 3: PR3 + PR8 improvements (polish and testing)

---

## L) Summary

### Current State (Observed)

1. **Queues are small and drop oldest** — prevents unbounded growth but loses audio
2. **No client-side backpressure** — capture continues even when server is drowning
3. **ASR buffer is unbounded** — risk of OOM on long sessions with slow ASR
4. **Metrics RTF uses actual audio duration** — `realtime_factor` computed from processing_time/audio_duration samples per source
5. **Single inference lock** — dual-source sessions contend for ASR
6. **Reconnection has exponential backoff** — good, but no ultimate give-up

### Critical Gaps

| Gap | Severity | PR Addressing |
|-----|----------|---------------|
| Client capture doesn't pause on overload | HIGH | PR2 |
| ASR buffer unbounded | HIGH | PR4 |
| WebSocket send can block indefinitely | HIGH | PR1 |
| No explicit ASR stall detection | MEDIUM | PR7 |
| NLP can hang indefinitely | MEDIUM | PR5 |
| Dual-source not auto-reduced | MEDIUM | PR3 |
| Metrics accuracy | MEDIUM | PR6 |

---

*End of Audit*
