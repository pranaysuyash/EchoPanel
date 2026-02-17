> **⚠️ OBSOLETE (2026-02-16):** Mac premium UX audit findings largely addressed:
> - Menu bar app: proper macOS citizen with menu bar presence
> - Keyboard shortcuts: `HotKeyManager.swift`, `KeyboardCheatsheetView.swift`
> - Onboarding: step indicators, permission flows
> - Design tokens: `DesignTokens.swift` with semantic colors
> Remaining: Test Audio plays beep only (no live input meter) — minor enhancement. Moved to archive.

# Mac Premium UX Audit — EchoPanel

**Date:** 2026-02-04
**Auditor:** GitHub Copilot (agent: codex)
**Scope:** Onboarding → Main Side Panel → Core Meeting Workflows (Start/Stop, Transcript, Cards, Entities)

---

## Update (2026-02-13)

This audit is a point-in-time document from 2026-02-04. As of 2026-02-13, several issues called out below are now implemented (or the underlying UI architecture has changed substantially):

- Onboarding now shows explicit step labeling ("Step X of Y") in addition to progress dots. Evidence: `macapp/MeetingListenerApp/Sources/OnboardingView.swift`.
- Server error UX includes actionable CTAs (Retry, Collect Diagnostics) and backend readiness feedback during onboarding. Evidence: `macapp/MeetingListenerApp/Sources/OnboardingView.swift` (ready step).
- Diarization token is no longer an onboarding step; HuggingFace token entry lives in Settings and is stored in Keychain (with legacy migration). Evidence: `macapp/MeetingListenerApp/Sources/SettingsView.swift`, `macapp/MeetingListenerApp/Sources/KeychainHelper.swift`.
- Side panel UI is no longer a single monolithic view; it is split across `macapp/MeetingListenerApp/Sources/SidePanel/*` and includes multiple sizes/modes (Roll/Compact/Full). Evidence: `macapp/MeetingListenerApp/Sources/SidePanel/`.
- Session stop terminology has been partially unified to "End Session" (menu bar + side panel). Evidence: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`, `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelTranscriptSurfaces.swift`.

Remaining UX opportunity from this audit:

- Onboarding "Test Audio" is still a beep-only check (speaker output), not a live input meter. Evidence: `macapp/MeetingListenerApp/Sources/OnboardingView.swift`.

## Executive Summary

This UX audit evaluates EchoPanel from the perspective of a paying macOS user seeking a premium experience. It applies two lenses: "Ive mode" (minimal, pixel-perfect craft) and "Jobs mode" (end-to-end clarity, trust, user control).

Result: The app delivers a strong foundation (clear onboarding, solid transcription UX), but several medium-impact UX issues (permissions remediation, first-success feedback, server error recovery) reduce perceived polish and trust. See Top 10 Fixes and Issue Log for concrete, testable changes.

---

## Scorecard (1–5)
- Clarity: 4
- Craft: 3
- Speed-feel: 4
- Control: 3
- Trust: 3

---

## Top 10 Fixes (Short)
1. Make the first success moment explicit (toast + sample transcript + waveform). (Jobs)
2. Add explicit step labels to onboarding progress (Step 2 of 5). (Ive)
3. Permission remediation: add Retry + guided steps. (Jobs)
4. Keyboard & focus polish across onboarding and side panel. (Jobs)
5. Server error UX: add Retry / Collect Diagnostics CTAs. (Jobs)
6. Improve Test Audio to show visual pass/fail + sample playback. (Ive)
7. Collapse lanes on small widths and provide lane-switch shortcuts. (Jobs)
8. Hide verbose debug text unless user enables Debug mode; add discoverable toggle. (Ive)
9. Diarization token UX: explain usage, privacy, and add clear/validate. (Jobs)
10. Normalize copy & microcopy (Start Listening vs Streaming vs Listening). (Ive)

Each recommendation above is precise and testable (see Issue Log entries for reproduction steps and file pointers).

---

## Issue Log (selected, 20 items)

Note: Each issue includes: id, severity, category, surface, steps_to_reproduce, expected, observed, evidence placeholder, recommendation, principle.

<!-- UX-001 -->
Issue:
- id: UX-001
- severity: P1
- category: Trust
- surface: Onboarding → readyStep
- steps_to_reproduce:
  1. Complete onboarding
  2. Click "Start Listening"
- expected: Immediate visual confirmation (toast + sample transcript + waveform) within 3s
- observed: App shows spinner or status without clear first-success feedback
- evidence: screenshots/ux/UX-001-first-success.png
- recommendation: Add a transient toast + small waveform widget with a sample transcript line and a dismiss action
- principle: Jobs (first-success)

<!-- UX-002 -->
Issue:
- id: UX-002
- severity: P2
- category: Clarity
- surface: Onboarding progress indicator
- steps_to_reproduce:
  1. Open onboarding and look at progress dots
- expected: Show "Step X of Y" and a label (e.g., "Permissions")
- observed: Only dots shown; unclear remaining steps
- evidence: screenshots/ux/UX-002-onboarding-progress.png
- recommendation: Replace or augment dots with "Step 2 of 5 — Permissions" and concise subtitle
- principle: Ive (typography/clarity)

<!-- UX-003 -->
Issue:
- id: UX-003
- severity: P1
- category: Control
- surface: PermissionRow
- steps_to_reproduce:
  1. Deny screen recording permission
  2. Open System Settings and return to app
- expected: App shows "Retry" button or automatic recheck and on-screen guidance for exactly what to enable
- observed: Button opens system settings but no in-app retry or persistent guidance
- evidence: screenshots/ux/UX-003-permission.png
- recommendation: Add "Retry" and inline steps checklist (exact toggles to flip in System Settings) and detect changes on return
- principle: Jobs (control)

<!-- UX-004 -->
Issue:
- id: UX-004
- severity: P2
- category: Craft
- surface: Onboarding Test Audio
- steps_to_reproduce: Click "Test Audio (Play Beep)"
- expected: Visual feedback (level meter) and pass/fail indicator
- observed: Only a beep (NSSound.beep), no visual confirmation
- evidence: screenshots/ux/UX-004-audio-test.png
- recommendation: Provide visual meter + “Passed / Failed” state with option to play recorded sample
- principle: Ive (motion/feedback)

<!-- UX-005 -->
Issue:
- id: UX-005
- severity: P2
- category: Trust
- surface: Diarization token field
- steps_to_reproduce: Read the diarization token explanation
- expected: Clear privacy explanation and storage policy + clear/remove button
- observed: Text mentions token but lacks privacy/storage explanation
- evidence: screenshots/ux/UX-005-diarization-token.png
- recommendation: Add short copy: "Stored locally in Keychain, used only for diarization; you can remove it anytime." and a Validate button
- principle: Jobs (trust/control)

<!-- UX-006 -->
Issue:
- id: UX-006
- severity: P2
- category: Speed-feel
- surface: Transcript auto-scroll
- steps_to_reproduce:
  1. Turn Follow off
  2. Let new text arrive
  3. Toggle Follow on
- expected: Smooth, interruptible scroll with micro-animation cue
- observed: Scroll happens but can feel jumpy on long transcripts
- evidence: clips/ux/UX-006-scroll.mp4
- recommendation: Throttle updates and use consistent ease (.easeOut, 0.2s), add subtle pulse on new content
- principle: Ive (motion/quality)

<!-- UX-007 -->
Issue:
- id: UX-007
- severity: P1
- category: Control
- surface: Keyboard navigation/shortcuts
- steps_to_reproduce:
  1. Tab through onboarding and main panel
  2. Use keyboard shortcuts listed (e.g., ⌘C, ⌘⇧E)
- expected: All actions focusable and discoverable, and a “Shortcuts” help overlay is present
- observed: Some actions available but no discoverable help overlay and some elements lack focus visuals
- evidence: screenshots/ux/UX-007-shortcuts.png
- recommendation: Add a Shortcuts overlay (⌘/?) and ensure focus ring on all interactive elements
- principle: Jobs (control)

<!-- UX-008 -->
Issue:
- id: UX-008
- severity: P2
- category: Clarity
- surface: Status pills (header)
- steps_to_reproduce: Hover or inspect status pills
- expected: Tooltip with definitions and link to diagnostics
- observed: No tooltip or inline explanation
- evidence: screenshots/ux/UX-008-status-pill.png
- recommendation: Add hover tooltips and an inline “?” that opens a one-line explanation modal
- principle: Jobs (clarity)

<!-- UX-009 -->
Issue:
- id: UX-009
- severity: P2
- category: Craft
- surface: LaneCard styles
- steps_to_reproduce: Inspect Cards/Entities lanes visually
- expected: Consistent headline weight/spacing/rounded corners across lanes
- observed: Minor inconsistencies in padding and font weight
- evidence: screenshots/ux/UX-009-lanes.png
- recommendation: Normalize card styles in a single card component and test at multiple sizes
- principle: Ive (typography/alignment)

<!-- UX-010 -->
Issue:
- id: UX-010
- severity: P1
- category: Trust
- surface: Server error presentation
- steps_to_reproduce: Simulate back-end failure (stop python server) and open app
- expected: CTA buttons: Retry Server, Collect Diagnostics, Contact Support
- observed: Only an error banner with static text
- evidence: screenshots/ux/UX-010-server-error.png
- recommendation: Add Retry and Collect Diagnostics (zipped logs) and show a short explanation
- principle: Jobs (trust/control)

<!-- Remaining issues (11–20) -->

<!-- UX-011 -->
Issue:
- id: UX-011
- severity: P3
- category: Jobs
- surface: Export buttons (SidePanel controls)
- steps_to_reproduce:
  1. End a short session or have content
  2. Click "Export JSON" or "Export Markdown"
- expected: Small toast/notification shows success and a link/button to reveal file in Finder; filename includes session ID and timestamp
- observed: Export appears to run (no blocking), but there is no clear success feedback or reveal-in-Finder affordance
- evidence: screenshots/ux/UX-011-export-toast.png
- recommendation: Add a transient toast with filename and a “Show in Finder” button; include an undo button if overwrite risk exists
- principle: Jobs (control/clarity)

<!-- UX-012 -->
Issue:
- id: UX-012
- severity: P2
- category: Ive
- surface: EntityDetailPopover
- steps_to_reproduce:
  1. Click an entity in Entities lane
  2. With the popover open, attempt keyboard navigation (↑/↓) and toggle filter
- expected: Keyboard bindings (up/down to navigate mentions, Enter to toggle filter) and visible focus states
- observed: Popover buttons are clickable but lack keyboard bindings and consistent focus outlines
- evidence: screenshots/ux/UX-012-entity-popover.png
- recommendation: Add keyboard handlers for navigation and ensure controls have accessible focus rings; add ARIA-style labels for accessibility
- principle: Ive (interaction/keyboard)

<!-- UX-013 -->
Issue:
- id: UX-013
- severity: P2
- category: Jobs
- surface: TranscriptRow (low-confidence segments)
- steps_to_reproduce:
  1. Trigger a low-confidence ASR segment (simulate or adjust test fixture)
  2. Attempt to mark it as verified
- expected: A lightweight 'Mark as verified' action is available inline, with a short reason tooltip
- observed: Only "Needs review" chip is visible; no quick verify action
- evidence: screenshots/ux/UX-013-low-confidence.png
- recommendation: Add an inline inline '✓ Verify' button and a tooltip showing why confidence is low (e.g., audio quality)
- principle: Jobs (control)

<!-- UX-014 -->
Issue:
- id: UX-014
- severity: P2
- category: Jobs
- surface: Onboarding window close behavior
- steps_to_reproduce:
  1. Close the onboarding window mid-step
  2. Re-open the app
- expected: App offers to resume the onboarding where left off or shows how to restart the flow
- observed: Onboarding closes and state may be lost; user not guided to resume
- evidence: screenshots/ux/UX-014-onboarding-close.png
- recommendation: Persist partial onboarding state (UserDefaults) and prompt to resume or restart when onboarding is opened again
- principle: Jobs (end-to-end clarity)

<!-- UX-015 -->
Issue:
- id: UX-015
- severity: P3
- category: Ive
- surface: SourceOptionRow selected state and accent color contrast
- steps_to_reproduce:
  1. Select an audio source (system/microphone/both)
  2. Inspect selected tile labels in Light and Dark modes
- expected: Selected state meets WCAG contrast for text and icons; consistent spacing and padding
- observed: Selected background tint is subtle and some small text may be low-contrast on certain themes
- evidence: screenshots/ux/UX-015-contrast.png
- recommendation: Use a slightly stronger selected background and ensure body text contrasts at >=4.5:1; test in Dark Mode
- principle: Ive (typography/contrast)

<!-- UX-016 -->
Issue:
- id: UX-016
- severity: P2
- category: Trust
- surface: Diarization HF token storage
- steps_to_reproduce:
  1. Enter a HuggingFace token in Onboarding diarization step
  2. Inspect storage (NSUserDefaults used)
- expected: Token stored securely in Keychain and a 'Remove token' control is present
- observed: Token is saved to UserDefaults with no visible clear button or explanation of storage
- evidence: screenshots/ux/UX-016-hf-token.png
- recommendation: Move token to Keychain, add 'Clear token' button, and show a one-line privacy note
- principle: Jobs (trust/control)

<!-- UX-017 -->
Issue:
- id: UX-017
- severity: P2
- category: Speed-feel
- surface: Scroll/animation behavior on transcript updates
- steps_to_reproduce:
  1. Send rapid transcript updates (simulate many small segments)
  2. Toggle Follow on/off rapidly
- expected: Animations are interruptible and debounce to avoid stutter; UX feels smooth
- observed: Animations stutter under high update frequency
- evidence: clips/ux/UX-017-debounce.mp4
- recommendation: Debounce auto-scroll and use non-blocking animations (short duration, low cost), cancel in-flight scrolls on user input
- principle: Ive (motion/performance)

<!-- UX-018 -->
Issue:
- id: UX-018
- severity: P3
- category: Clarity
- surface: Empty states (Cards/Entities lanes)
- steps_to_reproduce:
  1. Start app with no session content
  2. Inspect Cards and Entities lanes
- expected: Actionable CTAs (e.g., "Start a session to see actions" with keyboard hint) and brief guidance
- observed: Passive messages like "No actions yet"
- evidence: screenshots/ux/UX-018-empty.png
- recommendation: Replace passive copy with actionable suggestions and keyboard shortcuts (e.g., Press ⌘L to start listening)
- principle: Jobs (clarity)

<!-- UX-019 -->
Issue:
- id: UX-019
- severity: P2
- category: Control
- surface: Session finalization UI
- steps_to_reproduce:
  1. End a long session
  2. Observe finalization (server processing/transcripts consolidation)
- expected: A progress indicator with estimated time and 'Cancel processing' option for urgent situations
- observed: Spinner with "Finalizing Session..." and no ETA or cancel action
- evidence: screenshots/ux/UX-019-finalizing.png
- recommendation: Show progress % or step count and allow 'Cancel finalization' with clear note about consequences
- principle: Jobs (control/trust)

<!-- UX-020 -->
Issue:
- id: UX-020
- severity: P3
- category: Craft
- surface: UI assets and Retina polish
- steps_to_reproduce:
  1. Run on Retina and non-Retina screens
  2. Inspect all custom assets (icons, images)
- expected: All custom assets provided at @2x/@3x and look crisp at multiple scale factors
- observed: SF Symbols used appropriately, but custom assets need audit for @2x/@3x
- evidence: screenshots/ux/UX-020-retina.png
- recommendation: Audit custom assets and supply high-resolution equivalents; verify in Dark/Light modes
- principle: Ive (craft/retina)


---

## Evidence to collect (screenshots & clips)
- screenshots/ux/UX-001-first-success.png
- screenshots/ux/UX-002-onboarding-progress.png
- screenshots/ux/UX-003-permission.png
- screenshots/ux/UX-004-audio-test.png
- screenshots/ux/UX-005-diarization-token.png
- clips/ux/UX-006-scroll.mp4
- screenshots/ux/UX-007-shortcuts.png
- screenshots/ux/UX-010-server-error.png
- additional screenshots for empty states, popovers, and export flows.

---

## Next steps
1. Add UX worklog ticket and attach this audit file. (done)
2. Manually capture the listed screenshots and clips (15–30 minutes).
3. Create small, prioritized PRs for P1 issues: first-success toast, permission retry, server error CTAs, keyboard focus polish.
4. Follow-up: run quick usability test with 3 users (5–10 min each) and collect feedback.

---

*Audit saved: docs/audit/UX_MAC_PREMIUM_AUDIT_2026-02.md*
