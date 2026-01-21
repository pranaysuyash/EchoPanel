import Foundation

final class WebSocketClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var reconnectTimer: Timer?
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func connect() {
        disconnect()
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        listen()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func sendStart(sessionID: String) {
        let payload: [String: Any] = [
            "type": "start",
            "session_id": sessionID,
            "sample_rate": 16000,
            "format": "pcm_s16le",
            "channels": 1
        ]
        sendJSON(payload)
    }

    func sendStop(sessionID: String) {
        let payload: [String: Any] = [
            "type": "stop",
            "session_id": sessionID
        ]
        sendJSON(payload)
    }

    func sendPCMFrame(_ data: Data) {
        webSocketTask?.send(.data(data)) { error in
            if let error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let message = URLSessionWebSocketTask.Message.data(data)
            webSocketTask?.send(message) { error in
                if let error {
                    print("WebSocket JSON send error: \(error)")
                }
            }
        } catch {
            print("JSON encode error: \(error)")
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handle(message)
                self?.listen()
            case .failure:
                self?.scheduleReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            // TODO: Decode JSON events and update AppState.
            print("Received data: \(data.count) bytes")
        case .string(let text):
            print("Received text: \(text)")
        @unknown default:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}
