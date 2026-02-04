# Post-merge Validation (EchoPanel) — v1.0

**Goal**: After merging a PR, ensure the repo is healthy and tickets/docs reflect reality.

---

## Required checks
```bash
git status --porcelain
./scripts/project_status.sh
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js || true
```

---

## Manual smoke (pick relevant)
- Onboarding opens (first run or menu)
- Start listening opens side panel
- Stop opens summary and exports work
- History shows sessions and export works

---

## Output (required)
- Checklist results (Observed)
- Any regressions turned into tickets
- Tickets updated to DONE where appropriate

---

## Stop condition
Stop after checklist + worklog updates.
