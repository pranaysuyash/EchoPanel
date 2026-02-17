# EchoPanel UI/Visual Design Concept

**Author:** Apple Design Expert  
**Date:** 2026-02-09  
**Status:** Concept / Future Direction  
**Related:** Complements `ALTERNATIVE_ARCHITECTURE_VISION.md` (code architecture) and `COMPANION_VISION.md` (product features)

---

## Update (2026-02-13)

This document is explicitly a "future direction" concept (not an audit of current state). Since 2026-02-09, the codebase has already moved toward a more consistent visual system in a few concrete, low-risk ways:

- A centralized token set exists for corner radii, spacing, typography, strokes, and semantic backgrounds. Evidence: `macapp/MeetingListenerApp/Sources/DesignTokens.swift`.
- Focus and selection visuals now respect system affordances more closely (system focus ring + system accent tint) rather than hardcoded colors. Evidence: `macapp/MeetingListenerApp/Sources/DesignTokens.swift`.

The larger stylistic shifts proposed here (warm "paper & ink" palette, editorial serif typography, removing material/glass, adaptive density replacing explicit Roll/Compact/Full) are *not* implemented as of 2026-02-13; they remain roadmap-level design exploration and would require careful UX validation and iteration to avoid regressions.

## 1. Design Philosophy: "Companion, Not Tool"

### Current State
EchoPanel feels like a **utility** — functional, glassy, cool-toned, mode-switching.

### Vision
EchoPanel as a **skilled assistant** — warm, paper-like, adaptive, always present but never intrusive.

**Mood Board:**
- Things 3 (clarity and calm)
- Apple Notes (warmth and texture)
- Linear (precision and confidence)
- Craft (spatial depth and organization)

---

## 2. Visual Language: "Paper & Ink"

### Color Palette: Warm Neutrals

Never pure black or white. Always warm undertones.

| Element | Day (6am-6pm) | Evening (6pm-10pm) | Night (10pm-6am) |
|---------|---------------|-------------------|------------------|
| Background | `#FDFCF8` (warm white) | `#F8F6F1` (cream) | `#1C1C1E` (warm dark) |
| Surface | `#F5F3EE` (cream) | `#EDEAE4` (deeper cream) | `#2C2C2E` (elevated) |
| Text Primary | `#1A1A1A` (soft black) | `#2A2A2A` | `#F5F5F7` (warm white) |
| Text Secondary | `#6B6B6B` | `#5A5A5A` | `#A1A1A6` |
| Accent | `#2563EB` (calm blue) | `#4F46E5` (indigo) | `#60A5FA` (soft blue) |

### Typography: Editorial, Not System

**Serif for content, Sans for chrome:**

| Usage | Font | Size | Weight |
|-------|------|------|--------|
| Meeting Title | Charter / New York | 24pt | Bold |
| Transcript Text | Charter / New York | 15pt | Regular |
| Timestamps | SF Mono | 12pt | Regular |
| UI Labels | SF Pro Text | 13pt | Medium |
| Metadata | SF Pro Text | 11pt | Regular |

**Why:**
- Transcript is **content to be read** — deserves editorial typography
- UI is **chrome to be scanned** — needs clean sans-serif
- Serif creates warmth (meetings are human conversations)
- Monospace timestamps create rhythm and scanability

### Materials: Matte, Not Glass

- **No ultra-thin material** (`.ultraThinMaterial` is too cold)
- **No glass effects** (blur and vibrancy are distracting)
- **Subtle paper texture** (like Notes app, 2-3% opacity noise)
- **Soft shadows** (1-2pt depth, 20% opacity) not glows
- **No borders** — spacing and typography create structure

---

## 3. Navigation Model: "Floating Command Center"

### Current: Explicit Modes
Menu bar → Side panel (Roll/Compact/Full) → Settings in onboarding

### Vision: Spatial Canvas
Think **Figma's canvas meets iPad multitasking**.

```
┌─────────────────────────────────────────────┐
│  [Menu Bar: Recording Indicator]            │
├─────────────────────────────────────────────┤
│                                             │
│     ┌─────────────────┐                     │
│     │                 │     ┌──────────┐    │
│     │   Main Canvas   │────▶│  Tools   │    │
│     │   (Transcript)  │     │  Rail    │    │
│     │                 │     │          │    │
│     └─────────────────┘     └──────────┘    │
│           │                                 │
│           ▼                                 │
│     ┌─────────────────┐                     │
│     │  Smart Bar      │                     │
│     │  (Actions/Input)│                     │
│     └─────────────────┘                     │
│                                             │
└─────────────────────────────────────────────┘
```

**Key Principles:**
- Canvas adapts to window size, not explicit mode selection
- Workspaces slide in like iPad sidebars, not overlays
- Smart bar contextualizes to current activity

---

## 4. Adaptive Density (Replaces Roll/Compact/Full)

### Fluid Layout System

Instead of forcing users into modes, the UI **breathes** with the window:

| Window Size | Density | What Shows |
|-------------|---------|------------|
| **Micro** (300px) | Floating head | Live indicator + last line only |
| **Narrow** (400px) | Focus | Transcript + 1 priority card |
| **Standard** (600px) | Balanced | Transcript + 3 cards + quick entities |
| **Wide** (900px+) | Command | Everything + persistent inspector |

### Interaction Patterns

- **Hover near edge** → Preview wider layout
- **Drag to expand** → Stays expanded (persists)
- **Pin card** → Card persists across density changes
- **Focus mode** (keyboard shortcut) → Temporarily collapses to Micro
- **No mode picker** — the UI just adapts

---

## 5. Information Architecture: "Time & Topics"

### Current: Transcript-First
Transcript is primary. Cards overlay on top.

### Vision: Timeline-First
**Timeline is the anchor**, not the transcript.

```
┌──────────────────────────────────────────────────┐
│  Timeline Strip (always visible, top)            │
│  ├─ 9:00 ───────────────────────────┤          │
│  │  [●──Meeting Start──●]            │          │
│  │       [●──Decision: Ship──●]      │          │
│  │              [●──Action──●]       │          │
│  │                    [●──Risk───●]  │          │
│  └──────────────────────────────────┘          │
├──────────────────────────────────────────────────┤
│  Content Area (contextual)                       │
│  ├─ Click "Decision: Ship" → Vote UI             │
│  ├─ Click timeline gap → Transcript for time     │
│  ├─ Hover segment → Preview tooltip              │
└──────────────────────────────────────────────────┘
```

**Navigation Model:**
- Timeline provides **temporal orientation** (like video scrubber)
- Transcript is **searchable** but not always visible
- Cards **emerge from timeline**, not overlay

---

## 6. Workspaces: "Contextual Spaces"

### Current: Surface Overlay
Actions/Decisions/Risks/Entities appear as floating panels.

### Vision: Dedicated Spaces
Workspaces slide in from right like **iPad sidebars**.

```
Main View:
┌─────────────────────────────────┬────────────────┐
│                                 │                │
│  Transcript Canvas              │   Workspace    │
│  (Timeline + Content)           │   (Slide-in)   │
│                                 │                │
│                                 │   ┌──────────┐ │
│                                 │   │ Actions  │ │
│                                 │   ├──────────┤ │
│                                 │   │ Decisions│ │
│                                 │   ├──────────┤ │
│                                 │   │ Risks    │ │
│                                 │   └──────────┘ │
├─────────────────────────────────┴────────────────┤
│ Smart Bar (contextual actions)                   │
└──────────────────────────────────────────────────┘
```

**Workspace Behaviors:**
- Remember scroll position when switching
- Can be pinned open or auto-hide
- Swipe gestures on trackpad to switch between

---

## 7. The "Cards" Redesign: Polaroids

### Current
Rectangular panels with sharp corners, floating over content.

### Vision: Polaroid-Style Cards
Physical photo aesthetic with soft shadows and tactile interaction.

```
Visual Style:
┌────────────────────────┐
│  [Polaroid card]       │
│  ┌────────────────┐    │
│  │                │    │
│  │   Card content │    │
│  │                │    │
│  └────────────────┘    │
│  "Decision: Ship v2"   │
│  ───────────────────── │
│  Status: Pending       │
│  [Approve] [Edit]      │
└────────────────────────┘

Stacked (multiple cards):
     ┌───────────┐
    ┌┴──────────┐│
   ┌┴──────────┐││
   │ Top card  │││
   └───────────┘┘┘
```

**Interactions:**
- **Drag** to reorder stack
- **Swipe** to archive
- **Long-press** to expand full
- **Tap** to "flip" (front: summary, back: details/edit)

---

## 8. Meeting Lifecycle: Ambient Status

### Current
Status shown as small text under title. Explicit states (idle/starting/listening).

### Vision: Status Integrated into Chrome

| Phase | Visual Treatment |
|-------|------------------|
| **Ready** | Window shows subtle "EchoPanel" wordmark. Timeline: "No active meeting". Big friendly "Start" button. |
| **Recording** | Menu bar icon pulses gently (red dot). Window title becomes **live waveform**. Timeline shows moving scrubber. |
| **Paused** | Waveform freezes. Timeline dims. "Paused" label appears. |
| **Review** | Waveform becomes solid line showing duration. Timeline fully scrubbable. "Export" becomes primary. |

### First Success Moment
Instead of just starting, celebrate the first transcript line:

1. User clicks "Start"
2. First line appears with **gentle sparkle animation**
3. **Transient toast**: "EchoPanel is listening. Speak to test."
4. Toast fades after 5 seconds or on interaction

---

## 9. Onboarding: Contextual Learning

### Current
Step-by-step wizard (Welcome → Permissions → Source → Token → Ready)

### Vision: Progressive Disclosure

**Day 0 Experience:**
1. App opens in **demo mode** (pre-recorded meeting playing)
2. User sees the UI "working" immediately
3. **Tooltips on hover**: "This is the timeline," "Click to expand"
4. **"Try it yourself"** button triggers first permission request
5. **Gentle coaching UI** during first real meeting (non-blocking tips)

**Permission Requests:**
- Asked **when feature first needed**, not upfront
- Microphone: When clicking "Start" first time
- Screen recording: When selecting "System Audio"
- HuggingFace token: When clicking "Enable Speaker Labels"

**Empty States:**
- Show **example data**, not "No items" text
- Example cards with sample actions/decisions
- "This is where actions will appear"

---

## 10. Micro-Interactions: Physical, Not Digital

### Animation Principles

| Interaction | Treatment |
|-------------|-----------|
| **Pin segment** | Card "lifts" (scale 1.05, shadow deepens), settles with spring |
| **New transcript** | "Slides up" from bottom with physics, not fade |
| **Density change** | Fluid layout morph, not jump cut |
| **Card approval** | Stamp effect (scale bounce + ink spread) |
| **Scroll to live** | Smooth deceleration (iOS-style), not jump |

### Sound Design
- **Pin:** Subtle "thumbtack" click
- **New segment:** Soft "pop" (quiets as meeting gets longer)
- **Export complete:** Satisfying "whoosh"
- **Error:** Gentle "thud" (not alarming)

---

## 11. Summary: The Shift

| Aspect | Current | Vision |
|--------|---------|--------|
| **Metaphor** | Tool | Companion |
| **Materials** | Glass, neon, cool | Paper, ink, warm |
| **Structure** | Modes you switch | Density that adapts |
| **Navigation** | Overlay panels | Spatial workspaces |
| **Typography** | System fonts | Editorial (serif + sans) |
| **Status** | Explicit controls | Ambient, integrated |
| **Onboarding** | Wizard | Contextual learning |
| **Theme** | Dark/Light binary | Daylight adaptive |
| **Cards** | Panels | Polaroids |
| **Animation** | Standard fades | Physics-based |

---

## 12. Implementation Notes

### What Changes
- Visual design system (colors, typography, materials)
- Layout system (adaptive density vs explicit modes)
- Navigation model (timeline-first vs transcript-first)
- Onboarding flow (contextual vs wizard)

### What Stays
- Three information types (transcript, cards, entities)
- Core actions (pin, expand, jump to live)
- Keyboard shortcuts
- Export functionality

### Technical Considerations
- SwiftUI supports adaptive layouts with `ViewThatFits` and `GeometryReader`
- Custom fonts require font files bundled in app
- Physics animations use `.spring()` and `matchedGeometryEffect`
- Daylight adaptive theme requires time-based environment

---

## 13. Relation to Other Vision Docs

| Document | Focus | This Document |
|----------|-------|---------------|
| `ALTERNATIVE_ARCHITECTURE_VISION.md` | Code structure (TCA, protocols) | Visual design (how it looks) |
| `COMPANION_VISION.md` | Product features (Sidebar, LLM, Chat) | Interaction design (how it feels) |
| `UI_UX_AUDIT_2026-02-09.md` | Current state problems | Future state vision |

**Reading Order:**
1. This document for the **visual and interaction vision**
2. `COMPANION_VISION.md` for **feature roadmap**
3. `ALTERNATIVE_ARCHITECTURE_VISION.md` for **implementation approach**
