import Foundation

final class WebSocketStreamer: NSObject {
    var onStatus: ((StreamStatus, String) -> Void)?
    var onASRPartial: ((String, TimeInterval, TimeInterval, Double) -> Void)?
    var onASRFinal: ((String, TimeInterval, TimeInterval, Double) -> Void)?
    var onCardsUpdate: (([ActionItem], [DecisionItem], [RiskItem]) -> Void)?
    var onEntitiesUpdate: (([EntityItem]) -> Void)?
    var onFinalSummary: ((String, [String: Any]) -> Void)?

    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var url: URL
    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var pingTimer: Timer?

    private var sessionID: String?
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 10

    init(url: URL) {
        self.url = url
    }

    func connect(sessionID: String) {
        self.sessionID = sessionID
        reconnectDelay = 1

        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveLoop()
        schedulePing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sendStart()
        }
        if debugEnabled {
            NSLog("WebSocketStreamer: connect \(url.absoluteString)")
        }
    }

    func disconnect() {
        sendStop()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        sessionID = nil
        stopPing()
        if debugEnabled {
            NSLog("WebSocketStreamer: disconnect")
        }
    }

    func sendPCMFrame(_ data: Data) {
        if debugEnabled {
            NSLog("📤 WebSocketStreamer sending PCM frame: %d bytes", data.count)
        }
        task?.send(.data(data)) { [weak self] error in
            if let error {
                NSLog("❌ WebSocketStreamer send error: %@", error.localizedDescription)
                self?.handleError(error)
            }
        }
    }

    private func sendStart() {
        guard let sessionID else { return }
        if debugEnabled {
            NSLog("WebSocketStreamer: send start")
        }
        let payload: [String: Any] = [
            "type": "start",
            "session_id": sessionID,
            "sample_rate": 16000,
            "format": "pcm_s16le",
            "channels": 1
        ]
        sendJSON(payload)
    }

    private func sendStop() {
        guard let sessionID else { return }
        if debugEnabled {
            NSLog("WebSocketStreamer: send stop")
        }
        let payload: [String: Any] = [
            "type": "stop",
            "session_id": sessionID
        ]
        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { [weak self] error in
            if let error { self?.handleError(error) }
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
        case .data(let data):
            handleJSON(data)
        @unknown default:
            break
        }
    }

    private func handleJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "status":
            let state = (object["state"] as? String) ?? "error"
            let message = (object["message"] as? String) ?? ""
            if state == "streaming" {
                onStatus?(.streaming, message)
            } else if state == "reconnecting" {
                onStatus?(.reconnecting, message)
            } else {
                onStatus?(.error, message)
            }

        case "asr_partial":
            let text = (object["text"] as? String) ?? ""
            let t0 = (object["t0"] as? TimeInterval) ?? 0
            let t1 = (object["t1"] as? TimeInterval) ?? 0
            let confidence = (object["confidence"] as? Double) ?? 0.6
            onASRPartial?(text, t0, t1, confidence)

        case "asr_final":
            let text = (object["text"] as? String) ?? ""
            let t0 = (object["t0"] as? TimeInterval) ?? 0
            let t1 = (object["t1"] as? TimeInterval) ?? 0
            let confidence = (object["confidence"] as? Double) ?? 0.9
            onASRFinal?(text, t0, t1, confidence)

        case "cards_update":
            let actions = decodeActionItems(object["actions"])
            let decisions = decodeDecisionItems(object["decisions"])
            let risks = decodeRiskItems(object["risks"])
            onCardsUpdate?(actions, decisions, risks)

        case "entities_update":
            let entities = decodeEntityItems(object)
            onEntitiesUpdate?(entities)

        case "final_summary":
            let markdown = (object["markdown"] as? String) ?? ""
            let jsonObject = (object["json"] as? [String: Any]) ?? [:]
            onFinalSummary?(markdown, jsonObject)

        default:
            break
        }
    }

    private func decodeActionItems(_ value: Any?) -> [ActionItem] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.map { item in
            ActionItem(
                text: (item["text"] as? String) ?? "",
                owner: item["owner"] as? String,
                due: item["due"] as? String,
                confidence: (item["confidence"] as? Double) ?? 0
            )
        }
    }

    private func decodeDecisionItems(_ value: Any?) -> [DecisionItem] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.map { item in
            DecisionItem(text: (item["text"] as? String) ?? "", confidence: (item["confidence"] as? Double) ?? 0)
        }
    }

    private func decodeRiskItems(_ value: Any?) -> [RiskItem] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.map { item in
            RiskItem(text: (item["text"] as? String) ?? "", confidence: (item["confidence"] as? Double) ?? 0)
        }
    }

    private func decodeEntityItems(_ root: [String: Any]) -> [EntityItem] {
        let mapping: [(key: String, type: String)] = [
            ("people", "person"),
            ("orgs", "org"),
            ("dates", "date"),
            ("projects", "project"),
            ("topics", "topic")
        ]

        var results: [EntityItem] = []
        for (key, type) in mapping {
            guard let list = root[key] as? [[String: Any]] else { continue }
            for entity in list {
                results.append(
                    EntityItem(
                        name: (entity["name"] as? String) ?? "",
                        type: type,
                        lastSeen: (entity["last_seen"] as? TimeInterval) ?? 0,
                        confidence: (entity["confidence"] as? Double) ?? 0
                    )
                )
            }
        }
        return results
    }

    private func handleError(_ error: Error) {
        if debugEnabled {
            NSLog("WebSocketStreamer: error %@", error.localizedDescription)
        }
        onStatus?(.reconnecting, error.localizedDescription)
        reconnect()
    }

    private func reconnect() {
        guard let sessionID else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        stopPing()

        let delay = min(reconnectDelay, maxReconnectDelay)
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.connect(sessionID: sessionID)
        }
    }

    private func schedulePing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.task?.sendPing { error in
                if let error {
                    self.handleError(error)
                }
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
}
