# Features and Scope

## v0.1 features
- Menu bar Start/Stop toggle and session timer.
- System audio capture via ScreenCaptureKit (macOS 13+).
- WebSocket streaming of PCM16 16 kHz mono.
- Floating side panel with three lanes: Transcript, Cards (Actions/Decisions/Risks), Entities.
- Export actions: Copy Markdown, Export JSON.
- Observability: audio quality indicator and backend status line.

## Explicit non-goals (v0.1)
- Calendar/Zoom/Meet integrations.
- Bot join.
- Multi-user collaboration or team accounts.
- Full historical search.
- Diarization as a core feature.
- Video capture.

## Post v0.1 ideas (not committed)
- Optional buffering on disconnect with a ring buffer.
- Session library and search.
- Speaker diarization.
- Clip generation.

## Extras implemented (beyond v0.1 scope)
- Stable `.app` bundle build for consistent Screen Recording permissions.
- Combined dev runner to build, launch, and start backend together.
- Export Markdown to file (in addition to Copy Markdown and Export JSON).
- Permission status banner in the side panel UI.
