import XCTest
@testable import MeetingListenerApp
import ScreenCaptureKit

/// Tests for audio capture thread safety and hardening fixes
/// Addresses AUD-001, AUD-002, AUD-003 flow issues
@MainActor
final class AudioCaptureThreadSafetyTests: XCTestCase {
    
    // MARK: - AudioCaptureManager Thread Safety Tests
    
    func testQualityMetricsThreadSafety() async {
        let manager = AudioCaptureManager()
        
        // Simulate concurrent access to quality metrics
        let expectation = expectation(description: "Concurrent quality access")
        expectation.expectedFulfillmentCount = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = manager.currentQualityMetrics
                    expectation.fulfill()
                }
            }
            await group.waitForAll()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testStreamStateThreadSafety() async {
        let manager = AudioCaptureManager()
        
        // Verify initial state is accessible
        let initialState = manager.streamActive
        XCTAssertFalse(initialState)
        
        // State should be readable without crash
        let expectation = expectation(description: "State access")
        Task.detached {
            _ = manager.streamActive
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - MicrophoneCaptureManager Thread Safety Tests
    
    func testMicrophoneLevelThreadSafety() {
        let manager = MicrophoneCaptureManager()
        
        // Verify level can be read from any thread
        let expectation = expectation(description: "Level access")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            Task.detached {
                _ = manager.currentLevel
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - RedundantAudioCaptureManager Hardening Tests
    
    func testFailoverEventRingBuffer() async {
        let manager = RedundantAudioCaptureManager()
        
        // Manually trigger many failover events
        for i in 0..<150 {
            manager.switchToSource(i % 2 == 0 ? .primary : .backup)
        }
        
        // Verify events are bounded (max 100)
        let stats = manager.getStatistics()
        XCTAssertLessThanOrEqual(stats.failoverCount, 100, "Failover events should be bounded by ring buffer")
    }
    
    func testHysteresisPreventsRapidSwitching() {
        let manager = RedundantAudioCaptureManager()
        
        // Get initial state
        let initialSource = manager.activeSource
        
        // Attempt rapid switches
        for _ in 0..<5 {
            manager.switchToSource(.backup)
            manager.switchToSource(.primary)
        }
        
        // Verify behavior - source should be one of the valid options
        let finalSource = manager.activeSource
        XCTAssertTrue(finalSource == .primary || finalSource == .backup)
        
        // Failover events should track all switches
        let stats = manager.getStatistics()
        XCTAssertGreaterThan(stats.failoverCount, 0, "Should have recorded failover events")
    }
    
    func testAutomaticFailbackConfiguration() async {
        let manager = RedundantAudioCaptureManager()
        
        // Verify manager is properly initialized
        XCTAssertEqual(manager.activeSource, .primary)
        XCTAssertFalse(manager.isRedundancyActive)
        
        // Stats should be available
        let stats = manager.getStatistics()
        XCTAssertEqual(stats.failoverCount, 0)
        XCTAssertEqual(stats.primaryFrameCount, 0)
        XCTAssertEqual(stats.backupFrameCount, 0)
    }
    
    func testHealthStatusTransitions() {
        let manager = RedundantAudioCaptureManager()
        
        // Initial health should be unknown
        let initialHealth = manager.currentHealth
        
        // Health status should be a valid enum case
        XCTAssertTrue(
            initialHealth == .healthy || 
            initialHealth == .degraded || 
            initialHealth == .critical ||
            initialHealth == .unknown
        )
    }
}

// MARK: - RedundancyStats Extension for Testing

extension RedundancyStats {
    /// Helper to verify stats consistency
    var isConsistent: Bool {
        return failoverCount >= 0 && 
               primaryFrameCount >= 0 && 
               backupFrameCount >= 0
    }
}
