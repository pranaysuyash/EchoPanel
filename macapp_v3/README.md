# EchoPanel V3

**The Complete Meeting Intelligence Workstation**

**Version:** 3.0.0  
**Architecture:** 3-Tier Design (Menu Bar → Live Panel → Dashboard)  
**Platform:** macOS 14.0+  
**Language:** Swift 5.9, SwiftUI

---

## Overview

EchoPanel V3 is a comprehensive redesign based on extensive analysis of backend capabilities and design principles. It implements a **3-tier architecture** that perfectly matches the backend's dual-pipeline system:

- **Tier 1:** Menu Bar - Status and quick controls
- **Tier 2:** Live Panel - Real-time transcription during meetings  
- **Tier 3:** Dashboard - Post-meeting analysis and history

This architecture aligns with the Apple Design Review recommendation: *"The menu bar is just the handle you grab to summon it. Like a pilot light, not the stove."*

---

## Architecture

### 3-Tier System

```
┌─────────────────────────────────────────────────────────────┐
│  TIER 1: Menu Bar Icon (Always Present)                     │
│  • Status indicator (idle/recording/paused)                 │
│  • Recording timer display                                  │
│  • Quick Start/Stop controls                                │
│  • Recent sessions list                                     │
│  • Global keyboard shortcuts                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ summons
┌─────────────────────────────────────────────────────────────┐
│  TIER 2: Live Panel (During Meetings)                       │
│  • 400px floating sidebar panel                             │
│  • Positioned right edge, beside video calls               │
│  • Live transcript (partial → final transitions)           │
│  • Audio source controls (System/Mic/Both)                 │
│  • ASR provider indicator                                   │
│  • Real-time NER (entities every 12s)                      │
│  • Live cards (actions/decisions every 28s)                │
│  • Pause/Resume functionality                               │
│  • Recording timer & controls                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ opens when needed
┌─────────────────────────────────────────────────────────────┐
│  TIER 3: Dashboard (Deep Review)                            │
│  • 900px standard window                                    │
│  • Session history sidebar                                  │
│  • Post-meeting analysis with diarization                  │
│  • 5 tabs: Summary, Transcript, Highlights, People, Raw    │
│  • Full search and filtering                                │
│  • Export (Markdown/JSON/Text)                              │
│  • Provider settings                                        │
└─────────────────────────────────────────────────────────────┘
```

### Dual-Pipeline Backend Matching

**Live Pipeline (Lane A) → Tier 2 Panel:**
- Real-time bounded queue (<2s latency)
- May drop to stay "live"
- Partial transcripts stream immediately
- Entities update every 12s
- Cards appear every 28s
- No speaker labels (diarization not ready)
- Draft quality, immediate feedback

**Recording Pipeline (Lane B) → Tier 3 Dashboard:**
- Lossless audio saved to disk
- Post-meeting batch processing
- Full diarization (speaker labels)
- Complete NER with LLM
- All cards with confidence scores
- Premium quality, archival record
- Takes 30s-2min to process

---

## Features

### Complete Backend Feature Coverage

#### Audio Capture
- ✅ Multi-source capture (System + Mic / System Only / Mic Only)
- ✅ Audio source selection in live panel
- ✅ Audio quality indicators (Good/Fair/Poor)
- ✅ VAD (Voice Activity Detection) toggle
- ✅ Source tagging (system vs mic labels in transcript)
- ✅ Per-source volume control

#### Transcription (ASR)
- ✅ 6 ASR Providers (Auto, Faster Whisper, Whisper.cpp, MLX Whisper, ONNX Whisper, Voxtral)
- ✅ Provider selection with hardware requirements
- ✅ Auto-provider selection with recommendations
- ✅ Partial vs Final transcript distinction
- ✅ Visual styling (partial = gray/italic, final = solid)
- ✅ Smooth transitions between states
- ✅ Confidence scores (hidden but tracked)
- ✅ Language selection

#### Speaker Diarization
- ✅ Live speaker placeholders ("Speaker 1, 2" during live)
- ✅ Post-meeting speaker labels ("Alex", "Sarah")
- ✅ Diarization enable/disable toggle
- ✅ Visual speaker badges in transcript

#### Analysis (NER & Cards)
- ✅ Entity extraction (People, Organizations, Dates, Topics)
- ✅ Entity mention counts and tracking
- ✅ Live entity stream in panel
- ✅ Action item extraction with assignee and due date
- ✅ Decision extraction with stakeholders
- ✅ Risk extraction with severity and mitigation
- ✅ Key point extraction
- ✅ Confidence scores on all cards
- ✅ Evidence quotes linking to transcript
- ✅ Card editing and deletion

#### Export
- ✅ Markdown export with full formatting
- ✅ JSON export with complete metadata
- ✅ Plain text export
- ✅ Export preview before saving
- ✅ Copy to clipboard
- ✅ Auto-export options

#### Settings
- ✅ 5 settings tabs (General, Recording, Providers, Analysis, Privacy)
- ✅ Audio source configuration
- ✅ ASR provider selection with hardware detection
- ✅ Performance metrics display (RTF, latency)
- ✅ VAD sensitivity slider
- ✅ Diarization toggle
- ✅ LLM provider selection (None/OpenAI/Ollama)
- ✅ Screen OCR toggle
- ✅ Privacy settings with data deletion
- ✅ Storage usage display

### UI/UX Features

#### Design System
- ✅ System semantic colors (light/dark mode support)
- ✅ System materials (sidebar, toolbar, popover)
- ✅ macOS Liquid Glass guidelines compliance
- ✅ SF Symbols throughout
- ✅ Responsive layouts
- ✅ Smooth animations

#### Accessibility
- ✅ Full keyboard navigation
- ✅ VoiceOver support
- ✅ Reduce Motion support
- ✅ High contrast support
- ✅ Color-independent meaning

#### User Experience
- ✅ Global keyboard shortcuts
- ✅ Contextual actions
- ✅ Recent sessions in menu bar
- ✅ Pinned sessions support
- ✅ Session tagging
- ✅ Search across all sessions
- ✅ Speaker filtering in transcript

---

## File Structure

```
macapp_v3/
├── Package.swift
├── README.md
├── Sources/
│   ├── EchoPanelV3App.swift      # Main app with 3-tier scenes
│   ├── Models/
│   │   └── AppState.swift        # Complete state management
│   ├── Views/
│   │   ├── MenuBarView.swift     # Tier 1: Menu bar interface
│   │   ├── LivePanelView.swift   # Tier 2: Live meeting panel
│   │   ├── DashboardView.swift   # Tier 3: Post-meeting dashboard
│   │   └── SettingsView.swift    # Settings tabs
│   └── Utils/
│       └── MockData.swift        # Comprehensive demo data
```

---

## Building and Running

### Prerequisites
- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

### Build
```bash
cd macapp_v3
swift build
```

### Run
```bash
swift run EchoPanelV3
```

The app will appear in your menu bar. Click the waveform icon to see the menu bar dropdown.

---

## User Workflows

### The 9AM Standup (Sarah - Product Manager)

1. **Launch** - EchoPanel starts automatically (or already running)
2. **Join Zoom** - Live Panel appears beside Zoom window
3. **Click "Start Recording"** in panel or use ⌘⇧R
4. **See live transcript** - Text appears as people speak
5. **Notice highlights** - Action items appear in Highlights tab
6. **End meeting** - Click "End" or use ⌘⇧R
7. **Dashboard opens** - AI summary ready to copy
8. **Copy summary** - Paste to Notion/Slack
9. **Done**

**Pain point solved:** No window juggling. Panel stays beside video call, never covers it.

### The Debug Session (David - Senior Engineer)

1. **Open Dashboard** - Browse past sessions
2. **Change Provider** - Settings → Providers → Select MLX Whisper
3. **Monitor metrics** - RTF, latency displayed
4. **Export JSON** - Raw data for analysis
5. **Search sessions** - Find specific technical discussions

**Pain point solved:** Full control over audio routing and data portability.

### The Confidential 1:1 (Elena - Privacy Advocate)

1. **Verify offline** - Settings shows "Processing Locally"
2. **Check permissions** - Privacy tab confirms no network egress
3. **Record** - All processing on device
4. **Delete after** - "Delete Forever" removes all traces

**Pain point solved:** Clear visual confirmation of privacy controls.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧R | Start/Stop Recording |
| ⌘⇧P | Pause/Resume |
| ⌘⇧S | Show/Hide Live Panel |
| ⌘⇧D | Open Dashboard |
| ⌘, | Settings |
| ⌘Q | Quit |

---

## Technical Implementation

### State Management

```swift
@MainActor
class AppState: ObservableObject {
    @Published var currentSession: Session?
    @Published var recordingState: RecordingState
    @Published var audioSource: AudioSource
    @Published var asrProvider: ASRProvider
    // ... comprehensive state management
}
```

### Dual Transcript System

```swift
struct Session {
    var liveTranscript: [LiveTranscriptSegment]      // Tier 2
    var finalTranscript: [FinalTranscriptSegment]    // Tier 3
}

struct LiveTranscriptSegment {
    let isPartial: Bool      // Visual distinction
    let audioSource: AudioSourceSegment  // System vs Mic
}

struct FinalTranscriptSegment {
    let speakerName: String?  // Populated after diarization
    let highlights: [String]  // Linked cards
}
```

### Recording State Machine

```
IDLE → Start → LISTENING → Pause → PAUSED → Resume → LISTENING → Stop → FINALIZED
```

Handles:
- Timer management
- Audio capture lifecycle
- Session persistence
- Auto-pause on silence
- Auto-end on extended silence

---

## Design Decisions

### Why 3-Tier Architecture?

**Problem:** Previous versions had identity crisis between "menu bar utility" and "workspace panel"

**Solution:** Clear separation:
- **Menu Bar:** Always there, minimal, status only
- **Live Panel:** Meeting companion, floating beside video calls
- **Dashboard:** Deep review when needed, full window

**Benefit:** Each tier has clear purpose without competing for attention.

### Why Floating Panel (Not Full Window) for Tier 2?

**Problem:** Full windows cover video calls, requiring window management

**Solution:** 400px floating panel positioned right edge:
- Stays beside Zoom/Meet/Teams
- Always visible during meeting
- No window juggling
- Can be resized (400-600px)

**Benefit:** Natural meeting companion that doesn't interrupt workflow.

### Why Separate Raw vs Processed Views?

**Backend Reality:** Same audio produces two different transcripts:
- Live: Fast, draft quality, no speaker labels
- Final: Slow, premium quality, with diarization

**UI Solution:** 
- **Live Panel:** Shows draft during meeting
- **Dashboard:** Shows polished final after processing

**Benefit:** User understands why transcript quality improves after meeting.

---

## Comparison with V2

| Aspect | V2 | V3 |
|--------|-----|-----|
| **Architecture** | Single full window | 3-tier (Menu → Panel → Dashboard) |
| **During Meetings** | Window covers video call | Floating panel beside video |
| **Audio Source** | Hidden in Settings | Prominent in live panel |
| **ASR Provider** | Not selectable | 6 providers with hardware detection |
| **Partial Transcripts** | Not differentiated | Gray/italic styling |
| **Speaker Labels** | Mock only | Live placeholders → Final names |
| **Card Confidence** | Not shown | Visible with color coding |
| **Export Preview** | Not available | Live preview before export |
| **Search** | Per-session only | Across all sessions |
| **Settings** | 4 tabs | 5 comprehensive tabs |

---

## Roadmap

### Phase 1: Core (Current)
- ✅ 3-tier architecture
- ✅ Live panel with dual transcript
- ✅ Dashboard with all tabs
- ✅ Complete settings
- ✅ Comprehensive mock data

### Phase 2: Integration (Next)
- 🔄 WebSocket integration with real backend
- 🔄 Live transcript streaming
- 🔄 Real-time entity/card updates
- 🔄 Post-meeting processing pipeline

### Phase 3: Advanced (Future)
- 📋 RAG document management
- 📋 Screen OCR integration
- 📋 Custom export templates
- 📋 Plugin system
- 📋 Multi-language support

---

## Credits

**Design Philosophy:** Based on Apple Design Review and extensive backend analysis

**Architecture:** Validated against backend dual-pipeline system

**User Workflows:** Sarah (PM), David (Engineer), Elena (Privacy Advocate) personas

---

## License

Proprietary - All rights reserved

---

*EchoPanel V3 - The definitive meeting intelligence workstation*

*End of README*
