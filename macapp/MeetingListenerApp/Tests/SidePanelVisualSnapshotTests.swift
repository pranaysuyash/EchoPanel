import AppKit
import SwiftUI
import XCTest
import SnapshotTesting
@testable import MeetingListenerApp

@MainActor
final class SidePanelVisualSnapshotTests: XCTestCase {
    private static let recordSnapshots = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Snapshot tests are inherently environment-sensitive (fonts, rendering, OS updates).
        // Keep them opt-in so "swift test" is stable for day-to-day verification.
        let shouldRun = ProcessInfo.processInfo.environment["RUN_VISUAL_SNAPSHOTS"] == "1"
        try XCTSkipUnless(shouldRun, "Visual snapshot tests are opt-in. Set RUN_VISUAL_SNAPSHOTS=1 to run.")

        UserDefaults.standard.removeObject(forKey: "sidePanel.viewMode")
    }

    func testRollViewLight() {
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .light,
            named: "roll-light"
        )
    }

    func testRollViewDark() {
        assertPanelSnapshot(
            mode: .roll,
            size: CGSize(width: 430, height: 820),
            colorScheme: .dark,
            named: "roll-dark"
        )
    }

    func testCompactViewLight() {
        assertPanelSnapshot(
            mode: .compact,
            size: CGSize(width: 390, height: 760),
            colorScheme: .light,
            named: "compact-light"
        )
    }

    func testCompactViewDark() {
        assertPanelSnapshot(
            mode: .compact,
            size: CGSize(width: 390, height: 760),
            colorScheme: .dark,
            named: "compact-dark"
        )
    }

    func testFullViewLight() {
        assertPanelSnapshot(
            mode: .full,
            size: CGSize(width: 1180, height: 760),
            colorScheme: .light,
            named: "full-light"
        )
    }

    func testFullViewDark() {
        assertPanelSnapshot(
            mode: .full,
            size: CGSize(width: 1180, height: 760),
            colorScheme: .dark,
            named: "full-dark"
        )
    }

    private func assertPanelSnapshot(
        mode: SidePanelView.ViewMode,
        size: CGSize,
        colorScheme: ColorScheme,
        named: String
    ) {
        UserDefaults.standard.set(mode.rawValue, forKey: "sidePanel.viewMode")

        let appState = AppState()
        appState.seedDemoData()
        appState.screenRecordingPermission = .denied
        appState.microphonePermission = .authorized
        appState.noAudioDetected = false
        appState.audioSource = .both

        let view = SidePanelView(
            appState: appState,
            onEndSession: {},
            onModeChange: nil
        )
        .preferredColorScheme(colorScheme)

        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        assertSnapshot(
            of: hostingView,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                size: size
            ),
            named: nil,
            record: Self.recordSnapshots,
            timeout: 10,
            testName: named
        )
    }
}
