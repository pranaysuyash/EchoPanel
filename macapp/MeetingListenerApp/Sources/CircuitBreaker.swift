import Foundation
import SwiftUI

/// Circuit breaker pattern for preventing restart loops in BackendManager.
/// Tracks failures and opens the circuit after threshold to prevent cascading failures.
@MainActor
final class CircuitBreaker: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var state: State = .closed
    @Published private(set) var failureCount: Int = 0
    @Published private(set) var lastFailureTime: Date?
    @Published private(set) var lastError: Error?
    
    // MARK: - Types
    
    enum State: String {
        case closed = "Closed"       // Normal operation
        case open = "Open"           // Failing, blocking requests
        case halfOpen = "Half-Open"  // Testing if recovered
        
        var color: String {
            switch self {
            case .closed: return "green"
            case .open: return "red"
            case .halfOpen: return "yellow"
            }
        }
    }
    
    enum CircuitBreakerError: Error, LocalizedError {
        case circuitOpen
        case maxFailuresReached
        
        var errorDescription: String? {
            switch self {
            case .circuitOpen:
                return "Circuit breaker is open - too many failures, cooling down"
            case .maxFailuresReached:
                return "Maximum failure threshold reached"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// Number of failures before opening circuit
    let failureThreshold: Int
    
    /// Time to wait before attempting half-open (seconds)
    let resetTimeout: TimeInterval
    
    /// Time window for counting failures (seconds)
    let failureWindow: TimeInterval
    
    // MARK: - Private Properties
    
    private var failures: [Date] = []
    private var halfOpenTimer: Timer?
    // MARK: - Initialization
    
    init(
        failureThreshold: Int = 3,
        resetTimeout: TimeInterval = 30.0,
        failureWindow: TimeInterval = 60.0
    ) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
        self.failureWindow = failureWindow
    }
    
    // MARK: - Public Methods
    
    /// Execute a throwing closure with circuit breaker protection
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        try await execute(operation: operation)
    }
    
    /// Execute with explicit operation name for logging
    func execute<T>(operation: () async throws -> T, name: String = "operation") async throws -> T {
        // Check if we can proceed
        guard canExecute() else {
            StructuredLogger.shared.error("Circuit breaker blocked \(name)", metadata: [
                "state": state.rawValue,
                "failure_count": failureCount
            ])
            throw CircuitBreakerError.circuitOpen
        }
        
        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure(error)
            throw error
        }
    }
    
    /// Check if circuit allows execution
    func canExecute() -> Bool {
        cleanOldFailures()
        
        switch state {
        case .closed:
            return true
            
        case .open:
            // Check if enough time has passed to try half-open
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= resetTimeout {
                transitionTo(.halfOpen)
                return true
            }
            return false
            
        case .halfOpen:
            // Allow one test request
            return true
        }
    }
    
    /// Manually reset the circuit breaker
    func reset() {
        failures.removeAll()
        failureCount = 0
        lastFailureTime = nil
        lastError = nil
        halfOpenTimer?.invalidate()
        halfOpenTimer = nil
        transitionTo(.closed)
        
        StructuredLogger.shared.info("Circuit breaker manually reset", metadata: [:])
    }
    
    /// Force open the circuit (for maintenance mode)
    func forceOpen() {
        transitionTo(.open)
        StructuredLogger.shared.warning("Circuit breaker forced open", metadata: [:])
    }
    
    // MARK: - Private Methods
    
    func recordSuccess() {
        if state == .halfOpen {
            // Success in half-open, close the circuit
            failures.removeAll()
            failureCount = 0
            transitionTo(.closed)
            
            StructuredLogger.shared.info("Circuit breaker closed after recovery", metadata: [:])
        }
    }
    
    func recordFailure(_ error: Error) {
        let now = Date()
        failures.append(now)
        lastFailureTime = now
        lastError = error
        cleanOldFailures()
        failureCount = failures.count
        
        if state == .halfOpen {
            // Failed in half-open, go back to open
            transitionTo(.open)
            
            StructuredLogger.shared.error("Circuit breaker reopened after half-open failure", metadata: [
                "error": error.localizedDescription
            ])
        } else if failures.count >= failureThreshold {
            // Threshold reached, open circuit
            transitionTo(.open)
            
            StructuredLogger.shared.error("Circuit breaker opened due to failures", metadata: [
                "failure_count": failureCount,
                "threshold": failureThreshold
            ])
        }
    }
    
    private func cleanOldFailures() {
        let cutoff = Date().addingTimeInterval(-failureWindow)
        failures.removeAll { $0 < cutoff }
        failureCount = failures.count
    }
    
    private func transitionTo(_ newState: State) {
        let oldState = state
        state = newState
        
        // Schedule half-open timer if transitioning to open
        if newState == .open {
            halfOpenTimer?.invalidate()
            halfOpenTimer = Timer.scheduledTimer(withTimeInterval: resetTimeout, repeats: false) { _ in
                Task { @MainActor in
                    // Timer just marks that we can try half-open next time
                    // Actual transition happens in canExecute()
                }
            }
        } else if newState == .closed || newState == .halfOpen {
            halfOpenTimer?.invalidate()
            halfOpenTimer = nil
        }
        
        if oldState != newState {
            StructuredLogger.shared.info("Circuit breaker state changed", metadata: [
                "from": oldState.rawValue,
                "to": newState.rawValue
            ])
        }
    }
}

// MARK: - BackendManager Integration

extension BackendManager {
    /// Circuit breaker for server restart attempts
    @MainActor
    var restartCircuitBreaker: CircuitBreaker {
        // Use associated object or singleton pattern
        CircuitBreakerManager.shared.backendRestartBreaker
    }
}

/// Manages circuit breakers for different backend operations
@MainActor
final class CircuitBreakerManager {
    static let shared = CircuitBreakerManager()
    
    /// Circuit breaker for backend restart attempts
    let backendRestartBreaker = CircuitBreaker(
        failureThreshold: 3,
        resetTimeout: 60.0,  // Wait 1 minute before retry
        failureWindow: 300.0 // Count failures in 5 minute window
    )
    
    /// Circuit breaker for health check polling
    let healthCheckBreaker = CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: 30.0,
        failureWindow: 120.0
    )
    
    private init() {}
}

// MARK: - SwiftUI View

struct CircuitBreakerStatusView: View {
    @StateObject private var breaker: CircuitBreaker
    
    init(breaker: CircuitBreaker) {
        _breaker = StateObject(wrappedValue: breaker)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Circuit: \(breaker.state.rawValue)")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if breaker.failureCount > 0 {
                    Text("\(breaker.failureCount) failures")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if breaker.state == .open {
                Button("Reset") {
                    breaker.reset()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch breaker.state {
        case .closed: return .green
        case .open: return .red
        case .halfOpen: return .yellow
        }
    }
}

// MARK: - Broadcast Feature Integration

extension BroadcastFeatureManager {
    /// Enable circuit breaker for backend restarts
    var useCircuitBreaker: Bool {
        get { UserDefaults.standard.bool(forKey: "broadcast_useCircuitBreaker") }
        set { UserDefaults.standard.set(newValue, forKey: "broadcast_useCircuitBreaker") }
    }
    
    /// Access circuit breaker for backend restarts
    var backendCircuitBreaker: CircuitBreaker {
        CircuitBreakerManager.shared.backendRestartBreaker
    }
}
