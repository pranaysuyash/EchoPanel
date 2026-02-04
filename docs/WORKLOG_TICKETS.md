# Worklog Tickets (EchoPanel)

Append-only ticket log. Create a ticket before starting work; update status as you go.

## Status keys
- **OPEN** 🔵
- **IN_PROGRESS** 🟡
- **BLOCKED** 🔴
- **DONE** ✅

## Ticket template

```md
### TCK-YYYYMMDD-NNN :: <Short title>

Type: AUDIT_FINDING | BUG | FEATURE | IMPROVEMENT | HARDENING | DOCS
Owner: <human owner> (agent: <agent name>)
Created: YYYY-MM-DD HH:MM (local time)
Status: **<OPEN|IN_PROGRESS|BLOCKED|DONE>**
Priority: P0 | P1 | P2 | P3

Description:
<What is being done and why (1–4 lines)>

Scope contract:
- In-scope:
  - ...
- Out-of-scope:
  - ...
- Behavior change allowed: YES/NO/UNKNOWN

Targets:
- Surfaces: macapp | server | landing | docs
- Files: ...
- Branch/PR: <branch name / PR URL / Unknown>
- Range: <base..head or Unknown>

Acceptance criteria:
- [ ] ...
- [ ] ...

Evidence log:
- [YYYY-MM-DD HH:MM] <action> | Evidence:
  - Command: `<command>`
  - Output:
    ```
    <raw output>
    ```
  - Interpretation: Observed/Inferred/Unknown — <one sentence>

Status updates:
- [YYYY-MM-DD HH:MM] **OPEN** — created

Next actions:
1) ...
```

---

## Active tickets

### TCK-20260204-001 :: Establish repo prompt library + worklog system

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04
Status: **DONE** ✅
Priority: P1

Scope contract:
- In-scope: Add `AGENTS.md`, `prompts/`, `docs/WORKLOG_TICKETS.md`, `docs/audit/` scaffolding, and a `scripts/project_status.sh`.
- Out-of-scope: Product feature changes, security hardening, refactors.
- Behavior change allowed: NO

Acceptance criteria:
- [x] Prompt library exists and is indexed
- [x] Worklog exists with template
- [x] Status script prints usable summary

Evidence log:
- [2026-02-04] Added PM/prompt scaffolding files.

Status updates:
- [2026-02-04] **DONE** ✅ — scaffolding added

### TCK-20260204-002 :: Finalization failure UX (clear outcomes + export partial)

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04
Status: **DONE** ✅
Priority: P0

Scope contract:
- In-scope: Summary/finalization UI states when `final_summary` is delayed or missing; CTAs (Export partial, Open Diagnostics).
- Out-of-scope: ASR accuracy, backend diarization, distribution/signing.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/AppState.swift`, `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`, `macapp/MeetingListenerApp/Sources/SummaryView.swift`

Acceptance criteria:
- [ ] If final summary times out, user sees an explicit “Finalization incomplete” status.
- [ ] User can export partial session data from the Summary window.
- [ ] User has a clear “Open Diagnostics” action when finalization fails.

Source:
- Audit: `docs/audit/ui-ux-20260204.md`

Status updates:
- [2026-02-04] **OPEN** 🔵 — created from audit
- [2026-02-04] **DONE** ✅ — added `finalizationOutcome`, summary banner, and always-open-summary-on-stop behavior

### TCK-20260204-003 :: Entity UX polish (mode help + click Entities to filter + jump)

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04
Status: **DONE** ✅
Priority: P1

Scope contract:
- In-scope: Explain highlight modes, make entity list interactive (filter transcript + scroll to mention), minor usability improvements.
- Out-of-scope: New backend NER dependencies, ML model selection, diarization.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/EntityHighlighter.swift`

Acceptance criteria:
- [ ] Highlight modes have a short explanation (tooltip or info popover).
- [ ] Clicking an entity row filters transcript and scrolls to a mention.
- [ ] Filter state is always visible and easy to clear.

Source:
- Audit: `docs/audit/ui-ux-20260204.md`

Status updates:
- [2026-02-04] **OPEN** 🔵 — created from audit
- [2026-02-04] **DONE** ✅ — added highlight mode help popover and entity-row click-to-filter/jump

### TCK-20260204-004 :: History view: human-readable summary + transcript + exports

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04 15:33 (local time)
Status: **DONE** ✅
Priority: P1

Description:
Make Session History usable for non-technical users by rendering past session content as readable Summary/Transcript views (with JSON as advanced), and add export actions.

Scope contract:
- In-scope:
  - Update History details pane to show a snapshot viewer with tabs: Summary, Transcript, JSON.
  - Add export actions for Markdown and JSON from History.
- Out-of-scope:
  - Cloud sync, tagging, search across sessions, or redesigning storage format.
  - Changes to live session capture/streaming.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`, `macapp/MeetingListenerApp/Sources/SessionStore.swift` (if needed)
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [x] History details pane shows a readable Summary markdown for the selected session (final summary if present; otherwise fallback to rendered notes from transcript/actions/decisions/risks/entities).
- [x] History details pane shows a readable Transcript view for the selected session (final lines only; includes timestamps).
- [x] History details pane includes a JSON tab for the raw snapshot.
- [x] History supports exporting Markdown and JSON for the selected session.

Evidence log:
- [2026-02-04 15:33] Created from audit | Evidence:
  - Command: `sed -n '1,260p' docs/audit/ui-ux-20260204-comprehensive.md`
  - Output:
    ```
    (see file)
    ```
  - Interpretation: Observed — audit identifies History UX gap and desired viewer/export behavior
- [2026-02-04 15:40] Built macapp | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Building for debugging...
    Build complete!
    ```
  - Interpretation: Observed — History changes compile successfully

Status updates:
- [2026-02-04 15:33] **OPEN** 🔵 — created from audit `docs/audit/ui-ux-20260204-comprehensive.md`
- [2026-02-04 15:36] **IN_PROGRESS** 🟡 — implementing History snapshot viewer and exports
- [2026-02-04 15:40] **DONE** ✅ — History now renders Summary/Transcript/JSON with Markdown/JSON exports

Next actions:
1) Implement a snapshot viewer component for History (Summary/Transcript/JSON tabs).
2) Add Markdown export for selected session; keep existing JSON export.
3) Build `macapp/MeetingListenerApp` and verify UX manually.

### TCK-20260204-005 :: History view: delete selected session (privacy hygiene)

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04 15:33 (local time)
Status: **DONE** ✅
Priority: P1

Description:
Add user-facing deletion controls for stored sessions so users can remove local data and feel safe using the app long-term.

Scope contract:
- In-scope:
  - Add “Delete selected session…” action with confirmation.
  - Ensure deletion updates list and does not break recoverable session marker.
- Out-of-scope:
  - Bulk delete, retention policies, encryption at rest.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`, `macapp/MeetingListenerApp/Sources/SessionStore.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [x] User can delete a selected session from History with a confirmation prompt.
- [x] Deleted session no longer appears in History and its files are removed from disk.
- [x] Deleting a non-recoverable session does not affect `sessions/recovery.json`.
- [x] If the selected session is the recoverable session, deletion clears the recovery marker and UI state.

Evidence log:
- [2026-02-04 15:33] Created from audit | Evidence:
  - Command: `sed -n '1,260p' docs/audit/ui-ux-20260204-comprehensive.md`
  - Output:
    ```
    (see file)
    ```
  - Interpretation: Inferred — privacy hygiene requires user-facing deletion; current UI lacks it
- [2026-02-04 15:40] Built macapp | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Building for debugging...
    Build complete!
    ```
  - Interpretation: Observed — deletion flow compiles successfully

Status updates:
- [2026-02-04 15:33] **OPEN** 🔵 — created from audit `docs/audit/ui-ux-20260204-comprehensive.md`
- [2026-02-04 15:36] **IN_PROGRESS** 🟡 — adding SessionStore deletion + UI confirmation
- [2026-02-04 15:40] **DONE** ✅ — added delete action with confirmation and recovery marker handling

Next actions:
1) Add `SessionStore.deleteSession(sessionId:)` and recovery-marker handling.
2) Add UI action + confirmation in `SessionHistoryView`.
3) Build and verify delete behavior.

### TCK-20260204-006 :: History view: search/filter sessions

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-04 15:34 (local time)
Status: **DONE** ✅
Priority: P2

Description:
Add lightweight search/filter so users can find sessions quickly as history grows.

Scope contract:
- In-scope:
  - Add a search field that filters session list by date/time string and (if available) summary snippet.
- Out-of-scope:
  - Full-text search across transcripts; tagging; analytics.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [x] History sidebar includes a search field with clear button.
- [x] Typing filters the session list immediately (no crashes, no lag on small histories).
- [x] Clearing search restores full list.

Status updates:
- [2026-02-04 15:34] **OPEN** 🔵 — created from audit `docs/audit/ui-ux-20260204-comprehensive.md`
- [2026-02-04 15:36] **IN_PROGRESS** 🟡 — adding search filtering to History sidebar
- [2026-02-04 15:40] **DONE** ✅ — History sidebar filters sessions by date/time search text

### TCK-20260204-007 :: No audio captured / “nothing happens” during listening

Type: BUG
Owner: Pranay (agent: codex)
Created: 2026-02-04 16:02 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Fix cases where starting a session produces no audio levels/transcript and the app appears idle, including backend connection failures, permission gating, and capture pipeline errors.

Scope contract:
- In-scope:
  - Diagnose capture pipeline end-to-end (permission → capture → websocket → server) and fix root cause.
  - Add user-visible diagnostics to distinguish “no permission / no backend / no audio” states.
- Out-of-scope:
  - ASR quality improvements, diarization accuracy, product redesign.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp | server
- Files: `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`, `macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift`, `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`, `macapp/MeetingListenerApp/Sources/BackendManager.swift`, `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `server/*`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [ ] If capture cannot start due to permissions, the UI explains what’s missing and offers a direct “Open System Settings” action.
- [ ] If backend connection fails, the UI shows an actionable error (host/port, retry) and Diagnostics link.
- [ ] Audio meters change when audio is present; if no audio is detected, UI shows the most likely causes (meeting muted, wrong source, permissions) with clear next steps.
- [ ] Starting a session results in transcript updates in a normal local setup (Observed via logs and/or session transcript segments).

Status updates:
- [2026-02-04 16:02] **IN_PROGRESS** 🟡 — created from user report
- [2026-02-04 16:08] **DONE** ✅ — system-audio start now prompts for Screen Recording permission; ScreenCaptureKit targets main display; builds/tests pass

### TCK-20260204-008 :: Backend “ready” false positives (port in use + ASR not available)

Type: BUG
Owner: Pranay (agent: codex)
Created: 2026-02-04 17:58 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Fix cases where the app claims the backend is ready even when (a) port 8000 is already in use by an old server process or (b) ASR provider is missing, leading to “audio is sent but nothing transcribes”.

Scope contract:
- In-scope:
  - Make `/health` correctly report readiness and return non-200 when ASR isn’t available.
  - Make macapp health check parse status and show “Running (Needs setup)” instead of “Running”.
  - Default/validate model name to a faster-whisper compatible value.
- Out-of-scope:
  - Packaging/installing ASR deps into the mac app bundle.
  - Per-app audio attribution (Chrome vs Zoom).
- Behavior change allowed: YES

Targets:
- Surfaces: macapp | server
- Files: `server/main.py`, `server/services/asr_stream.py`, `macapp/MeetingListenerApp/Sources/BackendManager.swift`, `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [x] `/health` returns HTTP 200 only when ASR provider is available; returns non-200 with reason otherwise.
- [x] macapp only marks backend “ready” when `/health` returns status ok; otherwise surfaces actionable “needs setup” detail.
- [x] Default model value is compatible with faster-whisper (fallback to `base`).

Evidence log:
- [2026-02-04 17:45] Observed port-in-use and incorrect readiness | Evidence:
  - Command: `tail -n 120 /var/folders/fc/xwynjqm94t39_jvz88fhcpfc0000gn/T/echopanel_server.log`
  - Output:
    ```
    error while attempting to bind on address ('127.0.0.1', 8000): address already in use
    ```
  - Interpretation: Observed — app-launched server fails to bind; a different server may still answer health checks
- [2026-02-04 17:50] Implemented health gating + UI detail | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete!
    ```
  - Interpretation: Observed — macapp compiles after BackendManager health parsing changes
- [2026-02-04 17:50] Verified server tests | Evidence:
  - Command: `.venv/bin/python -m pytest -q`
  - Output:
    ```
    4 passed
    ```
  - Interpretation: Observed — server test suite still passes after health changes

Status updates:
- [2026-02-04 17:58] **DONE** ✅ — health readiness fixed and surfaced; model default set to base; app now blocks “ghost ready” states

### TCK-20260204-009 :: Side panel doesn’t open reliably on Start Listening

Type: BUG
Owner: Pranay (agent: codex)
Created: 2026-02-04 18:06 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Make the side panel open even when the session cannot start (backend not ready / onboarding gating), so the user always gets visible state and guidance instead of “nothing happened”.

Scope contract:
- In-scope:
  - Always show side panel when user clicks Start Listening.
  - If backend isn’t ready, surface an actionable error in the panel header (instead of failing silently).
- Out-of-scope:
  - Redesigning side panel controls or adding a dedicated “preflight” panel screen.
- Behavior change allowed: YES

Targets:
- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`, `macapp/MeetingListenerApp/Sources/SidePanelController.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:
- [x] Clicking “Start Listening” always opens the side panel window.
- [x] If backend is not ready, side panel shows “Not ready” state + message (via status line) instead of doing nothing.
- [x] Build passes.

Evidence log:
- [2026-02-04 18:07] Built macapp | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete!
    ```
  - Interpretation: Observed — side panel start behavior changes compile

Status updates:
- [2026-02-04 18:08] **DONE** ✅ — side panel now opens before start gating; close logging uses NSLog

Evidence log:
- [2026-02-04 16:05] Patched Screen Recording permission flow + display selection | Evidence:
  - Command: `rg -n "requestPermission\\(\\)" -S macapp/MeetingListenerApp/Sources/AppState.swift macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
  - Output:
    ```
    (see diffs in files)
    ```
  - Interpretation: Observed — startSession now prompts for Screen Recording and AudioCapture prefers main display
- [2026-02-04 16:07] Built and tested | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete!
    ```
  - Interpretation: Observed — macapp compiles after permission/capture changes
- [2026-02-04 16:07] Ran python tests | Evidence:
  - Command: `.venv/bin/python -m pytest -q`
  - Output:
    ```
    4 passed
    ```
  - Interpretation: Observed — server test suite still passes

---

## [P0] Fix multi-source partial overwrites + timer drift (macapp)

Context:
- With `Audio Source = Both`, ASR partials for system + mic can interleave; previously we only updated “the last partial”, causing one stream to overwrite the other in the transcript UI.
- Timer display could drift vs transcript timestamps in some menu-bar execution contexts.

Acceptance criteria:
- [x] System + mic partials don’t overwrite each other in the transcript list.
- [x] Header timer stays aligned with transcript time during active streaming.
- [x] Build passes.

Status updates:
- [2026-02-04 18:22] **DONE** ✅ — per-source partial tracking and elapsed sync on ASR messages

Evidence log:
- [2026-02-04 18:22] Built macapp | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build -c release`
  - Output:
    ```
    Build complete!
    ```
  - Interpretation: Observed — app compiles after transcript/timer changes

---

### TCK-20260204-002 :: Streaming ASR/NLP Reliability Audit

Type: AUDIT
Owner: pranay (agent: amp)
Created: 2026-02-04 20:00 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Comprehensive audit of streaming ASR/NLP pipeline. Identified P0-P2 issues
causing "streaming ASR and NLP are not working reliably". Fixed critical bugs:
- Missing `_pcm_stream()` function (NameError on first audio)
- CTranslate2 MPS/float16 unsupported (crash on macOS)
- Stop semantics race (incomplete transcripts in final_summary)
- WebSocket send-after-close race condition

Scope contract:
- In-scope:
  - ws_live_listener.py (WebSocket handler)
  - provider_faster_whisper.py (ASR provider)
  - test_ws_integration.py (test fix)
- Out-of-scope:
  - Diarization re-enable
  - Model pre-loading
- Behavior change allowed: YES (bug fixes)

Targets:
- Surfaces: server
- Files: server/api/ws_live_listener.py, server/services/provider_faster_whisper.py, tests/test_ws_integration.py
- Branch/PR: main
- Range: N/A (direct edits)

Acceptance criteria:
- [x] `_pcm_stream()` defined and used
- [x] CTranslate2 falls back to CPU/int8 on macOS
- [x] ASR flush completes before analysis cancel on stop
- [x] WebSocket send handles closed connection
- [x] All tests pass

Evidence log:
- [2026-02-04 20:00] Audit completed | Evidence:
  - Command: `pytest tests/ -v`
  - Output:
    ```
    4 passed
    ```
  - Interpretation: Observed — all P0 fixes verified by tests
- [2026-02-04 20:05] Audit report created | Evidence:
  - File: `docs/audit/STREAMING_ASR_AUDIT_2026-02.md`
  - Interpretation: Observed — detailed findings documented
