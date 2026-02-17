import Foundation

// MARK: - Python Backend

/// ASR backend that connects to Python WebSocket server
public actor PythonBackend: ASRBackend {
    
    // MARK: - Properties
    
    public nonisolated let name: String = "Python Server"
    
    public nonisolated var isAvailable: Bool {
        // Check without accessing actor-isolated state
        return true  // Assume available, actual check done in initialize
    }
    
    public private(set) var status: BackendStatus = BackendStatus(
        backendName: "Python Server",
        state: .unknown
    )
    
    public nonisolated let capabilities: BackendCapabilities = BackendCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        supportsDiarization: true,
        supportsOffline: false,
        requiresNetwork: true,
        supportedLanguages: Language.allCases,
        estimatedRTF: 0.15
    )
    
    // MARK: - WebSocket
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected: Bool = false
    private var serverURL: URL
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 3
    
    // MARK: - Streaming
    
    private var isStreaming: Bool = false
    private var streamingContinuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation?
    private var audioBuffer: Data = Data()
    private let bufferLock = NSLock()
    
    // MARK: - Metrics
    
    private var metrics = PerformanceMetrics()
    
    // MARK: - Configuration
    
    public var serverHost: String = "localhost"
    public var serverPort: Int = 8000
    public var connectionTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    public init(serverHost: String = "localhost", serverPort: Int = 8000) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.serverURL = URL(string: "ws://\(serverHost):\(serverPort)/ws/transcribe")!
    }
    
    // MARK: - ASRBackend Protocol
    
    public func initialize() async throws {
        await updateStatus(.initializing, message: "Connecting to Python server...")
        
        do {
            try await connect()
            await updateStatus(.ready, message: "Connected to server")
            
            if FeatureFlagManager.shared.enableVerboseLogging {
                print("✅ Python Backend: Connected to \(serverURL)")
            }
            
        } catch {
            await updateStatus(.error, message: "Connection failed: \(error.localizedDescription)")
            throw ASRError.initializationFailed(reason: "WebSocket connection failed: \(error)")
        }
    }
    
    public func transcribe(audio: Data, config: TranscriptionConfig) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw ASRError.backendNotAvailable(backend: name)
        }
        
        let startTime = Date()
        
        // Send audio to server
        let request: [String: Any] = [
            "type": "transcribe",
            "audio": audio.base64EncodedString(),
            "language": config.language.rawValue,
            "diarize": config.enableDiarization,
            "punctuation": config.enablePunctuation,
            "timestamps": config.enableTimestamps,
            "custom_vocabulary": config.customVocabulary
        ]
        
        let requestData = try JSONSerialization.data(withJSONObject: request)
        
        // Send and wait for response
        try await sendMessage(requestData)
        
        // Wait for response (simplified - in real implementation use request/response correlation)
        let response = try await waitForResponse(timeout: 30.0)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // Parse response
        guard let text = response["text"] as? String else {
            throw ASRError.transcriptionFailed(reason: "Invalid response format")
        }
        
        let segments = parseSegments(from: response)
        let duration = response["duration"] as? TimeInterval ?? 0
        let confidence = response["confidence"] as? Double ?? 0.9
        
        let result = TranscriptionResult(
            segments: segments,
            fullText: text,
            duration: duration,
            processingTime: processingTime,
            backendName: name,
            language: config.language,
            confidence: confidence
        )
        
        // Update metrics
        metrics.recordSuccess(duration: duration, processingTime: processingTime, confidence: confidence)
        
        return result
    }
    
    public func startStreaming(config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            self.streamingContinuation = continuation
            
            Task {
                do {
                    guard self.isAvailable else {
                        throw ASRError.backendNotAvailable(backend: self.name)
                    }
                    
                    self.isStreaming = true
                    continuation.yield(.started)
                    
                    // Send start streaming message
                    let startMessage: [String: Any] = [
                        "type": "start_stream",
                        "language": config.language.rawValue,
                        "diarize": config.enableDiarization,
                        "punctuation": config.enablePunctuation
                    ]
                    let messageData = try JSONSerialization.data(withJSONObject: startMessage)
                    try await self.sendMessage(messageData)
                    
                    // Start receiving messages
                    await self.receiveMessages(continuation: continuation)
                    
                } catch {
                    continuation.yield(.error(ASRError.streamingError(error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func stopStreaming() async {
        isStreaming = false
        
        do {
            let stopMessage: [String: Any] = ["type": "stop_stream"]
            let messageData = try JSONSerialization.data(withJSONObject: stopMessage)
            try await sendMessage(messageData)
        } catch {
            if FeatureFlagManager.shared.enableVerboseLogging {
                print("Python Backend: Error sending stop: \(error)")
            }
        }
        
        streamingContinuation?.finish()
        streamingContinuation = nil
    }
    
    public func health() async -> BackendStatus {
        var updatedStatus = status
        updatedStatus.performanceMetrics = metrics
        return updatedStatus
    }
    
    public func unload() async {
        await stopStreaming()
        disconnect()
        await updateStatus(.unknown, message: "Disconnected")
    }
    
    // MARK: - WebSocket Helpers
    
    private func connect() async throws {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: serverURL)
        
        // Set up message handler
        receiveMessage()
        
        webSocketTask?.resume()
        
        // Wait for connection
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        if webSocketTask?.state != .running {
            throw ASRError.networkError(NSError(domain: "WebSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"]))
        }
        
        isConnected = true
        reconnectAttempts = 0
    }
    
    private func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    private func reconnect() async throws {
        guard reconnectAttempts < maxReconnectAttempts else {
            throw ASRError.networkError(NSError(domain: "WebSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max reconnect attempts reached"]))
        }
        
        reconnectAttempts += 1
        
        if FeatureFlagManager.shared.enableVerboseLogging {
            print("Python Backend: Reconnecting (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")
        }
        
        disconnect()
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
        try await connect()
    }
    
    private func sendMessage(_ data: Data) async throws {
        guard isConnected else {
            throw ASRError.networkError(NSError(domain: "WebSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
        }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask?.send(message)
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                Task {
                    await self.handleMessage(message)
                    // Continue receiving
                    if await self.isConnected {
                        await self.receiveMessage()
                    }
                }
                
            case .failure(let error):
                Task {
                    await self.handleError(error)
                }
            }
        }
    }
    
    private func receiveMessages(continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async {
        while isStreaming && isConnected {
            do {
                let message = try await webSocketTask?.receive()
                if let message = message {
                    await handleStreamMessage(message, continuation: continuation)
                }
            } catch {
                continuation.yield(.error(ASRError.streamingError(error.localizedDescription)))
                break
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .data(let data):
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let json = json {
                    await handleServerMessage(json)
                }
            } catch {
                if FeatureFlagManager.shared.enableVerboseLogging {
                    print("Python Backend: Failed to parse message: \(error)")
                }
            }
            
        case .string(let text):
            do {
                let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
                if let json = json {
                    await handleServerMessage(json)
                }
            } catch {
                if FeatureFlagManager.shared.enableVerboseLogging {
                    print("Python Backend: Failed to parse message: \(error)")
                }
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleStreamMessage(_ message: URLSessionWebSocketTask.Message, continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async {
        switch message {
        case .data(let data):
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let json = json {
                    await handleStreamingServerMessage(json, continuation: continuation)
                }
            } catch {
                continuation.yield(.error(ASRError.streamingError("Parse error: \(error)")))
            }
            
        case .string(let text):
            do {
                let json = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any]
                if let json = json {
                    await handleStreamingServerMessage(json, continuation: continuation)
                }
            } catch {
                continuation.yield(.error(ASRError.streamingError("Parse error: \(error)")))
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleServerMessage(_ message: [String: Any]) async {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "status":
            if let status = message["status"] as? String {
                if status == "ready" {
                    isConnected = true
                }
            }
            
        case "error":
            if let errorMsg = message["message"] as? String {
                metrics.recordError(errorMsg)
                if FeatureFlagManager.shared.enableVerboseLogging {
                    print("Python Backend: Server error: \(errorMsg)")
                }
            }
            
        default:
            break
        }
    }
    
    private func handleStreamingServerMessage(_ message: [String: Any], continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation) async {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "partial":
            if let text = message["text"] as? String,
               let confidence = message["confidence"] as? Double {
                continuation.yield(.partial(text: text, confidence: confidence))
            }
            
        case "final":
            if let text = message["text"] as? String {
                let segment = TranscriptionSegment(
                    text: text,
                    startTime: message["start_time"] as? TimeInterval ?? 0,
                    endTime: message["end_time"] as? TimeInterval ?? 0,
                    confidence: message["confidence"] as? Double ?? 0.9,
                    speakerId: message["speaker_id"] as? String,
                    isFinal: true
                )
                continuation.yield(.final(segment: segment))
            }
            
        case "complete":
            if let result = message["result"] as? [String: Any] {
                let transcriptionResult = parseResult(from: result)
                continuation.yield(.completed(result: transcriptionResult))
                continuation.finish()
            }
            
        case "error":
            if let errorMsg = message["message"] as? String {
                continuation.yield(.error(ASRError.streamingError(errorMsg)))
                continuation.finish()
            }
            
        default:
            break
        }
    }
    
    private func handleError(_ error: Error) async {
        isConnected = false
        metrics.recordError(error.localizedDescription)
        
        if FeatureFlagManager.shared.enableVerboseLogging {
            print("Python Backend: Error: \(error)")
        }
        
        // Attempt reconnect if appropriate
        if reconnectAttempts < maxReconnectAttempts {
            do {
                try await reconnect()
            } catch {
                await updateStatus(.error, message: "Connection lost")
            }
        } else {
            await updateStatus(.error, message: "Connection lost")
        }
    }
    
    private func updateStatus(_ state: BackendState, message: String? = nil) async {
        status = BackendStatus(
            backendName: name,
            state: state,
            message: message,
            capabilities: capabilities
        )
    }
    
    // MARK: - Response Handling
    
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [: ]
    private var responseIdCounter: Int = 0
    
    private func waitForResponse(timeout: TimeInterval) async throws -> [String: Any] {
        let responseId = "\(responseIdCounter)"
        responseIdCounter += 1
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[responseId] = continuation
            
            // Timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let cont = pendingResponses.removeValue(forKey: responseId) {
                    cont.resume(throwing: ASRError.networkError(NSError(domain: "Timeout", code: -1)))
                }
            }
        }
    }
    
    private func parseSegments(from response: [String: Any]) -> [TranscriptionSegment] {
        guard let segmentsData = response["segments"] as? [[String: Any]] else {
            return []
        }
        
        return segmentsData.compactMap { data in
            guard let text = data["text"] as? String else { return nil }
            
            return TranscriptionSegment(
                text: text,
                startTime: data["start"] as? TimeInterval ?? 0,
                endTime: data["end"] as? TimeInterval ?? 0,
                confidence: data["confidence"] as? Double ?? 0.9,
                speakerId: data["speaker"] as? String,
                isFinal: true
            )
        }
    }
    
    private func parseResult(from response: [String: Any]) -> TranscriptionResult {
        let segments = parseSegments(from: response)
        let text = response["text"] as? String ?? segments.map { $0.text }.joined(separator: " ")
        
        let detectedLanguage = response["language"] as? String
        let language = Language(rawValue: detectedLanguage ?? "en") ?? .english

        return TranscriptionResult(
            segments: segments,
            fullText: text,
            duration: response["duration"] as? TimeInterval ?? 0,
            processingTime: response["processing_time"] as? TimeInterval ?? 0,
            backendName: name,
            language: language,
            confidence: response["confidence"] as? Double ?? 0.9
        )
    }
}
