# Privacy Review (EchoPanel) — v1.0

**Goal**: Ensure planned/implemented behavior matches privacy commitments (explicit consent, visible listening indicators, least-privilege storage, safe exports, and safe debug artifacts).

---

## Role
You are the privacy reviewer. You do not implement fixes in this run.

---

## Inputs
- Scope: `<feature/PR/ticket list>`
- Surfaces: `macapp | server | landing`
- Repo access: `<YES/NO>`

---

## Evidence discipline
Label claims as **Observed / Inferred / Unknown** with file/command/screenshot evidence.

---

## Required discovery (if repo access)
```bash
rg -n "ScreenCapture|Microphone|CGPreflightScreenCaptureAccess|requestPermission|AVCaptureDevice" -S macapp/MeetingListenerApp/Sources
rg -n "Application Support|sessions|snapshot|transcript\\.jsonl|export" -S macapp/MeetingListenerApp/Sources
rg -n "ws://|http://|WebSocket|send_text|receive" -S macapp server
rg -n "token|secret|Keychain|UserDefaults|ECHOPANEL_HF_TOKEN|hfToken" -S macapp server
rg -n "WAITLIST|email|name|company|role" -S landing
```

---

## Output (required)

### A) Privacy contract (Observed/Unknown)
- What is captured (system audio / mic / both)?
- What is stored locally (and where)?
- What is transmitted over network (and to whom)?
- Retention: how long does data persist by default?

### B) Controls checklist (Observed/Inferred/Unknown)
- Listening indicator: unambiguous, always visible while capturing
- Source clarity: System/Mic/Both is accurate everywhere
- Permissions recovery: deny/revoke/re-allow paths are clear
- Data minimization: nothing persisted unintentionally
- Exports: explicit user action; safe defaults; minimal metadata
- Debug bundle: does it include secrets or sensitive content unintentionally?

### C) Gaps (prioritized)
For each gap:
- Severity: `P0 | P1 | P2 | P3`
- Claim type: Observed/Inferred/Unknown
- Suggested smallest fix
- Verification steps (commands + manual)

### D) “No surprises” user messaging
- Recommended UI copy for permissions + data handling (short, user-facing)

Tickets:
- Create/update tickets in `docs/WORKLOG_TICKETS.md` for P0/P1 items.

---

## Stop condition
Stop after review + prioritized gaps. Do not implement changes.
