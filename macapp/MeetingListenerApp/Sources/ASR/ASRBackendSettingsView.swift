import SwiftUI

// MARK: - ASR Backend Settings View

public struct ASRBackendSettingsView: View {
    @StateObject private var asrManager = ASRContainer.shared.hybridASRManager
    @StateObject private var featureFlags = FeatureFlagManager.shared
    
    @State private var isInitializing = false
    @State private var showComparisonWindow = false
    
    public init() {}
    
    public var body: some View {
        Form {
            // Backend Mode Section
            Section(header: Text("Backend Mode"), footer: footerText) {
                Picker("Mode", selection: $asrManager.selectedMode) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isInitializing)
                
                Text(asrManager.selectedMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            
            // Backend Status Section
            Section(header: Text("Backend Status")) {
                BackendStatusRow(
                    name: "Native MLX",
                    status: asrManager.backendStatus[asrManager.nativeBackend.name],
                    isActive: isNativeActive
                )
                
                BackendStatusRow(
                    name: "Python Server",
                    status: asrManager.backendStatus[asrManager.pythonBackend.name],
                    isActive: isPythonActive
                )
                
                HStack {
                    Button(isInitializing ? "Initializing..." : "Initialize Backends") {
                        Task {
                            isInitializing = true
                            await asrManager.initialize()
                            isInitializing = false
                        }
                    }
                    .disabled(isInitializing)
                    
                    if isInitializing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                }
            }
            
            // Capabilities Section
            Section(header: Text("Capabilities")) {
                CapabilitiesComparisonTable(
                    native: asrManager.nativeBackend.capabilities,
                    python: asrManager.pythonBackend.capabilities
                )
            }
            
            // Testing Section
            Section(header: Text("Testing")) {
                Button("Open A/B Comparison Tool") {
                    showComparisonWindow = true
                }
                .sheet(isPresented: $showComparisonWindow) {
                    BackendComparisonTestView()
                        .frame(minWidth: 700, minHeight: 500)
                }
                
                #if DEBUG
                if featureFlags.isDevMode {
                    Button("Reset Feature Flags") {
                        featureFlags.resetToDefaults()
                    }
                    .foregroundStyle(.red)
                }
                #endif
            }
            
            // Dev Mode Section (Debug only)
            #if DEBUG
            if featureFlags.isDevMode {
                Section(header: Text("Developer Options")) {
                    Toggle("Enable Dual Mode", isOn: $featureFlags.enableDualMode)
                    Toggle("Verbose Logging", isOn: $featureFlags.enableVerboseLogging)
                    Toggle("Comparison Metrics", isOn: $featureFlags.enableComparisonMetrics)
                    
                    HStack {
                        Text("Rollout: \(Int(featureFlags.nativeBackendRolloutPercentage))%")
                        Slider(value: $featureFlags.nativeBackendRolloutPercentage, in: 0...100, step: 10)
                    }
                    
                    Picker("Forced Mode", selection: Binding(
                        get: { featureFlags.forcedBackendMode ?? .autoSelect },
                        set: { featureFlags.forcedBackendMode = $0 == .autoSelect ? nil : $0 }
                    )) {
                        Text("None").tag(BackendMode.autoSelect)
                        ForEach(BackendMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }
            }
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Auto-initialize on appear if not already
            if asrManager.backendStatus.isEmpty {
                isInitializing = true
                await asrManager.initialize()
                isInitializing = false
            }
        }
    }
    
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
    
    private var footerText: some View {
        Group {
            if featureFlags.isDevMode {
                Text("Dev Mode: All features enabled. No subscription required.")
                    .foregroundStyle(.green)
            } else {
                Text("Select your preferred transcription backend. Native mode works offline. Cloud mode requires internet but offers advanced features.")
            }
        }
        .font(.caption)
    }
}

// MARK: - Backend Status Row

struct BackendStatusRow: View {
    let name: String
    let status: BackendStatus?
    let isActive: Bool
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            
            Text(name)
            
            Spacer()
            
            if isActive {
                Text("Active")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            }
            
            if let state = status?.state {
                Text(state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var statusIcon: String {
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

// MARK: - Capabilities Comparison Table

struct CapabilitiesComparisonTable: View {
    let native: BackendCapabilities
    let python: BackendCapabilities
    
    var body: some View {
        VStack(spacing: 8) {
            CapabilityRow2(name: "Streaming", native: native.supportsStreaming, python: python.supportsStreaming)
            CapabilityRow2(name: "Batch", native: native.supportsBatch, python: python.supportsBatch)
            CapabilityRow2(name: "Diarization", native: native.supportsDiarization, python: python.supportsDiarization)
            CapabilityRow2(name: "Offline", native: native.supportsOffline, python: python.supportsOffline)
            CapabilityRow2(name: "Network Required", native: native.requiresNetwork, python: python.requiresNetwork, invert: true)
        }
    }
}

struct CapabilityRow2: View {
    let name: String
    let native: Bool
    let python: Bool
    var invert: Bool = false
    
    var body: some View {
        HStack {
            Text(name)
                .frame(width: 120, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 20) {
                Label("Native", systemImage: icon(for: native))
                    .foregroundStyle(color(for: native))
                    .font(.caption)
                
                Label("Cloud", systemImage: icon(for: python))
                    .foregroundStyle(color(for: python))
                    .font(.caption)
            }
        }
    }
    
    private func icon(for value: Bool) -> String {
        value ? "checkmark.circle.fill" : "xmark.circle"
    }
    
    private func color(for value: Bool) -> Color {
        let effective = invert ? !value : value
        return effective ? .green : .red.opacity(0.5)
    }
}

// MARK: - Preview

#Preview {
    ASRBackendSettingsView()
        .frame(width: 500, height: 400)
}
