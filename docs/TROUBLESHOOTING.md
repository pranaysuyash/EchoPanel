# Troubleshooting

## Screen Recording permission
Symptoms:
- App shows "permission required" or no audio is captured.

Checks:
- System Settings -> Privacy & Security -> Screen Recording
- Ensure EchoPanel is enabled.

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
- Status line shows Reconnecting or Backend unavailable.

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
- If running locally, ensure ASR extras are installed and enabled:
  - `scripts/run-dev-all.sh --asr`
- Enable debug logs to confirm PCM and ASR activity:
  - `export ECHOPANEL_DEBUG=1`
  - `scripts/run-dev-all.sh`
  - Look for `Debug: ... samples ... sent` in the panel header.
  - Look for `AudioCaptureManager: received` and `ws_live_listener: received` logs.

## Diarization not showing in outputs
Symptoms:
- Final JSON has an empty `diarization` list.

Checks:
- Set `ECHOPANEL_HF_TOKEN` and enable diarization:
  - `scripts/run-dev-all.sh --asr --diarization`
- Confirm `pyannote.audio` and `torch` are installed in the active venv.
