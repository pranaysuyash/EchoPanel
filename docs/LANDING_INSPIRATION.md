# Landing Page Inspiration — Textream

Source: https://blog.fka.dev/textream/

Textream is a free macOS teleprompter app. Its landing page has strong design patterns worth adapting for EchoPanel.

---

## Elements to adopt

### 1. Live demo animation (high priority)

Textream's hero features an animated "screen frame" with a notch overlay that expands and highlights words in real-time as a simulated voice speaks. It cycles through scenes (Meet call, presentation, recording).

**EchoPanel adaptation:** Build an animated panel mockup where transcript lines appear one by one, a "Decision" pill highlights, and the waveform bars animate — showing the product working without a video.

**Key CSS patterns:**
- `.screen-frame` with `aspect-ratio: 16/10`, dark gradient bg, rounded corners, heavy box-shadow
- `.demo-words span` transitions between `color: rgba(255,255,255,1)` (unread) → `.highlighted` at `0.3` opacity (read)
- `.demo-waveform .bar` elements with CSS height transitions and a `.lit` state (yellow glow)
- Scene switching via `.scene.active { opacity: 1 }` with `transition: opacity 0.6s ease`

### 2. Gradient headline text

Textream applies a gradient to key words in the h1:

```css
.gradient {
  background: linear-gradient(135deg, var(--accent1), var(--accent2));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
```

**EchoPanel adaptation:** Wrap "Live meeting notes" in a gradient span using `#1f6feb` → `#5ac8fa` (existing brand blue to sky blue).

### 3. Background glow

Textream uses a single fixed radial gradient behind the hero:

```css
.bg-glow {
  position: fixed;
  top: -40%;
  left: 50%;
  transform: translateX(-50%);
  width: 900px;
  height: 900px;
  background: radial-gradient(circle, rgba(124,106,255,0.1) 0%, transparent 70%);
  pointer-events: none;
}
```

**EchoPanel adaptation:** Replace the three `.mesh-orb` elements with a single, cleaner glow in EchoPanel blue. Simpler and less noisy.

### 4. Audio waveform visualizer

Textream renders a row of thin bars that animate height to simulate live audio:

```css
.demo-waveform .bar {
  width: 3px;
  border-radius: 1.5px;
  background: rgba(255,255,255,0.15);
  transition: height 0.08s ease-out;
  min-height: 4px;
}
.demo-waveform .bar.lit {
  background: rgba(255, 214, 10, 0.9);
}
```

**EchoPanel adaptation:** Add waveform bars to the hero panel mockup's header, next to "Streaming · Audio: Good". Animate with JS on a short interval.

### 5. Scene transitions

Textream cycles the demo background between three contexts (Meet, presentation, recording) using absolute-positioned `.scene` divs with opacity transitions.

**EchoPanel adaptation:** Cycle the hero visual between "Google Meet", "Zoom", and "In-person" contexts with different silhouettes/labels, showing EchoPanel works with any audio source.

### 6. Mode/feature cards with icons

Textream's "Three ways to guide your read" section uses cards with small icon containers:

```css
.feature-icon {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: rgba(124, 106, 255, 0.1);
}
```

**EchoPanel adaptation:** Upgrade `.value-card` to include SVG icons in tinted containers for Transcript, Decisions, Timeline, and Documents.

### 7. Numbered step pills

Textream uses CSS counters with gradient backgrounds for steps:

```css
.step::before {
  content: counter(step);
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: linear-gradient(135deg, var(--accent1), var(--accent2));
  color: #fff;
  font-size: 18px;
  font-weight: 700;
}
```

**EchoPanel adaptation:** Replace the serif `01/02/03` step numbers with gradient pill badges.

### 8. Dark mode variant

Textream's entire palette is dark:

```css
:root {
  --bg: #0A0A0C;
  --surface: #1C1C1E;
  --text: #F5F5F7;
  --text2: #86868B;
  --accent1: #7C6AFF;
  --accent2: #4F8BFF;
}
```

**EchoPanel adaptation:** Add a `prefers-color-scheme: dark` media query or a toggle. The dark palette suits EchoPanel's "always-on overlay" positioning and matches the actual app UI (dark menu bar + panel).

---

## Priority order

| # | Element | Effort | Impact |
|---|---------|--------|--------|
| 1 | Live demo animation | High | Very high |
| 2 | Gradient headline | Low | Medium |
| 3 | Background glow cleanup | Low | Medium |
| 4 | Waveform visualizer | Medium | High |
| 5 | Scene transitions | Medium | High |
| 6 | Feature card icons | Low | Medium |
| 7 | Step pill badges | Low | Low |
| 8 | Dark mode | Medium | Medium |
