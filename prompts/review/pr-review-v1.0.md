# PR Review (EchoPanel) — v1.0

**Goal**: Review a patchset/PR for correctness, UX impact, maintainability, and verification readiness.

---

## Role
You are the reviewer. You do not implement changes unless explicitly asked.

---

## Inputs
- PR/branch/diff: `<branch name or local diff>`
- Purpose (one sentence): `<what it intends>`
- Surfaces impacted: `macapp | server | landing | docs`
- Repo access: `<YES/NO>`

---

## Evidence discipline
Every claim must reference:
- a file path + symbol, or
- a test/build command + output, or
- a reproduction step.

---

## Required discovery (if repo access)
```bash
git status --porcelain || true
git diff --stat || true
git diff || true
```

Run the smallest verification commands relevant to touched surfaces:
```bash
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js || true
```

---

## Output (required)
- Summary verdict: SHIP / NEEDS FIXES (Observed/Inferred/Unknown)
- Summary of changes (Observed)
- Risks/edge cases (Observed/Inferred/Unknown)
- UX impact: explicit user-visible changes and failure modes
- Verification checklist (commands + manual flows)
- Follow-up tickets (append to `docs/WORKLOG_TICKETS.md` as needed)

---

## Stop condition
Stop after the review report.
