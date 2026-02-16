#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[verify] Running macapp build + tests (visual snapshots are opt-in via RUN_VISUAL_SNAPSHOTS=1)..."
cd "$ROOT_DIR/macapp/MeetingListenerApp"
swift build
swift test

echo "[verify] OK"
