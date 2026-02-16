import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    
    @AppStorage("whisperModel") private var whisperModel: String = "base.en"
    @AppStorage("audioSource") private var audioSource: String = "both"
    @State private var huggingFaceToken: String = ""
    @State private var backendToken: String = ""
    @State private var showTokenSaveError = false
    @State private var tokenSaveErrorMessage = ""
    @State private var showHFTokenSaveError = false
    @State private var hfTokenSaveErrorMessage = ""
    @State private var storageStats: StorageStatistics = StorageStatistics()
    @State private var showDeleteConfirmation = false
    @State private var showExportSuccess = false
    @State private var exportURL: URL?
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            audioTab
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
            
            privacyTab
                .tabItem {
                    Label("Data & Privacy", systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 350)
        .onAppear {
            loadTokens()
            refreshStorageStats()
        }
    }
    
    private var generalTab: some View {
        Form {
            Section(header: Text("Transcription Model"), footer: Text("Larger models are more accurate but slower. Changes take effect after app restart.")) {
                Picker("Model", selection: $whisperModel) {
                    Text("Tiny — Fastest, basic accuracy").tag("tiny")
                    Text("Tiny English — Fastest, English only").tag("tiny.en")
                    Text("Base — Balanced speed & accuracy").tag("base")
                    Text("Base English — Balanced, English only").tag("base.en")
                    Text("Small — Better accuracy").tag("small")
                    Text("Small English — Better, English only").tag("small.en")
                    Text("Medium — High accuracy").tag("medium")
                    Text("Large v3 — Best accuracy, slow").tag("large-v3")
                    Text("Large v3 Turbo — Best accuracy, optimized").tag("large-v3-turbo")
                    Text("Distil Large v3 — Near-best speed & accuracy").tag("distil-large-v3")
                }
                .pickerStyle(.menu)
                .help("Choose how accurately speech is converted to text. Larger models understand more accents and context but need more memory and processing power.")
            }

            Section(header: Text("Speaker Labels (Optional)"), footer: Text("Speaker labels help identify who said what in your transcripts. Requires a free HuggingFace account.")) {
                SecureField("Enter token starting with hf_...", text: $huggingFaceToken)
                    .help("A HuggingFace token lets EchoPanel download AI models that identify different speakers in your meetings. Get a free token at huggingface.co/settings/tokens")

                HStack {
                    Button("Save Token") {
                        saveHuggingFaceToken()
                    }
                    .disabled(huggingFaceToken.isEmpty)

                    Button("Clear") {
                        let _ = KeychainHelper.deleteHFToken()
                        huggingFaceToken = ""
                        showHFTokenSaveError = false
                    }
                }

                if showHFTokenSaveError {
                    Text(hfTokenSaveErrorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section(header: Text("Cloud API Token (Optional)"), footer: Text("Only needed if using a cloud transcription service instead of local processing.")) {
                SecureField("Enter your cloud provider token", text: $backendToken)
                    .help("If you're using a cloud transcription service instead of processing audio on your Mac, enter your API token here. Most users can leave this blank.")
                
                Button("Save Token") {
                    saveBackendToken()
                }
                .disabled(backendToken.isEmpty)
                
                if showTokenSaveError {
                    Text(tokenSaveErrorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
    
    private var audioTab: some View {
        Form {
            Section(header: Text("Audio Source"), footer: Text("Choose what audio to capture from your Mac.")) {
                Picker("Source", selection: $audioSource) {
                    Text("Meeting Audio — Captures app audio (Zoom, Teams, etc.)").tag("system")
                    Text("My Microphone — Captures only your voice").tag("microphone")
                    Text("Both — Captures meeting audio + your microphone").tag("both")
                }
                .pickerStyle(.radioGroup)
                .help("Meeting Audio captures what you hear from apps like Zoom or Teams. Microphone captures your voice. 'Both' is recommended for complete transcripts.")
            }
            
            Section(header: Text("Server Status")) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(backendManager.serverStatus.rawValue)
                        .foregroundColor(backendManager.isServerReady ? .green : .secondary)
                }
                
                if !backendManager.healthDetail.isEmpty {
                    HStack {
                        Text("Health:")
                        Spacer()
                        Text(backendManager.healthDetail)
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding()
    }
    
    private var privacyTab: some View {
        Form {
            Section(header: Text("Storage Location")) {
                HStack(alignment: .top) {
                    Text("Path:")
                        .frame(width: 60, alignment: .leading)
                    Text(storageStats.storagePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(storageStats.storagePath, forType: .string)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Section(header: Text("Storage Statistics")) {
                HStack {
                    Text("Total Sessions:")
                    Spacer()
                    Text("\(storageStats.sessionCount)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Storage Used:")
                    Spacer()
                    Text(storageStats.formattedSize)
                        .foregroundColor(.secondary)
                }
                
                if storageStats.oldestSessionDate != nil {
                    HStack {
                        Text("Oldest Session:")
                        Spacer()
                        Text(storageStats.formattedOldestDate)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Data Management")) {
                HStack(spacing: 12) {
                    Button("Export All Data...") {
                        exportAllData()
                    }
                    .disabled(storageStats.sessionCount == 0)
                    
                    Button("Delete All Data...") {
                        showDeleteConfirmation = true
                    }
                    .disabled(storageStats.sessionCount == 0)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            
            Section(header: Text("Subscription")) {
                HStack {
                    Text("Status:")
                    Spacer()
                    if subscriptionManager.isSubscribed {
                        Text("Active")
                            .foregroundColor(.green)
                    } else {
                        Text("Not Active")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let tier = subscriptionManager.subscriptionType {
                    HStack {
                        Text("Plan:")
                        Spacer()
                        Text(tier.displayName)
                            .foregroundColor(.secondary)
                    }
                }
                
                switch subscriptionManager.subscriptionStatus {
                case .active(let expiresAt):
                    HStack {
                        Text("Renews:")
                        Spacer()
                        Text(formatDate(expiresAt))
                            .foregroundColor(.secondary)
                    }
                case .expired(let expiresAt):
                    HStack {
                        Text("Expired:")
                        Spacer()
                        Text(formatDate(expiresAt))
                            .foregroundColor(.red)
                    }
                default:
                    EmptyView()
                }
                
                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .disabled(subscriptionManager.isLoading)
            }
            
            Section(footer: Text("Your data is stored locally on your Mac. Audio and transcripts never leave your device unless you explicitly export them.")) {
                EmptyView()
            }
        }
        .padding()
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all \(storageStats.sessionCount) sessions and their transcripts. This cannot be undone.")
        }
        .alert("Export Successful", isPresented: $showExportSuccess) {
            Button("OK") {}
            if let url = exportURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } message: {
            Text("All session data has been exported to a ZIP archive.")
        }
    }
    
    private func refreshStorageStats() {
        storageStats = SessionStore.shared.getStorageStatistics()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func deleteAllData() {
        let success = SessionStore.shared.deleteAllSessions()
        if success {
            refreshStorageStats()
        }
    }
    
    private func exportAllData() {
        Task {
            if let url = await SessionStore.shared.exportAllSessions() {
                await MainActor.run {
                    exportURL = url
                    showExportSuccess = true
                }
            }
        }
    }
    
    private func loadTokens() {
        if let token = KeychainHelper.loadBackendToken() {
            backendToken = token
        }
        if let hf = KeychainHelper.loadHFToken() {
            huggingFaceToken = hf
        }
    }
    
    private func saveBackendToken() {
        let success = KeychainHelper.saveBackendToken(backendToken)
        if success {
            showTokenSaveError = false
            // Trigger a server restart to pick up the new token
            backendManager.stopServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                backendManager.startServer()
            }
        } else {
            showTokenSaveError = true
            tokenSaveErrorMessage = "Failed to save token to Keychain"
        }
    }

    private func saveHuggingFaceToken() {
        let success = KeychainHelper.saveHFToken(huggingFaceToken)
        if success {
            showHFTokenSaveError = false
        } else {
            showHFTokenSaveError = true
            hfTokenSaveErrorMessage = "Failed to save HuggingFace token to Keychain"
            appState.recordCredentialSaveFailure(field: "HuggingFace token")
        }
    }
}

#Preview {
    SettingsView(appState: AppState(), backendManager: BackendManager.shared)
}
