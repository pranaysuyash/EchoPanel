import Foundation

final class WebSocketStreamer: NSObject {
    var onStatusUpdate: ((StreamStatus, String) -> Void)?
    var onPartial: ((String, TimeInterval, TimeInterval, Double) -> Void)?
    var onFinal: ((String, TimeInterval, TimeInterval, Double) -> Void)?
    var onCardsUpdate: (([ActionItem], [DecisionItem], [RiskItem]) -> Void)?
    var onEntitiesUpdate: (([EntityItem]) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var reconnectDelay: TimeInterval = 1
    private let maxDelay: TimeInterval = 10
    private let session = URLSession(configuration: .default)

    var url = URL(string: "ws://127.0.0.1:8000/ws/live-listener")

    func connect() {
        guard let url else { return }
        task = session.webSocketTask(with: url)
        task?.resume()
        sendStart()
        receiveLoop()
        onStatusUpdate?(.streaming, "Connected")
    }

    func disconnect() {
        sendStop()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    func sendAudioFrame(_ data: Data) {
        task?.send(.data(data)) { [weak self] error in
            if let error {
                self?.handleError(error)
            }
        }
    }

    private func sendStart() {
        let payload: [String: Any] = [
            "type": "start",
            "session_id": UUID().uuidString,
            "sample_rate": 16000,
            "format": "pcm_s16le",
            "channels": 1
        ]
        sendJSON(payload)
    }

    private func sendStop() {
        let payload: [String: Any] = [
            "type": "stop",
            "session_id": UUID().uuidString
        ]
        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            if let error {
                self?.handleError(error)
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            case .failure(let error):
                self.handleError(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else { return }
            handleJSON(data)
        case .data:
            break
        @unknown default:
            break
        }
    }

    private func handleJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "asr_partial":
            let text = object["text"] as? String ?? ""
            let t0 = object["t0"] as? TimeInterval ?? 0
            let t1 = object["t1"] as? TimeInterval ?? 0
            onPartial?(text, t0, t1, 0.6)
        case "asr_final":
            let text = object["text"] as? String ?? ""
            let t0 = object["t0"] as? TimeInterval ?? 0
            let t1 = object["t1"] as? TimeInterval ?? 0
            onFinal?(text, t0, t1, 0.9)
        case "cards_update":
            onCardsUpdate?([], [], [])
        case "entities_update":
            onEntitiesUpdate?([])
        case "status":
            let state = object["state"] as? String ?? ""
            if state == "streaming" {
                onStatusUpdate?(.streaming, "")
            } else if state == "reconnecting" {
                onStatusUpdate?(.reconnecting, "")
            } else {
                onStatusUpdate?(.error, "")
            }
        default:
            break
        }
    }

    private func handleError(_ error: Error) {
        onStatusUpdate?(.reconnecting, error.localizedDescription)
        reconnect()
    }

    private func reconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let delay = min(reconnectDelay, maxDelay)
        reconnectDelay = min(reconnectDelay * 2, maxDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
}
