# Release Readiness (EchoPanel) — v1.0

**Goal**: Decide if EchoPanel is ready for a demo/beta release and list any blockers with evidence.

---

## Inputs
- Release target: `<internal demo | private beta | public>`
- Surfaces: `macapp | server | landing`

---

## Required discovery (if repo access)
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
- Readiness verdict: READY / NOT READY / READY WITH RISKS
- Blockers (P0) and must-fix (P1), each with:
  - Evidence (command output / file path / repro)
  - Owner suggestion
  - Next steps
- “Known limitations” (P2/P3) appropriate for the release target
- Suggested next tickets (append to `docs/WORKLOG_TICKETS.md` if needed)

---

## Stop condition
Stop after the readiness report (no fixes).
