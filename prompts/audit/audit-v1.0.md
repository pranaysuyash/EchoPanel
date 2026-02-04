# Audit Prompt (EchoPanel) — v1.0

**Goal**: Produce a focused audit (one surface/area) with evidence-labeled findings, a strict report artifact, and trackable tickets.

---

## Role
You are an auditor. You do not implement fixes in this run.

---

## Inputs
- Surface: `macapp | server | landing | docs`
- Target area: `<feature, workflow, or module>`
- Scope hint (optional): `<file list>`
- Behavior change allowed: `YES/NO/UNKNOWN`
- Repo access: `<YES/NO>`
- Git availability: `<YES/NO/UNKNOWN>`

---

## Evidence labels (required)
Every non-trivial claim must be labeled as one:
- **Observed**: verified from file content, command output, screenshot, or reproduction
- **Inferred**: logically implied from Observed facts
- **Unknown**: cannot be verified from available evidence

---

## Required discovery (if repo access)

If git is available:
```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
```

Surface inventory:
```bash
ls -la macapp server landing docs || true
```

Focused grep (adapt keywords):
```bash
rg -n "<keywords>" -S macapp server landing docs
```

---

## Report artifact (required)
Write an artifact to:
`docs/audit/<surface>-<area>-<YYYYMMDD>.md`

---

## Required report format (strict)

### 1) Scope contract
- In-scope
- Out-of-scope
- Behavior change allowed: YES/NO/UNKNOWN

### 2) What exists today (Observed only)
- User-visible behaviors
- Major states and workflows

### 3) Findings (prioritized)
For each finding:
- ID: `F-###`
- Severity: `P0 | P1 | P2 | P3`
- Claim type: Observed/Inferred/Unknown
- Evidence: `<file path / screenshot / command>`
- User impact (one sentence)
- Recommendation (smallest fix)
- Verification steps (commands + manual checks)

### 4) Backlog conversion
- Which findings should become tickets (P0/P1 required)
- Suggested ticket titles + acceptance criteria

---

## Severity taxonomy
- **P0**: data loss, user blocked, trust/privacy break, crash
- **P1**: core workflow broken, common failure path unclear
- **P2**: meaningful polish/quality/maintainability
- **P3**: nice-to-have

---

## Stop condition
Stop after producing the audit artifact and listing ticket-ready findings (do not implement fixes).
