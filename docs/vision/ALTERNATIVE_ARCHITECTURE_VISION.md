# Alternative Architecture Vision: EchoPanel Reimagined

**Author:** Apple Developer Expert  
**Date:** 2026-02-09  
**Context:** How I would design EchoPanel from scratch

---

## Core Philosophy

> "Views should be thin, state should be observable, and business logic should be testable."

The current architecture (even after refactoring) puts too much in the view layer. My approach separates concerns aggressively using modern SwiftUI patterns.

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      EchoPanel Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   RollView   │  │ CompactView  │  │   FullView   │          │
│  │   (150 lines)│  │   (150 lines)│  │   (300 lines)│          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                 │
│         └──────────────────┼──────────────────┘                 │
│                            │                                    │
│              ┌─────────────▼─────────────┐                     │
│              │  TranscriptList (shared)  │                     │
│              │  SurfacePanel (shared)    │                     │
│              │  CaptureToolbar (shared)  │                     │
│              └─────────────┬─────────────┘                     │
│                            │                                    │
│         ┌──────────────────┼──────────────────┐                │
│         ▼                  ▼                  ▼                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ @Observable  │  │ @Observable  │  │ @Observable  │          │
│  │PanelState    │  │TranscriptState│  │ CaptureState │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                 │
│         └──────────────────┼──────────────────┘                 │
│                            │                                    │
│              ┌─────────────▼─────────────┐                     │
│              │     SessionService        │                     │
│              │     (protocol-based)      │                     │
│              └─────────────┬─────────────┘                     │
│                            │                                    │
│         ┌──────────────────┼──────────────────┐                │
│         ▼                  ▼                  ▼                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ASRService    │  │AudioCapture  │  │WebSocket     │          │
│  │LiveTranscript│  │Service       │  │Service       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. State Management: @Observable (iOS 17/macOS 14+)

Instead of `@StateObject` and `@ObservedObject`, I'd use the new `@Observable` macro:

```swift
// MARK: - Panel State

@Observable
final class PanelState {
    var viewMode: ViewMode = .roll
    var isSurfaceOverlayVisible = false
    var activeSurface: Surface = .summary
    
    // Keyboard shortcuts
    var showShortcutHelp = false
    
    // Dependencies (injected)
    private let transcriptState: TranscriptState
    private let captureState: CaptureState
    
    init(transcriptState: TranscriptState, captureState: CaptureState) {
        self.transcriptState = transcriptState
        self.captureState = captureState
    }
}

// MARK: - Transcript State

@Observable
final class TranscriptState {
    private(set) var segments: [TranscriptSegment] = []
    private(set) var filteredSegments: [TranscriptSegment] = []
    
    var focusedSegmentID: UUID?
    var lensSegmentID: UUID?
    var pinnedSegmentIDs: Set<UUID> = []
    var followLive = true
    
    // Search/filter
    var searchQuery = "" {
        didSet { updateFilteredSegments() }
    }
    
    var entityFilter: EntityItem? {
        didSet { updateFilteredSegments() }
    }
    
    // Derived state (computed once, not on every view access)
    private func updateFilteredSegments() {
        var result = segments
        
        if let filter = entityFilter {
            result = result.filter { segment in
                EntityHighlighter.matches(in: segment.text, entities: [filter], mode: .extracted).isEmpty == false
            }
        }
        
        if !searchQuery.isEmpty {
            let lowered = searchQuery.lowercased()
            result = result.filter { 
                $0.text.lowercased().contains(lowered) 
            }
        }
        
        filteredSegments = result
    }
    
    func appendSegment(_ segment: TranscriptSegment) {
        segments.append(segment)
        if followLive {
            focusedSegmentID = segment.id
        }
        updateFilteredSegments()
    }
}

// MARK: - Capture State

@Observable
final class CaptureState {
    var audioSource: AudioSource = .both
    var systemLevel: Float = 0
    var microphoneLevel: Float = 0
    var quality: AudioQuality = .unknown
    
    var permissionStatus: PermissionStatus = .unknown
    
    enum PermissionStatus {
        case unknown
        case granted
        case denied(permission: PermissionType)
        
        enum PermissionType {
            case screenRecording
            case microphone
        }
    }
}
```

### Why This Is Better

| Aspect | Current (@StateObject) | My Approach (@Observable)
|--------|------------------------|---------------------------
| Granularity | Whole object invalidates | Property-level tracking
| Syntax | `@StateObject var x = X()` | `@State var x = X()`
| Performance | Coarse | Fine-grained
| Dependencies | Manual | Automatic via init

---

## 3. View Layer: Protocol-Oriented Components

### 3.1 View Protocols

```swift
// MARK: - View Protocols

protocol TranscriptPresenting {
    var segments: [TranscriptSegment] { get }
    var focusedSegmentID: UUID? { get set }
    var lensSegmentID: UUID? { get set }
}

protocol SurfacePresenting {
    var activeSurface: Surface { get set }
    var isOverlayVisible: Bool { get set }
}

// MARK: - Mode-Specific Views

struct RollView: View {
    @State private var state: PanelState
    
    var body: some View {
        VStack(spacing: Design.Spacing.standard) {
            RollChrome(state: state)
            
            ZStack {
                TranscriptList(
                    segments: state.transcriptState.visibleSegments,
                    focusedID: $state.transcriptState.focusedSegmentID,
                    style: .roll
                )
                
                if state.isSurfaceOverlayVisible {
                    SurfaceOverlay(
                        surface: state.activeSurface,
                        onClose: { state.isSurfaceOverlayVisible = false }
                    )
                }
            }
            
            RollFooter(state: state)
        }
    }
}

struct FullView: View {
    @State private var state: PanelState
    
    var body: some View {
        HStack(spacing: Design.Spacing.standard) {
            SessionRail(state: state)
            
            VStack(spacing: Design.Spacing.standard) {
                FullChrome(state: state)
                
                TranscriptList(
                    segments: state.transcriptState.visibleSegments,
                    focusedID: $state.transcriptState.focusedSegmentID,
                    style: .full
                )
                
                TimelineScrubber(state: state)
            }
            
            PersistentSurfacePanel(state: state)
        }
    }
}
```

### 3.2 Shared Components

```swift
// MARK: - Transcript List

struct TranscriptList: View {
    let segments: [TranscriptSegment]
    @Binding var focusedID: UUID?
    let style: TranscriptStyle
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: style.rowSpacing) {
                    ForEach(segments) { segment in
                        TranscriptLine(
                            segment: segment,
                            isFocused: segment.id == focusedID,
                            onTap: { focusedID = segment.id }
                        )
                        .id(segment.id)
                    }
                }
                .padding(style.padding)
            }
            .onChange(of: focusedID) { _, newID in
                if let newID {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Transcript Line

struct TranscriptLine: View {
    let segment: TranscriptSegment
    let isFocused: Bool
    let onTap: () -> Void
    
    @Environment(TranscriptState.self) private var transcriptState
    
    var body: some View {
        HStack(spacing: Design.Spacing.tight) {
            TimestampView(time: segment.t0)
            SpeakerBadge(source: segment.source, speaker: segment.speaker)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .font(Design.Fonts.body)
                
                ConfidenceBadge(value: segment.confidence)
            }
            
            if isFocused {
                FocusActions(
                    onPin: { transcriptState.togglePin(segment.id) },
                    onLens: { transcriptState.toggleLens(segment.id) }
                )
            }
        }
        .padding(Design.Spacing.tight)
        .background(isFocused ? Design.Colors.focusedBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.small))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(segment.speaker ?? "Unknown") at \(formatTime(segment.t0)): \(segment.text)")
        .accessibilityAddTraits(.isButton)
    }
}
```

---

## 4. Service Layer: Protocol-Oriented Architecture

### 4.1 Service Protocols

```swift
// MARK: - ASR Service

protocol ASRServiceProtocol: Sendable {
    var transcriptStream: AsyncStream<TranscriptEvent> { get }
    
    func startSession() async throws
    func stopSession() async
    func sendAudio(_ buffer: AVAudioPCMBuffer, source: AudioSource) async
}

enum TranscriptEvent {
    case partial(TranscriptSegment)
    case final(TranscriptSegment)
    case error(Error)
}

// MARK: - Audio Capture Service

protocol AudioCaptureServiceProtocol: Sendable {
    var levelStream: AsyncStream<Float> { get }
    var permissionStatus: PermissionStatus { get async }
    
    func requestPermission() async -> Bool
    func startCapturing(source: AudioSource) async throws
    func stopCapturing() async
}

// MARK: - Session Service

protocol SessionServiceProtocol {
    func saveSession(_ session: Session) async throws
    func loadSessions() async throws -> [Session]
    func deleteSession(id: String) async throws
}
```

### 4.2 Service Implementations

```swift
// MARK: - Live ASR Service

actor LiveASRService: ASRServiceProtocol {
    private var webSocketTask: URLSessionWebSocketTask?
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    
    var transcriptStream: AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }
    
    func startSession() async throws {
        // Implementation
    }
    
    func stopSession() async {
        webSocketTask?.cancel()
    }
    
    func sendAudio(_ buffer: AVAudioPCMBuffer, source: AudioSource) async {
        // Convert and send
    }
}

// MARK: - Mock ASR Service (for previews/testing)

actor MockASRService: ASRServiceProtocol {
    var transcriptStream: AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            // Emit mock data
            Task {
                try? await Task.sleep(for: .seconds(1))
                continuation.yield(.final(TranscriptSegment.mock))
                continuation.finish()
            }
        }
    }
    
    func startSession() async throws {}
    func stopSession() async {}
    func sendAudio(_ buffer: AVAudioPCMBuffer, source: AudioSource) async {}
}
```

---

## 5. Dependency Injection

```swift
// MARK: - Dependency Container

@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    let asrService: ASRServiceProtocol
    let audioCaptureService: AudioCaptureServiceProtocol
    let sessionService: SessionServiceProtocol
    
    private init(
        asrService: ASRServiceProtocol = LiveASRService(),
        audioCaptureService: AudioCaptureServiceProtocol = AudioCaptureService(),
        sessionService: SessionServiceProtocol = LocalSessionService()
    ) {
        self.asrService = asrService
        self.audioCaptureService = audioCaptureService
        self.sessionService = sessionService
    }
    
    // For previews/testing
    static func mock() -> DependencyContainer {
        DependencyContainer(
            asrService: MockASRService(),
            audioCaptureService: MockAudioCaptureService(),
            sessionService: MockSessionService()
        )
    }
}

// MARK: - SwiftUI Integration

struct ContentView: View {
    @State private var state: PanelState
    
    init(container: DependencyContainer = .shared) {
        let transcriptState = TranscriptState(asrService: container.asrService)
        let captureState = CaptureState(audioService: container.audioCaptureService)
        _state = State(wrappedValue: PanelState(
            transcriptState: transcriptState,
            captureState: captureState
        ))
    }
    
    var body: some View {
        Group {
            switch state.viewMode {
            case .roll: RollView(state: state)
            case .compact: CompactView(state: state)
            case .full: FullView(state: state)
            }
        }
        .environment(state.transcriptState)
        .environment(state.captureState)
    }
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

```swift
@Test
func testTranscriptStateFiltering() async {
    let state = TranscriptState()
    state.segments = [
        TranscriptSegment(text: "Hello world", t0: 0, t1: 1, isFinal: true, confidence: 0.9),
        TranscriptSegment(text: "Goodbye world", t0: 1, t1: 2, isFinal: true, confidence: 0.9)
    ]
    
    state.searchQuery = "Hello"
    
    #expect(state.filteredSegments.count == 1)
    #expect(state.filteredSegments.first?.text == "Hello world")
}

@Test
func testPanelStateViewModeTransitions() {
    let state = PanelState()
    
    #expect(state.viewMode == .roll)
    
    state.viewMode = .full
    #expect(state.isSurfaceOverlayVisible == false) // Auto-close overlay in full
}
```

### 6.2 UI Tests

```swift
@MainActor
struct SidePanelUITests {
    @Test
    func testKeyboardNavigation() async throws {
        let app = XCUIApplication()
        app.launch()
        
        // Start session
        app.menuBars.statusItems["EchoPanel"].tap()
        app.buttons["Start Listening"].tap()
        
        // Test arrow key navigation
        app.keyboards.keys["up"].tap()
        // Verify focus changed
    }
}
```

---

## 7. File Organization

```
Sources/
├── App/
│   ├── EchoPanelApp.swift           # App entry
│   └── DependencyContainer.swift    # DI setup
│
├── State/                           # @Observable classes
│   ├── PanelState.swift             # Main panel state
│   ├── TranscriptState.swift        # Transcript + focus
│   ├── CaptureState.swift           # Audio capture
│   └── ViewModels/                  # Derived state
│       └── SessionViewModel.swift
│
├── Views/
│   ├── Modes/
│   │   ├── RollView.swift           # ~150 lines
│   │   ├── CompactView.swift        # ~150 lines
│   │   └── FullView.swift           # ~300 lines
│   │
│   ├── Components/
│   │   ├── Transcript/
│   │   │   ├── TranscriptList.swift
│   │   │   ├── TranscriptLine.swift
│   │   │   └── TranscriptLens.swift
│   │   │
│   │   ├── Surfaces/
│   │   │   ├── SurfaceOverlay.swift
│   │   │   ├── SurfacePanel.swift
│   │   │   └── SurfaceContent/
│   │   │       ├── SummarySurface.swift
│   │   │       ├── ActionsSurface.swift
│   │   │       └── EntitiesSurface.swift
│   │   │
│   │   └── Chrome/
│   │       ├── CaptureToolbar.swift
│   │       ├── StatusPill.swift
│   │       └── ModeSelector.swift
│   │
│   └── Shared/
│       ├── EmptyStateView.swift
│       ├── LoadingView.swift
│       └── ErrorView.swift
│
├── Services/                        # Protocols + Implementations
│   ├── ASR/
│   │   ├── ASRServiceProtocol.swift
│   │   ├── LiveASRService.swift
│   │   └── MockASRService.swift
│   │
│   ├── Audio/
│   │   ├── AudioCaptureProtocol.swift
│   │   ├── ScreenCaptureKitService.swift
│   │   └── MicrophoneService.swift
│   │
│   └── Storage/
│       ├── SessionServiceProtocol.swift
│       └── LocalSessionService.swift
│
├── Design/                          # Design system
│   ├── DesignTokens.swift           # Colors, spacing, fonts
│   ├── ViewModifiers/
│   │   ├── GlassModifier.swift
│   │   └── CardModifier.swift
│   └── Components/
│       ├── GlassCard.swift
│       └── IconButton.swift
│
├── Models/                          # Data types
│   ├── TranscriptSegment.swift
│   ├── ActionItem.swift
│   ├── DecisionItem.swift
│   └── EntityItem.swift
│
└── Utilities/
    ├── KeyboardHandler.swift
    ├── AccessibilityLabels.swift
    └── Formatters.swift
```

---

## 8. Key Differences Summary

| Aspect | Current Architecture | My Architecture |
|--------|---------------------|-----------------|
| **State** | `@State` in views, scattered | `@Observable` classes, centralized |
| **View Size** | SidePanelView: 2,738 lines | Largest view: ~300 lines |
| **Testing** | Hard to test (UI coupled) | Easy (protocol-based services) |
| **Previews** | Limited (needs full app) | Every component previewable |
| **Dependencies** | Global singletons | Injected via container |
| **Concurrency** | Closures, callbacks | async/await, AsyncStream |
| **Accessibility** | Manual labels | Automated + semantic |

---

## 9. Migration Path

If I were migrating the current codebase:

### Phase 1: Extract State (1-2 days)
1. Create `TranscriptState` @Observable class
2. Move transcript-related @State properties
3. Update views to use `@Environment`

### Phase 2: Extract Services (1-2 days)
1. Define `ASRServiceProtocol`
2. Wrap existing WebSocket in service
3. Inject into state

### Phase 3: Decompose Views (2-3 days)
1. Create component library
2. Extract TranscriptList, SurfacePanel
3. Simplify mode views

### Phase 4: Add Tests (1-2 days)
1. Unit tests for state classes
2. UI tests for navigation
3. Snapshot tests for components

---

## 10. Performance Wins

1. **LazyVStack** for transcripts (not VStack)
2. **Property-level observation** (not object-level)
3. **Memoized filtering** (computed once, not per-view)
4. **AsyncStream** for audio (no callback closures)
5. **Actor isolation** for services (thread-safe)

---

*This architecture prioritizes testability, maintainability, and SwiftUI best practices over rapid prototyping.*