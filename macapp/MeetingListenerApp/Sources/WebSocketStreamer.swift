import Foundation

/**
 * Metrics structure for real-time streaming health monitoring.
 *
 * Contains information about queue depths, processing times, and system health
 * to enable backpressure handling and performance optimization.
 */
// PR2: SourceMetrics struct for health monitoring
struct SourceMetrics {
    let source: String
    let queueDepth: Int
    let queueMax: Int
    let queueFillRatio: Double
    let droppedTotal: Int
    let droppedRecent: Int
    let avgInferMs: Double
    let realtimeFactor: Double
    let timestamp: TimeInterval
    
    // V1: Additional fields for enhanced observability
    let connectionId: String?
    let sessionId: String?
    let attemptId: String?
    
    // VAD metrics
    let clientVadEnabled: Bool
    let speechChunksEmitted: Int
    let totalChunksProcessed: Int
    let speechRatio: Double
}

// V1: Correlation IDs for observability
struct CorrelationIDs {
    let sessionId: String
    let attemptId: String
    let connectionId: String
    
    static func generate(sessionId: String, attemptId: String) -> CorrelationIDs {
        return CorrelationIDs(
            sessionId: sessionId,
            attemptId: attemptId,
            connectionId: UUID().uuidString
        )
    }
}

/**
 * WebSocket-based streaming client for real-time audio transmission to ASR backend.
 *
 * ## Architecture
 * This class manages the WebSocket connection to the backend ASR service,
 * handling real-time audio streaming, connection resilience, and metrics reporting.
 *
 * ## Real-time Streaming
 * - Sends audio frames as PCM data in real-time
 * - Handles partial and final ASR results
 * - Manages session lifecycle (start/stop)
 * - Supports multiple audio sources with tagging
 *
 * ## Resilience Features
 * - Automatic reconnection with exponential backoff
 * - Circuit breaker pattern to prevent infinite retry loops
 * - Message buffering during disconnections
 * - Ping/pong health checks
 *
 * ## Metrics and Monitoring
 * - Reports real-time processing metrics
 * - Tracks queue depth and fill ratios
 * - Monitors dropped frames and processing times
 * - Provides connection health indicators
 */
final class WebSocketStreamer: NSObject {
    var onStatus: ((StreamStatus, String) -> Void)?
    var onASRPartial: ((String, TimeInterval, TimeInterval, Double, String?) -> Void)? // + source
    var onASRFinal: ((String, TimeInterval, TimeInterval, Double, String?) -> Void)?   // + source
    var onCardsUpdate: (([ActionItem], [DecisionItem], [RiskItem]) -> Void)?
    var onEntitiesUpdate: (([EntityItem]) -> Void)?
    var onFinalSummary: ((String, [String: Any]) -> Void)?
    var onMetrics: ((SourceMetrics) -> Void)? // PR2: Metrics callback
    var onVoiceNoteTranscript: ((String, TimeInterval) -> Void)? // VNI: Voice note transcript callback

    // V1: Correlation ID access for logging
    var correlationIDs: CorrelationIDs? { _correlationIDs }
    private var _correlationIDs: CorrelationIDs?
    private var voiceNoteSessionID: String? // VNI: Track active voice note session

    // Lightweight connectivity indicator for callers that need a guard.
    var isConnected: Bool { task != nil }

    // Use main operation queue for URLSession delegate callbacks so delegate-based
// handlers (WebSocket receive/send callbacks) always run on the main thread.
// This prevents accidental Published-property mutations from occurring on the
// NSURLSession delegate background thread and avoids SwiftUI/Combine race/trap
// conditions (observed as EXC_BREAKPOINT in com.apple.NSURLSession-delegate).
private let session: URLSession = {
    let queue = OperationQueue.main
    queue.qualityOfService = .userInitiated
    return URLSession(configuration: .default, delegate: nil, delegateQueue: queue)
}()
    private var task: URLSessionWebSocketTask?
    private var webSocketRequest: URLRequest { BackendConfig.webSocketRequest }
    private var url: URL { webSocketRequest.url ?? BackendConfig.webSocketURL }
    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var pingTimer: Timer?

    private var sessionID: String?
    private var attemptID: String?
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 10
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var finalSummaryWaiter: CheckedContinuation<Bool, Never>?

    // P0: Bounded send queue to prevent blocking capture thread on network stall
    private let sendQueue = OperationQueue()
    private let maxQueuedSends = 100

    // Ping/pong liveness: treat the socket as dead if we don't get a ping completion for too long.
    private var lastPongTime: Date?
    private let pongTimeout: TimeInterval = 15

    // Audio pacing + buffering:
    // Capture callbacks must never block on pacing logic. We buffer frames per source and
    // drain them on a background task at (approx) real-time pace.
    private struct PendingAudioFrame {
        let data: Data
        let source: String
        let sampleCount: Int
        let enqueuedAtUptimeNs: UInt64
    }

    private final class RingBuffer<T> {
        private var storage: [T?]
        private var head: Int = 0
        private var tail: Int = 0
        private(set) var count: Int = 0

        let capacity: Int

        init(capacity: Int) {
            self.capacity = max(1, capacity)
            self.storage = Array(repeating: nil, count: self.capacity)
        }

        func removeAll() {
            storage = Array(repeating: nil, count: capacity)
            head = 0
            tail = 0
            count = 0
        }

        // Push newest. If full, evict oldest and return it.
        func pushEvictingOldest(_ value: T) -> T? {
            var evicted: T? = nil
            if count == capacity {
                evicted = pop()
            }
            storage[tail] = value
            tail = (tail + 1) % capacity
            count += 1
            return evicted
        }

        func pop() -> T? {
            guard count > 0 else { return nil }
            let value = storage[head]
            storage[head] = nil
            head = (head + 1) % capacity
            count -= 1
            return value
        }
    }

    private let audioBufferLock = NSLock()
    private var audioBuffersBySource: [String: RingBuffer<PendingAudioFrame>] = [:]
    private var audioDropsBySource: [String: Int] = [:]
    private var audioDrainTask: Task<Void, Never>?
    // MainActor-owned because it's driven by WS status events delivered to the main queue.
    @MainActor private var serverStreamingAcked: Bool = false

    // 16kHz mono PCM16. Defaults are tuned for "Both" mode:
    // keep at most ~2.4s buffered per source (120 frames * 20ms).
    private let audioSampleRate: Double = 16000.0
    private let audioBytesPerSample: Int = 2
    private let maxBufferedFramesPerSource: Int = 120

    override init() {
        super.init()
        sendQueue.maxConcurrentOperationCount = 1
        sendQueue.qualityOfService = .utility
    }

    func connect(sessionID: String, attemptID: String? = nil) {
        self.sessionID = sessionID
        self.attemptID = attemptID ?? UUID().uuidString
        Task { @MainActor in self.serverStreamingAcked = false }
        resetAudioBuffers()
        
        // V1: Generate correlation IDs for this connection
        self._correlationIDs = CorrelationIDs.generate(
            sessionId: sessionID,
            attemptId: self.attemptID!
        )
        
        reconnectDelay = 1
        reconnectAttempts = 0
        lastPongTime = nil

        task?.cancel(with: .goingAway, reason: nil)
        task = session.webSocketTask(with: webSocketRequest)
        task?.resume()
        receiveLoop()
        schedulePing()
        startAudioDrainLoop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sendStart()
        }
        
        // V1: Structured logging with correlation IDs (async to MainActor)
        Task { @MainActor in
            StructuredLogger.shared.withContext(
                sessionId: sessionID,
                attemptId: self.attemptID,
                connectionId: self._correlationIDs?.connectionId
            ) {
                StructuredLogger.shared.info("WebSocket connecting", metadata: [
                    "url_scheme": self.url.scheme ?? "ws",
                    "url_host": self.url.host ?? "localhost",
                    "url_port": self.url.port ?? 80
                ])
            }
        }
        
        if debugEnabled {
            // Sanitize URL: only log scheme and host to avoid leaking tokens in query params
            let sanitizedURL = "\(url.scheme ?? "ws")://\(url.host ?? "localhost"):\(url.port ?? 80)"
            NSLog("WebSocketStreamer: connect \(sanitizedURL)")
        }
    }

    func disconnect() {
        sendStop()
        
        // P0: Cancel pending send operations
        sendQueue.cancelAllOperations()
        
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        sessionID = nil
        stopPing()
        stopAudioDrainLoop()
        resetAudioBuffers()
        Task { @MainActor in self.serverStreamingAcked = false }
        reconnectAttempts = 0
        lastPongTime = nil
        finalSummaryWaiter = nil
        if debugEnabled {
            NSLog("WebSocketStreamer: disconnect")
        }
    }

    @MainActor
    func stopAndAwaitFinalSummary(timeout: TimeInterval) async -> Bool {
        guard task != nil else { return true }
        if finalSummaryWaiter != nil {
            return true
        }

        let didReceive = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.finalSummaryWaiter = continuation
            self.sendStop()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                if let waiter = self.finalSummaryWaiter {
                    self.finalSummaryWaiter = nil
                    waiter.resume(returning: false)
                }
            }
        }

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        sessionID = nil
        stopPing()
        stopAudioDrainLoop()
        resetAudioBuffers()
        self.serverStreamingAcked = false
        finalSummaryWaiter = nil
        return didReceive
    }

    func sendPCMFrame(_ data: Data, source: String = "system") {
        if debugEnabled {
            NSLog("📤 WebSocketStreamer sending PCM frame: %d bytes, source: %@", data.count, source)
        }

        // Never pace on the capture thread. Buffer and let the drain loop handle pacing + backpressure.
        enqueueAudioFrame(data, source: source)
    }
    
    // VNI: Send voice note audio data to backend for transcription
    func sendVoiceNoteAudio(data: Data) {
        guard task != nil else {
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("Dropping voice note audio (not connected)", metadata: [
                    "data_size": data.count
                ])
            }
            return
        }
        
        if debugEnabled {
            NSLog("🎤 WebSocketStreamer sending voice note audio: %d bytes", data.count)
        }
        
        let payload: [String: Any] = [
            "type": "voice_note_audio",
            "data": data.base64EncodedString()
        ]
        sendJSON(payload)
    }
    
    // VNI: Start a voice note session
    func startVoiceNoteSession() {
        voiceNoteSessionID = UUID().uuidString
        let payload: [String: Any] = [
            "type": "voice_note_start",
            "session_id": voiceNoteSessionID ?? "",
            "sample_rate": 16000,
            "format": "pcm_s16le",
            "channels": 1
        ]
        sendJSON(payload)
        
        if debugEnabled {
            NSLog("🎤 WebSocketStreamer starting voice note session: %@", voiceNoteSessionID ?? "unknown")
        }
    }
    
    // VNI: Stop the current voice note session
    func stopVoiceNoteSession() {
        let payload: [String: Any] = [
            "type": "voice_note_stop",
            "session_id": voiceNoteSessionID ?? ""
        ]
        sendJSON(payload)
        
        if debugEnabled {
            NSLog("🎤 WebSocketStreamer stopping voice note session: %@", voiceNoteSessionID ?? "unknown")
        }
        
        voiceNoteSessionID = nil
    }

    // OCR: Send client-side OCR text payloads (best-effort)
    func sendOCRText(_ text: String, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let payload: [String: Any] = [
            "type": "ocr_text",
            "text": trimmed,
            "timestamp": timestamp
        ]
        sendJSON(payload)
    }

    private func sendBinaryAudioFrame(_ data: Data, source: String) {
        // Binary audio framing (v1):
        // Header: "EP" + version byte + source byte + raw PCM16 payload.
        // - source byte: 0=system, 1=mic
        let sourceByte: UInt8
        switch source.lowercased() {
        case "mic", "microphone":
            sourceByte = 1
        default:
            sourceByte = 0
        }

        var framed = Data([0x45, 0x50, 0x01, sourceByte]) // "EP", v1, source
        framed.append(data)
        sendBinary(framed, payloadType: "audio_bin_v1")
    }

    private func resetAudioBuffers() {
        audioBufferLock.lock()
        audioBuffersBySource.removeAll()
        audioDropsBySource.removeAll()
        audioBufferLock.unlock()
    }

    private func bufferForSource(_ source: String) -> RingBuffer<PendingAudioFrame> {
        if let existing = audioBuffersBySource[source] {
            return existing
        }
        let buffer = RingBuffer<PendingAudioFrame>(capacity: maxBufferedFramesPerSource)
        audioBuffersBySource[source] = buffer
        return buffer
    }

    private func enqueueAudioFrame(_ data: Data, source: String) {
        // Cheap validation: ignore empty frames.
        guard !data.isEmpty else { return }

        // Estimate sample count from PCM16.
        let samples = max(0, data.count / audioBytesPerSample)
        let frame = PendingAudioFrame(
            data: data,
            source: source,
            sampleCount: samples,
            enqueuedAtUptimeNs: DispatchTime.now().uptimeNanoseconds
        )

        audioBufferLock.lock()
        let buffer = bufferForSource(source)
        let evicted = buffer.pushEvictingOldest(frame)
        if evicted != nil {
            audioDropsBySource[source, default: 0] += 1
            let dropped = audioDropsBySource[source, default: 0]
            audioBufferLock.unlock()
            // Sampled warning to avoid log spam at 50fps.
            StructuredLogger.shared.logSampled(
                level: .warning,
                message: "Audio buffer full; dropping oldest frame to keep near real-time",
                sampleKey: "ws_audio_drop_\(source)",
                sampleRate: 50,
                metadata: [
                    "source": source,
                    "drops_total": dropped,
                    "buffer_capacity_frames": maxBufferedFramesPerSource
                ]
            )
            return
        }
        audioBufferLock.unlock()
    }

    private func popAudioFrame(source: String) -> PendingAudioFrame? {
        audioBufferLock.lock()
        let frame = audioBuffersBySource[source]?.pop()
        audioBufferLock.unlock()
        return frame
    }

    private func startAudioDrainLoop() {
        stopAudioDrainLoop()
        audioDrainTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Per-source pacing (20ms frames at 16kHz, but compute from sampleCount to be robust).
            var nextSendNsBySource: [String: UInt64] = [:]
            let sources = ["system", "mic"]

            while !Task.isCancelled {
                // Don't send audio until:
                // - the socket exists, and
                // - the server has ACKed streaming (ensures "start" processed).
                let acked = await MainActor.run { self.serverStreamingAcked }
                if self.task == nil || acked == false {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    continue
                }

                let nowNs = DispatchTime.now().uptimeNanoseconds
                var didSend = false
                var soonestDueNs: UInt64? = nil

                for source in sources {
                    let dueNs = nextSendNsBySource[source] ?? nowNs
                    soonestDueNs = min(soonestDueNs ?? dueNs, dueNs)
                    guard nowNs >= dueNs else { continue }

                    guard let frame = self.popAudioFrame(source: source) else { continue }
                    didSend = true

                    // Schedule next send for this source based on audio duration.
                    let durationS = Double(frame.sampleCount) / self.audioSampleRate
                    let durationNs = UInt64(max(1.0, durationS * 1_000_000_000.0))
                    let nextNs = max(dueNs, nowNs) &+ durationNs
                    nextSendNsBySource[source] = nextNs
                    soonestDueNs = min(soonestDueNs ?? nextNs, nextNs)

                    if BackendConfig.useBinaryAudioFrames {
                        self.sendBinaryAudioFrame(frame.data, source: frame.source)
                    } else {
                        let payload: [String: Any] = [
                            "type": "audio",
                            "source": frame.source,
                            "data": frame.data.base64EncodedString()
                        ]
                        self.sendJSON(payload)
                    }
                }

                if didSend {
                    // Allow other tasks to run; keep loop responsive.
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    continue
                }

                // Nothing to send; sleep until the soonest due time or a short default.
                let sleepNs: UInt64
                if let due = soonestDueNs, due > nowNs {
                    sleepNs = min(due - nowNs, 20_000_000)
                } else {
                    sleepNs = 10_000_000
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    private func stopAudioDrainLoop() {
        audioDrainTask?.cancel()
        audioDrainTask = nil
    }

    private func sendStart() {
        guard let sessionID else { return }
        if debugEnabled {
            NSLog("WebSocketStreamer: send start")
        }
        
        // V1: Include correlation IDs in start message
        var payload: [String: Any] = [
            "type": "start",
            "session_id": sessionID,
            "sample_rate": 16000,
            "format": "pcm_s16le",
            "channels": 1
        ]

        payload["client_features"] = [
            "clock_drift_compensation_enabled": BackendConfig.clockDriftCompensationEnabled,
            "client_vad_enabled": BackendConfig.clientVADEnabled,
            "clock_drift_telemetry_enabled": true,
            "client_vad_telemetry_enabled": true
        ]
        
        if let correlationIDs = _correlationIDs {
            payload["attempt_id"] = correlationIDs.attemptId
            payload["connection_id"] = correlationIDs.connectionId
        }
        
        Task { @MainActor in
            StructuredLogger.shared.logWebSocketEvent(
                "start",
                connectionId: _correlationIDs?.connectionId ?? "unknown",
                metadata: ["session_id": sessionID]
            )
        }
        
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

    private func sendBinary(_ data: Data, payloadType: String) {
        // If capture starts before the WS task exists (or after it is torn down),
        // do not enqueue sends that will never complete and will back up the send queue.
        guard task != nil else {
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("Dropping WebSocket binary send (not connected)", metadata: [
                    "payload_type": payloadType
                ])
            }
            return
        }

        // P0: Enqueue send instead of blocking capture thread
        guard sendQueue.operationCount < maxQueuedSends else {
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("WebSocket send queue overflow, dropping frame", metadata: [
                    "payload_type": payloadType,
                    "queue_depth": self.sendQueue.operationCount,
                    "max_queue": self.maxQueuedSends
                ])
            }
            return
        }

        sendQueue.addOperation { [weak self] in
            guard let self = self else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var sendError: Error?

            guard let task = self.task else {
                DispatchQueue.main.async {
                    StructuredLogger.shared.warning("Dropping WebSocket binary send (disconnected)", metadata: [
                        "payload_type": payloadType
                    ])
                }
                return
            }

            task.send(.data(data)) { error in
                sendError = error
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + 5)
            if result == .timedOut {
                DispatchQueue.main.async {
                    StructuredLogger.shared.warning("WebSocket send timeout", metadata: [
                        "payload_type": payloadType
                    ])
                }
            }

            if let error = sendError {
                DispatchQueue.main.async {
                    self.handleError(error)
                }
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        // If capture starts before the WS task exists (or after it is torn down),
        // do not enqueue sends that will never complete and will back up the send queue.
        guard task != nil else {
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("Dropping WebSocket send (not connected)", metadata: [
                    "payload_type": payload["type"] as? String ?? "unknown"
                ])
            }
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        // P0: Enqueue send instead of blocking capture thread
        guard sendQueue.operationCount < maxQueuedSends else {
            // Log on main actor
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("WebSocket send queue overflow, dropping frame", metadata: [
                    "queue_depth": self.sendQueue.operationCount,
                    "max_queue": self.maxQueuedSends
                ])
            }
            return
        }
        
        // Capture payload type for logging before capturing self
        let payloadType = payload["type"] as? String ?? "unknown"
        
        sendQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            // Use semaphore to make async send synchronous for queue ordering
            let semaphore = DispatchSemaphore(value: 0)
            var sendError: Error?
            
            guard let task = self.task else {
                DispatchQueue.main.async {
                    StructuredLogger.shared.warning("Dropping WebSocket send (disconnected)", metadata: [
                        "payload_type": payloadType
                    ])
                }
                return
            }

            task.send(.string(text)) { error in
                sendError = error
                semaphore.signal()
            }
            
            // Wait up to 5 seconds for send to complete
            let result = semaphore.wait(timeout: .now() + 5)
            
            if result == .timedOut {
                DispatchQueue.main.async {
                    StructuredLogger.shared.warning("WebSocket send timeout", metadata: [
                        "payload_type": payloadType
                    ])
                }
            }
            
            if let error = sendError {
                DispatchQueue.main.async {
                    self.handleError(error)
                }
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
        case .data(let data):
            handleJSON(data)
        @unknown default:
            break
        }
    }
    
    // MARK: - Public Message Handler (for ResilientWebSocket integration)
    
    /// Handle raw message data from any source (used by ResilientWebSocket adapter)
    func handleMessageData(_ data: Data) {
        handleJSON(data)
    }

    private func handleJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = object["type"] as? String else { return }

        // V1: Drop late/out-of-order messages from previous start attempts.
        if let msgAttempt = object["attempt_id"] as? String,
           let expected = self.attemptID,
           !msgAttempt.isEmpty,
           msgAttempt != expected {
            DispatchQueue.main.async {
                StructuredLogger.shared.warning("Dropping WS message for mismatched attempt_id", metadata: [
                    "type": type,
                    "expected_attempt_id": expected,
                    "message_attempt_id": msgAttempt
                ])
            }
            return
        }

        switch type {
        case "status":
            let state = (object["state"] as? String) ?? "error"
            let message = (object["message"] as? String) ?? ""
            DispatchQueue.main.async {
                switch state {
                case "streaming", "backpressure", "warning", "buffering", "overloaded":
                    self.serverStreamingAcked = true
                    self.onStatus?(.streaming, message)
                case "connected", "connecting", "preparing", "reconnecting":
                    self.serverStreamingAcked = false
                    // Server uses "connected" while waiting for the client "start" message.
                    // Treating this as an error causes the mac client to abort a session immediately.
                    self.onStatus?(.reconnecting, message)
                case "error":
                    self.serverStreamingAcked = false
                    self.onStatus?(.error, message)
                default:
                    self.serverStreamingAcked = false
                    self.onStatus?(.error, message)
                }
            }

        case "asr_partial":
            let text = (object["text"] as? String) ?? ""
            let t0 = (object["t0"] as? TimeInterval) ?? 0
            let t1 = (object["t1"] as? TimeInterval) ?? 0
            let confidence = (object["confidence"] as? Double) ?? 0.6
            let source = object["source"] as? String
            DispatchQueue.main.async {
                self.onASRPartial?(text, t0, t1, confidence, source)
            }

        case "asr_final":
            let text = (object["text"] as? String) ?? ""
            let t0 = (object["t0"] as? TimeInterval) ?? 0
            let t1 = (object["t1"] as? TimeInterval) ?? 0
            let confidence = (object["confidence"] as? Double) ?? 0.9
            let source = object["source"] as? String
            DispatchQueue.main.async {
                self.onASRFinal?(text, t0, t1, confidence, source)
            }

        case "cards_update":
            let actions = decodeActionItems(object["actions"])
            let decisions = decodeDecisionItems(object["decisions"])
            let risks = decodeRiskItems(object["risks"])
            DispatchQueue.main.async {
                self.onCardsUpdate?(actions, decisions, risks)
            }

        case "entities_update":
            let entities = decodeEntityItems(object)
            DispatchQueue.main.async {
                self.onEntitiesUpdate?(entities)
            }

        case "final_summary":
            let markdown = (object["markdown"] as? String) ?? ""
            let jsonObject = (object["json"] as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                self.onFinalSummary?(markdown, jsonObject)
                if let waiter = self.finalSummaryWaiter {
                    self.finalSummaryWaiter = nil
                    waiter.resume(returning: true)
                }
            }

        case "metrics":
            // PR2: Parse metrics message
            // V1: Include correlation IDs from server response
            let metrics = SourceMetrics(
                source: object["source"] as? String ?? "",
                queueDepth: object["queue_depth"] as? Int ?? 0,
                queueMax: object["queue_max"] as? Int ?? 1,
                queueFillRatio: object["queue_fill_ratio"] as? Double ?? 0.0,
                droppedTotal: object["dropped_total"] as? Int ?? 0,
                droppedRecent: object["dropped_recent"] as? Int ?? 0,
                avgInferMs: object["avg_infer_ms"] as? Double ?? 0.0,
                realtimeFactor: object["realtime_factor"] as? Double ?? 0.0,
                timestamp: object["timestamp"] as? TimeInterval ?? 0,
                connectionId: object["connection_id"] as? String ?? self._correlationIDs?.connectionId,
                sessionId: object["session_id"] as? String ?? self.sessionID,
                attemptId: object["attempt_id"] as? String ?? self.attemptID,
                clientVadEnabled: object["client_vad_enabled"] as? Bool ?? false,
                speechChunksEmitted: object["speech_chunks_emitted"] as? Int ?? 0,
                totalChunksProcessed: object["total_chunks_processed"] as? Int ?? 0,
                speechRatio: object["speech_ratio"] as? Double ?? 0.0
            )
            DispatchQueue.main.async {
                self.onMetrics?(metrics)
            }

        case "voice_note_transcript":
            // VNI: Handle voice note transcript from backend
            let text = (object["text"] as? String) ?? ""
            let duration = (object["duration"] as? TimeInterval) ?? 0
            if debugEnabled {
                NSLog("🎤 WebSocketStreamer received voice note transcript: %d chars", text.count)
            }
            DispatchQueue.main.async {
                self.onVoiceNoteTranscript?(text, duration)
            }

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
                        count: (entity["count"] as? Int) ?? 0,
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
        DispatchQueue.main.async {
            self.onStatus?(.reconnecting, error.localizedDescription)
        }
        reconnect()
    }

    private func reconnect() {
        guard let sessionID else { return }
        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            stopPing()
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            DispatchQueue.main.async {
                self.onStatus?(.error, "Connection lost. Unable to reconnect (attempts=\(self.reconnectAttempts)).")
            }
            return
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        stopPing()

        let delay = min(reconnectDelay, maxReconnectDelay)
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            // Preserve attempt ID across reconnects to keep correlation stable for the UI.
            self.connect(sessionID: sessionID, attemptID: self.attemptID)
        }
    }

    private func schedulePing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let lastPong = self.lastPongTime,
               Date().timeIntervalSince(lastPong) > self.pongTimeout {
                self.handleError(NSError(domain: "WebSocketStreamer", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "Pong timeout"]))
                return
            }
            self.task?.sendPing { error in
                if let error {
                    self.handleError(error)
                } else {
                    self.lastPongTime = Date()
                }
            }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
}