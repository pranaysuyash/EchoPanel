# Issue Triage (EchoPanel) — v1.0

**Goal**: Prioritize incoming issues and convert them into a clean, implementable ticket queue.

---

## Inputs
- Issue list: `<bullets or links>`
- Constraints: `<time, privacy, MVP-only>`

---

## Output (required)
- Normalized issue table:
  - Title
  - Surface
  - Type (BUG/FEATURE/UX)
  - Priority (P0–P3)
  - Evidence status (Observed/Unknown)
  - Next action (repro / ticket / close)
- Ticket creation list (append to `docs/WORKLOG_TICKETS.md` for P0/P1)

---

## Stop condition
Stop after prioritization and ticket creation (no fixes).
