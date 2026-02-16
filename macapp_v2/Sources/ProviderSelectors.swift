import SwiftUI

struct AudioSourceSelector: View {
    @Binding var selectedSource: AudioSource
    @Environment(\.dismiss) private var dismiss
    
    enum AudioSource: String, CaseIterable {
        case systemAndMic = "System + Microphone"
        case systemOnly = "System Audio Only"
        case micOnly = "Microphone Only"
        
        var icon: String {
            switch self {
            case .systemAndMic: return "speaker.wave.2.fill"
            case .systemOnly: return "speaker.wave.3.fill"
            case .micOnly: return "mic.fill"
            }
        }
        
        var description: String {
            switch self {
            case .systemAndMic:
                return "Capture both meeting audio and your voice"
            case .systemOnly:
                return "Capture only the meeting audio (participants)"
            case .micOnly:
                return "Capture only your microphone"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio Source")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(AudioSource.allCases, id: \.self) { source in
                        SourceOption(
                            source: source,
                            isSelected: selectedSource == source
                        ) {
                            selectedSource = source
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Requires screen recording permission for system audio", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 400, height: 380)
    }
}

struct SourceOption: View {
    let source: AudioSourceSelector.AudioSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { action() }) {
            HStack(spacing: 16) {
                Image(systemName: source.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.rawValue)
                        .font(.headline)
                    Text(source.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProviderSelector: View {
    @Binding var selectedProvider: ASRProvider
    @Environment(\.dismiss) private var dismiss
    
    enum ASRProvider: String, CaseIterable {
        case auto = "Auto-Select"
        case fasterWhisper = "Faster Whisper"
        case whisperCpp = "Whisper.cpp"
        case mlxWhisper = "MLX Whisper"
        case onnxWhisper = "ONNX Whisper"
        case voxtral = "Voxtral"
        
        var description: String {
            switch self {
            case .auto:
                return "Automatically choose best provider for your hardware"
            case .fasterWhisper:
                return "Good balance of speed and accuracy (recommended)"
            case .whisperCpp:
                return "Optimized for Apple Silicon and CUDA"
            case .mlxWhisper:
                return "Native Apple Silicon acceleration"
            case .onnxWhisper:
                return "Cross-platform ONNX runtime"
            case .voxtral:
                return "High-end speech model (requires 32GB+ RAM)"
            }
        }
        
        var hardwareRequirements: String {
            switch self {
            case .auto: return "Any"
            case .fasterWhisper: return "8GB+ RAM recommended"
            case .whisperCpp: return "Apple Silicon or CUDA GPU"
            case .mlxWhisper: return "Apple Silicon only"
            case .onnxWhisper: return "Any CPU"
            case .voxtral: return "32GB+ RAM, GPU recommended"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcription Provider")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ASRProvider.allCases, id: \.self) { provider in
                        ProviderOption(
                            provider: provider,
                            isSelected: selectedProvider == provider
                        ) {
                            selectedProvider = provider
                            dismiss()
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 500)
    }
}

struct ProviderOption: View {
    let provider: ProviderSelector.ASRProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: { action() }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.rawValue)
                            .font(.headline)
                        
                        if provider == .auto {
                            Text("Recommended")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(provider.hardwareRequirements, systemImage: "cpu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
