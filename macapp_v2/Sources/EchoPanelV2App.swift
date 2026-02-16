import SwiftUI
import AppKit

@main
struct EchoPanelV2App: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("EchoPanel", id: "main") {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultPosition(.center)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationView {
            Sidebar()
                .frame(minWidth: 250)
            
            ContentArea()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                RecordButton()
                Spacer()
                ExportButton()
                SettingsButton()
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    
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
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .navigationTitle("EchoPanel")
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
                }
            }
            
            Spacer()
            
            Button(action: { appState.stopRecording() }) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
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
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Welcome to EchoPanel")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Select a session from the sidebar to view details, or start a new recording")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct RecordButton: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Button(action: {
            if appState.recordingState == .idle {
                appState.startRecording()
            } else {
                appState.stopRecording()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: appState.recordingState == .idle ? "record.circle" : "stop.fill")
                Text(appState.recordingState == .idle ? "Record" : "Stop")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.recordingState == .idle ? .accentColor : .red)
    }
}

struct ExportButton: View {
    var body: some View {
        Button(action: {}) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
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
    let session: Session
    @State private var selectedTab = 0
    
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
                    SummaryView(session: session)
                case 1:
                    TranscriptTabView(transcript: session.transcript)
                case 2:
                    HighlightsTabView(highlights: session.highlights)
                case 3:
                    PeopleTabView(people: MockData.samplePeople)
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct SummaryView: View {
    let session: Session
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI Summary
                VStack(alignment: .leading, spacing: 12) {
                    Label("AI Summary", systemImage: "brain")
                        .font(.headline)
                    
                    Text(MockData.sampleSummary)
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
                        value: "\(MockData.samplePeople.count)",
                        label: "Participants"
                    )
                    
                    StatCard(
                        icon: "text.bubble",
                        value: "\(session.transcript.count)",
                        label: "Messages"
                    )
                }
                
                // Quick actions
                VStack(alignment: .leading, spacing: 12) {
                    Label("Action Items", systemImage: "bolt")
                        .font(.headline)
                    
                    let actions = session.transcript.compactMap { $0.actionItem }
                    if actions.isEmpty {
                        Text("No action items found")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
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
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: 800, alignment: .leading)
        }
    }
}

struct TranscriptTabView: View {
    let transcript: [TranscriptItem]
    
    var body: some View {
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

struct HighlightsTabView: View {
    let highlights: [Highlight]
    
    var body: some View {
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

struct PeopleTabView: View {
    let people: [Person]
    
    var body: some View {
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
