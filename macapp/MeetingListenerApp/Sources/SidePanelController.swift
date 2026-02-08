import AppKit
import SwiftUI

final class SidePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SidePanelView>?
    private var onEndSession: (() -> Void)?
    private var currentMode: SidePanelView.ViewMode = .roll

    func show(appState: AppState, onEndSession: @escaping () -> Void) {
        self.onEndSession = onEndSession
        
        DispatchQueue.main.async {
            if self.panel == nil {
                let view = self.makeRootView(appState: appState, onEndSession: onEndSession)
                let host = NSHostingController(rootView: view)
                self.hostingController = host

                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
                    styleMask: [.titled, .closable, .resizable, .utilityWindow],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "EchoPanel"
                panel.isFloatingPanel = true
                panel.level = .floating
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.collectionBehavior = .moveToActiveSpace
                panel.contentViewController = host
                panel.delegate = self // Set delegate to capture close event
                panel.minSize = NSSize(width: 390, height: 620)
                self.panel = panel

                self.applyWindowLayout(for: self.currentMode, animated: false)
            } else if let hostingController = self.hostingController {
                hostingController.rootView = self.makeRootView(appState: appState, onEndSession: onEndSession)
            }

            // Force activation; MenuBarExtra apps can otherwise fail to bring panels forward.
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
        NSLog("SidePanelController: Window closing, stopping session if active")
        self.onEndSession?()
    }

    private func makeRootView(appState: AppState, onEndSession: @escaping () -> Void) -> SidePanelView {
        SidePanelView(
            appState: appState,
            onEndSession: onEndSession,
            onModeChange: { [weak self] mode in
                self?.applyWindowLayout(for: mode, animated: true)
            }
        )
    }

    private func applyWindowLayout(for mode: SidePanelView.ViewMode, animated: Bool) {
        guard let panel else { return }
        currentMode = mode

        let targetSize: NSSize
        let minSize: NSSize
        switch mode {
        case .roll:
            targetSize = NSSize(width: 460, height: 760)
            minSize = NSSize(width: 390, height: 620)
        case .compact:
            targetSize = NSSize(width: 360, height: 700)
            minSize = NSSize(width: 320, height: 560)
        case .full:
            targetSize = NSSize(width: 1120, height: 780)
            minSize = NSSize(width: 920, height: 640)
        }

        panel.minSize = minSize

        let oldFrame = panel.frame
        let centeredOrigin = NSPoint(
            x: oldFrame.midX - (targetSize.width / 2),
            y: oldFrame.midY - (targetSize.height / 2)
        )
        let newFrame = NSRect(origin: centeredOrigin, size: targetSize)
        panel.setFrame(newFrame, display: true, animate: animated)
    }
}
