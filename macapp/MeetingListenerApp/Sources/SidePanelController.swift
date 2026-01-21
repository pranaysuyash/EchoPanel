import AppKit
import SwiftUI

final class SidePanelController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SidePanelView>?

    func show(appState: AppState, onEndSession: @escaping () -> Void) {
        if panel == nil {
            let view = SidePanelView(appState: appState, onEndSession: onEndSession)
            let host = NSHostingController(rootView: view)
            hostingController = host

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 520),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "EchoPanel"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.contentViewController = host
            self.panel = panel
        } else if let hostingController {
            hostingController.rootView = SidePanelView(appState: appState, onEndSession: onEndSession)
        }

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

