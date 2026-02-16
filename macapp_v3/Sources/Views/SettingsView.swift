import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            RecordingSettings()
                .tabItem {
                    Label("Recording", systemImage: "waveform")
                }
            
            ProviderSettings()
                .tabItem {
                    Label("Providers", systemImage: "cpu")
                }
            
            AnalysisSettings()
                .tabItem {
                    Label("Analysis", systemImage: "sparkles")
                }
            
            PrivacySettings()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
        .frame(width: 550, height: 400)
        .padding()
    }
}

// MARK: - General Settings
struct GeneralSettings: View {
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("globalShortcut") private var globalShortcut = "⌘⇧R"
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $startAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
            }
            
            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Start/Stop Recording")
                    Spacer()
                    Text("⌘⇧R")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Pause/Resume")
                    Spacer()
                    Text("⌘⇧P")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Show/Hide Panel")
                    Spacer()
                    Text("⌘⇧S")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Open Dashboard")
                    Spacer()
                    Text("⌘⇧D")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Appearance") {
                Toggle("Show recording timer in menu bar", isOn: .constant(true))
                Toggle("Animate live transcript updates", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Recording Settings
struct RecordingSettings: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Form {
            Section("Audio Source") {
                Picker("Default Source", selection: $appState.audioSource) {
                    ForEach(AudioSource.allCases) { source in
                        Label(source.rawValue, systemImage: source.icon)
                            .tag(source)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("Voice Detection") {
                Toggle("Enable Voice Activity Detection (VAD)", isOn: $appState.enableVAD)
                
                if appState.enableVAD {
                    VStack(alignment: .leading) {
                        Text("Sensitivity")
                        Slider(value: .constant(0.5), in: 0...1)
                        HStack {
                            Text("Less sensitive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("More sensitive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Toggle("Auto-pause when silence detected", isOn: .constant(true))
                    Toggle("Auto-end after extended silence", isOn: .constant(true))
                }
            }
            
            Section("Export") {
                Picker("Auto-export format", selection: $appState.autoExportFormat) {
                    Text("None").tag("None")
                    Text("Markdown").tag("Markdown")
                    Text("JSON").tag("JSON")
                    Text("Plain Text").tag("Plain Text")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Provider Settings
struct ProviderSettings: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Form {
            Section("ASR Provider") {
                Picker("Provider", selection: $appState.asrProvider) {
                    ForEach(ASRProvider.allCases) { provider in
                        HStack {
                            Text(provider.rawValue)
                            if provider.isRecommended {
                                Text("Recommended")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(appState.asrProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if appState.asrProvider != .auto {
                    Label(appState.asrProvider.hardwareRequirements, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Performance") {
                HStack {
                    Text("Current Provider")
                    Spacer()
                    Text("Faster Whisper")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Model Size")
                    Spacer()
                    Text("base.en")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Compute Type")
                    Spacer()
                    Text("float16")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Realtime Factor (RTF)")
                    Spacer()
                    Text("0.45")
                        .foregroundStyle(.green)
                }
                
                HStack {
                    Text("Inference Latency")
                    Spacer()
                    Text("150ms")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Hardware Detection") {
                HStack {
                    Text("RAM")
                    Spacer()
                    Text("16 GB")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("GPU")
                    Spacer()
                    Text("Apple Silicon (MPS)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Recommended Provider")
                    Spacer()
                    Text("Faster Whisper")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Analysis Settings
struct AnalysisSettings: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Form {
            Section("Speaker Recognition") {
                Toggle("Enable speaker diarization", isOn: $appState.enableDiarization)
                
                if appState.enableDiarization {
                    Text("Identifies different speakers in the conversation. Requires more processing power.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Entity Extraction") {
                Toggle("Extract people and organizations", isOn: .constant(true))
                Toggle("Extract dates and deadlines", isOn: .constant(true))
                Toggle("Extract topics and keywords", isOn: .constant(true))
            }
            
            Section("Card Extraction") {
                Toggle("Extract action items", isOn: .constant(true))
                Toggle("Extract decisions", isOn: .constant(true))
                Toggle("Extract risks and blockers", isOn: .constant(true))
            }
            
            Section("Language") {
                Picker("Transcription Language", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("Auto-detect")
                    Text("English").tag("English")
                    Text("Spanish").tag("Spanish")
                    Text("French").tag("French")
                    Text("German").tag("German")
                    Text("Japanese").tag("Japanese")
                }
            }
            
            Section("LLM Enhancement") {
                Picker("LLM Provider", selection: $appState.llmProvider) {
                    Text("None (keyword only)").tag("None")
                    Text("OpenAI").tag("OpenAI")
                    Text("Ollama (Local)").tag("Ollama")
                }
                
                if appState.llmProvider != "None" {
                    Text("Using LLM for more accurate extraction and summary generation. Data is processed locally when using Ollama.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Screen OCR") {
                Toggle("Capture and index screen content", isOn: $appState.enableScreenOCR)
                
                if appState.enableScreenOCR {
                    Text("Automatically captures slides and documents shown on screen for context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy Settings
struct PrivacySettings: View {
    @State private var storageUsed = "124 MB"
    @State private var sessionCount = 12
    @AppStorage("autoDeleteDays") private var autoDeleteDays = 30
    
    var body: some View {
        Form {
            Section("Data Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Used")
                            .font(.headline)
                        Text("\(sessionCount) sessions • \(storageUsed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear All") {}
                        .buttonStyle(.bordered)
                }
                
                Picker("Auto-delete after", selection: $autoDeleteDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Never").tag(0)
                }
            }
            
            Section("Data Export") {
                Button("Export All Sessions...") {}
                Button("Export Settings...") {}
            }
            
            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Microphone Access")
                            .font(.headline)
                        Text("Required for recording your voice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen Recording")
                            .font(.headline)
                        Text("Required for capturing system audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Promise")
                        .font(.headline)
                    Text("All your data stays on your device. We don't upload, share, or analyze your recordings. You have full control over your data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
