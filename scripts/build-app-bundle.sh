#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/macapp/MeetingListenerApp"
APP_NAME="MeetingListenerApp"
# Use the canonical production bundle ID so TCC/keychain mappings stay stable across build flows.
BUNDLE_ID="com.echopanel.app"
INSTALL_DIR="$HOME/Applications"
BUNDLE_PATH="$INSTALL_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Optional: set SIGN_ID to a real signing identity (e.g. "Developer ID Application: Acme, Inc.")
SIGN_ID="${SIGN_ID:--}"

echo "Building $APP_NAME (release)..."
cd "$APP_DIR"
swift build -c release

echo "Creating app bundle at $BUNDLE_PATH"
rm -rf "$BUNDLE_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>EchoPanel</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>EchoPanel can optionally capture your microphone audio for more accurate transcription.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>EchoPanel captures meeting audio from your screen to generate transcripts and summaries. No audio leaves your Mac.</string>
</dict>
</plist>
EOF

# Prefer a real signing identity when available — fall back to ad-hoc when not set.
if [ "$SIGN_ID" = "-" ]; then
  echo "Signing bundle with ad-hoc identity (development fallback)..."
  codesign --force --deep --sign - "$BUNDLE_PATH"
else
  echo "Signing bundle with identity: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" --entitlements "$APP_DIR/App.entitlements" "$BUNDLE_PATH"
fi

echo "Done. Launch with:"
echo "  open \"$BUNDLE_PATH\""
