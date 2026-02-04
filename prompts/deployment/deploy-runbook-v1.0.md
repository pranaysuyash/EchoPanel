# Deploy Runbook (EchoPanel) — v1.0

**Goal**: Provide an operational runbook for deploying/distributing EchoPanel components (landing + local server + mac app builds).

---

## Inputs
- Target: `<internal | private beta | public>`
- Surfaces: `landing | server | macapp`
- Distribution constraints: `<codesign/notarize? local-only?>`

---

## Output (required)
- Step-by-step deploy/distribution procedure (by surface)
- Rollback plan
- Verification checklist
- Artifact checklist (what files/paths/urls must exist)

---

## Stop condition
Stop after the runbook (no deployments unless explicitly asked).
