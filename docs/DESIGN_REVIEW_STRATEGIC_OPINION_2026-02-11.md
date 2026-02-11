# EchoPanel Design Review — Strategic Opinion & Implementation Guide

**Date:** 2026-02-11  
**Context:** Follow-up to Apple-Level Design Review  
**Purpose:** Detailed opinion on product identity, windowing policy, and 7-day action plan

---

## The Core Opinion

EchoPanel is failing on narrative coherence, not engineering. That is the exact kind of thing that makes a Mac app feel "almost premium" but not "inevitable."

Right now EchoPanel is trying to satisfy two incompatible user contracts:

**Contract A (menu bar utility):** "I will never demand attention. I will not ask you to manage windows. I will be instantly understandable."

**Contract B (workspace panel):** "I am part of your working context. I will hold state. I will reward time spent."

EchoPanel's feature set is overwhelmingly Contract B, but the framing and entry point still smell like Contract A. That mismatch is why you keep needing extra modes, extra windows, extra naming, extra explanation.

---

## Strong Opinion: Commit to Workspace Panel

EchoPanel should be a workspace panel app that happens to live in the menu bar for convenience and status.

**Reason:** Transcription plus highlights is not a "glance" product. It's a parallel stream of truth. People will keep it visible while the meeting is happening, then they will skim it right after. That is workspace behavior.

If you try to force it into menu bar utility constraints, you'll amputate the differentiators and end up competing with commodity recorders.

---

## What This Commitment Implies

### 1) Default Behavior Must Match Core Value

If Roll mode is the hero, it has to appear without effort.
- When meeting starts (or user hits record), the panel opens in Roll mode
- Menu bar icon becomes a status and control point, not the primary UI
- The user should not have to decide "which mode" before they get value

### 2) Kill the "Mode Maze" Through Hierarchy

Replace "Roll / Compact / Full" as top-level modes with a single panel that has:
- Live view (Roll-like)
- Focus view (for the last N minutes plus highlights)
- Review view (search, filter, jump, export)

Keep UI density differences, but they should feel like "expand/collapse detail," not "you entered a different world."

### 3) "Surfaces" Is the Wrong Noun

Users understand: Highlights, Moments, Key points, Flags, Pins, Decisions, Action items.

They do not understand "surfaces" without explanation. That is a tax you pay forever.

**Rename to Highlights**, but also sanity-check the underlying concept:
- If Surfaces are overlays, make them feel like filters/lenses applied to the transcript
- If Surfaces are saved views, make them feel like Smart Folders
- If Surfaces are generated "cards," make them feel like Highlights feed

Pick one. Mixing these leads to confusion.

### 4) Window Architecture Must Be Boring

Boring is premium.

If you commit to workspace panel:
- One primary panel window for live and review
- One history/library window (could be the same window with a sidebar)
- Settings as a standard macOS Settings window (Cmd-comma)

Avoid separate "Summary window" unless it is objectively a different job-to-be-done.

**Bias:** Merge Summary into the same main window as a tab/section inside a session detail view:
- Session: Live, Highlights, Summary, Export

### 5) Permissions Timing: Trust Economics

Deferring Screen Recording permission until first use is correct.

**Why:** Early permission prompts feel like surveillance onboarding. Asking later, at the moment of need, feels like "tool requesting capability for a user action."

**Also:** Build a Privacy dashboard not as "policy copy," but as a tangible system status panel showing sources, storage paths, retention, and explicit "nothing leaves device" messaging.

### 6) Accessibility: Live Needs Live Semantics

If you are streaming transcript lines, you need live region announcements for screen readers, but avoid spam:
- Announce speaker change
- Announce new paragraph, not every token/word
- Provide a toggle for verbosity
- Respect focus, do not steal it

### 7) Visual Tokens: Only Fix What's Load-Bearing

Token consistency is valid but not the main lever. The main lever is conceptual clarity:
- Fewer nouns
- Fewer modes
- Fewer windows
- Clearer default journey

If you polish visuals while keeping the model messy, the app will look expensive and feel confusing.

---

## The Strategic Question, Answered

**EchoPanel is a workspace panel app.**

The menu bar is just the handle you grab to summon it. Like a pilot light, not the stove.

---

## Handling Rich Backend Features Without UI Chaos

You can have raw audio, diarization, cleaned transcript, NER, summaries, RAG, and still not become a UI junk drawer.

**First principle:** You are building a meeting intelligence workstation. Workstations keep a single "primary object" on screen and progressively reveal depth when asked.

**The primary object:** The session transcript, live and reviewable.

Everything else is either:
- A transformation of it (cleaned, formatted)
- An annotation on it (NER, highlights, action items)
- A retrieval tool that uses it (RAG)

### Layered Representations, One Primary View

Canonical data layers per session:
1. Raw: original audio stream + timestamps + device/source metadata
2. Diarized: speaker segments mapped onto time ranges
3. Text v0: ASR output
4. Text v1 (clean): normalization, punctuation, disfluency handling
5. Annotations: entities, topics, highlights, decisions, tasks, links
6. Derived artifacts: summary, minutes, action list, searchable index (RAG)

These are not "different screens." They are different depths of the same session.

### UI Structure That Scales

One main window, consistent skeleton:
- Center: Transcript timeline (the hero)
- Right sidebar: tabs (Highlights, Entities, Tasks, Ask)
- Top bar: Search, Jump Live, Export
- Bottom or inline: Processing status (what's ready, what's running)

Advanced details live behind a single "Details" drawer or inspector panel.

### How to Expose "Raw vs Formatted"

Default view is formatted and readable. Always.

Then provide:
- A toggle: View: Cleaned | Verbatim
- A per-line expansion: "Show raw segment"
- Provenance on hover: "Derived from 00:12:31–00:12:48, Speaker 2, confidence 0.82"

### NER and "Surfaces" as Transcript Lenses

NER is not a separate feature. It's a lens on the transcript.

Examples of lenses:
- Show only lines with People/Orgs
- Highlight dates and commitments
- Filter to one speaker
- Show "Questions" segments
- Show "Action items" segments

These are filters and highlights applied to the same transcript stream.

### Summary and RAG

**Summary:** A tab inside the session, not a separate window. An artifact derived from the session.

**RAG:** Should feel like "Ask this meeting" rather than "enter a different product."
- Input box: Ask a question
- Answers cite timestamps and speakers
- Clicking a citation jumps the transcript to that moment

### Design Rules to Keep You Honest

1. The user should be able to use EchoPanel fully without ever learning the words diarization, NER, or RAG.
2. Every advanced feature must attach to either the transcript view or the session artifact view.
3. No new top-level window unless it represents a different object type (not a different representation).

---

## Windowing & Layout Policy

### Primary Window Archetype

EchoPanel should behave like a "companion panel" window:
- Can be left open for long sessions
- Should not steal focus unnecessarily
- Should remember its size and position
- Should work well side-by-side with Zoom/Meet

### Default Placement

Right-side panel (most people keep meeting app center or left).

### Three Sizing Presets

| Preset | Width | Use Case |
|--------|-------|----------|
| Narrow | 360-420 pt | Minimal distractions, live Roll |
| Medium | 520-640 pt | Best default for most monitors |
| Wide | 760-900 pt | Deep review, search, RAG |

Keyboard addressable: ⌘1, ⌘2, ⌘3

Height: Full usable height minus menu bar and safe areas.

### Placement Policy

**First-run placement (no prior state):**
- Place on active display
- Snap to right edge with 20pt margin
- Use Medium preset
- Vertically align to top safe area

**Return placement (existing state):**
- Restore last position/size per display configuration
- If display is missing, move to current display and apply first-run

### Interaction Behavior

**When user starts recording:**
- Panel appears
- Does NOT steal focus (user might be presenting)
- Subtle first-run tip teaches keyboard shortcut to focus it

**When user clicks menu bar icon:**
- If panel is open, bring to front
- If closed, open at remembered size/position

**When meeting ends:**
- Do not auto-open new windows
- Show small non-modal banner inside panel: "Session saved. Summary ready in 20s."

### Responsive Breakpoints

- **< 420 pt:** Hide right sidebar by default, single "Panels" button
- **420-560 pt:** Show sidebar as overlay drawer
- **> 560 pt:** Show persistent sidebar

### Layout Skeleton (Stable)

- Top toolbar: session status, search, jump live, export
- Main content: transcript stream (center)
- Right sidebar: tabs (Highlights, Entities, Tasks, Ask)
- Bottom status strip: processing state (Live vs Refined)

Key rule: Transcript width should not wildly change when sidebar changes.

### Multi-Monitor Behavior

- Panel appears on display where user started recording
- If meeting app detected on another display, offer one-time "Move beside meeting" banner
- Don't chase windows automatically (feels haunted)

### Recommended Default Package

- Workspace panel window, right-snapped, Medium preset
- Appears on record start without stealing focus
- Persistent sidebar only above 560 pt
- Detach-to-window for deep review
- Restore position/size per display config
- Cmd-comma Settings, plus Privacy dashboard

---

## Concrete Implementation

### SwiftUI Window Configuration

```swift
Window("EchoPanel", id: "companion-panel") {
    CompanionPanelView(appState: appState)
        .frame(minWidth: 360, idealWidth: 580, maxWidth: 900, 
               minHeight: 400, idealHeight: 800)
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.defaultPosition(.trailing)
.restorationBehavior(.allowed)
.commands {
    CommandMenu("View") {
        Button("Narrow") { resizePanel(to: 380) }
            .keyboardShortcut("1", modifiers: .command)
        Button("Medium") { resizePanel(to: 580) }
            .keyboardShortcut("2", modifiers: .command)
        Button("Wide") { resizePanel(to: 780) }
            .keyboardShortcut("3", modifiers: .command)
        
        Divider()
        
        Toggle("Show Sidebar", isOn: $appState.showSidebar)
            .keyboardShortcut("0", modifiers: .command)
    }
}

// Detached review window (optional, power user)
Window("Session Review", id: "review") {
    ReviewWindowView(session: appState.selectedSession)
        .frame(minWidth: 780, minHeight: 600)
}

// Standard Settings window
Settings {
    SettingsView()
        .frame(width: 600, height: 480)
}
```

### Window Placement Controller

```swift
class WindowPlacementController: ObservableObject {
    @AppStorage("panel.lastFrame") private var savedFrame: String?
    @AppStorage("panel.displayID") private var savedDisplayID: String?
    
    func placementStrategy() -> WindowPlacement {
        guard let frameString = savedFrame,
              let previousDisplay = savedDisplayID,
              displayStillExists(previousDisplay) else {
            return .defaultRight
        }
        return .restore(NSRectFromString(frameString))
    }
    
    func saveCurrentFrame(_ frame: NSRect, displayID: String) {
        savedFrame = NSStringFromRect(frame)
        savedDisplayID = displayID
    }
}

enum WindowPlacement {
    case defaultRight
    case restore(NSRect)
    
    var nsRect: NSRect {
        switch self {
        case .defaultRight:
            guard let screen = NSScreen.main?.visibleFrame else {
                return NSRect(x: 100, y: 100, width: 580, height: 800)
            }
            let width: CGFloat = 580
            let padding: CGFloat = 20
            let x = screen.maxX - width - padding
            let y = screen.minY + padding
            let height = screen.height - (padding * 2)
            return NSRect(x: x, y: y, width: width, height: height)
            
        case .restore(let rect):
            return rect
        }
    }
}
```

### Responsive Sidebar

```swift
struct CompanionPanelView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                TranscriptColumn()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if geometry.size.width > 560 && appState.showSidebar {
                    SidebarColumn()
                        .frame(width: 240)
                        .transition(.move(edge: .trailing))
                }
            }
            .overlay(alignment: .topTrailing) {
                if geometry.size.width <= 560 {
                    Button { appState.showSidebar.toggle() } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(12)
                }
            }
        }
        .inspector(isPresented: $appState.showDetailsInspector) {
            SessionInspectorView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }
}
```

### Privacy Dashboard

```swift
struct PrivacyDashboard: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Data Storage") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Local Storage")
                            .font(.headline)
                        Text("All data stays on this Mac")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "internaldrive")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                
                StorageMeter(used: appState.storageUsed, 
                            itemCount: appState.sessionCount)
                
                HStack {
                    Button("Export All...") { appState.exportAllSessions() }
                    Button("Delete All...", role: .destructive) { 
                        appState.confirmDeleteAll() 
                    }
                }
            }
            
            Section("Retention") {
                Picker("Auto-delete sessions after", 
                       selection: $appState.retentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Never").tag(0)
                }
            }
            
            Section("Active Permissions") {
                PermissionRow(
                    name: "Screen Recording",
                    status: appState.screenRecordingPermission,
                    purpose: "Capture system audio from meetings"
                )
                PermissionRow(
                    name: "Microphone",
                    status: appState.microphonePermission,
                    purpose: "Record your voice"
                )
            }
            
            Section("Session Bundle Privacy") {
                Text("Debug bundles never include raw audio unless you explicitly opt in each time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .formStyle(.grouped)
    }
}
```

### Simplified Onboarding

```swift
struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var step: Step = .welcome
    
    enum Step {
        case welcome      // Value prop + privacy promise
        case permissions  // One-click setup (deferred actual ask)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                WelcomeStep { step = .permissions }
            case .permissions:
                PermissionsStep {
                    dismiss()
                    appState.openCompanionPanel() // Auto-open for demo
                }
            }
        }
        .frame(width: 480, height: 360)
    }
}

struct WelcomeStep: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Your meeting companion")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                BenefitRow(icon: "text.bubble", 
                          text: "Live transcript beside your meeting")
                BenefitRow(icon: "pin", 
                          text: "Pin key moments as they happen")
                BenefitRow(icon: "lock.shield", 
                          text: "Everything stays on your Mac")
            }
            
            Spacer()
            
            Button("Get Started") { onContinue() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}
```

---

## The 7-Day Action Plan

### Day 1: Settings Window
- Create SettingsView with 5 tabs
- Move existing settings from menu into it
- Add Privacy Dashboard (mocked data OK initially)
- Wire up ⌘, shortcut

### Day 2: Windowing Policy
- Replace Window definitions with companion-panel architecture
- Implement WindowPlacementController
- Add 3 preset sizes (⌘1, ⌘2, ⌘3)
- Test position restoration

### Day 3: Simplify Onboarding
- Cut from 5 steps to 2
- Remove permission requests from onboarding
- Add "defer until first use" logic
- Auto-open panel after onboarding

### Day 4: Consolidate Views
- Remove "Full mode" as top-level concept
- Make Roll the default live view
- Merge Summary into History as a tab
- Rename Surfaces → Highlights

### Day 5: Responsive Layout
- Implement 560pt sidebar breakpoint
- Add floating sidebar toggle for narrow
- Create Details inspector drawer
- Test at all 3 preset sizes

### Day 6: Error States & Polish
- Implement ErrorBanner component
- Add error scenarios from review
- Fix grid/spacing inconsistencies
- Menu bar icon states (idle/listening/paused)

### Day 7: Testing & Documentation
- Test window restoration across displays
- Test permission deferral flow
- Update AGENTS.md with windowing policy
- Write 1-paragraph IA explanation

---

## Final Principle

**If you have to explain it in a tooltip, it's wrong.**

Every feature should be guessable from its name and placement. "Surfaces" failed this. "Highlights" passes. "Full mode" fails. "Review" or "Analyze" passes.

Ship the 7-day plan. The app will feel inevitable.
