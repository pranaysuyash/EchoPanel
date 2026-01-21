#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PATH="$HOME/Applications/MeetingListenerApp-Dev"

"$ROOT_DIR/scripts/build-dev-app.sh"

echo "Launching $INSTALL_PATH"
open -a "$INSTALL_PATH"
