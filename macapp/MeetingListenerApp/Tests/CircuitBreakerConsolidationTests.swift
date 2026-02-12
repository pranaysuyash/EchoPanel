import XCTest
@testable import MeetingListenerApp

@MainActor
final class CircuitBreakerConsolidationTests: XCTestCase {
    func testCircuitBreakerOpensAfterFailureThreshold() {
        let breaker = CircuitBreaker(
            failureThreshold: 2,
            resetTimeout: 1.0,
            failureWindow: 60.0
        )

        XCTAssertTrue(breaker.canExecute())

        breaker.recordFailure(TestError.generic)
        XCTAssertEqual(breaker.state, .closed)
        XCTAssertTrue(breaker.canExecute())

        breaker.recordFailure(TestError.generic)
        XCTAssertEqual(breaker.state, .open)
        XCTAssertFalse(breaker.canExecute())
    }

    func testCircuitBreakerTransitionsToHalfOpenAfterTimeout() async {
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            resetTimeout: 0.05,
            failureWindow: 60.0
        )

        breaker.recordFailure(TestError.generic)
        XCTAssertEqual(breaker.state, .open)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(breaker.canExecute())
        XCTAssertEqual(breaker.state, .halfOpen)

        breaker.recordSuccess()
        XCTAssertEqual(breaker.state, .closed)
    }

    func testResilientWebSocketTransitionsToCircuitOpenOnConnectionFailure() async {
        let breaker = CircuitBreaker(
            failureThreshold: 1,
            resetTimeout: 2.0,
            failureWindow: 60.0
        )
        let config = ReconnectionConfiguration(
            maxAttempts: 3,
            backoff: ExponentialBackoff(initialDelay: 0.05, maxDelay: 0.05, jitterFactor: 0.0),
            circuitBreaker: breaker,
            messageBufferCapacity: 16,
            messageBufferTTL: 5
        )
        let socket = ResilientWebSocket(
            url: URL(string: "ws://127.0.0.1:1")!,
            configuration: config
        )

        var seenStates: [ResilientConnectionState] = []
        let circuitOpenExpectation = expectation(description: "socket enters circuit open state")
        socket.onStateChange = { state in
            seenStates.append(state)
            if case .circuitOpen = state {
                circuitOpenExpectation.fulfill()
            }
        }

        socket.connect()
        await fulfillment(of: [circuitOpenExpectation], timeout: 3.0)
        socket.disconnect()

        XCTAssertTrue(seenStates.contains {
            if case .circuitOpen = $0 { return true }
            return false
        })
    }
}

private enum TestError: Error {
    case generic
}
