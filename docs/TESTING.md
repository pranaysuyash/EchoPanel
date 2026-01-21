# Testing and Verification

This repo starts with manual verification. Add automated tests once the core pipeline is wired.

## v0.1 acceptance checklist
- Start opens panel and begins streaming.
- Partial transcript renders within 2-5 seconds.
- Cards update at least once per minute.
- Stop produces final summary and export functions.
- Handles backend disconnect with visible state and recovery.

## Manual verification (local)
### Docs and lint
- `rg -n \"ws/live-listener\" docs/WS_CONTRACT.md`

### Backend stub (if present)
- `uv venv .venv && source .venv/bin/activate`
- `uv pip install -e ".[dev]"`
- `python -m server.main`

### macOS app build (if present)
- `cd macapp/MeetingListenerApp && swift build`

## Automated tests (Python)
Run unit and integration tests with uv-managed environment:
```sh
uv venv .venv
source .venv/bin/activate
uv pip install -e ".[dev]"
pytest
```

## Visual testing (manual)
See `docs/VISUAL_TESTING.md`.

## Test data
- For WebSocket, use a simulated client that:
  - Sends `start`
  - Streams 20 ms PCM frames (640 bytes each)
  - Sends `stop`
