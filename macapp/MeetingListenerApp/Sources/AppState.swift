import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var sessionState: SessionState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var audioQuality: AudioQuality = .unknown
    @Published var streamStatus: StreamStatus = .reconnecting
    @Published var statusMessage: String = ""

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var actions: [ActionItem] = []
    @Published var decisions: [DecisionItem] = []
    @Published var risks: [RiskItem] = []
    @Published var entities: [EntityItem] = []

    @Published var finalSummaryMarkdown: String = ""
    @Published var finalSummaryJSON: [String: Any] = [:]

    private var sessionID: String?
    private var timerCancellable: AnyCancellable?

    private let audioCapture = AudioCaptureManager()
    private let streamer = WebSocketStreamer(url: URL(string: "ws://127.0.0.1:8000/ws/live-listener")!)

    init() {
        audioCapture.onAudioQualityUpdate = { [weak self] quality in
            Task { @MainActor in self?.audioQuality = quality }
        }
        audioCapture.onPCMFrame = { [weak self] frame in
            self?.streamer.sendPCMFrame(frame)
        }

        streamer.onStatus = { [weak self] status, message in
            Task { @MainActor in
                self?.streamStatus = status
                self?.statusMessage = message
            }
        }
        streamer.onASRPartial = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in self?.handlePartial(text: text, t0: t0, t1: t1, confidence: confidence) }
        }
        streamer.onASRFinal = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in self?.handleFinal(text: text, t0: t0, t1: t1, confidence: confidence) }
        }
        streamer.onCardsUpdate = { [weak self] actions, decisions, risks in
            Task { @MainActor in
                self?.actions = actions
                self?.decisions = decisions
                self?.risks = risks
            }
        }
        streamer.onEntitiesUpdate = { [weak self] entities in
            Task { @MainActor in self?.entities = entities }
        }
        streamer.onFinalSummary = { [weak self] markdown, jsonObject in
            Task { @MainActor in
                self?.finalSummaryMarkdown = markdown
                self?.finalSummaryJSON = jsonObject
            }
        }
    }

    var statusLine: String {
        let base: String
        switch streamStatus {
        case .streaming: base = "Streaming"
        case .reconnecting: base = "Reconnecting"
        case .error: base = "Backend unavailable"
        }
        if statusMessage.isEmpty { return base }
        return "\(base) - \(statusMessage)"
    }

    var timerText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startSession() {
        guard sessionState != .listening else { return }
        resetSession()
        sessionState = .starting
        statusMessage = "Requesting permission"

        Task {
            let granted = await audioCapture.requestPermission()
            guard granted else {
                sessionState = .error
                statusMessage = "Screen Recording permission required"
                return
            }

            let id = UUID().uuidString
            sessionID = id

            do {
                try await audioCapture.startCapture()
            } catch {
                sessionState = .error
                statusMessage = "Capture failed: \(error.localizedDescription)"
                return
            }

            streamStatus = .reconnecting
            statusMessage = "Connecting"
            streamer.connect(sessionID: id)
            startTimer()
            sessionState = .listening
        }
    }

    func stopSession() {
        guard sessionState == .listening || sessionState == .starting else { return }
        sessionState = .finalizing
        stopTimer()

        Task {
            await audioCapture.stopCapture()
            streamer.disconnect()
            sessionState = .idle
            statusMessage = ""
        }
    }

    func resetSession() {
        elapsedSeconds = 0
        transcriptSegments = []
        actions = []
        decisions = []
        risks = []
        entities = []
        finalSummaryMarkdown = ""
        finalSummaryJSON = [:]
        sessionID = nil
    }

    func copyMarkdownToClipboard() {
        let markdown = finalSummaryMarkdown.isEmpty ? renderLiveMarkdown() : finalSummaryMarkdown
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func renderLiveMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Live Notes")
        lines.append("")
        lines.append("## Transcript")
        for segment in transcriptSegments where segment.isFinal {
            lines.append("- [\(formatTime(segment.t0))] \(segment.text)")
        }
        lines.append("")
        lines.append("## Actions")
        for item in actions { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Decisions")
        for item in decisions { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Risks")
        for item in risks { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Entities")
        for entity in entities { lines.append("- \(entity.name) (\(entity.type))") }
        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.elapsedSeconds += 1
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        elapsedSeconds = 0
    }

    private func handlePartial(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        if let lastIndex = transcriptSegments.indices.last, transcriptSegments[lastIndex].isFinal == false {
            transcriptSegments[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence)
        } else {
            transcriptSegments.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence))
        }
    }

    private func handleFinal(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        if let lastIndex = transcriptSegments.indices.last, transcriptSegments[lastIndex].isFinal == false {
            transcriptSegments[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence)
        } else {
            transcriptSegments.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence))
        }
    }
}
