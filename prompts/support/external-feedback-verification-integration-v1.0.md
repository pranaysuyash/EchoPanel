# External Feedback Verification + Integration (EchoPanel) — v1.0

**Goal**: Verify external feedback and integrate it into the worklog as trackable tickets without ambiguity.

---

## Inputs
- Feedback artifact(s): `<text/screenshot/video>`
- Surface guess: `macapp | landing | server | unknown`
- Repo access: `<YES/NO>`

---

## Procedure (strict)
1) Attempt verification:
   - If reproducible → Observed
   - If not reproducible → Unknown (and list what evidence is missing)
2) Translate into ticket(s):
   - one outcome per ticket
   - explicit acceptance criteria
   - required evidence/logs to collect
3) Prioritize:
   - P0/P1 → immediate ticket
   - P2/P3 → backlog ticket with clear deferral rationale

---

## Output (required)
- Ticket(s) appended to `docs/WORKLOG_TICKETS.md`
- Verification notes (Observed/Unknown) and next evidence requests

---

## Stop condition
Stop after ticketing + verification notes (no implementation).
