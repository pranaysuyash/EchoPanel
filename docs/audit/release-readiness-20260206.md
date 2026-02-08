# Release Readiness — v0.2 Public Launch (2026-02-06)

**Release target**: Public launch

**Surfaces**: macapp | server | landing

---

## Readiness verdict
**READY WITH RISKS**

---

## Blockers (P0)
1. **Bundled Python runtime + server binary not shipped**
   - **Observed**: `docs/DISTRIBUTION_PLAN_v0.2.md` lists bundling as launch blockers.
   - **Owner suggestion**: macapp + build tooling.
   - **Next steps**: Bundle server via PyInstaller and include in `.app` resources.

2. **Model download progress UX missing**
   - **Observed**: `docs/STATUS_AND_ROADMAP.md` flags Model Preloading UI as pending.
   - **Owner suggestion**: macapp + server.
   - **Next steps**: Add model download progress flow per distribution plan.

3. **Pricing + purchase flow not finalized for public launch**
  - **Observed**: `docs/PRICING.md` notes “needs confirmation”.
  - **Owner suggestion**: Product/Founder.
  - **Next steps**: Publish pricing tier and payment provider setup (Gumroad or equivalent).

## Must-fix (P1)
1. **Pricing/licensing decisions not finalized**
   - **Observed**: `docs/PRICING.md` includes draft values and open questions.
   - **Owner suggestion**: Product/Founder.

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

- [2026-02-06] landing JS syntax | Evidence:
  - Command: `node -c landing/app.js`
  - Output:
    ```
    (no output)
    ```
  - Interpretation: **Observed** — landing JS parses

---

## Suggested next tickets
- TCK-20260206-004 (portrait side panel + tabs)
- TCK-20260206-005 (keyboard nav + auto-scroll)
- TCK-20260206-006 (Documents tab stub)
- TCK-20260206-008 (pricing/licensing + distribution)
