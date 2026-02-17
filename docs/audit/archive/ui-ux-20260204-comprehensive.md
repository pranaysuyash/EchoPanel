> **⚠️ OBSOLETE (2026-02-16):** All 3 findings resolved — verified against source code:
> - F-001 (readable History): `SessionHistoryView.swift:17-19` — Summary/Transcript/JSON tabs
> - F-002 (delete controls): `SessionHistoryView.swift:14,228-229` — delete confirmation alert + `SessionStore.swift:287` `deleteSession()`
> - F-003 (search/filter): `SessionHistoryView.swift:12,57,73` — `searchText` field + `filteredSessions` computed property
> - Additional: Reveal in Finder via `NSWorkspace.shared.activateFileViewerSelecting` (`SessionHistoryView.swift:148`)

# UI/UX Design Audit (EchoPanel) — Comprehensive Pass — 2026-02-04

Prompt used: `prompts/ui/ui-ux-design-audit-v1.1.0.md`

## Update (2026-02-13)

This audit is a point-in-time document from 2026-02-04. As of 2026-02-13, the three primary History-related findings in this doc have been addressed:

- F-001 (human-readable History): History now has Summary/Transcript/JSON tabs and renders a readable markdown summary (final summary preferred, fallback to rendered snapshot markdown). Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (`Tab`, `snapshotMarkdown`, `transcriptPane`).
- F-002 (delete controls): History includes "Delete…" with confirmation and deletes the on-disk session directory. Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (delete alert), `macapp/MeetingListenerApp/Sources/SessionStore.swift` (`deleteSession`).
- F-003 (search/filter): History includes a sidebar search field that filters sessions by date/time. Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (`searchText`, `filteredSessions`).

Additional UX affordance added: "Reveal in Finder" for the selected session to make local storage more transparent. Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`, `macapp/MeetingListenerApp/Sources/SessionStore.swift` (`sessionDirectoryURL`).

## Personas (primary)
1) **Recruiter / Hiring manager** — wants a clean transcript, reliable action items, named entities, and fast export/share right after calls.  
2) **Privacy-conscious user** — wants explicit consent, visible listening indicators, and clear local vs network behavior.

## Scope contract
- In-scope:
  - macOS app: menu bar controls, onboarding, side panel live loop, stop → summary → export, history/recovery, diagnostics
  - landing: hero + waitlist form trust UX
- Out-of-scope:
  - ASR/diarization accuracy benchmarking
  - distribution/signing/notarization
  - “cloud product” design exploration
- Behavior change allowed: **YES** (UX/polish and user-facing flows)

---

## Executive verdict

### Professional feel: **partial → close**
- Observed: Core screens exist (Onboarding, Side Panel, Summary, History, Diagnostics, Settings) and the live loop is coherent.  
  Evidence: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`, `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/SummaryView.swift`, `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`
- Observed: Finalization outcomes are explicitly surfaced and the Summary window opens on stop, which removes ambiguity and feels “real”.  
  Evidence: `macapp/MeetingListenerApp/Sources/AppState.swift`, `macapp/MeetingListenerApp/Sources/SummaryView.swift`
- Inferred: The biggest “professional product” gap is **historical session review**: the History view currently exposes raw JSON rather than a human-readable recap.

### Biggest UX adoption risks (P0/P1)
1) **History view is developer-centric** (raw JSON) rather than user-centric (readable summary/transcript + exports). (P1)  
2) **Session lifecycle control**: users can accumulate sessions without an obvious “delete” control, increasing privacy anxiety over time. (P1)

---

## Screen map (IA)

### Entry points (Observed)
- Menu bar extra: `MeetingListenerApp` → `MenuBarExtra`  
  Evidence: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`
- Windows:
  - Onboarding (`id: "onboarding"`)
  - Summary (`id: "summary"`)
  - History (`id: "history"`)
  - Diagnostics (`id: "diagnostics"`)
  - Demo (`id: "demo"`)  
  Evidence: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`

---

## Findings (prioritized)

### F-001 (P1) — History should be human-readable, not raw JSON
- Claim type: **Observed**
- Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (shows `prettyJSON(snapshot)` as the primary details view)
- User impact: Users can’t easily review past sessions for actions/decisions/notes without re-parsing JSON.
- Recommendation:
  - Replace the details pane with a “Session snapshot viewer” that supports:
    - Summary markdown view (prefer final summary, fallback to rendered live markdown)
    - Transcript view (final lines, timestamped, speaker/source)
    - JSON view (advanced/debug)
  - Add export actions for Markdown and JSON (and optionally transcript-only).
- Verification:
  - Manual: open History → select sessions → confirm summary/transcript render; exports produce expected files.
  - Build: `cd macapp/MeetingListenerApp && swift build`

### F-002 (P1) — History needs deletion controls + privacy hygiene
- Claim type: **Inferred** (based on current UI)
- Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (no session delete action; only “Discard Recoverable Session”)
- User impact: Privacy-conscious users will hesitate if they can’t easily remove local session data.
- Recommendation:
  - Add “Delete selected session…” with confirmation.
  - Add “Reveal in Finder” (optional) to make storage feel transparent.
- Verification:
  - Manual: delete session removes it from list; does not affect other sessions; recoverable marker remains correct.

### F-003 (P2) — History list needs quick search/filter
- Claim type: **Inferred**
- Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` (list shows only date/time; no search)
- User impact: As sessions grow, finding a specific session becomes slow.
- Recommendation:
  - Add a lightweight search field that filters by date/time and optionally summary snippet (if available).
- Verification:
  - Manual: typing filters list instantly; clear button restores list.

---

## Ticket backlog (from findings)

P1 quick wins (≤1 day):
- F-001 History readable viewer + exports
- F-002 Delete session action + confirmation

P2 polish:
- F-003 Search/filter sessions
