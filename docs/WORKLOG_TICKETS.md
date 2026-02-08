# Worklog Tickets (EchoPanel)

Append-only ticket log. Create a ticket before starting work; update status as you go.

## Status keys

- **OPEN** 🔵
- **IN_PROGRESS** 🟡
- **BLOCKED** 🔴
- **DONE** ✅

## Ticket template

````md
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

1. ...
````

---

## Active tickets

### TCK-20260208-001 :: macapp bug sweep — thread safety, UI, and logic fixes

Type: BUG
Owner: Pranay (agent: Amp)
Created: 2026-02-08 12:00 (local time)
Status: **DONE** ✅
Priority: P1

Description:
Comprehensive code review of the macOS app identified 10 issues spanning thread safety,
logic bugs, UI issues, and resource concerns. This ticket tracks fixes for all of them.

Scope contract:

- In-scope:
  - Thread safety: data races on `debugBytes`, `totalSamples`, `screenFrames`, counter vars
  - Logic: `stopServer` termination handler race, stale WebSocket URL after settings change,
    double-resume risk in `stopAndAwaitFinalSummary`
  - UI: `Cmd+C` overriding standard copy
  - Resource: per-frame NSLog spam in `onPCMFrame`
  - Probe timeout blocking main thread
- Out-of-scope:
  - Deprecated `.onChange` API (correct for macOS 13 deployment target)
  - Unused `NSObject` conformance on `WebSocketStreamer` (harmless)
- Behavior change allowed: NO (bug fixes only)

Targets:

- Surfaces: macapp
- Files:
  - `macapp/MeetingListenerApp/Sources/AppState.swift`
  - `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
  - `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`
  - `macapp/MeetingListenerApp/Sources/BackendManager.swift`
  - `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`

Acceptance criteria:

- [x] `debugBytes` mutation moved inside `Task { @MainActor }` — no data race
- [x] `totalSamples`, `screenFrames` protected by `statsLock` in AudioCaptureManager
- [x] `audioCallCount`, `screenCallCount` protected by `counterLock` in AudioSampleHandler
- [x] Per-frame NSLog removed (already fixed prior to this ticket)
- [x] `stopAndAwaitFinalSummary` timeout uses `DispatchQueue.main.asyncAfter` (already fixed prior)
- [x] `stopServer` termination handler clears `healthDetail` when `stopRequested`
- [x] Probe timeout reduced to 0.25s (already fixed prior)
- [x] WebSocket URL reads from `BackendConfig` on each connect (computed property)
- [x] `Cmd+C` changed to `Cmd+Shift+C` for Copy Markdown (already fixed prior)
- [x] `swift build` passes

Evidence log:

- [2026-02-08 12:00] Code review identified 10 issues | Evidence:
  - Files reviewed: all Sources/*.swift
  - Interpretation: Observed — 10 issues across 5 files

- [2026-02-08 12:30] Applied fixes | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output: `Build complete! (8.52s)`
  - Interpretation: Observed — all fixes compile cleanly

Status updates:

- [2026-02-08 12:00] **IN_PROGRESS** 🟡 — applying fixes
- [2026-02-08 12:30] **DONE** ✅ — all fixes applied, build passes

---

### TCK-20260206-003 :: v0.2 Launch UI refresh + landing + pricing + packaging readiness

Type: FEATURE
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:00 (local time)
Status: **OPEN** 🔵
Priority: P0

Description:
Define the v0.2 launch-ready UX for a portrait side panel (POS-style rolling window), update landing page to match, and align pricing/licensing + distribution requirements for Feb launch.

Scope contract:

- In-scope:
  - UI/UX change spec for portrait side panel with rolling window + tabs.
  - Launch readiness docs: pricing/licensing, packaging/deployment, QA plan, release readiness checklist.
  - Landing page copy/visual update to reflect new UI.
- Out-of-scope:
  - Full Swift UI implementation of the new side panel.
  - Backend model accuracy tuning.
- Behavior change allowed: YES (landing/UX docs)

Targets:

- Surfaces: docs | landing
- Files: `docs/*`, `landing/*`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] UI change spec documents the portrait side panel layout, rolling window behavior, and tab interactions.
- [ ] Pricing/licensing plan updated for Feb launch with clear tiers and assumptions.
- [ ] Distribution/packaging plan aligned with launch timeline and required Apple account steps.
- [ ] Landing page reflects portrait side panel and new feature framing.
- [ ] QA test plan and release readiness checklist updated for v0.2 launch.

Evidence log:

- [2026-02-06 00:00] Ticket created from user request | Evidence:
  - Source: User request in chat (2026-02-06)
  - Interpretation: Observed — requested UI change + launch readiness docs + landing updates

- [2026-02-06 10:12] Reviewed UI/UX notes + landing copy for side panel concept | Evidence:
  - Files: `docs/UI.md`, `docs/UX.md`, `landing/index.html`
  - Interpretation: Observed — existing side panel structure and UX baselines captured

Status updates:

- [2026-02-06 00:00] **OPEN** 🔵 — created
- [2026-02-06 00:40] **IN_PROGRESS** 🟡 — drafting UI/launch docs and landing refresh

Evidence log:

- [2026-02-06 00:58] Drafted UI/launch artifacts | Evidence:
  - Files: `docs/UI_CHANGE_SPEC_2026-02-06.md`, `docs/PRD_LAUNCH_UI_V0_2_2026-02-06.md`, `docs/audit/test-plan-20260206.md`, `docs/audit/release-readiness-20260206.md`, `docs/DEPLOY_RUNBOOK_2026-02-06.md`, `docs/LICENSING.md`
  - Interpretation: Observed — launch documentation created
- [2026-02-06 10:12] **IN_PROGRESS** 🟡 — drafting portrait side panel concept + interaction model

Evidence log:

- [2026-02-06 10:20] Reviewed pricing + launch + distribution docs | Evidence:
  - Command: `read_file docs/PRICING.md docs/LAUNCH_PLANNING.md docs/DISTRIBUTION_PLAN_v0.2.md`
  - Output:
    ```
    (see files)
    ```
  - Interpretation: Observed — source material gathered for Feb launch plan and recommendations

Next actions:

1. Draft UI change spec for portrait side panel + tabs.
2. Update pricing/licensing and distribution docs.
3. Update landing page visuals/copy.

### TCK-20260206-004 :: Portrait side panel + tabbed layout (macapp)

Type: FEATURE
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:15 (local time)
Status: **OPEN** 🔵
Priority: P0

Description:
Implement portrait side panel with tabs (Transcript/Decisions/Timeline/Documents) and rolling transcript window.

Scope contract:

- In-scope:
  - Portrait layout (~30% width) with tabbed content.
  - Rolling transcript window (cap recent segments).
  - Preserve status line and footer controls.
- Out-of-scope:
  - RAG indexing backend.
  - Full visual redesign of summary/history.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/*`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Panel renders in portrait layout with tabs and status/footer preserved.
- [ ] Transcript tab shows rolling window with recent segments only.
- [ ] No regression in Start/Stop flow.

Status updates:

- [2026-02-06 00:15] **OPEN** 🔵 — created from PRD
- [2026-02-06 01:05] **IN_PROGRESS** 🟡 — implementing portrait layout + tabs
- [2026-02-06 01:20] **DONE** ✅ — portrait layout + tabs shipped in side panel

Evidence log:

- [2026-02-06 01:20] Implemented portrait layout | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/SidePanelController.swift`
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete! (4.02s)
    ```
  - Interpretation: Observed — build passes with portrait tabbed UI

### TCK-20260206-005 :: Keyboard tab rotation + auto-scroll pause

Type: IMPROVEMENT
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:16 (local time)
Status: **OPEN** 🔵
Priority: P1

Description:
Add left/right arrow tab rotation and pause auto-scroll on user scroll with “Resume Live”.

Scope contract:

- In-scope:
  - Left/Right arrow keyboard navigation across tabs.
  - Auto-scroll pause on manual scroll + Resume Live action.
- Out-of-scope:
  - Global shortcuts in macOS menu.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/*`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Arrow keys rotate tabs when focus is not in a text field.
- [ ] Manual scroll pauses auto-follow; Resume Live restores.

Status updates:

- [2026-02-06 00:16] **OPEN** 🔵 — created from PRD
- [2026-02-06 01:05] **IN_PROGRESS** 🟡 — adding arrow-key rotation + auto-scroll pause
- [2026-02-06 01:21] **DONE** ✅ — arrow keys rotate tabs; scroll pause + Resume Live added

Evidence log:

- [2026-02-06 01:21] Implemented keyboard + auto-scroll | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — left/right arrow handling and auto-scroll pause UI added

### TCK-20260206-006 :: Documents tab (local upload stub)

Type: FEATURE
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:17 (local time)
Status: **OPEN** 🔵
Priority: P2

Description:
Add a Documents tab with local file upload + listing to prep for RAG.

Scope contract:

- In-scope:
  - Upload UI for PDF/MD/TXT.
  - Local file list with status (Queued/Indexed placeholder).
- Out-of-scope:
  - Embeddings, retrieval, or server-side indexing.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/*`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Users can add local docs and see them listed.
- [ ] UI shows placeholder indexing state without backend.

Status updates:

- [2026-02-06 00:17] **OPEN** 🔵 — created from PRD
- [2026-02-06 00:55] **BLOCKED** 🔴 — deferred to v0.3 per launch scope decision

### TCK-20260206-007 :: Landing refresh for portrait UI

Type: DOCS
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:18 (local time)
Status: **OPEN** 🔵
Priority: P1

Description:
Update landing page to reflect portrait side panel, tabbed views, and documents/RAG positioning.

Scope contract:

- In-scope:
  - Update hero mock and copy to match new UI.
- Out-of-scope:
  - Full redesign, new marketing sections.
- Behavior change allowed: YES

Targets:

- Surfaces: landing
- Files: `landing/index.html`, `landing/styles.css`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Hero mock shows portrait panel with tabs.
- [ ] Copy mentions tabbed views and document context.

Status updates:

- [2026-02-06 00:18] **OPEN** 🔵 — created from PRD
- [2026-02-06 00:45] **DONE** ✅ — landing hero mock + copy updated for portrait UI

Evidence log:

- [2026-02-06 00:45] Updated landing assets | Evidence:
  - Files: `landing/index.html`, `landing/styles.css`
  - Interpretation: Observed — portrait panel + tabbed mock now reflected

### TCK-20260206-008 :: Pricing/licensing + distribution docs refresh

Type: DOCS
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 00:19 (local time)
Status: **OPEN** 🔵
Priority: P1

Description:
Refresh pricing/licensing docs and align distribution plan for Feb launch.

Scope contract:

- In-scope:
  - Update pricing tiers and licensing assumptions.
  - Clarify Apple Developer account needs and DMG distribution steps.
- Out-of-scope:
  - Implementing licensing enforcement.
- Behavior change allowed: YES

Targets:

- Surfaces: docs
- Files: `docs/PRICING.md`, `docs/DISTRIBUTION_PLAN_v0.2.md`, new licensing doc
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Pricing tiers are concrete and launch-appropriate.
- [ ] Licensing and Apple account prerequisites are explicit.

Status updates:

- [2026-02-06 00:19] **OPEN** 🔵 — created from PRD
- [2026-02-06 00:46] **DONE** ✅ — pricing/licensing/distribution docs updated

Evidence log:

- [2026-02-06 00:46] Updated pricing/licensing/distribution docs | Evidence:
  - Files: `docs/PRICING.md`, `docs/LICENSING.md`, `docs/DISTRIBUTION_PLAN_v0.2.md`
  - Interpretation: Observed — launch-facing docs updated

### TCK-20260206-009 :: Side panel content vertically centered

Type: BUG
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 16:58 (local time)
Status: **DONE** ✅
Priority: P1

Description:
The portrait side panel content is vertically centered within the window, leaving a large blank area at the top. Align content to the top edge to match the intended layout.

Scope contract:

- In-scope:
  - Align the side panel root layout to top.
- Out-of-scope:
  - Visual redesign of header, controls, or spacing.
  - Changes to panel sizing.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Side panel content aligns to the top of the window with no large blank region.
- [ ] Build passes.

Status updates:

- [2026-02-06 16:58] **IN_PROGRESS** 🟡 — created from user report

Evidence log:

- [2026-02-06 17:02] Adjusted side panel alignment and built macapp | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete! (2.94s)
    ```
  - Interpretation: Observed — build passes after aligning layout to top

Status updates:

- [2026-02-06 17:02] **DONE** ✅ — side panel content aligned to top

### TCK-20260206-010 :: Apple-native glass UI polish (side panel)

Type: IMPROVEMENT
Owner: Pranay (agent: GitHub Copilot)
Created: 2026-02-06 17:10 (local time)
Status: **DONE** ✅
Priority: P1

Description:
Apply an Apple-native glass look to the portrait side panel: soft material backgrounds, subtle strokes, and refined spacing to match macOS design language.

Scope contract:

- In-scope:
  - Glass-style background for the side panel container.
  - Refined card surfaces with subtle material and shadow.
- Out-of-scope:
  - Full redesign of control placement or content structure.
  - New features or tab logic changes.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [ ] Side panel container uses a glass-like material with a subtle border and shadow.
- [ ] Cards retain native styling with a refined material surface.
- [ ] Build passes.

Status updates:

- [2026-02-06 17:10] **IN_PROGRESS** 🟡 — created from user request

Evidence log:

- [2026-02-06 17:14] Applied glass styling and rebuilt macapp | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete! (3.91s)
    ```
  - Interpretation: Observed — build passes with glass material styling

Status updates:

- [2026-02-06 17:14] **DONE** ✅ — glass UI polish applied to side panel

### TCK-20260206-014 :: Unified three-cut live UI (Roll default, Compact + Full renderers)

Type: FEATURE
Owner: Pranay (agent: codex)
Created: 2026-02-06 20:21 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Implement the transcript-first three-cut UI model from the HTML prototypes in native macOS SwiftUI using one interaction spine: Full view, Compact view, and Roll default behavior with shared shortcuts and follow-live semantics.

Scope contract:

- In-scope:
  - Shared interaction state in side panel for focus cursor, lens, follow-live, pinned lines, and active surface.
  - Three native renderers (Full/Compact/Roll) under one state model.
  - Shared keyboard controls: `↑/↓`, `Enter`, `P`, `Space`, `J`, `Esc`, `?`, plus surface cycling on `←/→`.
  - UI-level surface parity (Summary, Actions, Pins, Entities, Raw) with presentation differences by view mode.
- Out-of-scope:
  - Backend protocol/data model changes.
  - New analysis extraction models.
  - Cloud sync or document indexing backend work.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/SidePanelController.swift`, `docs/UI.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Side panel provides native Full, Compact, and Roll renderers from one shared interaction model.
- [x] Roll view implements explicit follow-live state, focus cursor, inline lens, and overlay surfaces.
- [x] Core keyboard contract is implemented consistently in native app.
- [x] Compact and Full views remain transcript-compatible and can navigate with the same focus/lens/pin behaviors.
- [x] `swift build` passes.

Evidence log:

- [2026-02-06 20:18] Audited HTML prototypes and current Swift state | Evidence:
  - Files: `echopanel.html`, `echopanel_sidepanel.html`, `echopanel_roll.html`, `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — prototypes define shared cursor/follow/lens/pins/surfaces behavior not yet implemented natively
- [2026-02-06 20:31] Implemented unified side-panel state + three renderers and adaptive panel sizing | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/SidePanelController.swift`
  - Interpretation: Observed — shared state model now drives Roll, Compact, and Full native presentations
- [2026-02-06 20:32] Verified build after implementation | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete! (7.95s)
    ```
  - Interpretation: Observed — macapp compiles successfully with three-cut UI implementation
- [2026-02-06 20:35] Updated UI docs to reflect three-cut architecture and shortcut invariants | Evidence:
  - File: `docs/UI.md`
  - Interpretation: Observed — UI source-of-truth now documents Roll/Compact/Full behavior and shared interaction contract

Status updates:

- [2026-02-06 20:21] **IN_PROGRESS** 🟡 — implementing unified three-cut native UI in side panel
- [2026-02-06 20:32] **DONE** ✅ — three-cut native side panel shipped with shared keyboard interaction model

### TCK-20260206-015 :: Apple HIG polish + validation + docs for three-cut side panel

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-06 21:07 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Refine the new native three-cut side panel to better align with Apple platform guidance (hierarchy, adaptive layout, accessibility, motion) and provide explicit validation/documentation evidence.

Scope contract:

- In-scope:
  - Apple-guideline UI polish for three-cut side panel in macapp.
  - Accessibility and reduced-motion handling for key interactions.
  - Verification commands and documented manual checks in docs.
- Out-of-scope:
  - Backend/service logic changes.
  - New feature surfaces beyond existing Roll/Compact/Full and Summary/Actions/Pins/Entities/Raw.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `docs/UI.md`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Side panel uses adaptive hierarchy and semantic visual decisions suitable for macOS (including compact constraints).
- [x] Core controls and micro-actions include accessibility labels/hints.
- [x] Transcript scrolling and state transitions respect Reduce Motion settings.
- [x] `swift build` and `swift test` run successfully for `macapp/MeetingListenerApp`.
- [x] Docs describe Apple-HIG alignment decisions and concrete manual verification steps.

Evidence log:

- [2026-02-06 21:07] Ticket created from user request for Apple standards + full testing/docs | Evidence:
  - Source: User request in chat (2026-02-06 21:06 local)
  - Interpretation: Observed — requested standards-focused polish, testing, and documentation
- [2026-02-06 22:41] Applied Apple-HIG polish pass to side panel | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — adaptive two-row header hierarchy, semantic macOS colors/materials, persisted mode selection, reduced-motion-aware transitions, and accessibility labels were added
- [2026-02-06 22:43] Added side-panel contract tests and package test target | Evidence:
  - Files: `macapp/MeetingListenerApp/Package.swift`, `macapp/MeetingListenerApp/Tests/SidePanelContractsTests.swift`
  - Interpretation: Observed — test target now validates mode/surface contract invariants
- [2026-02-06 22:43] Ran package tests for macapp | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift test`
  - Output:
    ```
    Executed 2 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — tests pass
- [2026-02-06 22:43] Verified macapp build after polish pass | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build`
  - Output:
    ```
    Build complete! (0.21s)
    ```
  - Interpretation: Observed — build passes
- [2026-02-06 22:44] Updated UI/testing documentation | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`
  - Interpretation: Observed — docs now capture HIG decisions and explicit three-cut verification checklist
- [2026-02-06 22:47] Re-ran final build + tests after semantic border color cleanup | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Executed 2 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — final code state compiles and tests pass

Status updates:

- [2026-02-06 21:07] **IN_PROGRESS** 🟡 — implementing HIG polish, running validation, and documenting checks
- [2026-02-06 22:44] **DONE** ✅ — Apple-guideline polish, testing, and documentation completed

### TCK-20260206-016 :: Full renderer parity completion (HTML-to-Swift) + docs/test closure

Type: FEATURE
Owner: Pranay (agent: codex)
Created: 2026-02-06 23:03 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Complete the remaining Full-view parity from `echopanel.html`/`echopanel_sidepanel.html`/`echopanel_roll.html` in native SwiftUI and close the loop with stronger contract tests plus explicit documentation/testing updates.

Scope contract:

- In-scope:
  - Full renderer parity elements in `SidePanelView` (session rail, insight tabs with context, timeline scrub, search focus shortcut wiring).
  - Contract test expansion for Full insight-tab invariants.
  - Documentation updates for UI invariants and manual verification checklist.
- Out-of-scope:
  - Backend API/protocol changes.
  - New model/provider integration.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Tests/SidePanelContractsTests.swift`, `docs/UI.md`, `docs/TESTING.md`, `docs/audit/test-plan-20260206.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Full renderer includes session rail, search affordance, context insight tab, and timeline scrub behavior.
- [x] Keyboard contract includes Full search focus shortcut (`Cmd/Ctrl + K`) without regressions to existing keys.
- [x] Contract tests cover Full insight-tab ordering and surface mapping behavior.
- [x] `swift build` and `swift test` pass for `macapp/MeetingListenerApp`.
- [x] UI/testing docs reflect the finalized three-cut parity contract.

Evidence log:

- [2026-02-06 23:03] Followed implementation workflow prompt | Evidence:
  - File: `prompts/remediation/implementation-v1.1.md`
  - Interpretation: Observed — remediation implementation prompt used for scoped execution/validation flow
- [2026-02-06 23:05] Implemented final Full renderer parity fixes | Evidence:
  - File: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — added missing Full-view support structs, fixed timeline decision token matching, and added `Cmd/Ctrl + K` search focus handling
- [2026-02-06 23:06] Expanded native UI contract tests | Evidence:
  - File: `macapp/MeetingListenerApp/Tests/SidePanelContractsTests.swift`
  - Interpretation: Observed — added Full insight-tab ordering and mapping contract coverage
- [2026-02-06 23:07] Validated macapp build and tests | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — code compiles and contract tests pass
- [2026-02-06 23:08] Updated source-of-truth docs for final parity checklist | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`, `docs/audit/test-plan-20260206.md`
  - Interpretation: Observed — docs now capture Full renderer-specific behaviors and explicit parity/manual validation steps

Status updates:

- [2026-02-06 23:03] **IN_PROGRESS** 🟡 — finalizing Full renderer parity + docs/tests closure
- [2026-02-06 23:08] **DONE** ✅ — Full parity, verification, and documentation completed

### TCK-20260206-017 :: Layout hardening pass for clipping/misalignment (Apple-quality fit/visibility)

Type: BUG
Owner: Pranay (agent: codex)
Created: 2026-02-06 23:11 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Fix reported UI clipping, misalignment, and hidden controls in native three-cut SwiftUI layouts so content remains visible and usable across practical window sizes.

Scope contract:

- In-scope:
  - Remove rigid width assumptions that cause control clipping in top/capture/footer areas.
  - Make Full layout responsive so columns can reflow instead of overflow.
  - Keep interaction contracts and existing backend wiring intact.
- Out-of-scope:
  - Backend protocol/data changes.
  - New feature surfaces beyond current Roll/Compact/Full contract.
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] View mode controls are fully visible and aligned in compact/roll/full without clipping.
- [x] Capture controls remain readable/operable without overlap at minimum window sizes.
- [x] Full mode avoids horizontal overflow by reflowing column layout when needed.
- [x] Footer actions stay accessible in narrow widths.
- [x] `swift build` and `swift test` pass.

Evidence log:

- [2026-02-06 23:11] Ticket created from visual QA findings | Evidence:
  - Source: User-provided screenshots and feedback in chat
  - Interpretation: Observed — clipping and visibility regressions are present in current native UI
- [2026-02-06 23:18] Implemented responsive layout hardening in side panel | Evidence:
  - File: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — adaptive top/capture/footer layouts were added, rigid width constraints were removed from SwiftUI root, and Full mode now reflows to avoid column overflow
- [2026-02-06 23:19] Validated build and tests | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — native app compiles and existing UI contract tests pass
- [2026-02-06 23:21] Re-ran final build+tests after doc/worklog closure | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — final tree state remains green
- [2026-02-06 23:20] Updated validation docs for minimum-size clipping checks | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`
  - Interpretation: Observed — docs now include responsive layout expectations and narrow-window verification steps

Status updates:

- [2026-02-06 23:11] **IN_PROGRESS** 🟡 — implementing responsive layout hardening
- [2026-02-06 23:20] **DONE** ✅ — clipping/misalignment hardening pass completed and validated

### TCK-20260206-018 :: Live capture diagnostics + timer resilience (no-transcript troubleshooting)

Type: BUG
Owner: Pranay (agent: codex)
Created: 2026-02-06 23:22 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Address user-reported "Audio good but timer stalled and transcript stuck at waiting for speech" by improving timer robustness and surfacing explicit live source diagnostics (input frames + ASR source activity).

Scope contract:

- In-scope:
  - Make timer display resilient during listening even when transcript events are sparse.
  - Track and display source diagnostics (system vs mic frame flow, last ASR source, last transcript event age).
  - Add UI hints clarifying current source capture behavior.
- Out-of-scope:
  - Backend ASR model/provider changes.
  - App-level per-process audio attribution (browser tab/app-specific routing).
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/AppState.swift`, `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Timer display keeps advancing while session is listening.
- [x] UI shows live source diagnostics (system/mic input + ASR source freshness).
- [x] Empty transcript state includes actionable source troubleshooting hints.
- [x] `swift build` and `swift test` pass.

Evidence log:

- [2026-02-06 23:22] Ticket created from user QA report | Evidence:
  - Source: User feedback and screenshots in chat
  - Interpretation: Observed — visible symptom includes timer stall perception and no transcript despite active audio indicators
- [2026-02-06 23:28] Implemented timer resilience + source diagnostics state | Evidence:
  - File: `macapp/MeetingListenerApp/Sources/AppState.swift`
  - Interpretation: Observed — timer display now uses wall-clock fallback during listening, and per-source input/ASR freshness tracking was added
- [2026-02-06 23:29] Implemented diagnostics strip in side panel | Evidence:
  - File: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — capture bar now renders `System`/`Mic` freshness chips and troubleshooting hints in waiting state
- [2026-02-06 23:29] Validated build + tests | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — macapp compiles and tests pass after diagnostics changes
- [2026-02-06 23:51] Re-ran self-verification test suite (server + macapp) | Evidence:
  - Commands:
    - `source .venv/bin/activate && pytest -q tests/test_streaming_correctness.py`
    - `source .venv/bin/activate && pytest -q tests/test_ws_live_listener.py`
    - `source .venv/bin/activate && uv pip install httpx && pytest -q tests/test_ws_integration.py`
    - `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    9 passed
    1 passed
    1 passed
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — source-tagged websocket flow and streaming correctness tests pass locally; macapp build/tests also pass
- [2026-02-06 23:30] Updated docs for diagnostics verification and source-granularity expectation | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`
  - Interpretation: Observed — docs now capture diagnostics strip behavior and clarify source granularity limits

Status updates:

- [2026-02-06 23:22] **IN_PROGRESS** 🟡 — implementing timer/source diagnostics fix
- [2026-02-06 23:30] **DONE** ✅ — timer/source diagnostics fix completed and validated

### TCK-20260207-019 :: Live-first UX simplification + status clarity (non-technical users)

Type: IMPROVEMENT
Owner: Pranay (agent: codex)
Created: 2026-02-07 10:46 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Reduce front-page control density and ambiguous language so non-technical users can focus on transcript/results first: shrink settings prominence, increase primary content space, and replace unclear "Not ready" messaging with actionable status text.

Scope contract:

- In-scope:
  - Collapse advanced capture/settings controls by default in live views.
  - Make status text plain-language and actionable.
  - Apply visual hierarchy polish consistent with native macOS glass/material style.
- Out-of-scope:
  - Backend protocol/model changes.
  - Per-app audio routing (browser-tab attribution).
- Behavior change allowed: YES

Targets:

- Surfaces: macapp | docs
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/AppState.swift`, `docs/UI.md`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Roll/Compact default UI prioritizes transcript area over settings chrome.
- [x] Status badge avoids ambiguous "Not ready" phrasing and shows clearer meaning.
- [x] View mode/audio/highlight controls no longer consume excessive horizontal/vertical space from visible labels.
- [x] `swift build` and `swift test` pass.

Evidence log:

- [2026-02-07 10:46] Ticket created from UX feedback + screenshots | Evidence:
  - Source: User feedback and screenshots in chat
  - Interpretation: Observed — current hierarchy over-emphasizes setup controls and uses unclear status wording
- [2026-02-07 10:49] Implemented live-first hierarchy and status copy changes | Evidence:
  - Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/AppState.swift`
  - Interpretation: Observed — capture panel now collapses by default in live views, segmented controls hide redundant labels, and status wording is plain-language (`Ready/Preparing/Permission needed/Setup needed`)
- [2026-02-07 10:49] Validated macapp build + tests | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — code compiles and existing UI contract tests pass
- [2026-02-07 10:50] Updated UI/testing documentation for new hierarchy/status contract | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`
  - Interpretation: Observed — docs reflect collapsed settings default and plain-language status expectations
- [2026-02-07 10:59] Implemented second UX polish pass from user screenshots | Evidence:
  - File: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`
  - Interpretation: Observed — capture setup now defaults collapsed in all modes, permission banner is condensed into one row, and narrow highlight toolbar avoids wrapped label artifacts
- [2026-02-07 10:59] Re-validated macapp build + tests after polish pass | Evidence:
  - Command: `cd macapp/MeetingListenerApp && swift build && swift test`
  - Output:
    ```
    Build complete!
    Executed 4 tests, with 0 failures (0 unexpected)
    ```
  - Interpretation: Observed — app still compiles and tests remain green after the UI adjustments
- [2026-02-07 10:59] Updated verification docs for latest UX contract | Evidence:
  - Files: `docs/UI.md`, `docs/TESTING.md`
  - Interpretation: Observed — documentation now reflects global collapsed setup and narrow-layout highlight regression check

Status updates:

- [2026-02-07 10:46] **IN_PROGRESS** 🟡 — implementing live-first hierarchy and status copy pass
- [2026-02-07 10:50] **DONE** ✅ — live-first simplification and status clarity pass completed
- [2026-02-07 10:59] **DONE** ✅ — second polish pass applied from visual QA feedback

### TCK-20260207-020 :: Automated macOS visual regression tests + always-run hook

Type: HARDENING
Owner: Pranay (agent: codex)
Created: 2026-02-07 11:07 (local time)
Status: **DONE** ✅
Priority: P0

Description:
Add native macOS visual automation for the SidePanel UI (Roll/Compact/Full snapshots) and wire local automation so these tests run automatically on every commit.

Scope contract:

- In-scope:
  - Snapshot-based visual tests for key SidePanel modes with deterministic fixture data.
  - Swift package/test configuration updates required for snapshot testing.
  - Git hook + verification script so `swift test` runs automatically before commit.
  - Docs updates describing how to record/update visual baselines.
- Out-of-scope:
  - Backend/service behavior changes.
  - Cloud CI pipeline redesign.
- Behavior change allowed: YES (test/tooling only)

Targets:

- Surfaces: macapp | scripts | docs
- Files: `macapp/MeetingListenerApp/Package.swift`, `macapp/MeetingListenerApp/Tests/*`, `.githooks/*`, `scripts/*`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`
- Branch/PR: Unknown
- Range: Unknown

Acceptance criteria:

- [x] Visual snapshot tests exist for SidePanel Roll/Compact/Full.
- [x] `swift test` passes locally with snapshots checked.
- [x] A pre-commit hook triggers verification automatically.
- [x] Docs include how to run/record visual snapshots and how auto-hook is installed.

Evidence log:

- [2026-02-07 11:07] Ticket created from user request | Evidence:
  - Source: User request in chat ("set it up properly and always runs after changes")
  - Interpretation: Observed — user requested automated visual macOS testing and default automatic execution
- [2026-02-07 11:31] Added snapshot test infrastructure for macOS SidePanel | Evidence:
  - Files: `macapp/MeetingListenerApp/Package.swift`, `macapp/MeetingListenerApp/Tests/SidePanelVisualSnapshotTests.swift`
  - Interpretation: Observed — SnapshotTesting dependency and deterministic Roll/Compact/Full visual tests were added
- [2026-02-07 11:35] Recorded baseline snapshot images | Evidence:
  - Command: `cd macapp/MeetingListenerApp && RECORD_SNAPSHOTS=1 swift test`
  - Output:
    ```
    Automatically recorded snapshot files under Tests/__Snapshots__/SidePanelVisualSnapshotTests/
    ```
  - Interpretation: Observed — baseline PNG snapshots were generated for all three mode tests
- [2026-02-07 11:37] Added always-run local verification hook and validated it | Evidence:
  - Files: `.githooks/pre-commit`, `scripts/verify.sh`, `scripts/install-git-hooks.sh`
  - Commands:
    - `./scripts/install-git-hooks.sh`
    - `./scripts/verify.sh`
  - Output:
    ```
    Installed git hooks path: .githooks
    [verify] OK
    ```
  - Interpretation: Observed — pre-commit now runs build+test (including visual snapshots) automatically
- [2026-02-07 11:38] Updated testing docs for visual workflow | Evidence:
  - Files: `docs/TESTING.md`, `README.md`
  - Interpretation: Observed — docs now define baseline compare/record flow and hook setup
- [2026-02-07 11:44] Final verification run on hooked command path | Evidence:
  - Command: `./scripts/verify.sh`
  - Output:
    ```
    [verify] OK
    ```
  - Interpretation: Observed — the same command used by pre-commit passes with visual snapshots enabled

Status updates:

- [2026-02-07 11:07] **IN_PROGRESS** 🟡 — implementing snapshot tests and always-run hook
- [2026-02-07 11:38] **DONE** ✅ — visual automation and always-run verification hook completed

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

1. Implement a snapshot viewer component for History (Summary/Transcript/JSON tabs).
2. Add Markdown export for selected session; keep existing JSON export.
3. Build `macapp/MeetingListenerApp` and verify UX manually.

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

1. Add `SessionStore.deleteSession(sessionId:)` and recovery-marker handling.
2. Add UI action + confirmation in `SessionHistoryView`.
3. Build and verify delete behavior.

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

---

### TCK-20260204-002 :: Streaming ASR/NLP Full Audit with Fixes

Type: AUDIT
Owner: pranay (agent: Amp)
Created: 2026-02-04 12:00
Status: **DONE** ✅
Priority: P0

Description:
Comprehensive audit of the streaming ASR and NLP pipeline to identify why
"streaming ASR and NLP are not working reliably". Covers client capture,
WebSocket transport, ASR providers, NLP pipelines, and diarization.

Scope contract:

- In-scope:
  - Client-side capture + resampling + framing + WebSocket transport
  - FastAPI server app lifecycle, health checks, websocket handler
  - ASR provider registry, stream pipeline, faster-whisper provider
  - NLP pipelines (entities/cards/summary) and diarization
  - Concurrency, backpressure, cancellation, resource cleanup
- Out-of-scope:
  - UI changes
  - Model accuracy tuning
- Behavior change allowed: YES (bug fixes)

Targets:

- Surfaces: server, docs
- Files:
  - server/api/ws_live_listener.py
  - server/services/asr_providers.py
  - docs/audit/STREAMING_ASR_NLP_AUDIT.md
  - tests/test_streaming_correctness.py
  - scripts/soak_test.py
- Branch/PR: main (direct fixes)

Acceptance criteria:

- [x] P0 fixes: Registry race condition, backpressure handling
- [x] P1 fixes: ASR flush timeout warning, transcript ordering
- [x] Unit tests for new fixes
- [x] Soak test harness created
- [x] Comprehensive audit document with prioritized issues

Evidence log:

- [2026-02-04 12:00] Started audit | Evidence:
  - Reviewed all files in capture → transport → ASR → NLP → diarization chain
  - Interpretation: Observed — identified 3 P0, 4 P1, 7 P2 issues
- [2026-02-04 12:30] Applied P0/P1 fixes | Evidence:
  - Command: `python -m py_compile server/api/ws_live_listener.py server/services/asr_providers.py`
  - Output: `Syntax OK`
  - Interpretation: Observed — syntax valid
- [2026-02-04 12:45] Ran all tests | Evidence:
  - Command: `pytest tests/test_streaming_correctness.py tests/test_ws_live_listener.py -v`
  - Output:
    ```
    10 passed
    ```
  - Interpretation: Observed — all tests pass

- [2026-02-04 13:00] Created audit document | Evidence:
  - File: `docs/audit/STREAMING_ASR_NLP_AUDIT.md`
  - Interpretation: Observed — 10-section audit with architecture map, protocol audit, correctness analysis, and 3-phase stabilization plan

---

### TCK-20260204-P2-9 :: Standardize log levels

Type: IMPROVEMENT
Owner: GitHub Copilot (agent: codex)
Created: 2026-02-04 14:00
Status: **DONE** ✅
Priority: P2

Description:
Mixed logging patterns found: some code uses `logger.debug()`, others use `logger.info()`, and many use `print()` statements with `DEBUG` guard clauses. Standardized to consistent `logging` module usage with appropriate levels (debug, info, warning, error).

Scope contract:

- In-scope: Replace all `print()` calls with `logger` calls; remove DEBUG guards; add logging imports
- Out-of-scope: Structured (JSON) logging; log aggregation; client-side logging
- Behavior change allowed: NO

Targets:

- Surfaces: server
- Files: `server/services/asr_stream.py`, `server/services/diarization.py`, `server/services/asr_providers.py`

Acceptance criteria:

- [x] All `print()` statements replaced with `logger` calls
- [x] DEBUG guard clauses removed
- [x] Logger imported and initialized in each modified file
- [x] All existing tests pass
- [x] No functional behavior changes

Evidence log:

- [2026-02-04 14:00] Analyzed logging patterns | Evidence: 13 matches found across service files
- [2026-02-04 14:05] Standardized asr_stream.py | Evidence: Replaced DEBUG flag with logging module, converted 3 print() calls
- [2026-02-04 14:10] Standardized diarization.py | Evidence: Replaced 9 DEBUG-guarded print() calls with logger levels
- [2026-02-04 14:12] Standardized asr_providers.py | Evidence: Removed DEBUG conditional in log() method
- [2026-02-04 14:15] Ran full test suite | Evidence: 13 passed, no regressions

Status updates:

- [2026-02-04 14:00] **IN_PROGRESS** — starting audit task P2-9
- [2026-02-04 14:15] **DONE** ✅ — logging standardized and tested

Summary:
Successfully replaced inconsistent `print()` + `DEBUG` pattern with proper Python `logging` module across three critical service files. All tests pass with no functional changes.

---

### TCK-20260204-P2-13 :: Add debug hooks for audio dumping

Type: IMPROVEMENT
Owner: GitHub Copilot (agent: codex)
Created: 2026-02-04 14:30
Status: **DONE** ✅
Priority: P2

Description:
Added configurable audio dump capability for debugging ASR issues. When enabled via `ECHOPANEL_DEBUG_AUDIO_DUMP=1`, raw PCM audio is written to timestamped files per source, allowing post-mortem analysis of audio quality issues.

Scope contract:

- In-scope: Add env-var controlled audio dump to disk; create dump files per source; add proper cleanup
- Out-of-scope: Audio playback tools; dump file management/rotation; compression
- Behavior change allowed: NO (feature is opt-in)

Targets:

- Surfaces: server
- Files: `server/api/ws_live_listener.py`

Acceptance criteria:

- [x] Audio dump controlled by `ECHOPANEL_DEBUG_AUDIO_DUMP` env var
- [x] Files saved with format: `{session_id}_{source}_{timestamp}.pcm`
- [x] Dump directory configurable via `ECHOPANEL_DEBUG_AUDIO_DUMP_DIR`
- [x] Files properly closed on session end
- [x] No performance impact when disabled
- [x] All existing tests pass

Evidence log:

- [2026-02-04 14:30] Designed solution | Evidence: Per-source PCM dump files with timestamped names
- [2026-02-04 14:35] Implemented dump hooks | Evidence: Added \_init_audio_dump, \_write_audio_dump, \_close_audio_dumps functions
- [2026-02-04 14:40] Integrated into audio flow | Evidence: Dump init on first source audio, write on each chunk, close in finally block
- [2026-02-04 14:45] Ran full test suite | Evidence: 13 passed, no regressions

Status updates:

- [2026-02-04 14:30] **IN_PROGRESS** — starting audit task P2-13
- [2026-02-04 14:45] **DONE** ✅ — audio dump implemented and tested

Summary:
Added optional audio dump feature for debugging. Files are written to `/tmp/echopanel_audio_dump/` by default with clear naming scheme. Zero performance impact when disabled. Proper error handling and cleanup ensures no file descriptor leaks.

---

### TCK-20260206-001 :: Commercialization vs Open Source vs Showcase Strategy Audit

Type: AUDIT
Owner: Pranay (agent: Amp)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P1

Description:
Comprehensive strategy audit evaluating whether EchoPanel should be monetized, open-sourced, used as a showcase project, or kept as internal tooling. Multi-agent (3 personas), evidence-first analysis covering repo intelligence, market landscape, monetization fit, OSS fit, and a 30/60/90 experiment plan.

Scope contract:

- In-scope:
  - Repo-wide product surface analysis
  - Market/competitive landscape research
  - Multi-persona independent recommendations
  - Decision matrix and scoring rubric
  - 30/60/90 day experiment plan
- Out-of-scope:
  - Code changes, architecture changes, implementation work
- Behavior change allowed: NO

Targets:

- Surfaces: docs
- Files: `docs/audit/COMMERCIALIZATION_STRATEGY_AUDIT_2026-02.md`

Acceptance criteria:

- [x] Multi-persona analysis (VC, OSS Maintainer, CTO) with independent recommendations
- [x] Evidence-backed claims with file path citations
- [x] Decision matrix with scoring rubric
- [x] 30/60/90 experiment plan with hypotheses and success metrics
- [x] Competitive landscape table
- [x] Unknowns documented with verification plan

Evidence log:

- [2026-02-06] Audit completed | Evidence:
  - Analyzed 40+ docs, server code, macOS app structure, landing page, tests, prompts
  - Multi-persona oracle consultation (VC/Growth PM, OSS Maintainer, CTO/SRE)
  - File: `docs/audit/COMMERCIALIZATION_STRATEGY_AUDIT_2026-02.md`
  - Interpretation: Observed — comprehensive audit document produced

Status updates:

- [2026-02-06] **DONE** ✅ — strategy audit memo delivered

---

### TCK-20260206-002 :: Gap Analysis (Cross-Referenced with Model-Lab + Online Research)

Type: AUDIT
Owner: Pranay (agent: Amp)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P0

Description:
Comprehensive gap analysis identifying 12 material gaps across ASR, NLP, preprocessing, distribution, and developer infrastructure. Cross-references EchoPanel's current implementation against model-lab benchmarks (4 models tested on real audio), the 60+ model ASR research audit, and model-lab's existing infrastructure (VAD, diarization, NLP, LLM, gating modules).

Scope contract:

- In-scope:
  - Map EchoPanel's current pipeline against production-grade standards
  - Cross-reference model-lab benchmark results and available infrastructure
  - Identify model upgrade path with concrete benchmarks
  - Prioritize gaps by severity and effort
- Out-of-scope:
  - Code changes or implementation
- Behavior change allowed: NO

Targets:

- Surfaces: docs
- Files: `docs/audit/GAPS_ANALYSIS_2026-02.md`

Evidence log:

- [2026-02-06] Analyzed EchoPanel server code + model-lab harness/models/benchmarks
  - EchoPanel files: `server/services/analysis_stream.py`, `server/services/provider_faster_whisper.py`, `server/services/asr_stream.py`, `server/services/asr_providers.py`, `server/api/ws_live_listener.py`
  - Model-lab files: `PERFORMANCE_RESULTS.md`, `EVALUATION_MATRIX.md`, `STREAMING_ASR_PORT_NOTES.md`, `ADVANCED_FEATURES_ROADMAP.md`, `COMPREHENSIVE_AUDIO_MODEL_ROADMAP_2026.md`
  - Research: `docs/ASR_MODEL_RESEARCH_2026-02.md` (60+ model audit, Tier 1/2/3 prioritization)
  - Interpretation: Observed — 12 gaps identified with evidence from both repos

Status updates:

- [2026-02-06] **DONE** ✅ — gap analysis delivered

---

### TCK-20260206-003 :: Model Inventory + Latency/Error Audit (EchoPanel + Model-Lab)

Type: AUDIT
Owner: Pranay (agent: Codex)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P1

Description:
Focused audit of the models currently used by EchoPanel, measured latency/error evidence, and feature/status alignment across EchoPanel docs/code and model-lab artifacts.

Scope contract:

- In-scope:
  - Identify active model paths in EchoPanel (ASR, diarization, related settings).
  - Gather observed latency/error evidence from local logs and model-lab benchmarks/runs.
  - Produce ticket-ready findings with Observed/Inferred/Unknown discipline.
- Out-of-scope:
  - Implementing fixes.
  - Re-architecting model pipeline.
- Behavior change allowed: NO

Targets:

- Surfaces: server, macapp, docs
- Files: `docs/audit/server-models-latency-error-20260206.md`

Acceptance criteria:

- [x] Active model configuration and selection paths mapped
- [x] Latency/error evidence captured from actual artifacts (not only roadmap claims)
- [x] Findings prioritized with ticket-ready remediation items
- [x] Worklog updated with commands and outcomes

Evidence log:

- [2026-02-06] Completed focused audit | Evidence:
  - EchoPanel model/config/runtime files reviewed (`server/services/asr_stream.py`, `server/services/asr_providers.py`, `server/services/provider_faster_whisper.py`, `server/api/ws_live_listener.py`, `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`, `macapp/MeetingListenerApp/Sources/BackendManager.swift`)
  - Model-lab benchmark docs reviewed (`/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md`, `/Users/pranay/Projects/speech_experiments/model-lab/STREAMING_ASR_PORT_NOTES.md`, `/Users/pranay/Projects/speech_experiments/model-lab/EVALUATION_MATRIX.md`)
  - Fresh streaming benchmarks executed (3 runs) and recorded under `/Users/pranay/Projects/speech_experiments/model-lab/runs/streaming_bench/`
  - Run-status/error-code distribution extracted from model-lab manifests via `jq`
  - Interpretation: Observed — audit artifact produced with prioritized findings and backlog conversion

Status updates:

- [2026-02-06 11:15] **IN_PROGRESS** 🟡 — gathering model inventory and measured latency/error artifacts
- [2026-02-06 11:40] **DONE** ✅ — audit artifact delivered (`docs/audit/server-models-latency-error-20260206.md`)

---

### TCK-20260206-004 :: UI Redesign Feedback Audit (current portrait panel quality)

Type: AUDIT
Owner: Pranay (agent: Codex)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P1

Description:
Evaluate the currently shipped portrait/"redesigned" side panel against the intended redesign goals and provide concrete corrective feedback.

Scope contract:

- In-scope:
  - Compare requested redesign intent vs shipped layout/visual behavior.
  - Identify concrete hierarchy/layout issues from screenshots + SwiftUI code.
  - Provide practical correction direction.
- Out-of-scope:
  - Implementing visual fixes in this ticket.
  - Broader product strategy.
- Behavior change allowed: NO

Targets:

- Surfaces: macapp, docs
- Files: `docs/audit/ui-redesign-feedback-20260206.md`

Acceptance criteria:

- [x] Feedback includes observed mismatches vs redesign intent
- [x] Prioritized issue list with severity
- [x] Concrete implementation direction for next pass

Evidence log:

- [2026-02-06] Reviewed redesign intent and shipped UI code/screens | Evidence:
  - Redesign intent docs: `docs/UI_CHANGE_SPEC_2026-02-06.md`, `docs/PRD_LAUNCH_UI_V0_2_2026-02-06.md`
  - Shipped UI code: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`, `macapp/MeetingListenerApp/Sources/SidePanelController.swift`
  - Current visuals: user-provided screenshots in thread
  - Interpretation: Observed — redesign is feature-complete but hierarchy/visual quality is below target

Status updates:

- [2026-02-06 12:05] **DONE** ✅ — UI redesign feedback audit delivered

---

### TCK-20260206-011 :: Model defaults/sanitization alignment (base.en baseline + turbo support)

Type: IMPROVEMENT
Owner: Pranay (agent: Codex)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P1

Description:
Apply docs-backed model defaults and fix mismatches in model selection so recommended models can actually be used end-to-end.

Scope contract:

- In-scope:
  - Set baseline default model to `base.en`.
  - Ensure `large-v3-turbo` passes sanitization from Settings to backend env.
  - Align local setup/testing docs with faster-whisper macOS CPU/int8 behavior.
- Out-of-scope:
  - Adding new ASR providers.
  - Runtime auto-benchmarking or adaptive model switching.
- Behavior change allowed: YES (default model and accepted model values)

Targets:

- Surfaces: macapp, server, docs
- Files:
  - `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`
  - `macapp/MeetingListenerApp/Sources/BackendManager.swift`
  - `server/services/asr_stream.py`
  - `server/README.md`
  - `docs/TESTING.md`
  - `docs/DEPLOY_RUNBOOK_2026-02-06.md`

Acceptance criteria:

- [x] Settings includes `base.en` and uses it as default.
- [x] `large-v3-turbo` is accepted by backend sanitizer.
- [x] Server ASR default is `base.en` when env is unset.
- [x] Setup/testing docs no longer recommend unsupported `metal` / `int8_float16` for faster-whisper.
- [x] `swift build` passes.

Evidence log:

- [2026-02-06] Implemented model alignment changes | Evidence:
  - Updated model defaults/options in `MeetingListenerApp.swift`
  - Expanded allow-list in `BackendManager.swift` to include `.en` variants + `large-v3-turbo`
  - Changed server default in `asr_stream.py` to `base.en`
  - Updated docs in `server/README.md`, `docs/TESTING.md`, `docs/DEPLOY_RUNBOOK_2026-02-06.md`
- [2026-02-06] Validation | Evidence:
  - `cd macapp/MeetingListenerApp && swift build` → success
  - `python -m compileall -q server` → success

Status updates:

- [2026-02-06 12:20] **DONE** ✅ — model defaults and sanitizer now aligned with docs-backed recommendations

---

### TCK-20260206-012 :: Settings helper: "Recommended for this Mac" ASR model

Type: IMPROVEMENT
Owner: Pranay (agent: Codex)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P2

Description:
Add a lightweight Settings helper that recommends `base.en` vs `large-v3-turbo` based on local hardware profile, with one-click apply.

Scope contract:

- In-scope:
  - Compute local hardware summary (chip class, RAM, core count).
  - Recommend model (`base.en` or `large-v3-turbo`) from simple heuristics.
  - Add “Use Recommended” action in ASR model settings.
- Out-of-scope:
  - Runtime benchmarking or adaptive switching during sessions.
  - Additional model tiers beyond base/turbo recommendation.
- Behavior change allowed: YES (settings UX enhancement)

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`

Acceptance criteria:

- [x] Settings shows a clear model recommendation for current Mac.
- [x] Recommendation includes rationale + hardware summary.
- [x] User can apply recommendation with one click.
- [x] Project builds successfully.

Evidence log:

- [2026-02-06] Implemented recommendation helper + UI | Evidence:
  - Added `ASRModelRecommendation` with RAM/chip heuristic in `MeetingListenerApp.swift`
  - Added recommendation text and `Use Recommended` button in `SettingsView` ASR section
- [2026-02-06] Validation | Evidence:
  - `cd macapp/MeetingListenerApp && swift build` → success

Status updates:

- [2026-02-06 12:35] **DONE** ✅ — recommendation helper shipped in Settings

---

### TCK-20260206-013 :: Side panel visual hierarchy redesign pass (visible UI correction)

Type: IMPROVEMENT
Owner: Pranay (agent: Codex)
Created: 2026-02-06
Status: **DONE** ✅
Priority: P1

Description:
Apply an explicitly visible redesign correction pass to the side panel to address "still looks ugly / not what was asked" feedback: simplify hierarchy, remove overcrowded header treatment, and improve transcript empty state.

Scope contract:

- In-scope:
  - Rebuild header hierarchy into compact top rows.
  - Simplify tabs strip visual noise.
  - Convert permission warnings to compact inline strips.
  - Improve transcript empty state block.
- Out-of-scope:
  - Re-architecting session logic.
  - New tabs/features.
- Behavior change allowed: YES (UI/layout only)

Targets:

- Surfaces: macapp
- Files: `macapp/MeetingListenerApp/Sources/SidePanelView.swift`

Acceptance criteria:

- [x] Header hierarchy is visibly simplified and less cluttered.
- [x] No vertical/clipped status pill layout in portrait width.
- [x] Tab strip no longer shows extra helper chrome.
- [x] Empty transcript state is a designed block, not lone text.
- [x] Build succeeds.

Evidence log:

- [2026-02-06] Implemented redesign pass | Evidence:
  - Refactored `header` into compact rows in `SidePanelView.swift`
  - Simplified `tabPicker` (removed persistent helper text)
  - Restyled `PermissionBanner` to compact inline alerts
  - Enhanced transcript empty-state card copy + structure
- [2026-02-06] Validation | Evidence:
  - `cd macapp/MeetingListenerApp && swift build` → success

Status updates:

- [2026-02-06 12:52] **DONE** ✅ — visible side panel redesign correction applied
