#!/bin/bash
#
# Create DMG for EchoPanel macOS app
#
# Usage:
#   ./scripts/create_dmg.sh [path/to/EchoPanel.app] [output.dmg]
#
# Requirements:
#   - create-dmg (brew install create-dmg)
#   - App must be signed (for Gatekeeper compatibility)
#

set -e

# Configuration
APP_NAME="EchoPanel"
VERSION="0.2.0"
BUNDLE_ID="com.echopanel.app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"

# Parse arguments
APP_BUNDLE="${1:-$DIST_DIR/$APP_NAME.app}"
DMG_OUTPUT="${2:-$DIST_DIR/$APP_NAME-$VERSION.dmg}"

echo "💿 EchoPanel DMG Creator"
echo "========================"
echo ""

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}❌ App bundle not found: $APP_BUNDLE${NC}"
    echo ""
    echo "Build the app first with:"
    echo "  python scripts/build_app_bundle.py --release"
    exit 1
fi

echo "📦 App bundle: $APP_BUNDLE"
echo "💿 DMG output: $DMG_OUTPUT"
echo ""

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo -e "${YELLOW}⚠️  create-dmg not found. Installing...${NC}"
    if command -v brew &> /dev/null; then
        brew install create-dmg
    else
        echo -e "${RED}❌ Homebrew not found. Please install create-dmg manually:${NC}"
        echo "  brew install create-dmg"
        exit 1
    fi
fi

# Check code signing
echo "🔏 Checking code signature..."
if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo -e "${GREEN}✅ App is signed${NC}"
    codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Signature|Authority|TeamIdentifier"
else
    echo -e "${YELLOW}⚠️  App is not signed (Gatekeeper will block)${NC}"
    echo "   To sign: python scripts/build_app_bundle.py"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Create DMG
echo "💿 Creating DMG..."

# Remove existing DMG
if [ -f "$DMG_OUTPUT" ]; then
    echo "🗑️  Removing existing DMG..."
    rm "$DMG_OUTPUT"
fi

# Create temp directory for DMG contents
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy app to temp dir
cp -R "$APP_BUNDLE" "$TEMP_DIR/"

# Create DMG with create-dmg
create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-pos 200 120 \
    --window-size 800 500 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 200 200 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 600 200 \
    --eula "$PROJECT_ROOT/LICENSE" \
    --background "$PROJECT_ROOT/assets/dmg_background.png" \
    "$DMG_OUTPUT" \
    "$TEMP_DIR" \
    2>/dev/null || {
    # Fallback to basic hdiutil if create-dmg fails
    echo -e "${YELLOW}⚠️  create-dmg failed, using basic hdiutil...${NC}"
    
    # Create temporary DMG
    TEMP_DMG="$TEMP_DIR/temp.dmg"
    hdiutil create -srcfolder "$TEMP_DIR" -volname "$APP_NAME $VERSION" -fs HFS+ -format UDRW "$TEMP_DMG"
    
    # Convert to compressed read-only
    hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_OUTPUT"
}

# Verify DMG
echo ""
echo "🔍 Verifying DMG..."
if [ -f "$DMG_OUTPUT" ]; then
    SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)
    echo -e "${GREEN}✅ DMG created successfully${NC}"
    echo "   Path: $DMG_OUTPUT"
    echo "   Size: $SIZE"
    
    # Test mount
    echo ""
    echo "🔍 Testing DMG mount..."
    MOUNT_TEST=$(hdiutil attach "$DMG_OUTPUT" -readonly -nobrowse 2>&1 | grep -o '/Volumes/.*' | head -1)
    if [ -n "$MOUNT_TEST" ]; then
        echo -e "${GREEN}✅ DMG mounts correctly${NC}"
        hdiutil detach "$MOUNT_TEST" -quiet 2>/dev/null || true
    else
        echo -e "${YELLOW}⚠️  Could not test mount${NC}"
    fi
    
    # Calculate hash
    echo ""
    echo "🔐 SHA256:"
    shasum -a 256 "$DMG_OUTPUT" | cut -d' ' -f1
    
else
    echo -e "${RED}❌ DMG creation failed${NC}"
    exit 1
fi

echo ""
echo "✨ Done!"
echo ""
echo "Next steps:"
echo "  1. Test the DMG: hdiutil attach \"$DMG_OUTPUT\""
echo "  2. Notarize (requires Apple Developer ID): xcrun altool --notarize-app ..."
echo "  3. Upload to distribution"
