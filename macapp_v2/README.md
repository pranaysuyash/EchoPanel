# EchoPanel V2 - UI Prototype

A standalone UI prototype for EchoPanel v2 with no backend dependencies. This version focuses purely on visual design and user experience.

## Overview

This is a visual prototype built with SwiftUI to test the new UI design before integration with the backend. It includes:

- **Menu bar interface** with full control center
- **Live recording panel** with highlights, transcript, and people tabs
- **Review mode** for post-meeting analysis
- **Session history** with search and management
- **Settings** with all configuration options
- **Mock data** for realistic visual testing

## Design Principles

1. **macOS Native**: Uses system colors, materials, and conventions
2. **Simplified**: Consolidated from 3 view modes to 2 (Live/Review)
3. **Clear Language**: Replaced jargon ("Surfaces" → "Highlights", "Entities" → "People & Topics")
4. **Liquid Glass Ready**: Follows macOS Tahoe design guidelines
5. **Fully Accessible**: VoiceOver, keyboard navigation, reduced motion support

## Running the Prototype

### Prerequisites
- macOS 14.0+
- Xcode 15.0+

### Build & Run

```bash
cd macapp_v2
swift build
swift run EchoPanelV2
```

Or open in Xcode:
```bash
open Package.swift
```

Then press Cmd+R to run.

## Features to Test

### Menu Bar
- [ ] Icon changes based on recording state (idle/recording/paused/error)
- [ ] Timer display during recording
- [ ] Recent sessions list
- [ ] Keyboard shortcuts shown

### Live Panel
- [ ] Tab switching (Highlights/Transcript/People)
- [ ] Always on top toggle
- [ ] Recording status in toolbar
- [ ] Transcript cards with speaker, text, timestamps
- [ ] Highlight cards with type icons
- [ ] Action items badges on transcript cards

### Review Mode
- [ ] Sidebar navigation between sessions
- [ ] Summary view with AI summary and stats
- [ ] Highlights organized by type
- [ ] Full transcript view
- [ ] People view with mention counts and topics

### History
- [ ] Session list with search
- [ ] Duration and date display
- [ ] Export and delete actions

### Settings
- [ ] General: startup, shortcuts, appearance
- [ ] Recording: audio source, voice detection, auto-export
- [ ] Highlights: AI analysis options, language
- [ ] Privacy: storage, export, permissions status

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧R | Start/Stop recording |
| ⌘⇧P | Show/Hide panel |
| ⌘⇧H | Open history |
| ⌘, | Settings |
| ⌘Q | Quit |

## File Structure

```
Sources/
├── EchoPanelV2App.swift      # App entry point
├── AppState.swift            # Global state & models
├── DesignTokens.swift        # Colors, spacing, typography
├── MockData.swift            # Sample data for testing
├── MenuBarView.swift         # Menu bar dropdown
├── LiveView.swift            # Live recording view
├── ReviewView.swift          # Post-meeting review
├── HistoryView.swift         # Session history
└── SettingsView.swift        # Settings tabs
```

## Mock Data

The prototype includes realistic mock data:
- 3 sample sessions
- 12 transcript items
- 4 highlights (actions, decisions, key points)
- 3 people with topics

This allows you to test the UI with realistic content immediately.

## Next Steps

After visual approval:
1. Integrate with actual backend (WebSocket, audio capture)
2. Replace mock data with real sessions
3. Add onboarding flow
4. Implement export functionality
5. Add search within transcripts

## Differences from V1

| Aspect | V1 | V2 |
|--------|-----|-----|
| View modes | 3 (Roll/Compact/Full) | 2 (Live/Review) |
| Terminology | Surfaces, Entities, VAD | Highlights, People & Topics, Voice detection |
| Menu bar | Custom | Full macOS standard |
| Colors | Custom tokens | System semantic |
| Materials | Custom backgrounds | Liquid Glass guidelines |
| Onboarding | 4 steps + immediate permissions | 3 steps, deferred permissions |

## Notes

- This is a **visual prototype only** - no actual recording happens
- All data is mock data from `MockData.swift`
- Backend integration will be added in a future iteration
- Settings changes are persisted via `@AppStorage`

## Feedback

When testing, consider:
1. Does the layout feel spacious or cramped?
2. Are the colors consistent with macOS?
3. Is the terminology clear?
4. Are the transitions smooth?
5. Is keyboard navigation intuitive?
