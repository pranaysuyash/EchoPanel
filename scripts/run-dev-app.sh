#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$HOME/Applications/MeetingListenerApp-Dev.app"

"$ROOT_DIR/scripts/build-dev-app.sh"

echo "Launching $APP_BUNDLE"
open "$APP_BUNDLE"
