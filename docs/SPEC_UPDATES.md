# Spec Updates Log

This file records decisions and deltas from the original v0.1 draft spec.

## Unreleased
- Establish initial WebSocket endpoint path as `/ws/live-listener` in `docs/WS_CONTRACT.md`.

## Extras Delivered (Beyond v0.1)
- Added a stable `.app` bundle build flow for consistent Screen Recording permissions.
- Added a combined dev runner that builds the app bundle, starts backend, and launches the app.
- Added export to Markdown file in addition to Copy Markdown and Export JSON.
- Added a permission status banner and debug line in the side panel UI.
- Added optional local ASR (faster-whisper) wiring and env flags in backend.

## Why These Help
- Stable `.app` bundles prevent permission prompts from attributing to Terminal or IDEs.
- One-command dev run reduces setup friction and keeps backend and app in sync.
- Markdown file export supports immediate sharing or archiving without manual copy.
- Permission banner makes consent state visible and debuggable for users.
- Optional local ASR enables offline development and future on-device paths.

## Next Recommended Steps
- Replace stub ASR with production streaming ASR and validate latency targets.
- Implement backend reconnect and buffering behavior aligned with spec.
- Align macOS UI with landing visuals once core stability is verified.
- Add basic integration tests for WebSocket streaming and export paths.
