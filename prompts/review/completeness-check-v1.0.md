# Completeness Check (EchoPanel) — v1.0

**Goal**: Catch obvious “ship blockers” before demo/release (missing states, broken commands, broken UX flows).

---

## Inputs
- Target surface: `macapp | landing | server | all`
- Scope: `<release | demo | feature>`

---

## Required checks (adapt to touched surfaces)
```bash
./scripts/project_status.sh
git status --porcelain
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js
```

---

## Output (required)
- Pass/fail checklist with evidence
- Any blockers (P0/P1) turned into tickets

---

## Stop condition
Stop after the checklist and ticket updates.
