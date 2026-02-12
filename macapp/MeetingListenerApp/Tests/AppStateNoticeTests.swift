import XCTest
@testable import MeetingListenerApp

@MainActor
final class AppStateNoticeTests: XCTestCase {
    func testRecordExportFailureSetsPersistentErrorNotice() {
        let appState = AppState()

        struct ExportFailure: LocalizedError {
            var errorDescription: String? { "Disk full" }
        }

        appState.recordExportFailure(format: "JSON", error: ExportFailure())

        XCTAssertEqual(appState.userNotice?.level, .error)
        XCTAssertEqual(appState.userNotice?.message, "JSON export failed: Disk full")
    }

    func testRecordCredentialSaveFailureSetsErrorNotice() {
        let appState = AppState()
        appState.recordCredentialSaveFailure(field: "backend token")

        XCTAssertEqual(appState.userNotice?.level, .error)
        XCTAssertEqual(
            appState.userNotice?.message,
            "Failed to save backend token. Check Keychain access and try again."
        )
    }

    func testSetUserNoticeAutoClears() async {
        let appState = AppState()
        appState.setUserNotice("Saved", level: .success, autoClearAfter: 0.05)

        XCTAssertEqual(appState.userNotice?.message, "Saved")
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(appState.userNotice)
    }
}
