# macOS Floating Panel Implementation Guide

## Overview

This document describes how EchoPanel implements its floating side panel to stay visible during fullscreen video meetings (Zoom, Teams, Google Meet) without stealing keyboard focus.

## Problem Statement

Meeting assistant apps face a critical UX challenge:
1. **Must stay visible** when users enter fullscreen video calls
2. **Must not steal focus** when clicked (users need to type in meeting chat)
3. **Must follow the user** across Spaces/desktop switches

## Solution: NSPanel Configuration

### Core Window Class

Always use `NSPanel` (not `NSWindow`) for floating utility windows:

```swift
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
    styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

### Critical Configuration Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `styleMask` | `[.titled, .closable, .resizable, .nonactivatingPanel]` | `.nonactivatingPanel` is essential - allows clicks without activating the app |
| `isFloatingPanel` | `true` | Enables floating panel behavior |
| `level` | `.floating` | Stays above normal application windows |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | **CRITICAL**: `.fullScreenAuxiliary` allows visibility over fullscreen apps |
| `becomesKeyOnlyIfNeeded` | `true` | Prevents stealing keyboard focus unless user starts typing |
| `hidesOnDeactivate` | `false` | Panel stays visible when user switches to another app |
| `isReleasedWhenClosed` | `false` | Allows window to be reopened without recreation |

### Implementation Pattern

```swift
final class SidePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    
    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            // Basic setup
            panel.title = "EchoPanel"
            panel.contentViewController = host
            
            // Floating behavior
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            
            // CRITICAL: Stay visible over fullscreen apps (Zoom, Teams, etc.)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Don't steal keyboard focus from meeting apps
            panel.becomesKeyOnlyIfNeeded = true
            
            panel.delegate = self
            self.panel = panel
        }
        
        // Show without stealing focus
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }
}
```

## What NOT To Do

### ❌ Avoid `.utilityWindow` style mask

```swift
// WRONG - .utilityWindow still causes focus stealing
styleMask: [.titled, .closable, .resizable, .utilityWindow]

// CORRECT - .nonactivatingPanel allows interaction without activation
styleMask: [.titled, .closable, .resizable, .nonactivatingPanel]
```

### ❌ Avoid activating the app on show

```swift
// WRONG - This steals focus from the meeting
NSApp.activate(ignoringOtherApps: true)
panel?.makeKeyAndOrderFront(nil)

// CORRECT - Show without activating
panel?.makeKeyAndOrderFront(nil)
panel?.orderFrontRegardless()
```

### ❌ Don't use `.moveToActiveSpace` alone

```swift
// WRONG - Panel disappears when app enters fullscreen
panel.collectionBehavior = .moveToActiveSpace

// CORRECT - Panel stays visible in fullscreen
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

## Version Implementation Status

### v1 (macapp/MeetingListenerApp)

**File**: `macapp/MeetingListenerApp/Sources/SidePanelController.swift`

**Changes Applied**:
- ✅ Changed `.utilityWindow` → `.nonactivatingPanel`
- ✅ Changed `.moveToActiveSpace` → `[.canJoinAllSpaces, .fullScreenAuxiliary]`
- ✅ Added `becomesKeyOnlyIfNeeded = true`
- ✅ Removed aggressive `NSApp.activate()` calls

### v3 (macapp_v3 - Exploration)

**File**: `macapp_v3/Sources/EchoPanelV3App.swift`

**Changes Applied**:
- ✅ Added `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- ✅ Added `becomesKeyOnlyIfNeeded = true`
- ✅ Added `hidesOnDeactivate = false`
- ✅ Removed `NSApp.activate()` call

## Testing Checklist

Verify the implementation works correctly:

- [ ] Panel stays visible when Zoom enters fullscreen
- [ ] Panel stays visible when Teams enters fullscreen
- [ ] Panel follows user across desktop Spaces
- [ ] Clicking panel doesn't steal focus from meeting chat
- [ ] Typing in panel text fields works when focused
- [ ] Panel can be dragged by title bar
- [ ] Panel can be resized
- [ ] Panel remembers position across app restarts

## Technical Details

### `fullScreenAuxiliary` Behavior

From Apple documentation:
> The window participates in fullscreen apps as an auxiliary window. This allows the window to appear on top of fullscreen windows.

This is the flag that enables "meeting assistant" behavior. Without it, the window is hidden when any app enters fullscreen mode.

### `nonactivatingPanel` vs `utilityWindow`

| Feature | `utilityWindow` | `nonactivatingPanel` |
|---------|-----------------|----------------------|
| Shows without app activation | ❌ No | ✅ Yes |
| Accepts clicks without activation | ❌ No | ✅ Yes |
| Has title bar | ✅ Yes | ✅ Yes |
| Can be dragged | ✅ Yes | ✅ Yes |

### `becomesKeyOnlyIfNeeded` Behavior

When `true`:
- Clicking the panel doesn't make it the key window
- Typing still goes to the previously active app
- Panel only becomes key when user explicitly interacts with a text field

## References

- [Apple Documentation: NSPanel](https://developer.apple.com/documentation/appkit/nspanel)
- [Apple Documentation: NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior)
- [Human Interface Guidelines: Panels](https://developer.apple.com/design/human-interface-guidelines/panels)

## Related Files

- `macapp/MeetingListenerApp/Sources/SidePanelController.swift` - v1 implementation
- `macapp_v3/Sources/EchoPanelV3App.swift` - v3 exploration implementation
- `macapp_v3/Sources/Views/LivePanelView.swift` - Panel UI content
