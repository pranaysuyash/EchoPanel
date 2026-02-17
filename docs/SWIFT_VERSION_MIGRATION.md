# Swift Version Migration Plan

**Date**: 2026-02-16  
**Current Status**: Swift 5.9 (tools) / Swift 6.2.3 (system)  
**Target**: Swift 6.x full migration  

---

## Current Situation

### What We Have
| Component | Version | Notes |
|-----------|---------|-------|
| System Swift | 6.2.3 | Latest (Xcode 16+) |
| Package Tools | 5.9 | `swift-tools-version: 5.9` |
| Platform Target | macOS 14 | Sonoma (2023) |
| Swift Language Mode | 5.x (implied) | Not explicitly set to 6 |

### Why We're on Swift 5.9

```swift
// Package.swift
// swift-tools-version: 5.9
platforms: [.macOS(.v14)]
```

**Historical reasons**:
1. **macOS 13 (Ventura) compatibility** - Original target was macOS 13
2. **Dependency compatibility** - Some packages required 5.9
3. **Stability** - Swift 6 has stricter concurrency checking

---

## Swift 6 Benefits

### Performance
- **10-15% faster** compilation on average
- **Better runtime performance** with optimized ARC
- **Smaller binaries** with dead code elimination improvements

### Safety
- **Strict concurrency checking** by default (no more warnings, actual errors)
- **Sendable protocol enforcement** - catches data races at compile time
- **Actor isolation** - clearer concurrency boundaries

### Features
- **Macros** - Code generation at compile time (Swift 5.9+, but mature in 6)
- **C++ interop** - Better interoperability with C++ libraries
- **Typed throws** - More precise error handling (`throws(MyError)`)
- **Pack iteration** - Better variadic generic handling

---

## Migration Plan

### Phase 1: Preparation (Now - Week 1)

**Enable Swift 6 Warnings**
```bash
# Build with Swift 6 language mode warnings
swift build -Xswiftc -swift-version -Xswiftc 6
```

**Current Warnings to Fix** (as of 2026-02-16):
```
ResilientWebSocket.swift:333:23: warning: call to main actor-isolated instance method 'handleSendError' in a synchronous nonisolated context
ResilientWebSocket.swift:496:36: warning: main actor-isolated property 'lastPongTime' can not be referenced from a Sendable closure
VoiceNoteCaptureManager.swift:130:23: warning: capture of 'self' with non-Sendable type 'VoiceNoteCaptureManager?' in a '@Sendable' closure
SidePanelTranscriptSurfaces.swift:50:14: warning: 'onChange(of:perform:)' was deprecated in macOS 14.0
```

**Tasks**:
1. Fix MainActor isolation warnings in ResilientWebSocket
2. Add `@Sendable` annotations where needed
3. Fix deprecated `onChange` usage
4. Make classes conform to `Sendable` where appropriate

### Phase 2: Package.swift Update (Week 2)

**Update Package.swift**:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingListenerApp",
    platforms: [
        .macOS(.v14)  // Keep same, but could bump to .v15
    ],
    swiftLanguageVersions: [.v6],  // Explicit Swift 6
    // ... rest unchanged
)
```

**Dependency Check**:
| Dependency | Current | Swift 6 Compatible? |
|------------|---------|---------------------|
| swift-snapshot-testing | 1.17.4 | ✅ Yes (1.18.0+) |
| swift-syntax (transitive) | Latest | ✅ Yes |

### Phase 3: Concurrency Hardening (Week 3-4)

**Key Changes Needed**:

1. **ResilientWebSocket** - Actor isolation
   ```swift
   @MainActor
   final class ResilientWebSocket: NSObject {
       // All state access on MainActor
   }
   ```

2. **Data Classes** - Sendable conformance
   ```swift
   struct TranscriptSegment: Sendable {
       // Value types are automatically Sendable
   }
   
   final class AudioCaptureManager: @unchecked Sendable {
       // Reference types need explicit @unchecked or proper isolation
   }
   ```

3. **Callback Closures** - @Sendable annotation
   ```swift
   func performOperation(completion: @escaping @Sendable () -> Void)
   ```

### Phase 4: Testing & Validation (Week 5)

**Test Matrix**:
```bash
# macOS 14 (Sonoma)
swift test

# macOS 15 (Sequoia) - if available
swift test

# With strict concurrency checking
swift build -Xswiftc -strict-concurrency=complete
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Strict concurrency breaks existing code | High | Fix warnings incrementally before migration |
| Dependencies not Swift 6 ready | Medium | Check all deps, fork/patch if needed |
| Performance regressions | Low | Benchmark before/after |
| macOS version requirement bump | Medium | Keep macOS 14 minimum for now |

---

## Benefits Post-Migration

1. **Data Race Prevention** - Compile-time guarantees instead of runtime crashes
2. **Better IDE Support** - Swift 6 has improved SourceKit
3. **Future-Proof** - New APIs will require Swift 6
4. **Performance** - Faster builds and smaller binaries

---

## Current Blockers

**None for Phase 1 (warning fixes)**

**For full migration**:
1. Need to fix ~20 concurrency warnings
2. Need to verify all dependencies compile with Swift 6
3. Should test on both macOS 14 and 15

---

## Recommendation

**Short term**: Stay on Swift 5.9 tools version, fix Swift 6 warnings incrementally  
**Medium term**: Migrate to Swift 6 after launch (v0.4 or v0.5)  
**Long term**: Keep current with latest Swift

**Priority**: Medium - not blocking launch, but should address warnings to make future migration easier.

---

## References

- [Swift 6 Release Notes](https://swift.org/blog/swift-6-released/)
- [Swift 6 Migration Guide](https://www.swift.org/migration/)
- [Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
