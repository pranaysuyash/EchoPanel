import XCTest
@testable import MeetingListenerApp

@MainActor
final class DataRetentionManagerTests: XCTestCase {

    func testCleanupDeletesOnlyOldSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("echopanel-retention-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        SessionStore.shared.overrideSessionsDirectoryForTesting(tempDir)
        defer {
            SessionStore.shared.restoreDefaultSessionsDirectoryForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let oldSessionId = "session-old"
        let recentSessionId = "session-recent"

        try createSessionDirectory(at: tempDir, sessionId: oldSessionId, startedAt: Date().addingTimeInterval(-120 * 24 * 60 * 60))
        try createSessionDirectory(at: tempDir, sessionId: recentSessionId, startedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60))

        let deletedCount = DataRetentionManager.shared.cleanupOldSessions(retentionDays: 90)

        XCTAssertEqual(deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(oldSessionId).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(recentSessionId).path))
    }

    func testSessionsToDeleteReflectsRetention() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("echopanel-retention-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        SessionStore.shared.overrideSessionsDirectoryForTesting(tempDir)
        defer {
            SessionStore.shared.restoreDefaultSessionsDirectoryForTesting()
            try? FileManager.default.removeItem(at: tempDir)
        }

        let oldSessionId = "session-old"
        let recentSessionId = "session-recent"

        try createSessionDirectory(at: tempDir, sessionId: oldSessionId, startedAt: Date().addingTimeInterval(-40 * 24 * 60 * 60))
        try createSessionDirectory(at: tempDir, sessionId: recentSessionId, startedAt: Date().addingTimeInterval(-5 * 24 * 60 * 60))

        let sessions = DataRetentionManager.shared.sessionsToDelete(retentionDays: 30)
        let ids = Set(sessions.map { $0.id })

        XCTAssertTrue(ids.contains(oldSessionId))
        XCTAssertFalse(ids.contains(recentSessionId))
    }

    private func createSessionDirectory(at baseURL: URL, sessionId: String, startedAt: Date) throws {
        let sessionDir = baseURL.appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let metadataURL = sessionDir.appendingPathComponent("metadata.json")
        let metadata: [String: Any] = [
            "session_id": sessionId,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "audio_source": "system",
            "app_version": "test"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted])
        try metadataData.write(to: metadataURL)
    }
}
