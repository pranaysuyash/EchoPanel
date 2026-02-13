# Release & TestFlight onboarding (macOS)

Purpose
- Document steps to publish macOS builds to App Store Connect / TestFlight and how testers should validate builds.

When to use
- Use this for every internal/external beta release, CI uploads, and tester onboarding.

---

## Prerequisites
- Apple Developer Program account and App Store Connect access (App Manager or Admin).
- Bundle identifier for the macOS app (check `macapp/` Xcode project).
- A CI runner capable of macOS builds for uploading (GitHub Actions `macos-latest` recommended).
- App Store Connect API Key (preferred) or Apple ID and app-specific credentials.

---

## Quick checklist (high level)
1. Create App record in App Store Connect (Platform: macOS) and set Bundle ID.
2. Ensure Xcode signing is configured for `Mac App Store` distribution.
3. Add App Store Connect API key to CI secrets.
4. Add `fastlane` lane + GitHub Action job to build → sign → notarize (if required) → upload.
5. Create TestFlight groups and invite testers.
6. Run smoke tests with internal testers, then open to external testers.

---

## App Store Connect setup
1. App Store Connect → My Apps → (+) → New App → Platform: macOS.
2. Use the app's Bundle ID and set SKU/title.
3. Under TestFlight, add internal tester team members first.

---

## Local build & upload (manual, for debugging)
- Archive (Xcode):

```bash
xcodebuild -workspace macapp/EchoPanel.xcworkspace \
  -scheme EchoPanel-AppStore \
  -configuration Release \
  -archivePath $PWD/build/EchoPanel.xcarchive archive

xcodebuild -exportArchive \
  -archivePath $PWD/build/EchoPanel.xcarchive \
  -exportOptionsPlist exportOptions.plist \
  -exportPath $PWD/build/Export
```

- Upload with altool / notarytool / transporter or use fastlane `deliver`/`pilot`.

---

## Recommended: fastlane lanes (example)
Add these lanes to `macapp/fastlane/Fastfile` (or root `fastlane/Fastfile`):

```ruby
platform :mac do
  desc "Build and upload macOS app to TestFlight"
  lane :beta do
    build_app(scheme: "EchoPanel-AppStore", export_method: "app-store")
    upload_to_app_store(skip_screenshots: true, skip_metadata: true)
  end
end
```

Use App Store Connect API key via environment or `Appfile`.

---

## CI (GitHub Actions) — minimal example
Create `.github/workflows/cd-mac.yml` with a job that runs on macOS and calls fastlane:

```yaml
name: macOS TestFlight
on:
  push:
    tags: ["v*.*.*"]

jobs:
  build-and-upload:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
      - name: Install fastlane
        run: gem install fastlane
      - name: Run fastlane beta
        env:
          APP_STORE_CONNECT_API_KEY: ${{ secrets.APP_STORE_CONNECT_API_KEY }}
        run: cd macapp && fastlane mac beta
```

Secrets to add to repository (Recommended names)
- `APP_STORE_CONNECT_API_KEY` (JSON or separate KEY_ID/ISSUER_ID/PRIVATE_KEY)
- `FASTLANE_USER` (optional)
- `MATCH_PASSWORD` (if using match)

---

## TestFlight workflow (internal → external)
1. Upload build via CI or Fastlane.
2. Add internal testers (App Store Connect → TestFlight → Internal Testing).
3. After internal verification, add external testers and submit beta build for Beta App Review if required.
4. Monitor crashes/feedback and iterate.

---

## Tester checklist (what we need tested)
- Installation: download/install from TestFlight, app launches.
- Auto-launch on login behavior (if enabled under settings).
- VAD behavior: voice starts/stops detected, no long false positives.
- Streaming: audio streaming remains stable for long sessions (10+ minutes).
- Incremental analysis: entities/cards appear and update incrementally.
- Crash check: no crashes during normal use; reproduce any crash steps.
- Preferences: toggling VAD, microphone selection, reconnection flow.

Please capture:
- macOS version (Example: macOS 13.6), app build number, short reproduction steps, and attach logs (Console.app or `~/Library/Logs/EchoPanel`).

---

## Bug report template (copy for testers)
- Build: vX.Y.Z (build N)
- macOS: 13.6 (or other)
- Steps to reproduce:
  1. ...
  2. ...
- Expected result:
- Actual result:
- Attach logs: `~/Library/Logs/EchoPanel/*` (or screenshot/video)
- Priority / severity: P0/P1/P2

---

## Acceptance criteria (ready to expand external testers)
- Internal testers confirm app installs and core flows pass (no critical crashes).  
- CI produces an App Store Connect-uploadable artifact automatically.  
- Crash rate is acceptable and reproducible bugs have tickets assigned.

---

## Rollout & rollback
- Rollout: internal (team) → small external group → wider external group.  
- Rollback: remove build from TestFlight, revert CI changes, publish a patched build.

---

## Where to find logs and telemetry
- Local logs: `~/Library/Logs/EchoPanel/`  
- CI logs: GitHub Actions run artifact / workflow logs  

---

## Next actions we can do for you
- Add `fastlane` lanes + `cd-mac.yml` GitHub Action (I can create PR).  
- Draft onboarding email + tester invite copy.  
- Help set up App Store Connect app record (requires your Apple access).


---

Document created by: Release/TestFlight onboarding guide — keep this updated with any changes to signing or CI.