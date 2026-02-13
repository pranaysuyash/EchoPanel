import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    @StateObject private var betaGating = BetaGatingManager.shared
    
    @AppStorage("whisperModel") private var whisperModel: String = "base.en"
    @AppStorage("audioSource") private var audioSource: String = "both"
    @State private var hfToken: String = ""
    @State private var backendToken: String = ""
    @State private var showTokenSaveError = false
    @State private var tokenSaveErrorMessage = ""
    
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
            
            betaTab
                .tabItem {
                    Label("Beta Access", systemImage: "star")
                }
        }
        .frame(width: 450, height: 300)
        .onAppear {
            loadTokens()
        }
    }
    
    private var generalTab: some View {
        Form {
            Section(header: Text("Transcription Model")) {
                Picker("Model", selection: $whisperModel) {
                    Text("Tiny (Fastest)").tag("tiny")
                    Text("Tiny English").tag("tiny.en")
                    Text("Base (Recommended)").tag("base")
                    Text("Base English").tag("base.en")
                    Text("Small").tag("small")
                    Text("Small English").tag("small.en")
                    Text("Medium").tag("medium")
                    Text("Large v3").tag("large-v3")
                    Text("Large v3 Turbo").tag("large-v3-turbo")
                    Text("Distil Large v3").tag("distil-large-v3")
                }
                .pickerStyle(.menu)
                .help("ASR = Automatic Speech Recognition. Larger models are more accurate but use more memory.")
                
                Text("Larger models are more accurate but slower. Model loads on app restart.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("API Token")) {
                SecureField("Token", text: $backendToken)
                    .help("Optional: Token for cloud ASR providers")
                
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
            Section(header: Text("Audio Source")) {
                Picker("Source", selection: $audioSource) {
                    Text("System Audio Only").tag("system")
                    Text("Microphone Only").tag("microphone")
                    Text("Both (Recommended)").tag("both")
                }
                .pickerStyle(.radioGroup)
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
    
    private var betaTab: some View {
        Form {
            Section(header: Text("Beta Access")) {
                HStack {
                    Text("Status:")
                    Spacer()
                    if betaGating.isBetaAccessGranted {
                        Text("Active")
                            .foregroundColor(.green)
                    } else {
                        Text("Not Granted")
                            .foregroundColor(.secondary)
                    }
                }
                
                if betaGating.isBetaAccessGranted {
                    HStack {
                        Text("Sessions This Month:")
                        Spacer()
                        Text("\(betaGating.sessionsThisMonth)/\(betaGating.sessionLimit)")
                    }
                    
                    if let code = betaGating.validatedInviteCode {
                        HStack {
                            Text("Code Validated:")
                            Spacer()
                            Text(code)
                                .font(.caption)
                        }
                    }
                } else {
                    TextField("Invite Code", text: $hfToken)
                        .help("Enter your beta invite code")
                    
                    Button("Validate Code") {
                        let isValid = betaGating.validateInviteCode(hfToken)
                        if !isValid {
                            showTokenSaveError = true
                            tokenSaveErrorMessage = "Invalid invite code"
                        } else {
                            showTokenSaveError = false
                            hfToken = ""
                        }
                    }
                    .disabled(hfToken.isEmpty)
                    
                    if showTokenSaveError {
                        Text(tokenSaveErrorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
    }
    
    private func loadTokens() {
        if let token = KeychainHelper.loadBackendToken() {
            backendToken = token
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
}

#Preview {
    SettingsView(appState: AppState(), backendManager: BackendManager.shared)
}
