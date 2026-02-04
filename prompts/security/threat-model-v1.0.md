# Threat Model (EchoPanel) — v1.0

**Goal**: Identify realistic security/privacy threats for EchoPanel’s user-facing flows (capture → stream → store → export) and propose mitigations with verification steps.

---

## Role
You are the threat modeler. You do not implement fixes in this run.

---

## Inputs
- Scope: `<feature/PR/ticket list>`
- Surfaces: `macapp | server | landing`
- Assumptions: `<local-only backend? cloud?>`
- Repo access: `<YES/NO>`

---

## Required discovery (if repo access)
```bash
rg -n "WebSocket|ws://|wss://|http://|https://|fetch\\(" -S macapp server landing
rg -n "UserDefaults|Keychain|token|secret" -S macapp server
rg -n "export|Application Support|sessions|debug|zip" -S macapp/MeetingListenerApp/Sources
```

---

## Deliverable artifact (required)
Write: `docs/audit/security-threat-model-<YYYYMMDD>.md`

---

## Output (required)

### A) System summary (Observed/Unknown)
- Data flow diagram (text): capture → processing → storage → export
- Trust boundaries (local app vs local server vs internet)

### B) Assets
- Audio, transcript text, summaries, entities
- Tokens/secrets
- Debug bundles/logs

### C) Threats (prioritized)
For each threat:
- STRIDE category (optional)
- Severity: `P0 | P1 | P2 | P3`
- Attack preconditions
- What could go wrong (user impact)
- Mitigation (smallest change)
- Verification steps

### D) Residual risk + next tickets
- What’s acceptable for MVP vs must-fix
- Ticket-ready mitigations (P0/P1 required) → append to `docs/WORKLOG_TICKETS.md`

---

## Stop condition
Stop after the threat model + ticket-ready mitigations. Do not implement fixes.
