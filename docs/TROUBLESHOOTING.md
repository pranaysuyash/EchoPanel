# Troubleshooting

## Replicable local dev runbook (macOS)

This runbook is designed so any agent can reproduce capture issues deterministically.

### Terminal 0 — hard reset (quit app + free port 8000)
```bash
# Quit any running instances (binary or .app)
pkill -f MeetingListenerApp || true

# Free the backend port (avoid “ghost server ready” states)
lsof -nP -iTCP:8000 -sTCP:LISTEN || true
# If something is listening, kill it (replace <PID>)
# kill <PID>

# Re-check port is free
lsof -nP -iTCP:8000 -sTCP:LISTEN || true
```

### Terminal 1 — build + install a stable Dev app bundle (recommended for permissions)
```bash
cd /Users/pranay/Projects/EchoPanel
./scripts/build-dev-app.sh
```

### Terminal 2 — launch the Dev bundle
```bash
./scripts/run-dev-app.sh
```

### macOS Settings (one-time)
1) System Settings → Privacy & Security → Screen Recording → enable **MeetingListenerApp Dev**
2) Quit the app fully (Cmd+Q)
3) Re-launch via Terminal 2

### Option A (recommended): app-managed backend

#### Terminal 3 — tail backend log file (spawned by the app)
```bash
tail -f /var/folders/fc/xwynjqm94t39_jvz88fhcpfc0000gn/T/echopanel_server.log
```

#### Terminal 4 — macOS app capture logs (only useful signals)
```bash
log stream --style compact --predicate '(process == "MeetingListenerApp") && (eventMessage CONTAINS "AudioSampleHandler" OR eventMessage CONTAINS "processAudio" OR eventMessage CONTAINS "onPCMFrame" OR eventMessage CONTAINS "AudioCaptureManager" OR eventMessage CONTAINS "MicrophoneCaptureManager" OR eventMessage CONTAINS "WebSocketStreamer" OR eventMessage CONTAINS "BackendManager" OR eventMessage CONTAINS "SidePanelController")'
```

In the UI:
1) Menu bar → Start Listening (side panel must open)
2) Set Source: System Audio / Microphone / Both
3) Play audio (YouTube) and/or speak for 10 seconds
4) End session

Success signals:
- System audio: `AudioSampleHandler: Received audio buffer ...` and `onPCMFrame ... source: system`
- Mic audio: `MicrophoneCaptureManager: Started capture` and `onPCMFrame ... source: mic`
- Backend: `asr_partial` / `asr_final` events (if ASR provider available)

If the side panel says **Not ready**:
- Open **Diagnostics** and check:
  - Backend Status
  - Backend Detail (may say “Port 8000 is already in use” or “ASR provider not available”)
- Then hard-reset port 8000 using Terminal 0 steps and relaunch.

### Option B: manual backend (only when you want full control)
**Important**: only one backend can bind `127.0.0.1:8000`. If you run uvicorn manually, the app’s built-in backend may fail to start (that’s fine), but ensure port ownership is unambiguous.

#### Terminal 1B — start backend with venv
```bash
cd /Users/pranay/Projects/EchoPanel
source .venv/bin/activate
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --log-level debug
```

#### Terminal 2B — verify backend readiness
```bash
curl -i http://127.0.0.1:8000/health
```

Expected:
- HTTP 200 with `provider` + `model` when ASR is available
- HTTP 503 with a reason when ASR isn’t available

If using manual backend on a non-8000 port, set Settings → Backend host/port in the app to match.

## Screen Recording permission
Symptoms:
- App shows "permission required" or no audio is captured.

Checks:
- System Settings -> Privacy & Security -> Screen Recording
- Ensure EchoPanel is enabled.
 - If prompts keep reappearing, you are likely running multiple identities (swift-run binary vs .app bundle) and macOS ties permission to the exact identity.
   - Recommended: build a stable bundle and keep using it:
     - `./scripts/build-dev-app.sh`
     - `./scripts/run-dev-app.sh`
   - After toggling Screen Recording, macOS often requires quitting and relaunching the app for it to take effect.

Notes:
- ScreenCaptureKit system audio capture requires Screen Recording permission.
- v0.1 must not attempt capture without explicit user action.

## Unsupported macOS version
Symptoms:
- App shows unsupported error or capture does not start.

Checks:
- v0.1 requires macOS 13+.

## Backend connection issues
Symptoms:
- Status line shows Reconnecting or Not ready.

Checks:
- Verify backend URL and endpoint path matches `docs/WS_CONTRACT.md` (`/ws/live-listener`).
- Verify TLS and WSS in production.
- If running locally, confirm the server is listening and no firewall blocks localhost ports.

## No transcript updates
Symptoms:
- Audio appears captured but transcript remains empty.

Checks:
- Backend is receiving binary PCM frames (20 ms frames, 640 bytes).
- Client sent `start` before sending binary frames.
- Verify sample rate and format match the contract.
- If running locally, ensure ASR deps are installed in the active venv (faster-whisper + numpy).
- Enable debug logs to confirm PCM and ASR activity:
  - Look for `Debug: ... samples ... screen frames ... sent` in the panel header.
  - Look for `AudioCaptureManager: received` and `ws_live_listener: received` logs.

## ScreenCaptureKit "stream output NOT found. Dropping frame"
Symptoms:
- Console logs show `stream output NOT found. Dropping frame`.

Checks:
- Ensure video capture is disabled for audio-only streams.
- Confirm the app is built with the latest `AudioCaptureManager` changes.

## Diarization not showing in outputs
Symptoms:
- Final JSON has an empty `diarization` list.

Checks:
- Set `ECHOPANEL_HF_TOKEN` and enable diarization:
  - `scripts/run-dev-all.sh --asr --diarization`
- Confirm `pyannote.audio` and `torch` are installed in the active venv.
