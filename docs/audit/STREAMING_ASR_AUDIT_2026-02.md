# EchoPanel Streaming ASR/NLP Audit Report

**Date**: February 2026  
**Scope**: Client-side capture → WebSocket transport → ASR → NLP → diarization  
**Status**: P0 issues fixed, P1/P2 issues documented

---

## Executive Summary

This audit identified **3 P0 (critical)** issues that would prevent the streaming ASR system from functioning, **5 P1 (high)** reliability issues, and **4 P2 (medium)** quality issues.

### Fixed in this PR

| Issue | Description | Status |
|-------|-------------|--------|
| P0-1 | `_pcm_stream()` function was undefined | ✅ Fixed |
| P0-2 | ASR task spawn logic was broken | Already fixed (started_sources) |
| P0-3 | CTranslate2/float16 on CPU crashes | ✅ Fixed (int8 fallback) |
| P1-2 | Stop semantics: ASR flush after analysis cancel | ✅ Fixed (order swapped) |
| P1-3 | Queue drop policy silent | ✅ Fixed (logging added) |
| Race | WebSocket send after close | ✅ Fixed (closed flag) |

---

## 1. Architecture Map

### Dataflow

```
┌────────────────────────────────────────────────────────────────────┐
│                         macOS Client                                │
├────────────────────────────────────────────────────────────────────┤
│ ScreenCaptureKit (float32, 48kHz) → AVAudioConverter → 16kHz mono  │
│ AVAudioEngine (mic) → AVAudioConverter → 16kHz mono                │
│        ↓                                                            │
│ WebSocketStreamer.sendPCMFrame(data, source="system"|"mic")        │
│        ↓ JSON: {"type":"audio","source":"...","data":"base64"}     │
└────────────────────────────────────────────────────────────────────┘
                              │ WebSocket
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                        FastAPI Server                               │
├────────────────────────────────────────────────────────────────────┤
│ ws_live_listener.py                                                 │
│   ├─ SessionState (queues per source, transcript, send_lock)       │
│   ├─ on "audio" → base64 decode → get_queue → put_audio            │
│   │               → spawn _asr_loop if new source                  │
│   └─ on "stop"  → EOF queues → wait ASR flush → final_summary      │
│                                                                     │
│ _pcm_stream(queue) → yields bytes until EOF                        │
│                                                                     │
│ stream_asr(pcm_stream) → provider.transcribe_stream()              │
│                                                                     │
│ FasterWhisperProvider:                                              │
│   - Buffer accumulates until chunk_bytes (4s default)              │
│   - _transcribe() runs in thread with _infer_lock                  │
│   - Yields ASRSegment (is_final=True)                              │
└────────────────────────────────────────────────────────────────────┘
```

### Key Files

| File | Role |
|------|------|
| `server/api/ws_live_listener.py` | WebSocket handler, session state, task orchestration |
| `server/services/asr_stream.py` | Streaming ASR interface |
| `server/services/provider_faster_whisper.py` | faster-whisper ASR provider |
| `server/services/analysis_stream.py` | Entity/card extraction, rolling summary |
| `macapp/.../AudioCaptureManager.swift` | System audio capture |
| `macapp/.../MicrophoneCaptureManager.swift` | Microphone capture |
| `macapp/.../WebSocketStreamer.swift` | WebSocket client |

---

## 2. Issues Fixed

### P0-1: `_pcm_stream()` Undefined

**Location**: `ws_live_listener.py:67`

**Fix**: Added async generator:

```python
async def _pcm_stream(queue: asyncio.Queue) -> AsyncIterator[bytes]:
    """Drain audio queue until EOF (None sentinel)."""
    while True:
        chunk = await queue.get()
        if chunk is None:
            return
        yield chunk
```

### P0-3: CTranslate2 MPS/float16 Unsupported

**Location**: `provider_faster_whisper.py:59-71`

**Fix**: Applied pattern from `model-lab/harness/registry.py`:

```python
# MPS not supported by faster-whisper
if device == "mps":
    device = "cpu"

# float16 not supported on CPU
if device == "cpu" and compute_type == "float16":
    compute_type = "int8"
```

### P1-2: Stop Semantics Order

**Before**:
1. Cancel analysis tasks
2. Wait for ASR flush
3. Generate final summary (missing late transcripts)

**After**:
1. Wait for ASR flush (all transcripts captured)
2. Cancel analysis tasks
3. Generate final summary (complete transcript)

### Race Condition: Send After Close

**Fix**: Added `closed` flag to SessionState, check before send:

```python
async def ws_send(state, websocket, event):
    if state.closed:
        return
    async with state.send_lock:
        try:
            await websocket.send_text(json.dumps(event))
        except RuntimeError:
            state.closed = True
```

---

## 3. Remaining Issues (P1/P2)

### P1-1: Model Load Latency

**Symptom**: First ASR result delayed by 5-30s (model load time).

**Recommendation**: Pre-load model in FastAPI lifespan:

```python
# In main.py lifespan()
provider = ASRProviderRegistry.get_provider()
if hasattr(provider, '_get_model'):
    await asyncio.to_thread(provider._get_model)
```

### P1-5: Timestamp Drift

**Issue**: Server uses sample-based time, not client capture time.

**Recommendation**: Client should send monotonic timestamp with audio frames.

### P2-1: VAD Disabled by Default

**Issue**: Silence chunks are transcribed, wasting CPU.

**Recommendation**: Enable VAD for mic source:

```python
if source == AudioSource.MICROPHONE:
    vad_filter = True
```

### P2-2: Diarization Disabled

**Issue**: Multi-source buffer concatenation produces incoherent audio.

**Status**: Correctly disabled. Future: per-source buffers.

---

## 4. Web Research Findings

### FastAPI/Starlette WebSocket Concurrency

- WebSocket is NOT thread-safe for concurrent sends
- **Mitigation**: `asyncio.Lock` (already implemented) ✅

### faster-whisper/CTranslate2

- MPS not supported (CPU fallback required)
- float16 not supported on CPU (int8 fallback)
- Thread-safe for inference (can remove lock for performance)

### macOS Audio Capture

- ScreenCaptureKit: float32, 48kHz (varies by hardware)
- AVAudioEngine: varies by device
- Both managers use AVAudioConverter correctly ✅

---

## 5. Test Results

```
tests/test_services.py::test_extract_cards_empty PASSED
tests/test_services.py::test_extract_entities_empty PASSED
tests/test_ws_integration.py::test_source_tagged_audio_flow PASSED
tests/test_ws_live_listener.py::test_ws_live_listener_start_stop PASSED
======================== 4 passed ========================
```

---

## 6. Stabilization Plan

### Phase 1: Correctness (Done)
- [x] Add `_pcm_stream()` function
- [x] Fix CTranslate2 device/compute_type fallback
- [x] Fix stop semantics order
- [x] Add closed connection handling

### Phase 2: Performance (Recommended)
- [ ] Pre-load model in lifespan
- [ ] Add ASR buffer size limit (prevent OOM)
- [ ] Consider removing `_infer_lock` (CTranslate2 is thread-safe)
- [ ] Add metrics: queue length, ASR latency histogram

### Phase 3: Quality (Future)
- [ ] Enable VAD for mic source
- [ ] Implement overlap/deduplication for repeated text
- [ ] Re-enable diarization with per-source buffers
- [ ] Add client timestamps to audio frames
