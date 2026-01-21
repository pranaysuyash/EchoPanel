import AppKit
import SwiftUI

final class SidePanelController {
    private let panel: NSPanel

    init(appState: AppState) {
        let contentView = SidePanelView(appState: appState)
        let hostingView = NSHostingView(rootView: contentView)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Live Meeting Listener"
        panel.contentView = hostingView
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}
