import Combine
import Foundation

final class AppState: ObservableObject {
    @Published var listenerState: ListenerState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var audioQuality: String = "Good"
    @Published var statusLine: String = "Idle"
    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var actions: [CardItem] = []
    @Published var decisions: [DecisionItem] = []
    @Published var risks: [RiskItem] = []
    @Published var entities: [EntityItem] = []
    @Published var panelVisible: Bool = false

    private var timerCancellable: AnyCancellable?

    func startSession() {
        listenerState = .listening
        statusLine = "Streaming"
        startTimer()
    }

    func stopSession() {
        listenerState = .idle
        statusLine = "Idle"
        stopTimer()
    }

    func resetSession() {
        elapsedSeconds = 0
        transcriptSegments = []
        actions = []
        decisions = []
        risks = []
        entities = []
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
    }
}
