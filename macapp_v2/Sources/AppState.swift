import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var panelVisible: Bool = false
    @Published var alwaysOnTop: Bool = false
    @Published var currentSession: Session?
    @Published var sessions: [Session] = MockData.sampleSessions
    
    private var timer: Timer?
    private var recordingSeconds: Int = 0
    
    func startRecording() {
        recordingSeconds = 0
        currentSession = Session(
            id: UUID(),
            title: "New Session",
            startTime: Date(),
            duration: 0,
            transcript: [],
            highlights: []
        )
        recordingState = .recording(duration: 0)
        startTimer()
        panelVisible = true
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
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
