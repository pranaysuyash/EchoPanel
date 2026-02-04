# Feedback Intake (EchoPanel) — v1.0

**Goal**: Convert external user feedback into one or more implementable tickets with reproducible evidence.

---

## Inputs
- Feedback source: `<email/chat/screenshot/video>`
- Reporter persona: `<founder, PM, recruiter, sales, privacy-conscious user, etc.>`
- Surface: `macapp | server | landing`

---

## Required fields (collect or mark Unknown)
- Environment: macOS version; audio source; backend host; app version
- Repro steps (numbered)
- Expected vs actual
- Frequency (always/sometimes/once)
- Impact (blocked/trust/polish)
- Evidence to request:
  - Diagnostics bundle (macapp)
  - session JSON export (if available)
  - screenshots (landing/app)

---

## Output (required)
- Ticket(s) appended to `docs/WORKLOG_TICKETS.md` with:
  - Scope contract
  - Acceptance criteria
  - Evidence log (what was provided vs missing)
- Suggested next prompt to run:
  - intake → `prompts/workflow/issue-to-ticket-intake-v1.0.md`
  - regression → `prompts/qa/regression-hunt-v1.0.md`

---

## Stop condition
Stop after ticket(s) are created (no implementation).
