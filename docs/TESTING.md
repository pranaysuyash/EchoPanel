# Testing and Verification

This repo starts with manual verification. Add automated tests once the core pipeline is wired.

**Note**: This project uses `uv` for fast package management. If you don't have uv installed, get it from [astral.sh/uv](https://github.com/astral-sh/uv).

## v0.1 acceptance checklist

- Start opens panel and begins streaming.
- Partial transcript renders within 2-5 seconds.
- With `Source = Both`, mic + system lines appear without overwriting each other.
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
- `export ECHOPANEL_WHISPER_MODEL=base.en`
- `export ECHOPANEL_WHISPER_DEVICE=cpu`
- `export ECHOPANEL_WHISPER_COMPUTE=int8`

### macOS app build (if present)

- `cd macapp/MeetingListenerApp && swift build`
- `cd macapp/MeetingListenerApp && swift test`

### Automated visual regression (macOS SidePanel)

- Baseline comparison (default): `cd macapp/MeetingListenerApp && swift test`
- Re-record snapshots after intentional UI changes:
  - `cd macapp/MeetingListenerApp && RECORD_SNAPSHOTS=1 swift test` (writes snapshot files and exits non-zero by design)
  - `cd macapp/MeetingListenerApp && swift test` (must pass with new baselines)
- Snapshot files:
  - `macapp/MeetingListenerApp/Tests/__Snapshots__/SidePanelVisualSnapshotTests/*.png`

### Always-run local verification (pre-commit)

- Install hooks once per clone:
  - `./scripts/install-git-hooks.sh`
- Pre-commit hook runs:
  - `./scripts/verify.sh`
- Verify command currently includes:
  - `cd macapp/MeetingListenerApp && swift build && swift test`

### Stable dev build (avoid repeated permission prompts)

```sh
scripts/run-dev-app.sh
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
Use `--no-build` if you want to avoid re-signing the app and re-prompting permissions:

```sh
scripts/run-dev-all.sh --no-build
```

Local ASR output is enabled by default for live transcripts.
Disable with:

```sh
scripts/run-dev-all.sh --no-asr
```

To enable diarization (requires Hugging Face token):

```sh
export ECHOPANEL_HF_TOKEN=your_token_here
scripts/run-dev-all.sh --asr --diarization
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

## Manual smoke test (UI/UX)

1. Start Listening → verify panel appears (even if “Not ready”).
2. Set Source to **Both** → play system audio + speak into mic.
3. Verify:
   - Timer matches the transcript time progression.
   - Mic (“You”) and System lines both appear and don’t overwrite each other.
4. End Session → Summary opens and exports work.

## Manual smoke test (Three-cut side panel)

1. Start Listening and confirm default mode is `Roll`.
2. Switch `Roll -> Compact -> Full` in the mode segmented control and verify panel resizes appropriately.
3. In each mode (`Roll`, `Compact`, `Full`), verify capture controls are collapsed by default and transcript remains the largest area.
4. Expand `Audio setup`, verify controls are available, then collapse again.
5. In each mode, verify shared keyboard contract:
   - `↑ / ↓` moves focused transcript line
   - `Enter` toggles Focus Lens for focused line
   - `P` pins/unpins focused line
   - `Space` toggles follow-live
   - `J` jumps to live
   - `Esc` closes one layer (help -> surfaces -> lens)
   - `?` toggles keyboard help
   - In `Full`, `Cmd/Ctrl + K` focuses the search box
6. In `Roll` and `Compact`, press `← / →` to open/cycle overlay surfaces (`Summary`, `Actions`, `Pins`, `Entities`, `Raw`).
7. In `Full`, verify:
   - Session rail appears on the left and selecting rows updates the header title.
   - Work mode segmented control (`Live`, `Review`, `Brief`) is visible.
   - Persistent insight tabs include `Context`.
   - Timeline scrub bar moves focus cursor through transcript lines.
8. Open `System Settings -> Accessibility -> Display -> Reduce motion`, repeat steps 1-7, and verify transitions remain functional without animated jitter.
9. Resize window to each mode minimum size and verify no clipped controls:
   - `Roll` around `390x620`
   - `Compact` around `320x560`
   - `Full` around `920x640`
10. In narrow `Compact`, verify footer still exposes copy/export/end actions (via icon/menu fallback) without truncation.
11. In capture controls, verify source diagnostics chips appear for selected source(s):
   - `In <age>` reflects live input-frame freshness per source (`System` / `Mic`).
   - `ASR <age>` reflects transcript event freshness per source.
12. With `Audio Good` but no transcript, verify troubleshooting text appears under diagnostics.
13. Verify status chip uses plain language (`Ready`, `Preparing`, `Permission needed`, `Setup needed`) and avoids ambiguous `Not ready`.
14. In narrow `Compact` and `Roll`, verify the highlights segmented control does not show a wrapped/vertical `Highlights` label artifact.

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
# Optional (destructive): resets Screen Recording permission prompts for ALL apps
# tccutil reset ScreenCapture
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
