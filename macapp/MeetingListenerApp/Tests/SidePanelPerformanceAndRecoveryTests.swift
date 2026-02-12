import AppKit
import SwiftUI
import XCTest
@testable import MeetingListenerApp

@MainActor
final class SidePanelPerformanceTests: XCTestCase {
    func testFilteringLargeTranscriptPerformance() {
        let segments = makeSegments(count: 2_000)
        let filter = EntityItem(name: "EchoPanel", type: "org", count: 12, lastSeen: 120, confidence: 0.9)

        measure {
            _ = SidePanelView.filterTranscriptSegments(
                segments,
                entityFilter: filter,
                normalizedFullQuery: "echopanel",
                viewMode: .full
            )
        }
    }

    func testFullModeRenderLayoutPerformance() {
        UserDefaults.standard.set(SidePanelView.ViewMode.full.rawValue, forKey: "sidePanel.viewMode")

        let appState = AppState()
        appState.seedDemoData()
        appState.transcriptSegments = makeSegments(count: 500)

        let view = SidePanelView(appState: appState, onEndSession: {}, onModeChange: nil)
            .preferredColorScheme(.dark)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
        hostingView.layoutSubtreeIfNeeded()

        measure {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
        }
    }

    private func makeSegments(count: Int) -> [TranscriptSegment] {
        (0..<count).map { index in
            TranscriptSegment(
                text: index.isMultiple(of: 3)
                    ? "EchoPanel review item \(index)"
                    : "General transcript line \(index)",
                t0: TimeInterval(index),
                t1: TimeInterval(index + 1),
                isFinal: true,
                confidence: 0.8,
                source: index.isMultiple(of: 2) ? "system" : "mic",
                speaker: index.isMultiple(of: 2) ? "Speaker A" : "Speaker B"
            )
        }
    }
}

@MainActor
final class BackendRecoveryUXTests: XCTestCase {
    func testBackendUXStateTransitions() {
        let manager = BackendManager.shared
        let appState = AppState()

        let originalIsReady = manager.isServerReady
        let originalStatus = manager.serverStatus
        let originalDetail = manager.healthDetail
        let originalRecovery = manager.recoveryPhase

        defer {
            manager._testSetState(
                isServerReady: originalIsReady,
                serverStatus: originalStatus,
                healthDetail: originalDetail,
                recoveryPhase: originalRecovery
            )
        }

        manager._testSetState(
            isServerReady: false,
            serverStatus: .starting,
            healthDetail: "",
            recoveryPhase: .idle
        )
        XCTAssertEqual(appState.backendUXState, .preparing)

        manager._testSetState(
            isServerReady: false,
            serverStatus: .starting,
            healthDetail: "Restarting (attempt 2/3)...",
            recoveryPhase: .retryScheduled(attempt: 2, maxAttempts: 3, delay: 2)
        )
        XCTAssertEqual(appState.backendUXState, .recovering(attempt: 2, maxAttempts: 3))

        manager._testSetState(
            isServerReady: false,
            serverStatus: .error,
            healthDetail: "Port 8000 is already in use.",
            recoveryPhase: .failed(attempts: 3, maxAttempts: 3)
        )
        XCTAssertEqual(appState.backendUXState, .failed(detail: "Port 8000 is already in use."))

        manager._testSetState(
            isServerReady: true,
            serverStatus: .running,
            healthDetail: "ASR ready",
            recoveryPhase: .idle
        )
        XCTAssertEqual(appState.backendUXState, .ready)
    }

    func testBackendHealthTimeoutDefaultsAndOverrides() {
        let key = "backendHealthTimeoutSeconds"
        let defaults = UserDefaults.standard
        let originalObject = defaults.object(forKey: key)

        defer {
            if let value = originalObject {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(BackendConfig.healthCheckTimeout, 2.0, accuracy: 0.0001)

        defaults.set(4.5, forKey: key)
        XCTAssertEqual(BackendConfig.healthCheckTimeout, 4.5, accuracy: 0.0001)

        defaults.set(0.05, forKey: key)
        XCTAssertEqual(BackendConfig.healthCheckTimeout, 0.2, accuracy: 0.0001)
    }

    func testWebSocketURLDoesNotContainQueryToken() {
        let components = URLComponents(url: BackendConfig.webSocketURL, resolvingAgainstBaseURL: false)
        XCTAssertNil(components?.query)
    }

    func testStagedAudioFeatureFlagsDefaultToOffAndReadOverrides() {
        let defaults = UserDefaults.standard
        let driftKey = "broadcast_useClockDriftCompensation"
        let vadKey = "broadcast_useClientVAD"
        let originalDrift = defaults.object(forKey: driftKey)
        let originalVAD = defaults.object(forKey: vadKey)

        defer {
            if let originalDrift {
                defaults.set(originalDrift, forKey: driftKey)
            } else {
                defaults.removeObject(forKey: driftKey)
            }
            if let originalVAD {
                defaults.set(originalVAD, forKey: vadKey)
            } else {
                defaults.removeObject(forKey: vadKey)
            }
        }

        defaults.removeObject(forKey: driftKey)
        defaults.removeObject(forKey: vadKey)
        XCTAssertFalse(BackendConfig.clockDriftCompensationEnabled)
        XCTAssertFalse(BackendConfig.clientVADEnabled)

        defaults.set(true, forKey: driftKey)
        defaults.set(true, forKey: vadKey)
        XCTAssertTrue(BackendConfig.clockDriftCompensationEnabled)
        XCTAssertTrue(BackendConfig.clientVADEnabled)
    }
}
