import AppKit
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

    @Published var sessionState: SessionState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var audioQuality: AudioQuality = .unknown
    @Published var streamStatus: StreamStatus = .reconnecting
    @Published var statusMessage: String = ""
    
    // Permission Tracking
    @Published var screenRecordingPermission: PermissionState = .unknown
    @Published var microphonePermission: PermissionState = .unknown
    
    // Audio Source Selection (v0.2)
    @Published var audioSource: AudioSource = .both
    @Published var systemAudioLevel: Float = 0
    @Published var microphoneAudioLevel: Float = 0
    
    @Published var permissionDebugLine: String = ""
    @Published var debugLine: String = ""

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var actions: [ActionItem] = []
    @Published var decisions: [DecisionItem] = []
    @Published var risks: [RiskItem] = []
    @Published var entities: [EntityItem] = []

    @Published var finalSummaryMarkdown: String = ""
    @Published var finalSummaryJSON: [String: Any] = [:]

    private var sessionID: String?
    private var sessionStart: Date?
    private var sessionEnd: Date?
    private var timerCancellable: AnyCancellable?
    private var permissionCancellable: AnyCancellable?

    private let audioCapture = AudioCaptureManager()
    private let micCapture = MicrophoneCaptureManager()
    private let streamer = WebSocketStreamer(url: URL(string: "ws://127.0.0.1:8000/ws/live-listener")!)
    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var debugSamples: Int = 0
    private var debugBytes: Int = 0
    private var debugScreenFrames: Int = 0

    init() {
        refreshScreenRecordingStatus()
        permissionCancellable = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshScreenRecordingStatus()
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
        audioCapture.onPCMFrame = { [weak self] frame, source in
            NSLog("🔊 onPCMFrame callback triggered: %d bytes, source: %@", frame.count, source)
            if let self {
                self.debugBytes += frame.count
                if self.debugEnabled {
                    Task { @MainActor in self.updateDebugLine() }
                }
            }
            self?.streamer.sendPCMFrame(frame, source: source)
        }
        
        // Mic capture callbacks (v0.2)
        micCapture.onPCMFrame = { [weak self] frame, source in
            if let self {
                self.debugBytes += frame.count
            }
            self?.streamer.sendPCMFrame(frame, source: source)
        }
        micCapture.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in self?.microphoneAudioLevel = level }
        }

        streamer.onStatus = { [weak self] status, message in
            Task { @MainActor in
                self?.streamStatus = status
                self?.statusMessage = message
            }
        }
        streamer.onASRPartial = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in self?.handlePartial(text: text, t0: t0, t1: t1, confidence: confidence) }
        }
        streamer.onASRFinal = { [weak self] text, t0, t1, confidence in
            Task { @MainActor in self?.handleFinal(text: text, t0: t0, t1: t1, confidence: confidence) }
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
            }
        }
    }

    var statusLine: String {
        let base: String
        switch streamStatus {
        case .streaming: base = "Streaming"
        case .reconnecting: base = "Reconnecting"
        case .error: base = "Backend unavailable"
        }
        if statusMessage.isEmpty { return base }
        return "\(base) - \(statusMessage)"
    }

    var timerText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func startSession() {
        guard sessionState != .listening else { return }
        resetSession()
        sessionState = .starting
        statusMessage = "Requesting permission"

        Task {
            refreshScreenRecordingStatus()
            
            // Check Screen Recording first
            if screenRecordingPermission != .authorized {
                // We can't request it programmatically in a nice way, but we can check
                let granted = CGPreflightScreenCaptureAccess()
                screenRecordingPermission = granted ? .authorized : .denied
                
                if !granted {
                    sessionState = .error
                    statusMessage = "Screen Recording permission required"
                    return
                }
            }

            // Request Microphone Permission (using AudioCaptureManager)
            let micGranted = await audioCapture.requestPermission()
            microphonePermission = micGranted ? .authorized : .denied
            
            guard micGranted else {
                sessionState = .error
                statusMessage = "Microphone permission required"
                return
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
                    sessionState = .error
                    statusMessage = "Capture failed: \(error.localizedDescription)"
                    return
                }
            }
            
            // Start Mic capture if needed
            if audioSource == .microphone || audioSource == .both {
                do {
                    try micCapture.startCapture()
                } catch {
                    sessionState = .error
                    statusMessage = "Mic capture failed: \(error.localizedDescription)"
                    // Stop system capture if it was started
                    if audioSource == .both {
                        await audioCapture.stopCapture()
                    }
                    return
                }
            }

            streamStatus = .reconnecting
            statusMessage = "Connecting"
            streamer.connect(sessionID: id)
            startTimer()
            sessionState = .listening
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
            streamer.disconnect()
            sessionState = .idle
            statusMessage = ""
        }
    }

    func resetSession() {
        elapsedSeconds = 0
        transcriptSegments = []
        actions = []
        decisions = []
        risks = []
        entities = []
        finalSummaryMarkdown = ""
        finalSummaryJSON = [:]
        sessionID = nil
        sessionStart = nil
        sessionEnd = nil
    }

    func copyMarkdownToClipboard() {
        let markdown = finalSummaryMarkdown.isEmpty ? renderLiveMarkdown() : finalSummaryMarkdown
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
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

    private func exportPayload() -> [String: Any] {
        let transcript = transcriptSegments.map { segment in
            [
                "t0": segment.t0,
                "t1": segment.t1,
                "text": segment.text,
                "is_final": segment.isFinal,
                "confidence": segment.confidence
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

    private func handlePartial(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let lastIndex = transcriptSegments.indices.last, transcriptSegments[lastIndex].isFinal == false {
                transcriptSegments[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence)
            } else {
                transcriptSegments.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: false, confidence: confidence))
            }
        }
    }

    private func handleFinal(text: String, t0: TimeInterval, t1: TimeInterval, confidence: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let lastIndex = transcriptSegments.indices.last, transcriptSegments[lastIndex].isFinal == false {
                transcriptSegments[lastIndex] = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence)
            } else {
                transcriptSegments.append(TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: true, confidence: confidence))
            }
        }
    }

    private func refreshScreenRecordingStatus() {
        let authorized = CGPreflightScreenCaptureAccess()
        screenRecordingPermission = authorized ? .authorized : .denied
        
        // Debug info
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        let processName = ProcessInfo.processInfo.processName
        let bundlePath = Bundle.main.bundleURL.path
        let isAppBundle = bundlePath.hasSuffix(".app")
        permissionDebugLine = "Bundle \(bundleID) · Process \(processName) · \(isAppBundle ? "App" : "Binary")"
    }

    private func updateDebugLine() {
        guard debugEnabled else {
            debugLine = ""
            return
        }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(debugBytes), countStyle: .file)
        debugLine = "Debug: \(debugSamples) samples · \(debugScreenFrames) screen frames · \(bytes) sent"
    }
}

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
