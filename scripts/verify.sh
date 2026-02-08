#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[verify] Running macapp build + tests (includes visual snapshots)..."
cd "$ROOT_DIR/macapp/MeetingListenerApp"
swift build
swift test

echo "[verify] OK"
