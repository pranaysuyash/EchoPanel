# Refactoring Validation Checklist

**Context:** Use this when refactoring large SwiftUI surfaces (especially `SidePanelView`) to validate correctness, test stability, and maintainability.

**Source of truth for status/evidence:** `docs/WORKLOG_TICKETS.md`

---

## Phase 1: Build & Test Verification ✅/❌

```bash
# 1. Build
cd macapp/MeetingListenerApp && swift build

# 2. Unit/contract tests pass (visual snapshots are opt-in)
swift test

# 3. Check for compiler warnings (goal: no new warnings)
swift build 2>&1 | rg -n "warning:" || true

# 4. Visual snapshot tests (opt-in; stable by default)
RUN_VISUAL_SNAPSHOTS=1 swift test --filter SidePanelVisualSnapshotTests
RUN_VISUAL_SNAPSHOTS=1 swift test --filter StreamingVisualTests

# Record baselines (only when intentional visual change)
RUN_VISUAL_SNAPSHOTS=1 RECORD_SNAPSHOTS=1 swift test --filter SidePanelVisualSnapshotTests
RUN_VISUAL_SNAPSHOTS=1 RECORD_STREAMING_SNAPSHOTS=1 swift test --filter StreamingVisualTests
```

**Expected:**
- [ ] Build succeeds
- [ ] `swift test` succeeds without requiring snapshot env vars
- [ ] Visual snapshot tests run when `RUN_VISUAL_SNAPSHOTS=1`
- [ ] No new compiler warnings introduced (or new warnings are ticketed + explained)

---

## Phase 2: Architecture Validation

### 2.1 File Organization

| File | Purpose | Line Target | Status |
|------|---------|-------------|--------|
| `Sources/SidePanelView.swift` | Container only | <350 lines | |
| `Sources/SidePanelController.swift` | Wiring/controller | <250 lines | |
| `Sources/SidePanel/Roll/` | Roll mode views | <250 lines | |
| `Sources/SidePanel/Compact/` | Compact mode views | <250 lines | |
| `Sources/SidePanel/Full/` | Full mode views | <800 lines | |
| `Sources/SidePanel/Shared/` | Common components | keep files <800 lines when feasible | |
| `Sources/SidePanel/Shared/SidePanelStateLogic.swift` | Business logic | <900 lines (logic can be larger) | |

### 2.2 State Management Check

**Before (Problem):**
```swift
@State private var viewMode: ViewMode = .roll
@State private var followLive = true
// ... 15+ more @State properties in one view
```

**After (Better):**
Options to validate:
- [ ] State still in SidePanelView but well-organized (current approach)
- [ ] **OR** State extracted to `@Observable` class (preferred)

**Validation:**
```swift
// Check if state is still scattered:
grep -n "@State" SidePanelView.swift | wc -l
# Should be: manageable (<20 @State properties in main view)

// Check for state dependencies across files:
grep -rn "focusedSegmentID" SidePanel/ | wc -l
# Should be: >0 (extensions accessing state), showing proper organization
```

---

## Phase 3: Code Quality Checks

### 3.1 Access Control

**Current approach:** Made properties `internal` instead of `private`
```swift
// Before
@State private var viewMode: ViewMode = .roll

// After (for extension access)
@State var viewMode: ViewMode = .roll
```

**Validation:**
- [ ] Properties that can stay private are private
- [ ] Only necessary properties exposed to extensions
- [ ] No public access where not needed

**Better approach to consider:**
```swift
// Use @Observable for shared state
@Observable
class SidePanelState {
    var viewMode: ViewMode = .roll
    var followLive = true
    // ... other state
}

// Then in view:
@State private var panelState = SidePanelState()
```

### 3.2 Preview Support

**Check:** Can you preview individual components?

```swift
// Should be possible after refactor:
#Preview("Roll Mode") {
    RollView(state: RollState.mock)
}

#Preview("Transcript Line") {
    TranscriptLineRow(segment: .mock, ...)
}
```

- [ ] Individual view previews work
- [ ] Mock data available for previews

---

## Phase 4: Performance Validation

### 4.1 Recomputation Check

**Problem from audit:** `filteredSegments` recomputes on every access

**Validation:**
```swift
// Check if still recomputing:
grep -A5 "var filteredSegments" SidePanel/Shared/*.swift

// Should ideally be:
@State private var filteredSegments: [TranscriptSegment] = []
// Updated via onChange, not computed property
```

### 4.2 Body Size Check

```bash
# Check main body complexity:
wc -l SidePanelView.swift
# Target: <300 lines (was 2,738)

# Check extension file sizes:
wc -l SidePanel/*/*.swift
# Target: View files <450 lines, logic files <700 lines
```

---

## Phase 5: Maintainability Scores

| Metric | Before | Target | After |
|--------|--------|--------|-------|
| Lines in `Sources/SidePanelView.swift` | 2,738 | <350 | |
| Number of SidePanel files | 1 | 8-12 | |
| `@State` properties in main view | 24 | <20 | |
| Visual snapshots opt-in | N/A | YES | |

---

## Phase 6: What to Validate in Each File

### SidePanelStateLogic.swift
- [ ] All computed properties are pure (no side effects)
- [ ] Methods are well-named and single-purpose
- [ ] No UI code (View building) mixed with logic

### SidePanelRollViews.swift
- [ ] Only Roll-specific UI
- [ ] No references to Full/Compact mode internals
- [ ] Uses shared components from Shared/

### SidePanelFullViews.swift
- [ ] Full mode complexity managed
- [ ] Column layout logic is readable
- [ ] Session rail is reusable component

### SidePanelChromeViews.swift
- [ ] Header/footer components are reusable
- [ ] No mode-specific logic leaked
- [ ] Responsive layout works

---

## Phase 7: Red Flags to Watch For

### 🚩 Structural Issues
- [ ] Extensions becoming too large (>500 lines)
- [ ] Circular dependencies between files
- [ ] State mutations from multiple places
- [ ] Callback hell (many closure properties)

### 🚩 SwiftUI Anti-Patterns
- [ ] Using `@State` for derived data
- [ ] Multiple `GeometryReader` nested
- [ ] `AnyView` usage (type erasure)
- [ ] `DispatchQueue.main.async` in view code

### 🚩 Testing Issues
- [ ] Business logic still coupled to View
- [ ] No way to test state transitions in isolation
- [ ] Snapshot tests broken due to structure changes

---

## Phase 8: Next Steps After Refactor

### Immediate (This PR)
1. [ ] All validation checks pass
2. [ ] Re-record snapshot baselines if intentional visual changes
3. [ ] Update tests to use new structure
4. [ ] Document new file organization

### Follow-up (Next PRs)
1. [ ] Extract `@Observable` state class
2. [ ] Add PreviewProvider for each component
3. [ ] Extract design system (colors, spacing)
4. [ ] Add unit tests for SidePanelStateLogic

---

## Quick Validation Commands

```bash
# Full validation script
cd /Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp

echo "=== Build Check ==="
swift build 2>&1 | tail -3

echo "=== Test Check ==="
swift test 2>&1 | rg "Executed"

echo "=== Visual Snapshots (Opt-In) ==="
RUN_VISUAL_SNAPSHOTS=1 swift test --filter SidePanelVisualSnapshotTests 2>&1 | rg "Executed|Skipping"

echo "=== File Sizes ==="
wc -l Sources/SidePanelView.swift Sources/SidePanelController.swift Sources/SidePanel/*/*.swift Sources/SidePanel/Shared/*.swift 2>/dev/null | tail -n 15

echo "=== State Property Count ==="
grep -c "@State" Sources/SidePanelView.swift

echo "=== Extension Count ==="
find Sources/SidePanel -name "*.swift" | wc -l
```

---

## Current Observed State (2026-02-13)

These are observed from the repo state on 2026-02-13 (do not assume they stay true after further edits):

- File sizes (Swift LOC):
  - `macapp/MeetingListenerApp/Sources/SidePanelView.swift`: 284
  - `macapp/MeetingListenerApp/Sources/SidePanelController.swift`: 134
  - `macapp/MeetingListenerApp/Sources/SidePanel/Compact/SidePanelCompactViews.swift`: 66
  - `macapp/MeetingListenerApp/Sources/SidePanel/Full/SidePanelFullViews.swift`: 683
  - `macapp/MeetingListenerApp/Sources/SidePanel/Roll/SidePanelRollViews.swift`: 69
  - `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelStateLogic.swift`: 743
- `@State` count:
  - `macapp/MeetingListenerApp/Sources/SidePanelView.swift`: 14
- Snapshot tests:
  - Opt-in via `RUN_VISUAL_SNAPSHOTS=1` (see `macapp/MeetingListenerApp/Tests/SidePanelVisualSnapshotTests.swift`, `macapp/MeetingListenerApp/Tests/StreamingVisualTests.swift`)
- Known build warnings exist (Swift concurrency / Swift 6 mode):
  - `macapp/MeetingListenerApp/Sources/SessionBundle.swift`: `NSLock.lock/unlock` in `async` contexts; optional-to-Any coercions
  - `macapp/MeetingListenerApp/Sources/ResilientWebSocket.swift`: actor isolation warnings in sendable closures
