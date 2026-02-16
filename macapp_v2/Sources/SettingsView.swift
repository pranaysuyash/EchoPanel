import SwiftUI

struct SettingsView: View {
    private enum Tabs: Hashable {
        case general
        case recording
        case highlights
        case privacy
    }
    
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            
            RecordingSettings()
                .tabItem {
                    Label("Recording", systemImage: "waveform")
                }
                .tag(Tabs.recording)
            
            HighlightsSettings()
                .tabItem {
                    Label("Highlights", systemImage: "sparkles")
                }
                .tag(Tabs.highlights)
            
            PrivacySettings()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
                .tag(Tabs.privacy)
        }
        .frame(width: 500, height: 380)
        .padding()
    }
}

struct GeneralSettings: View {
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
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
                    Text(globalShortcut)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Show/Hide Panel")
                    Spacer()
                    Text("⌘⇧P")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Open History")
                    Spacer()
                    Text("⌘⇧H")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Appearance") {
                Toggle("Show recording timer in menu bar", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingSettings: View {
    @AppStorage("audioSource") private var audioSource = "System + Microphone"
    @AppStorage("vadSensitivity") private var vadSensitivity = 0.5
    @AppStorage("autoExport") private var autoExport = false
    
    var body: some View {
        Form {
            Section("Audio Source") {
                Picker("Source", selection: $audioSource) {
                    Text("System + Microphone").tag("System + Microphone")
                    Text("System Audio Only").tag("System Audio Only")
                    Text("Microphone Only").tag("Microphone Only")
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("Voice Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitivity")
                    Slider(value: $vadSensitivity, in: 0...1)
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
                
                Toggle("Automatically pause when silence detected", isOn: .constant(true))
            }
            
            Section("Export") {
                Toggle("Auto-export when session ends", isOn: $autoExport)
                
                if autoExport {
                    Picker("Format", selection: .constant("Markdown")) {
                        Text("Markdown").tag("Markdown")
                        Text("JSON").tag("JSON")
                        Text("Plain Text").tag("Plain Text")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct HighlightsSettings: View {
    @AppStorage("extractActions") private var extractActions = true
    @AppStorage("extractDecisions") private var extractDecisions = true
    @AppStorage("extractPeople") private var extractPeople = true
    @AppStorage("language") private var language = "Auto-detect"
    
    var body: some View {
        Form {
            Section("AI Analysis") {
                Toggle("Extract action items", isOn: $extractActions)
                Toggle("Identify decisions", isOn: $extractDecisions)
                Toggle("Recognize people & topics", isOn: $extractPeople)
            }
            
            Section("Language") {
                Picker("Transcription Language", selection: $language) {
                    Text("Auto-detect").tag("Auto-detect")
                    Text("English").tag("English")
                    Text("Spanish").tag("Spanish")
                    Text("French").tag("French")
                    Text("German").tag("German")
                    Text("Japanese").tag("Japanese")
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Processing")
                        .font(.headline)
                    Text("Highlights are generated locally on your device. No audio is sent to external servers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacySettings: View {
    @State private var storageUsed = "124 MB"
    @State private var sessionCount = 12
    @AppStorage("autoDeleteDays") private var autoDeleteDays = 30
    
    var body: some View {
        Form {
            Section("Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Used")
                            .font(.headline)
                        Text("\(sessionCount) sessions · \(storageUsed)")
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
                Button("Export All Sessions…") {}
                Button("Export Settings…") {}
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
