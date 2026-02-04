# Issue → Ticket Intake (EchoPanel) — v1.0

**Goal**: Convert an ambiguous request, bug report, or audit note into one or more high-quality tickets in `docs/WORKLOG_TICKETS.md` (append-only), with explicit scope, acceptance criteria, and evidence.

---

## Role
You are the intake PM/tech lead. You create tickets; you do not implement fixes in this run.

---

## Inputs
- Intake source: `<user message / Slack note / screenshot / stack trace / GitHub issue>`
- Target surface(s): `macapp | server | landing | docs | unknown`
- Repo access: `<YES/NO>`
- Git availability: `<YES/NO/UNKNOWN>`

---

## Non-negotiables
1) **Evidence-first**: every non-trivial claim is **Observed / Inferred / Unknown**.
2) **One ticket = one outcome**: if there are multiple outcomes, split.
3) **Scope contract**: in-scope, out-of-scope, behavior change allowed.
4) **Testable acceptance criteria**: no vibes; must be verifiable by a user or command.

---

## Required discovery (if repo access)

If git is available:
```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
```

Repo orientation:
```bash
ls -la
find docs -maxdepth 2 -type f -name '*.md' | sort
find prompts -maxdepth 3 -type f -name '*.md' | sort
```

If the issue names a file/feature, run focused ripgreps:
```bash
rg -n "<keywords from issue>" -S macapp server landing docs
```

---

## Output (required)

### A) Clarified problem statement (evidence-labeled)
- Who is the user?
- What is the observable pain?
- What is the smallest desired outcome?
- What is Unknown (and what would confirm it)?

### B) Ticket set (append to `docs/WORKLOG_TICKETS.md`)
For each ticket:
- Priority `P0–P3` (P0 = data loss / user blocked / trust break)
- Type: `AUDIT_FINDING | BUG | FEATURE | IMPROVEMENT | HARDENING | DOCS`
- Targets: explicit surfaces and file paths (if known)
- Acceptance criteria: 3–7 checkboxes
- Evidence log: include any commands you ran + outputs (or mark Unknown)

### C) Suggested next prompt to run
State the exact prompt file to run next, and list its inputs.

---

## Stop condition
Stop after tickets are appended and the next prompt is selected.

