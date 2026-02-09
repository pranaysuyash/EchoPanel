# Features and Scope (current)

## Current implemented features (Observed)
- Menu bar control:
  - Start/Stop listening toggle, timer, status line.
- Capture:
  - System audio capture via ScreenCaptureKit.
  - Optional microphone capture.
  - `System`, `Microphone`, and `Both` source modes.
- Streaming:
  - WebSocket session with JSON `start` / `audio` / `stop`.
  - Source-tagged audio frames (`system` / `mic`).
- Transcript:
  - Timestamped transcript segments (`t0`, `t1`, confidence, source).
  - Live transcript UI in roll/compact/full side panel modes.
- Insight surfaces:
  - `Summary`, `Actions`, `Pins`, `Entities`, `Raw`.
  - Full layout also includes `Context` tab for local document retrieval.
- Analysis:
  - Rolling cards (actions/decisions/risks).
  - Entity extraction (people/orgs/dates/projects/topics).
  - Final summary markdown + JSON payload at session stop.
- Diarization:
  - Session-end diarization path (feature-flagged with `ECHOPANEL_DIARIZATION=1`).
  - Source-aware speaker merge into final transcript.
- Local context / RAG MVP:
  - Document index/list/query/delete API.
  - Side panel context UI for upload/query/result display.
  - Local lexical retrieval store (`LocalRAGStore`).
- Persistence and recovery:
  - Session autosave snapshots.
  - Transcript append log.
  - Crash recovery marker and recovery flow.
- Export:
  - Copy Markdown.
  - Export JSON.
  - Export Markdown file.
  - Debug bundle export.
- Auth and transport hardening:
  - Optional backend token (Keychain-backed).
  - Shared token gate for websocket + documents API.
  - Non-local backend defaults to secure schemes (`wss`/`https`).

## Current limitations (Observed)
- ASR partials:
  - Protocol supports partial events, but default `faster-whisper` provider currently emits final segments only.
- RAG scope:
  - Local lexical retrieval only; no embedding/vector DB, no remote sync.
- Auth model:
  - Single shared token; no user accounts, roles, rotation, or expiry flow.
- Deployment:
  - Full public distribution pipeline (signed/notarized DMG + clean-machine validation) is documented but not fully closed in evidence.
- Commercial:
  - Pricing/licensing still draft-level in docs.

## Out of scope (still true)
- Bot/calendar-native meeting integrations.
- Team collaboration/accounts.
- Cloud-hosted multi-tenant backend.
- Paid billing stack enforcement in current app runtime.
