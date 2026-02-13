#!/bin/bash
# scripts/record_autonomous_test.sh
# Record an autonomous UI test of the EchoPanel Mac application.

# Configuration
OUTPUT_DIR="/Users/pranay/.gemini/antigravity/brain/fafa2598-9634-4785-93cf-fda8b9f4c5bf"
RECORDING_FILE="${OUTPUT_DIR}/autonomous_test.mp4"
DURATION=30 # Recording duration in seconds
APP_NAME="MeetingListenerApp"
PROJECT_ROOT="/Users/pranay/Projects/EchoPanel"

# 1. Start Backend in background
echo "Starting backend..."
cd "$PROJECT_ROOT"
source .venv/bin/activate
export ECHOPANEL_ASR_VAD=0
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 > /tmp/record_backend.log 2>&1 &
BACKEND_PID=$!

# 2. Start Mac App in background
echo "Starting Mac app..."
./scripts/run-dev-app.sh > /tmp/record_app.log 2>&1 &
APP_PID=$!

# Wait for app to initialize
sleep 5

# 3. Start FFmpeg recording
# Using device [1] Capture screen 0 (from ffmpeg -devices)
echo "Starting screen recording..."
ffmpeg -y -f avfoundation -i "1" -t "$DURATION" -pix_fmt yuv420p "$RECORDING_FILE" > /tmp/record_ffmpeg.log 2>&1 &
FFMPEG_PID=$!

# 4. Use AppleScript for autonomous UI interaction
echo "Running autonomous UI interaction..."
osascript <<EOD
tell application "System Events"
    -- Wait for the app process
    repeat 10 times
        if exists process "$APP_NAME" then exit repeat
        delay 1
    end repeat
    
    tell process "$APP_NAME"
        set frontmost to true
        delay 2
        
        -- Try to find and click "Start Demo" button
        -- Note: This is an example, adjustment might be needed based on actual UI hierarchy
        try
            click button "Start Demo" of window 1
            log "Clicked Start Demo"
        on error
            log "Could not find Start Demo button"
        end try
    end tell
end tell
EOD

# 5. Wait for recording to complete
echo "Waiting for recording to finish ($DURATION seconds)..."
sleep "$DURATION"

# 6. Cleanup
echo "Cleaning up..."
kill "$FFMPEG_PID" || true
kill "$BACKEND_PID" || true
kill "$APP_PID" || true

echo "Recording saved to: $RECORDING_FILE"
