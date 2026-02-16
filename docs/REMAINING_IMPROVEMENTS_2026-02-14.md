# EchoPanel Remaining Improvements

**Date**: 2026-02-14  
**Status**: Post-free-tier removal, paid-only model  
**Goal**: Document, plan, and implement remaining P0/P1 improvements

> **Update (2026-02-16):** Most P0/P1 items in this document were implemented under the `TCK-20260214-08x` series.
> Canonical disposition and ticket mapping now lives in `docs/EXPLORATION_ACTION_TRIAGE_2026-02-16.md`.

---

## Executive Summary

After removing the free tier (paid-only model), these improvements remain to achieve launch readiness:

| Priority | Count | Impact |
|----------|-------|--------|
| P0 (Launch Blocker) | 4 | Accessibility, onboarding flow, UX |
| P1 (High Value) | 5 | User experience, discoverability |
| P2 (Polish) | 3 | Nice-to-have improvements |

---

## P0 Improvements (Must Fix Before Launch)

### P0-1: Accessibility - Confidence Text for VoiceOver

**Problem**: Color-only confidence indicators (red/green) are not accessible to VoiceOver users

**Location**: `macapp/MeetingListenerApp/Sources/EntityHighlighter.swift`, transcript rows

**Current**: 
```swift
// Uses .red/.green colors only
Text(segment.text)
    .foregroundColor(confidenceColor)
```

**Required**:
- Add explicit confidence percentage text (e.g., "Confidence: 85%")
- Add VoiceOver label with confidence level
- Keep color as secondary indicator

**Files to Modify**:
- `SidePanelSupportViews.swift` - TranscriptLineRow
- `EntityHighlighter.swift` - confidence display

**Effort**: 2-3 hours

---

### P0-2: Onboarding - Permission Gate

**Problem**: Users can proceed through onboarding without granting Screen Recording permission, leading to silent session failures

**Location**: `macapp/MeetingListenerApp/Sources/OnboardingView.swift`

**Current**: Next button enabled even if permission denied

**Required**:
- Block progression at permissions step until Screen Recording granted
- OR show explicit warning dialog if proceeding without permission
- Add "Check Permission" button that verifies access

**Files to Modify**:
- `OnboardingView.swift` - Permissions step logic

**Effort**: 4-6 hours

---

### P0-3: Menu Bar - Server Status Badge

**Problem**: Users can't see backend readiness without opening the menu

**Location**: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift` - labelContent

**Current**: Green/orange dot overlay exists but could be more visible

**Required**:
- Verify status badge is clearly visible
- Consider animation when status changes
- Add tooltip with detailed status

**Note**: This may already be implemented - verify and enhance if needed

**Files to Modify**:
- `MeetingListenerApp.swift` - Menu bar icon/badge

**Effort**: 1-2 hours (verification/enhancement)

---

### P0-4: SidePanel - Empty State Placeholder

**Problem**: Side panel shows blank when no transcript segments exist - users think app is broken

**Location**: `macapp/MeetingListenerApp/Sources/SidePanel/`

**Current**: Empty view with no guidance

**Required**:
- Add placeholder: "Transcript will appear here as people speak"
- Add troubleshooting hints ("Check audio source", "Verify permissions")
- Show spinner when waiting for first segment

**Files to Modify**:
- `SidePanelTranscriptSurfaces.swift` - Empty state view
- `SidePanelChromeViews.swift` - Empty state component

**Effort**: 3-4 hours

---

## P1 Improvements (High Value)

### P1-2: Search - Escape Key to Close

**Problem**: Cmd+F opens search but Escape doesn't close it in Full mode

**Location**: `macapp/MeetingListenerApp/Sources/SidePanel/Full/SidePanelFullViews.swift`

**Required**:
```swift
.onKeyPress(.escape) {
    isSearching = false
}
```

**Files to Modify**:
- `SidePanelFullViews.swift` - Search field

**Effort**: 30 minutes

---

### P1-4: Export - Format Guidance

**Problem**: Export formats (JSON, Markdown, Bundle) are unclear to users

**Location**: Export menu in MenuBarExtra

**Current**:
```
Export JSON
Export Markdown
```

**Required**:
```
Export for Notes (Markdown)
Export for Apps (JSON)
Export Everything (Bundle)
```

**Files to Modify**:
- `MeetingListenerApp.swift` - Menu bar export items

**Effort**: 1 hour

---

### P1-5: Menu Bar - First-Time User Hint

**Problem**: Menu bar shows "Idle" but no prompt for first-time users

**Location**: `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`

**Required**:
- When idle and no sessions recorded yet, show "Click to start"
- Or add tooltip: "Click to start your first session"

**Files to Modify**:
- `MeetingListenerApp.swift` - Menu bar label

**Effort**: 1-2 hours

---

### P1-6: Crash Reporting Foundation

**Problem**: No visibility into production crashes

**Required**:
- Implement `NSSetUncaughtExceptionHandler`
- Log crashes to local file
- Add "Send Crash Report" button in Diagnostics
- Store last 5 crash logs

**Files to Create**:
- `CrashReporter.swift` - New file

**Files to Modify**:
- `MeetingListenerApp.swift` - Register handler
- `DiagnosticsView.swift` - Show crash reports

**Effort**: 4-6 hours

---

### P1-7: Mode Switcher Tooltips

**Problem**: Roll/Compact/Full modes are unexplained

**Location**: Side panel mode switcher

**Required**:
- Add tooltips:
  - Roll: "Live meetings - auto-scrolls with new speech"
  - Compact: "Quick look - minimal footprint"
  - Full: "Review mode - search and analyze"

**Files to Modify**:
- `SidePanelChromeViews.swift` - Mode picker

**Effort**: 1 hour

---

## P2 Improvements (Polish)

### P2-1: Design Token Consistency

**Problem**: Corner radii vary (6/8/10/12/16/18pt)

**Required**:
- Audit all `.cornerRadius()` and `.clipShape()` calls
- Standardize on DesignTokens enum values

**Files to Modify**:
- Multiple view files

**Effort**: 4-6 hours

---

### P2-2: Recent Sessions in Menu

**Problem**: Session recovery not obvious

**Required**:
- Add "Recent Sessions" submenu with last 3 sessions
- Show date and duration

**Files to Modify**:
- `MeetingListenerApp.swift` - Menu bar

**Effort**: 2-3 hours

---

### P2-3: VoiceOver Rotor

**Problem**: Blind users cannot navigate efficiently between speakers

**Required**:
- Implement `AccessibilityRotorContent` for speaker navigation

**Files to Modify**:
- `SidePanelTranscriptSurfaces.swift`

**Effort**: 3-4 hours

---

## Implementation Roadmap

### Week 1: P0 Blockers

**Day 1-2**: P0-1 Accessibility (confidence text)
- Modify TranscriptLineRow
- Add VoiceOver labels
- Test with VoiceOver

**Day 3-4**: P0-2 Onboarding permission gate
- Implement hard gate or warning
- Test flow with denied permissions

**Day 5**: P0-3 & P0-4 Status visibility & empty state
- Verify/enhance menu bar badge
- Create empty state placeholder

### Week 2: P1 Quick Wins + Crash Reporting

**Day 1**: P1-2, P1-4, P1-5 (Quick wins)
- Escape to close search
- Export format labels
- Menu bar first-time hint

**Day 2-3**: P1-6 Crash reporting
- Implement CrashReporter
- Add Diagnostics integration

**Day 4-5**: P1-7 Mode tooltips + P2 items
- Mode switcher tooltips
- Recent sessions menu (if time)

---

## Acceptance Criteria Summary

### P0 Complete When:
- [x] VoiceOver announces confidence for each transcript segment (`TCK-20260213-017` follow-up, validated in transcript row accessibility labels)
- [x] Onboarding blocks progression without Screen Recording permission (`TCK-20260214-080` / P0-2 section)
- [x] Menu bar shows clear server status at a glance (`TCK-20260214-081`)
- [x] Side panel shows helpful empty state before first transcript (`TCK-20260214-082`)

### P1 Complete When:
- [x] Escape key closes search in Full mode (`TCK-20260214-083`)
- [x] Export menu shows descriptive labels (`TCK-20260214-086`)
- [x] First-time users see guidance in menu bar (`TCK-20260214-087`)
- [x] Crash reports are captured locally (`TCK-20260214-084`)
- [x] Mode switcher has explanatory tooltips (`TCK-20260214-088`)

---

## Testing Checklist

- [ ] Test with VoiceOver enabled
- [ ] Test onboarding with denied permissions
- [ ] Test empty state with new user
- [ ] Verify all keyboard shortcuts work
- [ ] Test crash reporter (simulate crash)
- [x] Verify no regressions in Swift tests

---

**Next Step (2026-02-16):** Execute remaining manual verification and exploration tickets via
`DOC-003`, `TCK-20260214-074`, `TCK-20260214-075`, and `TCK-20260216-001` through `TCK-20260216-012`.
