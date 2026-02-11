# EchoPanel UI/UX Specification — Workspace Panel Commit

**Version:** 1.1-audit-integrated  
**Date:** 2026-02-11  
**Status:** Ready for implementation  
**Related:** `docs/apple-design-review-2026-02-11.md`, `docs/DESIGN_REVIEW_STRATEGIC_OPINION_2026-02-11.md`

---

## 1. Product Identity Statement

> EchoPanel is a **workspace panel companion** for meetings. The menu bar provides convenient launch and status; the panel is the primary workspace.

**Contract:** "I am part of your working context. I will hold state. I will reward time spent."

---

## 2. Window Architecture

### 2.1 Current State vs Target

| Aspect | Current State | Target State |
|--------|---------------|--------------|
| Side Panel | Programmatic `NSPanel` via SidePanelController | SwiftUI `Window` with restoration |
| View Modes | Roll/Compact/Full enum with different sizes | Single panel with 3 preset sizes |
| Settings | Native SwiftUI Settings (2 tabs: General, Broadcast) | Add Privacy tab, reorganize |
| Summary Window | Separate window (`summary` id) | Merge into History as tab |
| Onboarding | 5 steps, permissions at step 2 | 2 steps, defer permissions |

### 2.2 Primary Window: Companion Panel (Target)

```
┌─────────────────────────────────────────────────────────────┐
│  EchoPanel                              🔍 Search    ⚙️    │  ← Top toolbar
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────────────────┐  ┌───────────────┐ │
│  │                                    │  │ Highlights    │ │
│  │  TRANSCRIPT TIMELINE               │  │ • Decisions   │ │  ← Right sidebar
│  │                                    │  │ • Actions     │ │    (collapsible)
│  │  [09:14] A: So the deadline is...  │  │ • Entities    │ │
│  │  [09:17] B: We need to confirm...  │  │ • Pins        │ │
│  │  [09:21] A: I'll send the doc...   │  │               │ │
│  │      ↳ Pinned                      │  │ ───────────── │ │
│  │                                    │  │ Ask           │ │
│  │  [ Follows live, scroll to pause ] │  │               │ │
│  │                                    │  └───────────────┘ │
│  └────────────────────────────────────┘                    │
├─────────────────────────────────────────────────────────────┤
│  Live • 14m 32s  [Jump to Live] [Export] [End Session]     │  ← Bottom bar
└─────────────────────────────────────────────────────────────┘
```

**Window Characteristics:**
| Property | Value |
|----------|-------|
| Style | `.hiddenTitleBar` |
| Position | Right edge of screen (default) |
| Restoration | Yes — remembers size/position per display |
| Level | Floating but not frontmost-stealing |
| Min/Max | 360pt min width, 900pt max width |

### 2.3 Preset Sizes (Keyboard Addressable)

| Preset | Width | Use Case | Shortcut |
|--------|-------|----------|----------|
| Narrow | 380pt | Minimal distraction, live only | ⌘1 |
| Medium | 580pt | Default, balanced | ⌘2 |
| Wide | 780pt | Deep review, search active | ⌘3 |

**Current mapping to existing modes:**
- Narrow ≈ Current Compact (360pt)
- Medium ≈ Current Roll (460pt)
- Wide ≈ New unified width

### 2.4 Window Inventory

**Current Windows (to modify):**
| ID | Current | Change |
|----|---------|--------|
| `onboarding` | 5-step wizard | 2-step, defer permissions |
| `diagnostics` | 400×300 troubleshooting | Keep as-is |
| `summary` | 820×620 current session | **Remove** — merge into history |
| `history` | 980×620 archive | Add Summary tab |
| `demo` | 980×560 demo UI | Keep as-is |
| (none) | SidePanel via NSPanel | Add `companion-panel` Window |

**Settings:** Already exists as native SwiftUI Settings. Add Privacy tab.

---

## 3. View Hierarchy

### 3.1 Core View: Live Transcript (Roll-style)

**The default and hero view.**

- Receipt-style scrolling transcript
- Timestamp + speaker badge + text
- Confidence indicator (subtle, inline)
- Pinnable lines
- Click to focus, double-click for lens/details
- Drag to scroll (disables follow-live)

### 3.2 Sidebar: Highlights (Renamed from Surfaces)

**Current State:** `Surface` enum with values: `summary`, `actions`, `pins`, `entities`, `raw`

**Target Tabs:**
1. **Highlights** — Decisions, Actions, Risks (auto-extracted)
2. **Entities** — People, orgs, dates, terms (click to filter)
3. **Pins** — User-saved moments
4. **Ask** — RAG interface (future)

**Behavior:**
- Persistent above 560pt width
- Collapses to overlay drawer below 560pt
- Toggle button appears when collapsed

**Implementation note:** 560pt breakpoint already exists but is hardcoded in 2 places. Need to centralize.

### 3.3 Responsive Breakpoints (Add to DesignTokens)

```swift
enum Breakpoints {
    static let ultraNarrow: CGFloat = 380  // Minimal labels
    static let narrow: CGFloat = 560       // Stack layouts
    static let medium: CGFloat = 600       // Reposition controls
    static let wide: CGFloat = 1080        // Full horizontal
    static let ultraWide: CGFloat = 1240   // Three-column
}
```

**Current hardcoded values to replace:**
- `SidePanelLayoutViews.swift:11` (600 → .medium)
- `SidePanelLayoutViews.swift:86` (560 → .narrow)
- `SidePanelFullViews.swift:60` (560 → .narrow)
- `SidePanelTranscriptSurfaces.swift:210` (380 → .ultraNarrow)

---

## 4. Onboarding Flow

### 4.1 Current State

**5 steps:**
1. Welcome
2. Permissions (Screen Recording + Microphone)
3. Source Selection (System/Mic/Both)
4. Diarization (HF token)
5. Ready

**Permission timing:** Step 2 shows UI with "Open Settings" buttons. Actual OS permission check happens via `refreshPermissionStatuses()`.

### 4.2 Target State: 2-Step Flow

**Step 1: Welcome (Value Proposition)**
```
┌────────────────────────────────────────┐
│          [waveform.badge.mic]          │
│                                        │
│     Your meeting companion             │
│                                        │
│     ✓ Live transcript beside meetings  │
│     ✓ Pin key moments as they happen   │
│     ✓ Everything stays on your Mac     │
│                                        │
│          [    Get Started    ]         │
└────────────────────────────────────────┘
```

**Step 2: Permissions Preview (Explain, Don't Ask)**
```
┌────────────────────────────────────────┐
│     One more step                      │
│                                        │
│     EchoPanel needs access to meeting  │
│     audio. We'll ask when you start    │
│     your first session.                │
│                                        │
│     🖥️  Screen Recording (Required)    │
│     🎙️  Microphone (Optional)          │
│                                        │
│          [   Open EchoPanel   ]        │
└────────────────────────────────────────┘
```

**Key changes:**
- Remove source selection from onboarding (move to Settings or first-use prompt)
- Remove diarization from onboarding (move to Settings)
- No actual permission requests here
- Auto-open panel after completion for demo

---

## 5. Settings Window

### 5.1 Current State

**Existing:** Native SwiftUI `Settings` with 2 tabs:
- **General:** Audio source, ASR Model, Backend config, Server status
- **Broadcast:** Advanced broadcast features (redundant audio, hotkeys, confidence display)

**@AppStorage keys found:**
- `whisperModel`, `backendHost`, `backendPort`
- `onboardingCompleted`
- `sidePanel.viewMode`
- `broadcast_*` (various broadcast settings)

### 5.2 Target State: 5 Tabs

| Tab | Contents |
|-----|----------|
| **General** | Launch at login, Show panel on record, Default preset, Theme |
| **Audio** | Default source, ASR model, Backend host/port |
| **Privacy** | Storage meter, Retention policy, Permissions status, Delete/Export all |
| **Shortcuts** | Reference list (read-only for now) |
| **Advanced** | Backend restart, Logs directory, Diagnostics |

### 5.3 Privacy Dashboard Requirements

**Storage Section:**
- Visual meter showing used storage
- Session count
- "Export All Sessions" button
- "Delete All Sessions" button (destructive, confirmation)

**Retention Section:**
- Picker: 30 days / 90 days / 1 year / Never

**Permissions Section:**
- Screen Recording status (green/orange/red)
- Microphone status
- "Open System Settings" buttons if denied

**Bundle Privacy Section:**
- Explanation: "Debug bundles never include raw audio unless explicitly opted in"

---

## 6. Error & Status Patterns

### 6.1 Current State

**Error types defined:**
```swift
enum AppRuntimeErrorState {
    case backendNotReady(detail: String)
    case screenRecordingPermissionRequired
    case screenRecordingRequiresRelaunch
    case microphonePermissionRequired
    case systemCaptureFailed(detail: String)
    case microphoneCaptureFailed(detail: String)
    case streaming(detail: String)
}
```

**Existing UI:**
- `PermissionBanner` in SidePanel (red background, System Settings link)
- `noAudioBanner` (orange background, silence message)
- Backend error in Onboarding (red label with retry)
- Menu bar status indicators (server, stream)
- DiagnosticsView with system status grid

### 6.2 Target: Error Banner Component

**Standardized banner with 3 tones:**

```swift
enum ErrorBannerStyle {
    case warning(title: String, detail: String?, action: (label: String, handler: () -> Void)?)
    case error(title: String, detail: String?, action: (label: String, handler: () -> Void)?)
    case offline(title: String, retry: () -> Void)
}
```

**Placement:** Below toolbar, above content. Pushes content down (doesn't overlay).

---

## 7. Menu Bar Behavior

### 7.1 Current State

**Icon:** `waveform.circle` / `waveform.circle.fill` with green palette when listening

**Menu items:**
- Status (Listening/Idle)
- Timer
- Server status
- Start/Stop (⌘⇧L)
- Export options
- Recover/Discard Last Session
- Session Summary / History
- Show Onboarding / Demo
- Quit

**CommandMenu (⌘-accessible):**
- Start/Stop (⌘⇧L)
- Copy Markdown (⌘⇧C)
- Export JSON (⌘⇧E)
- Export Markdown (⌘⇧M)
- Diagnostics (⌘⇧D)
- Session Summary (⌘⇧S)
- Session History (⌘⇧H)

### 7.2 Target State

**Icon states (distinct):**
| State | Icon |
|-------|------|
| Idle | `waveform` (outline) |
| Listening | `waveform.circle.fill` (filled, subtle pulse) |
| Paused | `pause.circle` |
| Error | `waveform.circle.fill` with red badge |

**Menu changes:**
- Add "Open Panel" (⌘⇧O)
- Remove "Session Summary" (merged into History)
- Add "Settings..." (⌘,)

---

## 8. Keyboard Shortcuts

### 8.1 Current Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧L | Start/Stop |
| ⌘⇧C | Copy Markdown |
| ⌘⇧E | Export JSON |
| ⌘⇧M | Export Markdown |
| ⌘⇧D | Diagnostics |
| ⌘⇧S | Session Summary |
| ⌘⇧H | Session History |

### 8.2 Target Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘⇧L | Start/Stop | Global |
| ⌘⇧O | Open/Close panel | Global (NEW) |
| ⌘⇧H | Open History | Global |
| ⌘⇧C | Copy Markdown | Global |
| ⌘⇧E | Export JSON | Global |
| ⌘, | Open Settings | Global (NEW) |
| ↑ / ↓ | Move focus | Panel |
| Space | Toggle follow-live | Panel |
| P | Pin/unpin | Panel |
| Enter | Toggle lens | Panel |
| J | Jump to live | Panel |
| ? | Shortcuts overlay | Panel |
| ⌘1/⌘2/⌘3 | Narrow/Medium/Wide | Panel (NEW) |
| ⌘0 | Toggle sidebar | Panel (NEW) |
| Esc | Close overlay | Any |

---

## 9. Implementation Tasks

### Task A: Windowing & Settings (Day 1-2)
**Owner:** Agent A
**Files:**
- `MeetingListenerApp.swift` — Add companion-panel Window, update menu
- Create `SettingsView.swift` — Reorganize tabs
- Create `PrivacyDashboard.swift` — New component

**Deliverables:**
- [ ] Settings accessible via ⌘,
- [ ] Privacy tab with storage, retention, permissions
- [ ] 3 preset sizes (⌘1/⌘2/⌘3) in View menu

### Task B: Onboarding Simplification (Day 2-3)
**Owner:** Agent B
**Files:**
- `OnboardingView.swift` — Rewrite as 2-step
- `AppState.swift` — Add permission deferral logic
- `SidePanelController.swift` — Auto-open after onboarding

**Deliverables:**
- [ ] 2-step onboarding flow
- [ ] Permissions deferred until first recording
- [ ] Panel auto-opens after completion

### Task C: View Consolidation (Day 3-4)
**Owner:** Agent C
**Files:**
- `SidePanelView.swift` — Remove ViewMode enum
- `SidePanelRollViews.swift` — Make default
- `SummaryView.swift` — Remove or merge
- `SessionHistoryView.swift` — Add Summary tab
- All `SidePanel*.swift` — Rename "Surfaces" → "Highlights"

**Deliverables:**
- [ ] Roll is default (no mode picker)
- [ ] "Surfaces" renamed to "Highlights"
- [ ] Summary merged into History
- [ ] No regressions in transcript display

### Task D: Responsive Layout & Polish (Day 4-5)
**Owner:** Agent D
**Files:**
- `DesignTokens.swift` — Add Breakpoints enum
- `SidePanelLayoutViews.swift` — Use Breakpoints.narrow
- `SidePanelFullViews.swift` — Use Breakpoints
- `SidePanelChromeViews.swift` — Add sidebar toggle
- Create `ErrorBanner.swift` — New component
- Update menu bar icon states

**Deliverables:**
- [ ] Breakpoints centralized in DesignTokens
- [ ] Sidebar collapses below 560pt
- [ ] Error banner component
- [ ] Menu bar icon states (idle/listening/paused)

---

## 10. Acceptance Criteria

- [ ] Panel opens automatically on record start
- [ ] Panel restores size/position across app launches
- [ ] 3 preset sizes work with ⌘1/⌘2/⌘3
- [ ] Sidebar collapses below 560pt, toggle appears
- [ ] Onboarding is 2 steps, no early permission requests
- [ ] Settings window accessible via ⌘,
- [ ] Privacy dashboard shows storage, retention, permissions
- [ ] Menu bar icon shows distinct states
- [ ] Error banners appear inline, push content
- [ ] "Surfaces" renamed to "Highlights"
- [ ] Summary merged into History
- [ ] All keyboard shortcuts work
- [ ] Swift build passes, no regressions

---

## 11. Files Modified/Created Summary

### Modified:
- `MeetingListenerApp.swift` — Windows, menu, commands
- `OnboardingView.swift` — 2-step flow
- `SidePanelView.swift` — Remove ViewMode
- `SidePanelRollViews.swift` — Default view
- `SidePanelLayoutViews.swift` — Breakpoint usage
- `SidePanelFullViews.swift` — Breakpoint usage
- `SidePanelCompactViews.swift` — May remove
- `SidePanelTranscriptSurfaces.swift` — Rename Surfaces→Highlights
- `SessionHistoryView.swift` — Add Summary tab
- `DesignTokens.swift` — Add Breakpoints
- `SettingsView.swift` — Reorganize tabs

### Created:
- `PrivacyDashboard.swift`
- `ErrorBanner.swift`
- `WindowPlacementController.swift`

### Potentially Removed:
- `SummaryView.swift` (functionality merged)

---

*Spec Version: 1.1-audit-integrated*  
*Ready for parallel implementation*
