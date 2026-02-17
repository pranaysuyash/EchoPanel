#!/bin/bash
# scripts/visual_proof_Feb16.sh
set -x

OUTPUT_DIR="/Users/pranay/.gemini/antigravity/brain/fafa2598-9634-4785-93cf-fda8b9f4c5bf"
PROJECT_ROOT="/Users/pranay/Projects/EchoPanel"
AUDIO_FILE="${PROJECT_ROOT}/llm_recording_pranay.wav"

cd "$PROJECT_ROOT"

# 1. Kill any existing processes
pkill -f "uvicorn server.main:app" || true
pkill -f "MeetingListenerApp-Dev" || true

# 2. Start Backend
source .venv/bin/activate
export ECHOPANEL_ASR_VAD=0
export ECHOPANEL_WHISPER_MODEL=base.en
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 > "${OUTPUT_DIR}/backend_live.log" 2>&1 &
BACKEND_PID=$!

# 3. Start App
open "/Users/pranay/Applications/MeetingListenerApp-Dev.app"
sleep 10

# 4. Bring App to Front
osascript -e 'tell application "MeetingListenerApp-Dev" to activate'
sleep 2

# 5. Start Screen Recording (30s)
ffmpeg -y -f avfoundation -i "1" -t 30 -pix_fmt yuv420p "${OUTPUT_DIR}/live_demonstration_fresh.mp4" > "${OUTPUT_DIR}/ffmpeg_live.log" 2>&1 &
FFMPEG_PID=$!

# 6. Start Audio Stream
python -u scripts/stream_test.py "$AUDIO_FILE" > "${OUTPUT_DIR}/stream_live.log" 2>&1 &
STREAM_PID=$!

# 7. Wait and take screenshot during active transcription
sleep 15
screencapture -x "${OUTPUT_DIR}/fresh_transcription_active.png"

# 8. Wait for finish
sleep 20

# 9. Cleanup
kill $BACKEND_PID $STREAM_PID $FFMPEG_PID || true
pkill -f "MeetingListenerApp-Dev" || true

echo "Demonstration complete. Artifacts in $OUTPUT_DIR"
