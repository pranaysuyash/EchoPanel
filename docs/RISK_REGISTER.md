# Risk Register (v0.1)

## Product risks
- Users do not grant Screen Recording permission.
  - Mitigation: clear onboarding copy, visible indicator, show steps to enable.
- Users expect speaker labels.
  - Mitigation: explicitly out of scope for v0.1; avoid implying diarization.

## Technical risks
- ScreenCaptureKit audio capture edge cases (no display, multi-display).
  - Mitigation: handle no-display and unsupported cases gracefully.
- Resampling and PCM conversion errors degrade ASR.
  - Mitigation: validate frame size and sample rate, add basic signal metrics.
- WebSocket reconnect loops cause duplicated `start` or mismatched `session_id`.
  - Mitigation: stable session id; explicit state machine for connect/reconnect.

## Operational risks
- Backend unavailable or rate limited.
  - Mitigation: visible status, exponential backoff, no silent buffering in v0.1.

