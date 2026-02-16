import Foundation
import Cocoa

/// CrashReporter captures and stores uncaught exceptions for debugging
/// Privacy-first: crash logs are stored locally, user must explicitly share them
@MainActor
final class CrashReporter {
    static let shared = CrashReporter()
    
    private let maxCrashLogs = 5
    private let crashLogsDirectory: URL
    private let fileManager = FileManager.default
    
    struct CrashLog: Codable, Identifiable {
        let id: String
        let timestamp: Date
        let appVersion: String
        let osVersion: String
        let exceptionName: String
        let exceptionReason: String
        let stackTrace: [String]
        let threadName: String
        
        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: timestamp)
        }
    }
    
    private init() {
        // Set up crash logs directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.echopanel"
        crashLogsDirectory = appSupport.appendingPathComponent(bundleId).appendingPathComponent("CrashLogs")
        
        try? fileManager.createDirectory(at: crashLogsDirectory, withIntermediateDirectories: true)
        
        // Register for uncaught exception notifications
        setupExceptionHandler()
    }
    
    // MARK: - Exception Handling
    
    private func setupExceptionHandler() {
        // Register for uncaught exceptions
        // Note: NSException handling is limited in Swift; we catch what we can
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }
        
        NSLog("CrashReporter: Exception handler registered")
    }
    
    /// Handle uncaught exception (called from exception handler)
    nonisolated func handleException(_ exception: NSException) {
        let crashLog = createCrashLog(from: exception)
        
        // Save on main actor
        Task { @MainActor in
            saveCrashLog(crashLog)
            NSLog("CrashReporter: Crash logged - \(exception.name.rawValue)")
        }
    }
    
    /// Create crash log from exception (nonisolated for handler callback)
    nonisolated private func createCrashLog(from exception: NSException) -> CrashLog {
        let stackTrace = exception.callStackSymbols
        let thread = Thread.current
        
        // Get app version from bundle (safe to access from nonisolated)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        
        return CrashLog(
            id: UUID().uuidString,
            timestamp: Date(),
            appVersion: version,
            osVersion: osVersionString,
            exceptionName: exception.name.rawValue,
            exceptionReason: exception.reason ?? "No reason provided",
            stackTrace: stackTrace,
            threadName: thread.name ?? "Unknown"
        )
    }
    
    // MARK: - Properties
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    // MARK: - Public API
    
    /// Get all stored crash logs, sorted by date (newest first)
    func getCrashLogs() -> [CrashLog] {
        guard let files = try? fileManager.contentsOfDirectory(at: crashLogsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let logs = files.compactMap { url -> CrashLog? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CrashLog.self, from: data)
        }
        
        return logs.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get the most recent crash log
    var mostRecentCrash: CrashLog? {
        getCrashLogs().first
    }
    
    /// Check if any crash logs exist
    var hasCrashes: Bool {
        !getCrashLogs().isEmpty
    }
    
    /// Delete a specific crash log
    func deleteCrashLog(id: String) -> Bool {
        let url = crashLogURL(id: id)
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch {
            NSLog("CrashReporter: Failed to delete crash log: \(error)")
            return false
        }
    }
    
    /// Delete all crash logs
    func deleteAllCrashLogs() -> Bool {
        let logs = getCrashLogs()
        var success = true
        
        for log in logs {
            if !deleteCrashLog(id: log.id) {
                success = false
            }
        }
        
        return success
    }
    
    /// Generate formatted crash report for sharing
    func generateCrashReport(id: String) -> String? {
        guard let log = getCrashLogs().first(where: { $0.id == id }) else { return nil }
        
        var report = """
        EchoPanel Crash Report
        ======================
        
        Crash ID: \(log.id)
        Date: \(log.formattedDate)
        App Version: \(log.appVersion)
        macOS Version: \(log.osVersion)
        Thread: \(log.threadName)
        
        Exception
        ---------
        Name: \(log.exceptionName)
        Reason: \(log.exceptionReason)
        
        Stack Trace
        -----------
        """
        
        for (index, frame) in log.stackTrace.enumerated() {
            report += "\n\(index): \(frame)"
        }
        
        return report
    }
    
    /// Copy crash report to clipboard
    func copyCrashReportToClipboard(id: String) -> Bool {
        guard let report = generateCrashReport(id: id) else { return false }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        return true
    }
    
    /// Export all crash logs to a file
    func exportAllCrashLogs() -> URL? {
        let logs = getCrashLogs()
        guard !logs.isEmpty else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let exportName = "echopanel_crash_logs_\(timestamp).txt"
        let exportURL = fileManager.temporaryDirectory.appendingPathComponent(exportName)
        
        var report = "EchoPanel Crash Logs Export\n"
        report += "===========================\n"
        report += "Generated: \(Date())\n"
        report += "App Version: \(appVersion)\n\n"
        
        for (index, log) in logs.enumerated() {
            report += "\n--- Crash #\(index + 1) ---\n"
            if let logReport = generateCrashReport(id: log.id) {
                report += logReport
            }
        }
        
        do {
            try report.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            NSLog("CrashReporter: Failed to export crash logs: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func saveCrashLog(_ log: CrashLog) {
        // Clean up old logs first
        cleanupOldLogs()
        
        let url = crashLogURL(id: log.id)
        
        do {
            let data = try JSONEncoder().encode(log)
            try data.write(to: url)
            NSLog("CrashReporter: Saved crash log to \(url.path)")
        } catch {
            NSLog("CrashReporter: Failed to save crash log: \(error)")
        }
    }
    
    private func cleanupOldLogs() {
        var logs = getCrashLogs()
        
        // Keep only the most recent maxCrashLogs
        while logs.count >= maxCrashLogs {
            if let oldest = logs.popLast() {
                _ = deleteCrashLog(id: oldest.id)
            }
        }
    }
    
    private func crashLogURL(id: String) -> URL {
        crashLogsDirectory.appendingPathComponent("\(id).json")
    }
}

// MARK: - Diagnostic Integration

extension CrashReporter {
    /// Get diagnostic info for the Diagnostics view
    struct DiagnosticInfo {
        let crashCount: Int
        let lastCrashDate: Date?
        let hasRecentCrashes: Bool
    }
    
    var diagnosticInfo: DiagnosticInfo {
        let logs = getCrashLogs()
        let recentThreshold = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours
        
        return DiagnosticInfo(
            crashCount: logs.count,
            lastCrashDate: logs.first?.timestamp,
            hasRecentCrashes: logs.contains { $0.timestamp > recentThreshold }
        )
    }
}
