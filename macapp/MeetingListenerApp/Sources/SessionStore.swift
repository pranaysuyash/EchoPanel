import Foundation

/// SessionStore manages local persistence of session data for auto-save and crash recovery.
/// 
/// Data is stored in the app's sandbox (Application Support directory) as JSON/JSONL files:
/// - `sessions/<session_id>/snapshot.json`: Current session state (periodic save)
/// - `sessions/<session_id>/transcript.jsonl`: Append-only transcript log
/// - `sessions/<session_id>/metadata.json`: Session metadata (start time, source, etc.)
/// - `sessions/recovery.json`: Reference to any unfinished session for crash recovery
final class SessionStore: ObservableObject {
    
    static let shared = SessionStore()
    
    @Published var hasRecoverableSession: Bool = false
    @Published var recoverableSessionId: String?
    @Published var recoverableSessionDate: Date?
    
    private let fileManager = FileManager.default
    private var sessionsDirectory: URL?
    private var currentSessionDirectory: URL?
    private var transcriptFileHandle: FileHandle?
    private var saveTimer: Timer?
    
    private let saveInterval: TimeInterval = 30.0 // Auto-save every 30 seconds
    
    init() {
        setupDirectory()
        checkForRecoverableSession()
    }
    
    // MARK: - Directory Setup
    
    private func setupDirectory() {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("SessionStore: Failed to get Application Support directory")
            return
        }
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.echopanel"
        sessionsDirectory = appSupport.appendingPathComponent(bundleId).appendingPathComponent("sessions")
        
        do {
            try fileManager.createDirectory(at: sessionsDirectory!, withIntermediateDirectories: true)
            NSLog("SessionStore: Sessions directory: \(sessionsDirectory!.path)")
        } catch {
            NSLog("SessionStore: Failed to create sessions directory: \(error)")
        }
    }
    
    // MARK: - Session Lifecycle
    
    func startSession(sessionId: String, audioSource: String) {
        guard let sessionsDir = sessionsDirectory else { return }
        
        currentSessionDirectory = sessionsDir.appendingPathComponent(sessionId)
        
        do {
            try fileManager.createDirectory(at: currentSessionDirectory!, withIntermediateDirectories: true)
            
            // Write metadata
            let metadata: [String: Any] = [
                "session_id": sessionId,
                "started_at": ISO8601DateFormatter().string(from: Date()),
                "audio_source": audioSource,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            ]
            let metadataURL = currentSessionDirectory!.appendingPathComponent("metadata.json")
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted])
            try metadataData.write(to: metadataURL)
            
            // Create transcript file
            let transcriptURL = currentSessionDirectory!.appendingPathComponent("transcript.jsonl")
            fileManager.createFile(atPath: transcriptURL.path, contents: nil)
            transcriptFileHandle = try FileHandle(forWritingTo: transcriptURL)
            
            // Mark session as recoverable
            markSessionRecoverable(sessionId: sessionId)
            
            // Start auto-save timer
            startAutoSave()
            
            NSLog("SessionStore: Started session \(sessionId)")
        } catch {
            NSLog("SessionStore: Failed to start session: \(error)")
        }
    }
    
    func endSession(sessionId: String, finalData: [String: Any]) {
        stopAutoSave()
        
        // Write final snapshot
        saveSnapshot(data: finalData, isFinal: true)
        
        // Close transcript file
        try? transcriptFileHandle?.close()
        transcriptFileHandle = nil
        
        // Clear recovery marker
        clearRecoveryMarker()
        
        currentSessionDirectory = nil
        hasRecoverableSession = false
        recoverableSessionId = nil
        
        NSLog("SessionStore: Ended session \(sessionId)")
        NotificationCenter.default.post(name: .sessionHistoryShouldRefresh, object: nil)
        NotificationCenter.default.post(name: .sessionEnded, object: nil, userInfo: ["session_id": sessionId])
    }
    
    // MARK: - Data Persistence
    
    func appendTranscriptSegment(_ segment: [String: Any]) {
        guard let handle = transcriptFileHandle else { return }
        
        do {
            var jsonData = try JSONSerialization.data(withJSONObject: segment, options: [])
            jsonData.append(Data("\n".utf8))
            try handle.write(contentsOf: jsonData)
        } catch {
            NSLog("SessionStore: Failed to append transcript: \(error)")
        }
    }
    
    func saveSnapshot(data: [String: Any], isFinal: Bool = false) {
        guard let sessionDir = currentSessionDirectory else { return }
        
        let filename = isFinal ? "final_snapshot.json" : "snapshot.json"
        let snapshotURL = sessionDir.appendingPathComponent(filename)
        
        do {
            var snapshotData = data
            snapshotData["saved_at"] = ISO8601DateFormatter().string(from: Date())
            snapshotData["is_final"] = isFinal
            
            let jsonData = try JSONSerialization.data(withJSONObject: snapshotData, options: [.prettyPrinted])
            try jsonData.write(to: snapshotURL)
            
            NSLog("SessionStore: Saved snapshot (\(isFinal ? "final" : "periodic"))")
        } catch {
            NSLog("SessionStore: Failed to save snapshot: \(error)")
        }
    }
    
    // MARK: - Auto-save
    
    private func startAutoSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveInterval, repeats: true) { _ in
            // Auto-save will be triggered by AppState
            NotificationCenter.default.post(name: .sessionAutoSaveRequested, object: nil)
        }
    }
    
    private func stopAutoSave() {
        saveTimer?.invalidate()
        saveTimer = nil
    }
    
    // MARK: - Crash Recovery
    
    private func markSessionRecoverable(sessionId: String) {
        guard let sessionsDir = sessionsDirectory else { return }
        
        let recoveryURL = sessionsDir.appendingPathComponent("recovery.json")
        let recoveryData: [String: Any] = [
            "session_id": sessionId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: recoveryData, options: [])
            try jsonData.write(to: recoveryURL)
        } catch {
            NSLog("SessionStore: Failed to write recovery marker: \(error)")
        }
    }
    
    private func clearRecoveryMarker() {
        guard let sessionsDir = sessionsDirectory else { return }
        
        let recoveryURL = sessionsDir.appendingPathComponent("recovery.json")
        try? fileManager.removeItem(at: recoveryURL)
    }
    
    private func checkForRecoverableSession() {
        guard let sessionsDir = sessionsDirectory else { return }
        
        let recoveryURL = sessionsDir.appendingPathComponent("recovery.json")
        
        guard fileManager.fileExists(atPath: recoveryURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: recoveryURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessionId = json["session_id"] as? String,
               let timestampStr = json["timestamp"] as? String,
               let timestamp = ISO8601DateFormatter().date(from: timestampStr) {
                
                recoverableSessionId = sessionId
                recoverableSessionDate = timestamp
                hasRecoverableSession = true
                
                NSLog("SessionStore: Found recoverable session \(sessionId) from \(timestamp)")
            }
        } catch {
            NSLog("SessionStore: Failed to read recovery marker: \(error)")
        }
    }
    
    func loadRecoverableSession() -> [String: Any]? {
        guard let sessionId = recoverableSessionId,
              let sessionsDir = sessionsDirectory else { return nil }
        
        let sessionDir = sessionsDir.appendingPathComponent(sessionId)
        let snapshotURL = sessionDir.appendingPathComponent("snapshot.json")
        
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: snapshotURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {
            NSLog("SessionStore: Failed to load recoverable session: \(error)")
        }
        
        return nil
    }

    func loadSnapshot(sessionId: String) -> [String: Any]? {
        guard let sessionsDir = sessionsDirectory else { return nil }
        let sessionDir = sessionsDir.appendingPathComponent(sessionId)
        let finalURL = sessionDir.appendingPathComponent("final_snapshot.json")
        let snapshotURL = sessionDir.appendingPathComponent("snapshot.json")

        let url = fileManager.fileExists(atPath: finalURL.path) ? finalURL : snapshotURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        } catch {
            NSLog("SessionStore: Failed to load snapshot: \(error)")
        }
        return nil
    }
    
    func discardRecoverableSession() {
        guard let sessionId = recoverableSessionId,
              let sessionsDir = sessionsDirectory else { return }
        
        let sessionDir = sessionsDir.appendingPathComponent(sessionId)
        try? fileManager.removeItem(at: sessionDir)
        clearRecoveryMarker()
        
        hasRecoverableSession = false
        recoverableSessionId = nil
        recoverableSessionDate = nil
        
        NSLog("SessionStore: Discarded recoverable session \(sessionId)")
        NotificationCenter.default.post(name: .sessionHistoryShouldRefresh, object: nil)
    }

    func deleteSession(sessionId: String) {
        guard let sessionsDir = sessionsDirectory else { return }

        let sessionDir = sessionsDir.appendingPathComponent(sessionId)
        do {
            if fileManager.fileExists(atPath: sessionDir.path) {
                try fileManager.removeItem(at: sessionDir)
            }
        } catch {
            NSLog("SessionStore: Failed to delete session %@: %@", sessionId, error.localizedDescription)
        }

        if recoverableSessionId == sessionId {
            clearRecoveryMarker()
            hasRecoverableSession = false
            recoverableSessionId = nil
            recoverableSessionDate = nil
        }

        NotificationCenter.default.post(name: .sessionHistoryShouldRefresh, object: nil)
    }
    
    // MARK: - Session History
    
    func listSessions() -> [(id: String, date: Date, hasTranscript: Bool)] {
        guard let sessionsDir = sessionsDirectory else { return [] }
        
        var sessions: [(id: String, date: Date, hasTranscript: Bool)] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.creationDateKey])
            
            for url in contents {
                guard url.hasDirectoryPath else { continue }
                
                let sessionId = url.lastPathComponent
                let metadataURL = url.appendingPathComponent("metadata.json")
                let transcriptURL = url.appendingPathComponent("transcript.jsonl")
                
                var date = Date()
                if let metadataData = try? Data(contentsOf: metadataURL),
                   let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                   let startedStr = metadata["started_at"] as? String,
                   let startedDate = ISO8601DateFormatter().date(from: startedStr) {
                    date = startedDate
                }
                
                let hasTranscript = fileManager.fileExists(atPath: transcriptURL.path)
                sessions.append((id: sessionId, date: date, hasTranscript: hasTranscript))
            }
        } catch {
            NSLog("SessionStore: Failed to list sessions: \(error)")
        }
        
        return sessions.sorted { $0.date > $1.date }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let sessionAutoSaveRequested = Notification.Name("sessionAutoSaveRequested")
    static let sessionEnded = Notification.Name("sessionEnded")
}
