# macapp_v2 UI Integration Plan

**Ticket**: TCK-20260303-XXX  
**Type**: FEATURE  
**Status**: IN_PROGRESS  
**Owner**: Agent  

---

## Executive Summary

macapp_v2 is a visual prototype with sophisticated UX but **zero backend integration**. This document maps backend capabilities to v2 UI components and provides a phased integration path.

**Current State**: v2 uses mock timers and scripted data flows. No actual recording, transcription, or analysis occurs.

**Target State**: Full backend integration preserving v2's superior UX while leveraging production ASR, entity extraction, and card analysis.

---

## 1. Feature Gap Analysis

### 1.1 Backend Capabilities (Production-Ready)

| Feature | Backend Support | v1 Status | v2 Status | Gap Level |
|---------|----------------|-----------|-----------|-----------|
| **WebSocket Streaming** | ✅ Full | ✅ Integrated | ❌ None | P0 |
| **ASR Transcription** | ✅ Whisper streaming | ✅ Working | ❌ Mock only | P0 |
| **Speaker Diarization** | ✅ Optional | ✅ Working | ❌ No UI | P1 |
| **Entity Extraction** | ✅ person/org/project/topic/place/date | ✅ Working | ❌ No UI | P1 |
| **Action Cards** | ✅ Extraction + confidence | ✅ Working | ✅ Mock only | P0 |
| **Decision Cards** | ✅ Extraction + confidence | ✅ Working | ✅ Mock only | P0 |
| **Risk Cards** | ✅ Extraction + confidence | ✅ Working | ❌ Not in UI | P2 |
| **Voice Notes** | ✅ Full pipeline | ✅ Working | ❌ No UI | P2 |
| **Dual Audio Capture** | ✅ system + mic | ✅ Working | ❌ Not implemented | P0 |
| **Session Persistence** | ✅ SQLite storage | ✅ Working | ❌ Mock only | P1 |
| **Context Documents** | ✅ RAG query | ✅ Working | ❌ No UI | P2 |
| **Flow Studio** | ❌ N/A (v2 only) | N/A | ✅ Mock only | P3 |

### 1.2 Data Model Comparison

#### v1 Models (Backend-Driven)
```swift
// TranscriptSegment - matches ASR output exactly
struct TranscriptSegment {
    let text: String
    let t0: TimeInterval      // precise timing
    let t1: TimeInterval
    let isFinal: Bool         // streaming partial/final
    let confidence: Double
    var source: String?       // "system" | "mic"
    var speaker: String?      // diarization
}

// Cards with confidence scores
struct ActionItem {
    let text: String
    let owner: String?
    let due: String?
    let confidence: Double    // backend-provided
}

struct DecisionItem {
    let text: String
    let confidence: Double
}

struct RiskItem {
    let text: String
    let confidence: Double
}

// Entity extraction
struct EntityItem {
    let name: String
    let type: String        // person/org/project/topic/place/date
    let count: Int
    let lastSeen: TimeInterval
    let confidence: Double
}
```

#### v2 Models (UI-Optimized)
```swift
// TranscriptItem - simplified for display
struct TranscriptItem: Identifiable {
    let id: UUID
    let speaker: String      // required (not optional)
    let text: String
    let timestamp: Date      // absolute time
    let isPinned: Bool       // UI state only
    var actionItem: ActionItem?  // embedded (not separate)
}

// Simplified ActionItem (no confidence, no due date)
struct ActionItem: Identifiable {
    let id: UUID
    let assignee: String     // renamed from owner
    let task: String         // renamed from text
    let isCompleted: Bool    // UI state only
}

// Highlight - unified card concept
enum HighlightType: String, CaseIterable {
    case decision
    case action
    case keyPoint          // v2 addition (not in v1)
    case question          // v2 addition (not in v1)
}

struct Highlight: Identifiable {
    let id: UUID
    let type: HighlightType
    let content: String
    let timestamp: Date
}

// Person - derived view
struct Person: Identifiable {
    let id: UUID
    let name: String
    let mentionCount: Int
    let topics: [String]     // v2 addition
}
```

### 1.3 Mapping Strategy

| Backend Data | v2 UI Component | Mapping |
|--------------|-----------------|---------|
| `TranscriptSegment` | `TranscriptItem` | Convert t0/t1 → Date, group by speaker |
| `ActionItem` | `Highlight(.action)` | Map owner→assignee, text→content |
| `DecisionItem` | `Highlight(.decision)` | Map text→content |
| `RiskItem` | `Highlight(.keyPoint)` OR new `.risk` type | Add to UI or map to keyPoint |
| `EntityItem` | `Person` + topics | Aggregate by name, derive topics |
| Speaker diarization | Speaker labels | Use as-is in transcript |

---

## 2. UI Component Inventory

### 2.1 Existing v2 Components (Ready for Integration)

```
macapp_v2/Sources/
├── ContentView.swift           # Main container (2-pane layout)
├── PanelContainerView.swift    # Tab switcher (Live/Review)
├── LiveView.swift              # Recording panel with tabs
├── HighlightsView.swift        # Card grid display
├── TranscriptView.swift        # Scrollable transcript
├── PeopleView.swift            # People + topics grid
├── ReviewView.swift            # Session list + detail
├── SessionDetailView.swift     # Read-only session view
├── SettingsView.swift          # @AppStorage settings
├── FlowPickerView.swift        # Flow Studio selection
└── AppState.swift              # Central state (mock-only)
```

### 2.2 Missing Components (Need Creation)

| Component | Purpose | Priority |
|-----------|---------|----------|
| `AudioCaptureManager` | System audio + mic capture | P0 |
| `WebSocketStreamer` | Port from v1 with v2 callbacks | P0 |
| `RecordingService` | Orchestrate capture → stream | P0 |
| `BackendSyncAdapter` | Map backend → v2 models | P0 |
| `EntityHighlightView` | Show entities in transcript | P1 |
| `VoiceNoteRecorder` | Quick capture UI | P2 |
| `SessionStore` | Persist sessions to disk | P1 |

---

## 3. Integration Architecture

### 3.1 Target State Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       v2 UI Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  LiveView    │  │  ReviewView  │  │  Settings    │      │
│  │  (3 tabs)    │  │  (session    │  │  (flows)     │      │
│  └──────┬───────┘  │   list)      │  └──────────────┘      │
│         │          └──────────────┘                         │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              AppState (@MainActor)                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │  sessions   │  │ liveTranscript │ │ livePeople │ │   │
│  │  │ highlights  │  │ recordingState │ │ activeFlow │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  └────────────────────┬────────────────────────────────┘   │
│                       │                                     │
└───────────────────────┼─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                    Service Layer                            │
│  ┌─────────────────┐    ┌──────────────────────────────┐   │
│  │ RecordingService│◄──►│    BackendSyncAdapter        │   │
│  │                 │    │  (maps backend → v2 models)   │   │
│  └────────┬────────┘    └──────────────────────────────┘   │
│           │                                                 │
│  ┌────────▼────────┐    ┌──────────────────────────────┐   │
│  │ AudioCaptureMgr │    │   WebSocketStreamer (v1)     │   │
│  │  ├─ SystemAudio │    │   (with v2 callbacks)        │   │
│  │  └─ Microphone  │    │                              │   │
│  └─────────────────┘    └──────────────┬───────────────┘   │
│                                         │                   │
└─────────────────────────────────────────┼───────────────────┘
                                          │
                                          ▼ WebSocket
┌─────────────────────────────────────────────────────────────┐
│                    Python Backend                           │
│  ASR → Entity Extraction → Cards → Session Storage          │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow

```
1. User clicks "Start Recording"
   │
   ▼
2. RecordingService.start()
   ├─► AudioCaptureManager.start() ──► Capture audio frames
   ├─► WebSocketStreamer.connect() ──► WebSocket handshake
   └─► Send "start" message with config
   │
   ▼
3. Audio frames flow:
   AudioCaptureManager ──► WebSocketStreamer.sendPCMFrame()
   │
   ▼
4. Backend processes:
   ASR ──► Entities ──► Cards ──► WebSocket messages
   │
   ▼
5. WebSocketStreamer callbacks:
   onASRFinal ────────► BackendSyncAdapter.addTranscript()
   onEntitiesUpdate ──► BackendSyncAdapter.updatePeople()
   onCardsUpdate ─────► BackendSyncAdapter.updateHighlights()
   │
   ▼
6. AppState updates @Published properties ──► UI auto-refreshes
```

---

## 4. Phased Implementation Plan

### Phase 1: Foundation (P0) — Core Recording Pipeline
**Goal**: Make v2 actually record and transcribe

| Task | File(s) | Description |
|------|---------|-------------|
| 1.1 | `Services/AudioCaptureManager.swift` | Port from v1 (system + mic capture) |
| 1.2 | `Services/WebSocketStreamer.swift` | Port from v1 with v2-friendly callbacks |
| 1.3 | `Services/RecordingService.swift` | Orchestrate capture + streaming |
| 1.4 | `Services/BackendSyncAdapter.swift` | Map backend messages → v2 models |
| 1.5 | `AppState.swift` | Replace mock recording with real RecordingService |
| 1.6 | `LiveView.swift` | Show connection status, not just mock timer |

**Acceptance Criteria**:
- [ ] Clicking "Start Recording" captures real audio
- [ ] Transcript appears from actual ASR (not mock script)
- [ ] Highlights populate from backend cards
- [ ] Session saves to disk on stop

### Phase 2: Feature Parity (P1) — Match v1 Capabilities
**Goal**: v2 has all v1 features with better UX

| Task | File(s) | Description |
|------|---------|-------------|
| 2.1 | `Models/TranscriptItem.swift` | Add `confidence`, `isFinal`, `source` fields |
| 2.2 | `Views/TranscriptView.swift` | Show confidence dots, source indicators |
| 2.3 | `Services/SpeakerDiarizationAdapter.swift` | Integrate speaker labels |
| 2.4 | `Views/PeopleView.swift` | Add entity type badges |
| 2.5 | `Services/SessionStore.swift` | Persist sessions to SQLite (v1 logic) |
| 2.6 | `ReviewView.swift` | Load real sessions from SessionStore |

### Phase 3: Differentiation (P2) — v2-Only Features
**Goal**: Leverage unique v2 capabilities

| Task | File(s) | Description |
|------|---------|-------------|
| 3.1 | `Views/VoiceNoteView.swift` | Quick capture UI (not in v1) |
| 3.2 | `Models/Highlight.swift` | Add `.risk` type to enum |
| 3.3 | `Views/HighlightsView.swift` | Risk card styling |
| 3.4 | `Services/ContextQueryService.swift` | Integrate slide_query backend |
| 3.5 | `Views/ContextPanelView.swift` | Show related documents |

### Phase 4: Flow Studio Production (P3) — Mock → Real
**Goal**: Make Flow Studio use real data

| Task | File(s) | Description |
|------|---------|-------------|
| 4.1 | `Services/FlowReplayer.swift` | Replay real sessions as "flows" |
| 4.2 | `AppState.swift` | Use FlowReplayer for demo mode |
| 4.3 | `Views/FlowPickerView.swift` | Show user's past sessions as flows |

---

## 5. Detailed Component Specs

### 5.1 BackendSyncAdapter

**Purpose**: Transform backend messages into v2 UI models

```swift
@MainActor
final class BackendSyncAdapter {
    private weak var appState: AppState?
    
    // Called by WebSocketStreamer.onASRFinal
    func addTranscript(text: String, t0: TimeInterval, t1: TimeInterval, 
                       confidence: Double, speaker: String?) {
        let item = TranscriptItem(
            id: UUID(),
            speaker: speaker ?? "Unknown",
            text: text,
            timestamp: Date(timeIntervalSince1970: t0),
            isPinned: false  // UI state, default false
        )
        appState?.liveTranscript.append(item)
    }
    
    // Called by WebSocketStreamer.onCardsUpdate
    func updateHighlights(actions: [ActionItem], decisions: [DecisionItem], 
                          risks: [RiskItem]) {
        var highlights: [Highlight] = []
        
        // Map ActionItem → Highlight(.action)
        highlights += actions.map { action in
            Highlight(
                id: UUID(),
                type: .action,
                content: "\(action.owner ?? "Someone"): \(action.text)",
                timestamp: Date()
            )
        }
        
        // Map DecisionItem → Highlight(.decision)
        highlights += decisions.map { decision in
            Highlight(
                id: UUID(),
                type: .decision,
                content: decision.text,
                timestamp: Date()
            )
        }
        
        // Map RiskItem → Highlight(.keyPoint) or new .risk
        highlights += risks.map { risk in
            Highlight(
                id: UUID(),
                type: .keyPoint,  // Could add .risk type
                content: "⚠️ \(risk.text)",
                timestamp: Date()
            )
        }
        
        appState?.liveHighlights = highlights
    }
    
    // Called by WebSocketStreamer.onEntitiesUpdate
    func updatePeople(entities: [EntityItem]) {
        // Aggregate person entities, count mentions
        let personEntities = entities.filter { $0.type == "person" }
        
        let people = personEntities.map { entity in
            Person(
                id: UUID(),
                name: entity.name,
                mentionCount: entity.count,
                topics: deriveTopics(for: entity.name, from: entities)
            )
        }
        
        appState?.livePeople = people.sorted { $0.mentionCount > $1.mentionCount }
    }
    
    private func deriveTopics(for person: String, from entities: [EntityItem]) -> [String] {
        // Find topic entities that appear near this person
        // Simplified: return top topic entities
        entities
            .filter { $0.type == "topic" }
            .prefix(3)
            .map { $0.name }
    }
}
```

### 5.2 RecordingService

**Purpose**: Orchestrate audio capture and WebSocket streaming

```swift
@MainActor
final class RecordingService: ObservableObject {
    @Published var state: RecordingState = .idle
    
    private let audioCapture: AudioCaptureManager
    private let webSocket: WebSocketStreamer
    private let syncAdapter: BackendSyncAdapter
    
    func startRecording(flow: MockFlowTrack? = nil) async {
        state = .starting
        
        do {
            // 1. Connect WebSocket first
            try await webSocket.connect()
            
            // 2. Start audio capture
            audioCapture.onAudioFrame = { [weak self] data, source in
                self?.webSocket.sendPCMFrame(data, source: source)
            }
            try audioCapture.start()
            
            // 3. Send start message with config
            let config: [String: Any] = [
                "type": "start",
                "session_title": flow?.title ?? "Quick Capture",
                "audio_format": "pcm_s16le_16khz",
                "enable_diarization": false
            ]
            webSocket.sendJSON(config)
            
            state = .recording(duration: 0)
            startDurationTimer()
            
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    func stopRecording() async {
        state = .finalizing
        
        audioCapture.stop()
        await webSocket.disconnect()
        
        // Save session to SessionStore
        // ...
        
        state = .idle
    }
}
```

---

## 6. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| v1 WebSocketStreamer too coupled to v1 | Medium | High | Create protocol abstraction layer |
| Data model mismatch causes UI bugs | High | Medium | Extensive mapping unit tests |
| Flow Studio logic conflicts with real data | Medium | Medium | Keep Flow Studio as separate mode |
| Performance: v2 UI slower with real data | Low | High | Profile early, use diffable collections |
| User confusion: where did mock data go? | Medium | Low | Add "Demo Mode" toggle in settings |

---

## 7. Testing Strategy

### 7.1 Unit Tests

```swift
// BackendSyncAdapterTests.swift
func testActionItemMapping() {
    let backendAction = ActionItem(
        text: "Test action",
        owner: "John",
        due: nil,
        confidence: 0.95
    )
    
    let highlight = adapter.mapAction(backendAction)
    
    XCTAssertEqual(highlight.type, .action)
    XCTAssertEqual(highlight.content, "John: Test action")
}

func testEntityToPeopleMapping() {
    let entities = [
        EntityItem(name: "Alice", type: "person", count: 5, lastSeen: 0, confidence: 0.9),
        EntityItem(name: "Project X", type: "project", count: 3, lastSeen: 0, confidence: 0.8)
    ]
    
    let people = adapter.mapEntitiesToPeople(entities)
    
    XCTAssertEqual(people.count, 1)  // Only person type
    XCTAssertEqual(people[0].name, "Alice")
}
```

### 7.2 Integration Tests

- Start recording → verify transcript appears within 5 seconds
- Speak test phrase → verify correct text appears
- Verify highlights populate within 30 seconds
- Stop recording → verify session saved to disk

### 7.3 UI Tests

- Tab switching works during active recording
- Always-on-top toggle persists
- Settings changes apply to next recording

---

## 8. Migration Path from v1

**For existing v1 users upgrading to v2:**

1. **Session History**: v1 SQLite sessions can be imported via SessionStore
2. **Settings**: Key settings (API endpoint, audio device) preserved
3. **Shortcuts**: Hotkey system will be ported

**Backward Compatibility**:
- v2 does not replace v1 initially
- Both apps can coexist
- v1 continues to receive critical fixes

---

## 9. Evidence Log

### Completed Analysis

| Date | Activity | Result |
|------|----------|--------|
| 2026-03-03 | Audited macapp_v2 source | Identified 8 Swift files, all mock-only |
| 2026-03-03 | Compared v1/v2 data models | Mapping strategy defined |
| 2026-03-03 | Reviewed backend message types | 8 message types to handle |
| 2026-03-03 | Created integration plan | This document |

### Next Steps

1. **Ticket Creation**: Create TCK-20260303-009 for Phase 1 implementation
2. **Architecture Review**: Get approval on service layer design
3. **Begin Implementation**: Start with RecordingService + BackendSyncAdapter

---

## Appendix: Backend Message Reference

### Incoming Messages (Backend → Frontend)

| Type | Payload | Frequency | Handler |
|------|---------|-----------|---------|
| `status` | state, message | Event | Update connection UI |
| `asr_partial` | text, t0, t1 | Realtime | (Optional) Show live typing |
| `asr_final` | text, t0, t1, confidence, speaker | Per utterance | Add to transcript |
| `entities_update` | entities[] | ~12s | Update people/topics |
| `cards_update` | actions[], decisions[], risks[] | ~28s | Update highlights |
| `voice_note_transcript` | text, confidence | Per voice note | Show notification |
| `final_summary` | summary text | Session end | Show in review |

### Outgoing Messages (Frontend → Backend)

| Type | Payload | When |
|------|---------|------|
| `start` | session_title, config | Recording start |
| `pcm_chunk` | binary audio data | Continuous |
| `voice_note_start` | timestamp | User triggers |
| `voice_note_chunk` | binary audio data | During voice note |
| `voice_note_end` | - | User ends |

---

*Document Version: 1.0*  
*Last Updated: 2026-03-03*  
*Review Cycle: Weekly during implementation*
