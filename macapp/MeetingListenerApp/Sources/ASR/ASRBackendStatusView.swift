import SwiftUI

// MARK: - ASR Backend Status View

public struct ASRBackendStatusView: View {
    @StateObject private var asrManager = ASRContainer.shared.hybridASRManager
    @State private var isInitializing = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            headerSection
            
            Divider()
            
            statusSection
            
            Spacer()
            
            actionButtons
        }
        .padding()
        .frame(width: 400, height: 300)
        .task {
            if asrManager.backendStatus.isEmpty {
                isInitializing = true
                await asrManager.initialize()
                isInitializing = false
            }
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading) {
                Text("ASR Backend Status")
                    .font(.headline)
                
                Text("Mode: \(asrManager.selectedMode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusCard(
                title: "Native MLX",
                icon: "cpu",
                status: asrManager.backendStatus[asrManager.nativeBackend.name],
                isActive: isNativeActive,
                color: .green
            )
            
            StatusCard(
                title: "Python Server",
                icon: "cloud",
                status: asrManager.backendStatus[asrManager.pythonBackend.name],
                isActive: isPythonActive,
                color: .purple
            )
        }
    }
    
    private var actionButtons: some View {
        HStack {
            Button(isInitializing ? "Initializing..." : "Reinitialize") {
                Task {
                    isInitializing = true
                    await asrManager.initialize()
                    isInitializing = false
                }
            }
            .disabled(isInitializing)
            
            Spacer()
            
            Picker("Mode", selection: $asrManager.selectedMode) {
                ForEach(BackendMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(width: 150)
        }
    }
    
    // MARK: - Helpers
    
    private var isNativeActive: Bool {
        asrManager.selectedMode == .nativeMLX ||
        (asrManager.selectedMode == .autoSelect && asrManager.activeBackend?.name == asrManager.nativeBackend.name)
    }
    
    private var isPythonActive: Bool {
        asrManager.selectedMode == .pythonServer ||
        (asrManager.selectedMode == .autoSelect && asrManager.activeBackend?.name == asrManager.pythonBackend.name)
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let title: String
    let icon: String
    let status: BackendStatus?
    let isActive: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
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
                        Label("\(metrics.totalRequests) reqs", systemImage: "number")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            StatusDot(state: status?.state ?? .unknown)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let state: BackendState
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
    
    private var color: Color {
        switch state {
        case .ready: return .green
        case .busy: return .orange
        case .error: return .red
        case .initializing: return .blue
        case .unknown: return .gray
        case .unavailable: return .red.opacity(0.5)
        }
    }
}

// MARK: - Preview

#Preview {
    ASRBackendStatusView()
}
