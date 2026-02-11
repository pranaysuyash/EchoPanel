import Cocoa
import Combine
import Foundation
import SwiftUI

/// Global hot-key manager for broadcast operator controls.
/// Provides hands-free operation during live productions.
@MainActor
final class HotKeyManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isEnabled: Bool = false
    @Published var bindings: [HotKeyAction: HotKeyBinding] = [:]
    @Published var lastTriggeredAction: HotKeyAction?
    @Published var triggerTimestamp: Date?
    
    // MARK: - Hot Key Definitions
    
    enum HotKeyAction: String, CaseIterable, Identifiable {
        case startSession = "start_session"
        case stopSession = "stop_session"
        case insertMarker = "insert_marker"
        case toggleMute = "toggle_mute"
        case exportTranscript = "export_transcript"
        case togglePause = "toggle_pause"
        case emergencyFailover = "emergency_failover"
        case toggleRedundancy = "toggle_redundancy"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .startSession: return "Start Session"
            case .stopSession: return "Stop Session"
            case .insertMarker: return "Insert Marker"
            case .toggleMute: return "Toggle Mute"
            case .exportTranscript: return "Export Transcript"
            case .togglePause: return "Toggle Pause"
            case .emergencyFailover: return "Emergency Failover"
            case .toggleRedundancy: return "Toggle Redundancy"
            }
        }
        
        var defaultKey: KeyCombo {
            switch self {
            case .startSession: return KeyCombo(key: .f1, modifiers: [])
            case .stopSession: return KeyCombo(key: .f2, modifiers: [])
            case .insertMarker: return KeyCombo(key: .f3, modifiers: [])
            case .toggleMute: return KeyCombo(key: .f4, modifiers: [])
            case .exportTranscript: return KeyCombo(key: .f5, modifiers: [])
            case .togglePause: return KeyCombo(key: .f6, modifiers: [])
            case .emergencyFailover: return KeyCombo(key: .f12, modifiers: [.command])
            case .toggleRedundancy: return KeyCombo(key: .f7, modifiers: [])
            }
        }
        
        var description: String {
            switch self {
            case .startSession: return "Start a new capture session"
            case .stopSession: return "Stop the current session"
            case .insertMarker: return "Insert a timestamp marker in transcript"
            case .toggleMute: return "Mute/unmute audio capture"
            case .exportTranscript: return "Export current transcript"
            case .togglePause: return "Pause/resume capture"
            case .emergencyFailover: return "Force audio failover to backup"
            case .toggleRedundancy: return "Enable/disable dual-path redundancy"
            }
        }
    }
    
    // MARK: - Callbacks
    
    var onAction: ((HotKeyAction) -> Void)?
    
    // MARK: - Private Properties
    
    private var eventMonitor: Any?
    private var localMonitor: Any?
    private var isRegistered = false
    
    // MARK: - Initialization
    
    init() {
        loadBindings()
    }
    
    nonisolated deinit {
        // Cleanup is handled by stopMonitoring() when app closes
        // Cannot call MainActor-isolated methods from deinit
    }
    
    // MARK: - Public Methods
    
    /// Enable global hot-key monitoring
    func startMonitoring() {
        guard !isRegistered else { return }
        
        // Local monitor (when app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // Consume event
            }
            return event
        }
        
        // Global monitor (when app is in background)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyEvent(event)
        }
        
        isRegistered = true
        isEnabled = true
        
        // Request accessibility permission if needed
        requestAccessibilityPermission()
        
        NSLog("HotKeyManager: Global hot-keys enabled")
    }
    
    /// Disable hot-key monitoring
    func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRegistered = false
        isEnabled = false
        NSLog("HotKeyManager: Global hot-keys disabled")
    }
    
    /// Update binding for an action
    func setBinding(_ action: HotKeyAction, keyCombo: KeyCombo) -> Bool {
        // Check for conflicts
        if let conflict = bindings.first(where: { $0.value.keyCombo == keyCombo && $0.key != action }) {
            NSLog("HotKeyManager: Conflict detected - \(keyCombo.description) already bound to \(conflict.key.displayName)")
            return false
        }
        
        bindings[action] = HotKeyBinding(action: action, keyCombo: keyCombo, isEnabled: true)
        saveBindings()
        return true
    }
    
    /// Reset binding to default
    func resetBinding(_ action: HotKeyAction) {
        bindings[action] = HotKeyBinding(action: action, keyCombo: action.defaultKey, isEnabled: true)
        saveBindings()
    }
    
    /// Reset all bindings to defaults
    func resetAllBindings() {
        bindings = HotKeyAction.allCases.reduce(into: [:]) { dict, action in
            dict[action] = HotKeyBinding(action: action, keyCombo: action.defaultKey, isEnabled: true)
        }
        saveBindings()
    }
    
    /// Get binding for an action
    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        return bindings[action]
    }
    
    /// Check if accessibility permission is granted
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Request accessibility permission
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - Private Methods
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        
        let keyCombo = KeyCombo(from: event)
        
        // Find matching binding
        for (action, binding) in bindings {
            guard binding.isEnabled, binding.keyCombo == keyCombo else { continue }
            
            triggerAction(action)
            return true
        }
        
        return false
    }
    
    private func triggerAction(_ action: HotKeyAction) {
        lastTriggeredAction = action
        triggerTimestamp = Date()
        
        NSLog("HotKeyManager: Triggered '\(action.displayName)'")
        
        // Haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        
        // Notify delegate
        onAction?(action)
    }
    
    private func loadBindings() {
        // Load from UserDefaults or use defaults
        let defaults = HotKeyAction.allCases.reduce(into: [:]) { dict, action in
            dict[action] = HotKeyBinding(action: action, keyCombo: action.defaultKey, isEnabled: true)
        }
        
        // TODO: Load custom bindings from UserDefaults
        bindings = defaults
    }
    
    private func saveBindings() {
        // TODO: Save to UserDefaults
    }
}

// MARK: - Supporting Types

struct KeyCombo: Equatable, Codable, CustomStringConvertible {
    let key: KeyCode
    let modifiers: Set<KeyModifier>
    
    var description: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        parts.append(key.displayName)
        return parts.joined()
    }
    
    var isEmpty: Bool {
        return key == .none
    }
    
    init(key: KeyCode, modifiers: Set<KeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }
    
    init(from event: NSEvent) {
        var mods: Set<KeyModifier> = []
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        
        self.modifiers = mods
        self.key = KeyCode(from: event.keyCode)
    }
}

enum KeyModifier: String, Codable, CaseIterable {
    case command
    case option
    case control
    case shift
}

enum KeyCode: UInt16, Codable, CaseIterable {
    case none = 0
    case f1 = 122
    case f2 = 120
    case f3 = 99
    case f4 = 118
    case f5 = 96
    case f6 = 97
    case f7 = 98
    case f8 = 100
    case f9 = 101
    case f10 = 109
    case f11 = 103
    case f12 = 111
    case escape = 53
    case space = 49
    case return_key = 36
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .escape: return "Esc"
        case .space: return "Space"
        case .return_key: return "Return"
        }
    }
    
    init(from keyCode: UInt16) {
        self = KeyCode(rawValue: keyCode) ?? .none
    }
}

struct HotKeyBinding: Equatable {
    let action: HotKeyManager.HotKeyAction
    let keyCombo: KeyCombo
    var isEnabled: Bool
}

// MARK: - SwiftUI Views

/// Hot-key configuration view for Settings
struct HotKeySettingsView: View {
    @StateObject private var hotKeyManager = HotKeyManager()
    @State private var recordingAction: HotKeyManager.HotKeyAction?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Enable toggle
            Toggle("Enable Global Hot-Keys", isOn: $hotKeyManager.isEnabled)
                .onChange(of: hotKeyManager.isEnabled) { enabled in
                    if enabled {
                        hotKeyManager.startMonitoring()
                    } else {
                        hotKeyManager.stopMonitoring()
                    }
                }
            
            if !hotKeyManager.checkAccessibilityPermission() && hotKeyManager.isEnabled {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Accessibility permission required for global hot-keys")
                        .font(.caption)
                    Button("Open Settings") {
                        hotKeyManager.requestAccessibilityPermission()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
            }
            
            Divider()
            
            // Key binding list
            Text("Key Bindings")
                .font(.headline)
            
            ForEach(HotKeyManager.HotKeyAction.allCases) { action in
                HotKeyBindingRow(
                    action: action,
                    binding: hotKeyManager.binding(for: action),
                    isRecording: recordingAction == action,
                    onRecord: { recordingAction = action },
                    onReset: { hotKeyManager.resetBinding(action) }
                )
            }
            
            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    hotKeyManager.resetAllBindings()
                }
            }
        }
        .padding()
        .frame(width: 450)
    }
}

private struct HotKeyBindingRow: View {
    let action: HotKeyManager.HotKeyAction
    let binding: HotKeyBinding?
    let isRecording: Bool
    let onRecord: () -> Void
    let onReset: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(action.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let binding = binding {
                HStack(spacing: 8) {
                    Text(binding.keyCombo.description)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isRecording ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    
                    Button(isRecording ? "Cancel" : "Change") {
                        if isRecording {
                            // Cancel recording
                        } else {
                            onRecord()
                        }
                    }
                    .font(.caption)
                    
                    Button("Reset") {
                        onReset()
                    }
                    .font(.caption)
                    .disabled(binding.keyCombo == action.defaultKey)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Floating hot-key help overlay
struct HotKeyHelpOverlay: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button("×") {
                    isVisible = false
                }
                .buttonStyle(PlainButtonStyle())
                .font(.title2)
            }
            
            Divider()
            
            HotKeyHelpRow(keys: "F1", description: "Start session")
            HotKeyHelpRow(keys: "F2", description: "Stop session")
            HotKeyHelpRow(keys: "F3", description: "Insert marker")
            HotKeyHelpRow(keys: "F4", description: "Toggle mute")
            HotKeyHelpRow(keys: "F5", description: "Export transcript")
            HotKeyHelpRow(keys: "F6", description: "Pause/Resume")
            HotKeyHelpRow(keys: "F7", description: "Toggle redundancy")
            HotKeyHelpRow(keys: "⌘F12", description: "Emergency failover")
            
            Text("Works even when app is in background")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding()
        .frame(width: 280)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

private struct HotKeyHelpRow: View {
    let keys: String
    let description: String
    
    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 60, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HotKeySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        HotKeySettingsView()
    }
}

struct HotKeyHelpOverlay_Previews: PreviewProvider {
    static var previews: some View {
        HotKeyHelpOverlay(isVisible: .constant(true))
    }
}
#endif
