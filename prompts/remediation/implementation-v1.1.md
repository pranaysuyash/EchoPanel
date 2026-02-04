# Remediation / Implementation (EchoPanel) — v1.1

**Goal**: Implement a specific ticket from `docs/WORKLOG_TICKETS.md` with minimal scope drift, strong verification evidence, and clean handoff.

## Inputs (required)
- Ticket ID
- Scope contract + acceptance criteria
- Target files

---

## Non-negotiables
1) Keep changes tightly tied to acceptance criteria.
2) Record evidence (commands + outputs) in the ticket.
3) If you discover out-of-scope work, record it as out-of-scope and create a follow-up ticket (do not expand silently).

---

## Procedure (strict)

### 1) Restate scope contract
- In-scope / out-of-scope
- Behavior change allowed: YES/NO

### 2) Identify the minimal change set
Prefer:
- small, cohesive edits
- existing patterns/components
- no new dependencies unless unavoidable

### 3) Implement
Keep changes tightly tied to acceptance criteria.

### 4) Validate (required)
Pick the right checks:
- macapp: `swift build` (and optionally run app in demo mode)
- server: `/.venv/bin/python -m pytest -q`
- landing: `node -c landing/app.js` and optionally Playwright/manual check

### 5) Update docs (if user-visible contract changed)
Update or create the minimal docs needed (do not invent huge doc trees):
- `docs/PROJECT_MANAGEMENT.md` (process changes)
- `docs/audit/<...>.md` (audit-driven justification)

### 6) Closeout
Update ticket:
- evidence log
- status DONE
- any follow-ups split into new tickets

## Required outputs
- Ticket status updated in `docs/WORKLOG_TICKETS.md`
- If audit-driven: link the audit file in the ticket

---

## Stop condition
Stop after implementation + verification + ticket updates.
