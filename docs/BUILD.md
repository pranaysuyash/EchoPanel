# Building EchoPanel

**Last Updated:** 2026-02-12  
**Version:** 0.2.0

This document describes how to build EchoPanel from source.

---

## Prerequisites

- macOS 13.0+
- Xcode 15+ (for Swift build)
- Python 3.11+ (for development mode)
- PyInstaller 6.0+ (for bundling backend)
- `create-dmg` tool (for DMG creation): `brew install create-dmg`

---

## Quick Build

### Full Release Build (First Time)

```bash
python scripts/build_app_bundle.py --release
```

This creates:
- `dist/EchoPanel.app` — Self-contained app bundle (81MB)
- `dist/EchoPanel-0.2.0.dmg` — Distribution DMG (73MB)
- `dist/echopanel-server` — Standalone backend (74MB)

### Incremental Build (Using Cached Artifacts)

```bash
# If Swift code hasn't changed
python scripts/build_app_bundle.py --release --skip-swift

# If backend hasn't changed
python scripts/build_app_bundle.py --release --skip-backend

# Skip both (just repackage)
python scripts/build_app_bundle.py --release --skip-swift --skip-backend
```

---

## Manual Build Steps

### 1. Build Swift Executable

```bash
cd macapp/MeetingListenerApp
swift build -c release
```

Output: `.build/arm64-apple-macosx/release/MeetingListenerApp`

### 2. Build Python Backend

```bash
python -m PyInstaller scripts/echopanel-server.spec --clean --noconfirm
```

Output: `dist/echopanel-server` (74MB standalone executable)

### 3. Create App Bundle

The build script does this automatically, but manual structure is:

```
EchoPanel.app/
├── Contents/
│   ├── MacOS/
│   │   └── EchoPanel              # Swift executable (10MB)
│   ├── Resources/
│   │   ├── echopanel-server       # Python backend (74MB)
│   │   └── entitlements.plist
│   └── Info.plist
```

### 4. Create DMG

```bash
create-dmg \
  --volname "EchoPanel Installer" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "dist/EchoPanel-0.2.0.dmg" \
  "dist/EchoPanel.app"
```

---

## Development Mode

For development (without bundling):

```bash
# Terminal 1: Start backend
cd server
uvicorn main:app --reload --port 8000

# Terminal 2: Run Swift app
cd macapp/MeetingListenerApp
swift run
```

The app will auto-detect development mode and use Python backend instead of bundled executable.

---

## Testing

### Swift Tests

```bash
cd macapp/MeetingListenerApp
swift test
```

Expected: "Executed 73 tests, with 0 failures"

### Python Tests

```bash
.venv/bin/pytest -q tests/
```

Expected: All tests pass

### App Launch Test

```bash
# Test bundled app
open dist/EchoPanel.app

# Check process is running
ps aux | grep EchoPanel
```

---

## Troubleshooting

### "No module named pip" Error

The build script uses `uv` for Python management. Ensure you have `uv` installed:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Swift Build Fails

```bash
# Clean build
cd macapp/MeetingListenerApp
swift package clean
swift build
```

### PyInstaller Missing Imports

Some imports (torchaudio, scipy, whisper) are optional and warnings can be ignored. If the build succeeds, the app should work.

### Code Signing Issues

The app is unsigned by default. To run on your Mac:

```bash
# Right-click app → Open, or:
codesign --force --deep --sign - dist/EchoPanel.app
```

For distribution, you need Apple Developer Program ($99/year) for proper code signing.

---

## Build Outputs

| File | Size | Purpose |
|------|------|---------|
| `dist/EchoPanel.app` | 81 MB | macOS app bundle |
| `dist/EchoPanel-0.2.0.dmg` | 73 MB | Distribution installer |
| `dist/echopanel-server` | 74 MB | Standalone backend |
| `build/` | — | Build artifacts (can delete) |

---

## Related Documentation

- `docs/STATUS_AND_ROADMAP.md` — Current project status
- `docs/WORKLOG_TICKETS.md` — All completed/pending work
- `docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md` — Launch tasks
- `scripts/build_app_bundle.py --help` — Build script options
