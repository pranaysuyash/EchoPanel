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

Optional local ASR:
- `uv pip install -e ".[asr]"`
- `export ECHOPANEL_WHISPER_MODEL=base`
- `export ECHOPANEL_WHISPER_DEVICE=metal`
- `export ECHOPANEL_WHISPER_COMPUTE=int8_float16`

### macOS app build (if present)
- `cd macapp/MeetingListenerApp && swift build`

### Stable dev build (avoid repeated permission prompts)
```sh
scripts/build-dev-app.sh
~/Applications/MeetingListenerApp-Dev
```

### Start backend server (dev)
```sh
scripts/run-dev-stack.sh
```

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
