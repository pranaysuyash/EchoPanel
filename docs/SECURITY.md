# Security and Privacy (v0.1)

## Principles
- User intent: capture only on explicit user action.
- Transparency: visible Listening indicator and connection status.
- Least data: stream audio for live processing; persist only what the user exports or what is needed for session history (v0.1 minimal).

## Permissions
- Screen Recording permission is required for ScreenCaptureKit system audio capture.
- The app must explain why the permission is needed and how to enable it in System Settings.

## Data handling
- Audio: streamed to the backend over WebSocket. Production must use `wss://` with valid TLS.
- Transcript and artifacts: stored locally in the app sandbox as JSON in v0.1 minimal; avoid sending to third parties.
- Logs: avoid logging raw transcript or audio payloads by default.

## Threat model (minimal)
- Network interception: mitigate with TLS and short-lived session IDs.
- Accidental capture: mitigate with explicit Start/Stop UX and visible indicator.
- Backend compromise: mitigate by limiting retained audio and storing only derived artifacts when possible.

