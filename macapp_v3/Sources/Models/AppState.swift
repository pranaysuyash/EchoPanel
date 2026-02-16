import SwiftUI
import Combine

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording(duration: TimeInterval, startTime: Date)
    case paused(duration: TimeInterval, startTime: Date, pausedAt: Date)
    case error(String)
}

// MARK: - Audio Source

enum AudioSource: String, CaseIterable, Identifiable {
    case systemAndMic = "System + Microphone"
    case systemOnly = "System Audio Only"
    case micOnly = "Microphone Only"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .systemAndMic: return "speaker.wave.2.fill"
        case .systemOnly: return "speaker.wave.3.fill"
        case .micOnly: return "mic.fill"
        }
    }
    
    var description: String {
        switch self {
        case .systemAndMic: return "Capture meeting audio and your voice"
        case .systemOnly: return "Capture only meeting participants"
        case .micOnly: return "Capture only your microphone"
        }
    }
}

// MARK: - ASR Provider

enum ASRProvider: String, CaseIterable, Identifiable {
    case auto = "Auto-Select"
    case fasterWhisper = "Faster Whisper"
    case whisperCpp = "Whisper.cpp"
    case mlxWhisper = "MLX Whisper"
    case onnxWhisper = "ONNX Whisper"
    case voxtral = "Voxtral"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .auto: return "Automatically choose best provider"
        case .fasterWhisper: return "Fast and accurate (recommended)"
        case .whisperCpp: return "Optimized for Apple Silicon"
        case .mlxWhisper: return "Native Apple Silicon acceleration"
        case .onnxWhisper: return "Cross-platform compatibility"
        case .voxtral: return "High-quality, requires 32GB+ RAM"
        }
    }
    
    var hardwareRequirements: String {
        switch self {
        case .auto: return "Any"
        case .fasterWhisper: return "8GB+ RAM"
        case .whisperCpp: return "Apple Silicon or CUDA"
        case .mlxWhisper: return "Apple Silicon only"
        case .onnxWhisper: return "Any CPU"
        case .voxtral: return "32GB+ RAM, GPU recommended"
        }
    }
    
    var isRecommended: Bool {
        self == .auto
    }
}

// MARK: - Session

struct Session: Identifiable, Hashable {
    let id: UUID
    var title: String
    let startTime: Date
    var duration: TimeInterval
    var status: SessionStatus
    
    // Transcripts
    var liveTranscript: [LiveTranscriptSegment]
    var finalTranscript: [FinalTranscriptSegment]
    
    // Analysis
    var highlights: [Highlight]
    var entities: SessionEntities
    var summary: String?
    
    // Metadata
    var audioSource: AudioSource
    var provider: ASRProvider
    var isPinned: Bool
    var tags: [String]
    
    enum SessionStatus: String {
        case live = "Live"
        case paused = "Paused"
        case finalized = "Completed"
        case processing = "Processing"
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: startTime, relativeTo: Date())
    }
    
    var actionItems: [ActionItem] {
        highlights.compactMap { highlight in
            if case .action(let action) = highlight.type {
                return action
            }
            return nil
        }
    }
}

// MARK: - Live Transcript Segment

struct LiveTranscriptSegment: Identifiable, Hashable {
    let id: UUID
    let text: String
    let timestamp: Date
    let isPartial: Bool
    let confidence: Double
    let audioSource: AudioSourceSegment
    
    enum AudioSourceSegment: String {
        case system = "System"
        case microphone = "Microphone"
        case unknown = "Unknown"
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Final Transcript Segment

struct FinalTranscriptSegment: Identifiable, Hashable {
    let id: UUID
    let speakerId: String
    let speakerName: String?
    let text: String
    let timestamp: Date
    let confidence: Double
    let highlights: [String] // IDs of highlights referencing this segment
    
    var displaySpeaker: String {
        speakerName ?? speakerId
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Highlight

struct Highlight: Identifiable, Hashable {
    let id: UUID
    let type: HighlightType
    let timestamp: Date
    let confidence: Double
    let transcriptSegmentId: UUID?
    let evidence: String? // Quote from transcript
    
    enum HighlightType: Hashable {
        case action(ActionItem)
        case decision(Decision)
        case risk(Risk)
        case keyPoint(String)
        
        var icon: String {
            switch self {
            case .action: return "checkmark.circle"
            case .decision: return "arrow.decision"
            case .risk: return "exclamationmark.triangle"
            case .keyPoint: return "star"
            }
        }
        
        var color: Color {
            switch self {
            case .action: return .blue
            case .decision: return .purple
            case .risk: return .orange
            case .keyPoint: return .yellow
            }
        }
        
        var title: String {
            switch self {
            case .action: return "Action Item"
            case .decision: return "Decision"
            case .risk: return "Risk"
            case .keyPoint: return "Key Point"
            }
        }
    }
}

// MARK: - Action Item

struct ActionItem: Identifiable, Hashable {
    let id: UUID
    let assignee: String
    let task: String
    let dueDate: Date?
    var isCompleted: Bool
    
    var dueDateText: String? {
        guard let date = dueDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Decision

struct Decision: Identifiable, Hashable {
    let id: UUID
    let statement: String
    let stakeholders: [String]
}

// MARK: - Risk

struct Risk: Identifiable, Hashable {
    let id: UUID
    let description: String
    let severity: Severity
    let mitigation: String?
    
    enum Severity: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
    }
}

// MARK: - Session Entities

struct SessionEntities: Hashable {
    var people: [Entity]
    var organizations: [Entity]
    var dates: [Entity]
    var topics: [Entity]
    
    struct Entity: Identifiable, Hashable {
        let id: UUID
        let name: String
        let mentionCount: Int
        let firstMentioned: Date
        let lastMentioned: Date
        let quotes: [String] // Example quotes
    }
    
    var allEntities: [Entity] {
        people + organizations + dates + topics
    }
}

// MARK: - Performance Metrics

struct PerformanceMetrics {
    var realtimeFactor: Double // Processing time / audio time
    var inferenceLatency: Double // ms
    var queueDepth: Int
    var queueMax: Int
    var droppedFrames: Int
    var totalFrames: Int
    
    var dropRate: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(droppedFrames) / Double(totalFrames)
    }
    
    var isHealthy: Bool {
        realtimeFactor < 1.0 && dropRate < 0.01
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    // MARK: - Session Management
    @Published var currentSession: Session?
    @Published var sessions: [Session] = []
    @Published var selectedSession: Session?
    
    // MARK: - Recording State
    @Published var recordingState: RecordingState = .idle
    @Published var isPanelVisible: Bool = false
    @Published var isDashboardOpen: Bool = false
    
    // MARK: - Settings
    @Published var audioSource: AudioSource = .systemAndMic
    @Published var asrProvider: ASRProvider = .auto
    @Published var selectedLanguage: String = "Auto-detect"
    @Published var enableVAD: Bool = true
    @Published var enableDiarization: Bool = true
    @Published var enableScreenOCR: Bool = false
    @Published var llmProvider: String = "None"
    @Published var autoExportFormat: String = "None"
    
    // MARK: - Live Metrics
    @Published var performanceMetrics = PerformanceMetrics(
        realtimeFactor: 0.8,
        inferenceLatency: 150,
        queueDepth: 12,
        queueMax: 64,
        droppedFrames: 0,
        totalFrames: 1240
    )
    
    @Published var audioQuality: AudioQuality = .good
    
    enum AudioQuality {
        case good
        case fair
        case poor
        
        var color: Color {
            switch self {
            case .good: return .green
            case .fair: return .yellow
            case .poor: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .good: return "waveform"
            case .fair: return "waveform.circle"
            case .poor: return "exclamationmark.triangle"
            }
        }
    }
    
    // MARK: - Timer
    private var recordingTimer: Timer?
    private var silenceTimer: Timer?
    private var lastAudioTime: Date?
    
    // MARK: - Initialization
    init() {
        // Load mock data for demonstration
        self.sessions = MockData.generateSessions()
        self.selectedSession = sessions.first
    }
    
    // MARK: - Recording Controls
    func startRecording() {
        let newSession = Session(
            id: UUID(),
            title: generateSessionTitle(),
            startTime: Date(),
            duration: 0,
            status: .live,
            liveTranscript: [],
            finalTranscript: [],
            highlights: [],
            entities: SessionEntities(people: [], organizations: [], dates: [], topics: []),
            summary: nil,
            audioSource: audioSource,
            provider: asrProvider,
            isPinned: false,
            tags: []
        )
        
        currentSession = newSession
        sessions.insert(newSession, at: 0)
        selectedSession = newSession
        recordingState = .recording(duration: 0, startTime: Date())
        isPanelVisible = true
        
        startRecordingTimer()
        startSilenceDetection()
        
        // Simulate live transcript streaming
        simulateLiveTranscription()
    }
    
    func stopRecording() {
        recordingTimer?.invalidate()
        silenceTimer?.invalidate()
        
        if var session = currentSession {
            // Calculate final duration
            let duration: TimeInterval
            switch recordingState {
            case .recording(let dur, _), .paused(let dur, _, _):
                duration = dur
            default:
                duration = 0
            }
            
            session.duration = duration
            session.status = .processing
            currentSession = session
            
            // Update in sessions array
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
        }
        
        recordingState = .idle
        isPanelVisible = false
        isDashboardOpen = true
        
        // Simulate post-processing
        processFinalTranscript()
    }
    
    func pauseRecording() {
        guard case .recording(let duration, let startTime) = recordingState else { return }
        recordingState = .paused(duration: duration, startTime: startTime, pausedAt: Date())
        recordingTimer?.invalidate()
        
        if var session = currentSession {
            session.status = .paused
            currentSession = session
        }
    }
    
    func resumeRecording() {
        guard case .paused(let duration, let startTime, _) = recordingState else { return }
        recordingState = .recording(duration: duration, startTime: startTime)
        startRecordingTimer()
        
        if var session = currentSession {
            session.status = .live
            currentSession = session
        }
    }
    
    // MARK: - Private Methods
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                switch self.recordingState {
                case .recording(let duration, let startTime):
                    let newDuration = Date().timeIntervalSince(startTime)
                    self.recordingState = .recording(duration: newDuration, startTime: startTime)
                    
                    if var session = self.currentSession {
                        session.duration = newDuration
                        self.currentSession = session
                    }
                    
                case .paused(let duration, let startTime, let pausedAt):
                    // Calculate duration up to pause point
                    let totalPaused = Date().timeIntervalSince(pausedAt)
                    let activeDuration = pausedAt.timeIntervalSince(startTime) - totalPaused
                    self.recordingState = .paused(duration: activeDuration, startTime: startTime, pausedAt: pausedAt)
                    
                default:
                    break
                }
            }
        }
    }
    
    private func startSilenceDetection() {
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Check if audio has been received recently
                // In real app, would check actual audio input
            }
        }
    }
    
    private func generateSessionTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: Date())
        return "Meeting at \(time)"
    }
    
    private func simulateLiveTranscription() {
        // Simulate live transcript updates
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
                guard self.recordingState != .idle else {
                    timer.invalidate()
                    return
                }
                
                // Add new transcript segment
                // In real app, this comes from WebSocket
            }
        }
    }
    
    private func processFinalTranscript() {
        // Simulate post-processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, var session = self.currentSession else { return }
            
            // Generate final transcript with speaker labels
            session.finalTranscript = MockData.generateFinalTranscript(from: session.liveTranscript)
            session.entities = MockData.generateEntities()
            session.highlights = MockData.generateHighlights()
            session.summary = MockData.generateSummary()
            session.status = .finalized
            
            self.currentSession = session
            if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                self.sessions[index] = session
            }
        }
    }
}
