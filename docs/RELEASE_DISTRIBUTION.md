# Release and Distribution (v0.1)

## Packaging
- Distribute via DMG or ZIP from website.
- macOS app must be code-signed with Developer ID and notarized.

## Notarization checklist (minimal)
- App bundle has correct entitlements for ScreenCaptureKit usage.
- App prompts for Screen Recording permission via user flow.
- Verify Gatekeeper behavior on a clean machine.

## Release checklist
- Update `docs/CHANGELOG.md`
- Update `docs/VERSIONING.md` if version policy changes
- Ensure `docs/WS_CONTRACT.md` matches the server implementation
- Verify v0.1 acceptance checklist in `docs/TESTING.md`

