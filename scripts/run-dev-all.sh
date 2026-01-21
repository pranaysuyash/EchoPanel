#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
APP_BUNDLE="$HOME/Applications/MeetingListenerApp.app"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Missing venv at $VENV_DIR"
  echo "Run: uv venv .venv && source .venv/bin/activate && uv pip install -e \".[dev]\""
  exit 1
fi

source "$VENV_DIR/bin/activate"

echo "Building app bundle..."
"$ROOT_DIR/scripts/build-app-bundle.sh"

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
open "$APP_BUNDLE"

echo "Backend running (PID $SERVER_PID). Press Ctrl+C to stop."
wait "$SERVER_PID"
