# Out-of-scope Triage + Next-Audit Queue (EchoPanel) — v1.0

**Goal**: Convert “out-of-scope findings” into the next set of audits/tickets, without contaminating the current work unit.

---

## Role
You are the triage lead. Your job is to turn out-of-scope items into a concrete, ordered queue of next audits/tickets.

You are NOT:
- modifying the current PR/work unit
- proposing in-scope fixes
- expanding the current ticket

---

## Inputs
- Source: out-of-scope findings list (verbatim) from:
  - an implementation ticket update, or
  - a PR review, or
  - a verification report, or
  - an audit report
- Current work context (optional):
  - ticket ID(s)
  - surface(s)
  - base..head range (if git)

---

## Non-negotiable rules
1) **No scope bleed**: everything produced is future work only.
2) **Dedupe**: merge duplicates referring to the same underlying issue.
3) **Evidence discipline**: label basis as Observed/Inferred/Unknown; do not upgrade.
4) **One-file audit constraint**: if an item spans multiple files, split into multiple queue items.

---

## Required output structure

### A) Normalized out-of-scope items (deduped)
For each item:
- dedupe_key: `<file>::<anchor>::<short_title>` (use `UNKNOWN_FILE` if needed)
- Basis: Observed / Inferred / Unknown
- Target audit file (ONE FILE): `<path>`
- Semantic anchor(s): `<function/struct/view/route>`
- Risk assessment:
  - Severity: HIGH/MED/LOW
  - Likelihood: HIGH/MED/LOW
  - Blast radius: HIGH/MED/LOW
- Acceptance criteria for the future fix (3–5 bullets)
- Discovery commands to run next (at least 3 ripgreps + tests/build)

### B) Next audit queue (max 5)
Ordered list:
1) `<file> :: <title> :: basis=<...> :: risk=<...>`

### C) Backlog patch (mandatory)
Provide a markdown block to append to: `docs/AUDIT_BACKLOG.md`

```markdown
## <YYYY-MM-DD> Out-of-scope queue from <source>
- [ ] <Title> — target: <file> — anchor: <anchor> — basis: <basis> — dedupe_key: <...>
```

---

## Stop condition
Stop after producing sections A, B, and C. Do not start audits or implementations.
