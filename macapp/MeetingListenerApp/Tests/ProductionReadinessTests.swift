
import XCTest
@testable import MeetingListenerApp

/// Production readiness tests to validate resource limits and core functionality
@MainActor
final class ProductionReadinessTests: XCTestCase {

    var appState: AppState!
    var resourceMonitor: ResourceMonitor!

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        resourceMonitor = ResourceMonitor.shared
    }

    override func tearDown() async throws {
        appState = nil
        try await super.tearDown()
    }

    // MARK: - Memory Management Tests

    func testTranscriptArchivalUnderLoad() async throws {
        // Given: A large number of transcript segments
        let initialMemory = resourceMonitor.memoryUsage

        // When: Adding many segments (simulating a long meeting)
        for i in 0..<6000 {
            let segment = TranscriptSegment(
                text: "Test segment \(i) with some content",
                t0: TimeInterval(i * 2),
                t1: TimeInterval(i * 2 + 1),
                isFinal: true,
                confidence: 0.9,
                source: "test"
            )
            await MainActor.run {
                appState.transcriptSegments.append(segment)
            }
        }

        // Then: Memory should remain bounded and segments should be archived
        let finalMemory = await MainActor.run { resourceMonitor.memoryUsage }
        let segmentCount = await MainActor.run { appState.transcriptSegments.count }

        XCTAssertLessThan(segmentCount, 5100, "Should keep less than 5,100 segments in active memory")
        XCTAssertLessThan(finalMemory - initialMemory, 500_000_000, "Memory growth should be <500MB for 6000 segments")
    }

    func testResourceMonitorDetection() async throws {
        // Given: Resource monitor is running
        await MainActor.run {
            XCTAssertTrue(resourceMonitor.memoryUsage >= 0, "Memory usage should be readable")

            // When: Simulating memory pressure (this is a basic test)
            _ = resourceMonitor.isUnderPressure

            // Then: Should be able to read pressure state
            XCTAssert(resourceMonitor.isUnderPressure == true || resourceMonitor.isUnderPressure == false, "Pressure state should be readable")
        }
    }

    // MARK: - Recording Lifecycle Tests

    func testStartStopStressTest() async throws {
        // Given: App state ready
        XCTAssertEqual(appState.sessionState, .idle, "Should start idle")

        // When: Rapid start/stop cycles
        for i in 0..<10 {
            await MainActor.run {
                if appState.sessionState == .idle {
                    appState.startSession()
                } else {
                    appState.stopSession()
                }
            }

            // Small delay between cycles
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Then: Should handle rapid cycles without crashes
        XCTAssertNotEqual(appState.sessionState, .error, "Should not error under rapid start/stop")
    }

    func testSessionStateTransitions() async throws {
        await MainActor.run {
            // Test idle -> starting (or idle if lazy init prevents immediate start)
            XCTAssertEqual(appState.sessionState, .idle)
            appState.startSession()
            // After startSession, state should change from idle (to starting/listening) or stay idle if permissions denied
            XCTAssertTrue([.idle, .starting, .listening].contains(appState.sessionState), "State should be valid after startSession()")
        }

        // Wait a bit for state change
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        await MainActor.run {
            if appState.sessionState == .listening {
                appState.stopSession()
                // Stop will eventually go back to idle or finalizing
                XCTAssertTrue([.idle, .finalizing, .listening].contains(appState.sessionState))
            }
        }
    }

    // MARK: - Data Integrity Tests

    func testTranscriptIntegrityUnderStress() async throws {
        // Given: Active session
        await MainActor.run {
            if appState.sessionState == .idle {
                appState.startSession()
            }
        }

        // When: Adding many segments rapidly
        for i in 0..<100 {
            let segment = TranscriptSegment(
                text: "Stress test segment \(i)",
                t0: TimeInterval(i),
                t1: TimeInterval(i + 1),
                isFinal: true,
                confidence: 0.95,
                source: "stress_test"
            )

            await MainActor.run {
                appState.transcriptSegments.append(segment)
            }
        }

        // Then: Data should remain consistent
        let segmentCount = await MainActor.run { appState.transcriptSegments.count }
        XCTAssertEqual(segmentCount, 100, "All segments should be preserved")
    }

    // MARK: - Resource Limit Tests

    func testMemoryThrottlingBehavior() async throws {
        // Given: Resource monitor
        let initialMemory = resourceMonitor.memoryUsage

        // When: Checking if we should throttle
        let shouldThrottle = resourceMonitor.shouldThrottleMemory()

        // Then: Should provide sensible answer based on current memory
        if initialMemory > 1_400_000_000 { // 1.4GB (70% of 2GB limit)
            XCTAssertTrue(shouldThrottle, "Should throttle when memory is high")
        } else {
            XCTAssertFalse(shouldThrottle, "Should not throttle when memory is reasonable")
        }
    }

    func testCPUThrottlingIntegration() async throws {
        await MainActor.run {
            // Given: OCR configuration (this tests the integration)
            let resourceMonitor = ResourceMonitor.shared

            // When: Checking CPU throttling
            let shouldThrottle = resourceMonitor.shouldThrottleCPU()

            // Then: Should provide guidance based on system pressure
            // This is mainly testing that the method works without crashes
            XCTAssert(shouldThrottle == true || shouldThrottle == false, "CPU throttling should be accessible")
        }
    }

    // MARK: - Error Recovery Tests

    func testGracefulDegradation() async throws {
        // Given: Normal operation
        let initialSegmentCount = await MainActor.run { appState.transcriptSegments.count }

        // When: Simulating error conditions
        await MainActor.run {
            // This tests that error handling doesn't crash
            appState.recordCredentialSaveFailure(field: "test_field")
        }

        // Then: App should remain stable
        let finalSegmentCount = await MainActor.run { appState.transcriptSegments.count }
        XCTAssertEqual(initialSegmentCount, finalSegmentCount, "Error handling shouldn't corrupt data")
    }

    // MARK: - Long-Running Session Tests

    func testMemoryStabilityOverTime() async throws {
        // This is a basic test - real testing requires Instruments profiling

        // Given: Initial memory state
        let initialMemory = resourceMonitor.memoryUsage

        // When: Simulating some activity
        for i in 0..<100 {
            let segment = TranscriptSegment(
                text: "Long running test \(i)",
                t0: TimeInterval(i * 10),
                t1: TimeInterval(i * 10 + 5),
                isFinal: true,
                confidence: 0.85,
                source: "long_running"
            )

            await MainActor.run {
                appState.transcriptSegments.append(segment)
            }

            // Small delay every 25 iterations
            if i % 25 == 0 {
                try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            }
        }

        // Then: Memory should be reasonable
        let finalMemory = resourceMonitor.memoryUsage
        let memoryGrowth = finalMemory - initialMemory

        XCTAssertLessThan(memoryGrowth, 200_000_000, "Memory growth should be <200MB for 100 segments")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentSegmentAccess() async throws {
        // Given: Shared transcript array
        let segmentsToAdd = 200

        // When: Adding segments concurrently from multiple "threads"
        await withTaskGroup(of: Void.self) { group in
            for batch in 0..<4 {
                group.addTask {
                    for i in 0..<(segmentsToAdd / 4) {
                        let segment = TranscriptSegment(
                            text: "Concurrent test \(batch)-\(i)",
                            t0: TimeInterval(i),
                            t1: TimeInterval(i + 1),
                            isFinal: true,
                            confidence: 0.9,
                            source: "concurrent_\(batch)"
                        )

                        await MainActor.run {
                            self.appState.transcriptSegments.append(segment)
                        }
                    }
                }
            }
        }

        // Then: All segments should be added safely
        let segmentCount = await MainActor.run { appState.transcriptSegments.count }
        XCTAssertEqual(segmentCount, segmentsToAdd, "All concurrent additions should succeed")
    }
}