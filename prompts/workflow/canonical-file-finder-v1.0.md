# Canonical File Finder (EchoPanel) — v1.0

**Goal**: Identify the “single source of truth” file(s) for a concept so future edits don’t spread across duplicates.

---

## Inputs
- Concept: `<e.g., entity highlighting, session export, onboarding permissions>`
- Surface: `macapp | server | landing | docs`

---

## Required discovery (if repo access)
```bash
rg -n "<concept keywords>" -S macapp server landing docs
find macapp -type f -maxdepth 4 | sort | head
find server -type f -maxdepth 4 | sort | head
find landing -type f -maxdepth 3 | sort | head
```

---

## Output (required)
- Canonical file(s) (with brief justification)
- Adjacent dependent files
- “Avoid editing” duplicates (if any) with a safe migration plan

---

## Stop condition
Stop after identifying the canonical sources and the safe edit plan.

