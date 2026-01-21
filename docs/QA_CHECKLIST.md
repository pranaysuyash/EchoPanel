# QA Checklist (v0.1)

## Core flows
- Start from menu bar toggles to Listening.
- Side panel appears on Start and hides on Stop.
- Timer increments while listening and resets on Stop.

## Permissions
- First run triggers permission UX.
- Capture does not start when permission is denied.
- App remains stable if permission toggles while app is running.

## Streaming and resilience
- `start` is sent once per session with a stable `session_id`.
- Binary frames stream at near real-time cadence.
- On backend disconnect, status indicates reconnecting and recovers within 10 seconds.

## UI correctness
- Partial transcript is visually distinct from final.
- Final segments replace partial cleanly without duplication.
- Confidence values show and low confidence is visibly labeled.
- Cards update at least once per minute (when backend sends updates).
- Entities update every 10-20 seconds (when backend sends updates).

## Exports
- Copy Markdown copies final summary if available.
- Export JSON writes a file containing session metadata and outputs.

