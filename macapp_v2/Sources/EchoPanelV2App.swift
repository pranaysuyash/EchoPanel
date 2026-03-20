import SwiftUI
import AppKit

@main
struct EchoPanelV2App: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("asrProvider") private var asrProvider = "Auto-Select"
    @AppStorage("llmProvider") private var llmProvider = "Auto-Select"
    @AppStorage("audioSource") private var audioSource = "System + Microphone"
    
    var body: some Scene {
        WindowGroup("EchoPanel", id: "main") {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingContainerView(isPresented: .constant(true), hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environmentObject(appState)
                } else {
                    MainView()
                        .environmentObject(appState)
                }
            }
            .frame(minWidth: 480, minHeight: 360)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if hasCompletedOnboarding {
                        Picker("Workspace", selection: $appState.workspaceMode) {
                            ForEach(AppState.WorkspaceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        RecordButton()
                        Spacer()
                        ExportButton()
                        SettingsButton()
                    }
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultPosition(.center)
        .keyboardShortcut("q", modifiers: .command)
        .commands {
            // ⌘⇧R - Toggle Recording
            CommandGroup(replacing: .newItem) {
                Button("Start/Stop Recording") {
                    appState.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            // ⌘⇧P - Toggle Panel
            CommandGroup(after: .toolbar) {
                Button("Show/Hide Panel") {
                    appState.togglePanel()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            
            // ⌘⇧H - Open History
            CommandGroup(after: .sidebar) {
                Button("Open History") {
                    appState.navigateToHistory()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            // ⌘, - Open Settings (native Settings scene)
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct OnboardingContainerView: View {
    @Binding var isPresented: Bool
    @Binding var hasCompletedOnboarding: Bool
    
    var body: some View {
        OnboardingView(isPresented: $isPresented)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationView {
            Sidebar()
                .frame(minWidth: 250)
            
            ContentArea(mode: appState.workspaceMode)
        }
        .navigationViewStyle(.columns)
    }
}

struct Sidebar: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: Session?
    
    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return appState.sessions
        }
        return appState.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            if appState.recordingState != .idle {
                Section("Recording Now") {
                    RecordingRow()
                }
            }
            
            Section("Sessions") {
                ForEach(filteredSessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        SessionListRow(session: session)
                    }
                    .contextMenu {
                        Button("Export") {
                            appState.exportSession(session)
                        }
                        Button("Delete", role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .focusable()
        .keyboardShortcut("f", modifiers: .command)
        .navigationTitle("EchoPanel")
        .sheet(isPresented: $showDeleteConfirmation) {
            if let session = sessionToDelete {
                DeleteConfirmationDialog(
                    session: session,
                    isPresented: $showDeleteConfirmation,
                    onDelete: {
                        appState.deleteSession(session)
                        sessionToDelete = nil
                    }
                )
                .frame(width: 400, height: 280)
            }
        }
        .sheet(isPresented: $appState.showExportDialog) {
            if let session = appState.selectedExportSession {
                ExportDialog(
                    session: session,
                    isPresented: $appState.showExportDialog
                )
            }
        }
    }
}

struct RecordingRow: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text("Recording...")
                    .font(.headline)
                
                if case .recording(let duration) = appState.recordingState {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .paused(let duration) = appState.recordingState {
                    Text("Paused: \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if case .recording = appState.recordingState {
                    Button(action: { appState.pauseRecording() }) {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if case .paused = appState.recordingState {
                    Button(action: { appState.resumeRecording() }) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button(action: { appState.stopRecording() }) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct SessionListRow: View {
    let session: Session
    
    var body: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.accentColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                
                HStack(spacing: 6) {
                    Text(session.formattedDuration)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(session.formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ContentArea: View {
    @EnvironmentObject private var appState: AppState
    let mode: AppState.WorkspaceMode
    
    var body: some View {
        Group {
            switch mode {
            case .dashboard:
                DashboardView()
            case .flowStudio:
                FlowStudioView()
            case .history:
                HistoryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome header
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Welcome to EchoPanel")
                        .font(.title2.weight(.semibold))
                    
                    if appState.sessions.isEmpty {
                        Text("Start your first recording to see it here")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select a session from the sidebar, or explore Flow Studio")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 40)
                
                // Quick actions
                if !appState.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Sessions")
                            .font(.headline)
                        
                        ForEach(appState.sessions.prefix(3)) { session in
                            NavigationLink(destination: SessionDetailView(session: session)) {
                                QuickSessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: 600, alignment: .leading)
                }
                
                // Flow Studio teaser
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try Flow Studio")
                        .font(.headline)
                    
                    Text("Explore polished meeting UX with mock scenarios")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    NavigationLink(destination: FlowStudioView()) {
                        Label("Open Flow Studio", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .frame(maxWidth: 600, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickSessionRow: View {
    let session: Session
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                
                HStack(spacing: 12) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.formattedDate, systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct RecordButton: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack(spacing: 6) {
                Image(systemName: recordIcon)
                Text(recordLabel)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(tintColor)
    }
    
    private var recordIcon: String {
        switch appState.recordingState {
        case .idle:
            return "record.circle"
        case .recording:
            return "stop.fill"
        case .paused:
            return "play.fill"
        case .error:
            return "exclamationmark.circle"
        }
    }
    
    private var recordLabel: String {
        switch appState.recordingState {
        case .idle:
            return "Record"
        case .recording:
            return "Stop"
        case .paused:
            return "Resume"
        case .error:
            return "Retry"
        }
    }
    
    private var tintColor: Color {
        switch appState.recordingState {
        case .idle:
            return .accentColor
        case .recording, .error:
            return .red
        case .paused:
            return .orange
        }
    }
}

struct ExportButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var showExportSheet = false
    
    var body: some View {
        Button(action: { showExportSheet = true }) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showExportSheet) {
            if let session = appState.sessions.first {
                ExportDialog(session: session, isPresented: $showExportSheet)
            }
        }
    }
}

struct SettingsButton: View {
    var body: some View {
        Button(action: {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }) {
            Image(systemName: "gear")
        }
        .buttonStyle(.bordered)
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    @State private var selectedTab = 0
    @State private var showExportSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.title2.weight(.semibold))
                    
                    HStack(spacing: 12) {
                        Label(session.formattedDuration, systemImage: "clock")
                        Label(session.formattedDate, systemImage: "calendar")
                        
                        if !session.highlights.isEmpty {
                            Label("\(session.highlights.count) highlights", systemImage: "sparkles")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { showExportSheet = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Summary").tag(0)
                Text("Transcript").tag(1)
                Text("Highlights").tag(2)
                Text("People").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    SummaryView(session: session, summaryText: sessionTitleSummary, people: MockData.people(from: session.transcript))
                case 1:
                    TranscriptTabView(transcript: session.transcript)
                case 2:
                    HighlightsTabView(highlights: session.highlights)
                case 3:
                    PeopleTabView(people: MockData.people(from: session.transcript))
                default:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportDialog(session: session, isPresented: $showExportSheet)
        }
    }
    
    private var sessionTitleSummary: String {
        "Session captured with EchoPanel. Review transcript, highlights, and action items below."
    }
}

struct SummaryView: View {
    let session: Session
    let summaryText: String
    let people: [Person]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI Summary
                VStack(alignment: .leading, spacing: 12) {
                    Label("Summary", systemImage: "text.alignleft")
                        .font(.headline)
                    
                    Text(summaryText)
                        .font(.body)
                        .lineSpacing(4)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // Stats
                HStack(spacing: 16) {
                    StatCard(
                        icon: "checkmark.circle",
                        value: "\(session.transcript.compactMap { $0.actionItem }.count)",
                        label: "Action Items"
                    )
                    
                    StatCard(
                        icon: "star",
                        value: "\(session.highlights.filter { $0.type == .decision }.count)",
                        label: "Decisions"
                    )
                    
                    StatCard(
                        icon: "person.3",
                        value: "\(people.count)",
                        label: "Participants"
                    )
                    
                    StatCard(
                        icon: "text.bubble",
                        value: "\(session.transcript.count)",
                        label: "Messages"
                    )
                }
                
                // Action items
                let actions = session.transcript.compactMap { $0.actionItem }
                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Action Items", systemImage: "bolt")
                            .font(.headline)
                        
                        ForEach(actions) { action in
                            HStack {
                                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundStyle(action.isCompleted ? .green : .secondary)
                                Text(action.task)
                                Spacer()
                                Text(action.assignee)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding()
            .frame(maxWidth: 800, alignment: .leading)
        }
    }
}

struct StatBox: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2.weight(.semibold))
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct TranscriptTabView: View {
    let transcript: [TranscriptItem]
    
    var body: some View {
        if transcript.isEmpty {
            EmptyStateView(
                icon: "text.bubble",
                title: "No Transcript",
                subtitle: "Start recording to see live transcript"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(transcript) { item in
                        TranscriptCard(item: item)
                    }
                }
                .padding()
            }
        }
    }
}

struct HighlightsTabView: View {
    let highlights: [Highlight]
    
    var body: some View {
        if highlights.isEmpty {
            EmptyStateView(
                icon: "sparkles",
                title: "No Highlights",
                subtitle: "Highlights will appear as the conversation progresses"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(highlights) { highlight in
                        HighlightCard(highlight: highlight)
                    }
                }
                .padding()
            }
        }
    }
}

struct PeopleTabView: View {
    let people: [Person]
    
    var body: some View {
        if people.isEmpty {
            EmptyStateView(
                icon: "person.3",
                title: "No Participants",
                subtitle: "Participants will appear as they're detected"
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(people) { person in
                        PersonCard(person: person)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - WorkspaceMode moved to AppState.swift
