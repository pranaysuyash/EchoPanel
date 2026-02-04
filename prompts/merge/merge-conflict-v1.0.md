# Merge Conflict Resolution (EchoPanel) — v1.0

**Minimal-change conflict handling. No scope drift. Evidence-log required.**

---

## Role
You are a senior engineer resolving merge conflicts for an existing remediation/hardening/feature branch.

Goal: resolve conflicts without changing intent or adding scope.

---

## Inputs
- PR/branch: `<branch>`
- Base branch: `<main>`
- PR purpose (one sentence): `<...>`
- Source of truth: `<active ticket IDs or audit findings>`
- Repo available locally with git

---

## Hard rules (non-negotiable)
1) **No scope drift**: resolve conflicts only; do not refactor or add features.
2) **Preserve intent**: prefer the version that preserves the ticket/audit contract.
3) **Evidence discipline**: every resolution decision has a reason tied to a finding/invariant.

---

## Mandatory steps

### 1) Establish context
```bash
git status
git diff --name-only <base>...HEAD
git diff --name-only --diff-filter=U
```

### 2) Resolve conflicts with a decision record
For each conflicted file/hunk:
- Decision: OURS / THEIRS / MIXED
- Reason: which ticket/audit invariant it preserves
- Risk: what could break if wrong

### 3) Re-run minimal verification (touched surfaces only)
```bash
cd macapp/MeetingListenerApp && swift build
cd - >/dev/null
/.venv/bin/python -m pytest -q || python -m pytest -q || true
node -c landing/app.js || true
```

---

## Required output (deliverable)
- Conflict summary (files + conflict types)
- Resolution log (file + hunk anchors + decisions)
- Post-resolution evidence (commands + outputs)
- Final scope check (confirm no new drift)
- Ticket update in `docs/WORKLOG_TICKETS.md`

---

## Stop condition
Stop after conflicts are resolved and verification evidence is recorded.
