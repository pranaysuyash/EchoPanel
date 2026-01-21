# UI Notes (v0.1)

## Surfaces
- Menu bar item
  - States: Idle, Listening, Error
  - Primary action: Start/Stop toggle
  - Timer display (mm:ss)
- Floating side panel
  - Three lanes only: Transcript, Cards, Entities
  - Persistent controls: Copy Markdown, Export JSON, End session
  - Status line: Streaming/Reconnecting/Backend unavailable
  - Audio quality: Good/OK/Poor

## Transcript rendering rules
- Append-only list for finalized segments.
- Partial segment is rendered in a lighter style.
- Final segment replaces the active partial cleanly, without duplicating text.
- Each final segment shows a timestamp.

