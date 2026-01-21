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
open ~/Applications/MeetingListenerApp-Dev.app
```

### Build a proper .app bundle (recommended for permissions)
```sh
scripts/build-app-bundle.sh
open ~/Applications/MeetingListenerApp.app
```

### Build and launch dev app
```sh
scripts/run-dev-app.sh
```

### Run backend + app together (recommended)
```sh
scripts/run-dev-all.sh
```
This builds the app bundle, starts the backend, and launches the app.

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

## Troubleshooting
### Screen Recording permission keeps prompting
Use the app bundle flow so macOS attributes permission to the app, not the shell.
```sh
pkill -f MeetingListenerApp || true
tccutil reset ScreenCapture
scripts/build-app-bundle.sh
open ~/Applications/MeetingListenerApp.app
```
Then toggle the app in System Settings:
`System Settings -> Privacy & Security -> Screen & System Audio Recording`.

### App shows "Could not connect to the server"
Start the backend in another terminal or use the combined script:
```sh
scripts/run-dev-all.sh
```
