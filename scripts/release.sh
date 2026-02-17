#!/bin/bash
#
# EchoPanel Release Script
#
# Builds, signs, notarizes, and packages the macOS app for distribution.
#
# Requirements:
#   - macOS with Xcode installed
#   - Apple Developer Program membership
#   - Notarization credentials in Keychain (xcrun notarytool store-credentials)
#
# Usage:
#   ./scripts/release.sh [version]
#

set -e

# Configuration
APP_NAME="EchoPanel"
BUNDLE_ID="com.echopanel.app"
VERSION="${1:-0.2.0}"
TEAM_ID="" # Will be detected from signing certificate

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"

echo -e "${BLUE}🚀 EchoPanel Release Script${NC}"
echo "============================"
echo ""
echo "Version: $VERSION"
echo "Bundle ID: $BUNDLE_ID"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Xcode not found${NC}"
    exit 1
fi

# Check for Developer ID certificate
echo "🔏 Checking signing certificate..."
CERT_INFO=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1)
if [ -z "$CERT_INFO" ]; then
    echo -e "${RED}❌ No Developer ID Application certificate found${NC}"
    echo ""
    echo "You need to:"
    echo "  1. Enroll in Apple Developer Program ($99/year)"
    echo "  2. Create a Developer ID Application certificate"
    echo "  3. Download and install it in Keychain"
    exit 1
fi

CERT_NAME=$(echo "$CERT_INFO" | sed -n 's/.*"\(.*\)".*/\1/p')
TEAM_ID=$(echo "$CERT_INFO" | grep -o '\(([A-Z0-9]*)\)' | tr -d '()')
echo -e "${GREEN}✅ Found certificate: $CERT_NAME${NC}"
echo "   Team ID: $TEAM_ID"
echo ""

# Check notarization credentials
echo "🔐 Checking notarization credentials..."
if ! xcrun notarytool list 2>/dev/null | grep -q "$TEAM_ID"; then
    echo -e "${YELLOW}⚠️  Notarization credentials not found${NC}"
    echo ""
    echo "To set up notarization:"
    echo "  xcrun notarytool store-credentials \"AC_PASSWORD\" \""
    echo "    --apple-id \"your@email.com\" \""
    echo "    --team-id \"$TEAM_ID\" \""
    echo "    --password \"<app-specific-password>\""
    echo ""
    read -p "Continue without notarization? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_NOTARIZE=1
else
    echo -e "${GREEN}✅ Notarization credentials found${NC}"
    SKIP_NOTARIZE=0
fi

echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build the app
echo ""
echo -e "${BLUE}🔨 Building app bundle...${NC}"
python "$SCRIPT_DIR/build_app_bundle.py" --release

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build complete${NC}"
echo ""

# Sign the app
echo -e "${BLUE}🔏 Signing app...${NC}"
ENTITLEMENTS="$DIST_DIR/EchoPanel.entitlements"

# Deep sign the app
codesign --force --deep --sign "Developer ID Application" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

# Verify signature
echo "🔍 Verifying signature..."
if codesign --verify --deep --strict "$APP_BUNDLE" 2>&1; then
    echo -e "${GREEN}✅ Signature valid${NC}"
else
    echo -e "${YELLOW}⚠️  Signature verification had issues${NC}"
fi

echo ""

# Notarize (optional)
if [ "$SKIP_NOTARIZE" = "0" ]; then
    echo -e "${BLUE}📤 Notarizing app...${NC}"
    
    # Create zip for notarization
    ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    
    # Submit for notarization
    echo "⏳ Submitting to Apple notarization service..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "AC_PASSWORD" \
        --wait \
        2>&1 | tee "$DIST_DIR/notarization.log"
    
    # Check result
    if grep -q "status: Accepted" "$DIST_DIR/notarization.log"; then
        echo -e "${GREEN}✅ Notarization accepted${NC}"
        
        # Staple the ticket
        echo "📝 Stapling notarization ticket..."
        xcrun stapler staple "$APP_BUNDLE"
    else
        echo -e "${YELLOW}⚠️  Notarization may have failed, check log${NC}"
    fi
    
    echo ""
fi

# Create DMG
echo -e "${BLUE}💿 Creating DMG...${NC}"
"$SCRIPT_DIR/create_dmg.sh" "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo -e "${GREEN}🎉 Release complete!${NC}"
echo ""
echo "Artifacts:"
ls -lh "$DIST_DIR/"
echo ""
echo "Next steps:"
echo "  1. Test the DMG on a clean macOS install"
echo "  2. Upload to GitHub Releases or distribution platform"
echo "  3. Update website download links"
echo ""
