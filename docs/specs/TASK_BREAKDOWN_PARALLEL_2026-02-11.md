# EchoPanel Workspace Panel Implementation — Task Breakdown

**Date:** 2026-02-11  
**Parent Ticket:** TCK-20260211-004  
**Approach:** 4 parallel workstreams

---

## Task Assignment Overview

| Task | Owner | Focus | Est. Time | Dependencies |
|------|-------|-------|-----------|--------------|
| A | Agent A | Windowing & Settings | 4-6 hrs | None |
| B | Agent B | Onboarding | 3-4 hrs | None |
| C | Agent C | View Consolidation | 5-7 hrs | None |
| D | Agent D | Responsive & Polish | 4-6 hrs | Task C (for Highlights rename) |

**Integration order:** A, B, C can merge independently → D merges last (touches many files)

---

## Task A: Windowing & Settings

### Scope
Create Settings window with Privacy dashboard, add companion-panel Window, implement preset sizes.

### Files to Modify
1. `MeetingListenerApp.swift` (lines 1-585)
   - Add companion-panel Window declaration
   - Update CommandMenu with new shortcuts
   - Update MenuBarExtra menu
2. Create `SettingsView.swift` (new file)
3. Create `PrivacyDashboard.swift` (new file)
4. Create `WindowPlacementController.swift` (new file)

### Implementation Details

#### A1: Add companion-panel Window (MeetingListenerApp.swift)
```swift
Window("EchoPanel", id: "companion-panel") {
    CompanionPanelView(appState: appState)
        .frame(minWidth: 360, idealWidth: 580, maxWidth: 900)
        .frame(minHeight: 400)
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.defaultPosition(.trailing)
.restorationBehavior(.allowed)
```

#### A2: Update Commands (MeetingListenerApp.swift)
Add to CommandMenu:
```swift
Button("Open Panel") { appState.openCompanionPanel() }
    .keyboardShortcut("o", modifiers: [.command, .shift])

Divider()

Button("Narrow") { appState.resizePanel(to: 380) }
    .keyboardShortcut("1", modifiers: .command)
Button("Medium") { appState.resizePanel(to: 580) }
    .keyboardShortcut("2", modifiers: .command)
Button("Wide") { appState.resizePanel(to: 780) }
    .keyboardShortcut("3", modifiers: .command)

Divider()

Toggle("Show Sidebar", isOn: $appState.showSidebar)
    .keyboardShortcut("0", modifiers: .command)
```

#### A3: SettingsView.swift (5 tabs)
```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "waveform") }
            PrivacyDashboard()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 600, height: 480)
    }
}
```

#### A4: PrivacyDashboard.swift
Key sections:
- Storage meter (use AppState.storageUsed, sessionCount)
- Retention picker (30/90/365/0 days)
- Permission status rows (Screen Recording, Microphone)
- Export All / Delete All buttons

#### A5: WindowPlacementController.swift
```swift
class WindowPlacementController: ObservableObject {
    @AppStorage("panel.lastFrame") private var savedFrame: String?
    @AppStorage("panel.displayID") private var savedDisplayID: String?
    @AppStorage("panel.preset") var defaultPreset: Preset = .medium
    
    enum Preset: String, CaseIterable {
        case narrow = "narrow"   // 380
        case medium = "medium"   // 580
        case wide = "wide"       // 780
        
        var width: CGFloat {
            switch self {
            case .narrow: return 380
            case .medium: return 580
            case .wide: return 780
            }
        }
    }
    
    func placementStrategy() -> WindowPlacement { ... }
    func saveCurrentFrame(_ frame: NSRect, displayID: String) { ... }
}
```

### Acceptance Criteria
- [ ] Settings opens with ⌘,
- [ ] Privacy tab shows storage meter, retention picker, permissions
- [ ] 3 preset sizes work (⌘1/⌘2/⌘3)
- [ ] Panel position restores across launches
- [ ] Swift build passes

### Files Delivered
- Modified: `MeetingListenerApp.swift`
- Created: `SettingsView.swift`, `PrivacyDashboard.swift`, `WindowPlacementController.swift`

---

## Task B: Onboarding Simplification

### Scope
Rewrite onboarding from 5 steps to 2, defer permissions until first recording.

### Files to Modify
1. `OnboardingView.swift` (476 lines → ~150 lines)
2. `AppState.swift` — Add permission deferral logic
3. `SidePanelController.swift` — Auto-open after onboarding

### Implementation Details

#### B1: OnboardingView.swift
Replace 5-step enum with 2-step:
```swift
enum OnboardingStep {
    case welcome
    case permissionsPreview
}
```

**Step 1 (Welcome):**
- Large icon: `waveform.badge.mic`
- Title: "Your meeting companion"
- 3 benefit bullets with checkmarks
- "Get Started" button

**Step 2 (Permissions Preview):**
- Title: "One more step"
- Explanatory text: "We'll ask when you start your first session"
- Two rows: Screen Recording (Required), Microphone (Optional)
- NO actual permission requests here
- "Open EchoPanel" button

#### B2: AppState.swift Changes
Add:
```swift
@Published var hasDeferredPermissions = false

func startSession() {
    // Check if permissions need to be requested
    if !hasRequestedPermissions {
        requestPermissionsIfNeeded()
        hasDeferredPermissions = true
    }
    // ... existing start logic
}

private func requestPermissionsIfNeeded() {
    // Only request at first use, not during onboarding
    if screenRecordingPermission == .notDetermined {
        // Request screen recording
    }
}
```

#### B3: Auto-open Panel
In onboarding completion:
```swift
.onboardingCompleted = true
appState.openCompanionPanel()
// Maybe start a demo recording or show sample transcript?
```

### Acceptance Criteria
- [ ] Onboarding is exactly 2 steps
- [ ] No permission requests during onboarding
- [ ] Permissions requested on first recording attempt
- [ ] Panel auto-opens after onboarding
- [ ] Swift build passes

### Files Delivered
- Modified: `OnboardingView.swift`, `AppState.swift`, `SidePanelController.swift`

---

## Task C: View Consolidation

### Scope
Remove ViewMode enum, make Roll default, rename Surfaces→Highlights, merge Summary into History.

### Files to Modify
1. `SidePanelView.swift` — Remove ViewMode
2. `SidePanelRollViews.swift` — Keep as default
3. `SidePanelCompactViews.swift` — May remove
4. `SidePanelFullViews.swift` — May remove or repurpose
5. `SidePanelTranscriptSurfaces.swift` — Rename Surfaces→Highlights
6. `SummaryView.swift` — Merge functionality
7. `SessionHistoryView.swift` — Add Summary tab

### Implementation Details

#### C1: SidePanelView.swift Changes
Remove:
```swift
// REMOVE this enum:
enum ViewMode: String, CaseIterable, Identifiable {
    case roll = "Roll"
    case compact = "Compact"
    case full = "Full"
}
```

Keep but simplify:
- `@State var viewMode` → remove or repurpose as just layout density
- Content routing: always use rollRenderer

#### C2: Rename Surfaces→Highlights
In `SidePanelTranscriptSurfaces.swift`:
- Rename `Surface` enum → `HighlightTab` or just use strings
- Update all references in:
  - `SidePanelView.swift`
  - `SidePanelChromeViews.swift`
  - `SidePanelFullViews.swift`

Search and replace: `surface` → `highlight`, `Surface` → `Highlight`

#### C3: Merge Summary into History
**Option 1:** Add Summary tab to History
```swift
// SessionHistoryView.swift
enum Tab: String, CaseIterable {
    case summary = "Summary"      // NEW
    case transcript = "Transcript"
    case json = "JSON"
}

// In summary tab, show the same content as current SummaryView
```

**Option 2:** Remove Summary window entirely, History is the only post-session UI

Remove from:
- `MeetingListenerApp.swift` (Window declaration)
- CommandMenu (⌘⇧S shortcut)
- MenuBarExtra menu

### Acceptance Criteria
- [ ] Roll is the only/default view mode
- [ ] "Surfaces" renamed to "Highlights" in all UI strings
- [ ] Summary window removed or merged
- [ ] History has Summary tab
- [ ] No ViewMode picker in UI
- [ ] Swift build passes

### Files Delivered
- Modified: `SidePanelView.swift`, `SidePanelTranscriptSurfaces.swift`, `SessionHistoryView.swift`
- Modified/Removed: `SidePanelCompactViews.swift`, `SidePanelFullViews.swift`, `SummaryView.swift`

---

## Task D: Responsive Layout & Polish

### Scope
Centralize breakpoints, implement sidebar collapse, create ErrorBanner, update menu bar icons.

### Files to Modify
1. `DesignTokens.swift` — Add Breakpoints enum
2. `SidePanelLayoutViews.swift` — Use breakpoints
3. `SidePanelFullViews.swift` — Use breakpoints
4. `SidePanelChromeViews.swift` — Add sidebar toggle
5. Create `ErrorBanner.swift`
6. `MeetingListenerApp.swift` — Menu bar icon states

### Implementation Details

#### D1: DesignTokens.swift — Add Breakpoints
```swift
// MARK: - Responsive Breakpoints
enum Breakpoints {
    /// 380pt - Ultra-narrow, minimal labels
    static let ultraNarrow: CGFloat = 380
    /// 560pt - Narrow width, sidebar collapses
    static let narrow: CGFloat = 560
    /// 600pt - Medium width, repositioned controls
    static let medium: CGFloat = 600
    /// 1080pt - Wide, full horizontal layouts
    static let wide: CGFloat = 1080
    /// 1240pt - Ultra-wide, three-column layout
    static let ultraWide: CGFloat = 1240
}
```

#### D2: Replace Hardcoded Values
Replace in:
- `SidePanelLayoutViews.swift:11` (600 → Breakpoints.medium)
- `SidePanelLayoutViews.swift:86` (560 → Breakpoints.narrow)
- `SidePanelFullViews.swift:60` (560 → Breakpoints.narrow)
- `SidePanelTranscriptSurfaces.swift:210` (380 → Breakpoints.ultraNarrow)

#### D3: Sidebar Collapse Logic
In `CompanionPanelView` (or updated `SidePanelView`):
```swift
GeometryReader { geometry in
    HStack(spacing: 0) {
        TranscriptColumn()
        
        if geometry.size.width > Breakpoints.narrow && showSidebar {
            SidebarColumn()
                .frame(width: 240)
                .transition(.move(edge: .trailing))
        }
    }
    .overlay(alignment: .topTrailing) {
        if geometry.size.width <= Breakpoints.narrow {
            Button { showSidebar.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(12)
        }
    }
}
```

#### D4: ErrorBanner.swift
```swift
struct ErrorBanner: View {
    let style: Style
    
    enum Style {
        case warning(title: String, detail: String?, action: Action?)
        case error(title: String, detail: String?, action: Action?)
        
        struct Action {
            let label: String
            let handler: () -> Void
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(tintColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let action = action {
                Button(action.label, action: action.handler)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(borderColor),
            alignment: .top
        )
    }
}
```

#### D5: Menu Bar Icon States
In `MeetingListenerApp.swift`, update icon based on state:
```swift
var menuBarIcon: String {
    switch appState.sessionState {
    case .idle: return "waveform"
    case .listening: return "waveform.circle.fill"
    case .paused: return "pause.circle"
    case .error: return "waveform.circle.fill" // with red badge
    }
}

var iconColor: Color {
    switch appState.sessionState {
    case .listening: return .green
    case .error: return .red
    default: return .secondary
    }
}
```

### Acceptance Criteria
- [ ] Breakpoints centralized in DesignTokens
- [ ] All hardcoded values replaced
- [ ] Sidebar collapses below 560pt
- [ ] Sidebar toggle appears when collapsed
- [ ] ErrorBanner component created and used
- [ ] Menu bar icon shows distinct states
- [ ] Swift build passes

### Files Delivered
- Modified: `DesignTokens.swift`, `SidePanelLayoutViews.swift`, `SidePanelFullViews.swift`, `SidePanelChromeViews.swift`, `MeetingListenerApp.swift`
- Created: `ErrorBanner.swift`

---

## Integration Checklist

After all tasks complete:

1. [ ] All 4 branches merged to main
2. [ ] No duplicate symbols (check for SettingsView, PrivacyDashboard)
3. [ ] No broken references (check renamed enums)
4. [ ] Swift build passes
5. [ ] Basic smoke test: onboarding → record → stop → history
6. [ ] Update AGENTS.md with new windowing policy

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Merge conflicts | Tasks A, B, C touch mostly different files. Task D touches many but is last. |
| Regression in transcript | Task C keeps Roll view intact, only removes alternatives |
| Settings data loss | Keep same @AppStorage keys, just reorganize UI |
| Permission flow break | Test deferred permission path explicitly |

---

*Task breakdown ready for parallel execution*
