# macOS Design Guidance — EchoPanel

> **Role:** Design Research Analyst (macOS UI), evidence-first  
> **Date:** 2026-02-15  
> **Purpose:** Synthesize best, most actionable macOS design guidance for building beautiful modern Mac apps

---

## Sources Collected

### Primary Apple Sources

- [Human Interface Guidelines — Apple](https://developer.apple.com/design/human-interface-guidelines)
- [Color — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/color)
- [Materials — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Typography — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/typography)
- [SF Symbols — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [App Icons — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Dark Mode — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
- [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [NSVisualEffectView.Material — Apple Docs](https://developer.apple.com/documentation/AppKit/NSVisualEffectView/Material-swift.enum)
- [SF Symbols App](https://developer.apple.com/sf-symbols/)

### WWDC Sessions

- **WWDC 2025:** Build an AppKit app with the new design (`#310`) — Liquid Glass / Tahoe design
- **WWDC 2024:** Tailor macOS windows with SwiftUI (`#10148`)
- **WWDC 2024:** Create custom visual effects with SwiftUI (`#10151`)
- **WWDC 2022:** What's new in AppKit (`#10074`)
- **WWDC 2020:** Adopt the new look of macOS (`#10104`)

### Secondary References

- [Vibrancy, NSAppearance, and Visual Effects in Modern AppKit and SwiftUI Apps](https://philz.blog/vibrancy-nsappearance-and-visual-effects-in-modern-appkit-apps/)
- [Build a macOS SwiftUI App with a Tahoe-Style Liquid Glass UI](https://medium.com/@dorangao/build-a-macos-swiftui-app-with-a-tahoe-style-liquid-glass-ui-fecb8029b2d8)
- [Reverse Engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview)

---

# DELIVERABLE A: Design Guidance Map

## A1. Color

| Rule / Principle                                                                                                                               | Source                                                                                                   | Practical Implication                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **[Apple-Explicit]** Use semantic colors that adapt to Light/Dark mode automatically (e.g., `Color.primary`, `Color.secondary`, `.background`) | [Color — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/color)                 | Never hardcode hex values; use system semantic colors or asset catalog with Both Appearances |
| **[Apple-Explicit]** Respect the user's system accent color for interactive elements                                                           | [Color — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/color)                 | Use `.accentColor` / `.tint` on standard controls; don't override with fixed brand color     |
| **[Apple-Explicit]** Ensure sufficient contrast for text (minimum 4.5:1 for body, 3:1 for large text)                                          | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Test all text in both Light and Dark modes; use Apple's contrast tools                       |
| **[Best-Practice]** Define semantic tokens: `primary`, `secondary`, `tertiary`, `disabled`, `success`, `warning`, `error`                      | Inference                                                                                                | Map each semantic token to system colors that work in both modes                             |

## A2. Materials & Glass

| Rule / Principle                                                                                                 | Source                                                                                                             | Practical Implication                                                                         |
| ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| **[Apple-Explicit]** Use system materials (`NSVisualEffectView.Material`) for sidebars, toolbars, popovers       | [Materials — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/materials)                   | Use `.sidebar`, `.toolbar`, `.popover`, `.hudWindow`, `.fullScreenUI` materials               |
| **[Apple-Explicit]** Set `blendingMode = .behindWindow` for translucent backgrounds that show underlying content | [NSVisualEffectView Docs](https://developer.apple.com/documentation/AppKit/NSVisualEffectView/Material-swift.enum) | Enables the classic macOS "glass" effect                                                      |
| **[Apple-Explicit]** Respect "Reduce Transparency" accessibility setting                                         | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)           | Check `accessibilityReduceTransparency`; replace vibrancy with solid backgrounds when enabled |
| **[Best-Practice]** Use `state = .followsWindowActiveState` so materials respond to window focus                 | [Vibrancy Blog](https://philz.blog/vibrancy-nsappearance-and-visual-effects-in-modern-appkit-apps/)                | Sidebar highlights when window is active, dims when inactive                                  |
| **[Best-Practice]** Avoid heavy blur on large areas; it impacts performance                                      | Inference                                                                                                          | Use subtle blur; test on older Macs                                                           |

## A3. Typography

| Rule / Principle                                                                                                  | Source                                                                                             | Practical Implication                                    |
| ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **[Apple-Explicit]** Use SF Pro (system font) at semantic sizes: `.title`, `.headline`, `.body`, `.caption`, etc. | [Typography — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/typography) | Never hardcode font sizes; use SwiftUI's semantic styles |
| **[Apple-Explicit]** Use SF Mono for code blocks                                                                  | [Typography — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/typography) | `Text("code").font(.system(.body, design: .monospaced))` |
| **[Best-Practice]** Dynamic Type support on macOS: support text scaling via accessibility settings                | Inference                                                                                          | Use `.dynamicTypeSize()` in SwiftUI where appropriate    |
| **[Best-Practice]** Line height ~1.2-1.4x font size for body text                                                 | Inference                                                                                          | System defaults are tuned; avoid tight leading           |

## A4. Icons

| Rule / Principle                                                                                       | Source                                                                                             | Practical Implication                                                |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| **[Apple-Explicit]** Use SF Symbols for all in-app icons                                               | [SF Symbols — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) | Prefer system symbols; fallback to custom only when no symbol exists |
| **[Apple-Explicit]** Use appropriate symbol weight: `.regular`, `.medium`, `.semibold`, `.bold`        | [SF Symbols — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) | Match weight to hierarchy: bold for emphasis, regular for content    |
| **[Apple-Explicit]** App icon: 1024x1024 master, all required sizes (16, 32, 64, 128, 256, 512, 1024)  | [App Icons — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons)   | Use App Icon set in asset catalog; include @1x and @2x               |
| **[Apple-Explicit]** App icon safe zone: 10% margin from edges; avoid rounded corners (system applies) | [App Icons — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons)   | Keep critical content within inner 80%                               |
| **[Best-Practice]** Use monochrome symbols in lists/grids; hierarchical symbols for toolbar            | Inference                                                                                          | Color follows content; symbol provides form                          |

## A5. Layout & Spacing

| Rule / Principle                                                                                        | Source                                                                                             | Practical Implication                                 |
| ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **[Apple-Explicit]** Sidebar: leading edge, collapsible, 180-320pt width, translucent source-list style | [Navigation — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/navigation) | Use `NavigationSplitView` with `.listStyle(.sidebar)` |
| **[Apple-Explicit]** Toolbar: unified title bar + toolbar for modern look                               | [Toolbars — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/toolbars)     | Use `.windowToolbarStyle(.unified)` in SwiftUI        |
| **[Apple-Explicit]** Window: resizable with sensible minimums (e.g., 600x400)                           | [Windows — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/windows)       | Set `.frame(minWidth:, minHeight:)`                   |
| **[Apple-Explicit]** Standard spacing: 20pt margins, 8pt between related controls, 20pt between groups  | [Spacing — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/spacing)       | Align to 8pt grid                                     |
| **[Best-Practice]** List row heights: 24-28pt for standard rows                                         | Inference                                                                                          | Use system list styles for consistency                |

## A6. Motion & Interaction

| Rule / Principle                                                                    | Source                                                                                                   | Practical Implication                                                 |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **[Apple-Explicit]** Respect "Reduce Motion" accessibility setting                  | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Check `accessibilityReduceMotion`; disable/alter animations when true |
| **[Best-Practice]** Spring animations for interactive elements (damping 0.7-0.8)    | Inference                                                                                                | Use `.animation(.spring(response: 0.3, dampingFraction: 0.7))`        |
| **[Best-Practice]** 150-300ms for standard transitions; instant for inline feedback | Inference                                                                                                | Avoid slow fades; prioritize perceived responsiveness                 |

## A7. Accessibility

| Rule / Principle                                                                                       | Source                                                                                                   | Practical Implication                                            |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **[Apple-Explicit]** Support full keyboard navigation (Tab, arrows, Enter, Esc)                        | [Keyboard — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/keyboard)           | Every action must have a keyboard shortcut                       |
| **[Apple-Explicit]** Provide visible focus rings for keyboard navigation                               | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Use `@FocusState` and built-in focus rings                       |
| **[Apple-Explicit]** Minimum 44x44pt touch/click targets (but 22-28pt is fine for Mac precision input) | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Mac users have precise pointers; compact controls are acceptable |
| **[Apple-Explicit]** Differentiate states without color alone (icons + text labels)                    | [Accessibility — Apple HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Don't rely solely on red/green; add icons or text                |

---

# DELIVERABLE B: Mac Beauty Checklist

## B1. Color & Theming

- [ ] Uses semantic colors (`Color.primary`, `.secondary`, `.background`) — no hardcoded hex
- [ ] Respects system accent color in standard controls
- [ ] Works correctly in Dark Mode (test both appearances)
- [ ] Defines semantic tokens: success/warning/error states
- [ ] Text contrast meets 4.5:1 (body) / 3:1 (large) in both modes

## B2. Iconography

- [ ] Uses SF Symbols for all in-app icons (no custom unless necessary)
- [ ] App icon: 1024x1024 master, all sizes in asset catalog
- [ ] App icon respects safe zone (10% margin)
- [ ] Symbol weights consistent with hierarchy
- [ ] Icons have appropriate size (16x16 to 24x24 for content, 32x32+ for toolbar)

## B3. Materials & Glass

- [ ] Uses system materials (`sidebar`, `toolbar`, `popover`) — not custom blur
- [ ] Vibrancy blending mode set to `.behindWindow` where appropriate
- [ ] Materials respond to window active state
- [ ] Respects "Reduce Transparency" accessibility setting
- [ ] Text remains legible on translucent backgrounds (contrast check)
- [ ] No performance issues from over-blur

## B4. Typography & Layout

- [ ] Uses SF Pro at semantic sizes (`.title`, `.headline`, `.body`, `.caption`)
- [ ] Uses SF Mono for code
- [ ] Sidebar: leading edge, collapsible, 180-320pt, source-list style
- [ ] Toolbar: unified style, user-customizable
- [ ] Window resizable with sensible minimums
- [ ] Spacing follows 8pt grid (20pt margins, 8pt between related, 20pt between groups)
- [ ] List row heights appropriate (24-28pt)

## B5. Motion & Polish

- [ ] Respects "Reduce Motion" setting
- [ ] Animations are subtle (150-300ms)
- [ ] Spring animations for interactive elements
- [ ] Hover states on all interactive elements
- [ ] Context menus on right-click
- [ ] Smooth scrolling with elastic bounce

## B6. Accessibility

- [ ] Full keyboard navigation (Tab, arrows, Enter, Esc)
- [ ] Visible focus rings for keyboard users
- [ ] All menu items have keyboard shortcuts
- [ ] Cmd+Z undo for all destructive actions
- [ ] "Differentiate without color" — icons + text for states
- [ ] Minimum hit targets (22pt+)
- [ ] Works with VoiceOver (labels on all controls)

---

# DELIVERABLE C: Starter Tokens

## C1. Color Tokens

### Semantic Colors

| Token                  | Light Mode             | Dark Mode              | Usage                |
| ---------------------- | ---------------------- | ---------------------- | -------------------- |
| `color.text.primary`   | `labelColor` (#000000) | `labelColor` (#FFFFFF) | Headlines, body text |
| `color.text.secondary` | `secondaryLabelColor`  | `secondaryLabelColor`  | Captions, metadata   |
| `color.text.tertiary`  | `tertiaryLabelColor`   | `tertiaryLabelColor`   | Placeholders         |
| `color.text.disabled`  | `disabledLabelColor`   | `disabledLabelColor`   | Disabled text        |

### Surface Colors

| Token                     | Light Mode                 | Dark Mode                  | Usage            |
| ------------------------- | -------------------------- | -------------------------- | ---------------- |
| `color.surface.primary`   | `windowBackgroundColor`    | `windowBackgroundColor`    | Main background  |
| `color.surface.secondary` | `controlBackgroundColor`   | `controlBackgroundColor`   | Cards, panels    |
| `color.surface.elevated`  | `underPageBackgroundColor` | `underPageBackgroundColor` | Popovers, sheets |

### Accent & State

| Token                  | System Source                     | Usage                                  |
| ---------------------- | --------------------------------- | -------------------------------------- |
| `color.accent`         | `.accentColor`                    | Interactive elements (system adaptive) |
| `color.state.success`  | `.systemGreen`                    | Success states                         |
| `color.state.warning`  | `.systemOrange`                   | Warning states                         |
| `color.state.error`    | `.systemRed`                      | Error states                           |
| `color.state.selected` | `.selectedContentBackgroundColor` | Selection highlight                    |

## C2. Typography Scale

| Token                | Font    | Size | Weight    | Line Height |
| -------------------- | ------- | ---- | --------- | ----------- |
| `type.title.large`   | SF Pro  | 34pt | .bold     | 41pt        |
| `type.title`         | SF Pro  | 28pt | .bold     | 34pt        |
| `type.title.small`   | SF Pro  | 22pt | .bold     | 28pt        |
| `type.headline`      | SF Pro  | 17pt | .semibold | 22pt        |
| `type.body`          | SF Pro  | 17pt | .regular  | 22pt        |
| `type.callout`       | SF Pro  | 16pt | .regular  | 21pt        |
| `type.subheadline`   | SF Pro  | 15pt | .regular  | 20pt        |
| `type.footnote`      | SF Pro  | 13pt | .regular  | 18pt        |
| `type.caption`       | SF Pro  | 12pt | .regular  | 16pt        |
| `type.caption.small` | SF Pro  | 11pt | .regular  | 13pt        |
| `type.code`          | SF Mono | 13pt | .regular  | 18pt        |

## C3. Spacing Scale

| Token         | Value | Usage                          |
| ------------- | ----- | ------------------------------ |
| `spacing.xs`  | 4pt   | Tight spacing within controls  |
| `spacing.sm`  | 8pt   | Between related controls       |
| `spacing.md`  | 16pt  | Standard padding               |
| `spacing.lg`  | 20pt  | Section margins, group spacing |
| `spacing.xl`  | 24pt  | Major section gaps             |
| `spacing.2xl` | 32pt  | Large separations              |

## C4. Corner Radius & Borders

| Token                | Value | Usage               |
| -------------------- | ----- | ------------------- |
| `radius.small`       | 4pt   | Small buttons, tags |
| `radius.medium`      | 8pt   | Cards, panels       |
| `radius.large`       | 12pt  | Large surfaces      |
| `border.width`       | 1pt   | Standard borders    |
| `border.width.thick` | 2pt   | Emphasis borders    |

## C5. Shadow / Elevation

| Token         | Effect                    | Usage             |
| ------------- | ------------------------- | ----------------- |
| `elevation.0` | No shadow                 | Flat surfaces     |
| `elevation.1` | `shadow(radius: 2, y: 1)` | Subtle depth      |
| `elevation.2` | `shadow(radius: 4, y: 2)` | Floating elements |
| `elevation.3` | `shadow(radius: 8, y: 4)` | Modals, dropdowns |

## C6. Material Presets

| Preset             | Material             | Blending Mode   | State                       | Usage              |
| ------------------ | -------------------- | --------------- | --------------------------- | ------------------ |
| `material.sidebar` | `.sidebar`           | `.behindWindow` | `.followsWindowActiveState` | Navigation sidebar |
| `material.toolbar` | `.toolbar`           | `.withinWindow` | `.active`                   | Toolbar area       |
| `material.popover` | `.popover`           | `.behindWindow` | `.active`                   | Popover panels     |
| `material.hud`     | `.hudWindow`         | `.behindWindow` | `.active`                   | HUD-style panels   |
| `material.sheet`   | `.fullScreenUI`      | `.behindWindow` | `.active`                   | Modal sheets       |
| `material.content` | `.contentBackground` | `.withinWindow` | `.active`                   | List/content areas |

### Reduce Transparency Fallback

```swift
// When reduceTransparency is true, use:
color.surface.primary     // instead of material.sidebar
color.surface.secondary   // instead of material.popover
```

### Reduce Motion Fallback

```swift
// When reduceMotion is true:
// - Use instant transitions (no fade)
// - Disable spring animations
// - Use linear animations instead
```

---

# DELIVERABLE D: Pitfalls & Anti-Patterns

## D1. Glass Done Wrong

| Problem                   | Symptom                                                                     | Fix                                                                                          |
| ------------------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Over-blur**             | Entire window has heavy blur, causing CPU/GPU strain and readability issues | Limit blur to specific areas (sidebar, toolbar); use subtle `.contentBackground` for content |
| **Insufficient contrast** | Text on glass is unreadable against wallpaper/background                    | Ensure 4.5:1 contrast; add semi-opaque backing if needed                                     |
| **No fallback**           | App breaks when user enables "Reduce Transparency"                          | Check `accessibilityReduceTransparency`; provide solid alternative                           |
| **Wrong material**        | Using `.hudWindow` for sidebar or `.sidebar` for popover                    | Match material to context (see C6)                                                           |
| **Static vibrancy**       | Glass doesn't dim when window loses focus                                   | Set `state = .followsWindowActiveState`                                                      |

## D2. General Anti-Patterns

| Anti-Pattern                     | Why It's Wrong                                   | Fix                                            |
| -------------------------------- | ------------------------------------------------ | ---------------------------------------------- |
| **Hamburger menu**               | iOS pattern; macOS has menu bar                  | Use proper menu bar + sidebar                  |
| **Bottom tab bar**               | iOS pattern; macOS uses sidebars/toolbars        | Use sidebar navigation                         |
| **Floating action button (FAB)** | Android pattern                                  | Put primary actions in toolbar/menu            |
| **Custom window chrome**         | Breaks macOS conventions, traffic lights missing | Use native title bar + toolbar                 |
| **Fixed window size**            | Users have varying display sizes                 | Allow resize with sensible minimums            |
| **Hardcoded colors**             | Breaks in Dark Mode, ignores system appearance   | Use semantic colors                            |
| **No keyboard shortcuts**        | Mac power users rely on keyboard                 | Add Cmd+letter for every action                |
| **No undo (Cmd+Z)**              | Violates fundamental Mac expectation             | Every destructive action must be undoable      |
| **Giant touch targets**          | Wastes space; Mac has precise pointer            | Use 22-28pt heights for controls               |
| **Modal sheets for everything**  | Creates friction for simple tasks                | Use inline editing, popovers for quick actions |
| **No right-click context menus** | Violates Mac interaction pattern                 | Add context menus to all interactive elements  |
| **Notification spam**            | Users disable notifications                      | Only notify for genuinely important events     |

## D3. Recovery Guide: Glass Fixes

1. **Text unreadable?** → Add `.background(Color.windowBackgroundColor.opacity(0.8))` behind text
2. **Performance lag?** → Reduce blur radius or limit blur to smaller areas
3. **Wrong look?** → Swap material enum (e.g., `.sidebar` → `.popover`)
4. **Accessibility fail?** → Implement reduce transparency fallback immediately
5. **No depth?** → Add subtle shadow to floating elements (elevation.2)

---

# DELIVERABLE E: Reference Gallery

## E1. Apps with Exemplary macOS UI

### 1. **Raycast** (raycast.com)

- **What they do right:** Excellent use of SF Symbols, consistent `.popover` material, keyboard-first design, subtle blur with solid fallback for accessibility
- **Reference:** [Raycast](https://raycast.com)

### 2. **Linear** (linear.app)

- **What they do right:** Clean typography scale, proper sidebar with source-list style, consistent spacing, dark mode first-class
- **Reference:** [Linear](https://linear.app)

### 3. **Figma** (figma.com)

- **What they do right:** Toolbar with unified style, proper keyboard shortcuts, context menus, responsive panels
- **Reference:** [Figma](https://figma.com)

### 4. **VS Code** (code.visualstudio.com)

- **What they do right:** Sidebar navigation, activity bar, status bar — all following macOS conventions despite being Electron
- **Reference:** [VS Code](https://code.visualstudio.com)

### 5. **Apple Notes** (Built-in)

- **What they do right:** Native sidebar, proper materials, SF Symbols, perfect Dark Mode support, accessibility-compliant
- **Reference:** System app

### 6. **Apple Music** (Built-in)

- **What they do right:** Toolbar with segmented controls, sidebar navigation, proper popover materials, album art as visual anchors
- **Reference:** System app

### 7. **Apple Podcasts** (Built-in)

- **What they do right:** Sidebar with source-list style, toolbar with search, proper window controls, seamless fullscreen
- **Reference:** System app

### 8. **Notion** (notion.so)

- **What they do right:** Clean typography, sidebar navigation, keyboard shortcuts, consistent with macOS visual language despite being web-based
- **Reference:** [Notion](https://notion.so)

### 9. **TablePlus** (tableplus.com)

- **What they do right:** Native-feeling UI, proper sidebar, toolbar, SF Symbols, excellent Dark Mode
- **Reference:** [TablePlus](https://tableplus.com)

### 10. **Alfred** (alfredapp.com)

- **What they do right:** Popover UI with proper `.popover` material, keyboard-driven, consistent with macOS design language
- **Reference:** [Alfred](https://www.alfredapp.com)

### 11. **CleanShot X** (cleanshot.com)

- **What they do right:** Floating panel design with proper materials, subtle animations, macOS-native feel
- **Reference:** [CleanShot X](https://cleanshot.com)

### 12. **Arc Browser** (arc.net)

- **What they do right:** Innovative sidebar, custom toolbar, proper use of blur/materials, keyboard-first
- **Reference:** [Arc](https://arc.net)

---

## Key Takeaways from Reference Apps

1. **Sidebar is king** — Every great macOS app uses a leading-edge sidebar with source-list styling
2. **Materials matter** — Proper use of `.sidebar`, `.toolbar`, `.popover` creates the "native" feel
3. **Typography ties it together** — SF Pro at semantic sizes, consistent hierarchy
4. **Keyboard is expected** — Every top app has comprehensive keyboard shortcuts
5. **Accessibility is non-negotiable** — The best apps work perfectly with Reduce Transparency/Motion

---

_Document Version: 1.0_  
_Next Review: When Apple releases major HIG updates (check annually)_
