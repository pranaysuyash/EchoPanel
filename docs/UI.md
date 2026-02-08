# UI Notes (v0.2)

## Surfaces
- Menu bar item
  - States: Idle, Listening, Error
  - Primary action: Start/Stop toggle
  - Timer display (`mm:ss`)
- Floating side panel
  - Three presentations from one interaction spine:
    - `Roll` (default, transcript-first live mode)
    - `Compact` (minimal companion mode)
    - `Full` (persistent insight surfaces + review tooling)
  - `Full` renderer adds review tooling from the HTML design set:
    - Session rail (current + historical sessions)
    - Work mode selector (`Live`, `Review`, `Brief`)
    - Search field (`Cmd/Ctrl+K` focus) and speaker chips
    - Persistent insight panel tabs (`Summary`, `Actions`, `Pins`, `Context`, `Entities`, `Raw`)
    - Timeline scrub strip for focus-jump navigation
  - Persistent controls: `Copy Markdown`, `Export JSON`, `Export Markdown`, `End Session`
  - Status line and listening state are always visible
  - Audio quality and source meters remain visible in top capture controls
  - In all modes, audio setup controls are collapsed by default behind `Audio Setup` so live transcript area remains primary.
  - Permission warnings are rendered as a single compact action row to avoid pushing transcript content below the fold.
  - Source diagnostics strip shows selected-source freshness:
    - `In <age>` = last captured input frame age by source
    - `ASR <age>` = last transcript event age by source
  - Current source granularity is `System Audio` (all app/browser output mix) and `Microphone` (input device), not per-app routing.

## Interaction invariants
- Focus cursor is first-class (`focusedSegmentID`).
- Follow-live is explicit state (`followLive`), not just scroll position.
- Lens is contextual (`lensSegmentID`) and opens inline on focused transcript line.
- Pins are annotations on transcript lines (`pinnedSegmentIDs`).
- Same surfaces exist in all presentations: `Summary`, `Actions`, `Pins`, `Entities`, `Raw`.
  - `Full`: persistent right-side surface panel
  - `Roll` / `Compact`: overlay surface panel
- `Context` appears as a `Full` insight tab and intentionally does not map to the shared overlay-surface list.

## Keyboard contract
- `↑ / ↓` move focus
- `Enter` toggle lens on focused line
- `P` pin/unpin focused line
- `Space` toggle follow-live
- `J` jump to live
- `← / →` open/cycle surfaces (or cycle persistent surface in `Full`)
- `Esc` close one layer (help -> surface overlay -> lens)
- `?` toggle shortcuts overlay
- `Cmd/Ctrl + K` focus Full-view search

## Transcript rendering rules
- Append-only list for finalized segments.
- Partial segment is rendered in a lighter style.
- Final segment replaces the active partial cleanly, without duplicating text.
- Each final segment shows timestamp, speaker context, and confidence.

## Apple HIG alignment decisions (v0.2)
- Use semantic system materials/colors (`windowBackgroundColor`, `controlBackgroundColor`, `textBackgroundColor`, `separatorColor`) so the panel adapts cleanly in light/dark appearances.
- Keep hierarchy compact and scannable with two header rows:
  - Row 1: identity + mode switcher.
  - Row 2: listening status + timer.
- Keep capture controls grouped in a single, bordered control card (`Audio source`, `Follow`, shortcuts help) with meters and quality chip below.
- Use responsive layout fallbacks instead of rigid control widths:
  - Top row and capture controls stack on narrow widths.
  - Full view collapses from 3-column to 2-column-plus-stacked-insight when space is constrained.
  - Footer actions fall back to compact icon/menu controls to avoid clipping.
- Prefer plain-language state labels over internal/system jargon:
  - `Ready`, `Preparing`, `Permission needed`, `Setup needed`, `Listening`, `Finalizing`.
- Respect accessibility preferences:
  - Reduce Motion disables animated transcript scrolling transitions.
  - Micro-actions include accessibility labels for pin/lens/jump operations.
- Persist the selected side panel mode across sessions via `@AppStorage("sidePanel.viewMode")`.
