import XCTest
@testable import MeetingListenerApp

@MainActor
final class AuthPolicyTests: XCTestCase {
    func testStartSessionRequiresTokenForRemoteBackend() {
        // Ensure we're in "remote backend" mode.
        UserDefaults.standard.set("example.com", forKey: "backendHost")
        defer { UserDefaults.standard.removeObject(forKey: "backendHost") }

        // Ensure no token exists.
        _ = KeychainHelper.deleteBackendToken()

        let appState = AppState()
        appState.startSession()

        XCTAssertEqual(appState.sessionState, .idle)
        XCTAssertEqual(
            appState.runtimeErrorState,
            .backendNotReady(detail: "Backend token required for remote backend. Set it in Settings → Backend Token.")
        )
    }
}

