> **⚠️ OBSOLETE (2026-02-16):** Descriptive audit of flows AP-001 through AP-008, all marked "Implemented".
> Code evidence: `applyLimiter()` in both `AudioCaptureManager.swift:398` and `MicrophoneCaptureManager.swift:324`,
> `NSLock` thread safety in both managers, PCM16 16kHz mono chunking, `RedundantAudioCaptureManager.swift` failover,
> `DeviceHotSwapManager.swift` with timeout + observer cleanup. No open action items.
> Moved to archive.

# Audio Pipeline Audit — EchoPanel

**Date:** 2026-02-11  
**Auditor:** Audio Pipeline Analyst  
**Scope:** Internal flows: audio detection → source identification → capture → buffering → VAD → diarization → ASR → post-processing  
**Flow IDs:** AP-001 through AP-008

---

## Executive Summary

EchoPanel implements a multi-source audio pipeline supporting three capture paths: system audio via ScreenCaptureKit, microphone via AVAudioEngine, and file input (future). The pipeline supports three ASR backends (faster_whisper, voxtral_realtime, whisper_cpp) with Silero VAD preprocessing and Pyannote speaker diarization.

**Key findings:**
- Dual-path redundancy with automatic failover (AP-003) is fully implemented
- VAD preprocessing reduces inference load by skipping silent chunks (AP-005)
- Speaker diarization requires batch processing at session end (AP-006)
- WebSocket streaming protocol delivers partial/final results with sub-second latency (AP-008)
- Sample rate standardization to 16kHz mono PCM16 occurs at capture layer (AP-001, AP-002)

---

## Flow AP-001: Microphone Capture Pipeline

**Status:** ✅ Implemented | **Evidence:** `MicrophoneCaptureManager.swift:1-192`

### Trigger(s)
- User initiates recording session via UI (`startCapture()` called)
- RedundantAudioCaptureManager starts backup path (AP-003)

### Preconditions
1. `AVCaptureDevice.requestAccess(for: .audio)` returns `.authorized`
2. Audio session configured for input-only operation

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Request audio input format | `inputNode.outputFormat(forBus: 0)` | - |
| 2 | Configure target format (16kHz mono Float32) | `MicrophoneCaptureManager:48` | - |
| 3 | Create AVAudioConverter | `MicrophoneCaptureManager:53` | - |
| 4 | Install tap on input node | `MicrophoneCaptureManager:57-59` | Callback on audio thread |
| 5 | Convert buffer to target format | `MicrophoneCaptureManager:84-92` | Per-buffer |
| 6 | Apply soft limiter (P0-2 fix) | `MicrophoneCaptureManager:102` | Prevents clipping |
| 7 | Update RMS level for UI | `MicrophoneCaptureManager:105,119` | EMA-weighted |
| 8 | Emit PCM16 frames (320 samples = 20ms) | `MicrophoneCaptureManager:157-184` | 50 fps |

### Inputs/Outputs

**Input:**
- Native device format (varies, typically 44.1kHz or 48kHz, stereo)

**Output:**
- Format: PCM16 mono
- Sample Rate: 16000 Hz
- Frame Size: 320 samples (20ms)
- Byte Size: 640 bytes per frame

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `AVAudioEngine.inputNode` | macOS Core Audio | Raw audio input |
| `AVAudioConverter` | `MicrophoneCaptureManager:53` | Sample rate/format conversion |
| `applyLimiter()` | `MicrophoneCaptureManager:124-155` | Soft limiting to prevent hard clipping |
| `emitPCMFrames()` | `MicrophoneCaptureManager:157-184` | Frame chunking for streaming |
| `onPCMFrame` callback | `MicrophoneCaptureManager:7` | Delivers data to redundancy manager |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Permission denied | User denied mic access | `requestPermission()` returns false | UI shows error, path disabled |
| Converter creation failed | Unsupported format | `converter == nil` | Throws `MicCaptureError.converterCreationFailed` |
| Engine start failed | Audio session error | `audioEngine.start()` throws | Error propagated to caller |
| Tap removed mid-stream | Device change | `isRunning` flag checked | Stop called, state reset |
| Buffer overrun | High CPU load | Callback backlog | Frames dropped silently |

### Observability

```swift
// Available callbacks
onPCMFrame: ((Data, String) -> Void)?    // (frame, source="mic")
onAudioLevelUpdate: ((Float) -> Void)?   // RMS level
onError: ((Error) -> Void)?              // Error propagation
```

### Latency Budget
- **Capture to callback:** < 10ms (audio thread callback)
- **Format conversion:** < 1ms per buffer
- **Limiter processing:** < 0.5ms per 20ms frame
- **Frame emission:** Immediate (async)

### Performance Hotspots
- `AVAudioConverter.convert()` per buffer (mandatory)
- EMA calculation for level tracking (minimal)

---

## Flow AP-002: System Audio Capture Pipeline (ScreenCaptureKit)

**Status:** ✅ Implemented | **Evidence:** `AudioCaptureManager.swift:1-381`

### Trigger(s)
- User initiates broadcast/recording session via `startCapture()`
- Screen Recording permission granted

### Preconditions
1. `CGRequestScreenCaptureAccess()` returns true (macOS 13+)
2. Display available for capture
3. `ScreenCaptureKit` framework available

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Request/verify permissions | `AudioCaptureManager:61-66` | - |
| 2 | Get shareable content | `AudioCaptureManager:73` | Includes displays |
| 3 | Create content filter (excludes own audio) | `AudioCaptureManager:80` | - |
| 4 | Configure stream (audio=true, excludesSelf=true) | `AudioCaptureManager:81-84` | - |
| 5 | Create SCStream with delegate | `AudioCaptureManager:85-86` | - |
| 6 | Add stream outputs (screen + audio) | `AudioCaptureManager:88-89` | - |
| 7 | Start capture | `AudioCaptureManager:90` | - |
| 8 | Callback: process CMSampleBuffer | `AudioCaptureManager:106` | Per audio buffer |
| 9 | Extract format, create AVAudioFormat | `AudioCaptureManager:107-116` | - |
| 10 | Convert to target (16kHz mono Float32) | `AudioCaptureManager:147-183` | Via AVAudioConverter |
| 11 | Apply limiter (P0-2 fix) | `AudioCaptureManager:210` | Prevent clipping |
| 12 | Update quality metrics | `AudioCaptureManager:212,286-340` | EMA-weighted |
| 13 | Emit PCM16 frames (320 samples) | `AudioCaptureManager:213,255-283` | 50 fps |

### Inputs/Outputs

**Input:**
- Format: Varies (typically 44.1kHz/48kHz, stereo Float32)
- Source: ScreenCaptureKit `CMSampleBuffer`

**Output:**
- Format: PCM16 mono
- Sample Rate: 16000 Hz
- Frame Size: 320 samples (20ms)
- Byte Size: 640 bytes per frame
- Source Tag: `"system"`

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `SCShareableContent` | `AudioCaptureManager:73` | Get available displays |
| `SCContentFilter` | `AudioCaptureManager:80` | Filter captured content |
| `SCStreamConfiguration.capturesAudio` | `AudioCaptureManager:82` | Enable audio capture |
| `SCStreamConfiguration.excludesCurrentProcessAudio` | `AudioCaptureManager:83` | Avoid feedback loop |
| `AudioSampleHandler` | `AudioCaptureManager:343-375` | SCStreamOutput delegate |
| `applyLimiter()` | `AudioCaptureManager:222-253` | Soft limiting |
| `emitPCMFrames()` | `AudioCaptureManager:255-283` | Frame chunking with remainder buffer |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Permission denied | User rejected Screen Recording | `CGPreflightScreenCaptureAccess()` | Throws `CaptureError` |
| No display found | Headless system | `content.displays` empty | Throws `CaptureError.noDisplay` |
| Unsupported OS | macOS < 13 | `#available(macOS 13, *)` check | Throws `CaptureError.unsupportedOS` |
| Converter creation failed | Format incompatibility | `converter == nil` | Logs error, drops buffer |
| Stream output add failed | Internal SCStream error | Exception from `addStreamOutput()` | Propagates to caller |
| Audio buffer without data | Corrupted CMSampleBuffer | Format description check fails | Buffer dropped |

### Observability

```swift
// Available callbacks
onPCMFrame: ((Data, String) -> Void)?    // (frame, source="system")
onAudioQualityUpdate: ((AudioQuality) -> Void)?  // .good/.ok/.poor
onAudioLevelUpdate: ((Float) -> Void)?   // RMS level
onSampleCount: ((Int) -> Void)?         // Total samples processed
onScreenFrameCount: ((Int) -> Void)?     // Screen frames received
```

### Latency Budget
- **SCStream to callback:** 16-33ms (at 30-60fps video)
- **Format conversion:** 1-5ms depending on buffer size
- **Limiter + quality:** < 1ms
- **Frame emission:** Immediate

### Performance Hotspots
- `CMSampleBufferCopyPCMDataIntoAudioBufferList()` (mandatory copy)
- `AVAudioConverter.convert()` per buffer
- EMA calculations for quality metrics (minimal)

---

## Flow AP-003: Redundant Audio Capture with Auto-Failover

**Status:** ✅ Implemented | **Evidence:** `RedundantAudioCaptureManager.swift:1-490`

### Trigger(s)
- User enables "Dual-Path Audio" in settings (`useRedundantAudio = true`)
- `startRedundantCapture()` called on session start

### Preconditions
1. Primary (system audio) permission granted
2. Backup (microphone) permission granted
3. `RedundantAudioCaptureManager` initialized

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Start primary capture (system) | `RedundantAudioCaptureManager:141-146` | Async |
| 2 | Start backup capture (mic) | `RedundantAudioCaptureManager:149-155` | Async |
| 3 | Set active source to primary | `RedundantAudioCaptureManager:158` | Default |
| 4 | Start quality monitoring timer | `RedundantAudioCaptureManager:159,284-289` | 100ms intervals |
| 5 | Primary PCM frame arrives | `RedundantAudioCaptureManager:235-244` | 50 fps |
| 6 | Update primary silence duration | `RedundantAudioCaptureManager:239` | Reset to 0 |
| 7 | Emit if primary is active | `RedundantAudioCaptureManager:242-243` | Source check |
| 8 | Backup PCM frame arrives | `RedundantAudioCaptureManager:260-269` | 50 fps |
| 9 | Emit if backup is active | `RedundantAudioCaptureManager:267-268` | Source check |
| 10 | Quality check timer fires | `RedundantAudioCaptureManager:297-324` | 100ms |
| 11 | Check silence duration | `RedundantAudioCaptureManager:308` | > 2s threshold |
| 12 | Check quality (clipping/silence) | `RedundantAudioCaptureManager:309` | `.poor` quality |
| 13 | If failover criteria met | `RedundantAudioCaptureManager:311-316` | Primary→Backup |
| 14 | Perform failover | `RedundantAudioCaptureManager:326-347` | Updates state, logs |

### Inputs/Outputs

**Inputs:**
- Primary: PCM16 frames from `AudioCaptureManager` (source="system")
- Backup: PCM16 frames from `MicrophoneCaptureManager` (source="mic")

**Outputs:**
- PCM16 frames via `onPCMFrame((Data, String))`
- Source tag reflects active path ("system" or "mic")
- Failover events via `onSourceChanged()` callback

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `RedundantAudioSource` enum | `RedundantAudioCaptureManager:6-16` | Primary/Backup |
| `startRedundantCapture()` | `RedundantAudioCaptureManager:136-162` | Initialize both paths |
| `qualityMonitorTimer` | `RedundantAudioCaptureManager:80,284-289` | 100ms quality checks |
| `failoverSilenceThreshold` | `RedundantAudioCaptureManager:89` | 2.0 seconds |
| `failoverClipThreshold` | `RedundantAudioCaptureManager:90` | 0.1 (10% clipping) |
| `performFailover()` | `RedundantAudioCaptureManager:326-347` | Execute switch |
| `FailoverEvent` | `RedundantAudioCaptureManager:98-111` | Audit trail |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Primary fails to start | SC permission denied | Exception in `startCapture()` | Continue with backup only |
| Backup fails to start | Mic permission denied | Exception in `startCapture()` | Continue with primary only |
| Both fail | No permissions | Both exceptions | Session cannot start |
| Failover loop | Alternating quality | Check `timeSinceBackup < 1.0` | Requires both sources healthy |
| Backup source also silent | Room truly silent | Both sources show silence | No failover triggered |
| Quality monitoring stalls | Timer thread blocked | `lastFrame` timestamps age | Manual switch available |

### Observability

```swift
// Published state
@Published var activeSource: RedundantAudioSource
@Published var isRedundancyActive: Bool
@Published var primaryQuality: AudioQuality
@Published var backupQuality: AudioQuality
@Published var failoverEvents: [FailoverEvent]

// Callbacks
var onPCMFrame: ((Data, String) -> Void)?
var onSourceChanged: ((RedundantAudioSource) -> Void)?
var onHealthChanged: ((RedundancyHealth) -> Void)?
```

### Latency Budget
- **Failover detection:** 100ms (quality check interval) + 2s (silence threshold) = 2.1s max
- **Failover execution:** Immediate on timer fire
- **Frame emission after switch:** First frame from new source emitted immediately

### Performance Hotspots
- Quality monitoring timer (100ms, minimal overhead)
- Dual capture increases CPU/GPU usage ~2x
- Memory: Two PCM buffers simultaneously

---

## Flow AP-004: WebSocket Audio Upload (Client → Server)

**Status:** ✅ Implemented | **Evidence:** `ws_live_listener.py:584-833`

### Trigger(s)
- Client receives PCM16 frames from capture layer
- Client WebSocket connected to `/ws/live-listener`
- Client sends `{"type": "audio", "data": <base64>, "source": "system"}` messages

### Preconditions
1. WebSocket connection established and authenticated
2. Session started via `{"type": "start"}` message
3. Concurrency controller initialized

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Receive audio message | `ws_live_listener.py:614` | WebSocket receive |
| 2 | Parse message, extract base64 data | `ws_live_listener.py:616-618` | - |
| 3 | Get/create source-specific queue | `ws_live_listener.py:243-247` | Per-source queue |
| 4 | Concurrency controller check | `ws_live_listener.py:297-304` | Backpressure |
| 5 | Submit chunk to controller | `ws_live_listener.py:307` | Async |
| 6 | Add to queue (or drop oldest) | `ws_live_listener.py:315-318` | FIFO |
| 7 | Track metrics | `ws_live_listener.py:321-323` | Bytes received |
| 8 | Send backpressure warning if needed | `ws_live_listener.py:326-333` | Throttled |
| 9 | ASR loop picks up chunk | `_asr_loop()` in separate task | Next iteration |

### Inputs/Outputs

**Input (from client):**
```json
{
  "type": "audio",
  "data": "<base64-encoded PCM16>",
  "source": "system" | "mic"
}
```

**Internal:**
- Queue: `asyncio.Queue(maxsize=48)` per source
- Format: Raw PCM16 bytes (no header)

**Output:**
- Chunks consumed by `_pcm_stream()` async iterator
- Metrics incremented via `metrics_registry`

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `get_queue()` | `ws_live_listener.py:243-247` | Source-specific queue |
| `put_audio()` | `ws_live_listener.py:250-342` | Backpressure handling |
| `ConcurrencyController` | `concurrency_controller.py` | Rate limiting, drop logic |
| `_pcm_stream()` | `ws_live_listener.py:344-350` | Async iterator for ASR |
| `_asr_loop()` | `ws_live_listener.py:353-409` | Per-source ASR task |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Queue full | Producer faster than consumer | `asyncio.QueueFull` | Drop oldest, warn client |
| Extreme load | Controller overload | `should_drop_source()` | Drop entire source temporarily |
| Invalid base64 | Malformed message | `base64.b64decode()` exception | Close connection |
| Unknown source | Invalid source string | `_normalize_source()` | Default to "system" |
| WebSocket disconnected | Network issue | `RuntimeError` on send | Session cleanup |

### Observability

```python
# Metrics tracked
audio_bytes_total{source}
audio_frames_dropped{source}
queue_depth{source}
# Status events sent to client
{"type": "status", "state": "backpressure", "message": "...", "dropped_frames": n}
```

### Latency Budget
- **WebSocket receive to queue:** < 5ms typically
- **Queue to ASR consumption:** Variable (depends on ASR speed)
- **Backpressure warning:** First drop triggers warning

### Performance Hotspots
- Base64 decoding (CPU-bound, minimal for modern hardware)
- Queue operations (lock-free asyncio.Queue)
- Concurrency controller checks (minimal overhead)

---

## Flow AP-005: VAD Pre-Filtering (Silence Skipping)

**Status:** ✅ Implemented | **Evidence:** `vad_asr_wrapper.py:1-482`

### Trigger(s)
- ASR pipeline processes audio stream
- VAD enabled in config (`vad_enabled=True`)

### Preconditions
1. Silero VAD model loaded (lazy-loaded from `snakers4/silero-vad`)
2. `torch` available
3. Sample rate is 8000 or 16000 Hz

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Check VAD availability | `vad_asr_wrapper.py:151-162` | Lazy load |
| 2 | Buffer incoming chunks | `vad_asr_wrapper.py:247` | Accumulates to chunk_seconds |
| 3 | Process complete chunks | `vad_asr_wrapper.py:254-306` | While len(buffer) >= chunk_bytes |
| 4 | Convert PCM16 → Float32 | `vad_asr_wrapper.py:164-169` | Normalize to [-1.0, 1.0] |
| 5 | Run Silero VAD inference | `vad_asr_wrapper.py:270-272` | Thread executor |
| 6 | Get speech timestamps | `vad_asr_wrapper.py:185-202` | Silero utility |
| 7 | If speech detected | `vad_asr_wrapper.py:274-296` | Pass to ASR |
| 8 | Update VAD stats | `vad_asr_wrapper.py:264-265,298-299` | Frames counts |
| 9 | If silence detected | `vad_asr_wrapper.py:297-306` | Skip ASR, update stats |
| 10 | Estimate time saved | `vad_asr_wrapper.py:301-302` | 500ms per skipped chunk |

### Inputs/Outputs

**Input:**
- Format: PCM16 bytes
- Chunk Size: 640 bytes (20ms at 16kHz) × chunk_seconds (default: 2s = 12800 chunks)
- Accumulated in `bytearray` buffer

**Output:**
- Speech chunks: Passed to underlying ASR provider
- Silence chunks: Dropped (not forwarded)
- Statistics: `VADStats` with ratios and counts

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `_load_vad_model()` | `vad_asr_wrapper.py:49-67` | Lazy load Silero |
| `Silero VAD` | `torch.hub.load()` | VAD model |
| `_pcm_to_float()` | `vad_asr_wrapper.py:164-169` | PCM16 → Float32 |
| `_has_speech()` | `vad_asr_wrapper.py:171-207` | VAD inference |
| `VADStats` | `vad_asr_wrapper.py:70-104` | Statistics tracking |
| `SmartVADRouter` | `vad_asr_wrapper.py:363-430` | Dynamic enable/disable |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| VAD model load fails | Network/missing torch | `torch.hub.load()` exception | Fall back to passthrough |
| VAD false positive | Noise triggers speech | `threshold` too low | Adjust threshold (default 0.5) |
| VAD false negative | Quiet speech missed | `threshold` too high | Adjust threshold |
| Sample rate mismatch | 44.1kHz input | Warning logged | Resample before VAD |
| Executor busy | High concurrency | `run_in_executor` queue | Async delays |

### Observability

```python
# VAD statistics
{
    "total_frames": int,
    "speech_frames": int,
    "silence_frames": int,
    "silence_ratio": float,  # e.g., 0.65 for 65% silence
    "skipped_chunks": int,
    "processed_chunks": int,
    "skip_rate": float,
    "infer_time_saved_ms": float,
}
# Log output (debug)
"VAD: skipped N silent chunks (ratio: XX%)"
```

### Latency Budget
- **VAD inference:** 5-20ms per 2s chunk (CPU)
- **Chunk processing overhead:** ~1ms
- **Total overhead:** ~6-21ms per 2s chunk (vs ASR inference 500ms+)
- **Time saved:** ~500ms per silent chunk

### Performance Hotspots
- Silero VAD inference (CPU-bound, but 20-100x faster than ASR)
- Thread executor for sync VAD call
- Buffer accumulation delays VAD by chunk_seconds

---

## Flow AP-006: Speaker Diarization (Pyannote)

**Status:** ✅ Implemented (Batch) | **Evidence:** `diarization.py:1-215`

### Trigger(s)
- Session ends or periodic diarization triggered
- `diarize_pcm()` called with accumulated audio

### Preconditions
1. `pyannote.audio` installed
2. `torch` available
3. `numpy` available
4. `ECHOPANEL_HF_TOKEN` environment variable set (HuggingFace auth)

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Check availability | `diarization.py:43-48` | Token + deps check |
| 2 | Load pipeline (lazy) | `diarization.py:51-81` | `pyannote/speaker-diarization-3.1` |
| 3 | Device selection | `diarization.py:69-76` | MPS > CUDA > CPU |
| 4 | Convert PCM16 → Float32 | `diarization.py:153` | Normalize |
| 5 | Convert to torch tensor | `diarization.py:154` | Unsqueeze for batch |
| 6 | Run diarization pipeline | `diarization.py:156` | Batch inference |
| 7 | Collect raw segments | `diarization.py:159-164` | (turn, track, speaker) |
| 8 | Merge adjacent segments | `diarization.py:84-114` | Same speaker, <0.5s gap |
| 9 | Assign friendly names | `diarization.py:117-132` | SPEAKER_00 → "Speaker 1" |
| 10 | Merge with transcript | `diarization.py:183-214` | Time-overlap matching |

### Inputs/Outputs

**Input:**
- Format: PCM16 bytes
- Sample Rate: 16000 Hz (configurable)
- Accumulated audio buffer (max: `diarization_max_bytes`)

**Output:**
```python
[
    {"t0": 0.0, "t1": 5.5, "speaker": "Speaker 1"},
    {"t0": 5.5, "t1": 12.3, "speaker": "Speaker 2"},
    # ...
]
```

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `_get_pipeline()` | `diarization.py:51-81` | Lazy load with device routing |
| `pyannote/speaker-diarization-3.1` | HuggingFace model | Diarization model |
| `_merge_adjacent_segments()` | `diarization.py:84-114` | Reduce fragmentation |
| `_assign_speaker_names()` | `diarization.py:117-132` | User-friendly labels |
| `merge_transcript_with_speakers()` | `diarization.py:183-214` | Attach to transcript |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Missing HF token | `ECHOPANEL_HF_TOKEN` not set | `_get_pipeline()` returns None | Diarization skipped |
| Pyannote not installed | Import exception | `Pipeline is None` | Skip with debug log |
| No audio buffer | Session too short | `pcm_bytes` empty | Return empty list |
| GPU OOM | Large session, limited GPU | `torch` exception | Fallback to CPU |
| Model load fails | Network/auth issue | Exception in `from_pretrained()` | Skip, log error |

### Observability

```python
# Log output (debug)
"Diarization found N raw segments"
"Diarization produced M segments after merging"
# Return value count
len(diarization_result)  # Number of speaker segments
```

### Latency Budget
- **Pipeline initialization:** 2-11s (first session, model load)
- **Diarization inference:** ~RTF 1.0-3x (depends on audio length, device)
- **Total session processing:** Audio duration × RTF

### Performance Hotspots
- `pyannote/speaker-diarization-3.1` inference (majority of time)
- GPU memory for long sessions (O(audio_duration))
- Batched processing (must accumulate audio first)

---

## Flow AP-007: ASR Provider Pipeline (faster_whisper)

**Status:** ✅ Implemented | **Evidence:** `provider_faster_whisper.py:1-308`

### Trigger(s)
- `stream_asr()` called from `_asr_loop()`
- Provider selected via `ASRProviderRegistry`

### Preconditions
1. `faster_whisper` installed
2. `numpy` available
3. Model downloaded (CTranslate2 format)
4. Chunk buffer accumulated

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | Get provider instance | `asr_stream.py:55` | Registry lookup |
| 2 | Get/load model | `provider_faster_whisper.py:76-111` | Lazy load |
| 3 | Buffer chunks | `provider_faster_whisper.py:124-127` | Accumulate to chunk_seconds |
| 4 | Process complete chunks | `provider_faster_whisper.py:148-210` | While len(buffer) >= chunk |
| 5 | Convert PCM16 → Float32 | `provider_faster_whisper.py:161` | Normalize |
| 6 | Run faster_whisper inference | `provider_faster_whisper.py:163-174` | Thread executor |
| 7 | Extract segments | `provider_faster_whisper.py:187-209` | Parse results |
| 8 | Compute confidence | `provider_faster_whisper.py:192-195` | From avg_logprob |
| 9 | Emit final segments | `provider_faster_whisper.py:200-209` | Only final (no partials) |
| 10 | Process remaining buffer | `provider_faster_whisper.py:212-276` | At stream end |
| 11 | Skip too-small final chunks | `provider_faster_whisper.py:225-228` | < 0.5s |
| 12 | Skip low-energy final chunks | `provider_faster_whisper.py:232-236` | < 0.01 RMS |
| 13 | Filter low-confidence | `provider_faster_whisper.py:261-263` | < 0.3 + < 3 words |

### Inputs/Outputs

**Input:**
- Format: PCM16 bytes from `_pcm_stream()`
- Chunk Size: `config.chunk_seconds` (default: 4s = 64000 bytes)
- Sample Rate: 16000 Hz

**Output:**
```python
ASRSegment(
    text: str,
    t0: float,       # Start time (seconds)
    t1: float,       # End time (seconds)
    confidence: float,  # 0.0-1.0
    is_final: bool,     # Always True (no partials)
    source: Optional[AudioSource],
    language: Optional[str],
)
```

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `_get_model()` | `provider_faster_whisper.py:76-111` | Model loading with device routing |
| `WhisperModel.transcribe()` | `provider_faster_whisper.py:167-171` | Core inference |
| `_infer_lock` | `provider_faster_whisper.py:47` | Serialize concurrent calls |
| `health()` | `provider_faster_whisper.py:279-303` | RTF and latency metrics |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| Model not available | Missing faster_whisper | `is_available` check | Fallback message emitted |
| GPU/CUDA error | Driver issue | `WhisperModel()` exception | Falls back to CPU |
| VAD filter failure | VAD exception | Logs warning | Continues with speech assumed |
| Chunk too small | Buffer underflow | `len(buffer) < chunk_bytes` | Accumulates more |
| Low confidence filter | Noise/hallucination | `confidence < 0.3` | Drops segment |
| Language mismatch | Wrong language set | Transcription fails | Provider handles or auto-detects |

### Observability

```python
# Health metrics
{
    "realtime_factor": float,  # < 1.0 is real-time
    "avg_infer_ms": float,
    "p95_infer_ms": float,
    "p99_infer_ms": float,
    "model_resident": bool,
    "chunks_processed": int,
}
# Log output
"Processing chunk #N, X bytes, t=Y-Zs"
"Transcribed M segments in Xms, language=en"
```

### Latency Budget
- **Model load (first chunk):** 2-10s (model initialization)
- **Inference per 4s chunk:** 500ms - 4s (depends on model size, device)
- **Total RTF:** 0.3x - 2.0x (model/device dependent)
- **Throughput:** 2-30x real-time (faster-whisper optimized)

### Performance Hotspots
- `WhisperModel.transcribe()` (dominant cost)
- Thread executor (prevents blocking event loop)
- Lock serialization (prevents OOM on GPU)

---

## Flow AP-008: WebSocket Streaming Protocol (Server → Client)

**Status:** ✅ Implemented | **Evidence:** `ws_live_listener.py:584-833`

### Trigger(s)
- ASR loop yields segment events
- Analysis completes
- Metrics update interval fires

### Preconditions
1. WebSocket connected and authenticated
2. Session started
3. ASR/analysis tasks running

### Step-by-Step Sequence

| Step | Action | Component | Timing |
|------|--------|-----------|--------|
| 1 | ASR yields segment | `_asr_loop()` in `ws_live_listener.py:361` | Per segment |
| 2 | Calculate RTF metrics | `ws_live_listener.py:373-391` | Per final segment |
| 3 | Append to transcript | `ws_live_listener.py:397` | Session state |
| 4 | Send via WebSocket | `ws_live_listener.py:399` | `ws_send()` |
| 5 | Analysis timer fires | `_analysis_loop()` in `ws_live_listener.py:411` | 12s/28s intervals |
| 6 | Run entity extraction | `ws_live_listener.py:418-420` | Thread, 10s timeout |
| 7 | Send entities update | `ws_live_listener.py:422` | `ws_send()` |
| 8 | Metrics timer fires | `_metrics_loop()` in `ws_live_listener.py:481` | 1s intervals |
| 9 | Calculate queue depth | `ws_live_listener.py:490-493` | Per source |
| 10 | Send metrics update | `ws_live_listener.py:570` | `ws_send()` |

### Inputs/Outputs

**Input (from ASR):**
```python
{
    "type": "asr_partial" | "asr_final",
    "t0": float,
    "t1": float,
    "text": str,
    "stable": bool,  # True for final
    "confidence": float,
    "source": str,   # "system" | "mic"
    "language": str, # e.g., "en"
}
```

**Output (to client):**
- JSON messages via WebSocket text frame
- UTF-8 encoded

### Key Modules/Functions/Events

| Item | Location | Purpose |
|------|----------|---------|
| `ws_send()` | `ws_live_listener.py:185-194` | Thread-safe send with error handling |
| `_asr_loop()` | `ws_live_listener.py:353-409` | Per-source ASR task |
| `_analysis_loop()` | `ws_live_listener.py:411-447` | Entity/card extraction |
| `_metrics_loop()` | `ws_live_listener.py:481-570` | Health monitoring |
| `DegradeLadder` | `ws_live_listener.py:72` | Adaptive performance |

### Failure Modes

| Mode | Trigger | Detection | Recovery |
|------|---------|-----------|----------|
| WebSocket disconnected | Client closed | `RuntimeError` on send | Session cleanup |
| Send buffer full | Slow client | `RuntimeError` | Mark closed, stop sending |
| JSON encode error | Invalid segment | Exception in `json.dumps()` | Skip, log error |
| Analysis timeout | NLP model slow | 10-15s timeout | Skip cycle, warn client |
| Degrade ladder error | RTF > 1.0 | `DegradeLadder.check()` | Apply mitigations |

### Observability

```python
# Status events
{"type": "status", "state": "connected", ...}
{"type": "status", "state": "backpressure", ...}
{"type": "status", "state": "buffering", ...}
{"type": "status", "state": "overloaded", ...}
# Metrics
{"type": "metrics", "queue_depth": int, "rtf": float, ...}
# Transcript
{"type": "asr_final", "t0": 0.0, "t1": 4.2, "text": "Hello", ...}
# Analysis
{"type": "entities_update", "entities": {...}}
{"type": "cards_update", "actions": [...], "decisions": [...]}
```

### Latency Budget
- **ASR to send:** < 10ms (same event loop iteration)
- **WebSocket transmit:** Network-dependent (typically < 50ms)
- **Analysis to send:** 10-15s timeout + processing time
- **Metrics:** 1s intervals (batched)

### Performance Hotspots
- `json.dumps()` per message (minimal)
- `ws_send()` lock contention (unlikely with single client)
- Analysis thread blocking (mitigated by timeout)

---

## Latency Budget Summary

| Component | Min | Typical | Max | Notes |
|-----------|-----|---------|-----|-------|
| Mic capture callback | < 1ms | 2-5ms | 10ms | Audio thread priority |
| System audio callback | < 1ms | 5-10ms | 33ms | Sync with screen refresh |
| Redundancy failover | 100ms | 2.1s | 5s | Timer + silence threshold |
| WebSocket upload | < 1ms | 5ms | 100ms | Network dependent |
| VAD preprocessing | 5ms | 10ms | 20ms | Per 2s chunk |
| **faster_whisper (base.en)** | 100ms | 500ms | 2s | Per 4s chunk, GPU |
| **faster_whisper (large-v3)** | 500ms | 2s | 8s | Per 4s chunk, GPU |
| **voxtral_realtime** | 50ms | 200ms | 500ms | Streaming mode |
| Pyannote diarization | 2s | RTF 1-3x | 10s | Session end only |
| **Total E2E (good)** | 400ms | 800ms | 2s | Mic → WebSocket |
| **Total E2E (degraded)** | 2s | 4s | 10s | Large model + GPU load |

---

## Provider Comparison

| Provider | RTF | VAD | Diarization | GPU | Notes |
|----------|-----|-----|-------------|-----|-------|
| faster_whisper | 0.3-1.0x | ✅ Built-in | ❌ | CUDA | Most tested |
| voxtral_realtime | 0.5-1.5x | ❌ | ❌ | MPS/BLAS | Streaming mode |
| whisper_cpp | 0.5-1.5x | ❌ | ❌ | CPU only | Legacy |

---

## Files Inspected

| File | Purpose |
|------|---------|
| `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift` | System audio via ScreenCaptureKit |
| `macapp/MeetingListenerApp/Sources/RedundantAudioCaptureManager.swift` | Dual-path redundancy |
| `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift` | Mic via AVAudioEngine |
| `macapp/MeetingListenerApp/Sources/BroadcastFeatureManager.swift` | NTP, hotkeys, confidence |
| `server/services/asr_stream.py` | ASR pipeline entry |
| `server/services/asr_providers.py` | Provider abstraction |
| `server/services/vad_asr_wrapper.py` | Silero VAD integration |
| `server/services/diarization.py` | Pyannote speaker diarization |
| `server/services/provider_faster_whisper.py` | Faster-Whisper backend |
| `server/services/provider_voxtral_realtime.py` | Voxtral streaming backend |
| `server/api/ws_live_listener.py` | WebSocket handler |

---

## Recommendations

### High Priority

1. **AP-005 VAD Integration Consistency**
   - VAD is optional in `asr_stream.py` config but not all providers support it uniformly
   - Recommendation: Standardize VAD usage or clarify which providers include VAD

2. **AP-006 Diarization Batch Limitation**
   - Speaker diarization only at session end prevents real-time speaker labels
   - Recommendation: Add real-time diarization option with lower accuracy/speed tradeoff

### Medium Priority

3. **AP-003 Failover Configuration**
   - Hardcoded thresholds (2s silence, 10% clipping) may not suit all use cases
   - Recommendation: Expose as UserDefaults settings

4. **AP-008 Metrics Granularity**
   - RTF calculated only every 5 chunks, may miss transient issues
   - Recommendation: Per-chunk RTF with exponential averaging

### Low Priority

5. **AP-007 Provider Health Check**
   - First chunk warm-up not tracked in health metrics
   - Recommendation: Add "cold_start" metric

---

## Status Summary

| Flow | Status | Confidence |
|------|--------|------------|
| AP-001: Microphone Capture | ✅ Implemented | High |
| AP-002: System Audio Capture | ✅ Implemented | High |
| AP-003: Redundant Capture | ✅ Implemented | High |
| AP-004: WebSocket Upload | ✅ Implemented | High |
| AP-005: VAD Pre-Filtering | ✅ Implemented | High |
| AP-006: Speaker Diarization | ✅ Implemented | Medium (batch only) |
| AP-007: ASR Provider (faster_whisper) | ✅ Implemented | High |
| AP-008: WebSocket Streaming | ✅ Implemented | High |
