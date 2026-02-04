# Repo UI Audit + Deep Dives (EchoPanel) — v1.0

**Goal**: a repo-grounded UI audit that maps real user flows to real code files, then deep-dives the highest impact UI files.

## Evidence discipline (required)
Every non-trivial claim: **Observed / Inferred / Unknown**.
All “Observed” must point to:
- file paths/symbols, or
- screenshot paths, or
- command outputs.

## Phase A — Whole-repo UI audit (macapp + landing)

### A1) Inventory user-facing surfaces (Observed)
Run:
```bash
rg -n "Window\\(|MenuBarExtra|Settings\\s*\\{" -S macapp/MeetingListenerApp/Sources
rg -n "struct .*View" -S macapp/MeetingListenerApp/Sources
rg -n "data-waitlist|waitlist" -S landing
```

### A2) Core workflows (Observed)
List workflows:
- First run onboarding
- Start listening
- Live loop (transcript/cards/entities)
- Stop → summary → export
- Recovery (permission denied, backend down, silence)
- History/recovery

### A3) Cross-cutting findings (Observed)
For each:
- observation
- impact
- recommendation
- where (file paths)
- how to validate

### A4) Deep dive targets (Observed)
Pick 3–6 highest impact UI files (likely):
- `SidePanelView.swift`
- `MeetingListenerApp.swift`
- `OnboardingView.swift`
- `SummaryView.swift`
- `SessionHistoryView.swift`

Justify each target based on Phase A findings.

## Phase B — Deep dive (one file at a time)
For each deep dive file:
1) Responsibilities and boundaries (Observed)
2) State matrix: loading/empty/error/success/disabled (Observed/Unknown)
3) Interaction + keyboard shortcuts + focus management (Observed/Unknown)
4) Performance risks (Observed/Inferred)
5) Fix options and tradeoffs (no code required in audit; code changes in remediation prompt)

## Required outputs
- Audit artifact: `docs/audit/ui-repo-<YYYYMMDD>.md`
- Tickets: `docs/WORKLOG_TICKETS.md` (P0/P1 items become tickets)
- Optional: split deep dives into separate files under `docs/audit/`

