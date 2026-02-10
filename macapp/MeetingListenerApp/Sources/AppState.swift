import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    enum PermissionState {
        case unknown
        case nonInteractive // During init
        case authorized
        case denied
    }
    
    enum AudioSource: String, CaseIterable {
        case system = "System Audio"
        case microphone = "Microphone"
        case both = "Both"
    }

    enum AppRuntimeErrorState: Equatable {
        case backendNotReady(detail: String)
        case screenRecordingPermissionRequired
        case screenRecordingRequiresRelaunch
        case microphonePermissionRequired
        case systemCaptureFailed(detail: String)
        case microphoneCaptureFailed(detail: String)
        case streaming(detail: String)

        var message: String {
            switch self {
            case .backendNotReady(let detail):
                return detail.isEmpty ? "Backend not ready. Open Diagnostics to see logs." : detail
            case .screenRecordingPermissionRequired:
                return "Screen Recording permission required for System Audio. Open Settings → Privacy & Security → Screen Recording."
            case .screenRecordingRequiresRelaunch:
                return "Screen Recording permission was granted, but macOS requires you to quit and relaunch EchoPanel before system audio can be captured."
            case .microphonePermissionRequired:
                return "Microphone permission required for Microphone audio"
            case .systemCaptureFailed(let detail):
                return "Capture failed: \(detail)"
            case .microphoneCaptureFailed(let detail):
                return "Mic capture failed: \(detail)"
            case .streaming(let detail):
                return detail
            }
        }

        var isStreamingError: Bool {
            if case .streaming = self {
                return true
            }
            return false
        }
    }

    enum BackendUXState: Equatable {
        case ready
        case preparing
        case recovering(attempt: Int, maxAttempts: Int)
        case failed(detail: String)
    }

    struct SourceProbe: Identifiable {
        let id: String
        let label: String
        let inputAgeSeconds: Int?
        let asrAgeSeconds: Int?

        var inputIsFresh: Bool {
            guard let inputAgeSeconds else { return false }
            return inputAgeSeconds <= 3
        }

        var asrIsFresh: Bool {
            guard let asrAgeSeconds else { return false }
            return asrAgeSeconds <= 8
        }

        var inputAgeText: String {
            guard let inputAgeSeconds else { return "none" }
            return inputAgeSeconds <= 1 ? "live" : "\(inputAgeSeconds)s"
        }

        var asrAgeText: String {
            guard let asrAgeSeconds else { return "none" }
            return asrAgeSeconds <= 1 ? "live" : "\(asrAgeSeconds)s"
        }
    }

    @Published var sessionState: SessionState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var audioQuality: AudioQuality = .unknown
    @Published var streamStatus: StreamStatus = .reconnecting
    @Published var statusMessage: String = ""
    @Published var runtimeErrorState: AppRuntimeErrorState?
    @Published private(set) var transcriptRevision: Int = 0
    
    // Permission Tracking
    @Published var screenRecordingPermission: PermissionState = .unknown
    @Published var microphonePermission: PermissionState = .unknown
    
    // Audio Source Selection (v0.2)
    @Published var audioSource: AudioSource = .both
    @Published var systemAudioLevel: Float = 0
    @Published var microphoneAudioLevel: Float = 0
    
    @Published var permissionDebugLine: String = ""
    @Published var debugLine: String = ""
    var isDebugEnabled: Bool { debugEnabled }
    
    // Diagnostics (v0.2)
    @Published var lastMessageDate: Date?
    @Published var inputLastSeenBySource: [String: Date] = [:]
    @Published var asrLastSeenBySource: [String: Date] = [:]
    @Published var asrEventCount: Int = 0
    
    // Gap 2 fix: Silence detection
    @Published var noAudioDetected: Bool = false
    @Published var silenceMessage: String = ""
    private var lastAudioTimestamp: Date?
    private var silenceCheckTimer: Timer?

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var actions: [ActionItem] = []
    @Published var decisions: [DecisionItem] = []
    @Published var risks: [RiskItem] = []
    @Published var entities: [EntityItem] = []
    @Published var contextDocuments: [ContextDocument] = []
    @Published var contextQueryResults: [ContextQueryResult] = []
    @Published var contextQuery: String = ""
    @Published var contextStatusMessage: String = ""
    @Published var contextBusy: Bool = false
    
    // PR2: Metrics tracking
    @Published var lastMetrics: [String: SourceMetrics] = [:]
    @Published var backpressureLevel: BackpressureLevel = .normal
    
    enum BackpressureLevel {
        case normal
        case buffering
        case overloaded
    }

    // H9 Fix: Expose backend status
    var isServerReady: Bool { BackendManager.shared.isServerReady }
    var serverStatus: BackendManager.ServerStatus { BackendManager.shared.serverStatus }
    var backendUXState: BackendUXState {
        if isServerReady {
            return .ready
        }

        let manager = BackendManager.shared
        switch manager.recoveryPhase {
        case .retryScheduled(let attempt, let maxAttempts, _):
            return .recovering(attempt: attempt, maxAttempts: maxAttempts)
        case .failed:
            let detail = manager.healthDetail.isEmpty ? "Backend failed to start." : manager.healthDetail
            return .failed(detail: detail)
        case .idle:
            if manager.serverStatus == .error || manager.serverStatus == .runningNeedsSetup {
                let detail = manager.healthDetail.isEmpty ? "Backend not ready." : manager.healthDetail
                return .failed(detail: detail)
            }
            return .preparing
        }
    }

    @Published var finalSummaryMarkdown: String = ""
    @Published var finalSummaryJSON: [String: Any] = [:]
    @Published var finalizationOutcome: FinalizationOutcome = .none

    enum FinalizationOutcome: String {
        case none
        case complete
        case incompleteTimeout
        case incompleteError
    }

    private var sessionID: String?
    private var sessionStart: Date?
    private var sessionEnd: Date?
    private var timerCancellable: AnyCancellable?
    private var permissionCancellable: AnyCancellable?
    private var lastPartialIndexBySource: [String: Int] = [:]
    
    // PR1: UI Handshake - track attempt ID and timeout
    private var startAttemptId: UUID?
    private var startTimeoutTask: Task<Void, Never>?

    private let audioCapture = AudioCaptureManager()
    private let micCapture = MicrophoneCaptureManager()
    private let streamer: WebSocketStreamer
    // Note: URL hardcoding is acceptable for v0.2 MVP as per M9 resolution plan (low risk local app)
    // But ideally should read from configuration. Keeping as is for now to avoid large refactor risk.
    private let sessionStore = SessionStore.shared
    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var debugSamples: Int = 0
    private var debugBytes: Int = 0
    private var debugScreenFrames: Int = 0
    private var autoSaveCancellable: AnyCancellable?
    private var lastContextRefreshAt: Date?

    init() {
        streamer = WebSocketStreamer()
        refreshPermissionStatuses()
        permissionCancellable = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshPermissionStatuses()
            }

        audioCapture.onSampleCount = { [weak self] sampleCount in
            Task { @MainActor in
                self?.debugSamples = sampleCount
                self?.updateDebugLine()
            }
        }
        audioCapture.onScreenFrameCount = { [weak self] frameCount in
            Task { @MainActor in
                self?.debugScreenFrames = frameCount
                self?.updateDebugLine()
            }
        }
        audioCapture.onAudioQualityUpdate = { [weak self] quality in
            Task { @MainActor in self?.audioQuality = quality }
        }
        audioCapture.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in self?.systemAudioLevel = level }
        }
        audioCapture.onPCMFrame = { [weak self] frame, source in
            guard let self else { return }
            Task { @MainActor in
                self.debugBytes += frame.count
                if self.debugEnabled {
                    self.updateDebugLine()
                }
                self.markInputFrame(source: source)
                self.lastAudioTimestamp = Date()
                if self.noAudioDetected {
                    self.noAudioDetected = false
                    self.silenceMessage = ""
                }
            }
            self.streamer.sendPCMFrame(frame, source: source)
        }
        
        // Mic capture callbacks (v0.2)
        micCapture.onPCMFrame = { [weak self] frame, source in
            guard let self else { return }
            Task { @MainActor in
                self.debugBytes += frame.count
                if self.debugEnabled {
                    self.updateDebugLine()
                }
                self.markInputFrame(source: source)
                self.lastAudioTimestamp = Date()
                if self.noAudioDetected {
                    self.noAudioDetected = false
                    self.silenceMessage = ""
                }
            }
            self.streamer.sendPCMFrame(frame, source: source)
        }
        micCapture.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in self?.microphoneAudioLevel = level }
        }

        streamer.onStatus = { [weak self] status, message in
            Task { @MainActor in
                self?.streamStatus = status
                self?.statusMessage = message
                
                // PR1: Handle streaming ACK from backend
                if status == .streaming && self?.sessionState == .starting {
                    self?.startTimeoutTask?.cancel()
                    self?.startTimeoutTask = nil
                    self?.sessionState = .listening
                }
                
                if status == .error {
                    self?.runtimeErrorState = .streaming(detail: message)
                    self?.startTimeoutTask?.cancel()
                    self?.startTimeoutTask = nil
                } else if self?.runtimeErrorState?.isStreamingError == true {
                    self?.runtimeErrorState = nil
                }
            }
        }
        
        // PR2: Handle metrics from backend
        streamer.onMetrics = { [weak self] metrics in
            Task { @MainActor in
                self?.lastMetrics[metrics.source] = metrics
                
                // Update backpressure level based on metrics
                if metrics.queueFillRatio > 0.95 || metrics.droppedRecent > 0 {
                    self?.backpressureLevel = .overloaded
                } else if metrics.queueFillRatio > 0.85 || metrics.realtimeFactor > 1.0 {
                    self?.backpressureLevel = .buffering
                } else {
                    self?.backpressureLevel = .normal
                }
            }
        }
        streamer.onASRPartial = { [weak self] text, t0, t1, confidence, source in
            Task { @MainActor in 
                self?.lastMessageDate = Date()
                self?.markASREvent(source: source)
                self?.handlePartial(text: text, t0: t0, t1: t1, confidence: confidence, source: source) 
            }
        }
        streamer.onASRFinal = { [weak self] text, t0, t1, confidence, source in
            Task { @MainActor in 
                self?.lastMessageDate = Date()
                self?.markASREvent(source: source)
                self?.handleFinal(text: text, t0: t0, t1: t1, confidence: confidence, source: source) 
            }
        }
        streamer.onCardsUpdate = { [weak self] actions, decisions, risks in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.actions = actions
                    self?.decisions = decisions
                    self?.risks = risks
                }
            }
        }
        streamer.onEntitiesUpdate = { [weak self] entities in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.entities = entities
                }
            }
        }
        streamer.onFinalSummary = { [weak self] markdown, jsonObject in
            Task { @MainActor in
                self?.finalSummaryMarkdown = markdown
                self?.finalSummaryJSON = jsonObject
                self?.finalizationOutcome = .complete
                
                // H8 Fix: Update transcript with diarized speakers
                if let transcriptData = jsonObject["transcript"] as? [[String: Any]] {
                    var newSegments: [TranscriptSegment] = []
                    for item in transcriptData {
                        guard let text = item["text"] as? String,
                              let t0 = item["t0"] as? TimeInterval,
                              let t1 = item["t1"] as? TimeInterval else { continue }
                        let confidence = (item["confidence"] as? Double) ?? 0.0
                        let isFinal = item["is_final"] as? Bool ?? true
                        let source = item["source"] as? String
                        var segment = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: isFinal, confidence: confidence, source: source)
                        segment.speaker = item["speaker"] as? String
                        newSegments.append(segment)
                    }
                    self?.transcriptSegments = newSegments
                    self?.bumpTranscriptRevision()
                }

                NotificationCenter.default.post(name: .finalSummaryReady, object: nil)
            }
        }
        
        // Auto-save observer (v0.2)
        autoSaveCancellable = NotificationCenter.default.publisher(for: .sessionAutoSaveRequested)
            .sink { [weak self] _ in
                self?.saveSnapshot()
            }
    }

    var statusLine: String {
        if sessionState == .idle && streamStatus != .error {
            return isServerReady ? "Ready" : "Preparing backend"
        }
        let base: String
        switch streamStatus {
        case .streaming: base = "Streaming"
        case .reconnecting: base = "Reconnecting"
        case .error: base = "Setup needed"
        }
        if statusMessage.isEmpty { return base }
        return "\(base) - \(statusMessage)"
    }

    var timerText: String {
        let displaySeconds = effectiveElapsedSeconds
        let minutes = displaySeconds / 60
        let seconds = displaySeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var activeSourceProbes: [SourceProbe] {
        let now = Date()
        let sourceIDs: [String]
        switch audioSource {
        case .system:
            sourceIDs = ["system"]
        case .microphone:
            sourceIDs = ["mic"]
        case .both:
            sourceIDs = ["system", "mic"]
        }

        return sourceIDs.map { sourceID in
            let label = sourceID == "system" ? "System" : "Mic"
            let inputAge = inputLastSeenBySource[sourceID].map { max(0, Int(now.timeIntervalSince($0))) }
            let asrAge = asrLastSeenBySource[sourceID].map { max(0, Int(now.timeIntervalSince($0))) }
            return SourceProbe(id: sourceID, label: label, inputAgeSeconds: inputAge, asrAgeSeconds: asrAge)
        }
    }

    var captureRouteDescription: String {
        switch audioSource {
        case .system:
            return "System Audio captures output from apps/tabs (browser, Zoom, players)."
        case .microphone:
            return "Microphone captures your selected input device."
        case .both:
            return "Both captures app/tab output plus your microphone input."
        }
    }

    var sourceTroubleshootingHint: String? {
        guard sessionState == .listening else { return nil }
        if streamStatus != .streaming {
            let stateText: String
            switch streamStatus {
            case .streaming:
                stateText = "streaming"
            case .reconnecting:
                stateText = "reconnecting"
            case .error:
                stateText = "error"
            }
            return "Backend is not fully streaming yet (\(stateText))."
        }

        let probes = activeSourceProbes
        if probes.isEmpty { return nil }

        let hasInput = probes.contains(where: { $0.inputIsFresh })
        let hasASR = probes.contains(where: { $0.asrIsFresh })

        if !hasInput {
            return "No recent input frames from selected source(s). Check source selection and permissions."
        }
        if !hasASR && effectiveElapsedSeconds >= 6 {
            return "Input audio is flowing, but ASR has not emitted text yet."
        }
        return nil
    }

    func reportBackendNotReady(detail: String) {
        streamStatus = .error
        let state = AppRuntimeErrorState.backendNotReady(detail: detail)
        runtimeErrorState = state
        statusMessage = state.message
    }

    private func setSessionError(_ error: AppRuntimeErrorState) {
        sessionState = .error
        runtimeErrorState = error
        statusMessage = error.message
    }

    private func bumpTranscriptRevision() {
        transcriptRevision &+= 1
    }

    func startSession() {
        guard sessionState != .listening && sessionState != .starting else { return }
        resetSession()
        sessionState = .starting
        statusMessage = "Requesting permission"
        runtimeErrorState = nil
        finalizationOutcome = .none
        
        // PR1: Generate new attempt ID for this start
        startAttemptId = UUID()
        let currentAttemptId = startAttemptId

        Task {
            refreshPermissionStatuses()

            // Screen Recording is required only if capturing system audio.
            if audioSource == .system || audioSource == .both {
                let preflightGranted = CGPreflightScreenCaptureAccess()
                let granted: Bool
                if preflightGranted {
                    granted = true
                } else {
                    granted = await audioCapture.requestPermission()
                }
                // On macOS, Screen Recording permission often requires an app restart to take effect.
                let effective = granted && CGPreflightScreenCaptureAccess()
                screenRecordingPermission = effective ? .authorized : .denied
                guard granted else {
                    setSessionError(.screenRecordingPermissionRequired)
                    return
                }
                guard effective else {
                    setSessionError(.screenRecordingRequiresRelaunch)
                    return
                }
            }

            // Microphone permission is required only if capturing microphone audio.
            if audioSource == .microphone || audioSource == .both {
                let micGranted = await micCapture.requestPermission()
                microphonePermission = micGranted ? .authorized : .denied
                guard micGranted else {
                    setSessionError(.microphonePermissionRequired)
                    return
                }
            }

            let id = UUID().uuidString
            sessionID = id
            sessionStart = Date()
            sessionEnd = nil

            // Start System Audio capture if needed
            if audioSource == .system || audioSource == .both {
                do {
                    try await audioCapture.startCapture()
                } catch {
                    setSessionError(.systemCaptureFailed(detail: error.localizedDescription))
                    return
                }
            }
            
            // Start Mic capture if needed
            if audioSource == .microphone || audioSource == .both {
                do {
                    try micCapture.startCapture()
                } catch {
                    setSessionError(.microphoneCaptureFailed(detail: error.localizedDescription))
                    // Stop system capture if it was started
                    if audioSource == .both {
                        await audioCapture.stopCapture()
                    }
                    return
                }
            }

            streamStatus = .reconnecting
            statusMessage = "Connecting to backend..."
            runtimeErrorState = nil
            streamer.connect(sessionID: id)
            startTimer()
            
            // PR1: Start timeout task for handshake
            startTimeoutTask?.cancel()
            startTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                
                guard let self else { return }
                
                // Check if this is still the current attempt
                guard self.startAttemptId == currentAttemptId else { return }
                
                // Check if we got the streaming ACK
                if self.sessionState == .starting {
                    // Timeout! Backend didn't acknowledge streaming
                    self.stopSession()
                    self.sessionState = .error
                    self.runtimeErrorState = .streaming(detail: "Backend did not start streaming within 5 seconds. It may be overloaded or still loading the ASR model.")
                }
            }
            
            // PR1: Don't set .listening yet! Wait for backend ACK in onStatus handler
            
            // Start session storage (v0.2)
            sessionStore.startSession(sessionId: id, audioSource: audioSource.rawValue)
            
            // Gap 2 fix: Start silence detection
            lastAudioTimestamp = Date()
            noAudioDetected = false
            silenceMessage = ""
            startSilenceCheck()
        }
    }

    func stopSession() {
        guard sessionState == .listening || sessionState == .starting else { return }
        sessionState = .finalizing
        stopTimer()
        sessionEnd = Date()

        Task {
            if audioSource == .system || audioSource == .both {
                await audioCapture.stopCapture()
            }
            if audioSource == .microphone || audioSource == .both {
                micCapture.stopCapture()
            }
            let didReceiveFinal = await streamer.stopAndAwaitFinalSummary(timeout: 10)
            if didReceiveFinal {
                self.finalizationOutcome = .complete
            } else {
                self.finalizationOutcome = .incompleteTimeout
            }
            
            // Gap 2 fix: Stop silence detection
            stopSilenceCheck()
            
            // End session storage (v0.2)
            if let id = sessionID {
                sessionStore.endSession(sessionId: id, finalData: exportPayload())
            }
            
            self.sessionState = .idle
            self.statusMessage = ""
            self.streamStatus = .reconnecting // Reset stream status
            self.runtimeErrorState = nil
            self.noAudioDetected = false

            NotificationCenter.default.post(name: .summaryShouldOpen, object: nil)
        }
    }

    func resetSession() {
        elapsedSeconds = 0
        transcriptSegments = []
        bumpTranscriptRevision()
        actions = []
        decisions = []
        risks = []
        entities = []
        finalSummaryMarkdown = ""
        finalSummaryJSON = [:]
        finalizationOutcome = .none
        sessionID = nil
        sessionStart = nil
        sessionEnd = nil
        lastPartialIndexBySource = [:]
        inputLastSeenBySource = [:]
        asrLastSeenBySource = [:]
        asrEventCount = 0
        runtimeErrorState = nil
    }
    
    /// Save current session snapshot for auto-save (v0.2)
    func saveSnapshot() {
        sessionStore.saveSnapshot(data: exportPayload())
    }
    
    // MARK: - Gap 2: Silence Detection
    
    private func startSilenceCheck() {
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }
    
    private func stopSilenceCheck() {
        silenceCheckTimer?.invalidate()
        silenceCheckTimer = nil
        noAudioDetected = false
        silenceMessage = ""
    }
    
    private func checkForSilence() {
        guard sessionState == .listening else { return }
        guard let lastAudio = lastAudioTimestamp else { return }
        
        let silenceDuration = Date().timeIntervalSince(lastAudio)
        if silenceDuration >= 10.0 && !noAudioDetected {
            noAudioDetected = true
            silenceMessage = "No audio detected for \(Int(silenceDuration))s. Check: Is the meeting muted? Is the correct audio source selected?"
        } else if noAudioDetected {
            // Update the duration
            silenceMessage = "No audio detected for \(Int(silenceDuration))s. Check: Is the meeting muted? Is the correct audio source selected?"
        }
    }

    func copyMarkdownToClipboard() {
        let markdown = finalSummaryMarkdown.isEmpty ? renderLiveMarkdown() : finalSummaryMarkdown
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    // MARK: - Local Context / RAG

    func refreshContextDocuments(force: Bool = false) {
        Task {
            await fetchContextDocuments(force: force)
        }
    }

    func indexContextDocument(from fileURL: URL) {
        Task {
            await indexContextDocumentAsync(from: fileURL)
        }
    }

    func queryContextDocuments(_ query: String? = nil) {
        Task {
            await queryContextDocumentsAsync(query ?? contextQuery)
        }
    }

    func deleteContextDocument(documentID: String) {
        Task {
            await deleteContextDocumentAsync(documentID: documentID)
        }
    }

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "echopanel-session.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let payload = self.exportPayload()
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url)
            } catch {
                NSLog("Export JSON failed: %@", error.localizedDescription)
            }
        }
    }

    func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "echopanel-notes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let markdown = self.finalSummaryMarkdown.isEmpty ? self.renderLiveMarkdown() : self.finalSummaryMarkdown
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Export Markdown failed: %@", error.localizedDescription)
            }
        }
    }

    func exportDebugBundle() {
        Task {
            // 1. Prepare files
            let tmpDir = FileManager.default.temporaryDirectory
            let bundleDir = tmpDir.appendingPathComponent("echopanel_debug_\(UUID().uuidString)")
            let logFile = tmpDir.appendingPathComponent("echopanel_server.log")
            
            do {
                try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
                
                // Copy Server Log
                if FileManager.default.fileExists(atPath: logFile.path) {
                    try FileManager.default.copyItem(at: logFile, to: bundleDir.appendingPathComponent("server.log"))
                } else {
                    try "Log file not found".write(to: bundleDir.appendingPathComponent("server.log_missing"), atomically: true, encoding: .utf8)
                }
                
                // Dump Session State
                let sessionData = try JSONSerialization.data(withJSONObject: exportPayload(), options: [.prettyPrinted, .sortedKeys])
                try sessionData.write(to: bundleDir.appendingPathComponent("session_dump.json"))
                
                // 2. Zip
                let zipURL = tmpDir.appendingPathComponent("echopanel_debug.zip")
                try? FileManager.default.removeItem(at: zipURL)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-r", zipURL.path, "."]
                process.currentDirectoryURL = bundleDir
                try process.run()
                process.waitUntilExit()
                
                // 3. Save Panel
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType.zip]
                    panel.nameFieldStringValue = "echopanel-debug.zip"
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        try? FileManager.default.copyItem(at: zipURL, to: url)
                        // Cleanup
                        try? FileManager.default.removeItem(at: bundleDir)
                        try? FileManager.default.removeItem(at: zipURL)
                    }
                }
            } catch {
                NSLog("Debug export failed: \(error)")
            }
        }
    }

    private func renderLiveMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Live Notes")
        lines.append("")
        lines.append("## Transcript")
        for segment in transcriptSegments where segment.isFinal {
            lines.append("- [\(formatTime(segment.t0))] \(segment.text)")
        }
        lines.append("")
        lines.append("## Actions")
        for item in actions { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Decisions")
        for item in decisions { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Risks")
        for item in risks { lines.append("- \(item.text) (\(formatConfidence(item.confidence)))") }
        lines.append("")
        lines.append("## Entities")
        for entity in entities { lines.append("- \(entity.name) (\(entity.type))") }
        return lines.joined(separator: "\n")
    }

    func renderLiveMarkdownForSummary() -> String {
        // Keep this stable and user-friendly (no "Live Notes" framing).
        var lines: [String] = []
        lines.append("# Notes")
        lines.append("")
        lines.append("## Transcript")
        for segment in transcriptSegments where segment.isFinal {
            let who: String
            if let speaker = segment.speaker, !speaker.isEmpty {
                who = speaker
            } else if let source = segment.source {
                who = (source == "mic" || source == "microphone") ? "You" : "System"
            } else {
                who = "Unknown"
            }
            lines.append("- [\(formatTime(segment.t0))] **\(who)**: \(segment.text)")
        }
        lines.append("")
        lines.append("## Actions")
        for item in actions { lines.append("- \(item.text)") }
        lines.append("")
        lines.append("## Decisions")
        for item in decisions { lines.append("- \(item.text)") }
        lines.append("")
        lines.append("## Risks")
        for item in risks { lines.append("- \(item.text)") }
        lines.append("")
        lines.append("## Entities")
        for entity in entities { lines.append("- \(entity.name) (\(entity.type))") }
        return lines.joined(separator: "\n")
    }

    private func exportPayload() -> [String: Any] {
        let transcript = transcriptSegments.map { segment in
            [
                "t0": segment.t0,
                "t1": segment.t1,
                "text": segment.text,
                "is_final": segment.isFinal,
                "confidence": segment.confidence,
                "source": segment.source as Any,
                "speaker": segment.speaker as Any,
            ]
        }
        let actionsPayload = actions.map { item in
            [
                "text": item.text,
                "owner": item.owner as Any,
                "due": item.due as Any,
                "confidence": item.confidence
            ]
        }
        let decisionsPayload = decisions.map { item in
            [
                "text": item.text,
                "confidence": item.confidence
            ]
        }
        let risksPayload = risks.map { item in
            [
                "text": item.text,
                "confidence": item.confidence
            ]
        }
        let entitiesPayload = entities.map { item in
            [
                "name": item.name,
                "type": item.type,
                "last_seen": item.lastSeen,
                "confidence": item.confidence
            ]
        }

        return [
            "session": [
                "session_id": sessionID as Any,
                "started_at": sessionStart?.iso8601 as Any,
                "ended_at": sessionEnd?.iso8601 as Any
            ],
            "transcript": transcript,
            "actions": actionsPayload,
            "decisions": decisionsPayload,
            "risks": risksPayload,
            "entities": entitiesPayload,
            "final_summary": [
                "markdown": finalSummaryMarkdown,
                "json": finalSummaryJSON
            ]
        ]
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private var effectiveElapsedSeconds: Int {
        guard (sessionState == .starting || sessionState == .listening), let sessionStart else {
            return elapsedSeconds
        }
        let wallClockElapsed = max(0, Int(Date().timeIntervalSince(sessionStart)))
        return max(elapsedSeconds, wallClockElapsed)
    }

    private func normalizedSource(_ source: String?) -> String {
        let raw = (source ?? "system").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "mic" || raw == "microphone" {
            return "mic"
        }
        if raw == "system" {
            return "system"
        }
        return raw
    }

    private func markInputFrame(source: String) {
        let key = normalizedSource(source)
        inputLastSeenBySource[key] = Date()
    }

    private func markASREvent(source: String?) {
        let key = normalizedSource(source)
        asrLastSeenBySource[key] = Date()
        asrEventCount += 1
    }

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.elapsedSeconds += 1
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        elapsedSeconds = 0
    }

    private func handlePartial(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double, source: String?) {
        // P2 Fix: Skip empty or whitespace-only partials to reduce visual noise
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Keep the UI timer aligned with the server's timeline (t1), especially if the timer
        // publisher is delayed or throttled in a menu-bar context.
        if t1.isFinite {
            elapsedSeconds = max(elapsedSeconds, Int(t1.rounded(.down)))
        }

        let sourceKey = (source ?? "system").lowercased()
        
        // P2 Fix: Use more stable updates - reduce animation jitter for partials
        // Only animate on significant text changes, not every partial update
        let shouldAnimate: Bool
        if let index = lastPartialIndexBySource[sourceKey],
           transcriptSegments.indices.contains(index),
           transcriptSegments[index].isFinal == false {
            let oldText = transcriptSegments[index].text
            let textDiff = abs(trimmedText.count - oldText.count)
            shouldAnimate = textDiff > 5  // Only animate on significant changes
        } else {
            shouldAnimate = true  // New segment
        }
        
        let updateAction = {
            if let index = self.lastPartialIndexBySource[sourceKey],
               self.transcriptSegments.indices.contains(index),
               self.transcriptSegments[index].isFinal == false {
                self.transcriptSegments[index] = TranscriptSegment(text: trimmedText, t0: t0, t1: t1, isFinal: false, confidence: confidence, source: source)
            } else {
                self.transcriptSegments.append(TranscriptSegment(text: trimmedText, t0: t0, t1: t1, isFinal: false, confidence: confidence, source: source))
                self.lastPartialIndexBySource[sourceKey] = self.transcriptSegments.count - 1
            }
            self.bumpTranscriptRevision()
        }
        
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.15), updateAction)
        } else {
            updateAction()
        }
    }

    private func handleFinal(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double, source: String?) {
        // P2 Fix: Skip empty or very short low-confidence finals (hallucination filter)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmedText.split(separator: " ").count
        if trimmedText.isEmpty || (confidence < 0.3 && wordCount < 2) {
            return
        }
        
        if t1.isFinite {
            elapsedSeconds = max(elapsedSeconds, Int(t1.rounded(.down)))
        }

        let sourceKey = (source ?? "system").lowercased()
        
        // P2 Fix: Check for duplicate final segments (same text + timestamp)
        let isDuplicate = transcriptSegments.contains { existing in
            existing.isFinal &&
            existing.text == trimmedText &&
            abs(existing.t0 - t0) < 0.5 &&  // Within 500ms
            existing.source == source
        }
        
        guard !isDuplicate else {
            lastPartialIndexBySource[sourceKey] = nil
            return
        }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            let segment = TranscriptSegment(text: trimmedText, t0: t0, t1: t1, isFinal: true, confidence: confidence, source: source)
            
            if let index = lastPartialIndexBySource[sourceKey],
               transcriptSegments.indices.contains(index),
               transcriptSegments[index].isFinal == false {
                // P2 Fix: Preserve speaker info from partial if available
                var updatedSegment = segment
                if updatedSegment.speaker == nil, let speaker = transcriptSegments[index].speaker {
                    updatedSegment.speaker = speaker
                }
                transcriptSegments[index] = updatedSegment
            } else {
                transcriptSegments.append(segment)
            }
            lastPartialIndexBySource[sourceKey] = nil
            bumpTranscriptRevision()
            
            // H6 Fix: Append to persistent transcript log
            let payload: [String: Any] = [
                "text": trimmedText,
                "t0": t0,
                "t1": t1,
                "confidence": confidence,
                "source": source as Any,
                "timestamp": Date().iso8601
            ]
            sessionStore.appendTranscriptSegment(payload)
        }
    }

    private func refreshScreenRecordingStatus() {
        let authorized = CGPreflightScreenCaptureAccess()
        screenRecordingPermission = authorized ? .authorized : .denied
        
        // Debug info
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        let processName = ProcessInfo.processInfo.processName
        let bundlePath = Bundle.main.bundleURL.path
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let isAppBundle = bundlePath.hasSuffix(".app")
        permissionDebugLine = "Bundle \(bundleID) v\(version) · Process \(processName) · \(isAppBundle ? "App" : "Binary") · \(bundlePath)"
    }

    func refreshPermissionStatuses() {
        refreshScreenRecordingStatus()
        refreshMicrophoneStatus()
    }

    private func refreshMicrophoneStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .authorized
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .unknown
        @unknown default:
            microphonePermission = .unknown
        }
    }

    private func updateDebugLine() {
        guard debugEnabled else {
            debugLine = ""
            return
        }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(debugBytes), countStyle: .file)
        debugLine = "Debug: \(debugSamples) samples · \(debugScreenFrames) screen frames · \(bytes) sent"
    }

    private func fetchContextDocuments(force: Bool) async {
        if !force, let lastContextRefreshAt, Date().timeIntervalSince(lastContextRefreshAt) < 2 {
            return
        }

        contextBusy = true
        defer { contextBusy = false }

        do {
            let request = makeAuthorizedRequest(url: BackendConfig.documentsListURL, method: "GET")
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureHTTPStatus(response, data: data)
            let payload = try JSONDecoder().decode(ContextDocumentsResponse.self, from: data)
            contextDocuments = payload.documents.map { $0.asContextDocument() }
            lastContextRefreshAt = Date()

            if contextDocuments.isEmpty {
                contextStatusMessage = "No context documents indexed yet."
            } else if contextStatusMessage.isEmpty {
                contextStatusMessage = "\(contextDocuments.count) document(s) available."
            }
        } catch {
            contextStatusMessage = "Context load failed: \(error.localizedDescription)"
        }
    }

    private func indexContextDocumentAsync(from fileURL: URL) async {
        do {
            let text = try loadTextFile(fileURL)
            if text.count > 250_000 {
                contextStatusMessage = "File too large (\(text.count) chars). Keep context files under 250k chars."
                return
            }

            contextBusy = true
            defer { contextBusy = false }
            contextStatusMessage = "Indexing \(fileURL.lastPathComponent)..."

            let payload: [String: Any] = [
                "title": fileURL.lastPathComponent,
                "source": fileURL.path,
                "text": text,
            ]
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let request = makeAuthorizedRequest(url: BackendConfig.documentsIndexURL, method: "POST", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureHTTPStatus(response, data: data)

            _ = try JSONDecoder().decode(ContextIndexResponse.self, from: data)
            contextStatusMessage = "Indexed \(fileURL.lastPathComponent)."
            await fetchContextDocuments(force: true)
        } catch {
            contextStatusMessage = "Indexing failed: \(error.localizedDescription)"
        }
    }

    private func queryContextDocumentsAsync(_ rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        contextQuery = query
        guard !query.isEmpty else {
            contextQueryResults = []
            contextStatusMessage = contextDocuments.isEmpty
                ? "No context documents indexed yet."
                : "Enter a query to search local context."
            return
        }

        contextBusy = true
        defer { contextBusy = false }

        do {
            let payload: [String: Any] = ["query": query, "top_k": 8]
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let request = makeAuthorizedRequest(url: BackendConfig.documentsQueryURL, method: "POST", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureHTTPStatus(response, data: data)
            let decoded = try JSONDecoder().decode(ContextQueryResponse.self, from: data)
            contextQueryResults = decoded.results.map { $0.asContextQueryResult() }
            if contextQueryResults.isEmpty {
                contextStatusMessage = "No matches for \"\(query)\"."
            } else {
                contextStatusMessage = "\(contextQueryResults.count) match(es) for \"\(query)\"."
            }
        } catch {
            contextStatusMessage = "Context query failed: \(error.localizedDescription)"
        }
    }

    private func deleteContextDocumentAsync(documentID: String) async {
        contextBusy = true
        defer { contextBusy = false }

        do {
            let request = makeAuthorizedRequest(
                url: BackendConfig.documentDeleteURL(documentID: documentID),
                method: "DELETE"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureHTTPStatus(response, data: data)
            contextDocuments.removeAll(where: { $0.id == documentID })
            contextQueryResults.removeAll(where: { $0.documentID == documentID })
            contextStatusMessage = "Document removed."
        } catch {
            contextStatusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func makeAuthorizedRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20.0
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = KeychainHelper.loadBackendToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "x-echopanel-token")
        }
        return request
    }

    private func ensureHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "EchoPanel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let detail = parseErrorDetail(from: data), !detail.isEmpty {
                throw NSError(domain: "EchoPanel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw NSError(
                domain: "EchoPanel",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Backend request failed (\(httpResponse.statusCode))"]
            )
        }
    }

    private func parseErrorDetail(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        if let detail = obj["detail"] as? String {
            return detail
        }
        if let detailObj = obj["detail"] as? [String: Any],
           let reason = detailObj["reason"] as? String {
            return reason
        }
        if let message = obj["message"] as? String {
            return message
        }
        return nil
    }

    private func loadTextFile(_ fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let encodings: [String.Encoding] = [.utf8, .unicode, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding),
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return text
            }
        }
        throw NSError(
            domain: "EchoPanel",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported file encoding for \(fileURL.lastPathComponent)"]
        )
    }

    func seedDemoData() {
        sessionState = .listening
        streamStatus = .streaming
        statusMessage = "Demo mode"
        runtimeErrorState = nil
        audioQuality = .good
        elapsedSeconds = 12 * 60 + 34
        audioSource = .both
        systemAudioLevel = 0.22
        microphoneAudioLevel = 0.18

        transcriptSegments = [
            TranscriptSegment(text: "We should ship by Friday.", t0: 31, t1: 33, isFinal: true, confidence: 0.87, source: "system", speaker: nil),
            TranscriptSegment(text: "I'll send the proposal tomorrow.", t0: 33, t1: 35, isFinal: true, confidence: 0.82, source: "mic", speaker: nil),
            TranscriptSegment(text: "Let’s keep the scope focused.", t0: 34, t1: 36, isFinal: true, confidence: 0.78, source: "system", speaker: nil),
        ]
        bumpTranscriptRevision()

        actions = [
            ActionItem(text: "Send revised proposal", owner: "Pranay", due: "Tue", confidence: 0.82),
        ]
        decisions = [
            DecisionItem(text: "Ship v0.2 on Friday", confidence: 0.74),
        ]
        risks = [
            RiskItem(text: "Audio quality during screen share", confidence: 0.61),
        ]
        entities = [
            EntityItem(name: "EchoPanel", type: "org", count: 2, lastSeen: 31, confidence: 0.88),
            EntityItem(name: "Friday", type: "date", count: 1, lastSeen: 31, confidence: 0.71),
            EntityItem(name: "ScreenCaptureKit", type: "topic", count: 1, lastSeen: 33, confidence: 0.74),
        ]
    }

    // BackendConfig reads host/port from UserDefaults.
}

private extension AppState {
    struct ContextDocumentsResponse: Decodable {
        let documents: [ContextDocumentPayload]
        let count: Int
    }

    struct ContextIndexResponse: Decodable {
        let document: ContextDocumentPayload
    }

    struct ContextQueryResponse: Decodable {
        let query: String
        let results: [ContextQueryResultPayload]
        let count: Int
    }

    struct ContextDocumentPayload: Decodable {
        let documentID: String
        let title: String
        let source: String
        let indexedAt: String
        let preview: String
        let chunkCount: Int

        enum CodingKeys: String, CodingKey {
            case documentID = "document_id"
            case title
            case source
            case indexedAt = "indexed_at"
            case preview
            case chunkCount = "chunk_count"
        }

        func asContextDocument() -> ContextDocument {
            ContextDocument(
                id: documentID,
                title: title,
                source: source,
                indexedAt: indexedAt,
                preview: preview,
                chunkCount: chunkCount
            )
        }
    }

    struct ContextQueryResultPayload: Decodable {
        let documentID: String
        let title: String
        let source: String
        let chunkIndex: Int
        let snippet: String
        let score: Double

        enum CodingKeys: String, CodingKey {
            case documentID = "document_id"
            case title
            case source
            case chunkIndex = "chunk_index"
            case snippet
            case score
        }

        func asContextQueryResult() -> ContextQueryResult {
            ContextQueryResult(
                documentID: documentID,
                title: title,
                source: source,
                chunkIndex: chunkIndex,
                snippet: snippet,
                score: score
            )
        }
    }
}

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
