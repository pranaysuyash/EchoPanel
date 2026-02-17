import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    
    @AppStorage("whisperModel") private var whisperModel: String = "base.en"
    @AppStorage("audioSource") private var audioSource: String = "both"
    @AppStorage("llmProvider") private var llmProvider: String = "none"
    @AppStorage("llmModel") private var llmModel: String = "gpt-4o-mini"
    @AppStorage("vadEnabled") private var vadEnabled: Bool = true
    @AppStorage("vadThreshold") private var vadThreshold: Double = 0.5
    @AppStorage("dataRetentionPeriod") private var retentionPeriodDays: Int = 90
    @AppStorage("ocrMode") private var ocrMode: String = "hybrid"
    @AppStorage("ocrVLMTrigger") private var ocrVLMTrigger: String = "adaptive"
    @AppStorage("ocrEnabled") private var ocrEnabled: Bool = true
    @State private var openAIKey: String = ""
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
    @State private var lastCleanupDate: Date?
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
            
            aiTab
                .tabItem {
                    Label("AI Analysis", systemImage: "brain.head.profile")
                }
            
            asrBackendTab
                .tabItem {
                    Label("ASR Backend", systemImage: "cpu")
                }
            
            privacyTab
                .tabItem {
                    Label("Data & Privacy", systemImage: "lock.shield")
                }

            legalTab
                .tabItem {
                    Label("Legal", systemImage: "doc.text")
                }
        }
        .frame(width: 500, height: 380)
        .onAppear {
            loadTokens()
            refreshStorageStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionHistoryShouldRefresh)) { _ in
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
    
    private var aiTab: some View {
        Form {
            Section(header: Text("Voice Activity Detection (VAD)"), footer: Text("VAD filters out silence before sending audio to transcription. This reduces CPU usage by ~40% in typical meetings.")) {
                Toggle("Enable VAD", isOn: $vadEnabled)
                        .onChange(of: vadEnabled) { newValue in
                        // Update backend via environment
                        setBackendVADEnabled(newValue)
                    }
                
                if vadEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sensitivity: \(Int(vadThreshold * 100))%")
                            .font(.caption)
                        Slider(value: $vadThreshold, in: 0.1...0.9, step: 0.1)
                                .onChange(of: vadThreshold) { newValue in
                                setBackendVADThreshold(newValue)
                            }
                        Text("Higher = more strict (less false positives, may miss quiet speech)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Screen Content Recognition (OCR)"), footer: Text("Extract text from shared slides and screens during meetings. Hybrid mode uses fast OCR + AI understanding for best results.")) {
                Toggle("Enable Screen Capture", isOn: $ocrEnabled)
                    .onChange(of: ocrEnabled) { newValue in
                        setBackendOCREnabled(newValue)
                    }
                
                if ocrEnabled {
                    Picker("Mode", selection: $ocrMode) {
                        Text("Hybrid — Fast + Smart (Recommended)").tag("hybrid")
                        Text("Fast Only — Basic text extraction").tag("paddle_only")
                        Text("Smart Only — AI understanding").tag("vlm_only")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: ocrMode) { newValue in
                        setBackendOCRMode(newValue)
                    }
                    
                    Picker("AI Enhancement", selection: $ocrVLMTrigger) {
                        Text("Adaptive — Smart triggering").tag("adaptive")
                        Text("Always — Every frame").tag("always")
                        Text("Confidence — Low confidence only").tag("confidence")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: ocrVLMTrigger) { newValue in
                        setBackendOCRVLMTrigger(newValue)
                    }
                    
                    Text("Hybrid: Fast OCR (50ms) + AI (200ms) when needed\nAdaptive: AI runs on charts, tables, and low confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("LLM-Powered Analysis"), footer: Text("Use AI to intelligently extract action items, decisions, and risks from transcripts. Local models run on your Mac with no data sent to the cloud.")) {
                Picker("Provider", selection: $llmProvider) {
                    Text("Disabled — Use keyword matching").tag("none")
                    Text("OpenAI — Best accuracy (cloud)").tag("openai")
                    Text("Ollama — Local & private").tag("ollama")
                }
                .pickerStyle(.menu)
                .onChange(of: llmProvider) { newValue in
                    setBackendLLMProvider(newValue)
                }
                
                if llmProvider == "openai" {
                    SecureField("OpenAI API Key (starts with sk-...)", text: $openAIKey)
                        .onAppear {
                            openAIKey = KeychainHelper.loadOpenAIKey() ?? ""
                        }
                    
                    HStack {
                        Button("Save Key") {
                            saveOpenAIKey()
                        }
                        .disabled(openAIKey.isEmpty)
                        
                        Button("Clear") {
                            let _ = KeychainHelper.deleteOpenAIKey()
                            openAIKey = ""
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Picker("Model", selection: $llmModel) {
                        Text("GPT-4o Mini — Fast & affordable").tag("gpt-4o-mini")
                        Text("GPT-4o — Best quality").tag("gpt-4o")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: llmModel) { newValue in
                        setBackendLLMModel(newValue)
                    }
                }
                
                if llmProvider == "ollama" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requires Ollama installed and running")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Link("Download Ollama", destination: URL(string: "https://ollama.com")!)
                            .font(.caption)
                        
                        Divider()
                        
                        Text("8GB Macs - Lightweight models:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Button("gemma3:1b") {
                                llmModel = "gemma3:1b"
                                setBackendLLMModel("gemma3:1b")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .help("Google Gemma 3, ~0.8GB RAM, 32k context")
                            
                            Button("llama3.2:1b") {
                                llmModel = "llama3.2:1b"
                                setBackendLLMModel("llama3.2:1b")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Meta, ~0.7GB RAM, 128k context")
                        }
                        
                        Text("16GB+ Macs - Better quality:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        HStack(spacing: 8) {
                            Button("gemma3:4b") {
                                llmModel = "gemma3:4b"
                                setBackendLLMModel("gemma3:4b")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Google Gemma 3, ~2.5GB RAM, 128k context, beats Gemma 2 27B")
                            
                            Button("llama3.2:3b") {
                                llmModel = "llama3.2:3b"
                                setBackendLLMModel("llama3.2:3b")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Meta, ~2GB RAM, 128k context")
                            
                            Button("qwen2.5:7b") {
                                llmModel = "qwen2.5:7b"
                                setBackendLLMModel("qwen2.5:7b")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Alibaba, ~4.5GB RAM, multilingual")
                        }
                        
                        if !llmModel.isEmpty && llmModel != "gpt-4o-mini" && llmModel != "gpt-4o" {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Selected: \(llmModel)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text("Install: ollama pull \(llmModel.isEmpty ? "<model>" : llmModel)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                            .padding(.top, 4)
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

            Section(header: Text("Retention"), footer: Text("Cleanup runs daily while EchoPanel is open. Sessions older than the selected period will be removed.")) {
                Picker("Retention", selection: $retentionPeriodDays) {
                    Text("Never (keep forever)").tag(0)
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days (default)").tag(90)
                    Text("180 days").tag(180)
                    Text("365 days").tag(365)
                }
                .pickerStyle(.menu)
                .onChange(of: retentionPeriodDays) { newValue in
                    if newValue > 0 {
                        _ = DataRetentionManager.shared.cleanupOldSessions(retentionDays: newValue)
                    }
                    refreshStorageStats()
                }

                HStack {
                    Text("Last cleanup:")
                    Spacer()
                    Text(formatCleanupDate(lastCleanupDate))
                        .foregroundColor(.secondary)
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
        lastCleanupDate = DataRetentionManager.shared.lastCleanupDate
    }

    private func formatCleanupDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        if let openAI = KeychainHelper.loadOpenAIKey() {
            openAIKey = openAI
        }
    }
    
    private func saveOpenAIKey() {
        let success = KeychainHelper.saveOpenAIKey(openAIKey)
        if success {
            // Restart server to pick up new key
            backendManager.stopServer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.backendManager.startServer()
            }
        }
    }
    
    private func setBackendVADEnabled(_ enabled: Bool) {
        // Set environment variable and restart server to apply
        setenv("ECHOPANEL_ASR_VAD", enabled ? "1" : "0", 1)
        backendManager.stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.backendManager.startServer()
        }
    }
    
    private func setBackendVADThreshold(_ threshold: Double) {
        let thresholdStr = String(format: "%.1f", threshold)
        setenv("ECHOPANEL_VAD_THRESHOLD", thresholdStr, 1)
        // Threshold change doesn't require restart
    }
    
    private func setBackendLLMProvider(_ provider: String) {
        setenv("ECHOPANEL_LLM_PROVIDER", provider, 1)
        backendManager.stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.backendManager.startServer()
        }
    }
    
    private func setBackendLLMModel(_ model: String) {
        setenv("ECHOPANEL_LLM_MODEL", model, 1)
        // Model change doesn't require restart
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
    
    // MARK: - OCR Configuration
    
    private func setBackendOCREnabled(_ enabled: Bool) {
        setenv("ECHOPANEL_OCR_ENABLED", enabled ? "true" : "false", 1)
        backendManager.stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.backendManager.startServer()
        }
    }
    
    private func setBackendOCRMode(_ mode: String) {
        setenv("ECHOPANEL_OCR_MODE", mode, 1)
        // Mode change doesn't require restart
    }
    
    private func setBackendOCRVLMTrigger(_ trigger: String) {
        setenv("ECHOPANEL_OCR_VLM_TRIGGER", trigger, 1)
        // Trigger change doesn't require restart
    }
    
    // MARK: - ASR Backend Tab
    
    private var asrBackendTab: some View {
        ASRBackendSettingsView()
    }

    private var legalTab: some View {
        Form {
            Section(header: Text("Legal Documents")) {
                Button("Privacy Policy") {
                    openLegalDocument(.privacy)
                }
                .help("Read how EchoPanel protects your privacy and handles your data")

                Button("Terms of Service") {
                    openLegalDocument(.terms)
                }
                .help("Read the terms for using EchoPanel")
            }

            Section(header: Text("Contact")) {
                Button("Contact Developer") {
                    openContactEmail()
                }
                .help("Email the developer with questions or feedback")

                Button("Report a Problem") {
                    openSupportEmail()
                }
                .help("Get help with technical issues")
            }

            Section(header: Text("About EchoPanel"), footer: Text("EchoPanel is built by a solo developer who cares about privacy. Your data stays on your Mac, you control what gets processed, and there's no tracking or data selling.")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EchoPanel")
                        .font(.headline)
                    Text("Privacy-focused meeting transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Version 0.2.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }

    private func openLegalDocument(_ documentType: LegalDocument) {
        switch documentType {
        case .privacy:
            if let url = URL(string: "https://echopanel.app/privacy") {
                NSWorkspace.shared.open(url)
            }
        case .terms:
            if let url = URL(string: "https://echopanel.app/terms") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func openContactEmail() {
        if let url = URL(string: "mailto:echo@echopanel.app") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openSupportEmail() {
        if let url = URL(string: "mailto:support@echopanel.app") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LegalDocument {
    case privacy, terms
}

#Preview {
    SettingsView(appState: AppState(), backendManager: BackendManager.shared)
}
