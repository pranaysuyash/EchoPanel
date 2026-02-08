# UI Redesign Feedback Audit (2026-02-06)

## Scope
- Target: Current "redesigned" side panel UI in macOS app.
- Compare against requested redesign intent in `docs/UI_CHANGE_SPEC_2026-02-06.md`.
- Output: Practical feedback + correction direction.

## What was asked (Observed)
From `docs/UI_CHANGE_SPEC_2026-02-06.md` and related tickets:
- Portrait side panel (~30% width) with strong top alignment and compact scanability.
- Tabs: Transcript / Decisions / Timeline.
- POS-style rolling transcript window (12-20 recent segments).
- Always-visible status and quality cues.
- Keyboard tab switching.

## What shipped (Observed)
- Tabbed portrait layout exists with keyboard left/right switching (`macapp/MeetingListenerApp/Sources/SidePanelView.swift`).
- Rolling transcript cap exists (`maxTranscriptSegments = 20`).
- Header includes status, permissions, source picker, meters, pills, timer.
- Material/glass styling added (`glassBackground`, `LaneCard`).

## Critical visual/UX issues (Observed from screenshots + code)

### 1) Header overload and broken hierarchy (P1)
- The top area has too many competing elements: title, status copy, permission card(s), source picker, meters, status pills, timer.
- In screenshots, this creates noisy composition and low information priority; eye has no clear primary anchor.
- Source: screenshot + `header` block in `SidePanelView.swift`.

### 2) Degenerate/chopped controls under width pressure (P1)
- Vertical/stacked clipping (e.g., "Idle", "Audio Unknown") indicates controls collapse badly in narrow portrait widths.
- Fixed widths (`frame(width: 200)` for source segmented picker) and dense trailing pills contribute to layout breakage.
- Source: screenshot + `SidePanelView.swift` header constraints.

### 3) Too much chrome, not enough signal (P1)
- Multiple rounded containers, heavy borders, shadows, pills, and segmented controls stack visual noise.
- Transcript content (the core value) is visually de-emphasized, especially in empty-state.
- Source: screenshot + `glassBackground`, `LaneCard`, dense toolbar.

### 4) Permission warning block dominates when not listening (P1)
- Large red warning card in header steals focus and creates "error app" feel.
- For a companion side panel, this should be compact and contextual.
- Source: screenshot + `PermissionBanner` design.

### 5) Empty-state feels unfinished and cold (P2)
- Vast blank white area + tiny "Waiting for speech" text; no guidance.
- Should communicate source selection, readiness, and expected first transcript latency.
- Source: screenshot + transcript empty state in `SidePanelView.swift`.

### 6) Tab row is disconnected from content identity (P2)
- "View" + segmented tabs + "← → Tabs" hint reads dev-toolish, not premium product UI.
- Header/title/selected tab relationship lacks crisp structure.
- Source: screenshot + `tabPicker` implementation.

## My direct design verdict
- The redesign is functionally closer to the spec than old UI, but visually it is not at a premium quality bar.
- Main failure mode: density and hierarchy, not feature completeness.

## Recommended direction (specific)

### A) Two-row header architecture
1. Row 1: `Live Meeting Listener` + compact status chip + timer.
2. Row 2: Source picker + meters only.
3. Permission issues move to a thin inline alert strip below row 2 (single-line + action).

### B) Remove trailing pill cluster from header
- Drop persistent `Idle` and `Audio Unknown` pills from the right cluster.
- Keep one state chip only (Listening / Not Ready / Reconnecting).
- Audio quality can be shown near meters, not as separate major badge.

### C) Rework transcript lane to prioritize content
- Reduce container visual weight (lighter stroke/shadow).
- Keep one toolbar row: highlight mode + follow toggle + mention nav.
- Strong empty-state card with:
  - "Waiting for speech"
  - source reminder
  - "First transcript appears in ~2-5s"

### D) Tab strip simplification
- Remove "View" label and arrow hint from always-visible UI.
- Keep segmented tabs only; move keyboard hint into tooltip/help.

### E) Width-safe constraints
- Replace hard fixed `200` width source picker with adaptive min/max and explicit compression priorities.
- Ensure no control can vertically collapse text into stacked letters.

## Suggested implementation plan (short)
1. Refactor `header` into `HeaderPrimaryRow`, `HeaderCaptureRow`, `HeaderAlertRow`.
2. Simplify state chips to a single semantic chip.
3. Replace `PermissionBanner` card with compact inline warning strip.
4. Tune spacing scale: 16/12/8 rhythm; reduce nested card paddings.
5. Update empty-state visuals and microcopy in transcript tab.

## Bottom line
This should be treated as a visual hierarchy correction pass, not another feature pass. The app already has the right controls; they need restructuring and restraint.
