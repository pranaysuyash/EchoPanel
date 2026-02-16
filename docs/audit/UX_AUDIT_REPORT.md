# Mac Premium UX Audit: EchoPanel

## Update (2026-02-13)

This audit is a point-in-time critique (authored 2026-02-06). As of 2026-02-13, several items called out here have been addressed in the current app:

- Session History is no longer raw JSON only: it has Summary/Transcript/JSON tabs, search/filter, deletion with confirmation, and "Reveal in Finder". Evidence: `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift`, `macapp/MeetingListenerApp/Sources/SessionStore.swift`.
- Onboarding diarization token friction is no longer present as an onboarding step; HuggingFace token entry lives in Settings and is stored in Keychain (with legacy UserDefaults migration). Evidence: `macapp/MeetingListenerApp/Sources/OnboardingView.swift`, `macapp/MeetingListenerApp/Sources/SettingsView.swift`, `macapp/MeetingListenerApp/Sources/KeychainHelper.swift`.
- Side panel supports a narrow companion layout (Roll/Compact) rather than a single landscape-heavy window. Evidence: `macapp/MeetingListenerApp/Sources/SidePanel/`.
- Session terminology has been partially unified: the menu bar now uses "End Session" (instead of "Stop Listening") to match the side panel and communicate a finalization step. Evidence: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`.

Items still open from this report:

- Onboarding "first success" audio metering remains a real UX opportunity: the current permissions step includes a beep test, but does not show live audio levels. Evidence: `macapp/MeetingListenerApp/Sources/OnboardingView.swift`.
- Global hotkey behavior (Cmd+Shift+L when menu is closed) remains constrained by macOS global hotkey requirements; implementing it would require a separate approach (event tap / registered hotkey) and likely additional permissions.

## Executive Summary
This audit evaluates EchoPanel through two distinct lenses:
1.  **The Current Utility**: How well does it perform as a premium Mac recorder? (Scorecard & Issues UX-001 to UX-008)
2.  **The Companion Vision**: How close is it to the "Sidebar Intelligence" pivot? (Persona Gaps & Issues UX-009 to UX-011)

**Key Finding**: While the app excels at window persistence and privacy (Score 4/5), it fails the "Companion" test due to rigid landscape window sizing ("Window Juggling") and lack of integrated query tools ("Context Switching").

---

## A) SCORECARD

| Metric | Score | Rationale |
| :--- | :---: | :--- |
| **Control** | **5/5** | Excellent window management forms the backbone of a great utility. Floating panel behavior, "Join All Spaces" logic, and robust persistence (auto-save, recovery) give users complete confidence. |
| **Trust** | **4/5** | "Privacy first" is backed by local processing architecture. Permission banners are clear and redundant. The only ding is the raw handling of backend errors (exposing Python logs). |
| **Speed-feel** | **4/5** | Native SwiftUI ensures instant launch and window toggling. Transitions in the card lane are smooth. |
| **Clarity** | **3/5** | Terminology inconsistency ("Stop Listening" vs "End Session") causes friction. The distinction between "System" and "Mic" sources is technical rather than outcome-based ("Meeting" vs "Voice"). |
| **Craft** | **3/5** | "Ive" details are missing: Onboarding tests output instead of input (fake confidence), layout alignment risks in the source picker, and the Diarization setup is developer-hostile. |

---

## B) TOP 10 FIXES

1.  **[First Success] Implement Real Audio Metering in Onboarding**
    *   **Context**: Currently, "Test Audio" just plays a system beep (`NSSound.beep()`).
    *   **Fix**: Replace the beep button with the existing `AudioLevelMeter` component connected to `AudioCaptureManager`. The user must *see* the bar bounce when they speak to trust the setup.

2.  **[Clarity] Unify Session Terminology**
    *   **Context**: The Menu Bar says "Stop Listening" (implies pause), while the Side Panel says "End Session" (implies finish & save).
    *   **Fix**: Rename all instances to "End Session" to clearly communicate that a summary will be generated. Use "Pause" if temporary suspension is intended.

3.  **[Flow] Remove Diarization Token Friction**
    *   **Context**: Asking for a HuggingFace User Access Token during onboarding is a massive churn risk.
    *   **Fix**: Move this to a "Pro Settings" tab. Default to "Speaker A/B" or source-based labels (Mic = You, System = Others) without the token, then upsell the token entry for "Named Speakers".

4.  **[Control] Fix Global Keyboard Shortcut Expectations**
    *   **Context**: Modifiers like `.keyboardShortcut` on `MenuBarExtra` items only work when the menu is open.
    *   **Fix**: Implement `CGEvent` tap or `HotKey` library registration in `MeetingListenerApp` init to make `Cmd+Shift+L` work globally, even when the app is in the background.

5.  **[Craft] Thematize the Source Picker**
    *   **Context**: The 200px fixed-width `SegmentedPicker` in `SidePanelView` header risks truncating labels like "Microphone".
    *   **Fix**: Use a `Menu` (dropdown) with full labels, or an icon-only segmented control (Safe visual language) with tooltips.

6.  **[Trust] Humanize Backend Errors**
    *   **Context**: `BackendManager` exposes raw health details like "Python exit code 1".
    *   **Fix**: Map common exit codes to human directions (e.g., Code 1 often means specific port conflict -> "Port 8000 is taken. Try changing it in Settings.").

7.  **[Speed] Optimistic "Listening" State**
    *   **Context**: `toggleSession` waits for backend checks before updating UI, which can feel sluggish if the server is waking up.
    *   **Fix**: Switch UI to "Connecting..." state immediately upon click, then transition to "Listening".

8.  **[Clarity] Relocate "Recover Session"**
    *   **Context**: It's a top-level menu item, cluttering the primary flow.
    *   **Fix**: Move it into the "Session History" window or a "File" submenu. It's an edge case, not a daily driver.

9.  **[Craft] Empty State Polish**
    *   **Context**: "No actions yet" is plain text.
    *   **Fix**: Add subtle SF Symbol illustrations (e.g., a grayed-out checklist for Actions) to make empty states feel designed.

10. **[Control] Add "Discard" to Side Panel**
    *   **Context**: User can only "End Session" (Save). If a meeting was junk, they have to save it, go to history, and delete it.
    *   **Fix**: Add a "Cancel/Discard" option in the `SidePanelView` control strip for quick aborts.

---

## C) ISSUE LOG

**Issue: UX-001**
-   **Severity**: P0
-   **Category**: Trust
-   **Surface**: OnboardingView / Permissions
-   **Steps to reproduce**: 1. Launch App. 2. Go to "Test Audio". 3. Click button.
-   **Expected**: I see a visual meter moving when I speak, confirming the app hears me.
-   **Observed**: Computer plays a "Beep" sound (tests speakers, not mic).
-   **Recommendation**: Embed `AudioLevelMeter` in the permission step.
-   **Principle**: Jobs (First success moment).

**Issue: UX-002**
-   **Severity**: P1
-   **Category**: Clarity
-   **Surface**: SidePanelView / Header
-   **Steps to reproduce**: 1. Open Side Panel. 2. Look at Source Picker.
-   **Expected**: Full text is visible or icons are used.
-   **Observed**: Fixed `frame(width: 200)` might truncate "System Audio" or "Microphone" on default font sizes.
-   **Recommendation**: Use Icon-only segments (`waveform`, `mic`, `circle.grid.2x2`) or remove fixed width.
-   **Principle**: Ive (Alignment/Typography).

**Issue: UX-003**
-   **Severity**: P1
-   **Category**: Flow
-   **Surface**: OnboardingView / Diarization
-   **Steps to reproduce**: 1. Reach Step 4. 2. Prompted for HuggingFace Token.
-   **Expected**: "One click" or "Skip for now" is prominent.
-   **Observed**: Text field for a complex token sequence. Feels like a dev tool.
-   **Recommendation**: Demote to "Advanced Settings". Default to simpler identification.
-   **Principle**: Ive (Subtraction).

**Issue: UX-004**
-   **Severity**: P2
-   **Category**: Control
-   **Surface**: Global / Keyboard
-   **Steps to reproduce**: 1. Focus another app (e.g. Chrome). 2. Press `Cmd+Shift+L`.
-   **Expected**: EchoPanel toggles recording.
-   **Observed**: Nothing happens (Shortcuts bound to MenuBarExtra only work when menu is open/focused).
-   **Recommendation**: Register global hotkey monitor.
-   **Principle**: Speed-feel.

**Issue: UX-005**
-   **Severity**: P2
-   **Category**: Clarity
-   **Surface**: MeetingListenerApp / Menu
-   **Steps to reproduce**: 1. Open Menu. 2. See "Recover Last Session".
-   **Expected**: Menu is clean, focused on "Start/Stop".
-   **Observed**: Panic/Recovery option is given equal weight to primary actions.
-   **Recommendation**: Move to `File > Recover...` or inside `Session History`.
-   **Principle**: Ive (Hierarchy).

**Issue: UX-006**
-   **Severity**: P2
-   **Category**: Trust
-   **Surface**: SidePanelView / Header
-   **Steps to reproduce**: 1. Backend fails. 2. Error message appears.
-   **Expected**: "Connection failed. Retrying..."
-   **Observed**: Raw Python exit codes or stack trace snippets in `healthDetail`.
-   **Recommendation**: Map error strings to user-friendly messages in `BackendManager`.
-   **Principle**: Jobs (Trust).

**Issue: UX-007**
-   **Severity**: P3
-   **Category**: Craft
-   **Surface**: SidePanelView / Entities
-   **Steps to reproduce**: 1. Entity list populates. 2. Filter logic.
-   **Expected**: Selected state is obvious and delightful.
-   **Observed**: Standard blue system buttons.
-   **Recommendation**: Use a custom "pill" style with active background color that matches the entity type (Person=Purple, Org=Blue).
-   **Principle**: Ive (Color/Consistency).

**Issue: UX-008**
-   **Severity**: P3
-   **Category**: Clarity
-   **Surface**: SessionHistoryView
-   **Steps to reproduce**: 1. Open History. 2. Look at "Transcript" tab.
-   **Expected**: Rich text or similar visual fidelity to the live view.
-   **Observed**: `Text("- [00:00] ...")` monospaced markdown-style rendering.
-   **Recommendation**: Reuse `TranscriptRow` component for history viewing to maintain high fidelity.
-   **Principle**: Jobs (Consistency).

---

## D) PERSONA SCENARIO ANALYSIS

### 1. Sarah - The Busy Product Manager
**Goal:** Quick summary for Slack. "Set and forget."
*   **The Workflow:** Launch -> "Start Listening" -> Minimize -> Meeting ends -> Copy Summary.
*   **Friction Points:**
    *   **Diarization Wall:** She effectively can't use the "Who said what" feature because fetching a HuggingFace token is too technical. She skips it, rendering the transcript a wall of text ("System" vs "You").
    *   **Recovery Anxiety:** If she accidentally quits instead of "End Session", does she lose the summary? (Code shows `SessionStore` auto-save, but UI doesn't reassure her).

### 2. David - The Senior Engineer
**Goal:** Keyboard control, custom models, data ownership.
*   **The Workflow:** `Cmd+Shift+L` to toggle. Tweak `large-v3` model. Export JSON.
*   **Friction Points:**
    *   **Hotkey Failure (Critical):** The `Cmd+Shift+L` shortcut defined in `MeetingListenerApp.swift` is attached to a `MenuBarExtra` button. This means **it only works when the menu is actually open**. David expects global control.
    *   **Log Spam:** He sees `BackendManager` dumping raw Python logs. While transparent, it feels "beta".

### 3. Elena - The Privacy Advocate
**Goal:** strict local isolation.
*   **The Workflow:** Offline mode. Verify no unexpected connections. Delete data.
*   **Friction Points:**
    *   **Debug Logs:** `BackendManager` sets `EchoPanel_DEBUG=1` by default in the audited code (`BackendManager.swift:96`), which might dump sensitive transcript segments to `tmp/echopanel_server.log`. This acts as a potential privacy leak if not rotated/wiped.
    *   **Web Dependence:** The onboarding "Permissions" screen links out to System Settings, which is good suitable, but the Diarization screen pushes a web link, breaking the "contained" feeling.

---

## E) ADDITIONAL ISSUES (FROM PERSONAS)

**Issue: UX-009**
-   **Severity**: P1
-   **Category**: Control
-   **Surface**: App Lifecycle
-   **Steps to reproduce**: 1. Launch App. 2. Hide Menu Bar menu. 3. Press `Cmd+Shift+L`.
-   **Expected**: Recording toggles.
-   **Observed**: Nothing. Shortcut is scoped to the Menu view.
-   **Recommendation**: Implement `CGEvent.tap` or use `HotKey` library for global listening.
-   **Principle**: Speed-feel.

**Issue: UX-010**
-   **Severity**: P2
-   **Category**: Trust
-   **Surface**: BackendManager
-   **Steps to reproduce**: 1. Inspect `/tmp/echopanel_server.log`.
-   **Expected**: Only system status logs.
-   **Observed**: `ECHOPANEL_DEBUG=1` is hardcoded. Potential PII leak in plain text.
-   **Recommendation**: Set `DEBUG=0` for production builds, or redact PII from logs.
-   **Principle**: Jobs (Trust).

**Issue: UX-011**
-   **Severity**: P1
-   **Category**: Clarity / Process
-   **Surface**: Window Management
-   **Steps to reproduce**: 1. Join a Zoom call. 2. Open EchoPanel SidePanel. 3. Try to position both.
-   **Expected**: EchoPanel snaps to a slim 300px sidebar to act as a "Companion".
-   **Observed**: Minimum width is 920px (Landscape), obscuring the video call or forcing "Minimize" (which hides the transcript).
-   **Recommendation**: Implement a responsive "Portrait/Sidebar" mode with vertical stacking.
-   **Principle**: Jobs (Flow).
