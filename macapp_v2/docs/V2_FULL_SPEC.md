# EchoPanel v2 — Full UI Spec

> **Status:** This is what v2 WILL become. Not started yet.
> **Build philosophy:** Complete mock UI first, wire backend second.

---

## Vision

EchoPanel v2 is the macOS menu-bar app that captures, understands, and surfaces everything said in your work life. Not just meetings — voice notes, screen recordings, injected audio, everything. The most comprehensive audio intelligence layer ever put on a Mac.

The UI is the brain. Everything spoken becomes searchable, actionable, and shareable.

---

## Use Cases Covered

### UC-1: Meeting Capture (Core)
- Start/stop from menu bar or hotkey
- System audio capture (what your Mac plays)
- Microphone capture (your voice)
- Both simultaneously with voice-diarization
- Live transcript with speaker labels
- Live highlights: actions, decisions, key points
- Live people tracking (who said what)
- Auto-save to session history

### UC-2: Voice Notes
- Quick capture hotkey → voice note
- Instant transcription
- Auto-categorization (tagged as "voice note")
- Searchable in session history
- Text or audio storage

### UC-3: Screen Recording + Transcript
- Record screen (with audio) alongside transcript
- OCR on screen content
- Sync transcript to screen recording timeline
- Export as video with burned-in captions

### UC-4: Live Captions (accessibility)
- Real-time captions for any app/window
- Follow-along mode (large text overlay)
- Pip mode (floating always-on-top mini captions)
- Language detection

### UC-5: Multi-Language & Translation
- Real-time translation of transcript
- Toggle between original and translated
- Export in original or translated language
- Support: English, Hindi, Kannada, Tamil, Telugu + 20 more

### UC-6: Post-Meeting Review
- Full transcript with speaker timeline
- AI summary (what was discussed, key decisions)
- Action items extracted and assignable
- MoA (Minutes of Meeting) format
- Highlights organized by type
- Share as PDF, Notion, or link

### UC-7: Session History & Search
- All past sessions searchable
- Full-text search within transcripts
- Filter by: date, duration, participants, tags
- Delete, export, rename sessions
- Bulk export

### UC-8: Team Sharing
- Share session transcript with teammates
- Collaborative annotations on transcript
- Thread comments on specific segments
- Shared team library of sessions
- Permission controls (view/comment/edit)

### UC-9: Calendar Integration
- Auto-detect meetings from calendar
- Pre-session briefing (agenda + relevant past sessions)
- Auto-start recording on meeting join
- Post-session auto-email summary

### UC-10: Analysis & Insights
- Brain Dump: search across all your sessions (RAG-based)
- Topic trends over time
- People tracking (who you talk to most)
- Decision tracker (all decisions across sessions)
- Personal knowledge graph

### UC-11: Integrations
- Slack: post summaries to channels
- Notion: append session to a Notion page
- Calendar: Google Calendar, Apple Calendar
- Zoom/Teams/Meet: auto-join and capture
- Zapier/Make: webhook triggers
- API: build on EchoPanel

### UC-12: On-Device AI
- Local transcription (no cloud)
- Local summarization
- Local embedding/similarity search
- MLX-powered (Apple Silicon)
- Whisper.cpp running locally
- Falls back to cloud when offline

### UC-13: Subscription & Billing
- Free: 5 sessions/month, 10 min max each
- Pro: Unlimited sessions, unlimited length, exports
- Team: Shared library, admin controls
- Enterprise: Self-hosted backend option

### UC-14: Settings & Configuration
- Audio source selection (mic/system/both)
- ASR provider selection (cloud/local/hybrid)
- Language settings
- Storage management
- Privacy controls (what gets stored, what gets deleted)
- Hotkey customization
- Startup behavior

### UC-15: Demo / Onboarding
- 4-step onboarding (install → mic → system audio → first recording)
- Demo mode (plays fake session)
- Tooltips and keyboard shortcuts cheatsheet
- Sample sessions to explore

### UC-16: Notifications
- "Recording started" notification
- "Action item assigned to you" notification
- "Summary ready" notification
- "Meeting detected" calendar notification

### UC-17: Export
- PDF (transcript + highlights + summary)
- Markdown
- Plain text
- JSON (structured data)
- SRT (subtitles format)
- Calendar event (add action items to calendar)
- Notion page
- Email

### UC-18: Flow Studio (Scenario Engine)
- Pre-built scenarios: Standup, Escalation, Hiring, Launch
- Each scenario: custom mock transcript, highlights, people
- Future: scenario-based recording with guided prompts

---

## Screen Map

```
┌─────────────────────────────────────────────────────────┐
│  Menu Bar Icon                                          │
│  ├── Recording indicator (idle/recording/paused)        │
│  ├── Timer display                                     │
│  └── Recent sessions (last 5)                          │
└─────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│  Main Panel (floating, always-on-top capable)           │
│                                                          │
│  ┌──────────┬──────────────────────────────────────┐   │
│  │ Sidebar  │  Content Area                         │   │
│  │          │                                        │   │
│  │ [Live]   │  Live View / Review View / etc.       │   │
│  │ [Review] │                                        │   │
│  │ [History]│                                        │   │
│  │ [Brain]  │                                        │   │
│  │ [Flow]   │                                        │   │
│  │ [Settings]│                                       │   │
│  │          │                                        │   │
│  │ [──────] │                                        │   │
│  │ [License]│                                        │   │
│  └──────────┴──────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Screens

### S1: Menu Bar
**What:** The dropdown from the menu bar icon

**States:**
- Idle: mic icon (gray)
- Recording: mic icon (red, pulsing)
- Paused: mic icon (yellow)
- Error: mic icon (red, X)

**Contents:**
- Current recording status + timer
- Start Recording / Pause / Stop
- Recent Sessions (last 5)
- Open Panel
- Settings
- Quit

**Keyboard shortcut hint:** ⌘⇧R (recording), ⌘⇧P (panel)

---

### S2: Live View
**What:** Real-time view during recording

**Sections:**
- Toolbar: always-on-top toggle, pause, stop, recording indicator
- Highlights tab: live stream of actions, decisions, key points
- Transcript tab: scrollable live transcript cards
- People tab: who's speaking, topic per person
- Summary tab: running summary (updated incrementally)

**Transcript Card:**
```
┌─────────────────────────────────────────────────────┐
│ [👤 Sarah Chen]  [10:34 AM]              [✓ action] │
│ "We need to ship the API by Friday or the launch   │
│  gets pushed."                                      │
└─────────────────────────────────────────────────────┘
```
- Speaker name
- Timestamp
- Text
- Action item badge (if applicable)
- Pinned indicator (if applicable)

**Highlight Card:**
```
┌─────────────────────────────────────────────────────┐
│ [⚡ Action]          [10:34 AM]                     │
│ Alex Kim: Complete API migration testing             │
└─────────────────────────────────────────────────────┘
```

---

### S3: Review View
**What:** Post-session analysis

**Sections:**
- Summary (AI-generated, full text)
- Stats bar: duration, speakers, transcript items, action items
- Tab: Highlights / Transcript / People / MoA
- Export button (top right)
- Share button

**People Card:**
```
┌─────────────────────────────────────────────────────┐
│ Sarah Chen                                          │
│ 12 mentions · 3 topics                              │
│ Topics: API migration, Launch blockers, Testing      │
└─────────────────────────────────────────────────────┘
```

**MoA Format:**
```
MINUTES OF MEETING — Team Standup
Date: March 19, 2026 | Duration: 30 min
Attendees: Sarah Chen, Alex Kim, Priya Sharma, James Wu

DISCUSSION POINTS
1. API Migration Status
   - Alex: Testing complete by Friday
   - Decision: Ship regardless of edge cases (ACTION: Alex)

2. Launch Blockers
   - Sarah: 3 P0 bugs remaining
   - ACTION: James to triage by EOD

NEXT STEPS
- [ ] Alex: Ship API by Friday
- [ ] James: Triage P0 bugs
- [ ] Sarah: Update stakeholders
```

---

### S4: History View
**What:** All past sessions

**Features:**
- Search bar (full-text across transcripts)
- Filter chips: date range, duration, has-action-items
- Session list: title, date, duration, participant avatars
- Bulk select + bulk delete
- Sort: newest, oldest, longest

**Session Card:**
```
┌─────────────────────────────────────────────────────┐
│ Team Standup                    2 hrs ago  32:45   │
│ 4 people · 3 action items                            │
│ Sarah, Alex, Priya, James                           │
│                                                         │
│ [▶ Play] [Export ▾] [⋯]                             │
└─────────────────────────────────────────────────────┘
```

---

### S5: Brain Dump View
**What:** Semantic search across all sessions (RAG)

**Features:**
- Search bar (natural language: "what did we decide about the API?")
- Results show session + transcript snippet
- "Ask a follow-up" (chat with your session history)
- Topic cloud
- People graph

---

### S6: Flow Studio View
**What:** Scenario-driven UX + mock data explorer

**Scenarios:**
1. Team Standup
2. Customer Escalation
3. Hiring Debrief
4. Launch War Room

**For each scenario:**
- Mock transcript that plays in real-time
- Mock highlights stream
- Mock people data
- Session summary
- Mock sessions list

**Controls:**
- Play/Pause/Stop
- Scenario selector
- Speed control (0.5x, 1x, 2x)
- "Load into live session" button

---

### S7: Settings View
**Tabs:**

**General:**
- Launch at login (toggle)
- Show in Dock (toggle)
- Always on top (toggle)
- Keyboard shortcuts (customizable)
- Appearance: System / Light / Dark

**Recording:**
- Audio source: System Audio / Microphone / Both
- Voice detection threshold (slider)
- Auto-export on stop (toggle)
- Auto-start on app launch (toggle)
- Max session length (dropdown: 30m / 1h / 2h / unlimited)
- Noise cancellation (toggle)

**Analysis:**
- ASR Provider: Cloud (OpenAI) / Local (Whisper.cpp) / Hybrid
- Language: Auto-detect / English / [specific]
- Summary style: Brief / Detailed / Bullet points
- Live analysis (toggle — show highlights while recording)
- Diarization (toggle — speaker detection)

**Privacy:**
- Auto-delete sessions older than (dropdown: Never / 30d / 90d / 1yr)
- Local-only mode (toggle — never sends to cloud)
- Include audio in exports (toggle)
-麦克风 permissions status
- System audio permissions status

**Storage:**
- Total storage used (bar chart)
- Per-session breakdown
- Clear all data (button)
- Export all data (button)

**Accounts:**
- Sign in with Apple / Google
- Subscription status
- Team management (Pro+)
- Billing portal (link)

**About:**
- Version
- Build number
- Check for updates
- Acknowledgements
- Support link

---

### S8: License / Upgrade View
**What:** Subscription upsell and management

**Sections:**
- Current plan: Free / Pro / Team
- Usage this month: X/5 sessions (Free)
- Upgrade CTA with feature comparison
- Restore purchases
- Terms / Privacy links

---

### S9: Onboarding View
**Steps:**
1. Welcome → what EchoPanel does
2. Microphone → request mic permission
3. System Audio → request screen recording permission (for system audio)
4. First Recording → do one test recording

---

### S10: Demo Mode View
**What:** Plays a fake session for users who want to explore before recording

**Behavior:**
- Shows a complete mock session (Flow Studio data)
- User can click "Start Demo" → plays like a live recording
- Shows all UI states without needing microphone/system audio

---

## Component Library

### TranscriptCard
- States: default, highlighted (speaker changed), action-item, pinned, playing
- Shows: speaker avatar placeholder, name, timestamp, text, badges
- Hover: pin button, copy button, share button

### HighlightCard
- Types: action (amber), decision (green), key-point (blue), question (purple)
- Shows: type icon, content, timestamp
- States: default, completed (for action items)

### PersonChip
- Shows: initials avatar, name, mention count
- Click: filters transcript to this person

### SessionCard (History)
- Shows: title, relative date, duration, participant count
- Actions: play audio, export, delete
- States: default, selected, playing

### TabBar
- macOS-style tabs: Highlights | Transcript | People | Summary | MoA
- Keyboard navigable

### RecordingToolbar
- Always-on-top toggle
- Mic level meter (live)
- Pause / Resume
- Stop
- Recording duration timer
- Live transcript word count

### SearchBar
- Full-text search
- Filter chips below
- Recent searches
- Voice input button

### SummaryCard
- AI summary text
- Generated timestamp
- Regenerate button
- Copy button

### FlowStudioCard
- Scenario icon + name + subtitle
- Live preview showing mock transcript streaming
- "Use Scenario" button

### AudioLevelMeter
- Real-time waveform or level bars
- Indicates current recording source

### SubscriptionBanner
- Inline upgrade prompt when free tier limit hit
- "Upgrade" CTA

### PermissionRequestCard
- Shown when permissions missing
- Icon + description + "Grant Access" button
- Link to System Preferences

### ExportMenu
- Dropdown: PDF / Markdown / Text / JSON / SRT / Calendar
- Progress indicator during export

---

## Technical Notes

### v2 is SwiftUI-native
- Full macOS Liquid Glass / Tahoe design guidelines
- System semantic colors
- Native materials (NSVisualEffectView behind panels)
- Respects system dark/light mode

### Backend Wiring (Phase 2)
- `AudioCaptureManager` → streams PCM via `WebSocketStreamer`
- `server/` → FastAPI receives stream, returns transcript events
- `HybridASRManager` → handles cloud vs local routing
- `SessionStore` → persists sessions (GRDB/SQLite)
- `SessionRAGStore` → RAG for Brain Dump search

### Onboarding Flow
- 4 steps: Welcome → Mic → System Audio → First Recording
- Deferred permissions (can skip, prompted later)
- System Preferences deep-links for permissions

### Local AI (MLX)
- `NativeMLXBackend` for on-device transcription
- `MLXAnalysisEngine` for summarization
- `MLXEmbeddingsEngine` for embeddings/similarity
- Requires macOS 14+, Apple Silicon
- Falls back to cloud (OpenAI) on Intel or older OS

---

## Open Questions

1. Calendar integration — which calendar APIs to support? (Google Calendar is free/easy, Apple Calendar requires entitlements)
2. Team sharing — server-side or peer-to-peer? (Server-side requires auth + database)
3. Zoom/Teams auto-join — requires platform-specific bot accounts
4. Self-hosted backend — should Team plan support this?
5. Video recording — is this in scope for v2 or v3?
