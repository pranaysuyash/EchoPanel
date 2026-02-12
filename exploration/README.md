# Exploration / HTML Prototypes

This folder contains HTML-based UI prototypes for the **EchoPanel macOS app**. These files were created during the design and exploration phase to iterate on UI concepts before implementing them in native SwiftUI.

## Files

- **`echopanel.html`** - Full-view interface prototype with session rail, insight tabs, timeline scrub, and pins UI
- **`echopanel_sidepanel.html`** - Side panel surface prototype for compact overlay UI
- **`echopanel_roll.html`** - Roll view prototype with pins state tracking

## Purpose

These HTML prototypes serve as:

1. **UI/UX reference** - Visual and interaction design reference for native SwiftUI implementation
2. **Feature exploration** - Rapid prototyping of features like pins, timeline scrub, and panel layouts
3. **Documentation** - Historical record of design decisions and interaction patterns

## Status

These are **prototypes only** - the actual EchoPanel application is a native macOS menu-bar app located in `macapp/MeetingListenerApp/`.

Not all features from these prototypes are implemented in the native app. Refer to `macapp/MeetingListenerApp/Sources/` for the current implementation status.

## Related Documentation

- [macOS App Source](../macapp/MeetingListenerApp/) - Native SwiftUI implementation
- [docs/UI.md](../docs/UI.md) - UI documentation and contracts
- [docs/WORKLOG_TICKETS.md](../docs/WORKLOG_TICKETS.md) - Feature implementation tracking
