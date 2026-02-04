# Incident Response (EchoPanel) — v1.0

**Goal**: Run a lightweight incident response process for user-impacting issues.

---

## Inputs
- Incident summary: `<what’s happening>`
- Start time: `<timestamp>`
- Impacted users: `<who>`
- Surface: `macapp | server | landing`

---

## Output (required)
- Incident report: `docs/audit/incident-<YYYYMMDD>.md`
- Timeline (Observed)
- Current mitigation status
- Root cause hypotheses (Observed/Inferred/Unknown)
- Immediate mitigations (smallest reversible actions)
- Follow-up tickets (P0/P1 first) with acceptance criteria

---

## Stop condition
Stop after incident report + ticketing (no speculative fixes).
