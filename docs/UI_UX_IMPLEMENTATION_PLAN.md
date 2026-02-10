# EchoPanel UI/UX Implementation Plan
**Based on:** UI/UX Audit 2026-02-10 + Apple Human Interface Guidelines

---

## HIG Principles Applied

### 1. **Color & Materials**
- Use system-defined colors that adapt to light/dark modes
- Apply semantic colors (background, secondaryBackground, etc.)
- Ensure sufficient contrast ratios (minimum 4.5:1 for text)
- Avoid hard-coding color values

### 2. **Layout & Spacing**
- Use standard macOS spacing (8pt grid system)
- Maintain consistent padding across views
- Support dynamic type where appropriate

### 3. **Controls & Interactions**
- Use standard control sizes (.small, .mini as appropriate)
- Maintain consistent button styles within contexts
- Provide clear visual feedback for interactions

### 4. **Accessibility**
- Support VoiceOver with proper labels and hints
- Ensure keyboard navigation works throughout
- Respect reduce motion preferences

---

## Implementation Phases

### Phase 1: Foundation (DesignTokens)
Create a single source of truth for all design values following HIG.

### Phase 2: Critical Fixes
- Add missing capture bar to Full mode
- Add Surfaces button to Compact mode
- Fix accessibility blockers

### Phase 3: Visual Consistency
- Standardize corner radii (HIG: consistent shapes)
- Unify background colors using semantic tokens
- Standardize typography

### Phase 4: Component Refactoring
- Extract shared chrome component
- Unify footer controls
- Standardize animations

---

## Design Token Specifications

### Corner Radii (Following HIG consistency)
```swift
enum CornerRadius {
    static let xs: CGFloat = 6   // Badges, small chips
    static let sm: CGFloat = 8   // Buttons, controls
    static let md: CGFloat = 10  // Cards, list items
    static let lg: CGFloat = 12  // Containers, panels
    static let xl: CGFloat = 16  // Main panel
}
```

### Spacing (8pt grid system per HIG)
```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}
```

### Colors (Semantic per HIG)
```swift
enum SemanticBackground {
    case panel      // Main panel background
    case container  // Transcript containers
    case card       // Individual cards/rows
    case control    // Controls, buttons
    case elevated   // Popovers, overlays
}
```

### Animations (Respect reduceMotion)
```swift
enum AnimationDuration {
    static let instant: Double = 0.10
    static let quick: Double = 0.15
    static let standard: Double = 0.20
    static let emphasis: Double = 0.30
}
```

---

## File Changes Required

### New Files
1. `Sources/DesignTokens.swift` - Design system constants
2. `Sources/SidePanel/Shared/SidePanelChrome.swift` - Shared chrome component

### Modified Files
1. `SidePanelView.swift` - Integrate tokens, fix accessibility
2. `SidePanelRollViews.swift` - Apply tokens, unify footer
3. `SidePanelCompactViews.swift` - Add Surfaces button, apply tokens
4. `SidePanelFullViews.swift` - Add capture bar, apply tokens
5. `SidePanelSupportViews.swift` - Apply tokens, fix accessibility
6. `SidePanelLayoutViews.swift` - Apply tokens
7. `SidePanelTranscriptSurfaces.swift` - Apply tokens
8. `SidePanelChromeViews.swift` - Apply tokens, extract shared
9. `SidePanelStateLogic.swift` - Standardize formatters

---

## HIG Compliance Checklist

### Color
- [ ] Use system colors where possible
- [ ] Define semantic color tokens
- [ ] Ensure 4.5:1 contrast ratio for text
- [ ] Test in both light and dark modes
- [ ] Support increased contrast accessibility

### Layout
- [ ] Use 8pt grid for spacing
- [ ] Consistent corner radii within hierarchies
- [ ] Proper use of materials (ultraThinMaterial, etc.)
- [ ] Respect safe areas and layout margins

### Typography
- [ ] Use system fonts
- [ ] Appropriate text styles (headline, caption, etc.)
- [ ] Support dynamic type

### Controls
- [ ] Standard control sizes
- [ ] Consistent button styles
- [ ] Clear feedback states

### Accessibility
- [ ] VoiceOver labels and hints
- [ ] Keyboard navigation
- [ ] Reduce motion support
- [ ] Sufficient touch targets (44x44pt minimum)

---

## Testing Plan

1. Visual regression tests for all three modes
2. Accessibility audit with VoiceOver
3. Light/dark mode testing
4. Different window sizes (responsive)
5. Keyboard navigation test
6. Reduce motion preference test
