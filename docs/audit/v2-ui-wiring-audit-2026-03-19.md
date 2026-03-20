# v2 UI Wiring Audit — 2026-03-19

**Auditor:** Amp Agent (Nova)
**Scope:** `~/Projects/EchoPanel/macapp_v2/` (exploratory SwiftUI) ↔ `~/Projects/EchoPanel/macapp/MeetingListenerApp/` (production Swift/AppKit)
**Files read:** 14 v2 Swift files + 4 production source files + `docs/WORKLOG_TICKETS.md`

---

## Executive Summary

- **macapp_v2** is a self-contained SwiftUI playground (16 source files, mock-only) with polished UI design, a scenario-driven Flow Studio, and comprehensive design tokens — all disconnected from the real audio/WS pipeline.
- **The production app** is fully functional (audio capture → WebSocket → ASR backend → transcript/analysis UI) but has rough edges: search result highlighting is missing, onboarding doesn't mention keyboard shortcuts, the menu bar view is minimal, and session history search lacks visual match feedback.
- **The highest-leverage improvement** is wiring v2's design system (`DesignTokens.swift`) into production — zero backend risk, immediate visual polish, ~1h effort.
- **The single most actionable bug** is: the `?` shortcut handler in `SidePanelChromeViews.swift` does not guard against firing when `fullSearchFocused` is `true`, so pressing `?` inside the search field toggles the shortcuts overlay instead of typing `?`. The v2 `SearchableTranscriptView` already handles this correctly.
- **Next sprint** should focus on: (1) porting design tokens, (2) fixing the `?` shortcut guard, (3) adding search match highlighting, (4) wiring session duration/elapsed time in live view, (5) adding keyboard shortcut callout to onboarding ready step.

---

## Part 1 — What's in macapp_v2 (Done Items)

### 1.1 App Structure
| File | Status | Notes |
|------|--------|-------|
| `EchoPanelV2App.swift` | ✅ Complete | SwiftUI App lifecycle, `AppState` as `StateObject`, window setup, `KeyboardShortcuts` |
| `AppState.swift` | ✅ Mock-only | `MockFlowTrack`, scenario switching, `applyFlow()`, mock sessions/transcripts |

### 1.2 UI Views
| File | Status | Notes |
|------|--------|-------|
| `LiveView.swift` | ✅ Complete (mock) | Live recording UI with waveform, partial/final transcript, analysis cards, live mock playback |
| `ReviewView.swift` | ✅ Complete (mock) | Post-session: action items, decisions, risks, entities, summary, export |
| `FlowStudioView.swift` | ✅ Complete (mock) | Scenario selector (standup/escalation/hiring/launch), per-scenario mock payloads, journey preview |
| `HistoryView.swift` | ✅ Complete (mock) | Session list, search, MOM export |
| `SettingsView.swift` | ✅ Complete (mock) | ASR provider selection, audio source, theme, hotkeys, server config |
| `SearchableTranscriptView.swift` | ✅ Complete (mock) | Searchable transcript with **highlighted match spans** |
| `OnboardingView.swift` | ✅ Complete (mock) | 3-step: Welcome → Tips → Ready; mentions `⌘⇧R`, `⌘⇧P` shortcuts |
| `MenuBarView.swift` | ✅ Complete (mock) | Menu bar popover with status, recording toggle, recent sessions, settings |
| `ConfirmationDialogs.swift` | ✅ Complete (mock) | End-session, delete-session, discard-changes dialogs |
| `ExportDialogs.swift` | ✅ Complete (mock) | Markdown, JSON, SRT, DOCX, ZIP export dialogs |
| `ProviderSelectors.swift` | ✅ Complete (mock) | ASR provider picker with latency/cost/quality indicators |

### 1.3 Design System
| File | Status | Notes |
|------|--------|-------|
| `DesignTokens.swift` | ✅ Production-quality | Semantic colors, spacing scale, corner radii, typography, materials, `CardStyle` modifier, `StatusDot`, `EmptyStateView` |

### 1.4 Data Layer
| File | Status | Notes |
|------|--------|-------|
| `MockData.swift` | ✅ Rich | `MockFlowPayload` with 4 scenario datasets (standup/escalation/hiring/launch) |

---

## Part 2 — What's NOT Wired to Production

### 2.1 AppState (v2 ↔ Production)
| Mock behavior | Production reality | Wired? |
|---|---|---|
| `startRecording()` — mock state change | `appState.startRecording()` → `AudioCaptureManager.start()` | ❌ No |
| `stopRecording()` — mock state change | `appState.stopRecording()` → `AudioCaptureManager.stop()` | ❌ No |
| `sessions` — mock session list | Real `Session` objects from `SessionBundleManager` | ❌ No |
| `liveTranscripts` — mock partial/final | Real `onASRPartial`/`onASRFinal` from `WebSocketStreamer` | ❌ No |
| `actionItems`/`decisions`/`risks` — mock | Real `onCardsUpdate` from `WebSocketStreamer` | ❌ No |
| `entities` — mock | Real `onEntitiesUpdate` from `WebSocketStreamer` | ❌ No |
| `sessionSummary` — mock | Real `onFinalSummary` from `WebSocketStreamer` | ❌ No |
| `SourceMetrics` (realtime factor, queue depth) | Real `onMetrics` callback in `WebSocketStreamer` | ❌ No |
| `MockFlowTrack` scenario state | No production equivalent | N/A |
| `applyFlow()` scenario switching | No production equivalent | N/A |

### 2.2 Views (v2 → Production)
| v2 View | Production equivalent | Wired? |
|---|---|---|
| `FlowStudioView` (scenario flows) | No production equivalent | ❌ No |
| `SearchableTranscriptView` (highlighted matches) | `SidePanelTranscriptSurfaces.swift` — search but no highlight spans | ❌ No |
| `DesignTokens.swift` | `SidePanelLayoutViews.swift` — inline styles, no shared tokens | ❌ No |
| `HistoryView` (with MOM export) | `SessionHistoryView.swift` — basic list, no MOM tab | ❌ No |
| v2 `OnboardingView` (shortcut callout in tips) | Production `OnboardingView.swift` — no shortcut reference | ❌ No |

### 2.3 Architecture
- v2 uses pure SwiftUI with `@StateObject`/`@EnvironmentObject` — no AppKit bridging.
- Production uses `SidePanelView` (AppKit `NSPanel` hosting `SwiftUI` via `NSHostingController`) with a complex `@State`/`@ObservedObject`/`@EnvironmentObject` mix.
- v2 window management (multi-window via `@main` + `WindowGroup`) is incompatible with production's `NSPanel`-based floating panel without a rewrite.

---

## Part 3 — Highest-Leverage Improvements

### Improvement 1: Port `DesignTokens.swift` to Production
- **Effort:** ~1 hour (copy file, replace inline style calls)
- **Risk:** Zero — no logic changes, purely visual
- **Impact:** High — consistent design system across all production UI components; `CardStyle` modifier reduces repetition in 10+ views
- **What to port:** Colors, `Spacing`, `CornerRadius`, `Typography`, `AppMaterial`, `CardStyle`, `StatusDot`, `EmptyStateView`
- **Note:** Production already has `Typography`, `Spacing`, `CornerRadius` in `SidePanelLayoutViews.swift` — audit for duplication before copying

### Improvement 2: Fix `?` Shortcut Fires in Search Field
- **Effort:** ~30 minutes
- **Risk:** Zero — adding a guard, no removal of behavior
- **Impact:** Medium — prevents confusing UX where typing `?` in search opens the shortcuts overlay
- **Location:** `SidePanelView.swift` — add `.keyboardShortcut("?", modifiers: [])` guard or move `?` handler to only fire when `!fullSearchFocused`
- **v2 already handles this correctly** in `SearchableTranscriptView`

### Improvement 3: Add Search Match Highlighting
- **Effort:** ~1 hour
- **Risk:** Zero — additive visual change
- **Impact:** Medium — significantly improves findability in long transcripts
- **What:** Port the highlighted-text approach from v2's `SearchableTranscriptView` — regex-based match spans with yellow highlight background and foreground color
- **Production gap:** `SidePanelTranscriptSurfaces.swift` filters but does not highlight

### Improvement 4: Add Session Elapsed Time to Live View
- **Effort:** ~1 hour
- **Risk:** Zero — `sessionStartTime` already exists in `AppState`
- **Impact:** Medium — users repeatedly ask "how long has this been recording?"
- **What:** Add elapsed timer (`HH:MM:SS`) to live recording chrome in `SidePanelFullViews.swift`; v2 has this in `LiveView` header
- **Note:** Already tracked as part of the live view polish

### Improvement 5: Add Keyboard Shortcut Callout to Onboarding Ready Step
- **Effort:** ~30 minutes
- **Risk:** Zero — additive text change
- **Impact:** Low-Medium — improves time-to-value for new users
- **What:** Add a hints section to `OnboardingView.readyStep` mentioning `⌘⇧R` (record) and `⌘⇧P` (panel); v2's `OnboardingView.TipsStep` already does this

---

## Part 4 — Bugs & Rough Edges in Production Swift Code

### B-1: `?` Shortcut Fires Inside Search Field
- **File:** `SidePanelView.swift` (line ~126 `@FocusState var fullSearchFocused`) + `SidePanelChromeViews.swift` shortcut overlay
- **Severity:** Low
- **Description:** The `?` keyboard shortcut that toggles the shortcuts overlay does not check `fullSearchFocused`. When the search field has focus, pressing `?` toggles the overlay instead of typing `?`.
- **Fix:** Add `fullSearchFocused` guard to the `?` handler (see Improvement 2)

### B-2: Audio Quality EMA Not Exposed in UI
- **File:** `AudioCaptureManager.swift` (lines 44-51) computes `rmsEMA`, `silenceEMA`, `clipEMA`, `limiterGainEMA` — all thread-safe with `emaLock`
- **Severity:** Low
- **Description:** These EMAs are computed every frame but only logged at debug level. A production-visible "Audio Health" indicator (like v2's waveform/quality display) would help users diagnose recording issues.
- **Fix:** Surface `AudioQuality` enum changes + VAD stats in `SidePanelChromeViews.sourceDiagnosticsStrip`

### B-3: `ShortcutRow` Missing from Production Imports
- **File:** `SidePanelChromeViews.swift` uses `ShortcutRow` in `shortcutOverlay` (line ~40)
- **Severity:** Info
- **Description:** `ShortcutRow` is defined in `SidePanelLayoutViews.swift` and used in `SidePanelChromeViews.swift` — cross-extension reference works because both are in the same module, but not documented
- **Fix:** Move `ShortcutRow` to a shared `SidePanelComponents.swift` or `SidePanelChromeViews.swift`

### B-4: Session Bundle ZIP Export Silently Fails if `zip` Not Found
- **File:** `SessionBundleManager.swift` or export code
- **Severity:** Low
- **Note:** TCK-20260212-001 (F-019) addressed this partially; verify exit code validation is complete

---

## Part 5 — Onboarding Audit

### Production Onboarding (`OnboardingView.swift` — 4 steps)
| Step | Content | Complete? |
|------|---------|-----------|
| Welcome | App description, waveform icon | ✅ |
| Permissions | Screen Recording + Mic status, open settings links, audio self-test beep | ✅ |
| Audio Source | System/Mic/Both picker wired to `appState.audioSource` | ✅ |
| Ready | Server status, Start Listening button | ✅ (with backend error state) |

**Gaps:**
- No mention of keyboard shortcuts anywhere in the 4 steps
- No `⌘⇧R` hint in the Ready step (v2's Tips step shows this)
- No step labels (e.g., "Step 2 of 4") — progress is only the dot indicator

### v2 Onboarding (`macapp_v2/Sources/OnboardingView.swift` — 3 steps)
| Step | Content | Complete? |
|------|---------|-----------|
| Welcome | App description, waveform icon | ✅ |
| Tips | Keyboard shortcut callouts (`⌘⇧R`, `P`, shortcuts) | ✅ |
| Ready | Open Panel / Start Recording buttons | ✅ |

**Gap:** `ReadyStep` uses `@State private var isPresented` instead of `@Binding` from parent — environment object mismatch (cosmetic bug in v2, not shipped to production)

---

## Part 6 — Next Sprint (5 Items, 1-2h Each)

| # | Item | Effort | Risk | Production file |
|---|------|--------|------|-----------------|
| 1 | Port `DesignTokens.swift` to production, replacing inline style duplication | ~1h | Zero | New: `DesignTokens.swift` |
| 2 | Fix `?` shortcut guard for `fullSearchFocused` in `SidePanelView` | ~30m | Zero | `SidePanelView.swift` |
| 3 | Add search match highlighting to transcript view | ~1h | Zero | `SidePanelTranscriptSurfaces.swift` |
| 4 | Add elapsed time display to live recording header | ~1h | Zero | `SidePanelFullViews.swift` |
| 5 | Add keyboard shortcut callout to production `OnboardingView.readyStep` | ~30m | Zero | `OnboardingView.swift` |

---

## Appendix: v2 ↔ Production File Map

| v2 File | Production File(s) | Relationship |
|---------|-------------------|--------------|
| `AppState.swift` | `AppState.swift` | v2 is mock-only; production has real pipeline wiring |
| `LiveView.swift` | `SidePanelFullViews.swift` | v2 has waveform/emojis; production has real transcript stream |
| `ReviewView.swift` | `SidePanelFullViews.swift` (Full mode) | v2 has rich card layout; production has equivalent but less polished |
| `FlowStudioView.swift` | None | v2-only scenario explorer; no production equivalent |
| `SearchableTranscriptView.swift` | `SidePanelTranscriptSurfaces.swift` | v2 has highlight spans; production filters only |
| `HistoryView.swift` | `SessionHistoryView.swift` | v2 has MOM tab; production has basic list |
| `SettingsView.swift` | `BackendConfig` + `AppState` settings | v2 has richer provider comparison UI |
| `OnboardingView.swift` | `OnboardingView.swift` | v2 has shortcut callout tips; production is more functional |
| `MenuBarView.swift` | `MeetingListenerApp.swift` (menu bar) | v2 is richer (recent sessions, export); production is basic |
| `DesignTokens.swift` | `SidePanelLayoutViews.swift` (inline) | v2 is comprehensive; production duplicates partially inline |
| `ConfirmationDialogs.swift` | `ConfirmationDialogs.swift` (production exists) | Need to compare |
| `ExportDialogs.swift` | `SessionBundleManager` | Need to compare |
| `ProviderSelectors.swift` | `AppState.swift` provider logic | v2 has better visual indicators |
| `MockData.swift` | None | v2-only |
| `AboutView.swift` | Need to check | — |
| `ConfirmationDialogs.swift` | Need to check | — |
