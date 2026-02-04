#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/macapp/MeetingListenerApp"
BUILD_DIR="$APP_DIR/.build/release"
APP_NAME="MeetingListenerApp"
APP_PATH="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME-Dev.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
PLIST_PATH="$APP_CONTENTS/Info.plist"
APP_ID="com.echopanel.meetinglistener.dev"
VERSION="0.2.0-dev"
BUILD_ID="$(date +%Y%m%d%H%M)"
GIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "Building $APP_NAME (release)..."
cd "$APP_DIR"
swift build -c release

echo "Installing to $APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$APP_PATH" "$APP_MACOS/$APP_NAME"
chmod +x "$APP_MACOS/$APP_NAME"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME Dev</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_ID</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION+$GIT_SHA</string>
    <key>EchoPanelGitSHA</key>
    <string>$GIT_SHA</string>
    <key>EchoPanelBuildID</key>
    <string>$BUILD_ID</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Capture microphone audio for real-time meeting transcripts and highlights.</string>
</dict>
</plist>
EOF

echo "Signing app bundle..."
codesign --force --sign - --deep "$APP_BUNDLE"

echo "Done. Run:"
echo "  open \"$APP_BUNDLE\""
