import AppKit
import SwiftUI

final class SidePanelController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SidePanelView>?

    func show(appState: AppState, onEndSession: @escaping () -> Void) {
        DispatchQueue.main.async {
            if self.panel == nil {
                let view = SidePanelView(appState: appState, onEndSession: onEndSession)
                let host = NSHostingController(rootView: view)
                self.hostingController = host

                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 960, height: 520),
                    styleMask: [.titled, .closable, .resizable, .utilityWindow],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "EchoPanel"
                panel.isFloatingPanel = true
                panel.level = .floating
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
                panel.contentViewController = host
                self.panel = panel
            } else if let hostingController = self.hostingController {
                hostingController.rootView = SidePanelView(appState: appState, onEndSession: onEndSession)
            }

            NSApp.activate(ignoringOtherApps: true)
            self.panel?.center()
            self.panel?.makeKeyAndOrderFront(nil)
            self.panel?.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
