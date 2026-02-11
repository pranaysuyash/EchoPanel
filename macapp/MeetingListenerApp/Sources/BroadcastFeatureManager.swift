import Foundation
import Combine
import SwiftUI

// MARK: - NTP Client

/// Simple NTP client for timestamp synchronization
@MainActor
final class NTPClient {
    private var offset: TimeInterval = 0
    private let ntpHost = "pool.ntp.org"
    private let ntpPort: UInt16 = 123
    
    /// Synchronize with NTP server and return offset
    func sync() async throws -> TimeInterval {
        // Simplified implementation - in production, use proper NTP protocol
        // This is a placeholder that returns 0 offset (local time)
        offset = 0
        return offset
    }
    
    /// Get NTP-corrected timestamp
    func now() -> Date {
        return Date().addingTimeInterval(offset)
    }
}

/// Manager for broadcast-specific features.
/// Separated from AppState to avoid stored property limitations in extensions.
@MainActor
final class BroadcastFeatureManager: ObservableObject {
    static let shared = BroadcastFeatureManager()
    
    // MARK: - Published State
    
    @Published var useRedundantAudio: Bool {
        didSet { UserDefaults.standard.set(useRedundantAudio, forKey: "broadcast_useRedundantAudio") }
    }
    
    @Published var useHotKeys: Bool {
        didSet {
            UserDefaults.standard.set(useHotKeys, forKey: "broadcast_useHotKeys")
            if useHotKeys {
                hotKeyManager.startMonitoring()
            } else {
                hotKeyManager.stopMonitoring()
            }
        }
    }
    
    @Published var showConfidence: Bool {
        didSet { UserDefaults.standard.set(showConfidence, forKey: "broadcast_showConfidence") }
    }
    
    @Published var currentConfidence: Float = 0
    @Published var rollingConfidence: Float = 0
    @Published var useNTPTimestamps: Bool {
        didSet { UserDefaults.standard.set(useNTPTimestamps, forKey: "broadcast_useNTP") }
    }
    @Published var ntpOffset: TimeInterval = 0
    
    // MARK: - Managers
    
    let redundantAudioManager = RedundantAudioCaptureManager()
    let hotKeyManager = HotKeyManager()
    let ntpClient = NTPClient()
    
    // MARK: - Callbacks
    
    var onHotKeyAction: ((HotKeyManager.HotKeyAction) -> Void)?
    var onRedundantAudioFrame: ((Data, String) -> Void)?
    
    // MARK: - Initialization
    
    private init() {
        useRedundantAudio = UserDefaults.standard.bool(forKey: "broadcast_useRedundantAudio")
        useHotKeys = UserDefaults.standard.bool(forKey: "broadcast_useHotKeys")
        showConfidence = UserDefaults.standard.bool(forKey: "broadcast_showConfidence")
        useNTPTimestamps = UserDefaults.standard.bool(forKey: "broadcast_useNTP")
        
        setupCallbacks()
        
        if useHotKeys {
            hotKeyManager.startMonitoring()
        }
    }
    
    // MARK: - Setup
    
    private func setupCallbacks() {
        // Hot-key actions
        hotKeyManager.onAction = { [weak self] action in
            Task { @MainActor in
                self?.handleHotKeyAction(action)
            }
        }
        
        // Redundant audio
        redundantAudioManager.onPCMFrame = { [weak self] frame, source in
            self?.onRedundantAudioFrame?(frame, source)
        }
        
        redundantAudioManager.onSourceChanged = { [weak self] source in
            Task { @MainActor in
                self?.objectWillChange.send()
                StructuredLogger.shared.warning("Audio source changed", metadata: [
                    "new_source": source.rawValue
                ])
            }
        }
        
        redundantAudioManager.onHealthChanged = { [weak self] health in
            Task { @MainActor in
                self?.objectWillChange.send()
                if health == .critical {
                    StructuredLogger.shared.error("Audio redundancy critical", metadata: [:])
                }
            }
        }
    }
    
    // MARK: - Hot Key Handling
    
    private func handleHotKeyAction(_ action: HotKeyManager.HotKeyAction) {
        guard useHotKeys else { return }
        
        onHotKeyAction?(action)
        
        // Haptic feedback for confirmation
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    
    /// Force emergency failover to backup audio
    func emergencyAudioFailover() {
        guard useRedundantAudio else { return }
        redundantAudioManager.emergencyFailover()
        StructuredLogger.shared.error("Emergency audio failover triggered by operator", metadata: [:])
    }
    
    // MARK: - NTP Synchronization
    
    func syncNTP() async {
        do {
            let offset = try await ntpClient.sync()
            ntpOffset = offset
            StructuredLogger.shared.info("NTP synchronized", metadata: [
                "offset_ms": offset * 1000
            ])
        } catch {
            StructuredLogger.shared.error("NTP sync failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }
    
    /// Get current timestamp (NTP-synced if enabled)
    func getCurrentTimestamp() -> TimeInterval {
        if useNTPTimestamps {
            return Date().timeIntervalSince1970 + ntpOffset
        } else {
            return Date().timeIntervalSince1970
        }
    }
    
    // MARK: - Confidence Tracking
    
    func updateConfidence(fromSegment segment: TranscriptSegment) {
        guard showConfidence else { return }
        
        currentConfidence = Float(segment.confidence * 100)
        rollingConfidence = rollingConfidence * 0.9 + currentConfidence * 0.1
        
        if rollingConfidence < 70 {
            StructuredLogger.shared.warning("Low ASR confidence", metadata: [
                "confidence": rollingConfidence
            ])
        }
    }
}

// MARK: - Broadcast Settings View

struct BroadcastSettingsView: View {
    @StateObject private var broadcast = BroadcastFeatureManager.shared
    @State private var showingHotKeyHelp = false
    
    var body: some View {
        Form {
            Section(header: Text("Audio Redundancy")) {
                Toggle("Enable Dual-Path Audio", isOn: $broadcast.useRedundantAudio)
                
                if broadcast.useRedundantAudio {
                    RedundancyStatusView(manager: broadcast.redundantAudioManager)
                        .padding(.vertical, 8)
                    
                    Button("Emergency Failover to Backup") {
                        broadcast.emergencyAudioFailover()
                    }
                    .foregroundColor(.red)
                    // Note: Disabled state should check session state from AppState
                }
                
                Text("Uses both system audio and microphone simultaneously, automatically switching if one fails.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Operator Controls")) {
                Toggle("Enable Global Hot-Keys", isOn: $broadcast.useHotKeys)
                
                if broadcast.useHotKeys {
                    Button("View Hot-Key Reference") {
                        showingHotKeyHelp = true
                    }
                    
                    if !broadcast.hotKeyManager.checkAccessibilityPermission() {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Accessibility permission required for global hot-keys")
                                .font(.caption)
                            Button("Grant") {
                                broadcast.hotKeyManager.requestAccessibilityPermission()
                            }
                            .font(.caption)
                        }
                    }
                }
                
                Text("Hot-keys work even when EchoPanel is not the active app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("ASR Quality Monitoring")) {
                Toggle("Show Confidence Scores", isOn: $broadcast.showConfidence)
                
                // Note: Session state check should come from AppState
                if broadcast.showConfidence {
                    VStack(alignment: .leading, spacing: 8) {
                        ConfidenceMeterView(
                            current: broadcast.currentConfidence,
                            rolling: broadcast.rollingConfidence
                        )
                        
                        HStack {
                            Text("Current: \(Int(broadcast.currentConfidence))%")
                            Spacer()
                            Text("5s Avg: \(Int(broadcast.rollingConfidence))%")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Timestamp Synchronization")) {
                Toggle("Use NTP Synchronization", isOn: $broadcast.useNTPTimestamps)
                
                if broadcast.useNTPTimestamps {
                    HStack {
                        Text("NTP Offset:")
                        Spacer()
                        Text("\(Int(broadcast.ntpOffset * 1000)) ms")
                            .foregroundColor(broadcast.ntpOffset == 0 ? .secondary : .primary)
                    }
                    
                    Button("Sync Now") {
                        Task { await broadcast.syncNTP() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showingHotKeyHelp) {
            HotKeyHelpOverlay(isVisible: $showingHotKeyHelp)
        }
    }
}

// MARK: - Confidence Meter View

struct ConfidenceMeterView: View {
    let current: Float
    let rolling: Float
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    Rectangle()
                        .fill(confidenceColor(rolling))
                        .frame(width: geo.size.width * CGFloat(rolling / 100), height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("Confidence")
                    .font(.caption)
                Spacer()
                Circle()
                    .fill(confidenceColor(current))
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    private func confidenceColor(_ value: Float) -> Color {
        if value >= 85 { return .green }
        else if value >= 70 { return .yellow }
        else { return .red }
    }
}

// MARK: - Preview

#if DEBUG
struct BroadcastSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        BroadcastSettingsView()
    }
}
#endif
