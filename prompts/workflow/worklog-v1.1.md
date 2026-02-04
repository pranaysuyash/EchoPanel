# Worklog + Ticketing (EchoPanel) — v1.1

**Goal**: Every agent run leaves a durable trail in `docs/WORKLOG_TICKETS.md` so another agent can resume later without re-deriving context.

---

## Hard rules (required)
1) **Append-only**: do not rewrite or reorder prior entries.
2) **Evidence-first**: include raw command output (or mark Unknown if not runnable).
3) **Scope contract** required for every ticket.
4) Status must be one of: **OPEN** | **IN_PROGRESS** | **BLOCKED** | **DONE**.
5) One ticket = one user-facing outcome (split if needed).

---

## Priority guide
- **P0**: user blocked, data loss, trust break, security/privacy violation
- **P1**: core UX broken, common failure paths, major confusion
- **P2**: meaningful polish, quality, maintainability that affects shipping speed
- **P3**: nice-to-have

---

## When to create a new ticket
Create a new ticket when:
- starting a new audit/remediation/hardening effort
- starting a new feature slice
- starting a new QA/security/release effort

If continuing an existing ticket, append a “Status updates / Evidence log / Next actions” block to that ticket instead.

---

## Required ticket fields (copy/paste)

```markdown
### TCK-YYYYMMDD-NNN :: <Short title>

Type: AUDIT_FINDING | BUG | FEATURE | IMPROVEMENT | HARDENING | DOCS
Owner: <human owner> (agent: <agent name>)
Created: YYYY-MM-DD HH:MM (local time)
Status: **OPEN** 🔵
Priority: P0 | P1 | P2 | P3

Description:
<What is being done and why (1–4 lines)>

Scope contract:
- In-scope:
  - <explicit surfaces/files>
- Out-of-scope:
  - <explicit non-goals>
- Behavior change allowed: YES/NO/UNKNOWN

Targets:
- Surfaces: macapp | server | landing | docs
- Files: `path/to/file.ext`, ...
- Branch/PR: <branch name / PR URL / Unknown>
- Range: <base..head or Unknown>

Acceptance criteria:
- [ ] <testable outcome>
- [ ] <testable outcome>

Evidence log:
- [YYYY-MM-DD HH:MM] <action> | Evidence:
  - Command: `<command>`
  - Output:
    ```
    <raw output>
    ```
  - Interpretation: Observed/Inferred/Unknown — <one sentence>

Status updates:
- [YYYY-MM-DD HH:MM] **OPEN** 🔵 — created

Next actions:
1) ...
2) ...
```

---

## WIP update block (append inside an existing ticket)
```markdown
Status updates:
- [YYYY-MM-DD HH:MM] **IN_PROGRESS** 🟡 — <what started>

Evidence log:
- [YYYY-MM-DD HH:MM] <what you tried> | Evidence:
  - Command: `<command>`
  - Output:
    ```
    <raw output>
    ```
  - Interpretation: Observed/Inferred/Unknown — <one sentence>

Next actions:
1) ...
```

---

## DONE update block (append inside an existing ticket)
```markdown
Acceptance criteria:
- [x] <met>
- [x] <met>

Status updates:
- [YYYY-MM-DD HH:MM] **DONE** ✅ — <summary>
```
