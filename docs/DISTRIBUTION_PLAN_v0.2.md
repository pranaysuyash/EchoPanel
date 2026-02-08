# EchoPanel v0.2 - Distribution & Deployment Plan

## Current State Analysis

### What Works ✅

- Swift app compiles as command-line executable
- Backend server runs locally via embedded BackendManager
- Python dependencies in venv work for development

### What's Missing ❌ (LAUNCH BLOCKERS)

- No `.app` bundle (currently Swift Package Manager executable)
- No bundled Python runtime (**CRITICAL: macOS 13+ does NOT include Python by default**)
- No bundled Whisper models (downloads 3-5GB on first run with no UI)
- No code signing or notarization (Gatekeeper will block)
- No DMG/installer package
- No user-friendly installation instructions

### ⚠️ IMPORTANT: Python is NOT included in modern macOS

- **macOS 12.3+**: Apple removed Python 2.7 completely
- **macOS 13+** (Ventura): No Python at all in base system
- **macOS 14+** (Sonoma): Still no Python
- **Conclusion**: We MUST bundle Python runtime - cannot rely on system Python!

---

## Distribution Strategy: Self-Contained .app Bundle

### User Experience Goal

1. User receives invite email with download link
2. User downloads `EchoPanel.dmg` (500MB-1GB)
3. User drags app to Applications folder
4. User opens app → macOS asks for Screen Recording permission
5. Onboarding wizard completes setup (HF token optional)
6. App downloads Whisper model on first session with progress bar
7. User starts first meeting capture

**No terminal commands. No Python installation. No manual setup.**

---

## Implementation Phases

### PHASE 1: Convert to Xcode App Bundle (4-6h)

#### Step 1.1: Create Xcode macOS App Project

**Files to create**:

- `macapp/EchoPanel.xcodeproj/` - Xcode project
- `macapp/EchoPanel/Info.plist` - App metadata
- `macapp/EchoPanel/EchoPanel.entitlements` - Permissions

**Info.plist requirements**:

```xml
<key>CFBundleName</key>
<string>EchoPanel</string>
<key>CFBundleIdentifier</key>
<string>com.echopanel.app</string>
<key>CFBundleVersion</key>
<string>0.2.0</string>
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
<key>LSUIElement</key>
<true/> <!-- Menu bar app, no dock icon -->
<key>NSScreenCaptureUsageDescription</key>
<string>EchoPanel captures meeting audio from your screen to generate transcripts and summaries.</string>
<key>NSMicrophoneUsageDescription</key>
<string>EchoPanel can optionally capture your microphone audio for more accurate transcription.</string>
```

**Entitlements required**:

```xml
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/> <!-- Required for Python runtime -->
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.device.camera</key>
<false/>
```

#### Step 1.2: Bundle Python Runtime

**Options**:

**Option A: py2app (Simpler, larger)**

```bash
# Install py2app
uv pip install py2app

# Create setup.py for bundling
python setup.py py2app

# Copies Python + deps into .app/Contents/Resources/
# Final size: ~800MB with all deps
```

**Option B: Miniforge Python (Smaller, manual)**

```bash
# Download Miniforge (conda-based Python)
# Bundle into .app/Contents/Resources/python/
# Size: ~400MB base + deps

# Update BackendManager.swift:
let bundledPython = resourcePath + "/python/bin/python3"
```

**Option C: PyInstaller Single Binary (Smallest)**

```bash
# Bundle server as standalone executable
pyinstaller server/main.py \
  --onefile \
  --name echopanel-server \
  --hidden-import fastapi \
  --hidden-import faster_whisper

# Final binary: ~200MB
# Bundle into .app/Contents/Resources/
```

**Recommendation**: **Option C (PyInstaller)** for smallest bundle size.

#### Step 1.3: Update BackendManager for Bundled Server

**Current code** (BackendManager.swift:163-188):

```swift
// Priority 1: Project venv
// Priority 2: Bundled Python (future)
// Priority 3: System Python
```

**New code**:

```swift
private func findServerPath() -> String? {
    // Priority 1: Bundled server binary
    if let resourcePath = Bundle.main.resourcePath {
        let bundledServer = (resourcePath as NSString).appendingPathComponent("echopanel-server")
        if FileManager.default.fileExists(atPath: bundledServer) {
            return bundledServer
        }
    }

    // Priority 2: Development mode (server/ directory in project)
    // ... existing code ...
}

func startServer() {
    // If bundled server, run directly (no Python needed)
    // process.executableURL = URL(fileURLWithPath: serverPath)
    // No need for pythonPath or venv activation
}
```

#### Step 1.4: Add Model Download Progress UI

**Where**: OnboardingView.swift or new ModelDownloadView.swift

**UI Flow**:

1. After permissions, show "Downloading AI Model..."
2. Progress bar showing download % (0-100%)
3. Size indicator: "Downloading large-v3-turbo (1.5GB / 3.2GB)"
4. Cancel button (optional)
5. On completion, proceed to "Ready" step

**Implementation**:

- Add `/health/model-status` endpoint to server
- Returns: `{ "status": "downloading", "progress": 0.45, "size_mb": 3200 }`
- Poll endpoint every 2s from Swift UI
- Show progress in OnboardingView

**Code changes needed**:

```swift
// OnboardingView.swift
case .modelDownload:
    modelDownloadStep

private var modelDownloadStep: some View {
    VStack(spacing: 16) {
        Text("Downloading AI Model")
        ProgressView(value: modelProgress, total: 1.0)
        Text("\(Int(modelProgress * 100))% - \(Int(modelSizeMB)) MB / 3200 MB")

        if modelError != nil {
            Text("Download failed. Check internet connection.")
                .foregroundColor(.red)
            Button("Retry") { downloadModel() }
        }
    }
    .onAppear { downloadModel() }
}
```

---

### PHASE 2: Code Signing & Notarization (2-3h)

#### Step 2.1: Apple Developer Account Setup

**Prerequisites**:

- Enrolled in Apple Developer Program ($99/year)
- Developer ID Application certificate in Keychain
- App-specific password for notarization
- App ID / Bundle ID reserved (e.g., `com.echopanel.app`)

**Steps**:

1. Go to developer.apple.com → Certificates
2. Create "Developer ID Application" certificate
3. Download and install in Keychain Access
4. Generate app-specific password for notarization

#### Step 2.2: Code Sign the App

```bash
# Sign all binaries inside .app
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  --entitlements EchoPanel.entitlements \
  EchoPanel.app

# Verify signature
codesign --verify --deep --strict --verbose=2 EchoPanel.app
```

#### Step 2.3: Notarize with Apple

```bash
# Create ZIP for notarization
ditto -c -k --sequesterRsrc --keepParent EchoPanel.app EchoPanel.zip

# Submit to Apple (requires Xcode 13+)
xcrun notarytool submit EchoPanel.zip \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID" \
  --wait

# Staple notarization ticket to app
xcrun stapler staple EchoPanel.app

# Verify notarization
spctl -a -vv EchoPanel.app
# Should output: "accepted" and "source=Notarized Developer ID"
```

**Timeline**: 5-30 minutes for Apple to process notarization.

#### Step 2.4: Create DMG Installer

**Using create-dmg tool**:

```bash
brew install create-dmg

create-dmg \
  --volname "EchoPanel v0.2" \
  --volicon "icons/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "EchoPanel.app" 200 190 \
  --hide-extension "EchoPanel.app" \
  --app-drop-link 600 185 \
  "EchoPanel-v0.2.dmg" \
  "build/EchoPanel.app"
```

**Result**: `EchoPanel-v0.2.dmg` ready for distribution.

---

### PHASE 3: Distribution Infrastructure (1-2h)

#### Step 3.1: Hosting Options

**Option A: Direct Download (Simple)**

- Host DMG on Vercel/Netlify static site
- Add download link to landing page
- ~$0/month (free tier)

**Option B: Gumroad (With License Keys)**

- Upload DMG to Gumroad
- Charge $0 (free) or paid tier
- Get email collection + license key generation
- ~$10 for 10% fee on paid tiers

**Option C: GitHub Releases (Developer Friendly)**

- Create GitHub release with DMG as asset
- Use for invite-only beta
- Free, but public by default

**Option D: S3 or Google Drive (Private sharing)**

- Host DMG on S3 with signed URLs or a private Drive link
- Useful for small invite-only waves
- Requires manual access control

**Recommendation**: Start with **Option A** (Vercel static download) for invite-only wave, then move to **Option B** (Gumroad) for wider release.

---

## Licensing (Feb launch)

- **Private beta**: invite-only download with email gating.
- **Paid (optional)**: Gumroad license keys + email fulfillment; lightweight in-app entry.
- **No hard enforcement** in v0.2 to keep onboarding friction low.

#### Step 3.2: Update Landing Page

**Add to landing page**:

```html
<!-- Download CTA -->
<a href="/downloads/EchoPanel-v0.2.dmg" class="download-btn">
  Download EchoPanel v0.2 (Beta)
</a>
<p class="download-meta">macOS 13+ • Apple Silicon & Intel • 850 MB</p>
```

#### Step 3.3: Invite Email Template

**Subject**: Your EchoPanel Early Access Invite 🎉

**Body**:

```
Hi [Name],

Welcome to EchoPanel Early Access!

You're invited to try EchoPanel v0.2 - the AI meeting notes app that runs entirely on your Mac.

🔗 Download: [Download EchoPanel.dmg]
📖 Quick Start Guide: [Link to docs]
💬 Feedback Form: [Link to Typeform]

What to expect:
✅ First launch takes ~5 minutes (downloads AI model)
✅ Works with Zoom, Meet, Teams, and any app with audio
✅ 100% private - everything runs locally on your Mac

Need help? Reply to this email or join our Discord: [link]

— Pranay & the EchoPanel team
```

---

## User Installation Flow

### For Beta Testers (v0.2)

**Step 1: Download & Install**

1. Click download link in invite email
2. Open `EchoPanel-v0.2.dmg`
3. Drag `EchoPanel.app` to Applications folder
4. Eject DMG

**Step 2: First Launch**

1. Open Applications → EchoPanel
2. macOS Gatekeeper: "EchoPanel is an app downloaded from the internet. Are you sure you want to open it?" → **Open**
3. App appears in menu bar (no dock icon)

**Step 3: Onboarding Wizard**

1. **Welcome** → Next
2. **Permissions** → Grant Screen Recording → Open Settings → Enable EchoPanel → Next
3. **Audio Source** → Select "System Audio Only" or "Both" → Next
4. **Speaker Labels (Optional)** → Enter HuggingFace token or Skip → Next
5. **Model Download** → Progress bar shows "Downloading large-v3-turbo (3.2GB)..." → waits 5-15 min
6. **Ready** → "Start Listening"

**Step 4: First Session**

1. Click menu bar icon → "Start Listening"
2. Join Zoom/Meet/Teams meeting
3. Side panel shows live transcript + entities
4. End session → Export JSON/Markdown

---

## Troubleshooting Guide (for users)

### "Cannot open EchoPanel because it is from an unidentified developer"

**Solution**: Right-click app → Open (while holding Option key) → Open anyway

### "Screen Recording permission required"

**Solution**: System Settings → Privacy & Security → Screen Recording → Enable EchoPanel

### "Backend server failed to start"

**Cause**: Bundled server binary missing or corrupted
**Solution**: Re-download DMG and reinstall

### "Model download stuck at 0%"

**Cause**: Firewall blocking HuggingFace CDN
**Solution**: Check internet connection, try different network

### "No audio detected"

**Cause**: Wrong audio source selected or meeting muted
**Solution**: Change audio source in side panel, unmute meeting

---

## Size & Performance Estimates

### Bundle Sizes

| Component                    | Size                | Notes                            |
| ---------------------------- | ------------------- | -------------------------------- |
| Swift app binary             | ~5 MB               | Compiled executable              |
| Python runtime (PyInstaller) | ~150 MB             | Includes interpreter + stdlib    |
| Python dependencies          | ~200 MB             | fastapi, faster-whisper, torch   |
| Pre-bundled model (optional) | ~1.5 GB             | base model (faster first launch) |
| **Total DMG**                | **350 MB - 1.8 GB** | Depends on model bundling        |

### Download Times (at different speeds)

- 10 Mbps: 5-15 minutes
- 50 Mbps: 1-3 minutes
- 100 Mbps: 30s-90s

### First Launch (without pre-bundled model)

- Model download: 5-15 minutes (one-time)
- Model loading: 10-30 seconds
- Total first launch: 6-16 minutes

### First Launch (with pre-bundled base model)

- Model loading: 10-30 seconds
- Total first launch: <1 minute

**Recommendation**: Bundle `base` model, allow upgrade to `large-v3-turbo` in Settings.

---

## Release Checklist

### Before Building App Bundle

- [ ] Update version in Info.plist to 0.2.0
- [ ] Update CHANGELOG.md with v0.2 features
- [ ] Create app icon (1024x1024 PNG → .icns)
- [ ] Test app on clean macOS VM (no dev tools)
- [ ] Verify all permissions prompts work
- [ ] Test model download progress UI

### Before Code Signing

- [ ] Enroll in Apple Developer Program ($99)
- [ ] Create Developer ID certificate
- [ ] Configure entitlements correctly
- [ ] Test unsigned build first

### Before Notarization

- [ ] Generate app-specific password
- [ ] Sign all binaries in bundle
- [ ] Verify signature with `codesign`
- [ ] Create ZIP for submission

### Before Distribution

- [ ] Create DMG with drag-to-Applications UX
- [ ] Staple notarization ticket to DMG
- [ ] Test DMG on clean macOS (no dev tools)
- [ ] Verify Gatekeeper accepts app
- [ ] Upload DMG to hosting

### Before Sending Invites

- [ ] Write installation guide
- [ ] Create troubleshooting FAQ
- [ ] Set up feedback collection (Typeform/Discord)
- [ ] Prepare invite email template
- [ ] Test download link works

---

## Timeline Estimate

| Phase       | Tasks                                | Effort    | Dependency                 |
| ----------- | ------------------------------------ | --------- | -------------------------- |
| **Phase 1** | Convert to Xcode app + bundle Python | 4-6h      | None                       |
| **Phase 2** | Code signing + notarization          | 2-3h      | Phase 1 + Apple enrollment |
| **Phase 3** | DMG creation + hosting               | 1-2h      | Phase 2                    |
| **Phase 4** | Documentation + testing              | 2-3h      | Phase 3                    |
| **TOTAL**   | **End-to-end distribution setup**    | **9-14h** | Apple Developer account    |

**Recommended Sprint**: 2-3 days of focused work.

---

## Alternative: Interim Manual Distribution (If Blocked)

If you need to send invites **before** completing full bundling:

### Quick & Dirty Beta (1-2h setup)

1. Build release binary: `swift build -c release`
2. Create ZIP with:
   - `MeetingListenerApp` binary
   - Python venv (`server/` + `.venv/`)
   - Shell script wrapper: `run-echopanel.sh`
3. Write manual setup guide (see below)
4. Host ZIP on Dropbox/Google Drive
5. Send invite with setup instructions

**Setup script** (`run-echopanel.sh`):

```bash
#!/bin/bash
# EchoPanel Quick Launcher

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3.11+ required. Install from python.org"
    exit 1
fi

# Activate venv
source .venv/bin/activate

# Install deps (first run only)
if [ ! -f .venv/installed ]; then
    uv pip install -e ".[asr,diarization]"
    touch .venv/installed
fi

# Run app
./MeetingListenerApp
```

**This is NOT recommended for production but works for <10 technical beta testers.**

---

## Decision Points

### 1. Model Bundling Strategy ⭐ DECISION NEEDED

**Question**: Bundle base model (1.5GB) or download on first launch?

**Option A: Bundle `base` model in DMG** ← **RECOMMENDED**

- ✅ Faster first launch (<1 minute)
- ✅ App works immediately without internet
- ✅ Better first impression for users
- ❌ Larger DMG download (1.8GB vs 350MB)
- **User can upgrade to large-v3-turbo in Settings later**

**Option B: Download model on first launch**

- ✅ Smaller DMG download (350MB)
- ❌ Longer first launch (10-20 minutes)
- ❌ Requires internet on first run
- ❌ Users may think app is broken during wait

**Recommendation**: **Option A** for better UX. Storage is cheap, user time is valuable.

**Implementation**:

- DMG includes pre-downloaded `base` model (1.5GB)
- On first session, app uses `base` model immediately
- Settings UI allows upgrade to `large-v3-turbo` (3.2GB download)
- App remembers model choice for future sessions

### 2. Distribution Channel

**Question**: Gumroad, direct download, or GitHub Releases?

**For invite-only beta**: **Direct download** (Vercel static)
**For public launch**: **Gumroad** (collects emails, license keys)

### 3. Update Mechanism

**Question**: Auto-updates or manual downloads?

**v0.2**: Manual downloads (simpler, no code needed)
**v0.3+**: Implement Sparkle framework for auto-updates

---

## Next Steps

1. **Immediate** (Before any invites):
   - [ ] Create Xcode app bundle project
   - [ ] Bundle Python runtime with PyInstaller
   - [ ] Add model download progress UI
   - [ ] Test on clean macOS (borrow friend's Mac)

2. **Before Public Beta**:
   - [ ] Enroll in Apple Developer Program
   - [ ] Code sign and notarize app
   - [ ] Create DMG installer
   - [ ] Write user installation guide

3. **Before Invites**:
   - [ ] Upload DMG to hosting
   - [ ] Set up feedback collection
   - [ ] Prepare invite email
   - [ ] Test end-to-end user flow

---

## Questions for You

1. **Do you have an Apple Developer account?** ($99/year required for notarization)
2. **What's your target DMG size?** (350MB minimal vs 1.8GB with model)
3. **How many invite waves planned?** (Helps size infrastructure)
4. **Technical or non-technical beta testers?** (Affects instructions complexity)
5. **Timeline pressure?** (Can do interim manual ZIP if urgent)

Let me know your answers and I can proceed with implementation! 🚀
