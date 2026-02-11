import Foundation
import Combine
import SwiftUI

/// Audio source identifier for redundancy tracking
enum RedundantAudioSource: String, CaseIterable {
    case primary = "primary"
    case backup = "backup"
    
    var displayName: String {
        switch self {
        case .primary: return "Primary (System Audio)"
        case .backup: return "Backup (Microphone)"
        }
    }
}

/// Quality metrics for a single audio source
struct SourceQualityMetrics {
    let source: RedundantAudioSource
    let rms: Float
    let isSilent: Bool
    let isClipping: Bool
    let lastFrameTime: Date
    let isHealthy: Bool
}

/// Redundant audio capture manager for broadcast reliability.
/// Runs primary (system audio) and backup (microphone) simultaneously,
/// monitors quality in real-time, and auto-switches on degradation.
@MainActor
final class RedundantAudioCaptureManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Currently active audio source
    @Published var activeSource: RedundantAudioSource = .primary
    
    /// True if redundancy is enabled and both sources are running
    @Published var isRedundancyActive = false
    
    /// Quality status for each source
    @Published var primaryQuality: AudioQuality = .unknown
    @Published var backupQuality: AudioQuality = .unknown
    
    /// Audio levels for visualization
    @Published var primaryLevel: Float = 0
    @Published var backupLevel: Float = 0
    
    /// Failover history for diagnostics
    @Published var failoverEvents: [FailoverEvent] = []
    
    /// Current health status
    var currentHealth: RedundancyHealth {
        if primaryQuality == .good || (activeSource == .backup && backupQuality == .good) {
            return .healthy
        } else if primaryQuality == .ok || backupQuality == .ok {
            return .degraded
        } else {
            return .critical
        }
    }
    
    // MARK: - Callbacks
    
    /// Called when a PCM frame is ready (data, source tag)
    var onPCMFrame: ((Data, String) -> Void)?
    
    /// Called when active source changes
    var onSourceChanged: ((RedundantAudioSource) -> Void)?
    
    /// Called when health status changes
    var onHealthChanged: ((RedundancyHealth) -> Void)?
    
    // MARK: - Private Properties
    
    private let primaryCapture = AudioCaptureManager()
    private let backupCapture = MicrophoneCaptureManager()
    
    private var qualityMonitorTimer: Timer?
    private var lastPrimaryFrame = Date()
    private var lastBackupFrame = Date()
    private var primarySilenceDuration: TimeInterval = 0
    private var backupSilenceDuration: TimeInterval = 0
    
    private var lastHealth: RedundancyHealth = .unknown
    
    // Failover configuration
    private let failoverSilenceThreshold: TimeInterval = 2.0
    private let failoverClipThreshold: Float = 0.1
    private let qualityCheckInterval: TimeInterval = 0.1
    private var autoFailoverEnabled = true
    
    // Track which source is providing frames
    private var primaryFrameCount = 0
    private var backupFrameCount = 0
    
    struct FailoverEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let from: RedundantAudioSource
        let to: RedundantAudioSource
        let reason: FailoverReason
        
        enum FailoverReason: String {
            case silence = "Silence detected"
            case clipping = "Excessive clipping"
            case engineStopped = "Capture engine stopped"
            case manual = "Manual override"
        }
    }
    
    enum RedundancyHealth: String {
        case healthy = "Healthy"
        case degraded = "Degraded"
        case critical = "Critical"
        case unknown = "Unknown"
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .degraded: return .orange
            case .critical: return .red
            case .unknown: return .gray
            }
        }
    }
    
    // MARK: - Lifecycle
    
    init() {
        setupCallbacks()
    }
    
    /// Start redundant capture with both primary and backup sources
    func startRedundantCapture(autoFailover: Bool = true) async throws {
        self.autoFailoverEnabled = autoFailover
        
        // Start primary (system audio)
        do {
            try await primaryCapture.startCapture()
            NSLog("RedundantAudioCaptureManager: Primary started")
        } catch {
            NSLog("RedundantAudioCaptureManager: Primary failed to start: \(error)")
            // Continue with backup only if primary fails
        }
        
        // Start backup (microphone)
        do {
            try backupCapture.startCapture()
            NSLog("RedundantAudioCaptureManager: Backup started")
        } catch {
            NSLog("RedundantAudioCaptureManager: Backup failed to start: \(error)")
            // If backup fails but primary succeeded, we can still operate
        }
        
        isRedundancyActive = true
        activeSource = .primary
        startQualityMonitoring()
        
        NSLog("RedundantAudioCaptureManager: Redundancy active, auto-failover \(autoFailover ? "enabled" : "disabled")")
    }
    
    /// Start single-source capture (for non-broadcast mode)
    func startSingleCapture(useBackup: Bool = false) async throws {
        autoFailoverEnabled = false
        
        if useBackup {
            try backupCapture.startCapture()
            activeSource = .backup
        } else {
            try await primaryCapture.startCapture()
            activeSource = .primary
        }
        
        isRedundancyActive = false
        startQualityMonitoring()
    }
    
    /// Stop all capture
    func stopCapture() async {
        stopQualityMonitoring()
        
        await primaryCapture.stopCapture()
        backupCapture.stopCapture()
        
        isRedundancyActive = false
        primaryQuality = .unknown
        backupQuality = .unknown
        
        NSLog("RedundantAudioCaptureManager: All capture stopped")
    }
    
    /// Manually switch to a specific source
    func switchToSource(_ source: RedundantAudioSource) {
        guard activeSource != source else { return }
        
        let previousSource = activeSource
        activeSource = source
        
        let event = FailoverEvent(
            timestamp: Date(),
            from: previousSource,
            to: source,
            reason: .manual
        )
        failoverEvents.append(event)
        
        onSourceChanged?(source)
        NSLog("RedundantAudioCaptureManager: Manual switch to \(source.displayName)")
    }
    
    /// Force immediate failover to backup (operator emergency control)
    func emergencyFailover() {
        guard activeSource != .backup else { return }
        performFailover(from: .primary, to: .backup, reason: .manual)
    }
    
    /// Get current statistics
    func getStatistics() -> RedundancyStats {
        return RedundancyStats(
            primaryFrameCount: primaryFrameCount,
            backupFrameCount: backupFrameCount,
            activeSource: activeSource,
            primaryLastFrame: lastPrimaryFrame,
            backupLastFrame: lastBackupFrame,
            failoverCount: failoverEvents.count
        )
    }
    
    // MARK: - Private Methods
    
    private func setupCallbacks() {
        // Primary (system audio) callbacks
        primaryCapture.onPCMFrame = { [weak self] frame, _ in
            guard let self = self else { return }
            self.lastPrimaryFrame = Date()
            self.primaryFrameCount += 1
            self.primarySilenceDuration = 0
            
            // Only emit if primary is active or we're in single-source mode
            if self.activeSource == .primary || !self.isRedundancyActive {
                self.onPCMFrame?(frame, "system")
            }
        }
        
        primaryCapture.onAudioQualityUpdate = { [weak self] quality in
            Task { @MainActor in
                self?.primaryQuality = quality
            }
        }
        
        primaryCapture.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.primaryLevel = level
            }
        }
        
        // Backup (microphone) callbacks
        backupCapture.onPCMFrame = { [weak self] frame, _ in
            guard let self = self else { return }
            self.lastBackupFrame = Date()
            self.backupFrameCount += 1
            self.backupSilenceDuration = 0
            
            // Only emit if backup is active
            if self.activeSource == .backup {
                self.onPCMFrame?(frame, "mic")
            }
        }
        
        backupCapture.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.backupQuality = self?.levelToQuality(level) ?? .unknown
                self?.backupLevel = level
            }
        }
        
        backupCapture.onError = { error in
            NSLog("RedundantAudioCaptureManager: Backup error: \(error)")
        }
    }
    
    private func startQualityMonitoring() {
        qualityMonitorTimer = Timer.scheduledTimer(withTimeInterval: qualityCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkQualityAndFailover()
            }
        }
    }
    
    private func stopQualityMonitoring() {
        qualityMonitorTimer?.invalidate()
        qualityMonitorTimer = nil
    }
    
    private func checkQualityAndFailover() {
        guard isRedundancyActive && autoFailoverEnabled else { return }
        
        let now = Date()
        
        // Update silence durations
        let timeSincePrimary = now.timeIntervalSince(lastPrimaryFrame)
        let timeSinceBackup = now.timeIntervalSince(lastBackupFrame)
        
        // Check if we need to failover from primary to backup
        if activeSource == .primary {
            let shouldFailover = timeSincePrimary > failoverSilenceThreshold ||
                                primaryQuality == .poor
            
            if shouldFailover && timeSinceBackup < 1.0 {
                let reason: FailoverEvent.FailoverReason = timeSincePrimary > failoverSilenceThreshold
                    ? .silence
                    : .clipping
                performFailover(from: .primary, to: .backup, reason: reason)
            }
        }
        
        // Update health status
        if currentHealth != lastHealth {
            lastHealth = currentHealth
            onHealthChanged?(currentHealth)
        }
    }
    
    private func performFailover(from: RedundantAudioSource, to: RedundantAudioSource, reason: FailoverEvent.FailoverReason) {
        activeSource = to
        
        let event = FailoverEvent(
            timestamp: Date(),
            from: from,
            to: to,
            reason: reason
        )
        failoverEvents.append(event)
        
        onSourceChanged?(to)
        
        // Log structured event
        StructuredLogger.shared.warning("Audio failover triggered", metadata: [
            "from": from.rawValue,
            "to": to.rawValue,
            "reason": reason.rawValue
        ])
        
        NSLog("RedundantAudioCaptureManager: FAILOVER from \(from.displayName) to \(to.displayName) - \(reason.rawValue)")
    }
    
    private func levelToQuality(_ level: Float) -> AudioQuality {
        if level < 0.01 {
            return .poor
        } else if level < 0.05 {
            return .ok
        } else {
            return .good
        }
    }
}

// MARK: - Statistics

struct RedundancyStats {
    let primaryFrameCount: Int
    let backupFrameCount: Int
    let activeSource: RedundantAudioSource
    let primaryLastFrame: Date
    let backupLastFrame: Date
    let failoverCount: Int
    
    var summary: String {
        return """
        Redundancy Statistics:
        - Active Source: \(activeSource.displayName)
        - Primary Frames: \(primaryFrameCount)
        - Backup Frames: \(backupFrameCount)
        - Failover Events: \(failoverCount)
        - Primary Last Frame: \(primaryLastFrame.timeIntervalSinceNow > -1 ? "Live" : "\(Int(-primaryLastFrame.timeIntervalSinceNow))s ago")
        - Backup Last Frame: \(backupLastFrame.timeIntervalSinceNow > -1 ? "Live" : "\(Int(-backupLastFrame.timeIntervalSinceNow))s ago")
        """
    }
}

// MARK: - SwiftUI Views

/// Redundancy status indicator for broadcast operator UI
struct RedundancyStatusView: View {
    @ObservedObject var manager: RedundantAudioCaptureManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(manager.currentHealth.color)
                    .frame(width: 12, height: 12)
                
                Text("Audio: \(manager.currentHealth.rawValue)")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Text(manager.activeSource.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(manager.activeSource == .primary ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if manager.isRedundancyActive {
                HStack(spacing: 12) {
                    SourceIndicator(
                        label: "PRI",
                        level: manager.primaryLevel,
                        quality: manager.primaryQuality,
                        isActive: manager.activeSource == .primary
                    )
                    
                    SourceIndicator(
                        label: "BAK",
                        level: manager.backupLevel,
                        quality: manager.backupQuality,
                        isActive: manager.activeSource == .backup
                    )
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

private struct SourceIndicator: View {
    let label: String
    let level: Float
    let quality: AudioQuality
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Rectangle()
                        .fill(qualityColor)
                        .frame(width: geo.size.width * CGFloat(min(level * 3, 1.0)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .opacity(isActive ? 1.0 : 0.5)
    }
    
    private var qualityColor: Color {
        switch quality {
        case .good: return .green
        case .ok: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RedundancyStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = RedundantAudioCaptureManager()
        manager.isRedundancyActive = true
        manager.activeSource = .primary
        manager.primaryLevel = 0.7
        manager.backupLevel = 0.3
        manager.primaryQuality = .good
        manager.backupQuality = .ok
        
        return RedundancyStatusView(manager: manager)
            .frame(width: 280)
            .padding()
    }
}
#endif
