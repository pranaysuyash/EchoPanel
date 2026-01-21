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
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        Settings {
            EmptyView()
        }
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
            Divider()
            Button(appState.sessionState == .listening ? "Stop Listening" : "Start Listening") {
                toggleSession()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Export JSON") {
                appState.exportJSON()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export Markdown") {
                appState.exportMarkdown()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
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
            appState.startSession()
            sidePanelController.show(appState: appState) {
                appState.stopSession()
                sidePanelController.hide()
            }
        }
    }
}
