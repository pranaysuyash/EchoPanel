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
    @State private var showTermsAcceptance = !UserDefaults.standard.bool(forKey: "hasAcceptedTerms")
    @State private var showRecoveryPrompt = false

    init() {
        // Start backend server on app launch
        BackendManager.shared.startServer()
        
        // Start data retention manager for automatic cleanup
        DataRetentionManager.shared.start()
        
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
        .onChange(of: showTermsAcceptance) { newValue in
            if newValue {
                openWindow(id: "terms-acceptance")
            }
        }
        .onChange(of: showOnboarding) { newValue in
            if newValue {
                openWindow(id: "onboarding")
            }
        }
        .commands {
            CommandMenu("EchoPanel") {
                Button(appState.sessionState == .listening ? "End Session" : "Start Listening") {
                    toggleSession()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Copy Markdown") {
                    appState.copyMarkdownToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Export for Apps (JSON)") {
                    appState.exportJSON()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help("Export transcript as JSON for use in other applications")

                Button("Export for Notes (Markdown)") {
                    appState.exportMarkdown()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Export transcript as Markdown for notes and documents")

                Menu("Export Minutes (MOM)") {
                    Button("Default") { appState.exportMinutesOfMeeting(template: .standard) }
                    Button("Executive") { appState.exportMinutesOfMeeting(template: .executive) }
                    Button("Engineering") { appState.exportMinutesOfMeeting(template: .engineering) }
                }
                .help("Export structured Minutes of Meeting")

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
                
                Button("Keyboard Shortcuts...") {
                    openWindow(id: "keyboard-cheatsheet")
                }
                .keyboardShortcut("?", modifiers: [.command])
                
                Divider()
                
                Menu("ASR Backend") {
                    Button("A/B Testing...") {
                        openWindow(id: "asr-testing")
                    }
                    
                    Button("Backend Comparison") {
                        openWindow(id: "asr-comparison")
                    }
                    
                    #if DEBUG
                    Divider()
                    
                    Button("Reset Feature Flags") {
                        FeatureFlagManager.shared.resetToDefaults()
                    }
                    
                    Button("Enable All Dev Features") {
                        FeatureFlagManager.shared.enableAllForDev()
                    }
                    #endif
                }
                Button("Quit") { 
                    BackendManager.shared.stopServer()
                    NSApp.terminate(nil) 
                }
            }
        }
        
        // Terms acceptance window shown on first launch
        Window("Terms and Conditions", id: "terms-acceptance") {
            TermsAcceptanceView {
                showTermsAcceptance = false
                if showOnboarding {
                    openWindow(id: "onboarding")
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 400)
        .windowResizability(.contentSize)

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
        .defaultSize(width: 500, height: 350)
        
        Window("Keyboard Shortcuts", id: "keyboard-cheatsheet") {
            KeyboardCheatsheetView()
        }
        .defaultSize(width: 600, height: 500)
        .windowResizability(.contentSize)
        
        // MARK: - ASR Backend Testing Windows
        
        Window("ASR A/B Testing", id: "asr-testing") {
            BackendComparisonTestView()
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentSize)
        
        Window("ASR Backend Status", id: "asr-status") {
            ASRBackendStatusView()
        }
        .defaultSize(width: 400, height: 300)
        .windowResizability(.contentSize)
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
    
    /// Format date for recent sessions menu
    private func formatRecentSessionDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var backendStatusHelpText: String {
        let hasSessions = UserDefaults.standard.integer(forKey: "totalSessionsRecorded") > 0
        
        if !hasSessions && appState.sessionState != .listening {
            return "Click to start your first session"
        }
        
        if backendManager.isServerReady {
            return "Backend ready - Click to start/stop listening"
        } else {
            return "Backend \(backendManager.serverStatus.rawValue) - Waiting for backend..."
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
                            Text("End Session")
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

                Menu {
                    Button("Default") { appState.exportMinutesOfMeeting(template: .standard) }
                    Button("Executive") { appState.exportMinutesOfMeeting(template: .executive) }
                    Button("Engineering") { appState.exportMinutesOfMeeting(template: .engineering) }
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(.teal)
                        Text("Export MOM")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)
            }
            
            // Recent Sessions
            let recentSessions = sessionStore.listSessions().prefix(3)
            if !recentSessions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    ForEach(Array(recentSessions), id: \.id) { session in
                        Button {
                            openWindow(id: "history")
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(formatRecentSessionDate(session.date))
                                    .font(.subheadline)
                                Spacer()
                                if session.hasTranscript {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
    @State private var crashLogs: [CrashReporter.CrashLog] = []
    @State private var selectedCrashId: String?
    @State private var showCrashDetail = false
    
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
            
            GroupBox("Crash Reports") {
                VStack(alignment: .leading, spacing: 10) {
                    if crashLogs.isEmpty {
                        Text("No crashes recorded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(crashLogs.count) crash(es) recorded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(crashLogs.prefix(3).map { $0 }, id: \.id) { (log: CrashReporter.CrashLog) in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.formattedDate)
                                        .font(.caption)
                                    Text(log.exceptionName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button("Copy") {
                                    if CrashReporter.shared.copyCrashReportToClipboard(id: log.id) {
                                        appState.setUserNotice("Crash report copied.", level: .success)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                        }
                        
                        if crashLogs.count > 3 {
                            Text("+ \(crashLogs.count - 3) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Button("Export All...") {
                                if let url = CrashReporter.shared.exportAllCrashLogs() {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .controlSize(.small)
                            
                            Button("Clear All") {
                                _ = CrashReporter.shared.deleteAllCrashLogs()
                                refreshCrashLogs()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 5)
                .onAppear {
                    refreshCrashLogs()
                }
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

                    Button("Copy Session ID") {
                        guard let sessionId = appState.sessionID else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sessionId, forType: .string)
                        appState.setUserNotice("Session ID copied.", level: .success)
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(appState.sessionID == nil)

                    Button("Report Issue...") {
                        let subject = "EchoPanel Issue Report"
                        let body = """
                        Describe the issue:
                        
                        
                        ---
                        Build: v0.2
                        Backend Status: \(backendManager.serverStatus.rawValue)
                        Server Ready: \(backendManager.isServerReady)
                        Input Source: \(appState.audioSource.rawValue)
                        Session ID: \(appState.sessionID ?? "none")
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
        .frame(width: 400, height: 450)
    }
    
    private func refreshCrashLogs() {
        crashLogs = CrashReporter.shared.getCrashLogs()
    }
}
