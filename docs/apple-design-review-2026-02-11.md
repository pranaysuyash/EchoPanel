# EchoPanel macOS — Apple-Level Design Review

**Date:** 2026-02-11  
**Reviewed:** macOS SwiftUI implementation (Onboarding, SidePanel, Menu Bar, Summary, History)  
**Reviewer Perspective:** Native macOS app critique against Apple HIG, platform conventions, and product clarity

---

## Executive Summary

EchoPanel is a technically sophisticated menu bar utility with a well-structured SwiftUI implementation. The codebase demonstrates strong engineering practices: comprehensive accessibility support, responsive layout with `ViewThatFits`, and thoughtful keyboard navigation. However, the product has **identity tension**—it doesn't clearly commit to being a passive background tool or an active workspace panel, resulting in UX ambiguity at critical moments.

**Verdict:** Solid foundation with several high-impact polish opportunities that would elevate it to "App Store Feature" quality.

---

## 1. Product Clarity: What Is This App?

### Current State
The app presents three competing identities:
1. **Menu bar utility** — passive presence, occasional glance
2. **Side panel companion** — active reference during meetings
3. **Transcript archive** — post-meeting review tool

### Issues

| Issue | Severity | Evidence |
|-------|----------|----------|
| "MeetingListener" naming is generic | Medium | Product name doesn't convey value proposition |
| Three view modes (Roll/Compact/Full) confuse the core metaphor | High | SidePanelView.swift:6-11 — no clear default recommendation |
| "Surfaces" concept requires learning | Medium | Abstract term for what are essentially "smart filters" |
| No clear empty state for first-time value | Medium | Onboarding ends at "Ready" without aha moment |

### Recommendations

1. **Lead with Roll mode as the default** — it's the most differentiated and visually compelling. The receipt metaphor is strong; lead with it.

2. **Rename "Surfaces" to "Highlights" or "Insights"** — the current term is jargon. "Highlights" matches the highlight mode picker and user mental model.

3. **Add a "First Session" experience** — after onboarding, auto-open with demo transcript or tooltips, not an empty panel.

---

## 2. Platform Conventions & macOS Fit

### What's Done Well

| Convention | Implementation | Location |
|------------|----------------|----------|
| Menu bar extra with dropdown | `MenuBarExtra` with `.menu` style | MeetingListenerApp.swift:36 |
| Keyboard shortcuts via `CommandMenu` | Full suite (⌘⇧L, ⌘⇧C, etc.) | MeetingListenerApp.swift:61-90 |
| Window management | `hiddenTitleBar` for onboarding | MeetingListenerApp.swift:115 |
| Native system integration | URL scheme deep-link to System Settings | OnboardingView.swift:179-183 |
| Responsive layout | `ViewThatFits` throughout | SidePanelLayoutViews.swift:106 |
| Reduce Motion respect | `@Environment(\.accessibilityReduceMotion)` | SidePanelView.swift:110 |

### Issues

#### A. Window Behavior Inconsistency
```swift
// MeetingListenerApp.swift — window definitions
Window("Get Started", id: "onboarding") { ... }  // 500×400 fixed
Window("Session Summary", id: "summary") { ... }  // 820×620 min
Window("Session History", id: "history") { ... }  // 980×620 min
```

The onboarding is a fixed-size panel while others are resizable. **Recommendation:** Make onboarding resizable or use `.fixedSize()` consistently. The hardcoded 500×400 feels like a dialog, but the content suggests a wizard.

#### B. Menu Bar Icon State Feedback
Current icon changes based on state, but the states aren't visually distinct enough:
- Idle: waveform
- Listening: waveform (same)
- Paused: waveform (subtle change)

**Recommendation:** Use more distinct SF Symbols:
- Idle: `waveform` (outline)
- Listening: `waveform.circle.fill` (filled, pulsing optional)
- Paused: `pause.circle` or `waveform.slash`

#### C. Settings Window Missing
The app has inline settings in the menu dropdown but no dedicated Settings window (⌘,). This breaks macOS convention.

**Recommendation:** Add a standard Settings window accessible via ⌘, and the menu.

---

## 3. Interaction Design

### Strengths

1. **Keyboard Navigation** — Comprehensive arrow key support, space for follow toggle, P for pin. The shortcut overlay (?) is discoverable.

2. **Focus State Clarity** — TranscriptLineRow shows focused state with background change and action buttons appearing. Clean implementation:
```swift
// SidePanelSupportViews.swift:112-133
.frame(width: isFocused ? Layout.actionContainerWidth : 0, alignment: .trailing)
.opacity(isFocused ? 1 : 0)
.animation(.easeInOut(duration: AnimationDuration.quick), value: isFocused)
```

3. **Drag to Unfollow** — Natural gesture: dragging scroll disables live following.

### Issues

#### A. Double-Tap Confusion
```swift
// SidePanelTranscriptSurfaces.swift:117-129
.onTapGesture { focusedSegmentID = segment.id }
.onTapGesture(count: 2) { /* toggle lens */ }
```

Single and double tap on the same element creates interaction ambiguity. Users may trigger single-tap actions when attempting double-tap.

**Recommendation:** Use single-tap for focus, long-press or dedicated button for lens.

#### B. Pin/Lens Model Is Abstract
"Pins" and "Lens" are developer concepts. Users think in "bookmarks" and "focus/details".

**Recommendation:** Consider renaming in UI:
- "Pin" → "Save" or "Star"
- "Lens" → "Details" or "Expand"

#### C. Jump Live Button Position
The "Jump Live" button appears in multiple places (toolbar, footer, after scrolling) with inconsistent styling:
- Sometimes `.borderedProminent`
- Sometimes plain text with count

**Recommendation:** Standardize. Use a floating pill (like Maps/Find My) when scrolled back:
```swift
// Concept:
.overlay(alignment: .bottom) {
    if !followLive {
        Button("Jump to Live") { ... }
            .buttonStyle(.borderedProminent)
    }
}
```

---

## 4. Privacy UX

### Strengths

1. **Bundle Privacy Levels** — Excellent implementation:
```swift
// SessionBundle.swift
enum BundlePrivacyLevel { case noAudio, metadataOnly, fullAudio }
```

2. **Session Bundle Safety** — Explicit opt-in for audio inclusion. No raw audio in logs.

3. **Transparency in UI** — Quality chips show audio status; permission banners appear inline.

### Issues

#### A. Permission Request Timing
Screen Recording permission is asked immediately during onboarding. This is the most sensitive permission on macOS. Users don't yet trust the app.

**Recommendation:** Defer permission request until user attempts first recording. Show value first, then ask.

#### B. No Privacy Dashboard
Users can't see what's been recorded, how long transcripts are retained, or manage deletion easily.

**Recommendation:** Add a "Privacy & Data" section in Settings showing:
- Storage used by transcripts
- Retention policy (auto-delete after X days)
- One-tap "Delete All History"

#### C. Diarization Token Handling
The HF token is stored in Keychain (good), but the onboarding presents it as optional without explaining value.

**Recommendation:** Show before/after example: "Add speaker names to your transcripts with diarization."

---

## 5. Accessibility

### Strengths

1. **Comprehensive AX support** — rotor entries, sort priorities, accessibility labels:
```swift
// SidePanelTranscriptSurfaces.swift:14-18
.accessibilityRotor("Transcript Segments") {
    ForEach(visibleTranscriptSegments) { segment in
        AccessibilityRotorEntry(transcriptRotorLabel(for: segment), id: segment.id)
    }
}
```

2. **Reduced motion support** — Checks `@Environment(\.accessibilityReduceMotion)` before animating.

3. **Dynamic Type readiness** — Uses relative font sizes via Typography tokens.

### Issues

#### A. Audio Level Meters Lack Full AX Support
```swift
// SidePanelSupportViews.swift:506-507
.accessibilityElement(children: .ignore)
.accessibilityLabel("\(label) audio level")
.accessibilityValue("\(Int(level * 100)) percent")
```

Good start, but should announce changes for VoiceOver users (e.g., "System audio detected" vs silence).

#### B. No Live Region for Transcript Updates
New transcript lines aren't announced to VoiceOver users. They must manually check.

**Recommendation:** Add `.accessibilityAnnouncement` for new content when followLive is true:
```swift
// Concept:
.onChange(of: visibleTranscriptSegments.count) { _ in
    if followLive {
        // Announce newest segment briefly
    }
}
```

#### C. Keyboard Shortcuts Not Discoverable
The ? overlay is great, but shortcuts don't appear in macOS standard Help menu.

**Recommendation:** Add to `CommandGroup(.help)`.

---

## 6. Visual Design & Polish

### Strengths

1. **Design Tokens Architecture** — Excellent systematization:
```swift
// DesignTokens.swift
CornerRadius.xs(6), .sm(8), .md(10), .lg(12), .xl(16)
Spacing.xs(4), .sm(8), .md(12), .lg(16), .xl(20)
```

2. **Consistent 8pt Grid** — Proper baseline alignment.

3. **Semantic Color Usage** — BackgroundStyle enum adapts to colorScheme properly.

### Issues

#### A. Corner Radius Inconsistency
```swift
// SidePanelView.swift:177
.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))  // Why 18?
```

18pt doesn't exist in DesignTokens. Use `CornerRadius.xl` (16) or add a new token.

#### B. Shadow Implementation
```swift
// SidePanelChromeViews.swift:81
.shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 14, x: 0, y: 8)
```

Hardcoded shadow values. Add to DesignTokens as `ShadowStyle`.

#### C. Color Scheme Checks Are Repetitive
```swift
// Pattern seen throughout:
Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
```

**Recommendation:** Create semantic color tokens:
```swift
// DesignTokens.swift addition:
enum ShadowStyle {
    static var panel: Color { 
        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
    }
}
```

#### D. Status Pill Colors
```swift
// SidePanelChromeViews.swift:153-166
Circle()
    .fill(sessionStatusColor)
    .frame(width: 7, height: 7)  // Odd number, not on 4pt grid
```

Use 8pt (4pt grid) or 6pt (8pt grid with half-step).

---

## 7. Information Architecture

### Current Hierarchy
```
EchoPanel
├── Menu Bar (status + quick actions)
├── Side Panel (live transcript)
│   ├── Roll/Compact/Full modes
│   └── Surfaces overlay
├── Summary Window (post-session)
├── History Window (archive)
└── Settings (inline in menu)
```

### Recommendation: Simplify to Two Modes

**Mode A: Companion (default)**
- Side panel only
- Roll or Compact view
- Minimal chrome
- For: Active meeting participation

**Mode B: Review**
- History window
- Full transcript analysis
- For: Post-meeting cleanup

The "Full" view mode and Summary window overlap in purpose. Consider consolidating.

---

## 8. Implementation Notes

### Code Quality: Excellent
- Comprehensive use of `@MainActor` implied patterns
- Proper memory management with weak self in callbacks
- Good separation of concerns (AppState, SessionStore, etc.)

### Potential Issues

#### A. State Synchronization Complexity
SidePanelView has ~20 `@State` variables. Risk of desynchronization:
```swift
// SidePanelView.swift
@State var viewMode: ViewMode = .roll
@State var followLive = true
@State var highlightMode: EntityHighlighter.HighlightMode = .extracted
// ... 17 more
```

**Recommendation:** Consider a `SidePanelViewModel` ObservableObject to centralize state.

#### B. Cache Invalidation
```swift
// SidePanelView.swift:98-103
struct FilterCacheKey: Equatable {
    let transcriptRevision: Int
    let entityFilterID: UUID?
    let normalizedFullQuery: String
    let viewMode: ViewMode
}
```

Good pattern, but ensure `transcriptRevision` increments atomically.

#### C. Keyboard Monitor Lifecycle
```swift
// SidePanelView.swift:202-207
.onAppear { installKeyboardMonitor() }
.onDisappear { removeKeyboardMonitor() }
```

NSEvent monitors can leak. Ensure remove is called reliably (onDisappear may not fire in all dismissal scenarios).

---

## 9. Priority Recommendations

### P0 — Must Fix Before 1.0
1. **Fix permission timing** — Don't ask for Screen Recording until user tries to record
2. **Standardize window sizing** — All windows should follow same resize model
3. **Add Settings window** — Standard ⌘, convention

### P1 — High Impact Polish
1. **Lead with Roll mode** — Remove mode picker prominence, default to Roll
2. **Rename Surfaces → Highlights** — Better mental model
3. **Standardize Jump Live button** — Floating pill pattern
4. **Add Privacy dashboard** — Build trust through transparency

### P2 — Nice to Have
1. **Reduce @State count** — Extract to ViewModel
2. **Add Settings to DesignTokens** — Shadow, semantic colors
3. **AX live regions** — Announce new transcript to VoiceOver
4. **Menu bar icon states** — More distinct symbols

---

## 10. Competitive Positioning

### EchoPanel's Differentiation
- **Local-first processing** — Privacy advantage, market it
- **Receipt metaphor** — Unique visual identity (lean into this)
- **Multi-source audio** — System + Mic is genuinely useful

### Gaps vs. Competitors
- No cloud sync (could be pro feature)
- No iOS companion (ecosystem play)
- No integrations (Slack, Notion export)

---

## Conclusion

EchoPanel is **85% of the way to a best-in-class macOS utility**. The engineering is solid, the accessibility is thoughtful, and the visual design shows care. The remaining work is **editorial, not technical** — clarifying the product narrative, simplifying the conceptual model, and ensuring every interaction reinforces the core value: "Never miss what matters in meetings."

**Three things to do this week:**
1. Default to Roll mode, make others secondary
2. Add Privacy dashboard in Settings
3. Fix permission request timing

**One thing to consider this month:**
- Is this a menu bar utility or a workspace panel? The answer determines whether "Full mode" and the Summary window should exist as separate concepts, or merge into a unified "Studio" view.

---

*Review conducted with reference to:*
- Apple Human Interface Guidelines (macOS)
- SwiftUI Accessibility best practices
- Privacy-preserving design patterns
- Native macOS app conventions

*Files reviewed:*
- OnboardingView.swift (476 lines)
- MeetingListenerApp.swift (562 lines)
- SidePanelView.swift (295 lines)
- SidePanelTranscriptSurfaces.swift (496 lines)
- SidePanelSupportViews.swift (520 lines)
- SidePanelLayoutViews.swift (247 lines)
- SidePanelChromeViews.swift (354 lines)
- DesignTokens.swift (311 lines)
- SummaryView.swift (287 lines)
- SessionHistoryView.swift (420 lines)
