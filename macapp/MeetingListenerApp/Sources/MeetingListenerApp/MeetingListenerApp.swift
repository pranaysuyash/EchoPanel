import AppKit
import SwiftUI

@main
struct MeetingListenerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Toggle Listen") {
                    appDelegate.toggleListening()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Button("Copy Markdown") {
                    // TODO: Implement copy action.
                }
                .keyboardShortcut("C", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var statusItem: NSStatusItem?
    private var panelController: SidePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        panelController = SidePanelController(appState: appState)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "EchoPanel"
            button.action = #selector(statusItemTapped)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Listening", action: #selector(toggleListening), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Listening", action: #selector(stopListening), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func statusItemTapped() {
        toggleListening()
    }

    @objc func toggleListening() {
        if appState.listenerState == .listening {
            stopListening()
        } else {
            startListening()
        }
    }

    @objc private func startListening() {
        appState.startSession()
        appState.panelVisible = true
        panelController?.show()
    }

    @objc private func stopListening() {
        appState.stopSession()
        appState.panelVisible = false
        panelController?.hide()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
