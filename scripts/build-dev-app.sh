#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/macapp/MeetingListenerApp"
BUILD_DIR="$APP_DIR/.build/release"
APP_NAME="MeetingListenerApp"
APP_PATH="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="$HOME/Applications"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME-Dev"

echo "Building $APP_NAME (release)..."
cd "$APP_DIR"
swift build -c release

echo "Signing binary..."
codesign --force --sign - "$APP_PATH"

echo "Installing to $INSTALL_PATH"
mkdir -p "$INSTALL_DIR"
cp "$APP_PATH" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "Done. Run:"
echo "  $INSTALL_PATH"
