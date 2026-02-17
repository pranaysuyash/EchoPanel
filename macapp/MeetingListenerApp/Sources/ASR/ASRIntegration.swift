import SwiftUI
import Combine

// MARK: - ASR Integration Helpers

/// Provides convenient integration points for the ASR system
@MainActor
public final class ASRIntegration: ObservableObject {
    public static let shared = ASRIntegration()
    
    @Published public private(set) var isInitialized = false
    @Published public private(set) var lastError: Error?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Lifecycle
    
    public func initialize() async {
        guard !isInitialized else { return }
        
        await MainActor.run {
            let manager = ASRContainer.shared.hybridASRManager
            Task {
                await manager.initialize()
            }
        }
        
        isInitialized = true
    }
    
    public func shutdown() async {
        await MainActor.run {
            let manager = ASRContainer.shared.hybridASRManager
            Task {
                await manager.unload()
            }
        }
        
        isInitialized = false
    }
    
    // MARK: - SwiftUI Environment
    
    /// Inject ASR manager into SwiftUI environment
    public func injectEnvironment() -> some ViewModifier {
        ASREnvironmentModifier()
    }
    
    // MARK: - Menu Bar Integration
    
    public func menuBarView() -> some View {
        BackendStatusMenuItem()
    }
    
    // MARK: - Settings Integration
    
    @MainActor
    public func settingsSection() -> some View {
        BackendSelectionView(asrManager: ASRContainer.shared.hybridASRManager)
    }
}

// MARK: - Environment Modifier

@MainActor
struct ASREnvironmentModifier: ViewModifier {
    @StateObject private var asrManager: HybridASRManager
    
    init() {
        _asrManager = StateObject(wrappedValue: ASRContainer.shared.hybridASRManager)
    }
    
    func body(content: Content) -> some View {
        content
            .environmentObject(asrManager)
    }
}

// MARK: - Backend Status Menu Item

@MainActor
struct BackendStatusMenuItem: View {
    @StateObject private var asrManager: HybridASRManager
    
    init() {
        _asrManager = StateObject(wrappedValue: ASRContainer.shared.hybridASRManager)
    }
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text("ASR: \(backendName)")
            Spacer()
            Text(rtfText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var backendName: String {
        switch asrManager.selectedMode {
        case .autoSelect:
            return "Auto (\(asrManager.activeBackend?.name ?? "Selecting..."))"
        case .nativeMLX:
            return "Native"
        case .pythonServer:
            return "Cloud"
        case .dualMode:
            return "Dual"
        }
    }
    
    private var statusIcon: String {
        let status = asrManager.backendStatus[asrManager.nativeBackend.name]
        return status?.state.icon ?? "questionmark.circle"
    }
    
    private var statusColor: Color {
        let status = asrManager.backendStatus[asrManager.nativeBackend.name]
        switch status?.state {
        case .ready: return .green
        case .busy: return .orange
        case .error: return .red
        case .initializing: return .blue
        default: return .gray
        }
    }
    
    private var rtfText: String {
        let status = asrManager.backendStatus[asrManager.nativeBackend.name]
        guard let rtf = status?.performanceMetrics?.realtimeFactor else { return "" }
        return String(format: "%.2fx", rtf)
    }
}

// MARK: - Transcription Button

public struct TranscriptionButton: View {
    @EnvironmentObject var asrManager: HybridASRManager
    @State private var isRecording = false
    
    let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            if asrManager.isTranscribing {
                Task {
                    await asrManager.stopTranscription()
                }
            } else {
                action()
            }
        }) {
            Image(systemName: asrManager.isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(asrManager.isTranscribing ? .red : .accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcription Display

public struct TranscriptionDisplay: View {
    @EnvironmentObject var asrManager: HybridASRManager
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcription")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if asrManager.isTranscribing {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor)
                        Text("Listening...")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            
            ScrollView {
                Text(asrManager.streamingText.isEmpty ? "Transcription will appear here..." : asrManager.streamingText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(asrManager.streamingText.isEmpty ? .secondary : .primary)
            }
            .frame(minHeight: 100)
            
            if let error = asrManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Backend Badge

public struct BackendBadge: View {
    @EnvironmentObject var asrManager: HybridASRManager
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: backendIcon)
            Text(backendName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backendColor.opacity(0.2))
        .foregroundStyle(backendColor)
        .cornerRadius(4)
    }
    
    private var backendName: String {
        switch asrManager.selectedMode {
        case .autoSelect:
            return "Auto"
        case .nativeMLX:
            return "Native"
        case .pythonServer:
            return "Cloud"
        case .dualMode:
            return "Dual"
        }
    }
    
    private var backendIcon: String {
        switch asrManager.selectedMode {
        case .autoSelect:
            return "arrow.triangle.2.circlepath"
        case .nativeMLX:
            return "cpu"
        case .pythonServer:
            return "cloud"
        case .dualMode:
            return "square.split.2x1"
        }
    }
    
    private var backendColor: Color {
        switch asrManager.selectedMode {
        case .autoSelect:
            return .blue
        case .nativeMLX:
            return .green
        case .pythonServer:
            return .purple
        case .dualMode:
            return .orange
        }
    }
}

// MARK: - View Extensions

public extension View {
    func withASR() -> some View {
        self.modifier(ASREnvironmentModifier())
    }
}

// MARK: - Audio Capture Integration

/// Integrates with AudioCaptureManager to feed audio to ASR
public actor ASRAudioCaptureIntegration {
    public static let shared = ASRAudioCaptureIntegration()
    
    private var audioStreamContinuation: AsyncStream<[Float]>.Continuation?
    private var audioStream: AsyncStream<[Float]>?
    
    private init() {}
    
    public func startCapture() -> AsyncStream<[Float]> {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        audioStream = stream
        audioStreamContinuation = continuation
        return stream
    }
    
    public func feedAudio(_ samples: [Float]) {
        audioStreamContinuation?.yield(samples)
    }
    
    public func stopCapture() {
        audioStreamContinuation?.finish()
        audioStreamContinuation = nil
        audioStream = nil
    }
}
