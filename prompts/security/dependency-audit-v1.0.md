# Dependency Audit (EchoPanel) — v1.0

**Goal**: Inventory dependencies by surface (macapp/server/landing), identify risk, and propose minimal upgrades/removals with verification steps.

---

## Role
You are the dependency auditor. You do not implement changes in this run unless explicitly asked.

---

## Inputs
- Surface(s): `macapp | server | landing`
- Trigger: `<new dep | release | incident>`
- Repo access: `<YES/NO>`

---

## Required discovery (if repo access)
```bash
sed -n '1,200p' pyproject.toml
sed -n '1,200p' server/requirements.txt || true
sed -n '1,200p' macapp/MeetingListenerApp/Package.swift
rg -n \"https://cdn|unpkg|jsdelivr\" -S landing
```

---

## Output (required)
- Dependency inventory (grouped by surface)
- Risks (security/maintenance/license) labeled Observed/Inferred/Unknown
- Recommended actions:
  - “Must do now” (P0/P1)
  - “Safe later” (P2/P3)
- Verification commands to run after any change

Deliverable artifact:
- `docs/audit/dependency-audit-<YYYYMMDD>.md`

Tickets:
- Append P0/P1 items to `docs/WORKLOG_TICKETS.md`

---

## Stop condition
Stop after the audit report + recommendations (no implementation).
