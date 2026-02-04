# Test Execution Report (EchoPanel) — v1.0

**Goal**: Record what was tested, what passed/failed, and what follow-up work is required, with evidence.

---

## Inputs
- Test plan reference: `<docs/audit/test-plan-YYYYMMDD.md or ticket IDs>`
- Environment: `<macOS version, device, audio setup>`
- Repo access: `<YES/NO>`

---

## Required evidence (if repo access)
```bash
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js || true
```

---

## Output (required)
### A) Summary
- Tested surfaces
- Overall result: PASS / FAIL / PARTIAL

### B) What was tested
- Matrix (audio source x network x core flow)

### C) Evidence log
- Commands run + raw outputs
- Screenshots (paths) or reproduction notes

### D) Failures + follow-ups
For each failure:
- Severity: P0–P3
- Repro steps
- Expected vs actual
- Suspected area (file paths if known)
- Ticket to create/update in `docs/WORKLOG_TICKETS.md`

---

## Stop condition
Stop after the report and ticket updates (no fixes).
