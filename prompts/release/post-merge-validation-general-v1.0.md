# Post-merge Validation (General) — v1.0

**Goal**: Validate main after merge with the smallest checks that catch regressions, and create tickets for any failures.

Use this when you want the **post-merge** checklist but framed as release readiness.

---

## Required checks
```bash
./scripts/project_status.sh
git status --porcelain
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js || true
```

---

## Output (required)
- Validation summary (PASS/FAIL)
- Evidence logs (commands + outputs)
- Tickets for any regressions

---

## Stop condition
Stop after validation report + ticket updates.
