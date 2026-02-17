import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuHeader()
            Divider().padding(.horizontal, 12)
            MenuActions()
            if !appState.sessions.isEmpty {
                Divider().padding(.horizontal, 12)
                MenuSessions()
            }
            Divider().padding(.horizontal, 12)
            MenuFooter()
        }
        .frame(width: 220)
    }
}

struct MenuHeader: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text("EchoPanel")
                    .font(.system(size: 13, weight: .bold))
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text("v3")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        switch appState.recordingState {
        case .idle: return .green
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
}

struct MenuActions: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 3) {
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.4) : Color.green.opacity(0.4))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isRecording ? .red : .green)
                    }
                    
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    Text("⌘⇧R")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button(action: openLivePanel) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    
                    Text("Show Panel")
                        .font(.system(size: 12))
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if appState.recordingState != .idle {
                Button(action: openLivePanel) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.4))
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                        
                        Text("Show Panel (Recording)")
                            .font(.system(size: 12))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if !appState.sessions.isEmpty && appState.recordingState == .idle {
                Button(action: {}) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.4))
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        
                        Text("Export Last Session")
                            .font(.system(size: 12))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var isRecording: Bool {
        if case .recording = appState.recordingState { return true }
        return false
    }
    
    private func toggleRecording() {
        switch appState.recordingState {
        case .idle: appState.startRecording()
        case .recording, .paused: appState.stopRecording()
        case .error: appState.startRecording()
        }
    }
    
    private func openLivePanel() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openLivePanel, object: nil)
    }
}

extension Notification.Name {
    static let openLivePanel = Notification.Name("openLivePanel")
    static let openDashboard = Notification.Name("openDashboard")
}

struct MenuSessions: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(appState.sessions.prefix(3)) { session in
                Button(action: {
                    appState.selectedSession = session
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .openDashboard, object: nil)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        Text(session.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(session.formattedDuration)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

struct MenuFooter: View {
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openDashboard, object: nil)
            }) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 22, height: 22)
                        
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    
                    Text("Dashboard")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Divider().frame(height: 16)
            
            Spacer()
            
            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 22, height: 22)
                        
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    Text("Settings")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Divider().frame(height: 16)
            
            Spacer()
            
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.4))
                            .frame(width: 22, height: 22)
                        
                        Image(systemName: "power")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    
                    Text("Quit")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
}

struct MenuBarIconView: View {
    let state: RecordingState
    
    var body: some View {
        switch state {
        case .idle:
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 20, height: 20)
                
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
        
        case .recording(let duration, _):
            HStack(spacing: 2) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        
        case .paused(let duration, _, _):
            HStack(spacing: 2) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.orange)
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
