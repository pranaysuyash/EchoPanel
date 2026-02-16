import SwiftUI

@main
struct EchoPanelV3App: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        // MARK: - Tier 1: Menu Bar Extra
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView(state: appState.recordingState)
        }
        
        // MARK: - Tier 2: Live Panel Window
        WindowGroup("Live Panel", id: "live-panel") {
            LivePanelView()
                .environmentObject(appState)
                .frame(minWidth: 400, idealWidth: 420, maxWidth: 600, 
                       minHeight: 500, idealHeight: 700)
        }
        .defaultPosition(.trailing)
        .windowResizability(.contentSize)
        
        // MARK: - Tier 3: Dashboard Window
        WindowGroup("EchoPanel", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultPosition(.center)
        
        // MARK: - Settings
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
