import Foundation

/// Manages automatic data retention and cleanup for session storage
@MainActor
final class DataRetentionManager {
    static let shared = DataRetentionManager()
    
    private let cleanupInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private var cleanupTimer: Timer?
    private let defaults = UserDefaults.standard
    private let lastCleanupKey = "lastDataCleanupDate"
    private let retentionPeriodKey = "dataRetentionPeriod"
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Start automatic cleanup scheduling
    func start() {
        defaults.register(defaults: [retentionPeriodKey: 90])
        // Run cleanup on startup if needed
        runCleanupIfNeeded()
        
        // Schedule periodic cleanup
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runCleanupIfNeeded()
            }
        }
        
        NSLog("DataRetentionManager: Started with interval \(cleanupInterval)s")
    }
    
    /// Stop automatic cleanup scheduling
    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        NSLog("DataRetentionManager: Stopped")
    }
    
    // MARK: - Cleanup Logic
    
    /// Run cleanup if retention period is set and last cleanup was over 24 hours ago
    private func runCleanupIfNeeded() {
        let retentionDays = defaults.integer(forKey: retentionPeriodKey)
        
        // Skip if retention is disabled (0 = never delete)
        guard retentionDays > 0 else { return }
        
        // Check if we need to run cleanup
        if let lastCleanup = defaults.object(forKey: lastCleanupKey) as? Date {
            let hoursSinceLastCleanup = Date().timeIntervalSince(lastCleanup) / 3600
            if hoursSinceLastCleanup < 24 {
                NSLog("DataRetentionManager: Skipping cleanup, last run \(hoursSinceLastCleanup)h ago")
                return
            }
        }
        
        // Run cleanup
        let deletedCount = cleanupOldSessions(retentionDays: retentionDays)
        NSLog("DataRetentionManager: Cleanup complete, deleted \(deletedCount) sessions")
    }
    
    /// Delete sessions older than the specified retention period
    /// - Parameter retentionDays: Number of days to retain sessions (sessions older than this are deleted)
    /// - Returns: Number of sessions deleted
    @discardableResult
    func cleanupOldSessions(retentionDays: Int) -> Int {
        guard retentionDays > 0 else { return 0 }
        
        let cutoffDate = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let sessions = SessionStore.shared.listSessions()
        
        var deletedCount = 0
        for session in sessions {
            if session.date < cutoffDate {
                if deleteSession(sessionId: session.id) {
                    deletedCount += 1
                }
            }
        }
        
        // Record cleanup date
        defaults.set(Date(), forKey: lastCleanupKey)

        if deletedCount > 0 {
            NotificationCenter.default.post(name: .sessionHistoryShouldRefresh, object: nil)
        }
        
        // Log result
        if deletedCount > 0 {
            NSLog("DataRetentionManager: Deleted \(deletedCount) sessions older than \(retentionDays) days")
            StructuredLogger.shared.info("Data retention cleanup completed", metadata: [
                "deletedSessions": deletedCount,
                "retentionDays": retentionDays,
                "cutoffDate": cutoffDate.iso8601
            ])
        } else {
            NSLog("DataRetentionManager: No sessions older than \(retentionDays) days to delete")
        }
        
        return deletedCount
    }
    
    /// Delete a specific session and its data
    private func deleteSession(sessionId: String) -> Bool {
        guard let sessionDir = SessionStore.shared.sessionDirectoryURL(sessionId: sessionId) else {
            return false
        }
        
        do {
            try FileManager.default.removeItem(at: sessionDir)
            return true
        } catch {
            NSLog("DataRetentionManager: Failed to delete session \(sessionId): \(error)")
            return false
        }
    }
    
    // MARK: - Statistics
    
    /// Get sessions that would be deleted with the given retention period
    func sessionsToDelete(retentionDays: Int) -> [(id: String, date: Date)] {
        guard retentionDays > 0 else { return [] }
        
        let cutoffDate = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let allSessions = SessionStore.shared.listSessions()
        
        return allSessions
            .filter { $0.date < cutoffDate }
            .map { (id: $0.id, date: $0.date) }
    }
    
    /// Get the date of the last cleanup
    var lastCleanupDate: Date? {
        defaults.object(forKey: lastCleanupKey) as? Date
    }
}

// MARK: - Date Extension

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
