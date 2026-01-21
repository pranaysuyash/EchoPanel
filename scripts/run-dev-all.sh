#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
APP_BUNDLE="$HOME/Applications/MeetingListenerApp.app"
ENABLE_ASR=1
ENABLE_DIARIZATION=0
SKIP_BUILD=0

for arg in "$@"; do
  if [[ "$arg" == "--no-asr" ]]; then
    ENABLE_ASR=0
  elif [[ "$arg" == "--no-build" ]]; then
    SKIP_BUILD=1
  elif [[ "$arg" == "--diarization" ]]; then
    ENABLE_DIARIZATION=1
  fi
done

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Missing venv at $VENV_DIR"
  echo "Run: uv venv .venv && source .venv/bin/activate && uv pip install -e \".[dev]\""
  exit 1
fi

source "$VENV_DIR/bin/activate"

if [[ "$ENABLE_ASR" -eq 1 ]]; then
  echo "Installing ASR extras..."
  uv pip install -e ".[asr]"
  export ECHOPANEL_WHISPER_MODEL="${ECHOPANEL_WHISPER_MODEL:-base}"
  if [[ -z "${ECHOPANEL_WHISPER_DEVICE:-}" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      export ECHOPANEL_WHISPER_DEVICE="metal"
      export ECHOPANEL_WHISPER_COMPUTE="${ECHOPANEL_WHISPER_COMPUTE:-int8_float16}"
    else
      export ECHOPANEL_WHISPER_DEVICE="auto"
      export ECHOPANEL_WHISPER_COMPUTE="${ECHOPANEL_WHISPER_COMPUTE:-int8}"
    fi
  fi
fi

if [[ "$ENABLE_DIARIZATION" -eq 1 ]]; then
  echo "Installing diarization extras..."
  uv pip install -e ".[diarization]"
  export ECHOPANEL_DIARIZATION=1
  if [[ -z "${ECHOPANEL_HF_TOKEN:-}" ]]; then
    echo "Missing ECHOPANEL_HF_TOKEN for pyannote models. Diarization will be skipped."
  fi
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "Building app bundle..."
  "$ROOT_DIR/scripts/build-app-bundle.sh"
else
  echo "Skipping app bundle build (--no-build)"
fi

echo "Starting backend..."
python -m server.main &
SERVER_PID=$!

cleanup() {
  if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID"
  fi
}
trap cleanup EXIT

sleep 1

echo "Launching app..."
if [[ "${ECHOPANEL_DEBUG:-0}" == "1" ]]; then
  open "$APP_BUNDLE" --args --debug
else
  open "$APP_BUNDLE"
fi

echo "Backend running (PID $SERVER_PID). Press Ctrl+C to stop."
wait "$SERVER_PID"
