# Deploy Runbook — Feb v0.2 Public Launch (2026-02-06)

**Target**: Public launch

**Surfaces**: landing | server | macapp

**Distribution constraints**: Code signing + notarization required for macOS distribution. **Observed**: `docs/DISTRIBUTION_PLAN_v0.2.md`

---

## Step-by-step procedure

### 1) macapp distribution build

1. Build .app bundle (Xcode or build script).
2. Bundle backend server (PyInstaller) into app resources.
3. Bundle base model (optional) or ensure download UI.
4. Code-sign app with Developer ID.
5. Notarize with Apple; staple ticket.
6. Create DMG for distribution.

### 2) Backend (local-only)

- Backend is bundled; no public server deployment.
- Verify local start in app.

### 2.1) ASR model profile (recommended)

- Default baseline: `faster-whisper base.en` (best launch default for English-heavy meetings, low download size).
- Quality upgrade: `faster-whisper large-v3-turbo` (higher accuracy, larger model, slower cold start).
- Fallback/safety: keep `base` (multilingual) available for non-English sessions.

### 3) Landing page

- Update hero mock + copy to reflect portrait UI.
- Update CTA for public launch (pricing + download).
- Deploy static assets to hosting.

### 4) Licensing + payments (public)

1. Decide pricing tier to publish (monthly or annual).
2. Configure Gumroad (or payment provider) with download + license keys.
3. Add license entry UI and status label in app Settings (if enforced).
4. Update landing page with purchase CTA.

---

## Rollback plan

- Keep last DMG and landing assets.
- Revert landing to previous build if issues appear.

---

## Verification checklist

- DMG opens on a clean macOS machine.
- App passes Gatekeeper (notarized).
- First-run permissions prompt appears.
- Start Listening opens side panel and begins transcript.
- Landing page loads and purchase / download flow works.
- Licensing or purchase confirmation is received (email receipt).

---

## Artifact checklist

- `EchoPanel.app`
- `EchoPanel-v0.2.dmg`
- Notarization logs
- Landing assets (`landing/` build or hosted site URL)
- Payment provider product page (public URL)
