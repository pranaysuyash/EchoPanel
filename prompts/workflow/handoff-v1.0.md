# Handoff Summary (EchoPanel) — v1.0

**Goal**: Produce a crisp handoff another agent (or you-in-a-week) can use to resume work fast.

---

## Inputs
- Active ticket IDs: `<TCK-...>`
- Primary surface(s): `macapp | server | landing | docs`
- Branch info: `<branch name or Unknown>`

---

## Required discovery (if repo access)
```bash
git status --porcelain || true
git rev-parse --abbrev-ref HEAD || true
git rev-parse HEAD || true
```

Also:
```bash
sed -n '1,260p' docs/WORKLOG_TICKETS.md
```

---

## Output (required)
- What was attempted (1–5 bullets)
- What changed (file list)
- What is done vs not done (by ticket)
- Known risks/unknowns (and how to resolve)
- Next 3 actions (commands + where to edit)

---

## Stop condition
Stop after the handoff is written (and optionally appended to the relevant tickets).

