# EchoPanel v2 UI Specification

## Overview

EchoPanel v2 is a native macOS meeting intelligence application built with SwiftUI. This document describes the complete UI implementation with mock data for all views and states.

## Architecture

### Technology Stack
- **UI Framework**: SwiftUI (macOS 13+)
- **Architecture**: MVVM with ObservableObject
- **State Management**: `@StateObject`, `@Binding`, `@AppStorage`
- **Persistence**: UserDefaults via `@AppStorage`
- **Build System**: Swift Package Manager (Swift 5.9+)

### File Structure
```
Sources/
├── EchoPanelV2App.swift      # App entry, main window, keyboard shortcuts
├── AppState.swift             # Global state, models, flow management
├── MockData.swift             # Mock payloads for all 4 flow scenarios
├── DesignTokens.swift         # Colors, spacing, typography, reusable components
├── MainView.swift             # (integrated into EchoPanelV2App.swift)
├── FlowStudioView.swift      # 4-track mock flow selector
├── LiveView.swift             # Live recording view with tabs
├── ReviewView.swift           # Session review with sidebar
├── HistoryView.swift          # Search and browse past sessions
├── SessionDetailView.swift    # Full session view (in EchoPanelV2App.swift)
├── SettingsView.swift         # Settings with 4 tabs
├── OnboardingView.swift       # 3-step onboarding flow
├── MenuBarView.swift          # Menu bar dropdown panel
├── ExportDialogs.swift        # Export with 4 formats + fileExporter
├── ConfirmationDialogs.swift  # Start/stop/delete confirmations
├── ProviderSelectors.swift    # ASR + LLM provider selection
├── SearchableTranscriptView.swift # Transcript with search
├── EmptyStateView.swift       # Empty state variants
├── LoadingStateView.swift     # Skeleton loading, streaming view
├── ErrorStateView.swift       # Error cards, paused state
└── AboutView.swift            # About dialog
```

## Views & States

### 1. Main Window (EchoPanelV2App.swift)

**States:**
- Onboarding (first launch)
- Dashboard (main view)
- Flow Studio (mock scenario selector)
- History (past sessions)

**Keyboard Shortcuts:**
- `⌘Q` - Quit
- `⌘⇧R` - Toggle Recording (start/stop)
- `⌘⇧P` - Toggle Panel visibility
- `⌘⇧H` - Open History

**Workspace Modes:**
- `dashboard` - Welcome + recent sessions
- `flowStudio` - 4-track mock scenario explorer
- `history` - Searchable session history

### 2. Sidebar

**Contains:**
- Recording indicator (when active)
- Session list with search
- Context menus for export/delete

**States:**
- Empty (no sessions)
- Normal (with sessions)
- Recording (shows timer + pause/stop buttons)

### 3. Flow Studio (FlowStudioView.swift)

**4 Mock Scenarios:**

1. **Team Standup** (✓ Complete)
   - 12 transcript items
   - 4 highlights
   - 3 participants (Sarah, Alex, Mike)
   - Topics: API migration, integration timeline, performance

2. **Customer Escalation** (✓ Complete)
   - 15 transcript items
   - 5 highlights
   - 4 participants (Maya, Raj, Iris, Leo)
   - Topics: Token refresh bug, hotfix deployment, customer communication
   - Escalation workflow: diagnosis → hotfix → monitoring → resolution

3. **Hiring Loop** (✓ Complete)
   - 20 transcript items
   - 4 highlights
   - 5 participants (Anya, Leo, Nina, Sam, Priya)
   - Topics: Technical interview, product sense, behavioral, follow-up decision

4. **Launch War Room** (✓ Complete)
   - 12 transcript items
   - 4 highlights
   - 3 participants (Priya, Noah, Evan)
   - Topics: Performance crisis, conversion vs personalization, GA decision

### 4. Live View (LiveView.swift)

**Tabs:**
- Highlights - Live highlight cards
- Transcript - Real-time transcript
- People - Detected participants

**States:**
- Idle (no recording)
- Recording (live updates)
- Paused (paused state view)

### 5. Session Detail View

**Tabs:**
- Summary - AI summary, stats, action items
- Transcript - Full transcript with speaker labels
- Highlights - All highlights grouped by type
- People - Participant cards with mention counts

### 6. Export Dialog (ExportDialogs.swift)

**Formats:**
- Markdown (.md) - Formatted document with headers
- JSON (.json) - Machine-readable with complete metadata
- Plain Text (.txt) - Simple text format
- SRT (.srt) - Subtitle format with timestamps

**Options:**
- Include transcript
- Include highlights
- Include action items

**Uses:** SwiftUI `.fileExporter` for native save dialog

### 7. Settings (SettingsView.swift)

**Tabs:**
- General - Theme, startup behavior
- Recording - Audio source, ASR provider
- Highlights - Detection preferences
- Privacy - Data retention, access controls

### 8. Onboarding (OnboardingView.swift)

**3 Steps:**
1. Welcome - App introduction
2. Tips - Usage best practices
3. Ready - Completion CTA

**Completion:** Sets `hasCompletedOnboarding = true` via `@AppStorage`

### 9. Menu Bar (MenuBarView.swift)

**Contains:**
- Recording state indicator
- Session timer
- Quick actions (start/stop/pause)
- Recent sessions list (last 5)
- Show/hide toggle
- Quit option

### 10. Error States (ErrorStateView.swift)

**Error Types:**
- `asrError` - Transcription failure
- `llmError` - AI processing failure
- `microphonePermission` - Mic access denied
- `screenRecordingPermission` - Screen recording denied
- `networkError` - Connection failure
- `storageFull` - Disk space issue
- `unknown` - Generic error

**Components:**
- ErrorStateView - Full error page
- ErrorCard - Compact error card
- ErrorBanner - Inline error banner
- PausedStateView - Recording paused UI

### 11. Loading States (LoadingStateView.swift)

**Components:**
- SkeletonTranscriptCard - Animated transcript placeholder
- SkeletonHighlightCard - Animated highlight placeholder
- SkeletonPersonCard - Animated person placeholder
- SkeletonSessionCard - Animated session placeholder
- StreamingTranscriptView - Live recording with dots animation
- ProgressLoadingView - Progress bar + message

### 12. Empty States (EmptyStateView.swift)

**Variants:**
- EmptySessionsView - No sessions with CTA
- EmptySearchResultsView - Search with no results
- NoHighlightsView - No highlights yet
- NoParticipantsView - No participants detected
- ComingSoonView - Feature not yet available

## Mock Data Structure

### Session Model
```swift
struct Session: Identifiable {
    let id: UUID
    let title: String
    let startTime: Date
    let duration: Int
    let transcript: [TranscriptItem]
    let highlights: [Highlight]
}
```

### TranscriptItem Model
```swift
struct TranscriptItem: Identifiable {
    let id: UUID
    let speaker: String
    let text: String
    let timestamp: Date
    var isPinned: Bool
    var actionItem: ActionItem?
}
```

### Highlight Model
```swift
struct Highlight: Identifiable {
    let id: UUID
    let type: HighlightType  // action, decision, keyPoint, question
    let content: String
    let timestamp: Date
}
```

### Person Model
```swift
struct Person: Identifiable {
    let id: UUID
    let name: String
    let mentionCount: Int
    let topics: [String]
}
```

## Backend Wiring Guide (Phase 2)

### Recording Flow
1. **Start Recording** → `AppState.startRecording()`
   - Creates new `Session` with UUID
   - Begins timer
   - Subscribes to ASR stream

2. **Live Transcript** → ASR provider → `AppState.liveTranscript`
   - Real-time append to transcript array
   - Auto-scroll in UI

3. **Live Highlights** → LLM provider → `AppState.liveHighlights`
   - Periodic analysis of transcript
   - Highlight type classification

4. **Stop Recording** → `AppState.stopRecording()`
   - Finalizes session
   - Triggers full summary generation
   - Adds to `sessions` array

### Export Flow
1. User clicks Export → `ExportDialog` opens
2. User selects format + options
3. `.fileExporter` triggered → Native save dialog
4. `ExportDocument.fileWrapper(configuration:)` called
5. Content generated from session data
6. File written to selected location

### Settings Flow
- All settings stored via `@AppStorage`
- ASR/LLM providers → API configuration
- Audio source → macOS audio routing
- Privacy settings → Local storage decisions

## Component Inventory

### Cards
- `SessionCard` - Session in list
- `TranscriptCard` - Single transcript item
- `HighlightCard` - Highlight with type badge
- `PersonCard` - Person with mention count
- `StatCard` - Dashboard statistics
- `SkeletonCard` - Loading placeholder

### Buttons
- `RecordButton` - Start/stop toggle
- `ExportButton` - Export sheet trigger
- `SettingsButton` - Settings window

### Pickers
- `WorkspacePicker` - Mode selector
- `ExportFormatPicker` - Format selector
- `ProviderPicker` - ASR/LLM selector

### Dialogs
- `ExportDialog` - Single session export
- `BatchExportDialog` - Multiple session export
- `DeleteConfirmationDialog` - Delete confirm
- `StartRecordingConfirmation` - Start confirm
- `StopRecordingConfirmation` - Stop confirm

## Design Tokens

### Colors
- Primary: System accent
- Success: Green (#34C759)
- Warning: Orange (#FF9500)
- Error: Red (#FF3B30)
- Info: Blue (#007AFF)

### Typography
- Headline: System bold
- Body: System regular
- Caption: System small
- Monospace: System monospaced

### Spacing
- xs: 4pt
- sm: 8pt
- md: 16pt
- lg: 24pt
- xl: 32pt

### Corner Radius
- xs: 4pt
- sm: 6pt
- md: 10pt
- lg: 16pt

## Success Criteria

1. ✅ `swift build` succeeds with zero errors
2. ✅ Every view renders with meaningful mock data
3. ✅ All 4 flow scenarios show complete different content
4. ✅ Empty state, loading state, error state all exist and render
5. ✅ Export dialogs generate real formatted text via `.fileExporter`
6. ✅ Keyboard shortcuts work (⌘⇧R, ⌘⇧P, ⌘⇧H)
7. ✅ Onboarding completes and navigates to dashboard
8. ✅ SessionDetailView exists and shows full session data
9. ✅ Menu bar shows recording state, timer, and recent sessions
10. ✅ All 4 export formats (Markdown, JSON, Text, SRT) implemented
