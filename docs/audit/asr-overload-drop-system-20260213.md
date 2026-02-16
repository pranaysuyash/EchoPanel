# ASR Overload Investigation: "Dropping system due to extreme overload"

Date: 2026-02-13
Status: Implemented fix + validated locally

## What Users Saw

Server logs repeatedly:

- `Dropping system due to extreme overload`

In practice, this looks like "system audio doesn't get transcribed" (remote speakers missing), even during otherwise normal live meetings.

## Root Cause (Observed)

The overload drop was driven by `ConcurrencyController.should_drop_source()` inside `put_audio()`:

- File: `server/api/ws_live_listener.py`
- Function: `put_audio(...)`

However, `put_audio()` was also submitting every chunk into ConcurrencyController's internal per-source queues via `submit_chunk()`, and **those controller queues were never drained** by the active ASR loop.

The ASR loop drains from a different queue:

- File: `server/api/ws_live_listener.py`
- Function: `_asr_loop(...)` drains `_pcm_stream(queue)` where `queue` is the per-source `asyncio.Queue(maxsize=QUEUE_MAX)`.

Result:

- ConcurrencyController internal queues become permanently full
- `get_backpressure_level()` returns `CRITICAL/OVERLOADED`
- `should_drop_source("system")` returns `True`
- Server logs "Dropping system due to extreme overload" even under paced/realtime audio

## Fix (Implemented)

We removed the unused controller-owned audio queue path from `put_audio()` so overload decisions reflect the **real ingest queue** used by `_asr_loop()`.

- File: `server/api/ws_live_listener.py`
  - `put_audio()` now enqueues only into the per-source `asyncio.Queue` actually drained by `_asr_loop()`
  - Backpressure is handled by dropping oldest frames when that ingest queue is full

We kept ConcurrencyController for session limiting (`acquire_session` / `release_session`) only.

## Validation (Observed)

1. Realtime-paced stream test (20s @ 40ms chunks)
   - No occurrences of `Dropping system due to extreme overload` in `/tmp/echopanel_server.log`.

2. Tests
   - Added regression test ensuring `put_audio()` does not fill ConcurrencyController queues:
     - `tests/test_put_audio_does_not_enqueue_controller.py`
   - Targeted suite:
     - `tests/test_ws_live_listener.py`
     - `tests/test_main_auto_select.py`
     - `tests/test_ws_integration.py`

## Notes On "Real" Overload (Still Relevant)

Even with the false-drop bug fixed, real overload can still happen if ASR inference cannot keep up with realtime. In that case the correct behavior is:

- surface `status.state="buffering"` / `status.state="overloaded"` to the client
- degrade quality or switch to a faster provider/model
- avoid fully dropping system audio for long periods (otherwise the user loses the meeting)

Provider/model selection is already capability-aware in `server/main.py` via `CapabilityDetector`, and we now also propagate `ECHOPANEL_HF_TOKEN` into Hugging Face standard env vars to speed model downloads:

- File: `server/main.py` (`_sync_huggingface_token_env()`)

Reliability note:

- Voxtral auto-selection is now opt-in via `ECHOPANEL_AUTO_SELECT_VOXTRAL=1` to avoid slow/fragile startup on machines where voxtral isn't installed or is too heavy for interactive use.
- `/capabilities` is a key endpoint for clients to show the recommended provider/model; it now returns 200 (previously could 500 due to missing imports in the detector).

## Follow-Ups

- Make degrade ladder actions actually take effect mid-session (requires provider support to reconfigure chunk/model safely).
- Add a small benchmark matrix for faster-whisper model variants and whisper.cpp vs faster-whisper on Apple Silicon.
