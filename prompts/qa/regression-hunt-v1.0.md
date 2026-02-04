# Regression Hunt (EchoPanel) — v1.0

**Goal**: Find the likely cause of a regression with minimal scope drift, and produce a ticket-ready diagnosis (and optionally a minimal fix plan).

---

## Inputs
- Regression description: `<what broke>`
- “Last known good”: `<date/commit/version or Unknown>`
- Surface: `macapp | server | landing`
- Repo access: `<YES/NO>`
- Git availability: `<YES/NO/UNKNOWN>`

---

## Required discovery (if git available)
```bash
git status --porcelain
git log -n 30 --oneline
```

If you have a suspected file/area:
```bash
rg -n "<keywords>" -S macapp server landing
```

---

## Output (required)
- Repro steps (Observed)
- Most likely cause (Observed/Inferred/Unknown) with evidence
- Suspect commit range (if possible)
- Minimal fix direction (not implementation)
- Verification steps
- Ticket updates in `docs/WORKLOG_TICKETS.md`

---

## Stop condition
Stop after diagnosis and ticketing (no refactors).
