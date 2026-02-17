> **⚠️ OBSOLETE (2026-02-16):** Core UI findings from this audit have been addressed:
> - Focus indicator: system focus ring color (TCK-20260213-061)
> - Search: Escape closes, Cmd+K works (TCK-20260213-063)
> - Terminology: unified "End Session" (TCK-20260213-069)
> - Onboarding: step labels "Step X of Y" (TCK-20260213-071)
> - Design tokens: `DesignTokens.swift` created with semantic color tokens
> - Export notices: user-visible success/failure/cancel banners (U6 fix)
> Remaining items (pinned segment persistence, NSToolbar for Full mode) are deferred polish.
> Moved to archive.

# EchoPanel macOS Frontend — UI/UX Audit Report

**Auditor:** Apple Developer Expert (UI/UX Focus)  
**Date:** 2026-02-09  
**Scope:** macapp/MeetingListenerApp — All Swift source files  
**App Version:** v0.2 (pre-launch)  
**Platform:** macOS 13+ (Ventura and later)

---

## Update (2026-02-13)

This audit is a point-in-time review from 2026-02-09. Several findings below are now stale due to subsequent refactors and hardening work:

- `SidePanelView.swift` is no longer a 2,700+ line monolith; transcript chrome/surfaces were split into `macapp/MeetingListenerApp/Sources/SidePanel/*` and shared subviews/state types. Evidence: `macapp/MeetingListenerApp/Sources/SidePanelView.swift` (current file size is small), `macapp/MeetingListenerApp/Sources/SidePanel/Shared/`.
- HuggingFace token storage is no longer `UserDefaults`; it is stored via Keychain helper with legacy migration cleanup. Evidence: `macapp/MeetingListenerApp/Sources/KeychainHelper.swift` (HF token storage + migration), `macapp/MeetingListenerApp/Sources/SettingsView.swift` (token save path).
- Visual snapshot tests exist (opt-in) for side panel layouts and streaming states. Evidence: `macapp/MeetingListenerApp/Tests/SidePanelVisualSnapshotTests.swift`, `macapp/MeetingListenerApp/Tests/StreamingVisualTests.swift`.
- Entity highlights are exposed to accessibility via an explicit SwiftUI accessibility representation and the underlying `NSTextView` has labels reflecting highlighted entities. Evidence: `macapp/MeetingListenerApp/Sources/EntityHighlighter.swift`, `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelSupportViews.swift`.
- Focus indicator contrast now uses system focus ring color (`NSColor.keyboardFocusIndicatorColor`) and selection tint uses `Color.accentColor` (instead of hardcoded blue) for better contrast and user-configured accent support. Evidence: `macapp/MeetingListenerApp/Sources/DesignTokens.swift`.

Remaining (still potentially relevant) suggestions from this audit include persisting pinned segments across app relaunches and deeper keyboard/focus interaction testing (not addressed in this update).

## Executive Summary

The EchoPanel macOS app is a menu-bar-based meeting transcription companion with an ambitious three-mode UI (Roll/Compact/Full) that demonstrates solid SwiftUI engineering. The codebase shows evidence of iterative refinement with attention to accessibility, responsive layout, and Apple platform conventions. However, there are several areas requiring attention before launch — ranging from minor HIG violations to architectural concerns about view complexity.

**Overall Grade: B+** — Solid foundation with polish needed before App Store submission.

---

## 1. Architecture Overview

### 1.1 File Organization

| File | Lines | Responsibility |
|------|-------|----------------|
| `SidePanelView.swift` | ~2,738 | Main UI monolith — all three view modes |
| `MeetingListenerApp.swift` | ~546 | App entry, menu bar, window definitions |
| `AppState.swift` | ~912 | Observable state, session lifecycle |
| `SidePanelController.swift` | ~99 | NSPanel controller, window management |
| `EntityHighlighter.swift` | ~219 | NLP + entity matching |
| `OnboardingView.swift` | ~410 | First-run wizard |
| `SummaryView.swift` | ~287 | Post-session summary window |
| `SessionHistoryView.swift` | ~420 | Historical session browser |
| `Models.swift` | ~62 | Core data types |

### 1.2 Key Patterns Observed

- **MVVM-ish:** `AppState` as central `@ObservableObject`, views observe state
- **Closure-based callbacks:** Audio/WebSocket managers use callback properties
- **Global keyboard monitoring:** `NSEvent.addLocalMonitorForEvents` in SidePanelView
- **AppStorage persistence:** View mode preference stored via `@AppStorage`
- **ViewThatFits:** Responsive layout using SwiftUI's adaptive container

---

## 2. UI Implementation Analysis

### 2.1 Three-Cut UI Model (Roll/Compact/Full)

The app implements a sophisticated "three-cut" presentation model:

```
┌─────────────────────────────────────────────────────────────┐
│ ROLL (460×760)     │ COMPACT (360×700)   │ FULL (1120×780)  │
├────────────────────┼─────────────────────┼──────────────────┤
│ Transcript-first   │ Minimal companion   │ Review + tools   │
│ Rolling window     │ Compact transcript  │ Session rail     │
│ Surface overlay    │ Surface overlay     │ Persistent panels│
│ 120 segments cap   │ 36 segments cap     │ 500 segments cap │
└────────────────────┴─────────────────────┴──────────────────┘
```

**Assessment:** This is a well-designed information architecture that maps to real use cases. The mode-specific segment caps prevent memory issues.

### 2.2 Layout System

**Strengths:**
- Uses `ViewThatFits` for responsive control layouts (lines 1138-1150)
- GeometryReader-based width calculations for adaptive sizing
- Semantic padding values extracted to `TranscriptStyle` enum
- Dark/light appearance support via `colorScheme` environment

**Concerns:**
- Hardcoded dimension values scattered throughout (e.g., `width: 460`, `pickerWidth: 0.42`)
- No centralized layout constants file
- `SidePanelView` at 2,738 lines violates single responsibility principle

### 2.3 Glass/Material Design

The app uses a "glass" aesthetic:

```swift
// From line 1432-1451
panelBackground: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LinearGradient(...), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(...), radius: 14, x: 0, y: 8)
}
```

**Apple HIG Assessment:** ✅ **Compliant**
- Uses semantic materials (`.ultraThinMaterial`)
- Respects dark/light appearance
- Continuous corner radius matches macOS aesthetic

---

## 3. Apple HIG Compliance Review

### 3.1 ✅ Compliant Areas

| Guideline | Implementation | Evidence |
|-----------|---------------|----------|
| **Semantic Colors** | Uses `NSColor.windowBackgroundColor`, `controlBackgroundColor`, `textBackgroundColor`, `separatorColor` | Throughout SidePanelView |
| **Materials** | `.ultraThinMaterial` for panel background | Line 1434 |
| **Typography** | System fonts with semantic styles (`.headline`, `.caption`, etc.) | Throughout |
| **Accessibility — Reduce Motion** | `reduceMotion` environment check disables animations | Lines 1703-1708, 501-502 |
| **Accessibility — Labels** | Action buttons have `accessibilityLabel` | Lines 2432-2446 |
| **Keyboard Navigation** | Full arrow key + shortcut support | Lines 2172-2228 |
| **Window Management** | `NSPanel` with `isFloatingPanel = true`, proper level | SidePanelController.swift |

### 3.2 ⚠️ Partial Compliance / Concerns

| Guideline | Issue | Severity | Line(s) |
|-----------|-------|----------|---------|
| **Window Titlebar** | MenuBarExtra app shouldn't use `.titled` style mask for side panel | Low | SidePanelController.swift:21 |
| **Focus Indicators** | Custom focus ring via background color may not meet contrast requirements | Medium | Line 2480-2488 |
| **Button Styles** | Inconsistent use of `.bordered`, `.borderedProminent`, custom styling | Low | Various |
| **Popover Anchors** | `arrowEdge: .bottom` may point off-screen in compact layouts | Low | Line 1188 |

### 3.3 ❌ Violations / Missing

| Guideline | Issue | Severity | Recommendation |
|-----------|-------|----------|----------------|
| **Toolbar Items** | Full view lacks proper NSToolbar; uses custom header | Medium | Consider native toolbar for Full mode |
| **VoiceOver — Landmarks** | No semantic landmarks for transcript regions | Medium | Add `accessibilityLabel` + `accessibilityElement` |
| **Color Contrast** | Low-confidence "Needs review" badge uses orange on variable background | Medium | Use system `.orange` with guaranteed contrast |
| **Window Resizing** | Panel animates size changes which may conflict with user resize | Low | Consider disabling animation during manual resize |

---

## 4. Interaction Design Review

### 4.1 Keyboard Contract

The app implements a comprehensive keyboard system:

| Key | Action | Status |
|-----|--------|--------|
| `↑ / ↓` | Move focus | ✅ Implemented |
| `Enter` | Toggle lens | ✅ Implemented |
| `P` | Pin/unpin | ✅ Implemented |
| `Space` | Toggle follow-live | ✅ Implemented |
| `J` | Jump to live | ✅ Implemented |
| `← / →` | Cycle surfaces | ✅ Implemented |
| `Esc` | Close layer | ✅ Implemented |
| `?` | Toggle shortcuts help | ✅ Implemented |
| `Cmd/Ctrl + K` | Focus search (Full) | ✅ Implemented |

**Issue:** The `Cmd+C` shortcut for "Copy Markdown" (line 1065) may conflict with standard copy in transcript text fields. The code attempts to handle this via `shouldIgnoreKeyEvent` but this is fragile.

### 4.2 Focus Management

The focus system uses three interrelated states:
- `focusedSegmentID: UUID?` — Currently focused transcript line
- `lensSegmentID: UUID?` — Expanded lens view on a line
- `pinnedSegmentIDs: Set<UUID>` — User-pinned lines

**Assessment:** This is a well-designed focus model that matches the interaction complexity. State sanitization (lines 2002-2029) prevents orphaned focus references.

### 4.3 Surface System

Surfaces (Summary, Actions, Pins, Entities, Raw) are presented:
- **Roll/Compact:** As overlay (`surfaceOverlay`, line 1249)
- **Full:** As persistent right panel (`fullInsightPanel`, line 814)

**Assessment:** Clever use of SwiftUI conditional rendering. The surface overlay correctly uses `.ultraThinMaterial` for modal presentation.

---

## 5. Code Quality & Maintainability

### 5.1 Complexity Hotspots

| Location | Metric | Concern |
|----------|--------|---------|
| `SidePanelView.swift` | 2,738 lines, ~90 subviews | Severe SRP violation; needs decomposition |
| `body` property | ~30 nested views | High cognitive load |
| `fullRenderer` | ~35 lines of nested HStack/VStack | Layout complexity |
| `handleKeyEvent` | ~55 lines | Consider command pattern |

### 5.2 Recommended Refactoring

```
SidePanelView/
├── SidePanelView.swift          (600 lines — container only)
├── Roll/
│   ├── RollView.swift
│   ├── RollFooter.swift
│   └── SurfaceOverlay.swift
├── Compact/
│   ├── CompactView.swift
│   └── CompactFooter.swift
├── Full/
│   ├── FullView.swift
│   ├── FullSessionRail.swift
│   ├── FullTranscriptColumn.swift
│   ├── FullInsightPanel.swift
│   └── FullTimelineStrip.swift
├── Shared/
│   ├── TranscriptScroller.swift
│   ├── TranscriptLineRow.swift
│   ├── SurfaceContent.swift
│   ├── CaptureBar.swift
│   ├── TopBar.swift
│   └── FooterControls.swift
└── Support/
    ├── ViewMode.swift
    ├── Surface.swift
    └── FullInsightTab.swift
```

### 5.3 Testing Coverage

Current tests in `SidePanelContractsTests.swift`:
- ✅ View mode ordering
- ✅ Surface parity
- ✅ Full insight tab ordering
- ✅ Surface mapping contract

**Missing:**
- ❌ Interaction state machine tests
- ❌ Keyboard handling tests
- ❌ Accessibility label verification
- ❌ Snapshot tests for dark mode (only light mode in current tests)

---

## 6. Performance Considerations

### 6.1 Observed Optimizations

- `visibleTranscriptSegments` caps segments per view mode (lines 1812-1822)
- NLP cache with 400-entry limit (EntityHighlighter.swift:23)
- `reduceMotion` check skips animations
- `sanitizeStateForTranscript` prevents orphaned references

### 6.2 Potential Issues

| Issue | Location | Risk |
|-------|----------|------|
| `onChange(of: appState.transcriptSegments.map(\.id))` | Line 242 | O(n) id mapping every segment update |
| `filteredSegments` recomputes on every view access | Line 1791 | High if filtering large transcripts |
| `decisionBeadPositions` searches transcript for each decision | Line 1948 | O(decisions × segments) |

### 6.3 Recommendations

1. **Memoize filtered segments** using `@State` or computed property with cache
2. **Debounce scroll-to-bottom** to prevent animation spam during rapid updates
3. **Consider LazyVStack** for transcript rendering (currently uses VStack)

---

## 7. Accessibility Audit

### 7.1 ✅ Positive Findings

- `accessibilityLabel` on action buttons (lines 2432-2446)
- `accessibilityReduceMotion` respected
- `accessibilityLabel` on view mode picker (line 303)
- Help text available via `help()` modifier

### 7.2 ⚠️ Gaps

| Element | Issue | Priority |
|---------|-------|----------|
| Transcript list | No `accessibilityLabel` for the scroll region | Medium |
| Speaker badges | No accessibility value (just shows initial) | Medium |
| Surface overlay | No accessibility announcement when opened | Medium |
| Timeline scrubber | No accessibility value (position % only) | Low |
| Focused line | No accessibility notification on focus change | Medium |
| Entity highlights | Clickable entities not exposed to VoiceOver | High |

### 7.3 Recommendations

```swift
// Add to transcriptScroller
.accessibilityLabel("Transcript, \(visibleTranscriptSegments.count) segments")
.accessibilityElement(children: .contain)

// Add to speaker badge
.accessibilityLabel("Speaker: \(speakerLabel(for: segment))")

// Add to entity highlights
.accessibilityAddTraits(.isButton)
.accessibilityLabel("Entity: \(entity.name), \(entity.type)")
```

---

## 8. State Management Review

### 8.1 State Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AppState                              │
│  (@MainActor, @ObservableObject)                            │
│  - sessionState: SessionState                               │
│  - transcriptSegments: [TranscriptSegment]                  │
│  - actions: [ActionItem]                                    │
│  - decisions: [DecisionItem]                                │
│  - entities: [EntityItem]                                   │
│  - risks: [RiskItem]                                        │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌──────────────┐    ┌────────────────┐    ┌──────────────┐
│ SidePanelView│    │ OnboardingView │    │ SummaryView  │
│  (@State for │    │                │    │              │
│   view-local)│    │                │    │              │
└──────────────┘    └────────────────┘    └──────────────┘
```

### 8.2 State Isolation

**Well-isolated:**
- View mode preference (`@AppStorage("sidePanel.viewMode")`)
- Keyboard shortcut state (`showShortcutOverlay`)
- Surface overlay state (`showSurfaceOverlay`, `activeSurface`)

**Potentially problematic:**
- `focusedSegmentID` is view-local but should perhaps be in AppState for cross-view consistency
- `pinnedSegmentIDs` is view-local and not persisted across app launches

### 8.3 Persistence

| Data | Persisted? | Mechanism |
|------|-----------|-----------|
| View mode | ✅ Yes | `@AppStorage` |
| Session history | ✅ Yes | `SessionStore` (JSON files) |
| Pinned segments | ❌ No | In-memory only |
| Focus position | ❌ No | In-memory only |
| Surface selection | ❌ No | In-memory only |

**Recommendation:** Consider persisting pinned segments per session for continuity.

---

## 9. Visual Polish Issues

### 9.1 Observed Inconsistencies

| Location | Issue | Severity |
|----------|-------|----------|
| Border strokes | Multiple opacity values (0.24, 0.58, 0.55) for same purpose | Low |
| Corner radius | Mix of 10, 11, 12, 14, 16, 18 — could be more systematic | Low |
| Padding | Mix of 6, 8, 10, 12, 14 — some inconsistency | Low |
| Shadow radius | Different shadow values in different areas | Low |

### 9.2 Suggested Design System

```swift
enum DesignSystem {
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 18
    }
    
    enum Padding {
        static let tight: CGFloat = 6
        static let standard: CGFloat = 10
        static let relaxed: CGFloat = 14
    }
    
    enum Opacity {
        static let backgroundDark: Double = 0.35
        static let backgroundLight: Double = 0.65
        static let strokeDark: Double = 0.58
        static let strokeLight: Double = 0.24
    }
}
```

---

## 10. Security & Privacy UI

### 10.1 Permission Handling

The app handles two sensitive permissions:
- **Screen Recording** — Required for system audio capture
- **Microphone** — Required for mic capture

**Implementation:** `PermissionBanner` view (lines 2653-2701) shows compact inline warnings.

**Assessment:** ✅ **Well-handled**
- Shows specific missing permission
- Provides direct link to System Settings
- Condensed into single row to avoid pushing content down

### 10.2 Token Storage

HuggingFace token is stored in `UserDefaults` (OnboardingView.swift:203-206):

```swift
SecureField("hf_...", text: Binding(
    get: { UserDefaults.standard.string(forKey: "hfToken") ?? "" },
    set: { UserDefaults.standard.set($0, forKey: "hfToken") }
))
```

**Issue:** `UserDefaults` is not the most secure storage for tokens. Consider Keychain.

---

## 11. Recommendations Summary

### 11.1 Must Fix Before Launch (P0)

1. **Break down SidePanelView.swift** — 2,738 lines is unmaintainable; refactor into subviews
2. **Add VoiceOver support for entity highlights** — Currently invisible to screen reader users
3. **Verify color contrast** — Run accessibility audit in Xcode
4. **Add missing snapshot tests** — Dark mode, high contrast, different sizes

### 11.2 Should Fix (P1)

1. **Persist pinned segments** across app launches
2. **Move HuggingFace token to Keychain**
3. **Add semantic accessibility landmarks** for transcript regions
4. **Optimize filteredSegments** — Memoize or lazy-compute
5. **Standardize design tokens** — Create DesignSystem enum

### 11.3 Nice to Have (P2)

1. **Add haptic feedback** for pin/unpin actions (Mac trackpad support)
2. **Support system accent color** instead of hardcoded blue
3. **Add "What's New" onboarding** for version updates
4. **Consider NSToolbar** for Full view mode
5. **Add full-screen support** for presentation mode

---

## 12. Evidence Log

| Date | Action | Evidence |
|------|--------|----------|
| 2026-02-09 | Reviewed all Swift source files | Files read: 16 source files, 2 test files |
| 2026-02-09 | Analyzed UI documentation | Files: docs/UI.md, docs/UX.md, docs/DECISIONS.md |
| 2026-02-09 | Examined worklog tickets | File: docs/WORKLOG_TICKETS.md (1000+ lines) |
| 2026-02-09 | Build verification | Command: `cd macapp/MeetingListenerApp && swift build` — Success |
| 2026-02-09 | Test verification | Command: `swift test` — 4 tests passed |

---

## Appendix: Code Metrics

```
Total Swift Files: 16
Total Lines of Code: ~6,500
Largest File: SidePanelView.swift (2,738 lines)
Test Files: 2
Test Coverage: Contract tests only (no UI interaction tests)
```

---

*This audit was conducted according to Apple Human Interface Guidelines (macOS), SwiftUI best practices, and accessibility standards (WCAG 2.1 AA).*
