# Completion Report (EchoPanel) — v1.0

**Goal**: When work is finished, produce a “what shipped” report with verification evidence and a clear next step.

---

## Inputs
- Completed ticket IDs: `<TCK-...>`
- Target audience: `internal | beta users | investors`
- Release tag (if any): `<vX.Y or Unknown>`

---

## Required discovery (if repo access)
```bash
git status --porcelain || true
git rev-parse --abbrev-ref HEAD || true
git rev-parse HEAD || true
```

Run the relevant checks for touched surfaces:
```bash
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
pytest -q || true
node -c landing/app.js || true
```

---

## Output (required)
- Outcome summary (user-facing)
- Files changed (grouped by surface)
- Verification evidence (commands + results)
- Known limitations
- Next recommended work (P1/P2)

---

## Stop condition
Stop after the completion report is produced and tickets are updated to DONE.

