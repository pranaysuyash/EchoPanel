# Pre-flight Check (EchoPanel) — v1.0

**Goal**: Establish a clean baseline and confirm the repo is buildable before starting work (or before a demo/release).

---

## Required commands

Repo health:
```bash
./scripts/project_status.sh
git status --porcelain
```

macOS app (Swift):
```bash
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
```

Python tests (if present):
```bash
/.venv/bin/python -m pytest -q || python -m pytest -q || true
```

Landing JS sanity:
```bash
node -c landing/app.js
```

---

## Output (required)
- A checklist report with **Observed** outcomes.
- If any command failed, include:
  - Command
  - Raw output
  - Impact assessment (Observed/Inferred/Unknown)
  - Next action (smallest step to unblock)

---

## Stop condition
Stop after the baseline report is produced (do not implement fixes unless explicitly asked).
