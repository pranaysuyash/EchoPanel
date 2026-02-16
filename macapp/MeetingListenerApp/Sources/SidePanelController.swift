import AppKit
import SwiftUI

final class SidePanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SidePanelView>?
    private var onEndSession: (() -> Void)?
    private var currentMode: SidePanelView.ViewMode = .roll
    private var savedFrameByMode: [SidePanelView.ViewMode: NSRect] = [:]

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

                self.applyWindowLayout(for: self.currentMode, animated: false, forceTarget: true)
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

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        savedFrameByMode[currentMode] = panel.frame
    }

    private func makeRootView(appState: AppState, onEndSession: @escaping () -> Void) -> SidePanelView {
        SidePanelView(
            appState: appState,
            onEndSession: onEndSession,
            onModeChange: { [weak self] mode in
                self?.applyWindowLayout(for: mode, animated: true)
            },
            onAlwaysOnTopChange: { [weak self] isOn in
                self?.applyAlwaysOnTop(isOn)
            }
        )
    }

    private func applyAlwaysOnTop(_ enabled: Bool) {
        guard let panel else { return }
        panel.isFloatingPanel = enabled
        panel.level = enabled ? .floating : .normal
    }

    private func applyWindowLayout(for mode: SidePanelView.ViewMode, animated: Bool, forceTarget: Bool = false) {
        guard let panel else { return }
        savedFrameByMode[currentMode] = panel.frame
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
            minSize = NSSize(width: 720, height: 580)
        }

        panel.minSize = minSize

        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let preferredFrame = forceTarget ? nil : savedFrameByMode[mode]

        let desiredSize: NSSize = {
            let source = preferredFrame?.size ?? targetSize
            var width = max(source.width, minSize.width)
            var height = max(source.height, minSize.height)
            if let screenFrame {
                width = min(width, screenFrame.width)
                height = min(height, screenFrame.height)
            }
            return NSSize(width: width, height: height)
        }()

        let oldFrame = panel.frame
        var centeredOrigin = NSPoint(
            x: oldFrame.midX - (desiredSize.width / 2),
            y: oldFrame.midY - (desiredSize.height / 2)
        )
        if let screenFrame {
            centeredOrigin.x = max(screenFrame.minX, min(centeredOrigin.x, screenFrame.maxX - desiredSize.width))
            centeredOrigin.y = max(screenFrame.minY, min(centeredOrigin.y, screenFrame.maxY - desiredSize.height))
        }
        let newFrame = NSRect(origin: centeredOrigin, size: desiredSize)
        panel.setFrame(newFrame, display: true, animate: animated)
        savedFrameByMode[mode] = panel.frame
    }
}
