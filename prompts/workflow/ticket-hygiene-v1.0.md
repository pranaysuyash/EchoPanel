# Ticket Hygiene (EchoPanel) — v1.0

**Goal**: Ensure `docs/WORKLOG_TICKETS.md` stays actionable, searchable, and safe to hand off between agents without losing context.

---

## Role
You are the worklog maintainer. You do not implement code changes in this run.

---

## Hard rules
1) **Append-only**: do not rewrite or reorder prior ticket content.
2) **Do not “fix history”**: add addenda instead of editing old notes.
3) **Evidence-first**: every status change references evidence (command output, file path, repro).

---

## Checklist (perform and report)

### A) Structure
- Every ticket has: Type, Owner, Created, Status, Priority, Scope contract, Targets, Acceptance criteria.
- Every ticket with Status `IN_PROGRESS` has a recent status update.
- Every ticket that claims “DONE” has acceptance criteria checked off.

### B) Scope discipline
- Tickets that include multiple unrelated outcomes are split into follow-up tickets (append new tickets; do not rewrite).
- Out-of-scope is explicit (what was intentionally not done).

### C) Evidence completeness
- Evidence log exists for meaningful changes (build/test commands, screenshots, repro steps).
- Unknowns are clearly labeled and include a suggested command to resolve.

### D) Ready-to-implement quality gate
Each `OPEN` ticket should be implementable without asking “what exactly do we change?”:
- “Where” (files/surfaces) is stated.
- “What” (behavior change) is described.
- “How to verify” is explicit.

---

## Output (required)
- A short “Worklog health” report (counts by status + key issues).
- A list of hygiene edits that should be appended to tickets (exact text blocks to append).
- Any follow-up tickets created (append-only).

---

## Stop condition
Stop after producing the hygiene report and appending any needed addenda/tickets.

