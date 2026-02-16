import SwiftUI

struct ConfirmationDialog: View {
    let title: String
    let message: String
    let confirmText: String
    let cancelText: String
    let isDestructive: Bool
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: isDestructive ? "exclamationmark.triangle" : "questionmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(isDestructive ? .orange : .accentColor)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(cancelText) {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(confirmText) {
                    onConfirm()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? .red : .accentColor)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}

struct DeleteConfirmationDialog: View {
    let session: Session
    @Binding var isPresented: Bool
    let onDelete: () -> Void
    
    var body: some View {
        ConfirmationDialog(
            title: "Delete Session?",
            message: "\"\(session.title)\" will be permanently deleted. This action cannot be undone.",
            confirmText: "Delete",
            cancelText: "Cancel",
            isDestructive: true,
            isPresented: $isPresented,
            onConfirm: onDelete
        )
    }
}

struct ClearAllConfirmationDialog: View {
    @Binding var isPresented: Bool
    let sessionCount: Int
    let onClear: () -> Void
    
    var body: some View {
        ConfirmationDialog(
            title: "Clear All Sessions?",
            message: "This will permanently delete \(sessionCount) sessions and free up storage space. This action cannot be undone.",
            confirmText: "Clear All",
            cancelText: "Cancel",
            isDestructive: true,
            isPresented: $isPresented,
            onConfirm: onClear
        )
    }
}

struct PermissionRequestDialog: View {
    let permissionType: PermissionType
    @Binding var isPresented: Bool
    let onRequest: () -> Void
    
    enum PermissionType {
        case microphone
        case screenRecording
        case both
        
        var icon: String {
            switch self {
            case .microphone: return "microphone"
            case .screenRecording: return "rectangle.stack"
            case .both: return "shield"
            }
        }
        
        var title: String {
            switch self {
            case .microphone: return "Microphone Access Required"
            case .screenRecording: return "Screen Recording Required"
            case .both: return "Permissions Required"
            }
        }
        
        var message: String {
            switch self {
            case .microphone:
                return "EchoPanel needs access to your microphone to capture your voice during meetings."
            case .screenRecording:
                return "EchoPanel needs screen recording permission to capture system audio from video calls."
            case .both:
                return "EchoPanel needs microphone and screen recording permissions to capture meeting audio."
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: permissionType.icon)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            VStack(spacing: 8) {
                Text(permissionType.title)
                    .font(.headline)
                
                Text(permissionType.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Your audio never leaves your device", systemImage: "lock.shield")
                Label("No cloud processing or storage", systemImage: "icloud.slash")
                Label("You control all your data", systemImage: "person.crop.circle.badge.checkmark")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Not Now") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                
                Button("Open Settings") {
                    onRequest()
                    isPresented = false
                    
                    // Open System Settings
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 380)
    }
}
