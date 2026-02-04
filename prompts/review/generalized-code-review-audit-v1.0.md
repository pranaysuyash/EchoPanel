# Generalized Code Review Audit (EchoPanel) — v1.0

**Goal**: Perform a broad, repo-aware code review focused on correctness, maintainability, and user-facing impact.

---

## Inputs
- Surface focus: `macapp | server | landing | all`
- Time budget: `<30m | 60m | 2h>`

---

## Required discovery (if repo access)
```bash
rg -n "TODO|FIXME|HACK" -S macapp server landing docs || true
```

---

## Output (required)
- Top issues by severity (P0–P3) with evidence labels
- “UI debt hotspots” (files that will slow shipping)
- Minimal refactor suggestions (only if they reduce user risk)
- Ticket-ready follow-ups

Optional artifact:
- `docs/audit/code-review-<YYYYMMDD>.md`

---

## Stop condition
Stop after findings + ticket list (no implementation).
