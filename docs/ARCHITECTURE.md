# Architecture (v0.1)

## Overview
EchoPanel v0.1 is a macOS menu bar app that captures system audio output and streams it to a backend over WebSocket for:
- streaming ASR events (partial and final transcript)
- periodic analysis events (actions, decisions, risks, entities)
- final consolidation at session end

The app renders a floating side panel that shows the live transcript and continuously updating artifacts.

## Components
### macOS app (Swift + SwiftUI)
- Menu bar control: Start/Stop toggle, timer, status.
- Side panel: transcript lane, cards lane, entities lane, export actions.
- Capture: ScreenCaptureKit audio capture (macOS 13+), no virtual drivers.
- Audio pipeline: downmix + resample to 16 kHz mono, convert to PCM16.
- Streaming: WebSocket client; sends control JSON and binary PCM frames; receives JSON events.
- Local storage: session transcript and outputs as JSON.

### Backend
- WebSocket endpoint: `/ws/live-listener` (see `docs/WS_CONTRACT.md`).
- Streaming ASR pipeline to emit `asr_partial` and `asr_final`.
- Periodic analysis pipeline:
  - Entities updates every 10-20 seconds.
  - Cards updates every 30-60 seconds over a sliding window (default last 10 minutes).
- Final consolidation on `stop`.

## Data flow
1) User clicks Start in menu bar.
2) App verifies Screen Recording permission.
3) App starts ScreenCaptureKit audio capture.
4) App connects to backend WebSocket and sends `start`.
5) App streams binary PCM frames at near real-time cadence (20 ms frames).
6) Backend emits ASR partials and finals, plus periodic analysis updates.
7) App updates UI state and renders new segments and cards/entities.
8) User clicks Stop.
9) App stops capture and sends `stop`.
10) Backend responds with `final_summary`.
11) App enables export actions and writes session JSON to local storage.

## Constraints and defaults (locked for v0.1)
- macOS 13+
- ScreenCaptureKit for system audio capture
- PCM16 16 kHz mono frames
- WebSocket transport
- No diarization

