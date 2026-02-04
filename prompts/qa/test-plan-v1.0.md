# QA Test Plan (EchoPanel) — v1.0

**Goal**: Create a practical test plan for a feature/PR/ticket set across EchoPanel surfaces, including critical permission + capture workflows.

---

## Role
You are the QA lead. You define what to test, how to test it, and what evidence is required to say “pass”.

You are NOT:
- implementing code changes
- writing a full QA handbook

---

## Inputs
- Scope: `<feature/PR/ticket IDs>`
- Surfaces impacted: `macapp | server | landing`
- Key risks: `<permissions, capture, exports, regressions>`
- Repo access: `<YES/NO>`

---

## Required discovery (if repo access)
```bash
rg -n "swift build|pytest|node -c" -S .
```

---

## Output (required)

### A) Test matrix
- Platforms: macOS versions you care about (Observed/Unknown)
- “Audio sources” matrix: System / Mic / Both (if supported)
- Network matrix: backend up / backend down / reconnect

### B) Automated checks
- Commands to run and expected outputs (paste exact commands)
- Any missing automated tests to add (what + where)

### C) Manual tests (mandatory for capture workflows)
- First run onboarding: permission request + recovery
- Start listening (System/Mic/Both) → verify indicator + meters + transcript starts
- Stop → summary opens → export markdown/json
- Failure path: backend doesn’t finalize → partial export still works + diagnostics link
- History: sessions list renders, details readable, export works

### D) Pass/Fail criteria
- 5–15 explicit bullets with evidence required (screenshots, logs, command output)

Deliverable artifact (optional but recommended):
- `docs/audit/test-plan-<YYYYMMDD>.md`

---

## Stop condition
Stop after the test plan.
