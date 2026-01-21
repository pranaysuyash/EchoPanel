import SwiftUI

@main
struct MeetingListenerApp: App {
    @StateObject private var appState = AppState()
    @State private var sidePanelController = SidePanelController()

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            labelContent
        }
        .menuBarExtraStyle(.menu)
        Settings {
            EmptyView()
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session: \(appState.sessionState.rawValue.capitalized)")
                .font(.headline)
            Text("Timer: \(formatElapsed(appState.elapsedTime))")
                .font(.caption)
            Divider()
            Button(appState.sessionState == .listening ? "Stop Listening" : "Start Listening") {
                toggleSession()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    private var labelContent: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.sessionState == .listening ? "waveform.circle.fill" : "waveform.circle")
            Text(formatElapsed(appState.elapsedTime))
        }
    }

    private func toggleSession() {
        if appState.sessionState == .listening {
            appState.stopSession()
            sidePanelController.hide()
        } else {
            appState.startSession()
            sidePanelController.show(appState: appState)
        }
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
