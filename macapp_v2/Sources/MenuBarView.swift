import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showPanel = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("EchoPanel")
                        .font(.headline)
                    Text("v2.0.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Status
            HStack {
                StatusDot(status: statusForState(appState.recordingState))
                Text(statusText)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Main actions
            VStack(spacing: 0) {
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
                
                Button(action: { 
                    NSApp.activate(ignoringOtherApps: true)
                    // Use AppKit to find and show the panel window
                    if let window = NSApp.windows.first(where: { $0.title == "EchoPanel" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "panel")
                    }
                }) {
                    HStack {
                        Image(systemName: "rectangle.stack")
                        Text("Open Panel")
                        Spacer()
                        Text("⌘⇧P")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                if !appState.sessions.isEmpty {
                    Button(action: exportLast) {
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
            
            Divider()
            
            // Recent sessions
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
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                Text(session.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(session.formattedDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
            }
            
            // System actions
            VStack(spacing: 0) {
                Button(action: { openWindow(id: "history") }) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Session History")
                        Spacer()
                        Text("⌘⇧H")
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
                        Text("Settings…")
                        Spacer()
                        Text("⌘,")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                Button(action: quit) {
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
        .frame(width: 280)
    }
    
    private var isRecording: Bool {
        if case .recording = appState.recordingState {
            return true
        }
        return false
    }
    
    private var statusText: String {
        switch appState.recordingState {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }
    
    private func statusForState(_ state: RecordingState) -> StatusDot.Status {
        switch state {
        case .idle:
            return .idle
        case .recording:
            return .active
        case .paused:
            return .warning
        case .error:
            return .error
        }
    }
    
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
    
    private func exportLast() {
        // Mock export
        print("Exporting last session...")
    }
    
    private func openSession(_ session: Session) {
        openWindow(id: "panel")
    }
    
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    private func quit() {
        NSApp.terminate(nil)
    }
}
