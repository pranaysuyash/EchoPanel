# Swift Coding Standards Audit — EchoPanel macOS App

**Date:** 2026-03-20  
**Auditor:** Swift/App Coding Standards Auditor  
**Project:** EchoPanel MeetingListenerApp + macapp_v2

---

## Build Status

### macapp/MeetingListenerApp
- ⚠️ **Build completes with warnings**
- Swift version: 6.x (inferred)
- Error: `escaping closure captures mutating 'self' parameter` at `MeetingListenerApp.swift:36`
- Deprecation warnings: `onChange(of:perform:)` deprecated in macOS 14.0 (lines 59, 64)

### macapp_v2
- ✅ **Builds successfully** (0.35s debug build)
- No compilation errors
- Uses SwiftUI App lifecycle with `@main`

---

## Architecture

### Pattern: MVVM with ObservableObject

| Component | Pattern | File |
|-----------|---------|------|
| `AppState` | `@MainActor ObservableObject` | Sources/AppState.swift:51 (final class) |
| `BackendManager` | Singleton pattern | Shared |
| `SubscriptionManager` | `final class ObservableObject` | Sources/SubscriptionManager.swift:7 |
| `LicenseManager` | ObservableObject | |

### Actors for Thread Safety

The app uses actors for ML/ASR services (good practice):

| Actor | File |
|-------|------|
| `MLXAnalysisEngine` | Sources/Analysis/MLXAnalysisEngine.swift |
| `SessionRAGStore` | Sources/BrainDump/SessionRAGStore.swift |
| `NativeMLXBackend` | Sources/ASR/NativeMLXBackend.swift |
| `ASRAudioCaptureIntegration` | Sources/ASR/ASRIntegration.swift |

### Concurrency Issues (Swift 6 Readiness)

1. **Critical Bug:** `MeetingListenerApp.swift:36`
   ```swift
   if requireLicenseValidation {
       Task {  // ERROR: escaping closure captures mutating 'self' parameter
           let hasValidLicense = await licenseManager.checkLicense()
   ```
   **Fix:** Store `requireLicenseValidation` in a local variable before the `if` block.

2. **`@escaping` closures with weak self** — Present but using proper `[weak self]` pattern in most places.

3. **No explicit `Sendable` conformance checks** — Actors exist but no `Sendable` audits visible.

---

## HIG Compliance

### Menu Bar App (macapp/MeetingListenerApp)

| Check | Status | Notes |
|-------|--------|-------|
| MenuBarExtra | ✅ | Uses SwiftUI `MenuBarExtra` |
| Status item | ✅ | Proper status item setup |
| Keyboard shortcuts | ⚠️ | Some custom shortcuts present, needs audit |
| Window management | ⚠️ | Uses `SidePanelController` (NSPanel) - custom implementation |

**Issues:**
- `SidePanelController.swift` uses custom `NSPanel` subclass — verify proper window delegate implementation
- No standard `Settings` scene (uses custom `SettingsView.swift:809`)

### macapp_v2 (New UI)

| Check | Status | Notes |
|-------|--------|-------|
| Window style | ⚠️ | `.windowStyle(.titleBar)` - minimal chrome |
| Liquid Glass | ❌ | No `.glassEffect()` found — uses legacy `.background(Material)` |
| Materials | ✅ | Uses `.background(Material.thinMaterial)` / `.regularMaterial` |
| Toolbar | ✅ | Proper SwiftUI `.toolbar` with `ToolbarItemGroup` |

**Issues:**
- **No Liquid Glass (macOS Tahoe):** v2 UI uses `Material.thinMaterial` instead of `.glassEffect()` for sidebars
- **Material usage in content areas:** `ReviewView.swift:66,114,162,190` uses `.background(Material.regularMaterial)` in dense content — violates HIG guidance that content areas should not be overly translucent

### Settings Window

| Check | Status | Notes |
|-------|--------|-------|
| Settings scene | ⚠️ | Uses custom window at line 207, not built-in `Settings {}` scene |
| UserDefaults | ✅ | Properly used for preferences |
| Keychain | ✅ | `KeychainHelper.swift` for secrets |

### Keyboard Shortcuts

- ✅ `⌘Q` quit shortcut present
- ✅ `⌘⇧R` for recording toggle
- ⚠️ No `⌘,` for Preferences (using custom settings window instead)

---

## Known Issues from Previous Audit

Based on this audit, the following previously-reported issues could not be verified against current code:

| Issue | Priority | Status | Notes |
|-------|----------|--------|-------|
| Skip button timing | High | ⚠️ Unknown | No v2-specific code found in macapp_v2 |
| Duration timer | Medium | ⚠️ Unknown | Duration displays exist in MenuBarView.swift:242 |
| Recent sessions | Low | ⚠️ Unknown | HistoryView.swift present but no "recent" specific code |

---

## Performance

### Memory

| Pattern | Status | File |
|---------|--------|------|
| Lazy initialization | ✅ | `AppState.swift:272,313,337,381` — audio/mic/voiceNote/diarization are lazy |
| Weak references | ✅ | Proper `[weak self]` in closures throughout |
| deinit cleanup | ✅ | `AudioCaptureManager.swift:100`, `MicrophoneCaptureManager.swift:43` etc. |

### Audio Processing

| Check | Status | Notes |
|-------|--------|-------|
| VAD enabled | ✅ | `SettingsView.swift:178-191` — VAD toggle and threshold |
| Thread safety | ⚠️ | Actors exist but audio pipeline thread safety not fully audited |
| Backpressure | ⚠️ | No visible backpressure handling in audio buffers |

### Metrics

| Metric | Value |
|--------|-------|
| macapp Swift files | 73 |
| macapp Lines of code | 26,876 |
| macapp_v2 Swift files | 19 |
| macapp_v2 Lines of code | 5,619 |
| macapp Release build | Completed (with warnings) |
| macapp_v2 Debug build | 0.35s |

---

## Swift 6 Concurrency Checklist

| Item | Status | Notes |
|------|--------|-------|
| async/await usage | ✅ | Actors and async throughout |
| @MainActor on UI | ✅ | AppState is @MainActor |
| Actor for shared state | ✅ | MLXAnalysisEngine, ASRAudioCaptureIntegration etc. |
| Sendable conformance | ⚠️ | Not explicitly checked |
| Task cancellation | ⚠️ | Not visible in audit |
| nonisolated usage | ⚠️ | `HotKeyManager.swift:92` has `nonisolated deinit` — necessary? |

---

## Recommendations

### High Priority

1. **Fix escape closure bug** — `MeetingListenerApp.swift:36`
   ```swift
   // Current (broken):
   if requireLicenseValidation {
       Task { ... }
   }
   
   // Fix:
   let needsValidation = requireLicenseValidation
   if needsValidation {
       Task { ... }
   }
   ```

2. **Update onChange modifiers** — Lines 59, 64 use deprecated signature
   ```swift
   // Current (deprecated):
   .onChange(of: showOnboarding) { newValue in ... }
   
   // Modern:
   .onChange(of: showOnboarding) { _, newValue in ... }
   ```

### Medium Priority

3. **Adopt Liquid Glass** for macapp_v2 sidebars (macOS Tahoe)
   - Replace `.background(Material.thinMaterial)` with `.glassEffect()`
   - Update in: `LiveView.swift:65`, `HistoryView.swift:35`, `ReviewView.swift:66`

4. **Use native Settings scene** instead of custom window
   ```swift
   Settings {
       SettingsView(appState: appState, backendManager: backendManager)
   }
   ```

5. **Add explicit Sendable conformance audits** — verify all types crossing concurrency boundaries

### Low Priority

6. **Add ⌘, keyboard shortcut** for Settings (standard macOS convention)

7. **Document audio pipeline backpressure strategy** — how does the app handle buffer overflow?

8. **Verify HotKeyManager deinit** — `nonisolated deinit` is unusual, confirm it's necessary

---

## Summary

| Category | Grade | Notes |
|----------|-------|-------|
| Build | ⚠️ B- | Completes but with 1 error + deprecation warnings |
| Architecture | ✅ B+ | Proper actor usage, MVVM, lazy loading |
| Concurrency | ⚠️ B- | Escape closure bug, needs Sendable audit |
| HIG Compliance | ⚠️ C+ | Missing Liquid Glass, non-standard Settings |
| Performance | ✅ A- | Lazy loading, weak refs, minimal footprint |
| macapp_v2 | ⚠️ B | Builds clean, uses legacy Materials instead of Liquid Glass |

---

*Audit complete. Next steps: Fix critical escape closure bug, update deprecated onChange, adopt Liquid Glass for Tahoe compatibility.*
