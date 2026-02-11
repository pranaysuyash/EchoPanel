//
//  ResilientWebSocket.swift
//  MeetingListenerApp
//
//  PR6: WebSocket Reconnect Resilience + Circuit Breaker
//  Implements exponential backoff with jitter, circuit breaker pattern,
//  max retry limits, and message buffering for safety.
//

import Foundation
import Combine

// MARK: - Circuit Breaker

/// Circuit breaker pattern to prevent infinite retry loops
enum CircuitState {
    case closed      // Normal operation, requests allowed
    case open        // Failure threshold exceeded, requests blocked
    case halfOpen    // Testing if service recovered
}

final class CircuitBreaker {
    private let failureThreshold: Int
    private let recoveryTimeout: TimeInterval
    
    private(set) var state: CircuitState = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    
    init(failureThreshold: Int = 5, recoveryTimeout: TimeInterval = 60) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
    }
    
    /// Check if request should be allowed
    var canExecute: Bool {
        switch state {
        case .closed:
            return true
        case .open:
            // Check if recovery timeout has passed
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= recoveryTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
    
    /// Record a successful request
    func recordSuccess() {
        failureCount = 0
        state = .closed
    }
    
    /// Record a failed request
    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
    
    /// Reset to closed state
    func reset() {
        state = .closed
        failureCount = 0
        lastFailureTime = nil
    }
}

// MARK: - Message Buffer

/// Circular buffer for queuing messages during disconnections
final class MessageBuffer<T> {
    private let capacity: Int
    private var buffer: [T] = []
    private let ttl: TimeInterval
    private var timestamps: [Date] = []
    
    init(capacity: Int, ttl: TimeInterval) {
        self.capacity = capacity
        self.ttl = ttl
    }
    
    /// Add item to buffer, returns true if added, false if dropped
    @discardableResult
    func append(_ item: T) -> Bool {
        // Clean expired items first
        cleanExpired()
        
        // Drop oldest if at capacity
        if buffer.count >= capacity {
            buffer.removeFirst()
            timestamps.removeFirst()
        }
        
        buffer.append(item)
        timestamps.append(Date())
        return true
    }
    
    /// Get all buffered items and clear buffer
    func flush() -> [T] {
        cleanExpired()
        let items = buffer
        buffer.removeAll()
        timestamps.removeAll()
        return items
    }
    
    /// Check if buffer has items
    var isEmpty: Bool {
        cleanExpired()
        return buffer.isEmpty
    }
    
    /// Current count of items
    var count: Int {
        cleanExpired()
        return buffer.count
    }
    
    private func cleanExpired() {
        let now = Date()
        while let firstTimestamp = timestamps.first,
              now.timeIntervalSince(firstTimestamp) > ttl {
            buffer.removeFirst()
            timestamps.removeFirst()
        }
    }
}

// MARK: - Exponential Backoff

/// Exponential backoff with jitter for reconnection delays
struct ExponentialBackoff {
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitterFactor: Double  // 0.0 to 1.0
    
    func delay(forAttempt attempt: Int) -> TimeInterval {
        // Exponential: 1s, 2s, 4s, 8s, ... up to max
        let exponential = min(initialDelay * pow(2.0, Double(attempt)), maxDelay)
        
        // Add jitter: ±jitterFactor * delay
        let jitterRange = exponential * jitterFactor
        let jitter = Double.random(in: -jitterRange...jitterRange)
        
        return max(0.1, exponential + jitter)  // Minimum 100ms
    }
}

// MARK: - Reconnection Configuration

struct ReconnectionConfiguration {
    let maxAttempts: Int
    let backoff: ExponentialBackoff
    let circuitBreaker: CircuitBreaker
    let messageBufferCapacity: Int
    let messageBufferTTL: TimeInterval
    
    static let `default` = ReconnectionConfiguration(
        maxAttempts: 15,
        backoff: ExponentialBackoff(
            initialDelay: 1.0,
            maxDelay: 60.0,
            jitterFactor: 0.2  // ±20% jitter
        ),
        circuitBreaker: CircuitBreaker(
            failureThreshold: 5,
            recoveryTimeout: 60
        ),
        messageBufferCapacity: 1000,
        messageBufferTTL: 30  // 30 seconds
    )
    
    static let aggressive = ReconnectionConfiguration(
        maxAttempts: 5,
        backoff: ExponentialBackoff(
            initialDelay: 0.5,
            maxDelay: 10.0,
            jitterFactor: 0.3
        ),
        circuitBreaker: CircuitBreaker(
            failureThreshold: 3,
            recoveryTimeout: 30
        ),
        messageBufferCapacity: 500,
        messageBufferTTL: 15
    )
}

// MARK: - Connection State

enum ResilientConnectionState: Equatable {
    case disconnected
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int, delay: TimeInterval)
    case circuitOpen(until: Date)
    case permanentlyFailed
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}

// MARK: - Resilient WebSocket

/// Enhanced WebSocket with automatic reconnection, circuit breaker, and message buffering
@MainActor
final class ResilientWebSocket: NSObject {
    // MARK: - Callbacks
    var onStateChange: ((ResilientConnectionState) -> Void)?
    var onMessage: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    
    // MARK: - Properties
    private let url: URL
    private let configuration: ReconnectionConfiguration
    private let session: URLSession
    
    private var task: URLSessionWebSocketTask?
    private var state: ResilientConnectionState = .disconnected {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }
    
    // Reconnection state
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    
    // Circuit breaker
    private var circuitBreaker: CircuitBreaker { configuration.circuitBreaker }
    
    // Message buffer for audio/data during disconnections
    private var messageBuffer: MessageBuffer<Data>
    
    // Ping/Pong for connection health
    private var pingTimer: Timer?
    private var lastPongTime: Date?
    private let pongTimeout: TimeInterval = 15  // Consider connection dead if no pong for 15s
    
    // Connection ID for logging
    private var connectionId: String = ""
    
    // MARK: - Initialization
    init(url: URL, configuration: ReconnectionConfiguration = .default) {
        self.url = url
        self.configuration = configuration
        self.session = URLSession(configuration: .default)
        self.messageBuffer = MessageBuffer<Data>(
            capacity: configuration.messageBufferCapacity,
            ttl: configuration.messageBufferTTL
        )
        super.init()
    }
    
    // MARK: - Connection Control
    
    func connect() {
        guard !state.isConnected else { return }
        
        // Check circuit breaker
        guard circuitBreaker.canExecute else {
            state = .circuitOpen(until: Date().addingTimeInterval(60))
            scheduleCircuitBreakerCheck()
            return
        }
        
        // Cancel any pending reconnect
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        
        connectionId = UUID().uuidString
        state = .connecting(attempt: reconnectAttempt)
        
        // Close existing task
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        
        // Create new connection
        task = session.webSocketTask(with: url)
        task?.resume()
        
        receiveLoop()
        schedulePing()
    }
    
    func disconnect() {
        // Cancel any pending reconnect
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        
        // Close connection
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        
        stopPing()
        
        // Clear buffer
        _ = messageBuffer.flush()
        
        state = .disconnected
        reconnectAttempt = 0
        circuitBreaker.reset()
    }
    
    /// Force immediate reconnect (for manual retry button)
    func forceReconnect() {
        reconnectAttempt = 0
        circuitBreaker.reset()
        connect()
    }
    
    // MARK: - Sending Data
    
    func send(_ data: Data) {
        if state.isConnected {
            // Send immediately
            sendImmediately(data)
        } else {
            // Buffer for later
            let added = messageBuffer.append(data)
            if !added {
                NSLog("ResilientWebSocket: Message buffer full, dropping data")
            }
        }
    }
    
    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }
    
    private func sendImmediately(_ data: Data) {
        task?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.handleSendError(error)
            }
        }
    }
    
    /// Flush buffered messages after reconnection
    private func flushBuffer() {
        let buffered = messageBuffer.flush()
        guard !buffered.isEmpty else { return }
        
        NSLog("ResilientWebSocket: Flushing %d buffered messages", buffered.count)
        
        for data in buffered {
            sendImmediately(data)
        }
    }
    
    // MARK: - Receiving
    
    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveLoop()  // Continue receiving
                    
                case .failure(let error):
                    self.handleError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            onMessage?(data)
        case .string(let text):
            if let data = text.data(using: .utf8) {
                onMessage?(data)
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ error: Error) {
        NSLog("ResilientWebSocket: Error - %@", error.localizedDescription)
        onError?(error)
        
        // Record failure in circuit breaker
        circuitBreaker.recordFailure()
        
        // Attempt reconnect if appropriate
        attemptReconnect(error: error)
    }
    
    private func handleSendError(_ error: Error) {
        // Check if connection is dead
        if isConnectionDead() {
            handleError(error)
        }
    }
    
    private func isConnectionDead() -> Bool {
        guard let lastPong = lastPongTime else {
            return false  // No pong yet, give it time
        }
        return Date().timeIntervalSince(lastPong) > pongTimeout
    }
    
    // MARK: - Reconnection Logic
    
    private func attemptReconnect(error: Error) {
        // Check if error is retriable
        guard isRetriableError(error) else {
            state = .permanentlyFailed
            return
        }
        
        // Check max attempts
        guard reconnectAttempt < configuration.maxAttempts else {
            NSLog("ResilientWebSocket: Max reconnection attempts (%d) exceeded", configuration.maxAttempts)
            state = .permanentlyFailed
            return
        }
        
        // Check circuit breaker
        guard circuitBreaker.canExecute else {
            state = .circuitOpen(until: Date().addingTimeInterval(60))
            scheduleCircuitBreakerCheck()
            return
        }
        
        // Calculate backoff delay
        let delay = configuration.backoff.delay(forAttempt: reconnectAttempt)
        reconnectAttempt += 1
        
        state = .reconnecting(attempt: reconnectAttempt, delay: delay)
        
        NSLog("ResilientWebSocket: Reconnecting in %.1fs (attempt %d/%d)",
              delay, reconnectAttempt, configuration.maxAttempts)
        
        // Schedule reconnect
        let workItem = DispatchWorkItem { [weak self] in
            self?.connect()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func isRetriableError(_ error: Error) -> Bool {
        // Check for fatal errors
        let nsError = error as NSError
        
        // Don't retry on authentication errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorUserCancelledAuthentication,
                 NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return false
            default:
                return true
            }
        }
        
        return true
    }
    
    private func onConnectionSuccess() {
        circuitBreaker.recordSuccess()
        reconnectAttempt = 0
        state = .connected
        lastPongTime = Date()
        
        // Flush any buffered messages
        flushBuffer()
    }
    
    // MARK: - Circuit Breaker Recovery
    
    private func scheduleCircuitBreakerCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            if self.circuitBreaker.canExecute && !self.state.isConnected {
                self.connect()
            }
        }
    }
    
    // MARK: - Ping/Pong
    
    private func schedulePing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            
            // Check if we've missed pongs
            if let lastPong = self.lastPongTime,
               Date().timeIntervalSince(lastPong) > self.pongTimeout {
                NSLog("ResilientWebSocket: Pong timeout, connection may be dead")
                self.handleError(NSError(domain: "ResilientWebSocket", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "Pong timeout"]))
                return
            }
            
            // Send ping
            self.task?.sendPing { [weak self] error in
                if let error = error {
                    NSLog("ResilientWebSocket: Ping failed - %@", error.localizedDescription)
                } else {
                    self?.lastPongTime = Date()
                }
            }
        }
    }
    
    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
}

// MARK: - Integration with Existing WebSocketStreamer

extension WebSocketStreamer {
    /// Create a resilient wrapper around this streamer
    @MainActor
    func makeResilient() -> ResilientWebSocketAdapter {
        return ResilientWebSocketAdapter(streamer: self)
    }
}

/// Adapter to bridge ResilientWebSocket with existing WebSocketStreamer
@MainActor
final class ResilientWebSocketAdapter {
    private let resilientSocket: ResilientWebSocket
    private var cancellables = Set<AnyCancellable>()
    private let streamer: WebSocketStreamer
    
    @MainActor
    init(streamer: WebSocketStreamer) {
        self.streamer = streamer
        self.resilientSocket = ResilientWebSocket(
            url: BackendConfig.webSocketURL,
            configuration: .default
        )
        
        // Forward callbacks
        resilientSocket.onMessage = { [weak streamer] data in
            // Parse and forward to streamer callbacks
            Task { @MainActor in
                streamer?.handleMessageData(data)
            }
        }
    }
    
    func connect(sessionID: String) {
        resilientSocket.connect()
    }
    
    func disconnect() {
        resilientSocket.disconnect()
    }
    
    func sendPCMFrame(_ data: Data, source: String = "system") {
        let payload: [String: Any] = [
            "type": "audio",
            "source": source,
            "data": data.base64EncodedString()
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        resilientSocket.send(jsonData)
    }
}
