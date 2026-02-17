import SwiftUI

// MARK: - Backend Selection View

public struct BackendSelectionView: View {
    @ObservedObject var asrManager: HybridASRManager
    @StateObject private var featureFlags = FeatureFlagManager.shared
    
    @State private var showUpgradePrompt = false
    @State private var upgradeFeature = ""
    
    public init(asrManager: HybridASRManager) {
        self.asrManager = asrManager
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Backend Mode Picker
            backendModeSection
            
            Divider()
            
            // Status Section
            statusSection
            
            Divider()
            
            // Capabilities Comparison
            capabilitiesSection
            
            // Dev Mode Controls
            #if DEBUG
            if featureFlags.isDevMode {
                Divider()
                devModeSection
            }
            #endif
        }
        .padding()
        .frame(minWidth: 400)
    }
    
    // MARK: - Sections
    
    private var backendModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Backend")
                .font(.headline)
            
            Text("Choose how your audio is transcribed. Native mode is private and works offline. Cloud mode enables advanced features.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker("Backend Mode", selection: $asrManager.selectedMode) {
                ForEach(availableModes) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: asrManager.selectedMode) { oldMode, newMode in
                if !asrManager.isModeAllowed(newMode) {
                    // Revert and show upgrade
                    asrManager.selectedMode = oldMode
                    upgradeFeature = newMode.displayName
                    showUpgradePrompt = true
                }
            }
            
            // Description of selected mode
            Text(asrManager.selectedMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend Status")
                .font(.headline)
            
            HStack(spacing: 16) {
                BackendStatusCard(
                    title: "Native MLX",
                    status: asrManager.backendStatus[asrManager.nativeBackend.name],
                    isActive: isNativeActive
                )
                
                BackendStatusCard(
                    title: "Python Server",
                    status: asrManager.backendStatus[asrManager.pythonBackend.name],
                    isActive: isPythonActive
                )
            }
        }
    }
    
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capabilities")
                .font(.headline)
            
            CapabilitiesTable(
                nativeCapabilities: asrManager.nativeBackend.capabilities,
                pythonCapabilities: asrManager.pythonBackend.capabilities
            )
        }
    }
    
    #if DEBUG
    private var devModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developer Mode")
                .font(.headline)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable Dual Mode", isOn: $featureFlags.enableDualMode)
                
                Toggle("Verbose Logging", isOn: $featureFlags.enableVerboseLogging)
                
                Toggle("Comparison Metrics", isOn: $featureFlags.enableComparisonMetrics)
                
                HStack {
                    Text("Forced Mode:")
                    Picker("", selection: Binding(
                        get: { featureFlags.forcedBackendMode },
                        set: { featureFlags.forcedBackendMode = $0 }
                    )) {
                        Text("None").tag(nil as BackendMode?)
                        ForEach(BackendMode.allCases) { mode in
                            Text(mode.displayName).tag(mode as BackendMode?)
                        }
                    }
                    .frame(width: 150)
                }
                
                HStack {
                    Text("Rollout: \(Int(featureFlags.nativeBackendRolloutPercentage))%")
                    Slider(
                        value: $featureFlags.nativeBackendRolloutPercentage,
                        in: 0...100,
                        step: 10
                    )
                }
            }
            .font(.caption)
            
            HStack {
                Button("Reset All") {
                    featureFlags.resetToDefaults()
                }
                .buttonStyle(.bordered)
                
                Button("Enable All") {
                    featureFlags.enableAllForDev()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    #endif
    
    // MARK: - Helpers
    
    private var availableModes: [BackendMode] {
        BackendMode.allCases.filter { mode in
            asrManager.isModeAvailable(mode)
        }
    }
    
    private var isNativeActive: Bool {
        asrManager.selectedMode == .nativeMLX ||
        (asrManager.selectedMode == .autoSelect && asrManager.activeBackend?.name == asrManager.nativeBackend.name)
    }
    
    private var isPythonActive: Bool {
        asrManager.selectedMode == .pythonServer ||
        (asrManager.selectedMode == .autoSelect && asrManager.activeBackend?.name == asrManager.pythonBackend.name)
    }
}

// MARK: - Backend Status Card

struct BackendStatusCard: View {
    let title: String
    let status: BackendStatus?
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                
                Spacer()
                
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .cornerRadius(4)
                }
            }
            
            if let message = status?.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if let metrics = status?.performanceMetrics {
                HStack(spacing: 12) {
                    Label("RTF: \(String(format: "%.2f", metrics.realtimeFactor))x", systemImage: "gauge")
                    Label("\(metrics.totalRequests)", systemImage: "number")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var iconName: String {
        guard let state = status?.state else { return "questionmark.circle" }
        return state.icon
    }
    
    private var statusColor: Color {
        guard let state = status?.state else { return .gray }
        switch state {
        case .ready: return .green
        case .busy: return .orange
        case .error: return .red
        case .initializing: return .blue
        default: return .gray
        }
    }
}

// MARK: - Capabilities Table

struct CapabilitiesTable: View {
    let nativeCapabilities: BackendCapabilities
    let pythonCapabilities: BackendCapabilities
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Feature")
                    .frame(width: 120, alignment: .leading)
                Spacer()
                Text("Native")
                    .frame(width: 60)
                Text("Cloud")
                    .frame(width: 60)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            
            // Rows
            CapabilityRow(
                name: "Streaming",
                native: nativeCapabilities.supportsStreaming,
                python: pythonCapabilities.supportsStreaming
            )
            
            CapabilityRow(
                name: "Batch",
                native: nativeCapabilities.supportsBatch,
                python: pythonCapabilities.supportsBatch
            )
            
            CapabilityRow(
                name: "Diarization",
                native: nativeCapabilities.supportsDiarization,
                python: pythonCapabilities.supportsDiarization
            )
            
            CapabilityRow(
                name: "Offline",
                native: nativeCapabilities.supportsOffline,
                python: pythonCapabilities.supportsOffline
            )
            
            CapabilityRow(
                name: "Network Required",
                native: nativeCapabilities.requiresNetwork,
                python: pythonCapabilities.requiresNetwork,
                invert: true  // For network required, checkmark is bad
            )
        }
        .font(.caption)
    }
}

struct CapabilityRow: View {
    let name: String
    let native: Bool
    let python: Bool
    var invert: Bool = false
    
    var body: some View {
        HStack {
            Text(name)
                .frame(width: 120, alignment: .leading)
            Spacer()
            
            Image(systemName: icon(for: native))
                .foregroundStyle(color(for: native))
                .frame(width: 60)
            
            Image(systemName: icon(for: python))
                .foregroundStyle(color(for: python))
                .frame(width: 60)
        }
        .padding(.vertical, 6)
    }
    
    private func icon(for value: Bool) -> String {
        value ? "checkmark" : "xmark"
    }
    
    private func color(for value: Bool) -> Color {
        let effective = invert ? !value : value
        return effective ? .green : .red.opacity(0.5)
    }
}

// MARK: - Preview

#Preview {
    BackendSelectionView(asrManager: ASRContainer.shared.hybridASRManager)
        .frame(width: 500)
}
