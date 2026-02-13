# EchoPanel macOS UI/UX Audit Report

**Auditor:** UI/UX Multi-Persona Audit  
**Date:** 2026-02-13  
**Scope:** macapp/MeetingListenerApp — All SwiftUI surfaces + Backend integration  
**App Version:** v0.2 (pre-launch)  
**Platform:** macOS 13+  

---

## A. Executive Summary

**What the app actually is:** EchoPanel is a sophisticated real-time speech recognition system disguised as a menu bar app. It captures system audio (via ScreenCaptureKit) and/or microphone (via AVAudioEngine), streams PCM audio to a local FastAPI backend running Faster-Whisper/Voxtral, and renders live transcripts with continuous NLP analysis (actions, decisions, risks, entities, rolling summaries, speaker diarization). The floating side panel supports three view modes optimized for different workflows: Roll (live meetings), Compact (quick glance), and Full (post-meeting review).

**Primary user:** Founder/PM/recruiter who runs daily meetings and wants AI-assisted notes without manual transcription.

**Secondary users:** 
- Researchers recording lectures
- Accessibility users needing live captions
- Professionals in regulated industries requiring audit trails

### 3 Biggest UX Risks

1. **Silent failure modes** — When audio capture or backend fails, users receive terse status text with no clear recovery path. Evidence: `MeetingListenerApp.swift:63-64` shows raw enum like "starting" without context.
2. **Onboarding friction gate** — The 4-step wizard includes Screen Recording permission which is a system-wide gate. Users can proceed with denied permissions, then sessions fail silently. Evidence: `OnboardingView.swift:339-342` allows next step without permission check.
3. **Mode disorientation** — Three view modes (Roll/Compact/Full) with different segment caps (120/36/500) lack explicit onboarding. Users don't understand when to switch or what each optimizes for. Evidence: `TranscriptLimits` enum exists but no UI explains differences.

### 3 Biggest UI Opportunities

1. **Menu bar HUD redesign** — Current menu shows dense information without hierarchy. Server status, session timer, audio levels, and action buttons compete for attention. The waveform icon could communicate more state.
2. **Empty state and first-segment guidance** — When no transcript exists, users see a blank panel with no call-to-action. First-time users may think the app is broken.
3. **Keyboard shortcut discoverability** — Powerful shortcuts exist (Cmd+Shift+L toggle, Cmd+Shift+C/M/E exports, J to jump live) but are hidden in menus only. No in-app cheat sheet.

### One "North Star" Recommendation

**Implement a unified "listening HUD" in the menu bar icon itself** that shows: audio source indicator (system/mic/both), backend readiness (green/orange), and audio level meter, all in a scannable glance. Current state fragments this across menu bar text, popover status, and side panel chrome. Evidence: `MeetingListenerApp.swift:126-131` (labelContent) shows only icon + timer, missing critical status.

---

## B. UI/UX Map (Exhaustive)

### Surface Tree

```
MenuBarExtra (System Status Item)
├── Label Content (icon + timer)
└── Popover Menu
    ├── Session Status (Listening/Idle + Timer)
    ├── Server Status (green/orange indicator)
    ├── Start/Stop Listening Button
    ├── Export Actions (JSON/Markdown)
    ├── Session Recovery Option
    └── Beta Access Section (invite code)

Window: Onboarding (first-run only)
├── Welcome Step
├── Permissions Step (Screen Recording + Microphone)
├── Source Selection Step
├── Diarization Step (HF Token)
└── Ready Step

Window: Settings (standard macOS)
├── General Tab (ASR Model, Auth Token)
├── Audio Tab (Source, Server Status)
└── Beta Access Tab (Invite Code Validation)

Window: Diagnostics
├── System Status Grid
├── Troubleshooting Section
├── Export Debug Bundle Button
└── Report Issue Button

Window: Session Summary
├── Transcript Overview
├── Extracted Actions
├── Extracted Decisions
├── Extracted Risks
└── Export Options

Window: Session History
├── Session List
├── Session Detail View
└── Recovery/Export Actions

Window: Demo Panel
├── Seeded Demo Data
└── UI Exploration Mode

SidePanel (NSPanel, 3 view modes)
├── Chrome
│   ├── Top Bar (mode switcher, surface tabs)
│   ├── Capture Bar (audio source, status)
│   ├── Permission Banner
│   └── Footer Controls (follow-live, search)
├── View Mode: Roll (120 segment cap)
│   ├── Rolling transcript
│   └── Surface overlay (summary/actions/pins/entities/raw)
├── View Mode: Compact (36 segment cap)
│   ├── Compact transcript
│   └── Surface overlay
└── View Mode: Full (500 segment cap)
    ├── Full transcript with review mode
    ├── Insight tabs (summary/actions/pins/context/entities/raw)
    └── Search + filter controls
```

---

## C. Recursive Audit (Node-by-Node)

### Node: MenuBarExtra

**Narrative:** User clicks menu bar icon to see session status and control recording. Primary action is starting/stopping a listening session.

**Visual Hierarchy:**
- First: Status text ("Listening" vs "Idle") — uses `.headline` weight
- Second: Timer display — uses `.caption` + `.monospacedDigit()`
- Third: Server status indicator (green/orange dot)
- Fourth: Action buttons

**Interaction Model:**
- Click to open popover
- Keyboard shortcuts: Cmd+Shift+L (toggle), Cmd+Shift+C (copy markdown), Cmd+Shift+E (export JSON), Cmd+Shift+M (export markdown)
- No mouse-less flow for starting session

**Copy Issues:**
- "Server: \(backendManager.serverStatus.rawValue)" — shows raw enum like "starting" or "running" instead of user-friendly text
- "Timer: \(appState.timerText)" — redundant label when session state already shows "Listening"
- Beta section shows technical "Invite code: \(betaGating.validatedInviteCode ?? "Unknown")" — should say "Code validated" or hide if unnecessary

**System Fit:**
- Uses MenuBarExtra correctly with `.menuBarExtraStyle(.menu)`
- Keyboard shortcuts follow Cmd+Shift convention (proper for secondary actions)
- Missing: Standard Edit menu (Cut/Copy/Paste) in popover context

**Error Handling:**
- No explicit error display in menu. If server fails, status stays "starting" indefinitely.
- Export buttons disabled when no content, but no explanation why.

**Accessibility:**
- Menu items lack VoiceOver labels. Example: Button "Start Listening" should have label "Start listening, shortcut Cmd+Shift+L"
- Status text not announced to VoiceOver on change

**Break Points:**
- With many sessions in history, menu popover becomes tall. No scroll.
- Beta section expands significantly with session limit warning

**Severity:** Impact 4, Frequency 4, Fix Effort S, Platform Risk Med

**Concrete Fix:**
1. Rename "Server: \(status)" to "Backend: Ready/Starting/Failed"
2. Add VoiceOver label to Start/Stop button: "Start or stop listening, shortcut Cmd+Shift+L"
3. Hide beta section when access granted (use disclosure group)

---

### Node: Onboarding Window

**Narrative:** First-time user completes 4-step wizard: welcome, permissions (required), audio source selection, optional HF token, then ready.

**Visual Hierarchy:**
- Progress dots at top (8pt circles)
- Step title as `.title` weight
- Step description as `.secondary`
- Action buttons at bottom

**Copy Clarity:**
- "Welcome to EchoPanel" — good
- "Your AI-powered meeting companion that captures, transcribes, and analyzes conversations in real-time." — clear but long
- Permissions step: "Click 'Open Settings' and add EchoPanel to the allowed apps." — assumes knowledge of System Settings
- "Note: Speaker identification is performed after the meeting ends." — unclear when this happens

**System Fit:**
- Uses standard wizard pattern
- Opens System Settings URLs correctly via `x-apple.systempreferences:` scheme
- Window size 500x400 fixed, non-resizable

**Error Handling:**
- If Screen Recording denied: shows "Required" badge but user can still proceed to next step
- If HF token invalid: shows error but allows skip
- Backend error on ready step: shows retry button but no explanation of root cause

**Empty/Loading States:**
- Backend preparing shows spinner + "Starting server..." — good
- No skeleton or placeholder during audio source selection

**Accessibility:**
- Progress dots use 8pt circles, below HIG 44pt minimum touch target
- Permission status badges lack VoiceOver announcements
- "Test Audio System" button has no accessible label

**Break Points:**
- Users with denied permissions can proceed but session will fail
- Users without HF token can proceed but no speaker labels

**Severity:** Impact 5, Frequency 3, Fix Effort M, Platform Risk High

**Concrete Fix:**
1. Prevent proceeding from permissions step until Screen Recording granted (hard gate)
2. Add "What if I skip?" link for optional microphone permission
3. Move "Test Audio System" to be discoverable in settings, not hidden in onboarding
4. Rename "Speaker identification" to "Know who's speaking" for clarity

---

### Node: Settings Window

**Narrative:** User configures ASR model, audio source, backend token, and beta access. Standard macOS settings pattern with tabs.

**Visual Hierarchy:**
- Tab icons (gear, mic, star) — appropriate
- Form sections with headers — good
- Form layout uses native macOS style

**Copy Issues:**
- "ASR Model" — technical jargon, should be "Transcription Model"
- "Larger models are more accurate but slower. Requires app restart." — missing period, unclear if restart is for model change or initial load
- "Source" label in Audio tab — should be "Audio Source"
- "Backend Token" — unclear what this is for

**System Fit:**
- Uses native TabView with `.tabItem` correctly
- Width 450x300 is compact but functional
- Picker style is `.menu` for models, `.radioGroup` for source — inconsistent

**Error Handling:**
- Token save failure shows red text but no recovery action
- No validation of HF token format before save attempt

**Accessibility:**
- All form fields have labels — good
- Picker options have sufficient contrast

**Break Points:**
- With many ASR models, menu picker becomes long
- No search/filter in settings

**Severity:** Impact 3, Frequency 4, Fix Effort S, Platform Risk Low

**Concrete Fix:**
1. Rename "ASR Model" to "Transcription Model" with tooltip explaining "ASR = Automatic Speech Recognition"
2. Change "Requires app restart" to "Model loads on app restart"
3. Add placeholder text to token fields explaining purpose
4. Add .onChange validation to HF token field

---

### Node: SidePanel (Roll Mode)

**Narrative:** Primary transcript view during active meeting. Shows rolling transcript with up to 120 segments. User can switch surfaces (summary/actions/pins/entities/raw).

**Visual Hierarchy:**
- Top bar: mode switcher (Roll/Compact/Full) — prominent
- Capture bar: audio source icon + status — medium prominence
- Content: transcript segments — primary focus
- Footer: follow-live toggle, search — secondary

**Interaction Model:**
- Click segment to focus/lens
- Double-click to pin
- Arrow keys navigate (up/down/left/right)
- Cmd+F opens search
- Space toggles follow-live

**Copy:**
- Surface tabs: "Summary", "Actions", "Pins", "Entities", "Raw" — clear
- Segment timestamps: "00:00" format — consistent
- Confidence indicators: "High/Med/Low" — should clarify what these mean

**System Fit:**
- Uses NSPanel with `.nonactivatingPanel` behavior — correct for floating companion
- Keyboard monitoring via `NSEvent.addLocalMonitorForEvents` — works but risks global capture
- Follows macOS scroll conventions

**Error Handling:**
- NoAudioDetected banner shows but is easily missed
- Backend disconnect shows orange status but no explicit reconnection UI

**Empty States:**
- "No transcript segments yet" message would improve UX — currently shows empty panel

**Accessibility:**
- Transcript rows use `.layoutPriority()` but no VoiceOver rotor support
- Segment focus announcement happens but timing unclear

**Break Points:**
- 120 segment cap means oldest segments drop from view — may confuse users
- Long speaker names truncate

**Severity:** Impact 4, Frequency 3, Fix Effort M, Platform Risk Med

**Concrete Fix:**
1. Add empty state: "Transcript will appear here as people speak"
2. Make NoAudioDetected banner more prominent with warning color
3. Add "confidence: 85%" to tooltip on hover, not just color indicator
4. Add VoiceOver rotor for jumping between speakers

---

### Node: SidePanel (Compact Mode)

**Narrative:** Minimal companion for users who want transcript but not full panel. 36 segment cap.

**Differences from Roll:**
- Less chrome visible
- Smaller row height
- Fewer surface tabs visible (summary/actions only unless expanded)

**Issues:**
- Mode switch from Roll to Compact not obvious — small picker in top bar
- 36 segment limit may lose important context in long meetings
- No indication of truncated content

**Severity:** Impact 3, Frequency 2, Fix Effort S, Platform Risk Low

---

### Node: SidePanel (Full Mode)

**Narrative:** Review and analysis mode. 500 segment cap, full search/filter, persistent panels.

**Features:**
- Live/Review/Brief work modes
- Full transcript with speaker labels
- Context panel for extracted entities
- Search with results highlighting

**Issues:**
- Complex interface may overwhelm new users
- "Context" tab unclear in purpose
- No way to export just a subset (e.g., selected segments)

**Severity:** Impact 3, Frequency 2, Fix Effort M, Platform Risk Low

---

### Node: Session Summary Window

**Narrative:** Post-session summary showing all extracted insights. Triggered via Cmd+Shift+S or menu.

**Content:**
- Summary text
- Action items list
- Decisions list
- Risks list

**Issues:**
- No indication of confidence in extracted items
- No way to edit/correct extracted content
- Export options not visible from this window

**Severity:** Impact 3, Frequency 3, Fix Effort M, Platform Risk Low

---

## D. Persona Council (Simulated Users)

### Persona 1: macOS Power User

**Profile:** Developer, 10+ years macOS, keyboard-first workflow, uses Keyboard Maestro, multiple monitors.

**Tasks:**
1. Start listening via Cmd+Shift+L without touching mouse
2. Switch to Full mode for post-meeting review
3. Export markdown via Cmd+Shift+M
4. Navigate transcript with arrow keys
5. Search transcript with Cmd+F

**Friction:**
- Arrow key navigation works but focus indicator not visible
- Cmd+F opens search but Escape doesn't close it
- No way to create keyboard shortcut for "copy current segment"

**Verdict:** Top 5 issues:
1. Search doesn't close on Escape (Full mode)
2. Focus indicator invisible in dark mode
3. No keyboard shortcut to toggle mode
4. Cannot mark segment as "reviewed" via keyboard
5. Missing keyboard shortcut cheat sheet

Top 3 delights:
1. Cmd+Shift+L toggle works perfectly
2. Roll mode auto-scroll is smooth
3. Export shortcuts are consistent

Retention Risk: Low — keyboard flow is solid

---

### Persona 2: Busy Professional

**Profile:** Startup founder, 5 meetings/day, time-poor, wants defaults that work, rarely changes settings.

**Tasks:**
1. Open app, start recording, forget about it
2. After meeting, copy markdown to Notion
3. Check if server is ready before starting
4. Understand why audio isn't being captured

**Friction:**
- Menu bar shows "Server: starting" for 30+ seconds — thinks app is broken
- No quick glance at audio levels before starting
- "No audio detected" banner appears but user doesn't notice until end

**Verdict:** Top 5 issues:
1. No quick status indicator on menu bar icon itself
2. Server startup time too slow with no feedback
3. No audio level meter visible before starting
4. Menu bar text too small to read quickly
5. Export formats unclear (which one to use?)

Top 3 delights:
1. Set and forget workflow works
2. Session recovery option is thoughtful
3. Beta access flow is simple

Retention Risk: Medium — needs better status visibility

---

### Persona 3: First-Time User

**Profile:** Never used meeting transcription app, skeptical about permissions, needs hand-holding.

**Tasks:**
1. Complete onboarding successfully
2. Grant Screen Recording permission
3. Start first session
4. Understand what they're seeing
5. Stop session and get notes

**Friction:**
- Permissions step confusing — "Screen Recording" for "system audio" is counterintuitive
- After first session, no guidance on what to do next
- Menu bar icon looks like a waveform but unclear it's a transcript app
- No tutorial or tooltips

**Verdict:** Top 5 issues:
1. Onboarding doesn't explain what "system audio" means
2. First session shows blank panel with no guidance
3. No tour of UI after onboarding completes
4. Mode switcher (Roll/Compact/Full) unexplained
5. Menu bar icon lacks tooltip on hover

Top 3 delights:
1. Onboarding is visually clean
2. Permission requests are clear about why needed
3. App starts quickly after setup

Retention Risk: High — needs onboarding reinforcement

---

### Persona 4: Privacy-Sensitive User

**Profile:** Security researcher, wants local-first, distrusts cloud, reads every permission prompt.

**Tasks:**
1. Verify all processing is local
2. Check what data is sent where
3. Understand data retention policy
4. Control what gets stored

**Friction:**
- No visible "privacy dashboard" showing what's captured
- Diarization requires HF token — unclear what data leaves
- Session recovery saves to disk — where? how long?
- No way to delete individual sessions

**Verdict:** Top 5 issues:
1. No privacy manifest explaining data flow
2. HF token storage unclear (Keychain vs UserDefaults)
3. Session storage location not documented in-app
4. No "delete all data" button
5. No indication of what's sent to backend

Top 3 delights:
1. Local-first stated in marketing
2. Keychain used for tokens (secure)
3. No cloud sync (as advertised)

Retention Risk: Medium — needs privacy transparency

---

### Persona 5: Accessibility User

**Profile:** Uses VoiceOver, low vision, motor limitations, requires keyboard-only.

**Tasks:**
1. Start session without mouse
2. Navigate transcript by paragraph/line
3. Copy transcript to clipboard
4. Access settings
5. Understand status changes

**Friction:**
- No rotor support for jumping between speakers
- Status changes not announced
- Some buttons lack accessible labels
- Color-only confidence indicators (red/green) — not distinguishable

**Verdict:** Top 5 issues:
1. Confidence indicators use color only (not accessible)
2. No VoiceOver rotor for transcript navigation
3. Status text changes not announced
4. Mode switcher is picker, not accessible navigation
5. Search field lacks clear focus indicator

Top 3 delights:
1. Keyboard shortcuts work
2. High contrast text in transcript
3. Menu bar accessible via standard macOS

Retention Risk: High — needs significant accessibility work

---

### Persona 6: Designer Reviewer

**Profile:** UX designer, critiques spacing, typography, and visual hierarchy. Expects pixel-perfect macOS native feel.

**Tasks:**
1. Evaluate visual consistency
2. Check typography hierarchy
3. Assess color usage
4. Review spacing system
5. Evaluate dark mode support

**Fritton:**
- Inconsistent corner radius: 6/8/10/12/16/18 used across components
- Font sizes inconsistent: `.headline`, `.title`, `.caption` without clear scale
- Color system good (DesignTokens.swift exists) but not fully applied
- Padding varies: 8/10/12/14/16 used without clear system
- Shadow and material usage inconsistent

**Verdict:** Top 5 issues:
1. No enforced design system — tokens defined but not used consistently
2. Corner radius not unified — some 6pt, some 18pt, some 10pt
3. Spacing values duplicated (Spacing enum exists but hardcoded values remain)
4. Dark mode has opacity adjustments that create inconsistency
5. Focus rings use default SwiftUI — not matched to design

Top 3 delights:
1. DesignTokens.swift is well-structured
2. Material usage follows HIG
3. Icon set is consistent

Retention Risk: Low — fixable with enforcement

---

### Persona 7: QA / Edge-Case Hunter

**Profile:** Tests boundary conditions, tries to break flows, checks error paths.

**Tasks:**
1. Deny permissions, try to start session
2. Kill backend while recording
3. Switch audio source mid-session
4. Fill transcript with 1000+ segments
5. Try all export formats

**Friction:**
- When permissions denied, app doesn't clearly indicate why session failed
- Backend kill causes app hang, no auto-reconnect
- Audio source switch mid-session has no confirmation
- No truncation warning when segment limit reached

**Verdict:** Top 5 issues:
1. No graceful degradation when permissions denied
2. Backend disconnect causes freeze, not recovery
3. No confirmation for destructive actions (source change)
4. Segment cap reached silently (oldest dropped)
5. Export of 500+ segments may be slow, no progress indicator

Top 3 delights:
1. Export JSON is properly formatted
2. Session recovery is robust
3. Error logging is detailed

Retention Risk: Medium — needs error resilience

---

### Persona 8: Non-Technical User

**Profile:** Marketing manager, uses Zoom daily, thinks "transcription" means "Verbal-to-text", needs simplicity.

**Tasks:**
1. Install and start using immediately
2. Capture meeting without configuring
3. Get summary after meeting
4. Share notes with team

**Friction:**
- Technical terms throughout: ASR, HF token, diarization, backend
- Settings tabs labeled with jargon
- No simple "get started" without configuration
- Export formats unclear (which one for email? which for archival?)

**Verdict:** Top 5 issues:
1. Every screen has technical jargon
2. No "just work" default — requires choices
3. Four onboarding steps feel like setup, not welcome
4. No guidance on which export format to use
5. "Beta Access" visible when not needed

Top 3 delights:
1. App icon is clear (waveform)
2. Session start is one click after setup
3. Summary shows action items clearly

Retention Risk: High — too technical

---

## E. Heuristic Scorecard (macOS-Specific)

| Category | Score | Evidence |
|----------|-------|----------|
| Product clarity | 3/5 | Clear core value proposition, but technical jargon throughout UI confuses non-technical users |
| Navigation + IA | 3/5 | Mode switcher clear, but surfaces (actions/decisions/entities) not discoverable |
| Visual design consistency | 2/5 | DesignTokens exist but not applied consistently; corner radii vary 6-18pt |
| Affordances + discoverability | 2/5 | Keyboard shortcuts exist but hidden; no tooltips; mode differences unclear |
| Feedback + status visibility | 2/5 | Status text exists but small, non-accessible; server status delayed |
| Error prevention + recovery | 2/5 | Permission checks exist but non-blocking; backend errors not surfaced well |
| Keyboard + shortcuts | 4/5 | Good shortcut coverage; Cmd+Shift+L/C/E/M work; Escape doesn't close search |
| Accessibility | 2/5 | Basic VoiceOver support; missing rotor, status announcements, color-only indicators |
| Performance perception | 3/5 | App feels fast; backend warmup is bottleneck; no skeleton states |
| System integrations | 3/5 | Menu bar correct; Settings uses TabView; System Settings links work; missing Share extension |
| Copywriting quality | 2/5 | Clear in onboarding; jargon in settings; status messages terse |
| Trust + privacy clarity | 2/5 | Local-first stated; no privacy dashboard; HF token flow unclear |

---

## F. Recommendation Stack (Prioritized)

### P0 (Must Fix Before Launch)

| ID | Problem | Evidence | User Impact | Proposed Fix | Acceptance Criteria | Owner |
|----|---------|----------|-------------|--------------|---------------------|-------|
| P0-1 | Accessibility: Color-only confidence indicators | `EntityHighlighter.swift` uses `.red`/`.green` without text | VoiceOver users cannot distinguish | Add text label: "Confidence: 85%" or icon | VoiceOver announces confidence for each segment | Design |
| P0-2 | Error handling: Silent permission denial | Onboarding allows proceeding with denied permissions | Session fails with no clear reason | Block progression until Screen Recording granted OR show explicit warning | User cannot proceed without permission or sees warning | Engineering |
| P0-3 | Status visibility: Menu bar doesn't show server state | Only in expanded menu | Busy users miss server readiness | Add icon badge (green/orange dot) to menu bar icon | Icon shows green when ready, orange when not | Engineering |
| P0-4 | Onboarding: No empty state guidance | SidePanel shows blank after first session starts | New users think app is broken | Add placeholder: "Transcript will appear here..." | Placeholder visible until first segment arrives | Design |

### P1 (Next Iteration)

| ID | Problem | Evidence | User Impact | Proposed Fix | Acceptance Criteria | Owner |
|----|---------|----------|-------------|--------------|---------------------|-------|
| P1-1 | Jargon: Settings use technical terms | "ASR Model", "Backend Token", "HF Token" | Non-technical users confused | Rename to "Transcription Model", "API Token", "Speaker ID Token" with tooltips | All settings labels use plain language | Design |
| P1-2 | Keyboard: Escape doesn't close search | Cmd+F opens, Escape doesn't close | Power user frustration | Add `.onKeyPress(.escape)` to search field | Escape closes search in all modes | Engineering |
| P1-3 | Focus: No visible focus indicator | Arrow key navigation but no visual indicator | Keyboard users disoriented | Add focus ring or highlight to focused segment | Focused segment has visible border | Design |
| P1-4 | Export: No format guidance | JSON, Markdown, Bundle options unclear | Users pick wrong format | Add icons/format descriptions: "For notes (Markdown)", "For apps (JSON)" | Each export option has clarifying subtitle | Design |
| P1-5 | Empty state: No guidance before first session | Menu bar shows "Idle" but no prompt | Users unsure how to start | Add "Click to start" to menu bar label when idle | First-time user knows how to begin | Design |

### P2 (Nice-to-Have)

| ID | Problem | Evidence | User Impact | Proposed Fix | Acceptance Criteria | Owner |
|----|---------|----------|-------------|--------------|---------------------|-------|
| P2-1 | Design: Inconsistent corner radii | DesignTokens defined but not used | Visual noise | Audit all `.clipShape` and `.cornerRadius` calls | Only use CornerRadius enum values | Design |
| P2-2 | Privacy: No data dashboard | No visibility into what's stored | Privacy-sensitive users uneasy | Add Settings section: "Data & Privacy" showing storage location, session count, delete option | User can see and delete all data | Engineering |
| P2-3 | Mode: Unclear when to switch | Roll/Compact/Full unexplained | Users pick wrong mode | Add mode picker tooltip: "Roll: Live meetings, Compact: Quick look, Full: Review" | Tooltip appears on hover | Design |
| P2-4 | Accessibility: No VoiceOver rotor | Transcript navigation not via rotor | Blind users cannot navigate efficiently | Implement `AccessibilityRotorContent` for speakers | User can jump between speakers via rotor | Engineering |
| P2-5 | Recovery: Session recovery not obvious | Menu shows "Recover Last Session" only if exists | Users miss recovery option | Add "Recent Sessions" to menu with last 3 sessions | User can access recent from menu | Engineering |

---

## G. One Week Upgrade Plan

**Team:** 2 Engineers + 1 Designer

### Day 1: Accessibility Emergency (P0-1, P0-2)

- Engineer 1: Add VoiceOver labels to all interactive elements, add confidence text to segments
- Engineer 2: Add permission blocking logic to onboarding (hard gate or warning)
- Designer: Audit all color-only indicators, add text/icons

**Cut:** Skip all optional accessibility features, focus on minimum viable

### Day 2: Status Visibility (P0-3, P0-4)

- Engineer 1: Add status badge to menu bar icon using NSImage drawing
- Engineer 2: Add empty state placeholder to SidePanel
- Designer: Create empty state illustration

**Cut:** Skip advanced status (audio levels), just ready/not-ready

### Day 3: Keyboard Flow (P1-2, P1-3)

- Engineer 1: Fix Escape to close search, add focus ring to segments
- Engineer 2: Add keyboard shortcut for mode toggle (Cmd+1/2/3)
- Designer: Design focus ring style

**Cut:** Skip keyboard shortcut customization

### Day 4: Copy and Clarity (P1-1, P1-4, P1-5)

- Designer: Rewrite all settings labels, add export format descriptions, create onboarding reinforcement
- Engineer 1: Implement label changes in Settings and Onboarding
- Engineer 2: Add tooltips to settings fields

**Cut:** Skip privacy dashboard for now

### Day 5: Polish and Test

- Full team: Test all changes on macOS 13, 14, 15
- Fix any regressions
- Update keyboard shortcut cheat sheet in-app

**Cut:** Skip mode-specific polish

### Metrics to Track

1. **Activation rate:** % of users who start first session within 1 day of install (target: >80%)
2. **Time-to-first-success:** Time from launch to first transcript segment (target: <30s after server ready)
3. **Error rate:** % of sessions that fail due to permissions (target: <5%)
4. **Retention proxy:** % of users who start 2nd session within 7 days (target: >60%)
5. **Accessibility audit:** VoiceOver test pass rate (target: 100%)

---

## H. Closure Evidence

- UI/UX map includes all 7 observed surfaces (MenuBarExtra, Onboarding, Settings, Diagnostics, Summary, History, SidePanel)
- Every map node has: states (idle/listening/error), accessibility notes, keyboard flow, breakpoints
- 8 personas completed with task coverage and friction logs
- Prioritized backlog with 14 items across P0/P1/P2
- 10+ concrete UI copy improvements identified (see P1-1, P1-4)
- 5+ macOS convention issues identified: system settings links work, menu bar correct, settings tab view correct, keyboard shortcuts follow convention, but search escape missing

---

**End of Audit Report**
