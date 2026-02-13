#!/usr/bin/env python3
"""
Build script for EchoPanel macOS .app bundle with bundled Python backend.

This script:
1. Uses PyInstaller to bundle the Python backend as a standalone executable
2. Creates the .app bundle structure
3. Copies the Swift executable and resources
4. Signs the bundle (if certificates are available)

Usage:
    python scripts/build_app_bundle.py [--release]
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


# Configuration
APP_NAME = "EchoPanel"
BUNDLE_ID = "com.echopanel.app"
VERSION = "0.2.0"
MIN_MACOS = "13.0"

# Paths
PROJECT_ROOT = Path(__file__).parent.parent
MACAPP_DIR = PROJECT_ROOT / "macapp" / "MeetingListenerApp"
BUILD_DIR = PROJECT_ROOT / "build"
DIST_DIR = PROJECT_ROOT / "dist"
SERVER_DIR = PROJECT_ROOT / "server"
PYINSTALLER_SPEC = PROJECT_ROOT / "scripts" / "echopanel-server.spec"


def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """Run a shell command."""
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)


def build_swift_executable(release: bool = False) -> Path:
    """Build the Swift executable using swift build."""
    print("\n🔨 Building Swift executable...")
    
    config = "release" if release else "debug"
    cmd = ["swift", "build", "-c", config]
    
    result = run(cmd, cwd=MACAPP_DIR)
    if result.returncode != 0:
        print(f"❌ Swift build failed:\n{result.stderr}")
        sys.exit(1)
    
    # Find the built executable
    build_path = MACAPP_DIR / ".build" / "arm64-apple-macosx" / config / "MeetingListenerApp"
    if not build_path.exists():
        # Try universal build path
        build_path = MACAPP_DIR / ".build" / "debug" / "MeetingListenerApp"
    
    if not build_path.exists():
        print(f"❌ Could not find built executable")
        sys.exit(1)
    
    print(f"✅ Swift executable built: {build_path}")
    return build_path


def build_pyinstaller_backend() -> Path:
    """Build the Python backend using PyInstaller."""
    print("\n📦 Building Python backend with PyInstaller...")
    
    # Ensure PyInstaller is installed
    result = run([sys.executable, "-m", "pip", "show", "pyinstaller"], check=False)
    if result.returncode != 0:
        print("📥 Installing PyInstaller...")
        run([sys.executable, "-m", "pip", "install", "pyinstaller"])
    
    # Clean previous builds
    pyinstaller_dist = PROJECT_ROOT / "dist"
    pyinstaller_build = PROJECT_ROOT / "build" / "pyinstaller"
    if pyinstaller_dist.exists():
        shutil.rmtree(pyinstaller_dist)
    if pyinstaller_build.exists():
        shutil.rmtree(pyinstaller_build)
    
    # Run PyInstaller
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--clean",
        "--noconfirm",
        str(PYINSTALLER_SPEC)
    ]
    
    result = run(cmd, cwd=PROJECT_ROOT)
    if result.returncode != 0:
        print(f"❌ PyInstaller failed:\n{result.stderr}")
        sys.exit(1)
    
    # Find the built executable
    backend_exe = DIST_DIR / "echopanel-server"
    if not backend_exe.exists():
        print(f"❌ Could not find PyInstaller output")
        sys.exit(1)
    
    print(f"✅ Python backend built: {backend_exe}")
    return backend_exe


def create_app_bundle(swift_exe: Path, backend_exe: Path, release: bool = False) -> Path:
    """Create the .app bundle structure."""
    print("\n📁 Creating .app bundle...")
    
    # Clean previous bundle
    app_bundle = DIST_DIR / f"{APP_NAME}.app"
    if app_bundle.exists():
        shutil.rmtree(app_bundle)
    
    # Create bundle structure
    contents = app_bundle / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    frameworks = contents / "Frameworks"
    
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    frameworks.mkdir(parents=True)
    
    # Copy Swift executable
    app_exe = macos / APP_NAME
    shutil.copy2(swift_exe, app_exe)
    os.chmod(app_exe, 0o755)
    
    # Copy backend executable to Resources
    backend_dest = resources / "echopanel-server"
    shutil.copy2(backend_exe, backend_dest)
    os.chmod(backend_dest, 0o755)
    
    # Create Info.plist
    info_plist = contents / "Info.plist"
    info_plist.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>{APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>{BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>{MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 EchoPanel. All rights reserved.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>EchoPanel captures meeting audio from your screen to generate transcripts and summaries. No audio leaves your Mac.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>EchoPanel can optionally capture your microphone audio for more accurate transcription.</string>
</dict>
</plist>
''')
    
    # Create entitlements file for signing
    entitlements = DIST_DIR / "EchoPanel.entitlements"
    entitlements.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for PyInstaller bundled Python -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    
    <!-- Audio permissions -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    
    <!-- Network permissions -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    
    <!-- File system permissions -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    
    <!-- No sandbox for now (simplifies PyInstaller) -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
''')
    
    print(f"✅ App bundle created: {app_bundle}")
    return app_bundle


def sign_app_bundle(app_bundle: Path, entitlements: Path) -> None:
    """Sign the app bundle if certificates are available."""
    print("\n🔏 Signing app bundle...")
    
    # Check for Developer ID certificate
    result = run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        check=False
    )
    
    if "Developer ID Application" not in result.stdout:
        print("⚠️  No Developer ID certificate found. Skipping signing.")
        print("   The app will need to be signed before distribution.")
        return
    
    # Sign the backend executable first
    backend_exe = app_bundle / "Contents" / "Resources" / "echopanel-server"
    run([
        "codesign", "--force", "--sign", "Developer ID Application",
        "--options", "runtime",
        str(backend_exe)
    ], check=False)
    
    # Sign the main app
    run([
        "codesign", "--force", "--deep", "--sign", "Developer ID Application",
        "--options", "runtime",
        "--entitlements", str(entitlements),
        str(app_bundle)
    ], check=False)
    
    # Verify
    result = run(["codesign", "--verify", "--deep", "--strict", str(app_bundle)], check=False)
    if result.returncode == 0:
        print("✅ App bundle signed successfully")
    else:
        print(f"⚠️  Signing verification failed: {result.stderr}")


def create_dmg(app_bundle: Path) -> Path:
    """Create a DMG for distribution."""
    print("\n💿 Creating DMG...")
    
    dmg_path = DIST_DIR / f"{APP_NAME}-{VERSION}.dmg"
    
    # Check if create-dmg is installed
    result = run(["which", "create-dmg"], check=False)
    if result.returncode != 0:
        print("⚠️  create-dmg not found. Installing...")
        run(["brew", "install", "create-dmg"], check=False)
    
    # Create DMG
    if dmg_path.exists():
        dmg_path.unlink()
    
    cmd = [
        "create-dmg",
        "--volname", f"{APP_NAME} {VERSION}",
        "--window-pos", "200", "120",
        "--window-size", "800", "400",
        "--icon-size", "100",
        "--app-drop-link", "600", "185",
        str(dmg_path),
        str(app_bundle)
    ]
    
    result = run(cmd, check=False)
    if result.returncode == 0:
        print(f"✅ DMG created: {dmg_path}")
        return dmg_path
    else:
        print(f"⚠️  DMG creation failed: {result.stderr}")
        return dmg_path


def main():
    parser = argparse.ArgumentParser(description="Build EchoPanel .app bundle")
    parser.add_argument("--release", action="store_true", help="Build release version")
    parser.add_argument("--skip-swift", action="store_true", help="Skip Swift build (use existing)")
    parser.add_argument("--skip-backend", action="store_true", help="Skip backend build (use existing)")
    parser.add_argument("--skip-dmg", action="store_true", help="Skip DMG creation")
    args = parser.parse_args()
    
    print(f"🚀 Building {APP_NAME} v{VERSION}")
    print(f"   Project root: {PROJECT_ROOT}")
    
    # Clean and create build directories
    BUILD_DIR.mkdir(exist_ok=True)
    DIST_DIR.mkdir(exist_ok=True)
    
    # Build Swift executable
    if args.skip_swift:
        config = "release" if args.release else "debug"
        swift_exe = MACAPP_DIR / ".build" / "arm64-apple-macosx" / config / "MeetingListenerApp"
        if not swift_exe.exists():
            swift_exe = MACAPP_DIR / ".build" / "debug" / "MeetingListenerApp"
        print(f"⏭️  Using existing Swift executable: {swift_exe}")
    else:
        swift_exe = build_swift_executable(args.release)
    
    # Build Python backend
    if args.skip_backend:
        backend_exe = DIST_DIR / "echopanel-server"
        print(f"⏭️  Using existing backend: {backend_exe}")
    else:
        backend_exe = build_pyinstaller_backend()
    
    # Create app bundle
    app_bundle = create_app_bundle(swift_exe, backend_exe, args.release)
    
    # Sign bundle
    entitlements = DIST_DIR / "EchoPanel.entitlements"
    sign_app_bundle(app_bundle, entitlements)
    
    # Create DMG
    if not args.skip_dmg:
        create_dmg(app_bundle)
    
    print(f"\n✨ Build complete!")
    print(f"   App bundle: {app_bundle}")
    print(f"   Size: {app_bundle.stat().st_size / (1024*1024):.1f} MB")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
