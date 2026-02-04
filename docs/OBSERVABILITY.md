# Observability (v0.1)

## User-facing signals
- Listening indicator: visible in menu bar and panel.
- Backend status line: Streaming, Reconnecting, Not ready.
- Audio quality: Good/OK/Poor derived from RMS, clipping rate, silence ratio.
- Confidence: display confidence numbers on transcript segments and cards/entities.

## Developer-facing signals (minimal)
- Connection lifecycle events: connect, disconnect, reconnect attempts and delay.
- Session events: start, stop, final summary received.
- Error bucket: permission denied, unsupported OS, WebSocket errors, decode errors.

## Logging guidance
- Avoid logging raw audio bytes.
- Avoid logging full transcript by default; prefer counts and hashes for debugging.
- When adding debug logging, ensure it is gated behind a debug flag.
