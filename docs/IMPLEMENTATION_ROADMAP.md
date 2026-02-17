# EchoPanel Hybrid Backend - Implementation Roadmap

**Date:** 2026-02-14  
**Goal:** Complete integration of hybrid ASR architecture  
**Estimated Duration:** 1-2 weeks

---

## Phase 1: Dependency Setup (Day 1)

### Task 1.1: Add MLX Audio Swift Package
- [ ] Check current Package.swift
- [ ] Add mlx-audio-swift dependency
- [ ] Resolve dependencies
- [ ] Verify build succeeds

### Task 1.2: Update Project Structure
- [ ] Create ASR module directory
- [ ] Move existing files if needed
- [ ] Update imports

---

## Phase 2: Native Backend Implementation (Days 2-3)

### Task 2.1: Implement NativeMLXBackend
- [ ] Import MLXAudioSTT
- [ ] Implement model loading
- [ ] Implement transcribe() method
- [ ] Implement transcribeStream() method
- [ ] Add audio format conversion

### Task 2.2: Model Management
- [ ] Create model download UI
- [ ] Implement model caching
- [ ] Add model switching
- [ ] Handle model loading errors

### Task 2.3: Audio Conversion
- [ ] Convert PCM to MLXArray
- [ ] Handle sample rate conversion
- [ ] Support different bit depths

---

## Phase 3: Python Backend Wrapper (Days 4-5)

### Task 3.1: Create PythonBackend
- [ ] Wrap existing WebSocketStreamer
- [ ] Implement ASRBackend protocol
- [ ] Handle connection states
- [ ] Add reconnection logic

### Task 3.2: Integrate with Existing Code
- [ ] Replace direct WebSocket usage
- [ ] Maintain backward compatibility
- [ ] Add migration path

---

## Phase 4: UI Integration (Days 6-7)

### Task 4.1: Settings Integration
- [ ] Add BackendSelectionView to Settings
- [ ] Show current backend status
- [ ] Add backend switcher in menu bar

### Task 4.2: Main UI Updates
- [ ] Show backend indicator in main window
- [ ] Add backend status to transcription view
- [ ] Show upgrade prompts when needed

### Task 4.3: Onboarding
- [ ] Add backend selection to onboarding
- [ ] Explain differences
- [ ] Recommend based on use case

---

## Phase 5: Integration with Audio Capture (Days 8-9)

### Task 5.1: Connect to AudioCaptureManager
- [ ] Inject HybridASRManager
- [ ] Route audio to selected backend
- [ ] Handle streaming audio

### Task 5.2: Real-time Transcription
- [ ] Implement streaming pipeline
- [ ] Handle partial results
- [ ] Show transcription progress

### Task 5.3: Fallback Handling
- [ ] Detect backend failures
- [ ] Automatic fallback
- [ ] User notification

---

## Phase 6: Feature Flags & Testing (Days 10-12)

### Task 6.1: Feature Flags
- [ ] Add FeatureFlagManager
- [ ] Create flags for hybrid backend
- [ ] Enable gradual rollout

### Task 6.2: Testing
- [ ] Unit tests for HybridASRManager
- [ ] Integration tests
- [ ] Backend comparison tests
- [ ] Performance benchmarks

### Task 6.3: Debug Tools
- [ ] Add backend comparison view
- [ ] Show performance metrics
- [ ] Export comparison results

---

## Phase 7: Documentation & Polish (Days 13-14)

### Task 7.1: Documentation
- [ ] Update user documentation
- [ ] Add backend selection guide
- [ ] Document troubleshooting

### Task 7.2: Error Handling
- [ ] Improve error messages
- [ ] Add recovery flows
- [ ] Log diagnostics

### Task 7.3: Polish
- [ ] UI animations
- [ ] Loading states
- [ ] Success/error feedback

---

## Detailed Task Breakdown

### Day 1: Dependency Setup

```bash
# Check current Package.swift
cat macapp/MeetingListenerApp/Package.swift

# Add MLX Audio Swift
# Edit Package.swift to add:
# .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.2.0")

# Build to verify
swift build
```

### Day 2-3: Native Backend

```swift
// Implement in NativeMLXBackend.swift:

import MLXAudioSTT
import MLXAudioCore

func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
    // 1. Convert audio format
    let audioArray = try convertToMLXArray(audio)
    
    // 2. Load model if needed
    if asrModel == nil {
        try await loadModel(preferredModel)
    }
    
    // 3. Transcribe
    let output = asrModel.generate(audio: audioArray)
    
    // 4. Convert to Transcription struct
    return Transcription(
        text: output.text,
        backend: name
    )
}
```

### Day 4-5: Python Backend

```swift
// Create PythonBackend.swift:

class PythonBackend: ASRBackend {
    private let webSocket: WebSocketStreamer
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
        // Use existing WebSocket connection
        return try await webSocket.transcribe(audio: audio, config: config)
    }
}
```

### Day 6-7: UI Integration

```swift
// Add to SettingsView.swift:

Section("Transcription Backend") {
    BackendSelectionView(asrManager: asrManager)
}

// Add to main window:
ToolbarItem {
    BackendStatusIndicator(backend: asrManager.currentBackend)
}
```

### Day 8-9: Audio Capture Integration

```swift
// Update AudioCaptureManager:

class AudioCaptureManager {
    var hybridASR: HybridASRManager?
    
    func processAudio(_ data: Data) {
        Task {
            let config = TranscriptionConfig(...)
            let result = try await hybridASR?.transcribe(
                audio: data,
                config: config
            )
        }
    }
}
```

### Day 10-12: Testing

```swift
// Create test file:

class HybridASRTests: XCTestCase {
    func testBackendSelection() async {
        // Test auto-selection logic
    }
    
    func testFallback() async {
        // Test fallback when primary fails
    }
    
    func testComparison() async {
        // Test dual mode comparison
    }
}
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| MLX Audio Swift not available | Keep stub, use Python only |
| Build failures | Feature flag to disable |
| Performance issues | A/B test before rollout |
| User confusion | Clear UI + documentation |

---

## Success Criteria

- [ ] Both backends functional
- [ ] Auto-selection works correctly
- [ ] UI integrated and intuitive
- [ ] Tests passing
- [ ] Documentation complete
- [ ] Beta users happy

---

## Resources Needed

- MLX Audio Swift package access
- Test audio files
- Beta user group
- Performance profiling tools
