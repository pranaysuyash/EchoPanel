> **⚠️ SUPERSEDED (2026-02-16):** This Feb 6 release readiness doc is superseded by
> `LAUNCH_READINESS_AUDIT_2026-02-12.md` and `SENIOR_STAKEHOLDER_RED_TEAM_REVIEW_20260214.md`.
> Core blockers resolved: .app bundle built (81MB, TCK-20260212-012), StoreKit implemented (TCK-20260212-004).
> Code signing remains open but tracked in current docs. Moved to archive.

# Release Readiness — v0.2 Public Launch (2026-02-06)

**Release target**: Public launch

**Surfaces**: macapp | server | landing

---

## Update (2026-02-13)

This document was authored on **2026-02-06**. Since then, several launch blockers were resolved (packaging, monetization), and a more current launch view exists in `docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md`.

Status as of **2026-02-13** (observed):
- ✅ Self-contained `.app` bundle + DMG exist (see `docs/STATUS_AND_ROADMAP.md`, ticket `TCK-20260212-012` in `docs/WORKLOG_TICKETS.md`).
- ✅ Pricing + purchase flow implemented via StoreKit 2 subscriptions (see `docs/PRICING.md`, ticket `TCK-20260212-004`).
- ⚠️ Model readiness UX: backend exposes `/health` (503 until model ready) and `/model-status` (preloader stats), but onboarding does not yet show first-run download/progress UI.
- 🚫 Code signing/notarization still not complete (Gatekeeper/App Store submission risk).

## Readiness verdict
**READY WITH RISKS**

---

## Blockers (P0)
1. **Bundled backend shipped (was blocker)**
   - **Status (2026-02-13)**: ✅ Resolved via self-contained app bundle + DMG (`TCK-20260212-012`).

2. **Code signing + notarization not complete**
   - **Observed**: Distribution plan requires signing/notarization; Gatekeeper will block unsigned app bundles.
   - **Owner suggestion**: macapp + build tooling.
   - **Next steps**: Establish Developer ID cert + notarization flow; verify DMG on a clean macOS install.

3. **Model download/progress UX missing (first-run)**
   - **Observed**: Server model preloading exists and `/model-status` is available, but the macapp onboarding does not surface progress (only readiness/health).
   - **Owner suggestion**: macapp + server.
   - **Next steps**: Add an onboarding step that polls `/model-status` and renders progress/state until ready.

## Must-fix (P1)
1. **Pricing/licensing decisions not finalized**
   - **Status (2026-02-13)**: ✅ Resolved for App Store subscriptions (see `docs/PRICING.md`, `TCK-20260212-004`). Direct-sales licensing is deferred.

2. **Landing mock must match new portrait UI**
   - **Observed**: Updated landing mock exists (see `landing/index.html`).
   - **Owner suggestion**: Landing maintainer; verify in browser.

## Known limitations (P2/P3)
- Documents tab is a UI stub without RAG indexing. **Inferred**
- No automated UI tests for tab navigation. **Inferred**

---

## Evidence log
- [2026-02-06] Project status | Evidence:
  - Command: `./scripts/project_status.sh`
  - Output:
    ```
    ✅ DONE:        15
    🔵 OPEN:        6
    ```
  - Interpretation: **Observed** — open tickets for launch readiness exist

- [2026-02-06] macapp build | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete!
    ```
  - Interpretation: **Observed** — app compiles

- [2026-02-06] server tests | Evidence:
  - Command: `./.venv/bin/python -m pytest -q || python -m pytest -q || true`
  - Output:
    ```
    zsh: no such file or directory: ./.venv/bin/python
    no tests ran in 0.00s
    ```
  - Interpretation: **Observed** — tests not executed due to missing venv

- [2026-02-13] server tests (targeted) | Evidence:
  - Command: `.venv/bin/python -m pytest -q tests/test_streaming_correctness.py tests/test_provider_whisper_cpp_contract.py`
  - Result: PASS (21 tests)

- [2026-02-06] landing JS syntax | Evidence:
  - Command: `node -c landing/app.js`
  - Output:
    ```
    (no output)
    ```
  - Interpretation: **Observed** — landing JS parses

---

## Suggested next tickets
- `TCK-20260212-012` (self-contained `.app` + DMG distribution) — DONE ✅
- `TCK-20260212-004` (StoreKit subscriptions) — DONE ✅
- `TCK-20260213-008` (UI/UX Audit - Focus Indicator) — OPEN 🔵
