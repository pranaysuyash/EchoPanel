# EchoPanel UI v2 Design Document

**Date:** 2026-02-15  
**Status:** Design Proposal  
**Scope:** Complete UI redesign without backend dependencies

---

## 1. Executive Summary

This document proposes a redesigned UI for EchoPanel that simplifies the user experience, adopts modern macOS design patterns (Liquid Glass), and clarifies the app's identity as a utility tool rather than a workspace replacement.

### Key Changes
- **Reduced complexity**: Consolidate from 3 view modes to 2
- **Clearer terminology**: Replace jargon with plain language
- **Better macOS citizenship**: Full menu bar structure, standard shortcuts
- **Simplified visual hierarchy**: System colors and materials
- **Deferred permissions**: Ask only when needed

---

## 2. App Identity & Architecture

### Current Problem
Tension between "passive menu bar tool" vs "active workspace panel" creates confusion about when and how to use the app.

### Proposed Solution
Commit to being a **utility app with an optional persistent panel**.

**Metaphor**: Like Things 3 or Bartender—not a full workspace, but a focused tool that can expand when needed.

**Hierarchy:**
```
Primary: Menu bar dropdown (control center)
Secondary: Side panel (appears on demand)
Tertiary: Popover panels (history, settings, etc.)
```

---

## 3. Layout & Navigation Structure

### 3.1 View Modes (Consolidated)

| Mode | Use Case | Layout |
|------|----------|--------|
| **Live** (default) | Active meeting | Clean transcript roll + floating insights |
| **Review** | Post-meeting | Full panel with sidebar navigation |

**Rationale**: "Compact" mode was essentially Live mode with less space. Remove it and let users resize the window.

### 3.2 Menu Bar Structure

```
App Menu
├── Start/Stop Recording ⌘⇧R
├── Show Panel ⌘⇧P
├── Recent Sessions (last 5)
├── Export Last Session
└── Settings… ⌘,

File Menu  
├── New Session ⌘N
├── Open History ⌘O
├── Export (submenu)
└── Close Window ⌘W

View Menu
├── Live Mode
├── Review Mode
├── Always on Top
└── Enter Full Screen ⌘⌃F

Window Menu
├── Minimize ⌘M
├── Show History
└── Bring All to Front
```

### 3.3 Window Model

| Window | Size | Behavior |
|--------|------|----------|
| Live Panel | 400×700 (min 320×500) | Floating, resizable |
| Review Window | 900×700 (min 700×500) | Standard window |
| Settings | 500×380 | Modal sheet |
| History | 980×620 | Standard window |
| Onboarding | 500×400 | Modal, hiddenTitleBar |

---

## 4. Visual Design

### 4.1 Color System

Adopt **system semantic colors** for automatic adaptation:

```swift
// Background hierarchy
.bg-primary: .systemBackground
.bg-secondary: .secondarySystemBackground  
.bg-tertiary: .tertiarySystemBackground

// Semantic colors
.accent: .accentColor (respects user preference)
.success: .systemGreen
.warning: .systemOrange
.danger: .systemRed

// Text
.text-primary: .label
.text-secondary: .secondaryLabel
.text-tertiary: .tertiaryLabel
.separator: .separator
```

**Why**: Automatically adapts to light/dark mode, accessibility settings, and user accent color preferences.

### 4.2 Typography

Use **system text styles** exclusively:

```swift
Display: .largeTitle    // Empty states
Headline: .headline     // Section headers
Title: .title3          // Card titles
Body: .body             // Transcript content
Caption: .caption1      // Timestamps, metadata
Mono: .body.monospaced() // Technical data
```

### 4.3 Materials (Liquid Glass Guidelines)

Following macOS Tahoe 26+ guidelines:

```swift
// Navigation/controls layer
.sidebar: .ultraThinMaterial
.toolbar: .thinMaterial
.popover: .thinMaterial

// Content layer (never use glass)
.card: .regularMaterial
.transcript: .clear (no material)
```

**Rule**: Never put Liquid Glass on content (tables, lists, documents)—it muddies hierarchy.

### 4.4 Spacing System (8pt Grid)

```
4pt:  Tight icon gaps, inline spacing
8pt:  Standard control padding
12pt: Card padding, section gaps  
16pt: Container padding
20pt: Section separation
24pt: Major section breaks
```

### 4.5 Corner Radii

```
4pt:  Tags, badges
8pt:  Buttons, small controls
10pt: Cards, list items
12pt: Containers, panels
16pt: Main panel, modals
```

---

## 5. Component Specifications

### 5.1 Menu Bar Icon

**States:**
- Idle: Waveform icon (gray)
- Listening: Filled waveform + timer (green dot)
- Paused: Pause icon (yellow dot)
- Error: Alert icon (red dot)

**Dropdown Structure:**
```
┌──────────────────────────────────────┐
│  EchoPanel                    v0.2.0 │
│  Status: Ready                       │
├──────────────────────────────────────┤
│  [● Start Recording]                 │
│  [Export Last Session]               │
├──────────────────────────────────────┤
│  Recent Sessions:                    │
│  → Team Standup (2h ago)             │
│  → Client Call (5h ago)              │
├──────────────────────────────────────┤
│  Open Panel              ⌘⇧P         │
│  Session History         ⌘⇧H         │
├──────────────────────────────────────┤
│  Settings…               ⌘,          │
│  Quit                    ⌘Q          │
└──────────────────────────────────────┘
```

### 5.2 Side Panel Layout

**Live Mode:**
```
┌─────────────────────────────────────────────────────┐
│ ◉ Recording   14:32           [📌] [⚙] [✕]         │  ← Toolbar
├─────────────────────────────────────────────────────┤
│ [Summary] [Actions] [Pins] [People]                 │  ← Tab bar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │ Sarah Chen                                   │  │
│  │ "The deadline is next Friday"                │  │
│  │                                    2:34 PM   │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │ Alex Kim                                     │  │
│  │ "I'll handle the API integration"            │  │
│  │ [✓] Action assigned to Alex                  │  │
│  │                                    2:35 PM   │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
│  [Always on Top]        [End Session]               │  ← Footer
└─────────────────────────────────────────────────────┘
```

**Review Mode:**
```
┌─────────────────────────────────────────────────────────────┐
│ EchoPanel                              [History] [Settings] │
├──────────────┬──────────────────────────────────────────────┤
│              │  Team Standup — Feb 15, 2025                 │
│  [Summary]   │  Duration: 45 min · 12 participants          │
│  [Actions]   │                                              │
│  [Pins]      │  Key Points:                                 │
│  [People]    │  • Deadline moved to Feb 28                  │
│  [Transcript]│  • API integration assigned to Alex          │
│              │                                              │
│  ────────────┤                                              │
│              │  Action Items:                               │
│  Sessions    │  ☑ Review Q1 numbers (Sarah)                 │
│  ├── Standup │  ☐ API integration (Alex)                    │
│  ├── Client  │  ☐ Update documentation (Mike)               │
│  └── Sprint  │                                              │
│              │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

### 5.3 Card Component

**Transcript Card:**
```swift
.background(.regularMaterial)
.cornerRadius(10)
.overlay(
    RoundedRectangle(cornerRadius: 10)
        .stroke(.separator, lineWidth: 0.5)
)
.padding(.horizontal, 12)
.padding(.vertical, 8)
```

**Content structure:**
```
[Speaker Name]                    [Pin button]
"Transcript text content..."
[Action chip - if applicable]          [Time]
```

### 5.4 Tab Bar Component

**Segmented control style for insights:**
```swift
Picker("View", selection: $selectedTab) {
    Text("Summary").tag(Tab.summary)
    Text("Actions").tag(Tab.actions)
    Text("Pins").tag(Tab.pins)
    Text("People").tag(Tab.people)
}
.pickerStyle(.segmented)
.padding(.horizontal, 12)
.padding(.vertical, 8)
```

---

## 6. Copy & Messaging

### 6.1 Terminology Changes

| Current | Proposed | Rationale |
|---------|----------|-----------|
| Surfaces | Highlights | Clearer purpose |
| Entities | People & Topics | Plain language |
| Roll mode | Live view | Descriptive |
| Compact mode | (remove) | Redundant |
| Full mode | Review view | Purpose-driven |
| VAD | Voice detection | User-friendly |

### 6.2 Menu Bar Copy

**States:**
```
Idle:       "EchoPanel" (gray dot)
Listening:  "● 14:32" (green dot + timer)
Paused:     "⏸ 14:32" (yellow dot)
Error:      "⚠ EchoPanel" (red dot)
```

**Actions:**
```
"Start Recording" / "End Session"
"Backend Ready" / "Backend Starting"
Shortcuts: "⌘⇧L" format
```

### 6.3 Empty States

**Pre-recording:**
```
"Ready to capture"
"Click Start or press ⌘⇧R to begin"
```

**Recording, waiting for speech:**
```
"Listening..."
"First transcript usually appears in 2-5 seconds"
```

**No insights yet:**
```
"No highlights yet"
"Key points will appear here as the conversation develops"
```

### 6.4 Settings Sections

```
General
  ├─ Start at login
  ├─ Show in dock
  └─ Keyboard shortcuts

Recording
  ├─ Audio source
  ├─ Voice detection sensitivity
  └─ Auto-export on end

Highlights
  ├─ Extract action items
  ├─ Identify people & topics
  └─ Language

Privacy & Data
  ├─ Storage usage
  ├─ Auto-delete after
  ├─ Export all data
  └─ Delete all sessions
```

---

## 7. Keyboard Shortcuts

### Complete Shortcut Map

| Action | Shortcut | Menu |
|--------|----------|------|
| Start/Stop recording | ⌘⇧R | App |
| Show/hide panel | ⌘⇧P | App |
| Pin current moment | ⌘⇧D | — |
| New session | ⌘N | File |
| Export | ⌘E | File |
| Settings | ⌘, | App |
| Always on top | ⌘⇧T | View |
| Open history | ⌘⇧H | Window |
| Help | ⌘? | Help |

### Navigation Shortcuts (when panel focused)

| Action | Shortcut |
|--------|----------|
| Next/previous item | ↑ / ↓ |
| Pin selected | P |
| Copy selected | ⌘C |
| Search | ⌘F |

---

## 8. Onboarding Flow

### Current Flow
Welcome → Permissions → Token → Ready

### Proposed Flow
Welcome → (defer permissions) → Quick tips → Ready

```
Step 1: Welcome
┌─────────────────────────────────────┐
│                                     │
│         [Waveform Icon]             │
│                                     │
│      Welcome to EchoPanel           │
│                                     │
│   Capture any meeting with one      │
│   click. Get transcripts, actions,  │
│   and highlights automatically.     │
│                                     │
│        [Get Started]                │
│                                     │
└─────────────────────────────────────┘

Step 2: Quick Tips
┌─────────────────────────────────────┐
│                                     │
│   Tip 1 of 3                        │
│                                     │
│   Press ⌘⇧R anytime to start        │
│   recording, even when the panel    │
│   is closed.                        │
│                                     │
│   [Skip]              [Next →]      │
│                                     │
└─────────────────────────────────────┘

Step 3: Ready
┌─────────────────────────────────────┐
│                                     │
│      You're all set!                │
│                                     │
│   First recording will ask for      │
│   microphone and screen recording   │
│   permissions.                      │
│                                     │
│        [Open Panel]                 │
│                                     │
└─────────────────────────────────────┘
```

**Key change**: Defer permission requests until first recording attempt. This reduces friction and improves conversion.

---

## 9. Accessibility Considerations

### VoiceOver Support

All interactive elements must have:
```swift
.accessibilityLabel("Start recording")
.accessibilityHint("Begins capturing audio from your meeting")
.accessibilityValue("Not recording")
```

### Keyboard Navigation

- Full tab order through all controls
- Focus rings on all interactive elements
- Escape to close panels/modals
- Space/Enter to activate

### Reduced Motion

```swift
.withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.2))
```

### Color Independence

Never encode meaning with color alone:
- Recording: Green dot + "Recording" label
- Warning: Orange dot + icon + label
- Error: Red dot + icon + "Error" label

---

## 10. Implementation Notes

### Tech Stack
- SwiftUI for all UI
- Swift 6 strict concurrency
- No external UI dependencies (keep it simple)

### State Management
```swift
@MainActor
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var panelVisible: Bool = false
    @Published var selectedTab: Tab = .highlights
    // ... other state
}
```

### Design Tokens
All values should be in a single `DesignTokens.swift` file for easy theming.

---

## 11. Migration Path

### Phase 1: Document (This document)
✅ Create comprehensive design specification

### Phase 2: Prototype (Next step)
- Build standalone v2 without backend
- Use mock data for visual testing
- Iterate based on visual feedback

### Phase 3: Integration
- Gradually replace v1 components
- Maintain backward compatibility for data
- Deprecate v1 after v2 stabilizes

---

## 12. Success Metrics

**Usability:**
- Time to first recording < 30 seconds
- Permission grant rate > 80%
- Error recovery without support

**Performance:**
- Panel open < 100ms
- Scroll 60fps with 1000+ items
- Memory < 200MB during recording

**Accessibility:**
- All interactive elements reachable via keyboard
- VoiceOver completes core workflow
- Passes all accessibility audits

---

## Appendix A: File Structure

```
macapp_v2/
├── Package.swift
├── Sources/
│   ├── EchoPanelApp.swift          # App entry point
│   ├── AppState.swift              # Global state
│   ├── DesignTokens.swift          # Colors, spacing, typography
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── TranscriptItem.swift
│   │   ├── Highlight.swift
│   │   └── Person.swift
│   ├── Views/
│   │   ├── MenuBarView.swift       # Menu bar dropdown
│   │   ├── PanelView.swift         # Main panel container
│   │   ├── LiveView.swift          # Live recording view
│   │   ├── ReviewView.swift        # Post-meeting review
│   │   ├── Components/
│   │   │   ├── TranscriptCard.swift
│   │   │   ├── TabBar.swift
│   │   │   ├── Toolbar.swift
│   │   │   └── EmptyState.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── GeneralSettings.swift
│   │       ├── RecordingSettings.swift
│   │       └── PrivacySettings.swift
│   ├── ViewModels/
│   │   ├── PanelViewModel.swift
│   │   └── SessionViewModel.swift
│   └── MockData/
│       └── SampleSessions.swift    # For visual testing
└── Tests/
    └── UITests/
```

---

## Appendix B: Comparison Matrix

| Aspect | v1 Current | v2 Proposed |
|--------|-----------|-------------|
| View modes | 3 (Roll/Compact/Full) | 2 (Live/Review) |
| Menu structure | Custom | Standard macOS |
| Colors | Custom tokens | System semantic |
| Materials | Custom backgrounds | Liquid Glass guidelines |
| Onboarding | 4 steps + immediate permissions | 3 steps, deferred permissions |
| Terminology | Surfaces, Entities, VAD | Highlights, People & Topics, Voice detection |
| Keyboard shortcuts | Partial | Complete coverage |
| Window model | Fixed sizes | Fluid, resizable |

---

*End of Document*
