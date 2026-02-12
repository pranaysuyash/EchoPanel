import XCTest
@testable import MeetingListenerApp

@MainActor
final class DeviceHotSwapManagerTests: XCTestCase {
    func testRecoveryTimesOutWhenRestartCallbackHangs() async {
        let manager = DeviceHotSwapManager(
            recoveryDelay: 0,
            retryDelay: 0,
            maxRecoveryAttempts: 1,
            restartCaptureTimeout: 0.05
        )
        manager.onShouldRestartCapture = {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        manager.triggerManualRecovery()
        await waitUntil(timeout: 1.0) { !manager.isRecovering }

        XCTAssertEqual(manager.deviceStatus, .failed)
        XCTAssertTrue((manager.lastError ?? "").contains("timed out"))
    }

    func testManualRecoveryIsGuardedAgainstReentry() async {
        let manager = DeviceHotSwapManager(
            recoveryDelay: 0,
            retryDelay: 0,
            maxRecoveryAttempts: 1,
            restartCaptureTimeout: 1.0
        )
        let counter = AttemptCounter()
        manager.onShouldRestartCapture = {
            await counter.increment()
            try await Task.sleep(nanoseconds: 250_000_000)
            struct TestFailure: Error {}
            throw TestFailure()
        }

        manager.triggerManualRecovery()
        manager.triggerManualRecovery()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let attemptCount = await counter.value()
        XCTAssertEqual(attemptCount, 1)
        await waitUntil(timeout: 1.0) { !manager.isRecovering }
    }

    func testStopMonitoringCleansObserversAndCancelsRecovery() async {
        let manager = DeviceHotSwapManager(
            recoveryDelay: 0,
            retryDelay: 0,
            maxRecoveryAttempts: 1,
            restartCaptureTimeout: 1.0
        )
        manager.startMonitoring()
        XCTAssertEqual(manager.activeObserverCountForTesting, 2)

        manager.onShouldRestartCapture = {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        manager.triggerManualRecovery()
        await waitUntil(timeout: 1.0) { manager.isRecovering }

        manager.stopMonitoring()
        XCTAssertEqual(manager.activeObserverCountForTesting, 0)
        XCTAssertFalse(manager.isRecovering)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async {
        if condition() {
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Condition not met before timeout (\(timeout)s)")
    }

    actor AttemptCounter {
        private var attempts = 0

        func increment() {
            attempts += 1
        }

        func value() -> Int {
            attempts
        }
    }
}
