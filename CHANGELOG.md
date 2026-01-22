# Changelog

All notable changes to this project will be documented in this file.

## [v0.2.0] - 2026-01-22

### 🚀 New Features
- **Multi-Source Audio**: Simultaneous capture of System Audio and Microphone using source-tagged JSON protocol.
- **Diarization**: Support for speaker labeling (requires HuggingFace token).
- **Session Recovery**: Crash recovery UI to restore previous sessions on launch.
- **Audio Meters**: Live level meters for both System and Microphone inputs.
- **Onboarding**: First-run wizard for permissions, audio source selection, and model configuration.
- **Auto-Save**: Real-time append-only transcript logging for data durability.

### 🐛 Bug Fixes (Audit Resolution)
- **Protocol**: Fixed binary audio frame handling by moving to JSON frames with explicit `source` tags (Fixes B1).
- **Confidence**: Replaced hardcoded 0.7 confidence with actual ASR segment scores (Fixes B2).
- **Health Check**: Updated `/health` endpoint to verify ASR model availability (Fixes B3).
- **Entity Counts**: Added missing `count` field to entity extraction and propagation (Fixes H5).
- **Export**: Fixed missing speaker labels in final export summary (Fixes H8).
- **Server Startup**: Added UI alerts when Python backend fails to start (Fixes H9).

### 🛠 Improvements
- **Rolling Summary**: Improved context separation into "Overall Highlights" vs "Recent Context" (Fixes H10).
- **Documentation**: Added `WS_CONTRACT.md` v0.2 spec and `.env.example`.
- **Testing**: Added integration tests for multi-source audio flow.

## [v0.1.0] - Initial Release
- Basic System Audio capture (ScreenCaptureKit).
- Local FasterWhisper ASR.
- Real-time transcription and basic entity extraction.
