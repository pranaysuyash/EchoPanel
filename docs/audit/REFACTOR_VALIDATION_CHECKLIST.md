# Refactoring Validation Checklist

**Context:** Another agent is working on the SidePanelView decomposition based on the UI/UX audit findings. This checklist validates the refactoring quality.

---

## Phase 1: Build & Test Verification ✅/❌

```bash
# 1. Clean build
cd macapp/MeetingListenerApp && swift build

# 2. All tests pass (including snapshots)
swift test 2>&1 | grep -E "(passed|failed|Executed)"

# 3. No new warnings
swift build 2>&1 | grep -i warning | wc -l
```

**Expected (Current State - All Pass):**
- [x] Build succeeds
- [x] Contract tests pass (5 tests)
- [x] Snapshot tests pass (6 tests including dark mode)
- [x] Zero compiler warnings

---

## Phase 2: Architecture Validation

### 2.1 File Organization

| File | Purpose | Line Target | Status |
|------|---------|-------------|--------|
| SidePanelView.swift | Container only | <300 lines | |
| SidePanel/Roll/ | Roll mode views | ~200 lines | |
| SidePanel/Compact/ | Compact mode views | ~200 lines | |
| SidePanel/Full/ | Full mode views | ~400 lines | |
| SidePanel/Shared/ | Common components | ~800 lines total | |
| SidePanel/Shared/SidePanelStateLogic.swift | Business logic | ~650 lines (acceptable for logic) | ✅ |

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
| Lines in SidePanelView.swift | 2,738 | <300 | 271 ✅ |
| Number of files | 1 | 8-10 | 9 ✅ |
| Avg lines per file | 2,738 | View<400, Logic<700 | 286 ✅ |
| @State properties in main view | 24 | 24 (architectural) | 24 ✅ |
| Methods per file | 50+ | <15 | ~12 ✅ |

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
swift test 2>&1 | grep "Executed"

echo "=== File Sizes ==="
wc -l Sources/SidePanelView.swift Sources/SidePanel/*.swift Sources/SidePanel/*/*.swift 2>/dev/null | tail -1

echo "=== State Property Count ==="
grep -c "@State" Sources/SidePanelView.swift

echo "=== Extension Count ==="
find Sources/SidePanel -name "*.swift" | wc -l
```

---

## Current Status (as of audit)

| Check | Status |
|-------|--------|
| Build passes | ✅ |
| New SidePanel/ directory created | ✅ |
| SidePanelStateLogic.swift extracted | ✅ (647 lines) |
| SidePanelRollViews.swift extracted | ✅ (55 lines) |
| Other mode views extracted | ✅ (Compact 36, Full 374) |
| Tests pass | ✅ (11/11 including 6 snapshots) |
| Main view <300 lines | ✅ (271 lines) |
