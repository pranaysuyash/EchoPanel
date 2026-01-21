# Implementation Plan (PR sequence)

This is a concrete PR breakdown for the v0.1 MVP. Keep each PR narrowly scoped.

## PR0: Documentation baseline
- Goal: Land spec and contract docs to unblock parallel work.
- Files:
  - `docs/LIVE_LISTENER_SPEC.md`
  - `docs/WS_CONTRACT.md`
  - `docs/TESTING.md`
  - `docs/SECURITY.md`
  - `docs/FEATURES.md`
  - `docs/UI.md`
  - `docs/UX.md`
  - `docs/VERSIONING.md`
  - `docs/SPEC_UPDATES.md`
  - `docs/PROJECT_MANAGEMENT.md`
- Tasks:
  - Align endpoint path and event schemas.
  - Add acceptance checklist and manual verification commands.
- Verification:
  - `rg -n \"type\\\":\\\"asr_\" docs/WS_CONTRACT.md`
- Acceptance:
  - Docs match v0.1 spec and are internally consistent.

## PR1: macOS app scaffold (menu bar + side panel)
- Goal: Menu bar app launches and side panel renders three lanes.
- Tasks:
  - SwiftUI menu bar app shell and session state.
  - Floating `NSPanel` side panel with transcript, cards, entities lanes.
  - Keyboard shortcuts: Cmd+Shift+L and Cmd+C (panel copy).
- Acceptance:
  - App runs 10 minutes idle without crash.

## PR2: Audio capture skeleton
- Goal: Request permissions and capture system audio via ScreenCaptureKit.
- Tasks:
  - Screen recording permission UX.
  - ScreenCaptureKit stream configuration for audio.
  - Audio quality heuristics (RMS, clipping, silence ratio).
- Acceptance:
  - Non-zero RMS when audio plays.

## PR3: WebSocket streaming skeleton
- Goal: Connect, send `start`, stream binary frames, receive events, reconnect.
- Tasks:
  - WebSocket client with exponential backoff reconnect.
  - JSON encode/decode per `docs/WS_CONTRACT.md`.
  - Binary frame send API.
- Acceptance:
  - Reconnect within 10 seconds after disconnect.

## PR4: Backend stub for integration
- Goal: Provide a local server and a simulated client to validate the protocol.
- Tasks:
  - WebSocket endpoint at `/ws/live-listener`.
  - Simulated ASR partial/final and periodic cards/entities.
  - Simulated client tool to send PCM frames.
- Acceptance:
  - UI updates when events are streamed from the stub.

