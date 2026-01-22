import SwiftUI

@main
struct MeetingListenerApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appState = AppState()
    @StateObject private var backendManager = BackendManager.shared
    @StateObject private var sessionStore = SessionStore.shared
    @State private var sidePanelController = SidePanelController()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")
    @State private var showRecoveryPrompt = false

    init() {
        // Start backend server on app launch
        BackendManager.shared.startServer()
        
        // Gap 5 fix: Check for recoverable session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if SessionStore.shared.hasRecoverableSession {
                // Will be handled in view
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            labelContent
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandMenu("EchoPanel") {
                Button(appState.sessionState == .listening ? "Stop Listening" : "Start Listening") {
                    toggleSession()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Copy Markdown") {
                    appState.copyMarkdownToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button("Export JSON") {
                    appState.exportJSON()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Export Markdown") {
                    appState.exportMarkdown()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()
                
                // Server status
                Text("Server: \(backendManager.serverStatus.rawValue)")
                    .foregroundColor(backendManager.isServerReady ? .green : .secondary)
                
                Button("Diagnostics...") {
                    openWindow(id: "diagnostics")
                }
                
                Divider()
                Button("Quit") { 
                    BackendManager.shared.stopServer()
                    NSApp.terminate(nil) 
                }
            }
        }
        
        // Onboarding window shown on first launch
        Window("Welcome to EchoPanel", id: "onboarding") {
            OnboardingView(appState: appState, isPresented: $showOnboarding)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView(appState: appState, backendManager: backendManager)
        }
        
        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(appState: appState, backendManager: backendManager)
        }
        .windowResizability(.contentSize)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.sessionState == .listening ? "Listening" : "Idle")
                .font(.headline)
            Text("Timer: \(appState.timerText)")
                .font(.caption)
                .monospacedDigit()
            if !appState.statusLine.isEmpty {
                Text(appState.statusLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Server status indicator
            HStack {
                Circle()
                    .fill(backendManager.isServerReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(backendManager.serverStatus.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            Button(appState.sessionState == .listening ? "Stop Listening" : "Start Listening") {
                toggleSession()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!backendManager.isServerReady)
            
            Button("Export JSON") {
                appState.exportJSON()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export Markdown") {
                appState.exportMarkdown()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            
            // Gap 5 fix: Session recovery option
            if sessionStore.hasRecoverableSession {
                Button("Recover Last Session...") {
                    if let data = sessionStore.loadRecoverableSession() {
                        // Export recovered data to JSON
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "recovered-session.json"
                        panel.begin { response in
                            guard response == .OK, let url = panel.url else { return }
                            do {
                                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted])
                                try jsonData.write(to: url)
                                sessionStore.discardRecoverableSession()
                            } catch {
                                NSLog("Recovery export failed: %@", error.localizedDescription)
                            }
                        }
                    }
                }
                Button("Discard Last Session") {
                    sessionStore.discardRecoverableSession()
                }
                Divider()
            }
            
            Button("Show Onboarding") {
                showOnboarding = true
            }
            Button("Quit") { 
                BackendManager.shared.stopServer()
                NSApp.terminate(nil) 
            }
        }
        .padding(.vertical, 4)
    }

    private var labelContent: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.sessionState == .listening ? "waveform.circle.fill" : "waveform.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(appState.sessionState == .listening ? Color.green : Color.secondary, Color.secondary.opacity(0.3))
            Text(appState.timerText)
                .monospacedDigit()
        }
        .accessibilityLabel(appState.sessionState == .listening ? "EchoPanel listening" : "EchoPanel idle")
    }

    private func toggleSession() {
        if appState.sessionState == .listening {
            appState.stopSession()
            sidePanelController.hide()
        } else {
            // Check if onboarding completed and server ready
            if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                showOnboarding = true
                return
            }
            
            if !backendManager.isServerReady {
                // TODO: Show alert that server is not ready
                return
            }
            
            appState.startSession()
            sidePanelController.show(appState: appState) {
                appState.stopSession()
                sidePanelController.hide()
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    
    var body: some View {
        Form {
            Section("Audio") {
                Picker("Source", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            }
            
            Section("ASR Model") {
                Picker("Whisper Model", selection: $whisperModel) {
                    Text("Base (Fast)").tag("base")
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large v3 Turbo (Best)").tag("large-v3-turbo")
                }
                Text("Changes take effect after restarting the server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Server") {
                HStack {
                    Text("Status")
                    Spacer()
                    Circle()
                        .fill(backendManager.isServerReady ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(backendManager.serverStatus.rawValue)
                }
                
                Button("Restart Server") {
                    backendManager.stopServer()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        backendManager.startServer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}

// MARK: - Diagnostics View (v0.2)

struct DiagnosticsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("System Status") {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text("Backend Status:")
                        Text(backendManager.serverStatus.rawValue)
                            .foregroundColor(backendManager.serverStatus == .running ? .green : .secondary)
                    }
                    GridRow {
                        Text("Server Ready:")
                        Text(backendManager.isServerReady ? "Yes" : "No")
                            .bold()
                    }
                    GridRow {
                        Text("Input Source:")
                        Text(appState.audioSource.rawValue)
                    }
                    GridRow {
                        Text("Last Heartbeat:")
                        if let date = appState.lastMessageDate {
                            Text(date, style: .time)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            
            GroupBox("Troubleshooting") {
                VStack(alignment: .leading) {
                    Text("If you encounter issues, please export a debug bundle to share with support.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button("Export Debug Bundle...") {
                        appState.exportDebugBundle()
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Report Issue...") {
                        let subject = "EchoPanel Beta Issue Report"
                        let body = """
                        Describe the issue:
                        
                        
                        ---
                        Build: v0.2
                        Backend Status: \(backendManager.serverStatus.rawValue)
                        Server Ready: \(backendManager.isServerReady)
                        Input Source: \(appState.audioSource.rawValue)
                        """
                        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "mailto:support@example.com?subject=\(encodedSubject)&body=\(encodedBody)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 5)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}
