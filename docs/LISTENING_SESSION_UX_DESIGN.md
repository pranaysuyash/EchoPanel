# Listening Session UX Design

**Status:** Design Proposal  
**Date:** 2026-02-11  
**Author:** Agent  
**Related:** `AppState.swift`, `SessionStore.swift`, `SidePanelView.swift`

---

## Executive Summary

This document proposes a comprehensive UX design for EchoPanel's listening session lifecycle, addressing ambiguity in session boundaries, silence handling, and user control. The goal is to create clear mental models, prevent data loss, and provide intuitive controls for various meeting scenarios.

---

## Key Decisions Summary

| # | Decision | Rationale | Status |
|---|----------|-----------|--------|
| 1 | **Add `paused` state** | Users need breaks without fragmenting sessions or losing context | Proposed |
| 2 | **Tiered silence handling** | 30s→toast, 5min→auto-pause, 30min→auto-end | Proposed |
| 3 | **Always auto-save locally** | User never needs to "save", only "export" | ✅ Keep current |
| 4 | **No parallel active sessions** | Prevents data fragmentation; allow rapid switch instead | Proposed |
| 5 | **Replace toggle with explicit controls** | [Pause] [End] buttons instead of Start/Stop toggle | Proposed |
| 6 | **"Forgot to end" protection** | Auto-pause at 5min silence, auto-end at 30min | Proposed |
| 7 | **24h pause expiration** | Paused sessions auto-finalize after 24 hours | Proposed |
| 8 | **Smart session switching** | Starting new session while paused prompts: resume or start new | Proposed |

### Session State Machine
```
IDLE ──Start──▶ LISTENING ──Pause──▶ PAUSED
  ▲                │                    │
  │                │ Stop/Auto-end      │ Resume
  │                ▼                    │
  └────────────── FINALIZED ◀───────────┘
```

### Silence Handling Tiers
| Duration | Action |
|----------|--------|
| 10-30s | Orange banner (existing) |
| 30s-5min | "Still listening?" toast notification |
| 5-30min | **Auto-pause** with notification |
| 30min+ | **Auto-end & save** with notification |

---

## Current State Analysis

### What's Implemented
| Feature | Status | Notes |
|---------|--------|-------|
| Start/Stop toggle | ✅ | Menu bar and menu command (⌘⇧L) |
| Session timer | ✅ | Elapsed time display |
| Auto-save to local | ✅ | `SessionStore` saves every 30s |
| Crash recovery | ✅ | Detects unfinished sessions on launch |
| Silence detection | ⚠️ | 10s threshold, only shows banner |
| Explicit end | ✅ | User must click "Stop Listening" |
| Export | ✅ | JSON and Markdown export |

### Current Pain Points
1. **Ambiguous session boundaries**: User doesn't know when a session "should" end
2. **No pause/resume**: All-or-nothing approach wastes transcription quota on breaks
3. **Silence handling is passive**: Only a banner, no proactive prompts
4. **Single session only**: Cannot have parallel or overlapping sessions
5. **No "forgot to stop" protection**: Session could run for hours unattended
6. **Manual save required**: User must remember to export, though auto-save exists locally

---

## Proposed Session Lifecycle

### Session States

```
┌─────────┐    Start     ┌──────────┐   Pause    ┌─────────┐
│  IDLE   │ ───────────▶ │ LISTENING│ ─────────▶│ PAUSED  │
└─────────┘              └──────────┘           └─────────┘
     ▲                        │                      │
     │                        │ Resume               │
     │                        │                      │
     │                   Stop │◀─────────────────────┘
     │                        │
     │                        ▼
     │                   ┌──────────┐
     └───────────────────│ FINALIZED│
        Auto-save        └──────────┘
```

### State Definitions

| State | Description | Visual Indicator |
|-------|-------------|------------------|
| `idle` | No active session, ready to start | Gray status pill |
| `listening` | Capturing and transcribing audio | Green pulsing indicator + timer |
| `paused` | Audio capture suspended, session retained | Yellow/amber indicator |
| `finalizing` | Processing final summary | Orange spinner |
| `error` | Permission or connection issue | Red badge |

---

## Detailed UX Specifications

### 1. Starting a Session

#### Primary Entry Point
- **Menu Bar Button**: Single click toggles Start/Stop
- **Keyboard Shortcut**: ⌘⇧L (unchanged)
- **Side Panel**: Large prominent "Start Listening" button when idle

#### Pre-flight Checklist (Before Starting)
```swift
// Pseudo-code for start flow
func startSessionWithChecks() {
    1. Check backend ready → Show preparing state if not
    2. Check permissions → Open settings if needed
    3. Check for recoverable session → Offer resume
    4. Validate audio source selection
    5. Start session → Transition to .listening
}
```

#### Audio Source Confirmation
- If source is "System Audio" and no audio detected in 5s, show:
  > "No system audio detected. Is your meeting app playing audio? Try switching to 'Both' if you're speaking too."

---

### 2. During Active Listening

#### Real-time Feedback
| Element | Behavior |
|---------|----------|
| Timer | MM:SS format, increments every second |
| Audio level meters | Real-time visualization |
| Status pill | "Listening" with green pulsing dot |
| Waveform icon | Animates in menu bar when active |

#### Silence Detection & Handling

**Tier 1: Short Silence (10-30 seconds)**
- Current: Orange banner with message
- Proposed: Keep banner, add subtle audio cue (optional)

**Tier 2: Medium Silence (30 seconds - 5 minutes)**
- Proposed: "Still listening?" toast notification
- Actions: [Continue] [Pause] [Stop & Save]

**Tier 3: Extended Silence (5+ minutes)**
- Proposed: Auto-pause with notification
- Message: "Session auto-paused due to silence. Resume when meeting continues."
- Session remains in `paused` state for up to 24 hours

**Tier 4: Very Extended (30+ minutes)**
- Proposed: Auto-finalize with notification
- Message: "Session ended automatically after 30 minutes of silence. Your notes have been saved."

#### Manual Controls During Listening

**In Side Panel Footer:**
```
[⏸ Pause] [⏹ End Session]  [Timer: 12:34]
```

**Pause Behavior:**
- Audio capture stops
- WebSocket connection maintained (or gracefully paused)
- Session state preserved in memory
- Timer pauses
- Resume continues from where left off

**Pause Use Cases:**
- Coffee break during long meeting
- Switching between back-to-back meetings
- Temporary discussion that shouldn't be transcribed

---

### 3. Paused Sessions

#### Pause State UI
- Status pill: "Paused · 12:34 elapsed"
- Audio meters: Static/grayed
- Footer: `[▶ Resume] [⏹ End Session] [Discard]`

#### Auto-Resume Detection (Optional)
- If audio detected above threshold while paused, offer:
  > "Audio detected. Resume session? [Resume] [Ignore]"

#### Session Expiration
- Paused sessions expire after 24 hours
- User notification: "Your paused session from yesterday has been saved. Start a new session?"

#### Parallel Session Prevention
- While paused, user can start a **new** session
- If attempted, show confirmation:
  > "Starting a new session will finalize your paused session (12:34 recorded). Continue?"
- This creates a **session history**, not parallel active sessions

---

### 4. Ending a Session

#### Explicit End (User Action)

**Confirmation Dialog for Long Sessions (>30 min):**
```
┌─────────────────────────────────────┐
│  End Session                        │
├─────────────────────────────────────┤
│  You've been listening for 45:23.   │
│                                     │
│  [⏸ Pause Instead] [End & Save]     │
└─────────────────────────────────────┘
```

**Finalization Flow:**
1. User clicks "End Session"
2. UI transitions to `finalizing` state
3. Backend processes final summary (up to 10s timeout)
4. Session saved locally (auto)
5. UI transitions to `idle`
6. Summary window opens (existing behavior)

#### Auto-End Scenarios

| Trigger | Action | Notification |
|---------|--------|--------------|
| 30+ min silence | Auto-finalize | "Session auto-ended after silence" |
| App quit while listening | Auto-save recovery state | None (silent) |
| System sleep | Auto-pause | Resume on wake |
| Crash | Recovery on relaunch | "Resume previous session?" |

---

### 5. Session History & Management

#### Session List View
- Access: Menu → "Session History" (⌘⇧H)
- Shows: All sessions from today + past 7 days
- States shown:
  - 🟢 Live (currently listening)
  - 🟡 Paused (can resume)
  - ⚪ Completed (finalized)
  - 🔴 Incomplete (crashed/interrupted)

#### Session Actions
| Action | Available When |
|--------|----------------|
| Resume | Paused sessions < 24h old |
| View Summary | All completed sessions |
| Export | All sessions |
| Rename | All sessions |
| Delete | All sessions |
| Merge | Multiple selected completed |

---

### 6. Auto-Save Strategy

#### Current Implementation (✅ Keep)
```swift
// SessionStore.swift - Existing behavior
- Save every 30 seconds during active session
- Append-only transcript log
- Recovery marker for crash detection
```

#### Proposed Enhancements

**Always-Save Philosophy:**
- ✅ All sessions saved locally automatically
- ✅ No "Save" dialog required
- ✅ Background auto-save every 30s
- ✅ On significant events (pause, silence detected, etc.)

**Export vs. Save Distinction:**
| Concept | Behavior |
|---------|----------|
| **Save** | Automatic, local only, never prompts user |
| **Export** | User-initiated, chooses format/location |

**Storage Management:**
- Keep last 30 days locally
- Auto-archive older sessions to compressed storage
- Show storage usage in Settings

---

## UI Components Specification

### 1. Main Control Button States

```swift
enum ControlButtonState {
    case startNew           // "Start Listening" (green, prominent)
    case resumePaused       // "Resume Session" (blue, shows duration)
    case pause              // "Pause" (secondary, in listening)
    case end                // "End Session" (red outline, in listening)
    case finalizing         // Disabled with spinner
}
```

### 2. Session Status Display

**Compact Mode (Menu Bar):**
```
[waveform] 12:34  (pulsing green when listening)
```

**Side Panel Header:**
```
EchoPanel          ┌─────────┐
Listening...       │ 12:34   │  [⏸] [⏹]
Active session     └─────────┘
```

### 3. Notification Toast Design

```swift
struct SessionNotification {
    let title: String
    let message: String
    let actions: [NotificationAction]
    let autoDismiss: Bool
    let duration: TimeInterval
}

// Example: Silence prompt
SessionNotification(
    title: "Still listening?",
    message: "No audio detected for 2 minutes",
    actions: [
        .init(title: "Continue", style: .primary),
        .init(title: "Pause", style: .secondary),
        .init(title: "End", style: .destructive)
    ],
    autoDismiss: false
)
```

---

## Edge Cases & Scenarios

### Scenario 1: User Forgets to End
**Current:** Session runs indefinitely, potentially for hours  
**Proposed:**
- 5 min silence → Toast notification
- 30 min silence → Auto-pause with notification
- User can resume or end from notification

### Scenario 2: Back-to-Back Meetings
**Current:** Must stop and start new session  
**Proposed:**
- End first session → Auto-opens summary
- One-click "Start Next Session" in summary window
- Optional: Auto-start after 5 min gap detection

### Scenario 3: Interrupted by System Sleep
**Current:** Unknown behavior  
**Proposed:**
- On sleep: Auto-pause session
- On wake: Offer to resume with "Meeting may have ended" warning

### Scenario 4: App Crash During Session
**Current:** Recovery marker, offers to export on relaunch  
**Proposed:**
- Same recovery mechanism
- Enhanced: Show session preview before recovery decision
- Option to "Save as incomplete" without resuming

### Scenario 5: Long Meeting with Break
**Current:** Must keep listening through break or end and start new  
**Proposed:**
- Pause during break (timer stops)
- Resume after break (continues same session)
- Single export for entire day

### Scenario 6: Parallel Sessions Attempt
**Current:** Not possible, second start ignored  
**Proposed:**
- Clear messaging: "You have a paused session (45:23). Start new or resume?"
- Prevents accidental data fragmentation

---

## Implementation Phases

### Phase 1: Core Pause/Resume (High Impact)
- [ ] Add `paused` session state
- [ ] Implement pause/resume logic in `AppState`
- [ ] Update UI controls for pause state
- [ ] Add pause button to side panel footer

### Phase 2: Smart Silence Handling (Medium Impact)
- [ ] Implement tiered silence detection
- [ ] Add notification toast system
- [ ] Auto-pause on extended silence
- [ ] Settings for silence thresholds

### Phase 3: Session Management (Nice to Have)
- [ ] Enhanced session history view
- [ ] Session preview in recovery dialog
- [ ] Storage management settings
- [ ] Session merge functionality

### Phase 4: Advanced Features (Future)
- [ ] Auto-detect meeting end via calendar integration
- [ ] ML-based meeting boundary detection
- [ ] Voice command: "Hey Echo, pause"

---

## Configuration Options

### User Preferences (Settings)

```swift
struct SessionPreferences {
    // Silence handling
    var autoPauseAfterSilence: TimeInterval? = 300  // 5 min default
    var autoEndAfterSilence: TimeInterval? = 1800   // 30 min default
    
    // Notifications
    var silenceWarningEnabled: Bool = true
    var silenceWarningThreshold: TimeInterval = 30
    
    // Auto-save
    var autoSaveInterval: TimeInterval = 30
    var retentionDays: Int = 30
    
    // Session behavior
    var confirmEndForLongSessions: Bool = true
    var autoOpenSummary: Bool = true
}
```

---

## Metrics to Track

| Metric | Purpose |
|--------|---------|
| Avg session duration | Understand usage patterns |
| Pause frequency | Validate pause feature utility |
| Auto-pause triggers | Tune silence thresholds |
| Forgot-to-stop rate | Measure auto-end effectiveness |
| Recovery rate | Assess crash handling |

---

## Open Questions

1. **Should we allow truly parallel sessions?**  
   Proposal: No, but allow rapid switching between paused/active.

2. **How long should paused sessions live?**  
   Proposal: 24 hours, then auto-finalize.

3. **Should silence detection vary by source?**  
   Proposal: Yes, system audio vs. mic may have different thresholds.

4. **Calendar integration for auto-start/stop?**  
   Proposal: Phase 4 feature, requires user opt-in.

5. **Should auto-saved sessions be visible in history immediately?**  
   Proposal: Yes, with "In Progress" label.

---

## Appendix: State Machine Diagram

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                                                         │
                    ▼                                                         │
┌────────┐    ┌──────────┐    Pause      ┌─────────┐    Resume    ┌─────────┐ │
│  IDLE  │───▶│ LISTENING│──────────────▶│ PAUSED  │─────────────▶│ LISTENING│─┘
└────────┘    └──────────┘               └─────────┘              └─────────┘
                  │                                                        │
                  │ Stop / Auto-end                                        │ Stop
                  │                                                        ▼
                  ▼                                                   ┌──────────┐
             ┌──────────┐                                             │ FINALIZED│
             │ FINALIZED│                                             └──────────┘
             └──────────┘                                                  │
                  │                                                        │
                  ▼                                                        ▼
             ┌──────────┐                                             ┌──────────┐
             │   IDLE   │                                             │  SAVED   │
             └──────────┘                                             └──────────┘
```

---

## References

- `docs/LIVE_LISTENER_SPEC.md` - Original streaming specification
- `macapp/MeetingListenerApp/Sources/AppState.swift` - Session state management
- `macapp/MeetingListenerApp/Sources/SessionStore.swift` - Local persistence
- `docs/WORKLOG_TICKETS.md` - Implementation tracking
