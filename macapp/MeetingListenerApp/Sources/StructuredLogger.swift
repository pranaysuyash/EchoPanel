import Foundation
import os.log

/// Structured logging system for EchoPanel with correlation ID support.
///
/// All logs are output as JSON for machine parsing, with human-readable
/// fallbacks for development. Correlation IDs (session_id, attempt_id, connection_id)
/// are automatically included in every log entry.
///
/// Usage:
///   logger.info("Session started", metadata: ["audio_source": "both"])
///   logger.error("ASR failed", error: error, metadata: ["source": "mic"])
final class StructuredLogger {
    
    // MARK: - Log Levels
    
    enum Level: String, CaseIterable, Comparable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
        
        static func < (lhs: Level, rhs: Level) -> Bool {
            let order: [Level] = [.debug, .info, .warning, .error, .critical]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
    
    // MARK: - Correlation Context
    
    /// Thread-safe correlation context for logging
    struct CorrelationContext {
        let sessionId: String?
        let attemptId: String?
        let connectionId: String?
        let sourceId: String?
        
        var isEmpty: Bool {
            sessionId == nil && attemptId == nil && connectionId == nil && sourceId == nil
        }
        
        func toDictionary() -> [String: String] {
            var dict: [String: String] = [:]
            if let sessionId = sessionId { dict["session_id"] = sessionId }
            if let attemptId = attemptId { dict["attempt_id"] = attemptId }
            if let connectionId = connectionId { dict["connection_id"] = connectionId }
            if let sourceId = sourceId { dict["source_id"] = sourceId }
            return dict
        }
    }
    
    // MARK: - Configuration
    
    struct Configuration {
        var minLevel: Level = .info
        var enableConsoleOutput: Bool = true
        var enableFileOutput: Bool = true
        var enableOSLog: Bool = true
        var maxFileSizeBytes: Int = 10 * 1024 * 1024  // 10 MB
        var maxFileCount: Int = 5
        var redactionPatterns: [RedactionPattern] = RedactionPattern.defaults
        
        static let `default` = Configuration()
    }
    
    struct RedactionPattern {
        let pattern: String
        let replacement: String
        let description: String
        
        static let defaults: [RedactionPattern] = [
            // API tokens (HuggingFace, OpenAI, etc.)
            RedactionPattern(
                pattern: "hf_[a-zA-Z0-9]{20,}",
                replacement: "***",
                description: "HuggingFace token"
            ),
            RedactionPattern(
                pattern: "sk-[a-zA-Z0-9]{20,}",
                replacement: "***",
                description: "API key"
            ),
            // Bearer tokens
            RedactionPattern(
                pattern: "Bearer\\s+[a-zA-Z0-9_\\-\\.]{20,}",
                replacement: "Bearer ***",
                description: "Bearer token"
            ),
            // File paths with PII (usernames)
            RedactionPattern(
                pattern: "/Users/[^/]+/",
                replacement: "~/",
                description: "User home directory"
            ),
            // Query param tokens
            RedactionPattern(
                pattern: "token=[a-zA-Z0-9_\\-\\.]{10,}",
                replacement: "token=***",
                description: "URL token"
            )
        ]
    }
    
    // MARK: - Singleton
    
    static let shared = StructuredLogger()
    
    // MARK: - Properties
    
    private let configuration: Configuration
    private let osLog: OSLog
    private var currentContext: CorrelationContext = CorrelationContext(
        sessionId: nil,
        attemptId: nil,
        connectionId: nil,
        sourceId: nil
    )
    
    private var logFileURL: URL?
    private var logFileHandle: FileHandle?
    private let fileQueue = DispatchQueue(label: "com.echopanel.logger.file", qos: .utility)
    
    // Sampling counters for high-frequency events
    private var sampleCounters: [String: Int] = [:]
    private let sampleLock = NSLock()
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.echopanel", category: "StructuredLogger")
        
        if configuration.enableFileOutput {
            setupLogFile()
        }
    }
    
    // MARK: - Context Management
    
    func setContext(
        sessionId: String? = nil,
        attemptId: String? = nil,
        connectionId: String? = nil,
        sourceId: String? = nil
    ) {
        currentContext = CorrelationContext(
            sessionId: sessionId ?? currentContext.sessionId,
            attemptId: attemptId ?? currentContext.attemptId,
            connectionId: connectionId ?? currentContext.connectionId,
            sourceId: sourceId ?? currentContext.sourceId
        )
    }
    
    func clearContext() {
        currentContext = CorrelationContext(sessionId: nil, attemptId: nil, connectionId: nil, sourceId: nil)
    }
    
    func withContext<T>(
        sessionId: String? = nil,
        attemptId: String? = nil,
        connectionId: String? = nil,
        sourceId: String? = nil,
        operation: () -> T
    ) -> T {
        let previousContext = currentContext
        setContext(sessionId: sessionId, attemptId: attemptId, connectionId: connectionId, sourceId: sourceId)
        defer { currentContext = previousContext }
        return operation()
    }
    
    // MARK: - Logging Methods
    
    func debug(
        _ message: String,
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, error: nil, metadata: metadata, file: file, function: function, line: line)
    }
    
    func info(
        _ message: String,
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, error: nil, metadata: metadata, file: file, function: function, line: line)
    }
    
    func warning(
        _ message: String,
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, error: nil, metadata: metadata, file: file, function: function, line: line)
    }
    
    func error(
        _ message: String,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, error: error, metadata: metadata, file: file, function: function, line: line)
    }
    
    func critical(
        _ message: String,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .critical, message: message, error: error, metadata: metadata, file: file, function: function, line: line)
    }
    
    // MARK: - Sampling Support
    
    /// Log with sampling - only log 1 out of every N calls
    func logSampled(
        level: Level,
        message: String,
        sampleKey: String,
        sampleRate: Int,  // 1 = always, 100 = 1%
        metadata: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        sampleLock.lock()
        let count = (sampleCounters[sampleKey] ?? 0) + 1
        sampleCounters[sampleKey] = count
        sampleLock.unlock()
        
        if count % sampleRate == 0 {
            var enrichedMetadata = metadata ?? [:]
            enrichedMetadata["sample_key"] = sampleKey
            enrichedMetadata["sample_count"] = count
            enrichedMetadata["sample_rate"] = sampleRate
            log(level: level, message: message, error: nil, metadata: enrichedMetadata, file: file, function: function, line: line)
        }
    }
    
    // MARK: - Private Implementation
    
    private func log(
        level: Level,
        message: String,
        error: Error?,
        metadata: [String: Any]?,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= configuration.minLevel else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let component = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        
        // Build structured log entry
        var entry: [String: Any] = [
            "timestamp": timestamp,
            "level": level.rawValue,
            "message": redact(message),
            "component": component,
            "function": function,
            "line": line
        ]
        
        // Add correlation context
        if !currentContext.isEmpty {
            entry["context"] = currentContext.toDictionary()
        }
        
        // Add error details if present
        if let error = error {
            entry["error"] = [
                "type": String(describing: type(of: error)),
                "message": redact(error.localizedDescription),
                "localized": error.localizedDescription != String(describing: error) ? redact(error.localizedDescription) : nil
            ].compactMapValues { $0 }
        }
        
        // Add metadata (with redaction)
        if let metadata = metadata {
            let redactedMetadata = metadata.mapValues { value -> Any in
                if let stringValue = value as? String {
                    return redact(stringValue)
                }
                return value
            }
            entry["metadata"] = redactedMetadata
        }
        
        // Output to all configured destinations
        if configuration.enableOSLog {
            writeToOSLog(level: level, message: message, entry: entry)
        }
        
        if configuration.enableConsoleOutput {
            writeToConsole(entry: entry)
        }
        
        if configuration.enableFileOutput {
            writeToFile(entry: entry)
        }
    }
    
    private func redact(_ text: String) -> String {
        var result = text
        for pattern in configuration.redactionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern.pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: pattern.replacement
                )
            }
        }
        return result
    }
    
    private func writeToOSLog(level: Level, message: String, entry: [String: Any]) {
        let logMessage = "[\(level.rawValue)] \(message)"
        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)
    }
    
    private func writeToConsole(entry: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
    
    private func writeToFile(entry: [String: Any]) {
        guard let logFileHandle = logFileHandle else { return }
        
        fileQueue.async {
            if let jsonData = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys),
               var jsonString = String(data: jsonData, encoding: .utf8) {
                jsonString.append("\n")
                if let data = jsonString.data(using: .utf8) {
                    logFileHandle.write(data)
                }
            }
        }
    }
    
    // MARK: - File Management
    
    private func setupLogFile() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("StructuredLogger: Failed to get Application Support directory")
            return
        }
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.echopanel"
        let logsDir = appSupport.appendingPathComponent(bundleId).appendingPathComponent("logs")
        
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            
            logFileURL = logsDir.appendingPathComponent("echopanel.log")
            
            // Create file if it doesn't exist
            if !FileManager.default.fileExists(atPath: logFileURL!.path) {
                FileManager.default.createFile(atPath: logFileURL!.path, contents: nil)
            }
            
            logFileHandle = try FileHandle(forWritingTo: logFileURL!)
            logFileHandle?.seekToEndOfFile()
            
            // Check if rotation needed
            rotateLogsIfNeeded()
            
        } catch {
            NSLog("StructuredLogger: Failed to setup log file: \(error)")
        }
    }
    
    private func rotateLogsIfNeeded() {
        guard let logFileURL = logFileURL else { return }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            if let fileSize = attributes[.size] as? Int,
               fileSize >= configuration.maxFileSizeBytes {
                rotateLogs()
            }
        } catch {
            // Ignore rotation errors
        }
    }
    
    private func rotateLogs() {
        guard let logFileURL = logFileURL else { return }
        
        let fileManager = FileManager.default
        let logsDir = logFileURL.deletingLastPathComponent()
        
        // Rotate existing files
        for i in (1..<configuration.maxFileCount).reversed() {
            let oldURL = logsDir.appendingPathComponent("echopanel.log.\(i)")
            let newURL = logsDir.appendingPathComponent("echopanel.log.\(i + 1)")
            
            if fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.removeItem(at: newURL)
                try? fileManager.moveItem(at: oldURL, to: newURL)
            }
        }
        
        // Move current to .1
        let newURL = logsDir.appendingPathComponent("echopanel.log.1")
        try? fileManager.removeItem(at: newURL)
        try? fileManager.moveItem(at: logFileURL, to: newURL)
        
        // Create new file
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
        
        // Reopen file handle
        logFileHandle?.closeFile()
        logFileHandle = try? FileHandle(forWritingTo: logFileURL)
    }
    
    // MARK: - Log Retrieval
    
    func getLogFileURLs() -> [URL] {
        guard let logsDir = logFileURL?.deletingLastPathComponent() else { return [] }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
            return files.filter { $0.lastPathComponent.hasPrefix("echopanel.log") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            return []
        }
    }
    
    func readRecentLogs(maxLines: Int = 1000) -> [[String: Any]] {
        guard let logFileURL = logFileURL else { return [] }
        
        do {
            let data = try Data(contentsOf: logFileURL)
            guard let content = String(data: data, encoding: .utf8) else { return [] }
            
            let lines = content.split(separator: "\n").suffix(maxLines)
            
            var entries: [[String: Any]] = []
            for line in lines {
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    entries.append(json)
                }
            }
            
            return entries
        } catch {
            return []
        }
    }
}

// MARK: - Convenience Extensions

extension StructuredLogger {
    /// Quick log for session lifecycle events
    func logSessionEvent(
        _ event: String,
        sessionId: String,
        metadata: [String: Any]? = nil
    ) {
        setContext(sessionId: sessionId)
        info("Session event: \(event)", metadata: metadata)
    }
    
    /// Quick log for WebSocket events
    func logWebSocketEvent(
        _ event: String,
        connectionId: String,
        metadata: [String: Any]? = nil
    ) {
        setContext(connectionId: connectionId)
        debug("WebSocket event: \(event)", metadata: metadata)
    }
    
    /// Quick log for audio/streaming events
    func logAudioEvent(
        _ event: String,
        source: String,
        metadata: [String: Any]? = nil,
        level: Level = .debug
    ) {
        setContext(sourceId: source)
        
        // Use sampling for high-frequency audio events
        if event.contains("frame") {
            logSampled(
                level: level,
                message: "Audio event: \(event)",
                sampleKey: "audio_\(event)_\(source)",
                sampleRate: 100,  // 1% sampling
                metadata: metadata
            )
        } else {
            switch level {
            case .debug: debug("Audio event: \(event)", metadata: metadata)
            case .info: info("Audio event: \(event)", metadata: metadata)
            case .warning: warning("Audio event: \(event)", metadata: metadata)
            case .error: error("Audio event: \(event)", metadata: metadata)
            case .critical: critical("Audio event: \(event)", metadata: metadata)
            }
        }
    }
}
