import Foundation
import CryptoKit

/// SessionBundle manages the collection and export of session artifacts
/// for debugging and support purposes.
///
/// A session bundle includes:
/// - receipt.json: Metadata and configuration
/// - events.ndjson: Timeline of session events
/// - metrics.ndjson: 1Hz metric samples
/// - transcript_realtime.json: Transcript as received
/// - transcript_final.json: Final processed transcript
/// - drops_summary.json: Frame drop analysis
/// - audio_manifest.json: Audio file references (no audio by default)
/// - logs/client.log: Structured client logs
/// - logs/server.log: Server stdout/stderr
///
/// Privacy: Audio is NOT included by default. Users must explicitly opt-in.
@MainActor
final class SessionBundle {

    enum ExportError: LocalizedError {
        case zipFailed(exitCode: Int32)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let exitCode):
                return "Failed to create session bundle archive (zip exit code \(exitCode))."
            }
        }
    }
    
    // MARK: - Types
    
    struct Configuration {
        var includeAudio: Bool = false
        var includeTranscript: Bool = true
        var includeMetrics: Bool = true
        var includeLogs: Bool = true
        var maxBundleSizeMB: Int = 50
        
        static let `default` = Configuration()
        static let privacySafe = Configuration(includeAudio: false, includeTranscript: true, includeMetrics: true, includeLogs: true)
    }
    
    enum BundleEventType: String {
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case wsConnect = "ws_connect"
        case wsDisconnect = "ws_disconnect"
        case wsStatus = "ws_status"
        case firstAudioFrame = "first_audio_frame"
        case firstASR = "first_asr"
        case asrPartial = "asr_partial"
        case asrFinal = "asr_final"
        case frameDrop = "frame_drop"
        case error = "error"
        case warning = "warning"
        case metrics = "metrics"
    }
    
    struct BundleEvent {
        let timestamp: TimeInterval
        let type: BundleEventType
        let metadata: [String: Any]
        
        func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "timestamp": timestamp,
                "type": type.rawValue
            ]
            if !metadata.isEmpty {
                dict["metadata"] = metadata
            }
            return dict
        }
    }
    
    // MARK: - Properties
    
    let sessionId: String
    let createdAt: Date
    private(set) var configuration: Configuration
    
    private var events: [BundleEvent] = []
    private var metrics: [SourceMetrics] = []
    private var transcriptRealtime: [[String: Any]] = []
    private var transcriptFinal: [[String: Any]] = []
    private var droppedFrames: [(timestamp: TimeInterval, source: String, total: Int)] = []
    private var voiceNotes: [[String: Any]] = []
    
    private let eventsLock = NSLock()
    private let metricsLock = NSLock()
    private let transcriptLock = NSLock()
    private let voiceNotesLock = NSLock()
    
    private var sessionStartDate: Date?
    private var sessionEndDate: Date?
    private var audioSource: String?
    private var appVersion: String?
    
    // MARK: - Initialization
    
    init(sessionId: String, configuration: Configuration = .default) {
        self.sessionId = sessionId
        self.createdAt = Date()
        self.configuration = configuration
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    // MARK: - Event Recording
    
    func recordEvent(_ type: BundleEventType, metadata: [String: Any] = [:]) {
        let event = BundleEvent(
            timestamp: Date().timeIntervalSince1970,
            type: type,
            metadata: metadata
        )
        
        eventsLock.lock()
        events.append(event)
        eventsLock.unlock()
    }
    
    func recordSessionStart(audioSource: String) {
        self.sessionStartDate = Date()
        self.audioSource = audioSource
        recordEvent(.sessionStart, metadata: ["audio_source": audioSource])
    }
    
    func recordSessionEnd(finalization: String) {
        self.sessionEndDate = Date()
        recordEvent(.sessionEnd, metadata: ["finalization": finalization])
    }
    
    func recordWebSocketStatus(state: String, message: String? = nil) {
        var metadata: [String: Any] = ["state": state]
        if let message = message {
            metadata["message"] = message
        }
        recordEvent(.wsStatus, metadata: metadata)
    }
    
    func recordFrameDrop(source: String, totalDropped: Int) {
        let timestamp = Date().timeIntervalSince1970
        droppedFrames.append((timestamp: timestamp, source: source, total: totalDropped))
        recordEvent(.frameDrop, metadata: [
            "source": source,
            "dropped_total": totalDropped
        ])
    }
    
    func recordError(_ error: Error, context: String? = nil) {
        var metadata: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription
        ]
        if let context = context {
            metadata["context"] = context
        }
        recordEvent(.error, metadata: metadata)
    }
    
    // MARK: - Metrics Recording
    
    func recordMetrics(_ metrics: SourceMetrics) {
        metricsLock.lock()
        self.metrics.append(metrics)
        metricsLock.unlock()
        
        // Also record as event for key thresholds
        if metrics.queueFillRatio > 0.95 {
            recordEvent(.warning, metadata: [
                "warning_type": "queue_critical",
                "queue_fill_ratio": metrics.queueFillRatio,
                "source": metrics.source
            ])
        } else if metrics.queueFillRatio > 0.85 {
            recordEvent(.warning, metadata: [
                "warning_type": "queue_high",
                "queue_fill_ratio": metrics.queueFillRatio,
                "source": metrics.source
            ])
        }
    }
    
    // MARK: - Transcript Recording
    
    func recordTranscriptSegment(_ segment: TranscriptSegment) {
        let dict: [String: Any] = [
            "text": segment.text,
            "t0": segment.t0,
            "t1": segment.t1,
            "is_final": segment.isFinal,
            "confidence": segment.confidence,
            "source": segment.source ?? "unknown",
            "speaker": segment.speaker ?? NSNull(),
            "timestamp": Date().timeIntervalSince1970
        ]
        
        transcriptLock.lock()
        transcriptRealtime.append(dict)
        transcriptLock.unlock()
    }
    
    func setFinalTranscript(_ segments: [TranscriptSegment]) {
        transcriptLock.lock()
        transcriptFinal = segments.map { segment in
            [
                "text": segment.text,
                "t0": segment.t0,
                "t1": segment.t1,
                "is_final": segment.isFinal,
                "confidence": segment.confidence,
                "source": segment.source ?? "unknown",
                "speaker": segment.speaker ?? NSNull()
            ]
        }
        transcriptLock.unlock()
    }
    
    // MARK: - Voice Notes Recording
    
    func recordVoiceNote(_ note: VoiceNote) {
        let dict: [String: Any] = [
            "id": note.id.uuidString,
            "text": note.text,
            "start_time": note.startTime,
            "end_time": note.endTime,
            "created_at": ISO8601DateFormatter().string(from: note.createdAt),
            "confidence": note.confidence,
            "is_pinned": note.isPinned,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        voiceNotesLock.lock()
        voiceNotes.append(dict)
        voiceNotesLock.unlock()
        
        // Also record as event
        recordEvent(.asrFinal, metadata: [
            "voice_note_id": note.id.uuidString,
            "text_length": note.text.count
        ])
    }
    
    func setVoiceNotes(_ notes: [VoiceNote]) {
        voiceNotesLock.lock()
        voiceNotes = notes.map { note in
            [
                "id": note.id.uuidString,
                "text": note.text,
                "start_time": note.startTime,
                "end_time": note.endTime,
                "created_at": ISO8601DateFormatter().string(from: note.createdAt),
                "confidence": note.confidence,
                "is_pinned": note.isPinned
            ]
        }
        voiceNotesLock.unlock()
    }
    
    // MARK: - Bundle Generation
    
    func generateBundle() async throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let bundleName = "echopanel_session_\(sessionId.prefix(8))_\(timestamp).bundle"
        let bundleURL = tempDir.appendingPathComponent(bundleName)
        
        // Create bundle directory
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        
        // Generate all files
        try await generateReceipt(bundleURL: bundleURL)
        try await generateEvents(bundleURL: bundleURL)
        try await generateMetrics(bundleURL: bundleURL)
        try await generateTranscript(bundleURL: bundleURL)
        try await generateDropsSummary(bundleURL: bundleURL)
        try await generateAudioManifest(bundleURL: bundleURL)
        try await generateLogs(bundleURL: bundleURL)
        
        return bundleURL
    }
    
    func exportBundle(to destinationURL: URL) async throws {
        let bundleURL = try await generateBundle()
        
        // Create zip
        let zipURL = bundleURL.appendingPathExtension("zip")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", zipURL.path, bundleURL.lastPathComponent]
        process.currentDirectoryURL = bundleURL.deletingLastPathComponent()
        
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExportError.zipFailed(exitCode: process.terminationStatus)
        }

        // Copy to destination
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: zipURL, to: destinationURL)
        
        // Cleanup
        try? fm.removeItem(at: bundleURL)
        try? fm.removeItem(at: zipURL)
    }
    
    // MARK: - Private File Generation
    
    private func generateReceipt(bundleURL: URL) async throws {
        var receipt: [String: Any] = [
            "receipt_version": "1.0",
            "session_id": sessionId,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "client_info": [
                "app_version": appVersion ?? "unknown",
                "os_version": await getOSVersion(),
                "machine_id": getHashedMachineId()
            ],
            "flags": [
                "has_audio": configuration.includeAudio,
                "has_transcript": configuration.includeTranscript,
                "has_metrics": configuration.includeMetrics,
                "has_logs": configuration.includeLogs
            ]
        ]
        
        // Add session summary if available
        if let startDate = sessionStartDate {
            var summary: [String: Any] = [
                "started_at": ISO8601DateFormatter().string(from: startDate),
                "audio_source": audioSource ?? "unknown"
            ]
            
            if let endDate = sessionEndDate {
                summary["ended_at"] = ISO8601DateFormatter().string(from: endDate)
                summary["duration_seconds"] = endDate.timeIntervalSince(startDate)
            }
            
            summary["total_transcript_segments"] = transcriptRealtime.count
            summary["dropped_frames_total"] = droppedFrames.last?.total ?? 0
            summary["max_queue_fill_ratio"] = metrics.map { $0.queueFillRatio }.max() ?? 0.0
            
            receipt["session_summary"] = summary
        }
        
        let receiptURL = bundleURL.appendingPathComponent("receipt.json")
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: receiptURL)
    }
    
    private func generateEvents(bundleURL: URL) async throws {
        let eventsCopy = await eventsLock.withLock { events }
        
        let eventsURL = bundleURL.appendingPathComponent("events.ndjson")
        var eventsData = Data()
        
        for event in eventsCopy {
            let dict = event.toDictionary()
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys) {
                eventsData.append(jsonData)
                eventsData.append(Data("\n".utf8))
            }
        }
        
        try eventsData.write(to: eventsURL)
    }
    
    private func generateMetrics(bundleURL: URL) async throws {
        guard configuration.includeMetrics else { return }
        
        let metricsCopy = await metricsLock.withLock { metrics }
        
        let metricsURL = bundleURL.appendingPathComponent("metrics.ndjson")
        var metricsData = Data()
        
        for metric in metricsCopy {
            let dict: [String: Any] = [
                "timestamp": metric.timestamp,
                "session_id": metric.sessionId ?? sessionId,
                "attempt_id": metric.attemptId,
                "connection_id": metric.connectionId,
                "source": metric.source,
                "queue_depth": metric.queueDepth,
                "queue_max": metric.queueMax,
                "queue_fill_ratio": metric.queueFillRatio,
                "dropped_total": metric.droppedTotal,
                "dropped_recent": metric.droppedRecent,
                "avg_infer_ms": metric.avgInferMs,
                "realtime_factor": metric.realtimeFactor
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys) {
                metricsData.append(jsonData)
                metricsData.append(Data("\n".utf8))
            }
        }
        
        try metricsData.write(to: metricsURL)
    }
    
    private func generateTranscript(bundleURL: URL) async throws {
        guard configuration.includeTranscript else { return }
        
        let (realtimeCopy, finalCopy) = await transcriptLock.withLock { (transcriptRealtime, transcriptFinal) }
        
        // Realtime transcript
        let realtimeURL = bundleURL.appendingPathComponent("transcript_realtime.json")
        let realtimeData = try JSONSerialization.data(withJSONObject: realtimeCopy, options: [.prettyPrinted, .sortedKeys])
        try realtimeData.write(to: realtimeURL)
        
        // Final transcript
        if !finalCopy.isEmpty {
            let finalURL = bundleURL.appendingPathComponent("transcript_final.json")
            let finalData = try JSONSerialization.data(withJSONObject: finalCopy, options: [.prettyPrinted, .sortedKeys])
            try finalData.write(to: finalURL)
        }
    }
    
    private func generateDropsSummary(bundleURL: URL) async throws {
        let dropIntervals = calculateDropIntervals()
        
        let summary: [String: Any] = [
            "total_dropped_frames": droppedFrames.last?.total ?? 0,
            "drop_count": droppedFrames.count,
            "drop_intervals": dropIntervals,
            "by_source": calculateDropsBySource()
        ]
        
        let dropsURL = bundleURL.appendingPathComponent("drops_summary.json")
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: dropsURL)
    }
    
    private func generateAudioManifest(bundleURL: URL) async throws {
        let manifest: [String: Any] = [
            "note": "Audio files not included by default for privacy",
            "included": configuration.includeAudio,
            "files": [],
            "opt_in_instructions": "To include audio, enable 'Share audio samples' in Settings"
        ]
        
        let manifestURL = bundleURL.appendingPathComponent("audio_manifest.json")
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL)
    }
    
    private func generateLogs(bundleURL: URL) async throws {
        guard configuration.includeLogs else { return }
        
        let logsDir = bundleURL.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Client logs
        let clientLogs = StructuredLogger.shared.getLogFileURLs()
        if let mainLog = clientLogs.first,
           let logData = try? Data(contentsOf: mainLog) {
            let clientLogURL = logsDir.appendingPathComponent("client.log")
            try logData.write(to: clientLogURL)
        }
        
        // Server logs
        let serverLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("echopanel_server.log")
        if FileManager.default.fileExists(atPath: serverLogURL.path),
           let logData = try? Data(contentsOf: serverLogURL) {
            let destinationURL = logsDir.appendingPathComponent("server.log")
            try logData.write(to: destinationURL)
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateDropIntervals() -> [[String: Any]] {
        guard droppedFrames.count > 1 else { return [] }
        
        var intervals: [[String: Any]] = []
        var currentInterval: (start: TimeInterval, count: Int, source: String)?
        
        for drop in droppedFrames {
            if let interval = currentInterval {
                // If within 2 seconds of previous, extend interval
                if drop.timestamp - interval.start < 2.0 && drop.source == interval.source {
                    currentInterval = (interval.start, interval.count + 1, interval.source)
                } else {
                    // Close previous interval
                    intervals.append([
                        "start": interval.start,
                        "end": drop.timestamp,
                        "count": interval.count,
                        "source": interval.source
                    ])
                    currentInterval = (drop.timestamp, 1, drop.source)
                }
            } else {
                currentInterval = (drop.timestamp, 1, drop.source)
            }
        }
        
        // Close final interval
        if let interval = currentInterval {
            intervals.append([
                "start": interval.start,
                "end": Date().timeIntervalSince1970,
                "count": interval.count,
                "source": interval.source
            ])
        }
        
        return intervals
    }
    
    private func calculateDropsBySource() -> [String: Int] {
        var bySource: [String: Int] = [:]
        for drop in droppedFrames {
            bySource[drop.source, default: 0] += 1
        }
        return bySource
    }
    
    private func getOSVersion() async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
        process.arguments = ["-productVersion"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        } catch {
            return "unknown"
        }
    }
    
    private func getHashedMachineId() -> String {
        // Use system UUID, hashed for privacy
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Extract UUID from output
            if let range = output.range(of: "IOPlatformUUID\" = \"") {
                let start = output.index(range.upperBound, offsetBy: 0)
                if let end = output[start...].firstIndex(of: "\"") {
                    let uuid = String(output[start..<end])
                    // Hash it for privacy
                    return sha256(uuid).prefix(16).description
                }
            }
        } catch {
            // Ignore
        }
        
        return "unknown"
    }
    
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AppState Integration

extension AppState {
    /// Get or create the session bundle for the current session
    var sessionBundle: SessionBundle? {
        get {
            // Store bundle in associated object or separate manager
            return SessionBundleManager.shared.bundle(for: sessionID ?? "")
        }
        set {
            if let sessionID = sessionID {
                SessionBundleManager.shared.setBundle(newValue, for: sessionID)
            }
        }
    }
}

/// Manager for active session bundles
@MainActor
final class SessionBundleManager {
    static let shared = SessionBundleManager()
    
    private var bundles: [String: SessionBundle] = [:]
    
    func bundle(for sessionId: String) -> SessionBundle? {
        return bundles[sessionId]
    }
    
    func setBundle(_ bundle: SessionBundle?, for sessionId: String) {
        bundles[sessionId] = bundle
    }
    
    func createBundle(for sessionId: String, configuration: SessionBundle.Configuration = .default) -> SessionBundle {
        let bundle = SessionBundle(sessionId: sessionId, configuration: configuration)
        bundles[sessionId] = bundle
        return bundle
    }
}
