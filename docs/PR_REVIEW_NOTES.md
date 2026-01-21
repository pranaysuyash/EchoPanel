# PR Review Notes (2026-01-21)

This file summarizes the current open PRs and a proposed consolidation path to match `docs/LIVE_LISTENER_SPEC.md`.

## Open PRs
### PR #1: Scaffold v0.1: macOS menu-bar app, Side Panel UI, ScreenCaptureKit & WebSocket stubs
- Branch: `codex/implement-macos-live-meeting-listener-v0.1`
- Strengths:
  - Matches the spec WebSocket path `/ws/live-listener`.
  - AppState wiring capture -> stream -> UI is present.
  - Transcript partial/final replacement logic is implemented.
  - Includes `docs/IMPLEMENTATION_PLAN.md`.
- Gaps:
  - `session_id` is regenerated for `start` and `stop` (should be stable per session).
  - ScreenCaptureKit capture is a stub (no SCStream config/output yet).
  - Cards/entities parsing is stubbed (currently empty arrays).

Review feedback to apply:
- Reuse the same `session_id` for `start` and `stop` (Codex).
- Do not start the timer or connect WebSocket when Screen Recording permission is denied (Codex).
- Minor doc wording: use “start/stop” phrasing (CodeRabbit).

### PR #2: Add v0.1 macOS listener scaffold, ScreenCaptureKit and WebSocket stubs, and backend contract
- Branch: `codex/implement-macos-live-meeting-listener-v0.1-oupyom`
- Strengths:
  - ScreenCaptureKit capture setup is more complete (SCShareableContent, SCStream config, audio output hook).
  - Code is organized into subfolders (`Models/`, `UI/`, `AudioCapture/`, `Streaming/`).
- Gaps:
  - Contract and server use `/ws/asr` which conflicts with the v0.1 spec path.
  - WebSocket client does not decode server events into UI state yet.
  - Reconnect logic is fixed-interval (5s) rather than exponential backoff to max 10s.

Review feedback to apply:
- Reset session state on new session start (Codex).
- Route “End Session” through the same stop flow as menu stop (Codex).
- Fix `stream_asr` async iterator stub to avoid `async for` crash (Cubic).
- If using `NSStatusItem.menu`, the button action will not fire; prefer `MenuBarExtra` or implement click handling carefully (Cubic).

## Proposed consolidation path
1) Use PR #1 as the base because it is closer to the end-to-end spec flow and uses `/ws/live-listener`.
2) Port PR #2's ScreenCaptureKit capture implementation into PR #1 (or rebase PR #1 onto PR #2) while keeping:
   - The `/ws/live-listener` endpoint and `docs/WS_CONTRACT.md` schema.
   - The AppState wiring and transcript rendering semantics.
3) Fix spec mismatches and correctness issues during consolidation:
   - Persist a single `session_id` through `start` and `stop`.
   - Align server route to `/ws/live-listener` and ensure docs match.
   - Implement JSON event decoding for `asr_partial`, `asr_final`, `cards_update`, `entities_update`, `status`, `final_summary`.
   - Ensure keyboard shortcuts match spec: Cmd+Shift+L toggles listening globally; Cmd+C copies Markdown from panel.

## Spec improvements worth adopting (still v0.1 scope)
- Add `client_version` to `start` for observability (optional field).
- Add `server_time` or `seq` to server events to help UI ordering (optional field).
