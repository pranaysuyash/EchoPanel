# WebSocket Reconnection Resilience: Best Practices Research

> **Document Type**: Technical Research  
> **Scope**: Client and server patterns for robust WebSocket connections  
> **Last Updated**: 2026-02-10

---

## Executive Summary

WebSocket connections are inherently fragile. Network interruptions, server restarts, load balancer timeouts, and mobile network switches can terminate connections without warning. A production-grade WebSocket implementation must handle failures gracefully, maintaining data integrity and providing a seamless user experience.

This document covers battle-tested patterns for building resilient WebSocket clients and servers, with concrete implementations for **Swift (macOS/iOS)** and **Python (FastAPI)**.

---

## 1. Reconnection Strategies

### 1.1 Exponential Backoff with Jitter

**Why**: Immediately retrying can overwhelm the server ("thundering herd" problem) and waste client resources. Exponential backoff spaces out retries, while jitter prevents synchronized reconnection storms.

**Algorithm**:
```
delay = min(baseDelay * 2^attempt + jitter, maxDelay)
```

**Swift Implementation**:

```swift
import Foundation

/// Configuration for exponential backoff
struct BackoffConfiguration {
    let baseDelay: TimeInterval      // Initial delay (default: 1.0s)
    let maxDelay: TimeInterval       // Maximum cap (default: 30.0s)
    let multiplier: Double           // Growth factor (default: 2.0)
    let jitterFactor: Double         // Randomization (0-1, default: 0.1)
}

/// Exponential backoff calculator with jitter
final class ExponentialBackoff {
    private var attempt: Int = 0
    private let config: BackoffConfiguration
    
    init(config: BackoffConfiguration = BackoffConfiguration(
        baseDelay: 1.0,
        maxDelay: 30.0,
        multiplier: 2.0,
        jitterFactor: 0.1
    )) {
        self.config = config
    }
    
    /// Calculate next delay and increment attempt counter
    func nextDelay() -> TimeInterval {
        let exponentialDelay = config.baseDelay * pow(config.multiplier, Double(attempt))
        let cappedDelay = min(exponentialDelay, config.maxDelay)
        let jitter = cappedDelay * config.jitterFactor * Double.random(in: 0...1)
        
        attempt += 1
        return cappedDelay + jitter
    }
    
    /// Reset after successful connection
    func reset() {
        attempt = 0
    }
    
    var currentAttempt: Int { attempt }
}

// Example delay progression:
// Attempt 0: ~1.0s  (base)
// Attempt 1: ~2.1s  (2x + jitter)
// Attempt 2: ~4.0s  (4x + jitter)
// Attempt 3: ~8.2s  (8x + jitter)
// Attempt 4: ~16.1s (16x + jitter)
// Attempt 5+: ~30s+ (capped + jitter)
```

**Python Implementation**:

```python
import random
import asyncio
from dataclasses import dataclass


@dataclass
class BackoffConfig:
    base_delay: float = 1.0      # Initial delay in seconds
    max_delay: float = 30.0      # Maximum delay cap
    multiplier: float = 2.0      # Exponential growth factor
    jitter_factor: float = 0.1   # Randomization factor (0-1)


class ExponentialBackoff:
    """Exponential backoff with jitter for reconnection delays."""
    
    def __init__(self, config: BackoffConfig = None):
        self.config = config or BackoffConfig()
        self._attempt = 0
    
    def next_delay(self) -> float:
        """Calculate next delay with exponential growth and jitter."""
        exponential = self.config.base_delay * (self.config.multiplier ** self._attempt)
        capped = min(exponential, self.config.max_delay)
        jitter = capped * self.config.jitter_factor * random.random()
        
        self._attempt += 1
        return capped + jitter
    
    def reset(self) -> None:
        """Reset attempt counter after successful connection."""
        self._attempt = 0
    
    @property
    def current_attempt(self) -> int:
        return self._attempt
```

### 1.2 Circuit Breaker Pattern

**Why**: Prevents cascading failures by stopping reconnection attempts when the server is clearly unavailable (e.g., during maintenance or outage).

**States**:
- **CLOSED**: Normal operation, requests flow through
- **OPEN**: Too many failures detected, fast-fail without attempting connection
- **HALF_OPEN**: Testing if service has recovered with limited requests

**Swift Implementation**:

```swift
import Foundation

enum CircuitState {
    case closed        // Normal operation
    case open          // Failing, reject requests
    case halfOpen      // Testing recovery
}

struct CircuitBreakerConfig {
    let failureThreshold: Int        // Failures before opening (default: 5)
    let successThreshold: Int        // Successes to close from half-open (default: 2)
    let openTimeout: TimeInterval    // Time before half-open (default: 30s)
}

/// Circuit breaker for WebSocket connections
final class CircuitBreaker {
    private var state: CircuitState = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: Date?
    private let config: CircuitBreakerConfig
    private let queue = DispatchQueue(label: "circuit-breaker", attributes: .concurrent)
    
    init(config: CircuitBreakerConfig = CircuitBreakerConfig()) {
        self.config = config
    }
    
    /// Check if operation should be allowed
    var canAttempt: Bool {
        queue.sync {
            switch state {
            case .closed:
                return true
            case .open:
                // Check if we should transition to half-open
                if let lastFailure = lastFailureTime,
                   Date().timeIntervalSince(lastFailure) >= config.openTimeout {
                    state = .halfOpen
                    successCount = 0
                    return true
                }
                return false
            case .halfOpen:
                return true
            }
        }
    }
    
    /// Record successful operation
    func recordSuccess() {
        queue.async(flags: .barrier) {
            switch self.state {
            case .closed:
                self.failureCount = 0
            case .halfOpen:
                self.successCount += 1
                if self.successCount >= self.config.successThreshold {
                    self.state = .closed
                    self.failureCount = 0
                }
            case .open:
                break
            }
        }
    }
    
    /// Record failed operation
    func recordFailure() {
        queue.async(flags: .barrier) {
            switch self.state {
            case .closed:
                self.failureCount += 1
                if self.failureCount >= self.config.failureThreshold {
                    self.state = .open
                    self.lastFailureTime = Date()
                }
            case .halfOpen:
                self.state = .open
                self.lastFailureTime = Date()
            case .open:
                break
            }
        }
    }
    
    var currentState: CircuitState {
        queue.sync { state }
    }
    
    /// Reset circuit breaker (e.g., user-initiated retry)
    func reset() {
        queue.async(flags: .barrier) {
            self.state = .closed
            self.failureCount = 0
            self.successCount = 0
            self.lastFailureTime = nil
        }
    }
}
```

### 1.3 Maximum Retry Limits

**Why**: Prevents infinite reconnection loops and allows graceful degradation (e.g., showing offline UI).

**Strategy**:
- Use **attempt-based limits** for initial connections (e.g., 10-15 attempts)
- Use **time-based limits** for established sessions (e.g., retry for 5 minutes)
- Distinguish between **retriable** and **fatal** errors

**Error Classification**:

| Error Type | Retriable? | Example |
|------------|-----------|---------|
| Network timeout | ✅ Yes | WiFi disconnected temporarily |
| Connection refused | ✅ Yes | Server restarting |
| 5xx server error | ✅ Yes | Temporary server overload |
| Authentication failure | ❌ No | Invalid token |
| Protocol error | ❌ No | Incompatible client/server |
| 404 Not Found | ❌ No | Endpoint doesn't exist |

**Swift Implementation**:

```swift
enum WebSocketError: Error {
    case retriable(underlying: Error)
    case fatal(underlying: Error)
    case maxRetriesExceeded
}

/// Categorizes errors for retry decisions
func categorizeError(_ error: Error) -> WebSocketError {
    let nsError = error as NSError
    
    // Check for fatal close codes
    if let closeCode = nsError.userInfo["closeCode"] as? Int {
        switch closeCode {
        case 1002, 1003, 1007, 1008, 1011: // Protocol/policy errors
            return .fatal(underlying: error)
        default:
            break
        }
    }
    
    // Check for network-related errors
    switch nsError.code {
    case NSURLErrorNotConnectedToInternet,
         NSURLErrorTimedOut,
         NSURLErrorNetworkConnectionLost,
         NSURLErrorCannotConnectToHost:
        return .retriable(underlying: error)
    case NSURLErrorBadURL,
         NSURLErrorUnsupportedURL:
        return .fatal(underlying: error)
    default:
        return .retriable(underlying: error)
    }
}

/// Retry limit configuration
struct RetryPolicy {
    let maxAttempts: Int           // Maximum reconnection attempts
    let maxDuration: TimeInterval  // Maximum total retry duration
    let attemptBased: Bool         // Use attempts vs duration
}
```

---

## 2. State Management During Reconnect

### 2.1 Message Buffering While Disconnected

**Why**: WebSocket is a transport, not a message queue. Messages sent while disconnected are lost forever without client-side buffering.

**Strategy**:
- Maintain an outbound message queue
- Automatically flush on reconnection
- Implement size limits and TTL to prevent memory issues

**Swift Implementation**:

```swift
import Foundation

/// Represents a queued message with metadata
struct QueuedMessage {
    let id: String
    let data: Data
    let timestamp: Date
    var attempts: Int = 0
    let maxAttempts: Int
    let onSuccess: (() -> Void)?
    let onFailure: ((Error) -> Void)?
}

/// Message queue with size limits and TTL
final class MessageQueue {
    private var queue: [QueuedMessage] = []
    private let maxSize: Int
    private let maxAge: TimeInterval
    private let defaultMaxAttempts: Int
    private let queue = DispatchQueue(label: "message-queue")
    
    init(
        maxSize: Int = 500,
        maxAge: TimeInterval = 300,  // 5 minutes
        defaultMaxAttempts: Int = 3
    ) {
        self.maxSize = maxSize
        self.maxAge = maxAge
        self.defaultMaxAttempts = defaultMaxAttempts
    }
    
    /// Add message to queue
    func enqueue(
        _ data: Data,
        maxAttempts: Int? = nil,
        onSuccess: (() -> Void)? = nil,
        onFailure: ((Error) -> Void)? = nil
    ) -> String {
        let id = "\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
        
        let message = QueuedMessage(
            id: id,
            data: data,
            timestamp: Date(),
            maxAttempts: maxAttempts ?? defaultMaxAttempts,
            onSuccess: onSuccess,
            onFailure: onFailure
        )
        
        queue.sync {
            // Remove oldest if at capacity
            if self.queue.count >= self.maxSize {
                let dropped = self.queue.removeFirst()
                dropped.onFailure?(MessageQueueError.queueOverflow)
            }
            self.queue.append(message)
        }
        
        return id
    }
    
    /// Flush all queued messages using provided send function
    func flush(using send: (Data) async throws -> Void) async {
        pruneExpired()
        
        while let message = queue.first {
            do {
                try await send(message.data)
                queue.sync { _ = self.queue.removeFirst() }
                message.onSuccess?()
            } catch {
                var mutableMessage = message
                mutableMessage.attempts += 1
                
                if mutableMessage.attempts >= mutableMessage.maxAttempts {
                    queue.sync { _ = self.queue.removeFirst() }
                    mutableMessage.onFailure?(error)
                } else {
                    // Stop flushing on error, will retry next time
                    break
                }
            }
        }
    }
    
    /// Remove expired messages
    private func pruneExpired() {
        let now = Date()
        queue.sync {
            let expired = self.queue.filter { 
                now.timeIntervalSince($0.timestamp) > self.maxAge 
            }
            expired.forEach { $0.onFailure?(MessageQueueError.messageExpired) }
            self.queue.removeAll { 
                now.timeIntervalSince($0.timestamp) > self.maxAge 
            }
        }
    }
    
    var count: Int {
        queue.sync { queue.count }
    }
    
    func clear() {
        queue.sync {
            self.queue.forEach { $0.onFailure?(MessageQueueError.queueCleared) }
            self.queue.removeAll()
        }
    }
}

enum MessageQueueError: Error {
    case queueOverflow
    case messageExpired
    case queueCleared
}
```

### 2.2 Session Resumption vs Restart

**Why**: When reconnecting, the client may want to either resume an existing session or start fresh.

**Resumption Strategies**:

1. **Stateless Resume**: Client stores session state, re-authenticates, continues
2. **Server-Affinity Resume**: Client reconnects to same server instance with session ID
3. **Full Restart**: Clean slate, discard previous state

**Swift Implementation**:

```swift
/// Session persistence strategy
enum SessionStrategy {
    case resume(sessionID: String, lastSequenceNumber: Int)
    case restart
}

/// Manages session state across reconnections
final class SessionManager {
    private var currentSessionID: String?
    private var lastSequenceNumber: Int = 0
    private var pendingAcks: Set<Int> = []
    
    /// Start new session
    func startNewSession() -> String {
        let sessionID = UUID().uuidString
        currentSessionID = sessionID
        lastSequenceNumber = 0
        pendingAcks.removeAll()
        return sessionID
    }
    
    /// Prepare for reconnection with appropriate strategy
    func prepareReconnection() -> SessionStrategy {
        guard let sessionID = currentSessionID else {
            return .restart
        }
        return .resume(sessionID: sessionID, lastSequenceNumber: lastSequenceNumber)
    }
    
    /// Track outgoing message for acknowledgment
    func trackMessage(sequenceNumber: Int) {
        pendingAcks.insert(sequenceNumber)
    }
    
    /// Confirm message received by server
    func acknowledge(sequenceNumber: Int) {
        pendingAcks.remove(sequenceNumber)
    }
    
    /// Messages that need to be resent on reconnection
    var unacknowledgedMessages: [Int] {
        Array(pendingAcks).sorted()
    }
}
```

### 2.3 Detecting and Handling Zombie Connections

**Why**: A "zombie" connection appears alive but silently drops messages. This happens when:
- Network interface changes (WiFi to cellular)
- NAT/firewall times out connection
- Server crashes without clean close

**Detection Methods**:
1. **Application-level heartbeat** (ping/pong)
2. **Send timeout** (expect ACK within N seconds)
3. **Receive timeout** (expect data within N seconds)

**Swift Implementation**:

```swift
import Foundation

/// Detects stale/zombie connections
final class ZombieConnectionDetector {
    private var lastPongTime: Date?
    private var pingTimer: Timer?
    private var timeoutTimer: Timer?
    
    let pingInterval: TimeInterval      // How often to ping (e.g., 30s)
    let pongTimeout: TimeInterval       // How long to wait for pong (e.g., 10s)
    let onZombieDetected: () -> Void
    
    init(
        pingInterval: TimeInterval = 30.0,
        pongTimeout: TimeInterval = 10.0,
        onZombieDetected: @escaping () -> Void
    ) {
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        self.onZombieDetected = onZombieDetected
    }
    
    func start(pingAction: @escaping () -> Void) {
        stop()
        
        // Schedule periodic pings
        pingTimer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { _ in
            self.sendPing(pingAction: pingAction)
        }
        
        // Send initial ping
        sendPing(pingAction: pingAction)
    }
    
    func stop() {
        pingTimer?.invalidate()
        timeoutTimer?.invalidate()
        pingTimer = nil
        timeoutTimer = nil
        lastPongTime = nil
    }
    
    private func sendPing(pingAction: () -> Void) {
        timeoutTimer?.invalidate()
        pingAction()
        
        // Start timeout for pong response
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: pongTimeout, repeats: false) { _ in
            self.onZombieDetected()
        }
    }
    
    /// Call when pong received from server
    func receivedPong() {
        lastPongTime = Date()
        timeoutTimer?.invalidate()
    }
    
    /// Check if connection appears healthy
    var isHealthy: Bool {
        guard let lastPong = lastPongTime else { return false }
        return Date().timeIntervalSince(lastPong) < (pingInterval + pongTimeout)
    }
}
```

---

## 3. Client-Side Patterns (Swift/macOS)

### 3.1 Complete ReconnectingWebSocket Implementation

This combines all patterns into a production-ready WebSocket client:

```swift
import Foundation
import Combine

/// Connection state for UI binding
enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval)
    case failed(Error?)
}

/// Production-ready WebSocket client with reconnection
final class ReconnectingWebSocket: NSObject {
    // MARK: - Public Properties
    
    @Published private(set) var state: WebSocketConnectionState = .disconnected
    let messagePublisher = PassthroughSubject<Data, Never>()
    
    // MARK: - Configuration
    
    struct Configuration {
        let url: URL
        let maxReconnectAttempts: Int = 15
        let reconnectBackoff: BackoffConfiguration = BackoffConfiguration()
        let heartbeatInterval: TimeInterval = 30.0
        let heartbeatTimeout: TimeInterval = 10.0
        let messageQueueSize: Int = 500
        let messageQueueTTL: TimeInterval = 300
    }
    
    // MARK: - Private Properties
    
    private let config: Configuration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let backoff: ExponentialBackoff
    private let circuitBreaker: CircuitBreaker
    private let messageQueue: MessageQueue
    private let zombieDetector: ZombieConnectionDetector
    private let sessionManager = SessionManager()
    
    private var reconnectWorkItem: DispatchWorkItem?
    private var intentionalDisconnect = false
    private var reconnectAttempts = 0
    
    // MARK: - Initialization
    
    init(configuration: Configuration) {
        self.config = configuration
        self.session = URLSession(configuration: .default)
        self.backoff = ExponentialBackoff(config: configuration.reconnectBackoff)
        self.circuitBreaker = CircuitBreaker()
        self.messageQueue = MessageQueue(
            maxSize: configuration.messageQueueSize,
            maxAge: configuration.messageQueueTTL
        )
        self.zombieDetector = ZombieConnectionDetector(
            pingInterval: configuration.heartbeatInterval,
            pongTimeout: configuration.heartbeatTimeout
        ) { [weak self] in
            self?.handleZombieConnection()
        }
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Connect to WebSocket server
    func connect() {
        guard case .disconnected = state else {
            logger.warning("Already connected or connecting")
            return
        }
        
        guard circuitBreaker.canAttempt else {
            logger.warning("Circuit breaker is open, skipping connection attempt")
            state = .failed(CircuitBreakerError.circuitOpen)
            return
        }
        
        state = .connecting
        intentionalDisconnect = false
        
        // Determine session strategy
        let strategy = sessionManager.prepareReconnection()
        
        // Build URL with session info if resuming
        var url = config.url
        if case .resume(let sessionID, _) = strategy {
            url = url.appending(queryItems: [
                URLQueryItem(name: "session_id", value: sessionID),
                URLQueryItem(name: "resume", value: "true")
            ])
        }
        
        task = session.webSocketTask(with: url)
        task?.delegate = self
        task?.resume()
        
        receiveLoop()
    }
    
    /// Send message (queues if disconnected)
    func send(_ data: Data) {
        // If connected, try to send immediately
        if case .connected = state {
            task?.send(.data(data)) { [weak self] error in
                if let error = error {
                    self?.handleSendError(error, data: data)
                }
            }
        } else {
            // Queue for later
            messageQueue.enqueue(data)
            logger.debug("Message queued, queue size: \(messageQueue.count)")
        }
    }
    
    /// Send text message (queues if disconnected)
    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }
    
    /// Gracefully disconnect
    func disconnect() {
        intentionalDisconnect = true
        state = .disconnected
        
        cancelReconnect()
        zombieDetector.stop()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        
        // Don't clear queue on intentional disconnect - user may want to retry
    }
    
    /// Force immediate reconnection attempt (e.g., user-initiated)
    func forceReconnect() {
        circuitBreaker.reset()
        backoff.reset()
        reconnectAttempts = 0
        
        task?.cancel(with: .goingAway, reason: nil)
        performReconnect()
    }
    
    // MARK: - Private Methods
    
    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveLoop()
                
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            messagePublisher.send(data)
            
        case .string(let text):
            // Check for pong/heartbeat response
            if text == "pong" {
                zombieDetector.receivedPong()
                return
            }
            
            if let data = text.data(using: .utf8) {
                messagePublisher.send(data)
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleError(_ error: Error) {
        logger.error("WebSocket error: \(error)")
        
        let categorized = categorizeError(error)
        
        switch categorized {
        case .retriable:
            circuitBreaker.recordFailure()
            scheduleReconnect()
            
        case .fatal:
            state = .failed(error)
            disconnect()
            
        case .maxRetriesExceeded:
            state = .failed(error)
        }
    }
    
    private func handleSendError(_ error: Error, data: Data) {
        logger.error("Send failed: \(error)")
        // Re-queue for retry
        messageQueue.enqueue(data)
        // Trigger reconnection
        scheduleReconnect()
    }
    
    private func handleZombieConnection() {
        logger.warning("Zombie connection detected")
        scheduleReconnect()
    }
    
    private func scheduleReconnect() {
        guard !intentionalDisconnect else { return }
        
        if reconnectAttempts >= config.maxReconnectAttempts {
            state = .failed(MaxRetryError.maxAttemptsReached)
            return
        }
        
        let delay = backoff.nextDelay()
        reconnectAttempts += 1
        
        state = .reconnecting(attempt: reconnectAttempts, nextRetryIn: delay)
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performReconnect()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func performReconnect() {
        cancelReconnect()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connect()
    }
    
    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }
    
    private func onConnected() {
        backoff.reset()
        reconnectAttempts = 0
        circuitBreaker.recordSuccess()
        state = .connected
        
        // Start heartbeat
        zombieDetector.start { [weak self] in
            self?.task?.send(.string("ping")) { _ in }
        }
        
        // Flush queued messages
        Task {
            await flushMessageQueue()
        }
    }
    
    private func flushMessageQueue() async {
        await messageQueue.flush { [weak self] data in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self?.task?.send(.data(data)) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ReconnectingWebSocket: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        logger.info("WebSocket connected")
        onConnected()
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        logger.info("WebSocket closed: \(closeCode)")
        
        if !intentionalDisconnect {
            scheduleReconnect()
        }
    }
}

// MARK: - Errors

enum CircuitBreakerError: Error {
    case circuitOpen
}

enum MaxRetryError: Error {
    case maxAttemptsReached
}

// MARK: - Logging

private let logger = Logger(subsystem: "com.echopanel", category: "WebSocket")
import OSLog
```

### 3.2 User Notification Patterns

**macOS User Notifications for Connection Events**:

```swift
import UserNotifications

/// Manages user notifications for WebSocket events
final class WebSocketNotificationManager {
    private var lastNotificationTime: Date?
    private let minimumInterval: TimeInterval = 30.0  // Throttle notifications
    
    init() {
        requestAuthorization()
    }
    
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }
    
    func notifyConnectionLost(attempt: Int) {
        guard canShowNotification() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Connection Lost"
        content.body = "Attempting to reconnect (attempt \(attempt))..."
        content.sound = .default
        
        show(content)
    }
    
    func notifyConnectionRestored() {
        let content = UNMutableNotificationContent()
        content.title = "Connected"
        content.body = "Connection restored successfully."
        
        show(content)
    }
    
    func notifyMaxRetriesReached() {
        let content = UNMutableNotificationContent()
        content.title = "Connection Failed"
        content.body = "Could not reconnect after multiple attempts. Tap to retry."
        content.sound = .default
        
        // Add action to retry
        let retryAction = UNNotificationAction(
            identifier: "RETRY",
            title: "Retry Now",
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: "CONNECTION_FAILED",
            actions: [retryAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "CONNECTION_FAILED"
        
        show(content)
    }
    
    private func canShowNotification() -> Bool {
        guard let last = lastNotificationTime else { return true }
        return Date().timeIntervalSince(last) >= minimumInterval
    }
    
    private func show(_ content: UNMutableNotificationContent) {
        lastNotificationTime = Date()
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

---

## 4. Server-Side Considerations

### 4.1 Session Affinity and Reconnection

**Why**: Clients should reconnect to the same server instance that holds their session state.

**Python/FastAPI Implementation**:

```python
import asyncio
import json
import time
from typing import Dict, Optional, Set
from dataclasses import dataclass, field
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from contextlib import asynccontextmanager

app = FastAPI()


@dataclass
class ClientSession:
    """Server-side session state"""
    session_id: str
    websocket: Optional[WebSocket] = None
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    sequence_number: int = 0
    pending_messages: list = field(default_factory=list)
    is_connected: bool = False
    
    def touch(self):
        """Update last activity timestamp"""
        self.last_activity = time.time()


class SessionManager:
    """Manages client sessions with reconnection support"""
    
    def __init__(self, session_timeout: float = 300.0):
        self._sessions: Dict[str, ClientSession] = {}
        self._session_timeout = session_timeout
        self._cleanup_task: Optional[asyncio.Task] = None
    
    async def start(self):
        """Start background cleanup task"""
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())
    
    async def stop(self):
        """Stop background cleanup"""
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
    
    async def _cleanup_loop(self):
        """Periodically clean up expired sessions"""
        while True:
            try:
                await asyncio.sleep(60)  # Check every minute
                await self._cleanup_expired()
            except asyncio.CancelledError:
                break
    
    async def _cleanup_expired(self):
        """Remove sessions that haven't been active"""
        now = time.time()
        expired = [
            sid for sid, session in self._sessions.items()
            if not session.is_connected and 
               (now - session.last_activity) > self._session_timeout
        ]
        for sid in expired:
            del self._sessions[sid]
            print(f"Cleaned up expired session: {sid}")
    
    def get_or_create_session(
        self, 
        session_id: Optional[str],
        websocket: WebSocket
    ) -> ClientSession:
        """Get existing session or create new one"""
        
        if session_id and session_id in self._sessions:
            # Reconnecting client
            session = self._sessions[session_id]
            session.websocket = websocket
            session.is_connected = True
            session.touch()
            print(f"Session resumed: {session_id}")
            return session
        
        # New session
        new_id = session_id or self._generate_session_id()
        session = ClientSession(
            session_id=new_id,
            websocket=websocket,
            is_connected=True
        )
        self._sessions[new_id] = session
        print(f"New session created: {new_id}")
        return session
    
    def mark_disconnected(self, session_id: str):
        """Mark session as disconnected (client may reconnect)"""
        if session_id in self._sessions:
            self._sessions[session_id].is_connected = False
            self._sessions[session_id].websocket = None
            self._sessions[session_id].touch()
    
    def _generate_session_id(self) -> str:
        """Generate unique session ID"""
        import uuid
        return str(uuid.uuid4())
    
    async def send_to_session(self, session_id: str, message: dict) -> bool:
        """Send message to a specific session"""
        session = self._sessions.get(session_id)
        if not session or not session.is_connected:
            return False
        
        try:
            await session.websocket.send_json(message)
            session.touch()
            return True
        except Exception:
            session.is_connected = False
            return False


# Global session manager
session_manager = SessionManager()


@app.on_event("startup")
async def startup():
    await session_manager.start()


@app.on_event("shutdown")
async def shutdown():
    await session_manager.stop()


@app.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    session_id: Optional[str] = None,
    resume: bool = False
):
    """WebSocket endpoint with session support"""
    await websocket.accept()
    
    # Get or resume session
    session = session_manager.get_or_create_session(
        session_id if resume else None,
        websocket
    )
    
    try:
        # Send session ID to client
        await websocket.send_json({
            "type": "session",
            "session_id": session.session_id,
            "resumed": resume and session_id == session.session_id
        })
        
        # Send any pending messages from previous session
        for msg in session.pending_messages:
            await websocket.send_json(msg)
        session.pending_messages.clear()
        
        # Main message loop
        while True:
            try:
                message = await websocket.receive_json()
                session.touch()
                session.sequence_number += 1
                
                # Process message...
                await handle_message(session, message)
                
            except WebSocketDisconnect:
                break
                
    except Exception as e:
        print(f"WebSocket error: {e}")
        
    finally:
        # Mark as disconnected (don't delete - client may reconnect)
        session_manager.mark_disconnected(session.session_id)
        print(f"Client disconnected: {session.session_id}")


async def handle_message(session: ClientSession, message: dict):
    """Process incoming message"""
    msg_type = message.get("type")
    
    if msg_type == "ping":
        await session.websocket.send_json({"type": "pong"})
    
    elif msg_type == "ack":
        # Client acknowledged receipt
        seq = message.get("sequence_number")
        print(f"Client acknowledged message {seq}")
    
    # ... handle other message types
```

### 4.2 Heartbeat/Keepalive Patterns

**Server-side heartbeat handling**:

```python
import asyncio
from typing import Dict, Set
from fastapi import WebSocket


class HeartbeatManager:
    """Manages WebSocket heartbeats on the server"""
    
    def __init__(
        self,
        ping_interval: float = 30.0,      # Send ping every 30s
        pong_timeout: float = 10.0,        # Wait 10s for pong
        cleanup_interval: float = 60.0     # Check for stale connections every 60s
    ):
        self.ping_interval = ping_interval
        self.pong_timeout = pong_timeout
        self.cleanup_interval = cleanup_interval
        
        # Track pending pings
        self._pending_pings: Dict[str, asyncio.Task] = {}
        self._last_pong: Dict[str, float] = {}
        self._connected_sockets: Dict[str, WebSocket] = {}
        
        self._running = False
        self._tasks: list[asyncio.Task] = []
    
    async def start(self):
        """Start heartbeat management"""
        self._running = True
        self._tasks = [
            asyncio.create_task(self._ping_loop()),
            asyncio.create_task(self._cleanup_loop())
        ]
    
    async def stop(self):
        """Stop heartbeat management"""
        self._running = False
        for task in self._tasks:
            task.cancel()
        for task in self._pending_pings.values():
            task.cancel()
        await asyncio.gather(*self._tasks, return_exceptions=True)
    
    def register(self, socket_id: str, websocket: WebSocket):
        """Register a new WebSocket for heartbeat monitoring"""
        self._connected_sockets[socket_id] = websocket
        self._last_pong[socket_id] = asyncio.get_event_loop().time()
    
    def unregister(self, socket_id: str):
        """Unregister a WebSocket"""
        self._connected_sockets.pop(socket_id, None)
        self._last_pong.pop(socket_id, None)
        if socket_id in self._pending_pings:
            self._pending_pings[socket_id].cancel()
            del self._pending_pings[socket_id]
    
    def record_pong(self, socket_id: str):
        """Record pong received from client"""
        self._last_pong[socket_id] = asyncio.get_event_loop().time()
    
    async def _ping_loop(self):
        """Send periodic pings to all connected clients"""
        while self._running:
            try:
                await asyncio.sleep(self.ping_interval)
                await self._send_pings()
            except asyncio.CancelledError:
                break
    
    async def _send_pings(self):
        """Send ping to all connected sockets"""
        now = asyncio.get_event_loop().time()
        
        for socket_id, websocket in list(self._connected_sockets.items()):
            # Skip if already waiting for pong
            if socket_id in self._pending_pings:
                continue
            
            try:
                await websocket.send_json({"type": "ping"})
                
                # Schedule timeout check
                self._pending_pings[socket_id] = asyncio.create_task(
                    self._pong_timeout(socket_id, websocket)
                )
                
            except Exception as e:
                print(f"Failed to ping {socket_id}: {e}")
                await self._close_socket(socket_id, websocket)
    
    async def _pong_timeout(self, socket_id: str, websocket: WebSocket):
        """Wait for pong response"""
        try:
            await asyncio.sleep(self.pong_timeout)
            
            # Check if pong was received
            now = asyncio.get_event_loop().time()
            last_pong = self._last_pong.get(socket_id, 0)
            
            if now - last_pong > self.pong_timeout:
                print(f"Pong timeout for {socket_id}, closing connection")
                await self._close_socket(socket_id, websocket)
            
        except asyncio.CancelledError:
            pass  # Expected when pong received
        finally:
            self._pending_pings.pop(socket_id, None)
    
    async def _cleanup_loop(self):
        """Periodically check for stale connections"""
        while self._running:
            try:
                await asyncio.sleep(self.cleanup_interval)
                await self._cleanup_stale()
            except asyncio.CancelledError:
                break
    
    async def _cleanup_stale(self):
        """Close connections that haven't responded"""
        now = asyncio.get_event_loop().time()
        stale_threshold = self.ping_interval + self.pong_timeout + 10
        
        stale_sockets = [
            (sid, ws) for sid, ws in self._connected_sockets.items()
            if now - self._last_pong.get(sid, 0) > stale_threshold
        ]
        
        for socket_id, websocket in stale_sockets:
            print(f"Cleaning up stale connection: {socket_id}")
            await self._close_socket(socket_id, websocket)
    
    async def _close_socket(self, socket_id: str, websocket: WebSocket):
        """Close a WebSocket connection"""
        self.unregister(socket_id)
        try:
            await websocket.close(code=1001)  # Going away
        except Exception:
            pass


# Usage in WebSocket endpoint:
heartbeat_manager = HeartbeatManager()

@app.on_event("startup")
async def startup():
    await heartbeat_manager.start()

@app.on_event("shutdown")
async def shutdown():
    await heartbeat_manager.stop()

@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    socket_id = str(id(websocket))
    
    heartbeat_manager.register(socket_id, websocket)
    
    try:
        while True:
            message = await websocket.receive_json()
            
            if message.get("type") == "pong":
                heartbeat_manager.record_pong(socket_id)
            else:
                # Handle other messages
                pass
                
    except WebSocketDisconnect:
        pass
    finally:
        heartbeat_manager.unregister(socket_id)
```

### 4.3 Detecting Stale Connections Server-Side

```python
import time
import asyncio
from collections import defaultdict
from typing import Dict, Callable


class StaleConnectionDetector:
    """Detects and handles stale/zombie connections"""
    
    def __init__(
        self,
        read_timeout: float = 120.0,      # Max time without reading
        write_timeout: float = 60.0,      # Max time without successful write
        on_stale: Callable[[str], None] = None
    ):
        self.read_timeout = read_timeout
        self.write_timeout = write_timeout
        self.on_stale = on_stale
        
        self._last_read: Dict[str, float] = {}
        self._last_write: Dict[str, float] = {}
        self._write_failures: Dict[str, int] = defaultdict(int)
        self._running = False
    
    async def start_monitoring(self):
        """Start monitoring for stale connections"""
        self._running = True
        while self._running:
            await asyncio.sleep(30)  # Check every 30 seconds
            self._check_stale_connections()
    
    def stop_monitoring(self):
        """Stop monitoring"""
        self._running = False
    
    def record_read(self, socket_id: str):
        """Record that we received data from client"""
        self._last_read[socket_id] = time.time()
    
    def record_write_success(self, socket_id: str):
        """Record successful write to client"""
        self._last_write[socket_id] = time.time()
        self._write_failures[socket_id] = 0
    
    def record_write_failure(self, socket_id: str) -> bool:
        """Record failed write. Returns True if connection should be closed."""
        self._write_failures[socket_id] += 1
        # Close after 3 consecutive failures
        return self._write_failures[socket_id] >= 3
    
    def remove(self, socket_id: str):
        """Remove tracking for a socket"""
        self._last_read.pop(socket_id, None)
        self._last_write.pop(socket_id, None)
        self._write_failures.pop(socket_id, None)
    
    def _check_stale_connections(self):
        """Identify and handle stale connections"""
        now = time.time()
        stale_sockets = []
        
        for socket_id, last_read in self._last_read.items():
            # Check read timeout
            if now - last_read > self.read_timeout:
                stale_sockets.append((socket_id, "read timeout"))
                continue
            
            # Check write timeout
            last_write = self._last_write.get(socket_id, 0)
            if now - last_write > self.write_timeout:
                stale_sockets.append((socket_id, "write timeout"))
        
        for socket_id, reason in stale_sockets:
            print(f"Stale connection detected: {socket_id} ({reason})")
            if self.on_stale:
                self.on_stale(socket_id)
```

---

## 5. Recommended Configuration Values

| Parameter | Development | Production | Rationale |
|-----------|-------------|------------|-----------|
| **Backoff base delay** | 1s | 1s | Quick initial retry |
| **Backoff max delay** | 10s | 60s | Don't wait too long in production |
| **Max reconnect attempts** | 5 | 15 | Allow more retries in production |
| **Heartbeat interval** | 10s | 30s | Balance between responsiveness and overhead |
| **Heartbeat timeout** | 5s | 10s | Allow for network variability |
| **Message queue size** | 100 | 500-1000 | More buffering in production |
| **Message queue TTL** | 60s | 300s | Messages stay valid longer |
| **Circuit breaker threshold** | 3 | 5 | More tolerance in production |
| **Session timeout** | 60s | 300s | Keep sessions alive longer |

---

## 6. Testing Reconnection Behavior

### Simulating Network Failures

```python
# chaos_testing.py - Server-side network chaos
import random
import asyncio
from fastapi import WebSocket


class ChaosInjector:
    """Inject failures for testing reconnection logic"""
    
    def __init__(
        self,
        drop_rate: float = 0.1,           # 10% message drop rate
        disconnect_rate: float = 0.05,    # 5% chance to disconnect per minute
        latency_range: tuple = (0, 0.5)   # 0-500ms added latency
    ):
        self.drop_rate = drop_rate
        self.disconnect_rate = disconnect_rate
        self.latency_range = latency_range
        self.enabled = False
    
    async def maybe_drop(self) -> bool:
        """Returns True if message should be dropped"""
        if not self.enabled:
            return False
        return random.random() < self.drop_rate
    
    async def maybe_disconnect(self, websocket: WebSocket) -> bool:
        """Randomly close connection for testing"""
        if not self.enabled:
            return False
        if random.random() < self.disconnect_rate:
            await websocket.close(code=1001)
            return True
        return False
    
    async def add_latency(self):
        """Add random latency"""
        if self.enabled:
            delay = random.uniform(*self.latency_range)
            await asyncio.sleep(delay)
```

---

## 7. Summary

### Key Takeaways

1. **Always use exponential backoff with jitter** to prevent thundering herd
2. **Implement circuit breakers** to fail fast during outages
3. **Buffer messages client-side** - WebSocket is not a message queue
4. **Use application-level heartbeats** to detect zombie connections faster than TCP
5. **Support session resumption** for seamless reconnection experience
6. **Classify errors** as retriable vs fatal to avoid infinite loops
7. **Monitor connection health** with metrics for queue depth, latency, drop rates

### EchoPanel-Specific Recommendations

Based on the current `WebSocketStreamer.swift` implementation:

1. **Add jitter** to the current exponential backoff (line 327)
2. **Implement circuit breaker** to prevent rapid reconnection during server outages
3. **Add message buffering** for audio frames during disconnection
4. **Extend heartbeat interval** from 10s to 30s (reduces overhead)
5. **Add pong timeout detection** in addition to ping sending
6. **Track unacknowledged messages** for potential replay on reconnect

---

## References

- [RFC 6455 - The WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [Azure Architecture Center - Circuit Breaker Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)
- [Ably - WebSocket Architecture Best Practices](https://ably.com/topic/websocket-architecture-best-practices)
- [OneUptime - WebSocket Reconnection Logic](https://oneuptime.com/blog/post/2026-01-27-websocket-reconnection-logic/view)
