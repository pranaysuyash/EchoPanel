# Audio Pipeline Rate Limiting Issue

**Date:** 2026-02-13  
**Status:** IN PROGRESS
**Severity:** P0 - Core functionality broken

## Summary of Issues Faced

### Issue 1: App Didn't Detect Existing Server
- **Symptom:** App showed "Backend Starting" and Start button was greyed out
- **Root Cause:** App was trying to launch its own server instead of detecting existing one on port 8000
- **Fix:** The app should detect existing backend via health check

### Issue 2: "Connected" Status Treated as Error
- **Symptom:** Session would start then immediately stop
- **Root Cause:** Server sends initial status "connected, waiting for start" but client treated any non-streaming status as error
- **Fix:** WebSocketStreamer.swift - map "connected" to .reconnecting instead of .error (TCK-20260213-036)

### Issue 3: Dual-Path Audio Not Respecting User Selection
- **Symptom:** Audio capture not working regardless of source selection
- **Root Cause:** RedundantAudioCaptureManager always started dual capture regardless of user setting
- **Fix:** AppState.swift - respect user's AudioSource selection

### Issue 4: Audio Overload / No Transcripts
- **Symptom:** Server shows "Dropping system due to extreme overload", no transcripts
- **Root Cause:** Multiple issues:
  - Client sends audio faster than real-time
  - Server queue too small (50 frames)
  - Single inference thread
- **Fixes Attempted:**
  - Added 20ms rate limiting in WebSocketStreamer
  - Increased server queue sizes to 100/200
  - Tested with tiny model

### Issue 5: Browser Audio Capture
- **Finding:** Works with ScreenCaptureKit - earlier DRM assumption was incorrect
- **Verification:** Tested with browser audio and saw audio buffers received

## Current Status

As of 2026-02-13 22:40:
- Server runs and is healthy
- App detects server and shows "Backend Ready"
- Session starts but audio still has issues
- More investigation needed

## What Was Changed

### Client (Swift) Changes
- `WebSocketStreamer.swift`: Added rate limiting (20ms interval)
- `WebSocketStreamer.swift`: Fixed "connected" status mapping
- `AppState.swift`: Fixed dual-path audio selection

### Server (Python) Changes
- `concurrency_controller.py`: Increased queue sizes from 50/100 to 100/200
- Default model selection: auto-detect based on RAM

## Lessons Learned

1. Always verify assumptions with tests
2. Don't assume DRM blocks browser audio without testing
3. Rate limiting must be at correct layer
4. Server ASR processing speed is critical for real-time

## Next Steps

1. Debug why rate-limited client still causes server overload
2. Implement dual-mode: real-time (tiny) vs batch (better model)
3. Add proper backpressure handling
