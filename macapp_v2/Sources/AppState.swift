import SwiftUI
import Combine

enum MockFlowTrack: String, CaseIterable, Identifiable {
    case teamStandup
    case customerEscalation
    case hiringLoop
    case launchWarRoom

    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .teamStandup:
            return "Team Standup"
        case .customerEscalation:
            return "Customer Escalation"
        case .hiringLoop:
            return "Hiring Debrief"
        case .launchWarRoom:
            return "Launch War Room"
        }
    }

    var subtitle: String {
        switch self {
        case .teamStandup:
            return "Balanced cross-functional sync"
        case .customerEscalation:
            return "High-stress triage and ownership"
        case .hiringLoop:
            return "Structured people decisions"
        case .launchWarRoom:
            return "Fast decisions under release pressure"
        }
    }

    var icon: String {
        switch self {
        case .teamStandup:
            return "person.3.sequence"
        case .customerEscalation:
            return "exclamationmark.bubble"
        case .hiringLoop:
            return "person.crop.rectangle.stack"
        case .launchWarRoom:
            return "bolt.badge.clock"
        }
    }

    var accent: Color {
        switch self {
        case .teamStandup:
            return .teal
        case .customerEscalation:
            return .orange
        case .hiringLoop:
            return .indigo
        case .launchWarRoom:
            return .mint
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var recordingState: RecordingState = .idle
    @Published var panelVisible: Bool = false
    @Published var alwaysOnTop: Bool = false
    @Published var currentSession: Session?
    @Published var sessions: [Session] = MockData.sampleSessions
    @Published var activeFlow: MockFlowTrack = .teamStandup
    @Published var liveTranscript: [TranscriptItem] = MockData.sampleTranscript
    @Published var liveHighlights: [Highlight] = MockData.sampleHighlights
    @Published var livePeople: [Person] = MockData.samplePeople
    @Published var reviewSummary: String = MockData.sampleSummary
    
    // MARK: - UI State
    @Published var isLoading: Bool = false
    @Published var errorState: AppError?
    @Published var showOnboarding: Bool = false
    @Published var showExportDialog: Bool = false
    @Published var showDeleteConfirmation: Bool = false
    @Published var sessionToDelete: Session?
    @Published var selectedExportSession: Session?
    @Published var workspaceMode: WorkspaceMode = .dashboard
    
    // MARK: - AppStorage Properties (via UserDefaults in EchoPanelV2App)
    var hasCompletedOnboarding: Bool = false
    
    // MARK: - Private
    private var timer: Timer?
    private var recordingSeconds: Int = 0
    private var scriptedMoments: [TranscriptItem] = []
    
    enum WorkspaceMode: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case flowStudio = "Flow Studio"
        case history = "History"
        
        var id: String { rawValue }
    }

    init() {
        applyFlow(.teamStandup)
    }

    func applyFlow(_ flow: MockFlowTrack) {
        let payload = MockData.payload(for: flow)
        activeFlow = flow
        sessions = payload.sessions
        liveTranscript = payload.transcript
        liveHighlights = payload.highlights
        livePeople = payload.people
        reviewSummary = payload.summary
        scriptedMoments = payload.transcript
        stopTimer()
        recordingState = .idle
        currentSession = nil
    }

    func startRecording() {
        recordingSeconds = 0
        let payload = MockData.payload(for: activeFlow)
        scriptedMoments = payload.transcript

        currentSession = Session(
            id: UUID(),
            title: "\(activeFlow.title) (Live)",
            startTime: Date(),
            duration: 0,
            transcript: [],
            highlights: []
        )

        recordingState = .recording(duration: 0)
        startTimer()
        panelVisible = true

        // Seed the stream so users immediately see movement in live UX previews.
        appendNextScriptedMoment()
        appendNextScriptedMoment()
    }

    func stopRecording() {
        stopTimer()
        if var session = currentSession {
            session.duration = recordingSeconds
            sessions.insert(session, at: 0)
        }
        recordingState = .idle
        currentSession = nil
    }
    
    func pauseRecording() {
        stopTimer()
        recordingState = .paused(duration: recordingSeconds)
    }
    
    func resumeRecording() {
        recordingState = .recording(duration: recordingSeconds)
        startTimer()
    }
    
    func skipForward(seconds: Int) {
        // Add the skip interval to the recording duration
        recordingSeconds += seconds
        switch recordingState {
        case .recording(let duration):
            recordingState = .recording(duration: recordingSeconds)
        case .paused(let duration):
            recordingState = .paused(duration: recordingSeconds)
        default:
            break
        }
    }
    
    func toggleRecording() {
        switch recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .paused:
            resumeRecording()
        case .error:
            startRecording()
        }
    }
    
    func togglePanel() {
        panelVisible.toggle()
    }
    
    func navigateToHistory() {
        workspaceMode = .history
    }
    
    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = nil
        }
    }
    
    func showDeleteConfirmation(for session: Session) {
        sessionToDelete = session
        showDeleteConfirmation = true
    }
    
    func confirmDelete() {
        if let session = sessionToDelete {
            deleteSession(session)
        }
        sessionToDelete = nil
        showDeleteConfirmation = false
    }
    
    func exportSession(_ session: Session) {
        selectedExportSession = session
        showExportDialog = true
    }
    
    func dismissError() {
        errorState = nil
    }
    
    func retryError() {
        let lastError = errorState
        errorState = nil
        // Attempt to recover from the error
        switch lastError {
        case .asrError, .llmError:
            startRecording()
        default:
            break
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.recordingSeconds += 1
                switch self.recordingState {
                case .recording:
                    self.recordingState = .recording(duration: self.recordingSeconds)
                case .paused:
                    self.recordingState = .paused(duration: self.recordingSeconds)
                default:
                    break
                }

                if self.recordingSeconds % 8 == 0 {
                    self.appendNextScriptedMoment()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func appendNextScriptedMoment() {
        guard var session = currentSession else { return }
        guard !scriptedMoments.isEmpty else { return }

        let next = scriptedMoments.removeFirst()
        session.transcript.append(next)

        if let action = next.actionItem {
            session.highlights.append(
                Highlight(
                    id: UUID(),
                    type: .action,
                    content: "\(action.assignee): \(action.task)",
                    timestamp: next.timestamp
                )
            )
        } else if next.isPinned {
            session.highlights.append(
                Highlight(
                    id: UUID(),
                    type: .keyPoint,
                    content: next.text,
                    timestamp: next.timestamp
                )
            )
        }

        currentSession = session
        liveTranscript = session.transcript
        liveHighlights = session.highlights
        livePeople = MockData.people(from: session.transcript, fallback: livePeople)
    }
}

enum RecordingState: Equatable {
    case idle
    case recording(duration: Int)
    case paused(duration: Int)
    case error(String)
}

struct Session: Identifiable, Hashable {
    let id: UUID
    var title: String
    let startTime: Date
    var duration: Int
    var transcript: [TranscriptItem]
    var highlights: [Highlight]
    
    var formattedDuration: String {
        let mins = duration / 60
        let secs = duration % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: startTime, relativeTo: Date())
    }
}

struct TranscriptItem: Identifiable, Hashable {
    let id: UUID
    let speaker: String
    let text: String
    let timestamp: Date
    var isPinned: Bool = false
    var actionItem: ActionItem?

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct Highlight: Identifiable, Hashable {
    let id: UUID
    let type: HighlightType
    let content: String
    let timestamp: Date
}

enum HighlightType: Hashable {
    case action
    case decision
    case keyPoint
    case question
    
    var displayName: String {
        switch self {
        case .action: return "Action"
        case .decision: return "Decision"
        case .keyPoint: return "Key Point"
        case .question: return "Question"
        }
    }
}

struct ActionItem: Identifiable, Hashable {
    let id: UUID
    let assignee: String
    let task: String
    var isCompleted: Bool = false
}

struct Person: Identifiable, Hashable {
    let id: UUID
    let name: String
    let mentionCount: Int
    let topics: [String]
}
