# Worklog → Issues Triage (EchoPanel) — v1.0

**Goal**: Turn audit notes and worklog tickets into a prioritized “what to do next” list, without implementing changes.

---

## Inputs
- Target time horizon: `<today | this week | this month>`
- Primary surface: `macapp | server | landing`
- Constraints: `<privacy, offline, MVP-only, etc.>`

---

## Required discovery (if repo access)
```bash
sed -n '1,260p' docs/WORKLOG_TICKETS.md
find docs/audit -maxdepth 2 -type f -name '*.md' | sort
```

---

## Output (required)

### A) Current backlog snapshot
- P0/P1 items (with ticket IDs)
- “Big rocks” (multi-day work) vs “Quick wins” (≤1 day)

### B) Risk map
- Data loss / trust / privacy risks
- UX adoption risks
- Maintainability risks (only if they affect speed to ship)

### C) Proposed next 5 tickets
For each:
- Ticket id (or “create new”)
- Why it’s next
- What will be delivered
- What “done” means

---

## Stop condition
Stop after the prioritized next list is produced.

