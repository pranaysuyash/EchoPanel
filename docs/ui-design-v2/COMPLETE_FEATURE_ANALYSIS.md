# EchoPanel V2 UI - Complete Feature Analysis & Design Rationale

**Date:** 2026-02-15  
**Status:** Comprehensive Analysis  
**Scope:** Full UI coverage of backend features, design philosophy, and UX rationale

---

## Executive Summary

The current V2 UI prototype is a **full window application** with sidebar navigation, but the **intended design** from the Apple Design Review is a **"companion panel"** - a floating workspace that lives alongside video conferencing apps. The menu bar is meant to be just a "handle" to summon the panel, not the primary interface.

**Current State:** Full window app (like Mail, Finder)  
**Intended State:** Floating companion panel (like Spotlight, Notification Center)

---

## Part 1: Backend Features → UI Coverage Analysis

### 1.1 Audio Capture Features

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Multi-source capture** (System + Mic) | Hidden in Settings | ⚠️ Missing | HIGH |
| **Source tagging** (system vs mic labels) | Not shown in transcript | ⚠️ Missing | HIGH |
| **Audio quality indicators** (Good/OK/Poor) | Not displayed | ❌ Missing | MEDIUM |
| **VAD (Voice Activity Detection)** | Toggle in Settings only | ⚠️ Partial | MEDIUM |
| **Silent audio detection** | Not shown | ❌ Missing | MEDIUM |
| **Dual-lane pipeline** (Recording lane) | No UI indication | ❌ Missing | LOW |
| **Debug audio dump** | No UI | ❌ Missing | LOW |

**Gap Analysis:** Audio source selection should be prominent in the live panel, not buried in Settings. Users need to see which sources are active during recording.

### 1.2 Transcription Features (ASR)

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Multiple ASR providers** (6 providers) | Not selectable | ❌ Missing | HIGH |
| **Auto-provider selection** | No indication | ❌ Missing | MEDIUM |
| **Model size selection** (tiny→large) | Not exposed | ❌ Missing | MEDIUM |
| **Language selection** | Basic dropdown in Settings | ⚠️ Partial | MEDIUM |
| **Partial transcripts** (live updates) | Not differentiated | ❌ Missing | HIGH |
| **Final transcripts** | Shown | ✅ Implemented | - |
| **Confidence scores** | Not displayed | ❌ Missing | LOW |
| **Source attribution** (system vs mic) | Not shown | ❌ Missing | HIGH |

**Gap Analysis:** Provider selection is a key power-user feature. Should have a "Performance" or "Engine" section in Settings with visual indicators of what's being used.

### 1.3 Speaker Diarization

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Speaker segmentation** | Not shown | ❌ Missing | HIGH |
| **Multi-source diarization** | Not shown | ❌ Missing | HIGH |
| **Speaker label assignment** | Mock data only | ⚠️ Partial | HIGH |
| **Diarization configuration** | No UI | ❌ Missing | MEDIUM |
| **Pre-warming status** | Not shown | ❌ Missing | LOW |

**Gap Analysis:** Diarization is a major feature that needs UI - speaker labels in transcript, confidence indicators, ability to merge/split speakers.

### 1.4 Analysis Features

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Entity extraction** (People, Orgs, Dates) | Mock data | ⚠️ Partial | HIGH |
| **Entity counts** | Shown | ✅ Implemented | - |
| **Entity recency tracking** | Not shown | ❌ Missing | LOW |
| **Grounding quotes** | Not shown | ❌ Missing | MEDIUM |
| **Action items** | Shown | ✅ Implemented | - |
| **Decisions** | Mock data | ⚠️ Partial | HIGH |
| **Risks** | Not shown | ❌ Missing | MEDIUM |
| **Due date parsing** | Not shown | ❌ Missing | HIGH |
| **LLM-powered analysis** | No UI | ❌ Missing | MEDIUM |
| **LLM provider selection** (OpenAI/Ollama) | Not exposed | ❌ Missing | MEDIUM |

**Gap Analysis:** Cards (Actions/Decisions/Risks) need more detail - confidence scores, evidence quotes, ability to edit/dismiss.

### 1.5 Export Features

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **JSON Export** | Dialog exists | ✅ Implemented | - |
| **Markdown Export** | Dialog exists | ✅ Implemented | - |
| **Plain Text Export** | Not offered | ⚠️ Missing | MEDIUM |
| **Auto-save** | No indication | ❌ Missing | MEDIUM |
| **Session recovery** | Not shown | ❌ Missing | LOW |

**Gap Analysis:** Export is covered but could be enhanced with preview, format options, and auto-save indicators.

### 1.6 RAG (Document Management)

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Document indexing** | No UI | ❌ Missing | MEDIUM |
| **Document listing** | No UI | ❌ Missing | MEDIUM |
| **Document search** (Lexical/Semantic) | No UI | ❌ Missing | MEDIUM |
| **Hybrid reranking** | No UI | ❌ Missing | LOW |
| **Context injection** | No UI | ❌ Missing | MEDIUM |

**Gap Analysis:** RAG is a planned v0.4 feature but needs a "Documents" section in the sidebar for managing indexed docs.

### 1.7 Screen OCR

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Frame capture** | No UI | ❌ Missing | MEDIUM |
| **OCR toggle** | Not in Settings | ❌ Missing | MEDIUM |
| **Perceptual hashing** | No UI | ❌ Missing | LOW |
| **Auto-indexing** | No UI | ❌ Missing | LOW |

**Gap Analysis:** OCR needs a toggle in Settings and visual indicators when slides are captured.

### 1.8 Settings & Configuration

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Environment variables** | Not exposed | ❌ Missing | LOW |
| **Provider auto-detection** | Not shown | ❌ Missing | MEDIUM |
| **Hardware profiling** | Not shown | ❌ Missing | MEDIUM |
| **Degrade ladder status** | Not shown | ❌ Missing | LOW |

**Gap Analysis:** Settings need a "System" or "Advanced" tab showing detected capabilities and recommended settings.

### 1.9 Metrics & Observability

| Backend Feature | Current UI | Status | Priority |
|-----------------|------------|--------|----------|
| **Realtime Factor (RTF)** | Not shown | ❌ Missing | MEDIUM |
| **Inference latency** | Not shown | ❌ Missing | LOW |
| **Queue metrics** | Not shown | ❌ Missing | LOW |
| **Drop statistics** | Not shown | ❌ Missing | LOW |
| **Provider health** | Not shown | ❌ Missing | MEDIUM |
| **Model health** | Not shown | ❌ Missing | MEDIUM |

**Gap Analysis:** Power users need a "Performance" or "Diagnostics" view showing real-time metrics.

### 1.10 Planned/In-Progress Features

| Feature | Status | UI Need |
|---------|--------|---------|
| **Live diarization** (currently session-end only) | Backend ready | Real-time speaker labels |
| **Visual Memory RAG** (v0.4) | Planned | Frame/slide timeline |
| **Vector Storage (LanceDB)** (v0.3) | Planned | Enhanced document search |
| **Multi-language support** | Planned | Language switching |
| **Caption Extension** | Planned | System extension UI |

---

## Part 2: UI Feature Inventory - What's Missing

### Critical Missing Features (Must Have)

1. **Audio Source Selector**
   - Toggle between System/Mic/Both
   - Visual indicator of which sources are active
   - Per-source volume/quality indicators

2. **ASR Provider Selection**
   - Visual list of available providers
   - Auto-detection with recommendations
   - Performance indicators (speed/accuracy)

3. **Real-time Speaker Labels**
   - Live diarization display
   - Ability to rename speakers
   - Speaker confidence indicators

4. **Live Transcript Differentiation**
   - Partial vs final text styling
   - Confidence highlighting
   - Source attribution (system vs mic)

5. **Card Detail View**
   - Confidence scores
   - Evidence quotes
   - Edit/delete actions
   - Due dates for action items

### Important Missing Features (Should Have)

6. **Performance Dashboard**
   - RTF indicator
   - Queue depth
   - Provider status
   - Degrade level

7. **Document Management (RAG)**
   - Index new documents
   - Search indexed docs
   - Context injection toggle

8. **Screen OCR Controls**
   - Enable/disable toggle
   - Capture frequency
   - Visual capture indicators

9. **LLM Settings**
   - Provider selection (OpenAI/Ollama/None)
   - Model selection
   - API key management

10. **Advanced Audio Settings**
    - VAD sensitivity slider
    - Chunk size configuration
    - Audio quality thresholds

### Nice to Have Features

11. **Session Timeline Visualization**
12. **Audio Waveform Display**
13. **Keyboard Shortcut Customization**
14. **Custom Export Templates**
15. **Plugin/Extension Support**

---

## Part 3: Design Philosophy - App vs Panel

### The Identity Crisis (From Design Review)

**Original Problem:**
EchoPanel suffered from an identity crisis between two incompatible contracts:

- **Contract A (Menu Bar Utility):** "I will never demand attention. I will not ask you to manage windows."
- **Contract B (Workspace Panel):** "I am part of your working context. I will hold state."

**Apple Design Review Verdict:**
> "EchoPanel should commit to being a **workspace panel app that happens to live in the menu bar for convenience and status** — not the other way around."

> "The menu bar is just the handle you grab to summon it. Like a pilot light, not the stove."

### Current V2 Implementation Analysis

**What I Built:**
- Full window application with sidebar
- Like Mail, Finder, or Safari
- Takes over the screen
- Requires window management

**What's Wrong With This:**
1. **Covers the meeting** - User can't see Zoom/Teams while using EchoPanel
2. **Context switching** - User must manage windows instead of focusing on meeting
3. **Window Juggling** (Sarah's pain point) - Large window covers video call
4. **Menu bar as primary** - I made the menu bar the main interface, but it should be secondary

### Intended Design: The Companion Panel

**The Vision:**
EchoPanel is a **"companion panel"** or **"meeting intelligence workstation"** - a floating workspace that lives alongside video conferencing apps.

**Key Characteristics:**

1. **Always Visible During Meetings**
   - Floats beside Zoom/Meet/Teams
   - Not minimized or hidden
   - Provides continuous value

2. **Three Sizing Presets:**
   - **Narrow** (360-420pt): Minimal distractions, live Roll
   - **Medium** (520-640pt): Best default for most monitors
   - **Wide** (760-900pt): Deep review, search, RAG

3. **Panel Placement:**
   - First-run: Right edge with 20pt margin, Medium preset
   - Return visits: Restore last position/size per display
   - Multi-monitor: Appears on display where recording started

4. **Window Hierarchy:**
   ```
   Primary: Floating panel (Live/Review)
   Secondary: Menu bar (status + quick controls)
   Tertiary: History window (when needed)
   ```

### Why This Matters for the Use Case

**The User Workflow:**

**Sarah (Product Manager) - The 9AM Standup:**
```
1. Launch EchoPanel (or it's already running)
2. Join Zoom
3. EchoPanel panel appears automatically (or is already there)
4. Click "Start Recording" in panel
5. Continue focusing on Zoom - panel is beside, not covering
6. See live transcript scrolling in peripheral vision
7. End meeting → Summary appears in same panel
8. Copy summary → Paste to Notion
9. Done
```

**The Anti-Pattern (Current V2):**
```
1. Launch EchoPanel
2. Full window opens, covers everything
3. Resize/move window to see Zoom
4. Click menu bar
5. Click "Open Panel"
6. Another window appears
7. Window management nightmare
8. User gives up
```

### Recommended Redesign

**Option A: Floating Panel (Recommended)**
- Single floating panel window
- No sidebar - use tabs or segmented control
- Resizable with presets
- Positioned beside video call
- Menu bar just for status + quick start/stop

**Option B: Menu Bar Popover (Not Recommended)**
- Would require extreme minimalism
- Hard to fit all features
- Contradicts "workspace panel" philosophy

**Option C: Hybrid (Best of Both)**
- **Recording Mode:** Compact floating panel (Narrow preset)
- **Review Mode:** Can expand to Medium/Wide or open separate History window
- **Settings:** Standard macOS Settings window

---

## Part 4: User Personas & Workflows

### Three Core Personas

**1. Sarah - The Busy Product Manager**
- **Needs:** Meeting notes immediately to paste into Slack/Notion
- **Wants:** App to "just work" in the background
- **Pain Point:** "Window Juggling" — large window covers Zoom screen
- **Key Scenario:** "The 9AM Standup"
- **Workflow:** Launch → Join Zoom → Start Recording → Minimize (but see live) → Copy Summary → Quit

**2. David - The Senior Engineer**
- **Needs:** Complete control over audio routing, keyboard-only navigation, data portability
- **Wants:** Technical details, JSON export, hardware monitoring
- **Pain Point:** "Context Switching" — has to leave app to search PDF specs
- **Key Scenario:** "The Debug Session"
- **Workflow:** Change Model → Monitor Entities → Export JSON → Analyze

**3. Elena - The Privacy Advocate / Consultant**
- **Needs:** Zero network egress, clear visual confirmation, kill switch
- **Wants:** Offline mode, local-only indicators, delete forever
- **Pain Point:** Trust and verification
- **Key Scenario:** "The Confidential 1:1"
- **Workflow:** Verify Offline Mode → Check "Processing Locally" → Record → Delete Forever

### Universal Workflow Requirements

**Recording Session Lifecycle:**
```
IDLE → Start → LISTENING → Pause → PAUSED → Resume → LISTENING → Stop → FINALIZED
```

**Silence Handling:**
| Duration | UI Action |
|----------|-----------|
| 10-30s | Orange banner |
| 30s-5min | "Still listening?" toast |
| 5-30min | Auto-pause with notification |
| 30min+ | Auto-end & save |

---

## Part 5: Recommended UI Architecture

### Window Structure

```
EchoPanel
├── Main Panel (Floating, resizable)
│   ├── Header (Title, Timer, Status)
│   ├── Tab Bar (Summary | Transcript | Highlights | People)
│   ├── Content Area
│   └── Footer (Audio Source, Provider Status)
├── Menu Bar (Status icon + dropdown)
│   ├── Quick Start/Stop
│   ├── Recent Sessions
│   └── Settings shortcut
└── History Window (Optional, standard window)
    ├── Session list
    └── Search/filter
```

### Panel States

**State 1: Idle/Welcome**
- "Ready to record" message
- Big "Start Recording" button
- Recent sessions list (last 3)
- Quick settings (audio source)

**State 2: Recording (Live)**
- Timer display
- Live transcript (auto-scrolling)
- Current highlights (floating or sidebar)
- Audio level indicators
- Stop button

**State 3: Review**
- Full session data
- All tabs active
- Export buttons
- Edit capabilities

### Key UI Principles

1. **"Boring is Premium"**
   - Standard macOS window chrome
   - No custom title bars or weird shapes
   - Predictable behavior

2. **"If you have to explain it in a tooltip, it's wrong"**
   - "Highlights" not "Surfaces"
   - "People & Topics" not "Entities"
   - Clear, guessable names

3. **Primary Object: The Session**
   - Everything relates to the transcript
   - No orphan features
   - Contextual actions only

4. **Deferred Permissions**
   - Ask for microphone when user clicks "Record"
   - Not during onboarding
   - Feels like "tool requesting capability" not "surveillance onboarding"

---

## Part 6: Implementation Roadmap

### Phase 1: Core Panel (Current Priority)
- [ ] Redesign as floating panel (not full window)
- [ ] Add audio source selector to live panel
- [ ] Show partial vs final transcript differently
- [ ] Add real-time speaker labels
- [ ] Implement Narrow/Medium/Wide presets

### Phase 2: Power User Features
- [ ] ASR provider selection UI
- [ ] Performance dashboard (RTF, latency)
- [ ] Diarization controls
- [ ] Advanced audio settings

### Phase 3: Intelligence Features
- [ ] Document management (RAG)
- [ ] Screen OCR toggle
- [ ] LLM settings and status
- [ ] Context injection

### Phase 4: Polish
- [ ] Keyboard shortcut customization
- [ ] Custom themes/accent colors
- [ ] Export templates
- [ ] Plugin system

---

## Conclusion

The current V2 UI is a **functional demonstration** of features but has the **wrong form factor**. It's built as a full application when it should be a **companion panel**.

**Key Takeaways:**

1. **Form Factor:** Change from full window to floating panel
2. **Position:** Right edge, beside video calls, not covering them
3. **Hierarchy:** Panel is primary, menu bar is secondary
4. **Missing Features:** Audio source, provider selection, real-time speaker labels are critical gaps
5. **User Workflow:** Must support continuous visibility during meetings

**Next Steps:**
1. Redesign current UI as floating panel
2. Add critical missing features (audio source, providers, speakers)
3. Test with the "9AM Standup" scenario
4. Iterate based on window management experience

The UI should feel like a **second monitor** for your meetings, not another app to manage.

---

## Part 7: Validated 3-Tier Architecture (New Findings)

**Date Added:** 2026-02-15  
**Context:** Architecture validation against backend dual-pipeline system

### 7.1 The Architecture That Matches Backend

After detailed analysis of the backend code, a **3-tier architecture** emerges as the optimal design:

```
┌─────────────────────────────────────────────────────────────┐
│  TIER 1: Menu Bar Icon (Always Present)                     │
│  • Status indicator (idle/recording/paused)                 │
│  • Quick controls (Start/Stop/Pause)                        │
│  • Recent sessions access                                   │
│  • Settings shortcut                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ summons
┌─────────────────────────────────────────────────────────────┐
│  TIER 2: Sidebar Panel (During Meetings)                    │
│  • Live transcript (streaming partials → finals)           │
│  • Live NER (entities extracted every 12s)                 │
│  • Live cards (actions/decisions every 28s)                │
│  • Audio source controls                                   │
│  • Recording timer & pause/resume                          │
│  • Quick pins                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ opens when needed
┌─────────────────────────────────────────────────────────────┐
│  TIER 3: Full Dashboard (Deep Review)                       │
│  • Post-meeting analysis (diarization, full NER)           │
│  • Session history & search                                │
│  • Raw transcript view                                     │
│  • Export options (JSON/Markdown/Text)                     │
│  • RAG document management                                 │
│  • Performance metrics                                     │
│  • Provider/Model settings                                 │
└─────────────────────────────────────────────────────────────┘
```

**Key Insight:** This architecture perfectly matches the backend's **dual-lane pipeline** design.

### 7.2 Tier 2 = Live Pipeline (Lane A)

**Backend:** Real-time bounded queue, <2s latency, may drop to stay live  
**UI:** Sidebar panel showing live transcript with incremental updates

**Live Analysis Cycle:**
- **ASR Streaming:** `asr_partial` → `asr_final` progression every ~2s
- **Entity Extraction:** Incremental update every **12 seconds** (minimum)
- **Card Extraction:** Actions/decisions/risks every **28 seconds** (minimum)
- **Metrics:** Health telemetry every **1 second**

**What This Means for UI:**
- Partial transcripts should appear **immediately** (grayed/italic)
- Final transcripts **replace** partials with solid styling
- Entities update in **bursts** every 12s (not continuous)
- Cards appear as they're found (every 28s)
- Audio quality indicator updates every second

**Critical Missing in Current UI:**
- Partial vs final distinction not shown
- Entity updates not visible
- Card appearance timing not communicated
- Audio quality not displayed

### 7.3 Tier 3 = Recording Pipeline (Lane B) + Post-Processing

**Backend:** Lossless audio recording + session-end batch processing  
**UI:** Full dashboard opened after meeting or for deep review

**Post-Meeting Processing Pipeline:**
1. **Signal EOF** to audio queues (immediate)
2. **Wait for ASR flush** (up to 8s timeout)
3. **Cancel analysis tasks** (5s timeout)
4. **Run diarization** per audio source (pyannote.audio)
5. **Merge transcript with speakers** (speaker labels assigned)
6. **Generate final outputs:**
   - Full transcript with speaker labels
   - Complete entity extraction (can use LLM)
   - All cards with confidence scores
   - Markdown summary
   - Diarization segments
7. **Finalize recording lanes** (save lossless audio)

**What This Means for UI:**
- **Different transcript** than live view (has speaker labels)
- **Higher quality** analysis (can use slower, better models)
- **Complete data** (not incremental)
- **Takes 30s-2min** to process (show progress)
- **Raw view** available (plain text export)

**Key User Story:**
> During meeting: "Speaker 1 said..." (Tier 2 live)  
> After meeting: "Alex said..." (Tier 3 dashboard with diarization)

### 7.4 The Dual Transcript System Explained

**Same audio, two different transcripts:**

| Aspect | Live Transcript (Tier 2) | Final Transcript (Tier 3) |
|--------|--------------------------|---------------------------|
| **Timing** | Real-time streaming | Post-meeting batch |
| **ASR Model** | faster-whisper base.en (fast) | Can use large-v3-turbo (accurate) |
| **Chunks** | 2-second segments | Full recording |
| **Diarization** | ❌ None (speaker unknown) | ✅ Full (pyannote.audio) |
| **NER** | Keyword-based incremental | Full extraction with LLM |
| **Cards** | Keyword-based | LLM-powered with context |
| **Latency** | <2 seconds | 30s-2min processing |
| **Quality** | Draft (good enough for live) | Premium (archival quality) |
| **Purpose** | Immediate UI feedback | Permanent high-quality record |

**User Mental Model:**
- **Live Panel (Tier 2):** "What was just said?" (draft, fast)
- **Dashboard (Tier 3):** "What happened in the meeting?" (polished, accurate)

### 7.5 Session State Management

**State Machine:**
```
IDLE ──Start──▶ LISTENING ──Pause──▶ PAUSED
  ▲                │                    │
  │                │ Stop/Auto-end      │ Resume
  │                ▼                    │
  └────────────── FINALIZED ◀───────────┘
```

**Tier 1 (Menu Bar) Responsibilities:**
- **Idle:** Gray icon, "Start Recording" available
- **Listening:** Red recording icon + timer display
- **Paused:** Yellow pause icon + timer (frozen)
- **Finalized:** Returns to idle, session appears in recent list

**Pause/Resume Behavior:**
- **Pause:** Audio capture stops, timer freezes, WebSocket maintained
- **Resume:** Continues same session from where left off
- **Auto-pause:** After 5 minutes of silence
- **Auto-end:** After 30 minutes of silence (saves session)
- **Session expiration:** Paused sessions auto-finalize after 24 hours

**Meeting Switching:**
- Only **one active session** at a time (by design)
- Starting new while paused prompts: "Resume existing or start new?"
- Prevents parallel sessions to avoid data fragmentation
- Dashboard (Tier 3) allows browsing past sessions (read-only)

### 7.6 Raw vs Processed Views

**Raw View (Tier 3 Dashboard):**
```
[2:34 PM] Speaker 1: The deadline is next Friday
[2:35 PM] Speaker 2: I'll handle the API integration
[2:37 PM] Speaker 1: We should review the Q1 numbers
```
- Plain text format
- Monospace font
- Timestamps + speaker labels
- One line per segment
- Copy-to-clipboard functionality
- Export-ready

**Processed Views (Tier 3 Dashboard):**
- **Summary Tab:** AI-written meeting summary
- **Transcript Tab:** Rich text with speaker badges
- **Highlights Tab:** Action items, decisions, risks with evidence
- **People Tab:** Clickable entities with mention counts
- **Search:** Find text across all sessions

**Key Difference:**
- **Raw:** Machine-readable, exportable, no styling
- **Processed:** Human-readable, interactive, contextual

---

## Part 8: Critical UI Components for Each Tier

### 8.1 Tier 2 (Sidebar Panel) - Live Meeting View

**Window Specifications:**
- **Type:** Floating panel (not full window)
- **Size:** 400px width (Narrow preset) during meetings
- **Position:** Right edge, 20pt margin, beside video call
- **Behavior:** Stays on top during recording (optional)

**Required Components:**

**1. Header Bar**
```
┌─────────────────────────────────────┐
│ [● Recording]  12:34    [Pin] [⚙]  │
└─────────────────────────────────────┘
```
- Recording status indicator (colored dot)
- Live timer (updates every second)
- Pin button (mark important moment)
- Settings gear (quick settings)

**2. Audio Source Control**
```
┌─────────────────────────────────────┐
│  System ●───────────○ Mic          │
│         [System + Microphone]       │
└─────────────────────────────────────┘
```
- Toggle between System/Mic/Both
- Visual indicator of active sources
- Per-source audio level meters (optional)

**3. Tab Bar**
```
┌─────────────────────────────────────┐
│ [Transcript] [Highlights] [Entities]│
└─────────────────────────────────────┘
```
- **Transcript:** Rolling live text
- **Highlights:** Recent cards (floating or sidebar)
- **Entities:** Recently mentioned people/topics

**4. Transcript Area (Rolling)**
```
Sarah: "The deadline is next Friday"    [2:34 PM]
  ↳ gray/italic while partial

Alex: "I'll handle the API integration"  [2:35 PM]
  ↳ solid text when final
  ✓ Action: Alex - API work

[Recording... new text appears here      [2:36 PM]
  ↳ auto-scroll with smooth animation
```

**Styling Requirements:**
- **Partial text:** Gray, italic, 0.7 opacity
- **Final text:** Solid, normal weight, 1.0 opacity
- **Smooth transition:** When partial becomes final
- **Auto-scroll:** Keep latest text visible
- **Timestamp:** Right-aligned, small font

**5. Live Highlights Section (Floating or Collapsible)**
```
⚡ Recent Highlights
━━━━━━━━━━━━━━━━━━━━━
• Deadline: next Friday      [2:34 PM]
• Action: Alex - API work    [2:35 PM]
• Decision: Use new stack    [2:40 PM]
```
- Shows last 3-5 cards
- Auto-updates every 28s
- Click to jump to transcript location
- Swipe/drag to dismiss

**6. Footer Controls**
```
┌─────────────────────────────────────┐
│  [⏸ Pause]           [⏹ End]      │
└─────────────────────────────────────┘
```
- Pause/Resume button (maintains session)
- End Session button (finalizes)
- Visual distinction between pause (temporary) and end (permanent)

**7. Silence Detection Banner (Conditional)**
```
┌─────────────────────────────────────┐
│ ⚠️ No audio detected for 15s        │
│     [Continue] [Stop]               │
└─────────────────────────────────────┘
```
- Appears after 10-30s of silence
- Orange warning color
- Auto-pause after 5min, auto-end after 30min

### 8.2 Tier 3 (Dashboard) - Deep Review

**Window Specifications:**
- **Type:** Standard window (opens on demand)
- **Size:** 900x700px (Wide preset)
- **Navigation:** Sidebar with session list
- **Behavior:** Standard window management (can minimize, etc.)

**Layout:**
```
┌───────────┬────────────────────────────────────────┐
│           │ Team Standup - Feb 15, 2025            │
│ Sessions  │ Duration: 45 min • 3 participants      │
│           │                                        │
│ [Summary] │ Key Points:                            │
│ [Trans]   │ • Deadline moved to Feb 28            │
│ [Highlts] │ • API integration assigned to Alex    │
│ [People]  │ • Q1 review scheduled                 │
│ [Raw]     │                                        │
│           │ Action Items:                          │
│ ───────── │ ☑ Review Q1 numbers (Sarah)           │
│           │ ☐ API integration (Alex)              │
│ Recent    │ ☐ Update documentation (Mike)         │
│ ───────── │                                        │
│ Standup   │ [Export] [Share] [Delete]              │
│ Client    │                                        │
│ Sprint    │                                        │
└───────────┴────────────────────────────────────────┘
```

**Required Tabs:**

**1. Summary Tab**
- AI-generated meeting summary
- Stats cards (Action Items, Decisions, Participants, Messages)
- Key points bullet list
- Quick action items list

**2. Transcript Tab**
- Full transcript with speaker labels (not "Speaker 1" but "Alex")
- Search bar (find text in this session)
- Filter by speaker
- Click timestamp to play audio (if available)

**3. Highlights Tab**
- All action items with checkboxes
- All decisions with confidence scores
- All risks with severity indicators
- Evidence quotes linking back to transcript
- Edit/delete capabilities

**4. People Tab**
- All detected people with mention counts
- All organizations
- All topics
- Click to filter transcript
- Grounding quotes (example mentions)

**5. Raw Tab**
- Plain text view
- Monospace font
- Copy button
- Export buttons (JSON/Markdown/Text)

**Sidebar:**
- List of all sessions
- Search across all sessions
- Sort by date, duration, title
- Delete/archive actions

### 8.3 Tier 1 (Menu Bar) - Status & Quick Access

**Dropdown Menu:**
```
┌─────────────────────────────────────┐
│ EchoPanel                    v2.0.0 │
│ Status: Recording (12:34)           │
├─────────────────────────────────────┤
│ [● Stop Recording]                  │
│ [Show Panel]              ⌘⇧S       │
├─────────────────────────────────────┤
│ Recent Sessions:                    │
│ → Team Standup (2h ago)             │
│ → Client Call (5h ago)              │
├─────────────────────────────────────┤
│ Open Dashboard            ⌘⇧D       │
├─────────────────────────────────────┤
│ Settings...               ⌘,        │
│ Quit                      ⌘Q        │
└─────────────────────────────────────┘
```

**Icon States:**
- **Idle:** Gray waveform
- **Recording:** Red dot + timer "● 12:34"
- **Paused:** Yellow pause icon "⏸ 12:34"
- **Error:** Red warning triangle

**Global Hotkeys:**
- ⌘⇧R - Start/Stop Recording
- ⌘⇧P - Pause/Resume
- ⌘⇧S - Show/Hide Panel
- ⌘⇧D - Open Dashboard

---

## Part 9: Implementation Priority Matrix

### Phase 1: Core Tier 2 Panel (MVP for Live Meetings)

**Must Have for Live Use:**
1. ✅ Floating panel window (400px, right edge)
2. ✅ Live transcript with partial/final distinction
3. ⚠️ Audio source toggle (System/Mic/Both) - **MISSING**
4. ⚠️ Recording timer with start/stop - **PARTIAL**
5. ⚠️ Pause/resume functionality - **MISSING**
6. ⚠️ Basic highlights display - **PARTIAL (mock only)**

**Without these:** User can't effectively use during meetings

### Phase 2: Tier 3 Dashboard (Post-Meeting Review)

**Must Have for Review:**
1. ✅ Session list sidebar
2. ✅ Summary view with stats
3. ✅ Transcript with speaker labels
4. ⚠️ Full highlights with confidence - **MISSING**
5. ⚠️ People/entities view - **PARTIAL (mock only)**
6. ⚠️ Export functionality - **PARTIAL (dialog only)**
7. ⚠️ Search across sessions - **MISSING**

**Without these:** User can't analyze or export meetings

### Phase 3: Power User Features

**Important for Power Users:**
1. ⚠️ ASR provider selection (6 providers) - **MISSING**
2. ⚠️ Performance dashboard (RTF, latency) - **MISSING**
3. ⚠️ Advanced audio settings (VAD, chunks) - **MISSING**
4. ⚠️ Diarization controls - **MISSING**
5. ⚠️ LLM settings (OpenAI/Ollama) - **MISSING**

**Without these:** Power users lack control

### Phase 4: Advanced Features

**Future Enhancements:**
1. ⚠️ Document management (RAG) - **MISSING**
2. ⚠️ Screen OCR toggle - **MISSING**
3. ⚠️ Custom keyboard shortcuts - **MISSING**
4. ⚠️ Plugin system - **MISSING**

---

## Part 10: Backend-to-UI Mapping Summary

### Live Analysis (Every X Seconds)

| Backend Event | Frequency | UI Component | Current Status |
|---------------|-----------|--------------|----------------|
| `asr_partial` | Continuous | Transcript text (gray) | ❌ Not styled |
| `asr_final` | Continuous | Transcript text (solid) | ✅ Shown |
| `entities_update` | Every 12s | Entities sidebar | ❌ Not shown |
| `cards_update` | Every 28s | Highlights section | ⚠️ Mock only |
| `metrics` | Every 1s | Audio quality indicator | ❌ Not shown |

### Post-Meeting Processing (Once at End)

| Backend Step | UI Result | Current Status |
|--------------|-----------|----------------|
| Diarization | Speaker labels (Alex, not Speaker 1) | ⚠️ Mock only |
| Full NER | Complete entities with counts | ⚠️ Mock only |
| Full Cards | All actions with confidence | ⚠️ Mock only |
| Summary | AI-written meeting summary | ✅ Mock text |
| Raw Export | Plain text transcript | ❌ Not implemented |

---

*End of Analysis - Updated with Architecture Validation*

