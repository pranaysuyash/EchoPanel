import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Status
            statusSection
            
            Divider()
            
            // Main Actions
            actionsSection
            
            Divider()
            
            // Recent Sessions
            recentSessionsSection
            
            Divider()
            
            // System Actions
            systemActionsSection
        }
        .frame(width: 280)
    }
    
    // MARK: Header Section
    private var headerSection: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("EchoPanel")
                    .font(.headline)
                Text("v3.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: Status Section
    private var statusSection: some View {
        HStack {
            statusDot
            Text(statusText)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
    
    private var statusColor: Color {
        switch appState.recordingState {
        case .idle: return .gray
        case .recording: return .red
        case .paused: return .orange
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch appState.recordingState {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }
    
    // MARK: Actions Section
    private var actionsSection: some View {
        VStack(spacing: 0) {
            // Record/Stop Button
            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    Text(isRecording ? "End Session" : "Start Recording")
                    Spacer()
                    Text("⌘⇧R")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(isRecording ? Color.red.opacity(0.1) : Color.clear)
            
            // Show Panel Button
            if appState.recordingState != .idle {
                Button(action: showPanel) {
                    HStack {
                        Image(systemName: "rectangle.stack")
                        Text("Show Panel")
                        Spacer()
                        Text("⌘⇧S")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            
            // Export Last Session
            if !appState.sessions.isEmpty && appState.recordingState == .idle {
                Button(action: exportLastSession) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Last Session")
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var isRecording: Bool {
        if case .recording = appState.recordingState {
            return true
        }
        return false
    }
    
    // MARK: Recent Sessions Section
    @ViewBuilder
    private var recentSessionsSection: some View {
        if !appState.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                ForEach(appState.sessions.prefix(3)) { session in
                    Button(action: { openSession(session) }) {
                        HStack {
                            Image(systemName: "waveform.circle")
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.title)
                                    .lineLimit(1)
                                Text(session.formattedDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: System Actions Section
    private var systemActionsSection: some View {
        VStack(spacing: 0) {
            Button(action: openDashboard) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Open Dashboard")
                    Spacer()
                    Text("⌘⇧D")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            Divider()
                .padding(.horizontal)
            
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: Actions
    private func toggleRecording() {
        switch appState.recordingState {
        case .idle:
            appState.startRecording()
        case .recording, .paused:
            appState.stopRecording()
        case .error:
            appState.startRecording()
        }
    }
    
    private func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "live-panel")
    }
    
    private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "dashboard")
    }
    
    private func openSession(_ session: Session) {
        appState.selectedSession = session
        openDashboard()
    }
    
    private func exportLastSession() {
        // Trigger export for last session
    }
    
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Menu Bar Icon View
struct MenuBarIconView: View {
    let state: RecordingState
    
    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
        
        case .recording(let duration, _):
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        
        case .paused(let duration, _, _):
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 8))
                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
