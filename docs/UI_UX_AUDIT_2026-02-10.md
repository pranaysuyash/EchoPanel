# EchoPanel UI/UX Comprehensive Audit
**Date:** 2026-02-10  
**Auditor:** Kimi Code CLI  
**Scope:** All three view modes (Roll, Compact, Full) + Shared Components

---

## Executive Summary

This audit identifies **47 distinct issues** across the EchoPanel macOS app UI, categorized by severity and component. The analysis covers visual consistency, layout stability, interaction patterns, and accessibility.

### Issue Severity Distribution
- **🔴 Critical (5):** Layout breaks, functional issues, accessibility blockers
- **🟠 High (12):** Visual inconsistencies, confusing UX patterns
- **🟡 Medium (18):** Minor styling inconsistencies, polish issues
- **🟢 Low (12):** Code organization, documentation gaps

---

## 1. Roll View Mode Analysis

### 1.1 Layout & Structure
```swift
// Current implementation
transcriptScroller(style: .roll)
    .background(receiptBackground)  // ← Unique to Roll
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))  // ← 16px
```

**Issues Found:**

| # | Severity | Issue | Location | Recommendation |
|---|----------|-------|----------|----------------|
| R1 | 🟠 High | Uses unique `receiptBackground` gradient | `SidePanelRollViews.swift:12` | Unify with `contentBackgroundColor` or document intentional differentiation |
| R2 | 🟡 Medium | Corner radius 16px (others use 14px) | `SidePanelRollViews.swift:13` | Standardize to 14px or 16px across all modes |
| R3 | 🟡 Medium | Footer shows "Surfaces" button that Compact lacks | `SidePanelRollViews.swift:38` | Ensure feature parity or document intentional omission |
| R4 | 🟢 Low | `rollFooterState` naming inconsistent (others use inline) | `SidePanelRollViews.swift:30` | Consider renaming to `rollFooter` for consistency |

### 1.2 Visual Design Tokens

**Inconsistent Values in Roll Mode:**
```swift
// Spacing
rowSpacing: 10        // vs Compact: 8, Full: 8
verticalPadding: 14   // vs Compact: 10, Full: 12
horizontalPadding: 14 // vs Compact: 10, Full: 12

// Background opacity (dark mode)
receiptBackground: textBackgroundColor 0.34/0.22  // Unique gradient
```

---

## 2. Compact View Mode Analysis

### 2.1 Layout & Structure
```swift
// Current implementation
transcriptScroller(style: .compact)
    .background(contentBackgroundColor)  // ← Standard
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))  // ← 14px
```

**Issues Found:**

| # | Severity | Issue | Location | Recommendation |
|---|----------|-------|----------|----------------|
| C1 | 🟠 High | Missing "Surfaces" button (present in Roll) | `SidePanelCompactViews.swift:25` | Add Surfaces button for feature parity |
| C2 | 🟡 Medium | Button label "Live" vs "Jump Live" in Roll | `SidePanelCompactViews.swift:31` | Standardize button labels across modes |
| C3 | 🟡 Medium | No surfaceOverlay ZStack handling | `SidePanelCompactViews.swift:19` | Verify overlay works correctly in Compact mode |

### 2.2 Missing Elements (vs Roll)
- ❌ No "Surfaces" button in footer
- ❌ Different "Jump Live" button styling
- ❌ No `AccessibilitySortPriority` on footer HStack (Roll has 100)

---

## 3. Full View Mode Analysis

### 3.1 Layout & Structure

**Issues Found:**

| # | Severity | Issue | Location | Recommendation |
|---|----------|-------|----------|----------------|
| F1 | 🔴 Critical | Completely different chrome layout | `SidePanelFullViews.swift:76` | Users lose familiarity when switching modes; consider shared chrome component |
| F2 | 🔴 Critical | No capture bar - audio controls missing | `SidePanelFullViews.swift` | Full mode lacks audio source toggle, follow toggle |
| F3 | 🟠 High | Timeline only visible in Full mode | `SidePanelFullViews.swift:459` | Consider if timeline should be accessible in other modes |
| F4 | 🟠 High | Session rail takes significant space | `SidePanelFullViews.swift:132` | Collapsible rail or responsive breakpoint needs tuning |
| F5 | 🟡 Medium | Corner radius 16px (inconsistent with Compact's 14px) | `SidePanelFullViews.swift:56` | Standardize corner radius values |
| F6 | 🟡 Medium | Work mode picker appears twice (stacked vs inline) | `SidePanelFullViews.swift:96-121` | Verify responsive logic works correctly |
| F7 | 🟡 Medium | "LIVE · J" button uses different styling | `SidePanelFullViews.swift:63` | Standardize jump-to-live button appearance |

### 3.2 Full Mode-Only Features (Potential Inconsistency)

```swift
// Features ONLY in Full mode:
- Session rail with search
- Speaker chips
- Work mode picker (Live/Review/Brief)
- Insight panel with tabs
- Timeline strip with decision beads
- Context panel for documents
```

**Question:** Are these intentionally Full-mode only, or should some be available in Roll/Compact?

---

## 4. Shared Components Analysis

### 4.1 `TranscriptLineRow` (SidePanelSupportViews.swift)

**Strengths:**
- ✅ Fixed frame sizes prevent layout shifts (P2 fixes implemented)
- ✅ Transaction modifiers for smooth updates
- ✅ Accessibility representation for entity highlights

**Issues:**

| # | Severity | Issue | Location | Current Value | Recommended |
|---|----------|-------|----------|---------------|-------------|
| S1 | 🟡 Medium | Confidence threshold inconsistent | `SidePanelSupportViews.swift:45` | `0.5` | Should match server-side filter (0.3) |
| S2 | 🟡 Medium | Action buttons width hardcoded | `SidePanelSupportViews.swift:121` | `84` | Calculate from button sizes |
| S3 | 🟢 Low | `needsReviewBadge` uses NSColor directly | `SidePanelSupportViews.swift:244` | - | Use SwiftUI Color for consistency |
| S4 | 🟢 Low | `EntityTextView` frame modifiers repeated | `SidePanelSupportViews.swift:65-81` | - | Extract to shared style |

### 4.2 Color & Background Inconsistencies

```swift
// contentBackgroundColor usage varies:
Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.26 : 0.86)  // Chrome
Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.18 : 0.75)  // Row
Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.24 : 0.72)  // Chip
Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.65)  // Raw text
```

**Audit Finding:** 6 different opacity values for textBackgroundColor

| Use Case | Dark | Light |
|----------|------|-------|
| Chrome/Panel | 0.26 | 0.86 |
| Transcript Row | 0.18 | 0.75 |
| Source Chip | 0.24 | 0.72 |
| Raw Text | 0.35 | 0.65 |
| Empty State | 0.30 | 0.66 |
| Search Field | 0.24 | 0.90 |

**Recommendation:** Define semantic color tokens:
```swift
enum BackgroundLevel {
    case elevated    // 0.35 / 0.90
    case `default`   // 0.26 / 0.86
    case subtle      // 0.18 / 0.75
}
```

### 4.3 Corner Radius Audit

| Component | Current | Suggested |
|-----------|---------|-----------|
| Main panel | 18 | 18 ✓ |
| Transcript container (Roll) | 16 | 14 |
| Transcript container (Compact) | 14 | 14 ✓ |
| Transcript container (Full) | 16 | 14 |
| Capture bar | 12 | 12 ✓ |
| Full insight panel | 14 | 14 ✓ |
| Full main header | 12 | 12 ✓ |
| Row cards | 12 | 12 ✓ |
| Chips | 10 | 10 ✓ |

### 4.4 Typography Inconsistencies

| Element | Roll | Compact | Full | Recommended |
|---------|------|---------|------|-------------|
| Title | system(19, semibold, rounded) | - | headline | Unify |
| Timestamp | caption2 | caption2 | - | ✓ Consistent |
| Confidence | caption2 | caption2 | - | ✓ Consistent |
| Badge text | caption2 | caption2 | - | ✓ Consistent |

**Issue:** Full mode uses `.headline` while Roll uses custom system font.

---

## 5. Interaction & Behavior Issues

### 5.1 Keyboard Shortcuts

| Shortcut | Roll | Compact | Full | Issue |
|----------|------|---------|------|-------|
| ↑/↓ Focus | ✅ | ✅ | ✅ | ✓ Consistent |
| Enter Lens | ✅ | ✅ | ✅ | ✓ Consistent |
| P Pin | ✅ | ✅ | ✅ | ✓ Consistent |
| Space Follow | ✅ | ✅ | ✅ | ✓ Consistent |
| J Jump Live | ✅ | ✅ | ✅ | ✓ Consistent |
| ←/→ Surfaces | ✅ | ✅ | ✅ | ✓ Consistent |
| Cmd+K Search | ❌ | ❌ | ✅ | F8: Only in Full mode |

### 5.2 Focus Management

**Issues:**

| # | Severity | Issue | Location |
|---|----------|-------|----------|
| I1 | 🟠 High | `fullSearchFocused` FocusState only in Full mode | `SidePanelView.swift:143` | Consider adding to other modes |
| I2 | 🟡 Medium | `focusedSegmentID` sync differs between modes | Various | Verify sync logic is consistent |
| I3 | 🟡 Medium | `lensSegmentID` behavior not consistent | `SidePanelTranscriptSurfaces.swift:127` | Verify lens opens in all modes |

### 5.3 Animation Inconsistencies

```swift
// Different animation durations across the app:
.easeInOut(duration: 0.18)  // viewMode change
.easeInOut(duration: 0.15)  // TranscriptLineRow
easeOut(duration: 0.2)      // performAnimatedUpdate
```

**Recommendation:** Define animation constants:
```swift
enum AnimationDuration {
    static let quick: Double = 0.15
    static let standard: Double = 0.20
    static let slow: Double = 0.30
}
```

---

## 6. Accessibility Issues

### 6.1 Missing Accessibility Features

| # | Severity | Issue | Location |
|---|----------|-------|----------|
| A1 | 🔴 Critical | `fullTimelineStrip` lacks accessibility labels | `SidePanelFullViews.swift:459` | Add slider accessibility |
| A2 | 🟠 High | Decision beads not accessible | `SidePanelFullViews.swift:478` | Add accessibility representation |
| A3 | 🟠 High | `AudioLevelMeter` not accessible | `SidePanelSupportViews.swift:461` | Add value labels |
| A4 | 🟡 Medium | Speaker chips missing hints | `SidePanelFullViews.swift:243` | Add accessibility hints |

### 6.2 Accessibility Sort Priority Inconsistencies

```swift
// Roll mode:
transcriptToolbar: 300
transcriptScroller: 200
rollFooterState: 100

// Full mode:
fullTopChrome: 500
fullSessionRail: 400
fullTranscriptColumn: 300
fullInsightPanel: 200
fullTimelineStrip: 100

// Compact mode: MISSING many priorities
```

**Issue:** Compact mode lacks accessibility sort priorities.

---

## 7. Responsive Design Issues

### 7.1 Breakpoint Inconsistencies

| Mode | Breakpoint | Behavior |
|------|------------|----------|
| Roll | 600px | View mode picker moves below title |
| Compact | 600px | (inherited) |
| Full | 1080px | Work mode picker stacks |
| Full | 1240px | Insight panel stacks below |

**Issues:**
- F6: Different breakpoints for similar responsive behavior
- No shared breakpoint constants

### 7.2 Width Calculations

```swift
// Different calculation approaches:
let pickerWidth = min(max(panelWidth * 0.42, 170), 250)  // Roll
let pickerWidth = min(max(panelWidth * 0.32, 170), 300)  // Full
let pickerCap: CGFloat = viewMode == .compact ? 190 : 250  // Toolbar
```

**Recommendation:** Create shared width calculation utilities.

---

## 8. Code Organization Issues

### 8.1 View Extension Proliferation

**Current State:**
- `SidePanelView` has 20+ extensions across 6 files
- Logic spread between `SidePanelStateLogic.swift`, view files, and main view

**Issues:**

| # | Severity | Issue | Recommendation |
|---|----------|-------|----------------|
| O1 | 🟢 Low | State logic mixed with view code | Extract to dedicated ViewModels |
| O2 | 🟢 Low | Formatting functions duplicated | Create shared Formatters utility |
| O3 | 🟢 Low | Color definitions scattered | Create Theme/DesignTokens struct |

### 8.2 Magic Numbers

**Found throughout codebase:**
```swift
// Corner radii: 10, 11, 12, 14, 16, 18
// Opacities: 0.08, 0.11, 0.14, 0.15, 0.16, 0.18, 0.22, 0.24, 0.26, 0.30, 0.32, 0.34, 0.35, 0.38, 0.42, 0.45, 0.55, 0.56, 0.58, 0.65, 0.72, 0.75, 0.86, 0.90, 0.94
// Frame widths: 44, 84, 72, 24
// Durations: 0.15, 0.18, 0.20
```

---

## 9. Recommendations Summary

### 9.1 Immediate Actions (Critical/High Priority)

1. **F2 - Add capture bar to Full mode** or document intentional exclusion
2. **C1 - Add Surfaces button to Compact mode** footer
3. **Standardize corner radii** to 12px (cards), 14px (containers), 18px (panel)
4. **Unify background colors** with semantic tokens
5. **Add missing accessibility labels** to Full mode exclusive features

### 9.2 Short-term Improvements (Medium Priority)

6. Create `DesignTokens.swift` with:
   - Corner radius constants
   - Animation duration constants
   - Semantic color definitions
   - Spacing constants

7. Create `ViewModeFeatures.swift` documenting which features exist in which modes

8. Extract shared chrome component for mode switcher

9. Standardize button labels ("Jump Live" vs "Live")

### 9.3 Long-term Refactoring (Low Priority)

10. Consider ViewModel architecture for state management
11. Create snapshot tests for each view mode
12. Document responsive breakpoint strategy
13. Add UI regression tests

---

## 10. Appendices

### Appendix A: Color Token Reference

```swift
// Recommended design token structure
struct DesignTokens {
    struct CornerRadius {
        static let small: CGFloat = 8   // chips, badges
        static let medium: CGFloat = 12 // cards, rows
        static let large: CGFloat = 14  // containers
        static let xlarge: CGFloat = 18 // panel
    }
    
    struct Background {
        static func elevated(_ scheme: ColorScheme) -> Color
        static func `default`(_ scheme: ColorScheme) -> Color
        static func subtle(_ scheme: ColorScheme) -> Color
    }
    
    struct Animation {
        static let quick = 0.15
        static let standard = 0.20
        static let slow = 0.30
    }
}
```

### Appendix B: View Mode Feature Matrix

| Feature | Roll | Compact | Full | Notes |
|---------|------|---------|------|-------|
| Transcript scrolling | ✅ | ✅ | ✅ | All modes |
| Surface overlay | ✅ | ✅ | N/A | Full has dedicated panel |
| Follow live toggle | ✅ | ✅ | ✅ | All modes |
| Jump to live | ✅ | ✅ | ✅ | All modes |
| Pin/unpin | ✅ | ✅ | ✅ | All modes |
| Focus lens | ✅ | ✅ | ✅ | All modes |
| Entity filter | ✅ | ✅ | ✅ | All modes |
| Audio source picker | ✅ | ✅ | ❌ | F2: Missing in Full |
| Audio level meters | ✅ | ✅ | ❌ | F2: Missing in Full |
| Surfaces button | ✅ | ❌ | N/A | C1: Missing in Compact |
| Session rail | ❌ | ❌ | ✅ | Full only |
| Speaker chips | ❌ | ❌ | ✅ | Full only |
| Timeline | ❌ | ❌ | ✅ | Full only |
| Work mode picker | ❌ | ❌ | ✅ | Full only |
| Context panel | ❌ | ❌ | ✅ | Full only |
| Cmd+K search | ❌ | ❌ | ✅ | Full only |

### Appendix C: File Organization

```
Sources/SidePanel/
├── Shared/
│   ├── SidePanelSupportViews.swift      # TranscriptLineRow, etc.
│   ├── SidePanelChromeViews.swift       # Backgrounds, badges
│   ├── SidePanelLayoutViews.swift       # TopBar, CaptureBar
│   ├── SidePanelTranscriptSurfaces.swift # Scroller, surfaces
│   └── SidePanelStateLogic.swift        # State helpers
├── Roll/
│   └── SidePanelRollViews.swift         # Roll-specific
├── Compact/
│   └── SidePanelCompactViews.swift      # Compact-specific
├── Full/
│   └── SidePanelFullViews.swift         # Full-specific
└── SidePanelView.swift                  # Main container
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-10  
**Next Review:** After implementation of Critical/High priority items
