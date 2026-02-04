# Hardening (EchoPanel) — v1.0

**Goal**: Improve reliability, correctness, and supportability without adding new product features.

This prompt produces a **hardening plan + tickets**. Use `prompts/remediation/implementation-v1.1.md` to implement.

---

## Inputs
- Surface: `macapp | server | landing`
- Scope area: `<e.g., stop flow, session storage, reconnects, exports>`
- Constraints: `<no new deps, preserve behavior?>`
- Repo access: `<YES/NO>`

---

## Required discovery (if repo access)
```bash
rg -n "<keywords>" -S macapp server landing || true
```

---

## Output (required)
- Hardening contract (what must not regress)
- Top risks (P0–P3) with evidence labels
- Minimal hardening plan (3–10 steps)
- Verification plan (commands + manual)
- Ticket set (append to `docs/WORKLOG_TICKETS.md`)

---

## Stop condition
Stop after plan + ticketing (do not implement in this run).
