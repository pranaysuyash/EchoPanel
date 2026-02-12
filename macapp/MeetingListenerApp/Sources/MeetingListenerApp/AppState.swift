import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var sessionState: SessionState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var transcript: [TranscriptSegment] = []
    @Published var actions: [ActionItem] = []
    @Published var decisions: [DecisionItem] = []
    @Published var risks: [RiskItem] = []
    @Published var entities: [EntityItem] = []
    @Published var audioQuality: AudioQuality = .unknown
    @Published var streamStatus: StreamStatus = .reconnecting
    @Published var statusMessage: String = ""

    private var timerCancellable: AnyCancellable?
    private var sessionStart: Date?

    let audioCapture = AudioCaptureManager()
    let streamer = WebSocketStreamer()

    init() {
        audioCapture.onAudioQualityUpdate = { [weak self] quality in
            Task { @MainActor in
                self?.audioQuality = quality
            }
        }
        audioCapture.onPcmFrame = { [weak self] data in
            self?.streamer.sendAudioFrame(data)
        }
        audioCapture.onPermissionRequired = { [weak self] in
            Task { @MainActor in
                self?.sessionState = .error
                self?.statusMessage = "Screen recording permission required"
            }
        }
        streamer.onStatusUpdate = { [weak self] status, message in
            Task { @MainActor in
                self?.streamStatus = status
                self?.statusMessage = message
            }
        }
        streamer.onPartial = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in
                self?.handlePartial(text: text, t0: t0, t1: t1, confidence: confidence)
            }
        }
        streamer.onFinal = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in
                self?.handleFinal(text: text, t0: t0, t1: t1, confidence: confidence)
            }
        }
        streamer.onCardsUpdate = { [weak self] actions, decisions, risks in
            Task { @MainActor in
                self?.updateCards(actions: actions, decisions: decisions, risks: risks)
            }
        }
        streamer.onEntitiesUpdate = { [weak self] entities in
            Task { @MainActor in
                self?.updateEntities(entities)
            }
        }
    }

    func startSession() {
        guard sessionState != .listening else { return }
        sessionState = .listening
        streamStatus = .reconnecting
        statusMessage = "Connecting"
        transcript.removeAll()
        actions.removeAll()
        decisions.removeAll()
        risks.removeAll()
        entities.removeAll()
        sessionStart = Date()
        startTimer()
        audioCapture.startCapture()
        streamer.connect()
    }

    func stopSession() {
        guard sessionState == .listening else { return }
        sessionState = .idle
        statusMessage = ""
        stopTimer()
        audioCapture.stopCapture()
        streamer.disconnect()
    }

    func updateElapsed() {
        guard let sessionStart else {
            elapsedTime = 0
            return
        }
        elapsedTime = Date().timeIntervalSince(sessionStart)
    }

    private func startTimer() {
        stopTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateElapsed()
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        elapsedTime = 0
    }

    func handlePartial(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        if let lastIndex = transcript.indices.last, transcript[lastIndex].isFinal == false {
            transcript[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence)
        } else {
            transcript.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence))
        }
    }

    func handleFinal(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        if let lastIndex = transcript.indices.last, transcript[lastIndex].isFinal == false {
            transcript[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence)
        } else {
            transcript.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence))
        }
    }

    func updateCards(actions: [ActionItem], decisions: [DecisionItem], risks: [RiskItem]) {
        self.actions = actions
        self.decisions = decisions
        self.risks = risks
    }

    func updateEntities(_ entities: [EntityItem]) {
        self.entities = entities
    }
}
