import XCTest
@testable import MeetingListenerApp
import SwiftUI

@MainActor
final class RedundantAudioCaptureTests: XCTestCase {
    
    var manager: RedundantAudioCaptureManager!
    
    override func setUp() {
        super.setUp()
        manager = RedundantAudioCaptureManager()
    }
    
    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        XCTAssertEqual(manager.activeSource, .primary)
        XCTAssertFalse(manager.isRedundancyActive)
        XCTAssertEqual(manager.primaryQuality, .unknown)
        XCTAssertEqual(manager.backupQuality, .unknown)
        // Both qualities unknown means no healthy source, so health is critical
        XCTAssertEqual(manager.currentHealth, .critical)
        XCTAssertTrue(manager.failoverEvents.isEmpty)
    }
    
    func testHealthStateTransitions() {
        // Initially critical (both sources unknown quality)
        
        // Good quality = healthy
        manager.primaryQuality = .good
        XCTAssertEqual(manager.currentHealth, .healthy)
        
        // OK quality = degraded
        manager.primaryQuality = .ok
        XCTAssertEqual(manager.currentHealth, .degraded)
        
        // Poor quality + backup on = degraded (backup is ok)
        manager.primaryQuality = .poor
        manager.backupQuality = .ok
        manager.activeSource = .backup
        XCTAssertEqual(manager.currentHealth, .degraded)
        
        // Both poor = critical
        manager.backupQuality = .poor
        XCTAssertEqual(manager.currentHealth, .critical)
    }
    
    // MARK: - Source Switching Tests
    
    func testManualSourceSwitch() {
        let expectation = XCTestExpectation(description: "Source change callback")
        
        manager.onSourceChanged = { source in
            XCTAssertEqual(source, .backup)
            expectation.fulfill()
        }
        
        manager.switchToSource(.backup)
        
        XCTAssertEqual(manager.activeSource, .backup)
        XCTAssertEqual(manager.failoverEvents.count, 1)
        XCTAssertEqual(manager.failoverEvents.first?.reason, .manual)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testEmergencyFailover() {
        manager.switchToSource(.primary)
        XCTAssertEqual(manager.activeSource, .primary)
        
        manager.emergencyFailover()
        
        XCTAssertEqual(manager.activeSource, .backup)
        XCTAssertEqual(manager.failoverEvents.count, 1)
        XCTAssertEqual(manager.failoverEvents.first?.reason, .manual)
    }
    
    func testNoDuplicateFailover() {
        // Switch to backup
        manager.switchToSource(.backup)
        XCTAssertEqual(manager.failoverEvents.count, 1)
        
        // Try to switch to backup again (should not add event)
        manager.switchToSource(.backup)
        XCTAssertEqual(manager.failoverEvents.count, 1)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsStructure() {
        let stats = manager.getStatistics()
        
        XCTAssertEqual(stats.primaryFrameCount, 0)
        XCTAssertEqual(stats.backupFrameCount, 0)
        XCTAssertEqual(stats.activeSource, .primary)
        XCTAssertEqual(stats.failoverCount, 0)
    }
    
    // MARK: - AudioSource Enum Tests
    
    func testAudioSourceEnum() {
        XCTAssertEqual(RedundantAudioSource.primary.rawValue, "primary")
        XCTAssertEqual(RedundantAudioSource.backup.rawValue, "backup")
        XCTAssertEqual(RedundantAudioSource.primary.displayName, "Primary (System Audio)")
        XCTAssertEqual(RedundantAudioSource.backup.displayName, "Backup (Microphone)")
    }
    
    func testAudioSourceAllCases() {
        let allCases = RedundantAudioSource.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.primary))
        XCTAssertTrue(allCases.contains(.backup))
    }
    
    // MARK: - FailoverEvent Tests
    
    func testFailoverEventCreation() {
        let event = RedundantAudioCaptureManager.FailoverEvent(
            timestamp: Date(),
            from: .primary,
            to: .backup,
            reason: .silence
        )
        
        XCTAssertEqual(event.from, .primary)
        XCTAssertEqual(event.to, .backup)
        XCTAssertEqual(event.reason, .silence)
    }
    
    func testFailoverReasonRawValues() {
        XCTAssertEqual(RedundantAudioCaptureManager.FailoverEvent.FailoverReason.silence.rawValue, "Silence detected")
        XCTAssertEqual(RedundantAudioCaptureManager.FailoverEvent.FailoverReason.clipping.rawValue, "Excessive clipping")
        XCTAssertEqual(RedundantAudioCaptureManager.FailoverEvent.FailoverReason.engineStopped.rawValue, "Capture engine stopped")
        XCTAssertEqual(RedundantAudioCaptureManager.FailoverEvent.FailoverReason.manual.rawValue, "Manual override")
    }
    
    // MARK: - RedundancyHealth Enum Tests
    
    func testRedundancyHealthEnum() {
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.healthy.rawValue, "Healthy")
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.degraded.rawValue, "Degraded")
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.critical.rawValue, "Critical")
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.unknown.rawValue, "Unknown")
    }
    
    func testRedundancyHealthColors() {
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.healthy.color, .green)
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.degraded.color, .orange)
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.critical.color, .red)
        XCTAssertEqual(RedundantAudioCaptureManager.RedundancyHealth.unknown.color, .gray)
    }
    
    // MARK: - RedundancyStats Tests
    
    func testRedundancyStatsSummary() {
        let stats = RedundancyStats(
            primaryFrameCount: 1000,
            backupFrameCount: 500,
            activeSource: .primary,
            primaryLastFrame: Date(),
            backupLastFrame: Date(timeIntervalSinceNow: -5),
            failoverCount: 2
        )
        
        let summary = stats.summary
        XCTAssertTrue(summary.contains("Primary (System Audio)"))
        XCTAssertTrue(summary.contains("1000"))
        XCTAssertTrue(summary.contains("500"))
        XCTAssertTrue(summary.contains("2"))
    }

    // MARK: - Config Overrides

    func testFailoverThresholdDefaultsMatchExpected() {
        UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailoverSilenceSeconds)
        UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailoverCooldownSeconds)
        UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailbackStabilizationSeconds)

        XCTAssertEqual(manager.effectiveFailoverSilenceThreshold, 2.0, accuracy: 0.0001)
        XCTAssertEqual(manager.effectiveFailoverCooldown, 5.0, accuracy: 0.0001)
        XCTAssertEqual(manager.effectiveFailbackStabilizationPeriod, 10.0, accuracy: 0.0001)
    }

    func testFailoverThresholdUserDefaultsOverridesApply() {
        defer {
            UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailoverSilenceSeconds)
            UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailoverCooldownSeconds)
            UserDefaults.standard.removeObject(forKey: RedundantAudioCaptureManager.defaultsKeyFailbackStabilizationSeconds)
        }

        UserDefaults.standard.set(3.5, forKey: RedundantAudioCaptureManager.defaultsKeyFailoverSilenceSeconds)
        UserDefaults.standard.set(7.0, forKey: RedundantAudioCaptureManager.defaultsKeyFailoverCooldownSeconds)
        UserDefaults.standard.set(12.0, forKey: RedundantAudioCaptureManager.defaultsKeyFailbackStabilizationSeconds)

        XCTAssertEqual(manager.effectiveFailoverSilenceThreshold, 3.5, accuracy: 0.0001)
        XCTAssertEqual(manager.effectiveFailoverCooldown, 7.0, accuracy: 0.0001)
        XCTAssertEqual(manager.effectiveFailbackStabilizationPeriod, 12.0, accuracy: 0.0001)
    }
}
