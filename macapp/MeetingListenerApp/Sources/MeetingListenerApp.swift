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
                seedDemoData()
            }
        }
        .defaultSize(width: 980, height: 560)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            StartupTasksView(
                appState: appState,
                showOnboarding: $showOnboarding,
                openOnboarding: { openWindow(id: "onboarding") }
            ) {
                seedDemoData()
                openWindow(id: "demo")
            }

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
            .help(backendManager.isServerReady ? "Start live notes" : "Backend not ready — click for details")
            
            Button("Export JSON") {
                appState.exportJSON()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)
            Button("Export Markdown") {
                appState.exportMarkdown()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)
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

            Button("Session Summary...") {
                openWindow(id: "summary")
            }
            Button("Session History...") {
                openWindow(id: "history")
            }
            
            Button("Show Onboarding") {
                showOnboarding = true
            }
            if ProcessInfo.processInfo.arguments.contains("--demo-ui") {
                Button("Open Demo Window") {
                    seedDemoData()
                    openWindow(id: "demo")
                }
            }
            Button("Quit") { 
                BackendManager.shared.stopServer()
                NSApp.terminate(nil) 
            }
        }
        .padding(.vertical, 4)
        .onReceive(NotificationCenter.default.publisher(for: .summaryShouldOpen)) { _ in
            openWindow(id: "summary")
        }
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
            // Always open the side panel so the user sees state and guidance even if
            // we can't start listening yet (permissions/backend not ready).
            sidePanelController.show(appState: appState) {
                appState.stopSession()
                sidePanelController.hide()
            }

            // Check if onboarding completed and server ready
            if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
                showOnboarding = true
                return
            }
            
            if !backendManager.isServerReady {
                // Surface an actionable error in the side panel header.
                appState.reportBackendNotReady(
                    detail: backendManager.healthDetail.isEmpty
                        ? "Backend not ready. Open Diagnostics to see logs."
                        : backendManager.healthDetail
                )
                return
            }
            
            appState.startSession()
        }
    }

    private func startListeningFromOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        showOnboarding = false
        toggleSession()
    }

    private func seedDemoData() {
        appState.seedDemoData()
    }
}

private struct StartupTasksView: View {
    @ObservedObject var appState: AppState
    @Binding var showOnboarding: Bool
    let openOnboarding: () -> Void
    let openDemo: () -> Void

    @State private var didRun = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                guard !didRun else { return }
                didRun = true

                // Ensure permission badges are accurate even before the first session.
                appState.refreshPermissionStatuses()

                if showOnboarding {
                    // If already true on first launch, .onChange won't fire; open explicitly.
                    openOnboarding()
                }

                if ProcessInfo.processInfo.arguments.contains("--demo-ui") {
                    openDemo()
                }
            }
    }
}

private struct DemoPanelView: View {
    @ObservedObject var appState: AppState
    let seed: () -> Void

    var body: some View {
        SidePanelView(appState: appState) {
            // Demo window should not end sessions.
        }
        .onAppear {
            seed()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var backendManager: BackendManager
    
    @AppStorage("whisperModel") private var whisperModel = "base.en"
    @AppStorage("backendHost") private var backendHost = "127.0.0.1"
    @AppStorage("backendPort") private var backendPort = 8000
    private let modelRecommendation = ASRModelRecommendation.forCurrentMac()
    
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
                    Text("Base English (Recommended)").tag("base.en")
                    Text("Base (Multilingual)").tag("base")
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large v3 Turbo (Best)").tag("large-v3-turbo")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended for this Mac: \(modelRecommendation.displayName)")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Text("\(modelRecommendation.hardwareSummary) · \(modelRecommendation.reason)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if whisperModel != modelRecommendation.modelKey {
                        Button("Use Recommended") {
                            whisperModel = modelRecommendation.modelKey
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                Text("Changes take effect after restarting the server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Backend") {
                TextField("Host", text: $backendHost)
                    .textFieldStyle(.roundedBorder)
                Stepper(value: $backendPort, in: 1024...65535) {
                    Text("Port: \(backendPort)")
                }
                Text("Backend changes take effect after restarting the server.")
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
                if backendManager.usingExternalBackend {
                    Text("Using existing backend on \(backendHost):\(backendPort).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !backendManager.healthDetail.isEmpty {
                    Text(backendManager.healthDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 420, height: 430)
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
