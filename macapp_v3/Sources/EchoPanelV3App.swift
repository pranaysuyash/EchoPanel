import SwiftUI
import AppKit

/// Custom NSPanel that supports dragging from anywhere in the content area
final class DraggablePanel: NSPanel {
    override func awakeFromNib() {
        super.awakeFromNib()
        isMovable = true
        isMovableByWindowBackground = true
    }
}

@main
struct EchoPanelV3App: App {
    @StateObject private var appState = AppState()
    @State private var livePanelWindow: NSWindow?
    @State private var dashboardWindow: NSWindow?
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: .openLivePanel)) { _ in
                    openLivePanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
                    openDashboard()
                }
        } label: {
            MenuBarIconView(state: appState.recordingState)
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
    
    private func openLivePanel() {
        if let existing = livePanelWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Live Panel"
        panel.contentView = NSHostingView(rootView: LivePanelView().environmentObject(appState))
        
        // Floating panel behavior - stays above normal windows
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        
        // Critical: Stay visible over fullscreen apps (Zoom, Teams, etc.)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Don't steal keyboard focus from meeting apps when clicked
        panel.becomesKeyOnlyIfNeeded = true
        
        // Allow dragging from window background for easy repositioning
        panel.isMovableByWindowBackground = true
        
        panel.center()
        panel.setFrameAutosaveName("LivePanel")
        
        livePanelWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    private func openDashboard() {
        if let existing = dashboardWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoPanel Dashboard"
        window.contentView = NSHostingView(rootView: DashboardView().environmentObject(appState))
        window.center()
        window.setFrameAutosaveName("Dashboard")
        
        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
