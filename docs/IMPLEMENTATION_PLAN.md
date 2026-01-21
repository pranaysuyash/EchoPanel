# Implementation Plan: EchoPanel v0.1

## PR0: Documentation and contract
- Goal: land spec copy and WebSocket contract
- Files changed:
  - docs/LIVE_LISTENER_SPEC.md
  - docs/WS_CONTRACT.md
  - docs/IMPLEMENTATION_PLAN.md
- Tasks:
  1) Add the spec copy for reference
  2) Define WebSocket schemas and binary framing
  3) Capture the PR sequence and acceptance checklist
- Verification commands:
  - `ls docs`
- Acceptance criteria:
  - Spec and contract are present and readable

## PR1: macOS app scaffold
- Goal: SwiftUI menu bar app with floating side panel and state model
- Files changed:
  - macapp/MeetingListenerApp/Package.swift
  - macapp/MeetingListenerApp/Sources/MeetingListenerApp/**
- Tasks:
  1) Add Swift Package definition for macOS 13
  2) Add app state model and session lifecycle
  3) Add menu bar controller and side panel controller
  4) Add placeholder UI for transcript, cards, entities
  5) Add build instructions
- Verification commands:
  - `cd macapp/MeetingListenerApp && swift build`
- Acceptance criteria:
  - App builds
  - Menu bar toggle opens and closes the side panel

## PR2: Capture module stub
- Goal: ScreenCaptureKit capture skeleton with permission UX stubs
- Files changed:
  - macapp/MeetingListenerApp/Sources/MeetingListenerApp/Audio/AudioCaptureManager.swift
- Tasks:
  1) Add ScreenCaptureKit configuration and start stop API
  2) Stub sample buffer conversion to PCM16
  3) Emit audio quality updates
  4) Add permission state helpers
- Verification commands:
  - `cd macapp/MeetingListenerApp && swift build`
- Acceptance criteria:
  - Capture module compiles and can be called from app state

## PR3: Streaming module stub
- Goal: WebSocket client skeleton and reconnect strategy
- Files changed:
  - macapp/MeetingListenerApp/Sources/MeetingListenerApp/Streaming/WebSocketStreamer.swift
  - server/api/ws_asr.py
  - server/services/asr_stream.py
  - server/services/analysis_stream.py
  - server/tools/sim_client.py
- Tasks:
  1) Add WebSocket client with JSON start stop messages
  2) Add binary send API for PCM frames
  3) Add reconnect backoff and status events
  4) Add backend stub entrypoint and analysis placeholders
  5) Add a simulated client tool for testing
- Verification commands:
  - `python server/api/ws_asr.py`
  - `python server/tools/sim_client.py --url ws://127.0.0.1:8000/ws/live-listener`
- Acceptance criteria:
  - Client can connect and send dummy frames
  - App prints status transitions in logs

## PR4: Wiring and UI update cadence
- Goal: Hook UI to receive events and show cadence placeholders
- Files changed:
  - macapp/MeetingListenerApp/Sources/MeetingListenerApp/**
- Tasks:
  1) Route streaming events into app state
  2) Update transcript with partial and final segments
  3) Update cards and entities on cadence
  4) Add export actions stubs
- Verification commands:
  - `cd macapp/MeetingListenerApp && swift build`
- Acceptance criteria:
  - Transcript, cards, and entities update with simulated events

## Acceptance test checklist
- Start opens panel and begins streaming
- Partial transcript renders within 2 to 5 seconds
- Cards update at least once per minute
- Stop produces final summary and export functions
- Handles backend disconnect with visible state and recovery

## Assumptions
- Swift Package Manager is acceptable for scaffolding the macOS app
- Backend stack will replace the stub server code in production
