import AppKit
import SwiftUI

final class SidePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SidePanelView>?
    private var onEndSession: (() -> Void)?

    func show(appState: AppState, onEndSession: @escaping () -> Void) {
        self.onEndSession = onEndSession
        
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
                panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
                panel.contentViewController = host
                panel.delegate = self // Set delegate to capture close event
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

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // High Severity Fix: Ensure session stops when window is closed via 'x'
        print("SidePanelController: Window closing, stopping session if active")
        self.onEndSession?()
    }
}
