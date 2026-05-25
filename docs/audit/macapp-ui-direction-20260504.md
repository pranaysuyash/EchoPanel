# EchoPanel macOS UI Direction — 2026-05-04

## Intent

Reframe the live macOS panel as a meeting workspace rather than a collection of controls. The UI should optimize for trust, legibility, and actionability:

- Clear session state and capture state at a glance
- Transcript-first live experience
- Insights as a secondary, summonable layer
- Stronger separation between live work, review, and historical session navigation

## Direction Applied

- Elevated the top chrome into a clearer status/header block with stronger hierarchy
- Simplified collapsed capture controls so the app reads as "what is happening now" before "what can I configure"
- Renamed secondary surface affordances toward "Insights" instead of generic surface language
- Added compact metric badges for transcript, actions, decisions, and entities in full-mode workspace views
- Reframed full mode around three explicit zones:
  - Session rail
  - Transcript workspace
  - Insight panel

## Files Changed

- `macapp/MeetingListenerApp/Sources/DesignTokens.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelChromeViews.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelLayoutViews.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelStateLogic.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Roll/SidePanelRollViews.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Compact/SidePanelCompactViews.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Full/SidePanelFullViews.swift`
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelTranscriptSurfaces.swift`

## Remaining Follow-Through

- Visual verification in the running app
- Full Swift build/test after freeing more disk space or using a leaner dependency/build setup
- Ticket/worklog synchronization once the repo environment is stable enough for broader documentation updates
