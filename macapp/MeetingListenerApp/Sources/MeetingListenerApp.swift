import SwiftUI

@main
struct MeetingListenerApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appState = AppState()
    @StateObject private var backendManager = BackendManager.shared
    @StateObject private var sessionStore = SessionStore.shared
    @State private var sidePanelController = SidePanelController()
    @StateObject private var betaGating = BetaGatingManager.shared
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
        .onChange(of: showOnboarding) { newValue in
            if newValue {
                openWindow(id: "onboarding")
            }
        }
        .commands {
            CommandMenu("EchoPanel") {
                Button(appState.sessionState == .listening ? "Stop Listening" : "Start Listening") {
                    toggleSession()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Copy Markdown") {
                    appState.copyMarkdownToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

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
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Session Summary...") {
                    openWindow(id: "summary")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Session History...") {
                    openWindow(id: "history")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                
                Divider()
                Button("Quit") { 
                    BackendManager.shared.stopServer()
                    NSApp.terminate(nil) 
                }
            }
        }
        
        // Onboarding window shown on first launch
        Window("Welcome to EchoPanel", id: "onboarding") {
            OnboardingView(appState: appState, isPresented: $showOnboarding) {
                startListeningFromOnboarding()
            }
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

        Window("Session Summary", id: "summary") {
            SummaryView(appState: appState)
        }
        .defaultSize(width: 820, height: 620)

        Window("Session History", id: "history") {
            SessionHistoryView(appState: appState, sessionStore: sessionStore)
        }
        .defaultSize(width: 980, height: 620)

        Window("EchoPanel Demo", id: "demo") {
            DemoPanelView(appState: appState) {
                appState.seedDemoData()
            }
        }
        .defaultSize(width: 980, height: 560)

        Window("EchoPanel Settings", id: "settings") {
            SettingsView(appState: appState, backendManager: backendManager)
        }
        .defaultSize(width: 450, height: 300)
    }

    private var labelContent: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.sessionState == .listening ? "waveform.circle.fill" : "waveform.circle")
                .foregroundColor(appState.sessionState == .listening ? .green : .secondary)
                .overlay(alignment: .topTrailing) {
                    if backendManager.isServerReady {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -4)
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -4)
                    }
                }
            Text(appState.timerText)
        }
        .help(backendStatusHelpText)
    }
    
    private var backendStatusHelpText: String {
        if backendManager.isServerReady {
            return "Backend ready"
        } else {
            return "Backend \(backendManager.serverStatus.rawValue)"
        }
    }
    
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // App Header
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("EchoPanel")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(appState.sessionState == .listening ? "Recording" : "Ready")
                        .font(.caption)
                        .foregroundColor(appState.sessionState == .listening ? .green : .secondary)
                }
                
                Spacer()
                
                Text(appState.timerText)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .monospacedDigit()
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Status Section
            HStack(spacing: 8) {
                Circle()
                    .fill(backendManager.isServerReady ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(backendManager.isServerReady ? "Backend Ready" : "Backend Starting")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if !appState.statusLine.isEmpty {
                Text(appState.statusLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Main Actions with colored backgrounds
            VStack(spacing: 6) {
                if appState.sessionState == .listening {
                    Button {
                        toggleSession()
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                            Text("Stop Listening")
                                .fontWeight(.medium)
                            Spacer()
                            Text("⌘⇧L")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        toggleSession()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                            Text("Start Listening")
                                .fontWeight(.medium)
                            Spacer()
                            Text("⌘⇧L")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!backendManager.isServerReady)
                }
            }
            
            // Export Section
            VStack(spacing: 6) {
                Button {
                    appState.exportJSON()
                } label: {
                    HStack {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Export JSON")
                            .font(.subheadline)
                        Spacer()
                        Text("⌘⇧E")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)
                
                Button {
                    appState.exportMarkdown()
                } label: {
                    HStack {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                        Text("Export Markdown")
                            .font(.subheadline)
                        Spacer()
                        Text("⌘⇧M")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)
            }
            
            // Recovery
            if sessionStore.hasRecoverableSession {
                Divider()
                Button {
                    if let data = sessionStore.loadRecoverableSession() {
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
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .foregroundColor(.orange)
                        Text("Recover Last Session")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Windows Section
            VStack(spacing: 4) {
                Button {
                    openWindow(id: "summary")
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                        Text("Session Summary")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                Button {
                    openWindow(id: "history")
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.gray)
                        Text("Session History")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                Button {
                    openWindow(id: "diagnostics")
                } label: {
                    HStack {
                        Image(systemName: "stethoscope")
                            .foregroundColor(.green)
                        Text("Diagnostics")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Bottom Actions
            Button {
                openWindow(id: "settings")
            } label: {
                HStack {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                    Text("Settings")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("⌘,")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .foregroundColor(.red)
                    Text("Quit EchoPanel")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("⌘Q")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 280)
    }
    
    private var broadcastSettingsTab: some View {
        BroadcastSettingsView()
            .padding()
    }
    
    private func toggleSession() {
        if appState.sessionState == .listening {
            appState.stopSession()
        } else {
            appState.startSession()
            sidePanelController.show(appState: appState) {
                self.appState.stopSession()
            }
        }
    }
    
    private func startListeningFromOnboarding() {
        showOnboarding = false
        appState.startSession()
        sidePanelController.show(appState: appState) {
            self.appState.stopSession()
        }
    }
    
    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ASRModelRecommendation {
    let modelKey: String
    let displayName: String
    let hardwareSummary: String
    let reason: String

    static func forCurrentMac() -> ASRModelRecommendation {
        let ramGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let siliconLabel: String = {
#if arch(arm64)
            return "Apple Silicon"
#else
            return "Intel"
#endif
        }()

        let summary = "\(siliconLabel), \(ramGiB) GB RAM, \(cpuCount) cores"

        if siliconLabel == "Apple Silicon" && ramGiB >= 24 {
            return ASRModelRecommendation(
                modelKey: "large-v3-turbo",
                displayName: "Large v3 Turbo",
                hardwareSummary: summary,
                reason: "high-memory profile supports better quality model"
            )
        }

        return ASRModelRecommendation(
            modelKey: "base.en",
            displayName: "Base English",
            hardwareSummary: summary,
            reason: "fastest stable baseline for local real-time meetings"
        )
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
                    if !backendManager.healthDetail.isEmpty {
                        GridRow {
                            Text("Backend Detail:")
                            Text(backendManager.healthDetail)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let code = backendManager.lastExitCode {
                        GridRow {
                            Text("Last Exit Code:")
                            Text("\(code)")
                                .foregroundColor(code == 0 ? .secondary : .orange)
                        }
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
