#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/macapp/MeetingListenerApp"
BUILD_DIR="$APP_DIR/.build/release"
SWIFT_BINARY="MeetingListenerApp"
SWIFT_BINARY_PATH="$BUILD_DIR/$SWIFT_BINARY"
INSTALL_DIR="$HOME/Applications"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INSTALL_TARGET="$INSTALL_DIR"
APP_BUNDLE="$INSTALL_TARGET/MeetingListenerApp-Dev.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_EXECUTABLE="EchoPanel"
PLIST_PATH="$APP_CONTENTS/Info.plist"
APP_ID="com.echopanel.app.dev"
VERSION="0.2.0-dev"
BUILD_ID="$(date +%Y%m%d%H%M)"
GIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "================================================"
echo "  EchoPanel Dev Build — $TIMESTAMP"
echo "  Git: $GIT_SHA"
echo "================================================"
echo ""

echo "Step 1: Building Swift binary (release)..."
cd "$APP_DIR"
swift build -c release

echo ""
echo "Step 2: Installing to $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$SWIFT_BINARY_PATH" "$APP_MACOS/$APP_EXECUTABLE"
chmod +x "$APP_MACOS/$APP_EXECUTABLE"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>EchoPanel</string>
    <key>CFBundleDisplayName</key>
    <string>EchoPanel Dev</string>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE</string>
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
    <key>EchoPanelBuildTimestamp</key>
    <string>$TIMESTAMP</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Capture meeting audio from apps like Zoom, Meet, and Teams for local transcription.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Capture microphone audio for real-time meeting transcripts and highlights.</string>
</dict>
</plist>
EOF

echo ""
echo "Step 3: Signing app bundle..."
codesign --force --sign - --deep "$APP_BUNDLE"

echo ""
echo "================================================"
echo "  Build Complete"
echo "================================================"
echo ""
echo "  App location:  $APP_BUNDLE"
echo "  Timestamp:     $TIMESTAMP"
echo "  Git SHA:       $GIT_SHA"
echo ""
echo "  Launch with:"
echo "    open \"$APP_BUNDLE\""
echo ""
echo "  Permissions note:"
echo "    macOS ties Screen Recording permission to the app path and code identity."
echo "    This script preserves a stable dev path so permissions stay attached."
echo "================================================"
