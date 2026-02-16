# EchoPanel UI Architecture Validation

**Date:** 2026-02-15  
**Status:** Architecture Proposal Validation  
**Context:** User's proposed 3-tier architecture vs backend capabilities

---

## User's Proposed Architecture

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

---

## Validation: Does This Match Backend Capabilities?

### ✅ YES - This Architecture is Perfect

Your proposal aligns **exactly** with how the backend works:

### Tier 2 (Sidebar Panel) = Live Pipeline (Lane A)

**Backend:** Real-time bounded queue, <2s latency, may drop to stay live  
**UI:** Sidebar panel showing live transcript with incremental updates

**What happens live:**
- `asr_partial` → Shows in UI immediately (may change)
- `asr_final` → Confirms text in UI
- `entities_update` (every 12s) → Updates People/Orgs/Topics in sidebar
- `cards_update` (every 28s) → Shows Actions/Decisions/Risks
- `metrics` (every 1s) → Audio quality indicators

**Your sidebar panel should show:**
1. **Transcript Roll** - Auto-scrolling text, partials grayed/italic
2. **Live Highlights** - Floating cards or compact sidebar section
3. **Entity Stream** - Recently mentioned people/topics
4. **Controls** - Source toggle, pause/resume, timer

### Tier 3 (Dashboard) = Recording Pipeline (Lane B) + Post-Processing

**Backend:** Lossless audio recording + session-end processing  
**UI:** Full dashboard opened after meeting or for deep review

**What happens post-meeting:**
1. **Diarization** - Speaker labels assigned (not available live)
2. **Full NER** - Complete entity extraction with LLM
3. **Full Cards** - All actions/decisions with confidence scores
4. **Summary Generation** - AI-written meeting summary
5. **Raw Transcript** - Plain text with timestamps

**Your dashboard should show:**
1. **Tabs:** Summary | Transcript | Highlights | People | Raw
2. **Summary Tab:** AI summary + stats cards
3. **Transcript Tab:** Full text with speaker labels
4. **Highlights Tab:** All cards with evidence quotes
5. **People Tab:** All entities with mention counts
6. **Raw Tab:** Plain text export view

### Tier 1 (Menu Bar) = Session State Management

**Backend:** State machine (IDLE → LISTENING → PAUSED → FINALIZED)  
**UI:** Menu bar reflects state, provides global shortcuts

**State handling:**
- **IDLE:** Gray icon, "Start Recording"
- **LISTENING:** Red recording icon + timer
- **PAUSED:** Yellow pause icon + timer
- **FINALIZED:** Returns to idle, session appears in recent list

---

## Key Backend Features Your Architecture Handles

### 1. Dual Transcript System ✅

**Live Transcript (Tier 2 Sidebar):**
- Partial → Final progression visible
- No speaker labels (diarization not ready)
- Draft quality, real-time

**Final Transcript (Tier 3 Dashboard):**
- Post-meeting, with speaker labels
- Processed with full pipeline
- High quality, permanent record

### 2. Pause/Resume ✅

**Tier 2 Panel handles this perfectly:**
- Pause button in panel stops audio capture
- Timer pauses
- Session state maintained
- Resume continues same session
- Auto-pause after 5min silence

### 3. Meeting Switching ✅

**Tier 3 Dashboard supports this:**
- Sidebar in dashboard shows all sessions
- Click to switch between meetings
- Can't have parallel active sessions (by design)
- Starting new prompts: "Resume or start new?"

### 4. Raw vs Processed Views ✅

**Tier 3 Dashboard Raw Tab:**
- Plain text format
- Monospace font
- Timestamps + speaker labels
- Copy-to-clipboard

**Tier 3 Dashboard Processed Tabs:**
- Rich UI with highlights
- Clickable entities
- Visual cards
- Interactive filtering

### 5. Recording Secondary Analysis ✅

**This is the Lane B (Recording Lane):**
- Audio saves to disk during recording (configurable)
- After meeting, can re-process with better models
- Tier 3 Dashboard shows this "premium" analysis
- Different from live "draft" analysis

---

## Critical Features to Add to Your Architecture

Based on backend gaps analysis:

### Must Add to Tier 2 (Sidebar Panel)

1. **Audio Source Toggle**
   - System / Mic / Both
   - Visual indicator of what's active
   - Per-source audio level meters

2. **ASR Provider Indicator**
   - Show which provider is running (faster-whisper, Voxtral, etc.)
   - Quick switch for power users
   - Performance indicator (RTF)

3. **Live Speaker Detection (Placeholder)**
   - Show "Speaker 1", "Speaker 2" during live
   - After meeting, labels become "Alex", "Sarah" (post-diarization)

4. **Pin Button**
   - Press 'P' or click pin to mark moment
   - Pinned items appear in Highlights

5. **Silence Indicators**
   - Banner when no audio detected >10s
   - "Still listening?" after 30s
   - Auto-pause warning

### Must Add to Tier 3 (Dashboard)

1. **Provider Selection**
   - Choose between 6 ASR providers
   - Auto-detect recommendation
   - Hardware capability display

2. **Card Detail View**
   - Confidence scores
   - Evidence quotes linking to transcript
   - Edit/delete cards
   - Due date assignment for actions

3. **Search Across Sessions**
   - Find text in any meeting
   - Filter by date, participant, topic

4. **Document Management (RAG)**
   - Index documents for context
   - Search indexed docs
   - Visual context injection toggle

5. **Export with Preview**
   - JSON/Markdown/Text options
   - Live preview before export
   - Include/exclude sections

### Tier 1 (Menu Bar) Improvements

1. **Global Hotkeys**
   - ⌘⇧R - Start/Stop
   - ⌘⇧P - Pause/Resume
   - ⌘⇧S - Show/Hide panel

2. **Recent Sessions List**
   - Last 5 sessions in menu
   - Click to open in dashboard

3. **Quick Status**
   - Recording duration in menu bar
   - Backend health indicator
   - Audio source indicator

---

## Implementation Recommendations

### Phase 1: Tier 2 Sidebar Panel (MVP)

**Window Type:** Floating panel, not full window
**Size:** 400px wide (Narrow preset) during meetings
**Position:** Right edge, beside Zoom/Meet

**Components:**
```
┌──────────────────────────────┐
│ [● Recording]  12:34    [⚙] │ <- Header
├──────────────────────────────┤
│ System ●───────○ Mic        │ <- Audio sources
├──────────────────────────────┤
│ [Summary] [Trans] [Pins]    │ <- Tab bar
├──────────────────────────────┤
│                              │
│ Sarah: "The deadline..."     │ <- Transcript
│ 2:34 PM                      │    (rolling)
│                              │
│ Alex: "I'll handle it"       │
│ 2:35 PM ✓ Action             │
│                              │
├──────────────────────────────┤
│ ⚡ Highlights                │
│ • Deadline: next Friday      │
│ • Action: Alex - API work    │ <- Live cards
├──────────────────────────────┤
│ [Pause]        [End Session] │ <- Footer controls
└──────────────────────────────┘
```

### Phase 2: Tier 3 Dashboard

**Window Type:** Standard window (opens when needed)
**Size:** 900x700px (Wide preset)
**Navigation:** Sidebar with session list

**Layout:**
```
┌──────────────┬───────────────────────────────┐
│              │ Team Standup - Feb 15        │
│ [Summary]    │ Duration: 45 min             │
│ [Transcript] │                              │
│ [Highlights] │ Key Points:                   │
│ [People]     │ • Deadline moved to Feb 28   │
│ [Raw]        │ • API integration assigned   │
│              │                              │
│ ──────────── │ Action Items:                 │
│              │ ☑ Review Q1 (Sarah)          │
│ Sessions     │ ☐ API integration (Alex)     │
│ ├── Standup  │ ☐ Update docs (Mike)         │
│ ├── Client   │                              │
│ └── Sprint   │ [Export] [Share] [Delete]    │
└──────────────┴───────────────────────────────┘
```

### Phase 3: Polish

1. **Animations:** Smooth transitions between partial/final text
2. **Accessibility:** VoiceOver, keyboard navigation
3. **Themes:** Light/dark/auto with system
4. **Shortcuts:** Customizable hotkeys

---

## Comparison: Your Architecture vs Original Design

| Aspect | Original Design Review | Your Proposal | Match? |
|--------|----------------------|---------------|---------|
| **Menu bar role** | "Handle, not stove" | Status + quick controls | ✅ Perfect |
| **Primary interface** | Floating panel | Sidebar panel (Tier 2) | ✅ Perfect |
| **During meetings** | Panel beside video call | Tier 2 sidebar | ✅ Perfect |
| **Deep review** | Expandable panel/window | Tier 3 dashboard | ✅ Better |
| **Window count** | 1-2 max | 3 intentional tiers | ✅ Acceptable |
| **User mental model** | "Meeting companion" | Exactly that | ✅ Perfect |

**Your improvement:** Making Tier 3 a separate dashboard (not just expanded panel) is actually better for power users who want full history and management.

---

## Conclusion

**Your 3-tier architecture is validated and superior:**

✅ Matches backend dual-pipeline design (Live Lane A vs Recording Lane B)
✅ Handles both live and post-meeting analysis correctly
✅ Supports pause/resume and meeting switching
✅ Separates raw vs processed views appropriately
✅ Aligns with design review "companion panel" philosophy
✅ Gives power users the dashboard they need without cluttering the live view

**Next Steps:**
1. Build Tier 2 sidebar panel as floating window (400px, right edge)
2. Ensure it shows live transcript with partial/final distinction
3. Add critical missing features (audio source, pause/resume)
4. Build Tier 3 dashboard for post-meeting deep dive
5. Keep Tier 1 menu bar minimal (status + shortcuts)

This architecture will make Sarah (Product Manager), David (Engineer), and Elena (Privacy Advocate) all happy because it serves each persona without compromise.

---

*End of Validation*
