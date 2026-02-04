# Claims Registry (Append-only)

Purpose: prevent contradictions and “memory drift” across people/agents by recording important claims with evidence labels.

## Evidence labels
- **Observed** — verified directly in code or by running commands
- **Inferred** — plausible but not directly verified
- **Unknown** — cannot determine from available evidence

## Template

```md
### CLM-YYYYMMDD-NNN :: <Claim title>

Claim:
- <statement>

Evidence level: Observed | Inferred | Unknown

Evidence:
- File(s): `...`
- Commands: `...`
- Notes: ...
```

---

## Claims

### CLM-20260204-001 :: Prompt library and worklog exist

Claim:
- EchoPanel repo includes a prompt library (`prompts/`) and a worklog (`docs/WORKLOG_TICKETS.md`) for project management.

Evidence level: Observed

Evidence:
- File(s): `AGENTS.md`, `prompts/README.md`, `docs/WORKLOG_TICKETS.md`

