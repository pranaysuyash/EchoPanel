# Live Meeting Reliability (End-User Behavior)

Date: 2026-02-13

This doc is focused on what end users experience during real live meetings (Zoom/Meet/etc.) where they cannot tune scripts or pacing knobs.

## Core Principle

The client must not treat server backpressure states as fatal errors. Under load, the system should:

- Keep the session running.
- Surface degraded performance clearly (buffering/overloaded messages, diagnostics).
- Prefer dropping or degrading work over stopping.

## Observed System Behavior

- The mac app captures system audio using ScreenCaptureKit and emits PCM frames continuously.
- The backend emits WebSocket `status` messages that include:
  - `state="connected"`: websocket accepted, waiting for client `start`
  - `state="streaming"`: ASR loop started and ready
  - `state="buffering"`: backend queue filling, falling behind realtime
  - `state="overloaded"`: critical backlog; backend may drop frames

## Critical Fixes (Prevent "Start Then Stop")

1. Client must not treat `status.state="connected"` as an error.
   - File: `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`
2. Client must not treat `status.state="buffering"` / `status.state="overloaded"` as errors.
   - These are expected live-meeting states under transient CPU/model load.
   - File: `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`

Related tickets:

- `TCK-20260213-036` (connected mapping)
- `TCK-20260213-040` (buffering/overloaded mapping)

## Backpressure + Dropping: What It Means For Users

If the backend cannot keep up:

- The server may send `status.state="buffering"` to indicate it is behind.
- If backlog becomes critical, it may send `status.state="overloaded"` and begin dropping frames.
- In extreme overload, server-side policy may preferentially drop system audio while keeping microphone audio (to preserve the user's voice).

The correct UX is: the session continues, but transcript quality/latency degrades. This must not look like "EchoPanel stopped".

## Validation Approach (End-User Aligned)

End users generate audio at real-time. Any test harness must be paced to avoid false overload failures.

Recommended local validation:

1. Start the backend.
   - `python -m uvicorn server.main:app --host 127.0.0.1 --port 8000`
2. Start a mac session and confirm the session does not auto-stop when server reports:
   - `connected` (pre-start)
   - `buffering` / `overloaded` (backpressure)
3. Confirm the UI enters and stays in a non-idle state while backpressure is active, and Diagnostics show backpressure/metrics updates.

Tooling note:

- `scripts/test_with_audio.py` supports realtime pacing via `--speed 1.0`.
- Sending unpaced (`--speed 0`) is intentionally allowed for stress tests, but will trigger overload and frame drops that do not represent end-user behavior.

## Diagnostics For Real Users

When a user reports "no transcript" or "stops automatically":

- Check whether capture is running (ScreenCaptureKit start + AudioSampleHandler buffers).
- Check the WebSocket status stream:
  - `connected` is normal.
  - `buffering/overloaded` are degradation signals, not fatal.
  - `error` requires corrective action (auth/capacity/model load failure).
- Export a Session Bundle (Diagnostics) and inspect:
  - `client.log` for WS drops/timeouts and status transitions
  - `metrics.ndjson` for queue fill and dropped frames

