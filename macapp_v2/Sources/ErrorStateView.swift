import SwiftUI

// MARK: - Error State View

struct ErrorStateView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    @EnvironmentObject private var appState: AppState
    
    init(
        error: AppError,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Error icon
            ZStack {
                Circle()
                    .fill(errorColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: error.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(errorColor)
            }
            
            // Error content
            VStack(spacing: Spacing.sm) {
                Text(error.title)
                    .font(.headline)
                
                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                
                if let details = error.details {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(Spacing.sm)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(CornerRadius.sm)
                }
            }
            
            // Actions
            HStack(spacing: Spacing.md) {
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if let onDismiss = onDismiss {
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorColor: Color {
        switch error.severity {
        case .info:
            return .statusInfo
        case .warning:
            return .statusWarning
        case .error:
            return .statusError
        case .critical:
            return .red
        }
    }
}

// MARK: - App Error Model

enum AppError: Identifiable {
    case asrError(String)
    case llmError(String)
    case microphonePermission
    case screenRecordingPermission
    case networkError
    case storageFull
    case unknown(String)
    
    var id: String {
        title
    }
    
    var title: String {
        switch self {
        case .asrError:
            return "Transcription Error"
        case .llmError:
            return "AI Processing Error"
        case .microphonePermission:
            return "Microphone Access Required"
        case .screenRecordingPermission:
            return "Screen Recording Required"
        case .networkError:
            return "Network Error"
        case .storageFull:
            return "Storage Full"
        case .unknown:
            return "Something Went Wrong"
        }
    }
    
    var message: String {
        switch self {
        case .asrError(let detail):
            return "Failed to transcribe audio: \(detail)"
        case .llmError(let detail):
            return "Failed to process with AI: \(detail)"
        case .microphonePermission:
            return "EchoPanel needs microphone access to record your meetings."
        case .screenRecordingPermission:
            return "EchoPanel needs screen recording permission to capture system audio."
        case .networkError:
            return "Unable to connect to the server. Check your internet connection."
        case .storageFull:
            return "Your disk is almost full. Free up space to continue recording."
        case .unknown(let detail):
            return "An unexpected error occurred: \(detail)"
        }
    }
    
    var details: String? {
        switch self {
        case .asrError(let detail), .llmError(let detail), .unknown(let detail):
            return detail
        default:
            return nil
        }
    }
    
    var icon: String {
        switch self {
        case .asrError:
            return "waveform.badge.exclamationmark"
        case .llmError:
            return "brain"
        case .microphonePermission:
            return "microphone.slash"
        case .screenRecordingPermission:
            return "rectangle.slash"
        case .networkError:
            return "wifi.exclamationmark"
        case .storageFull:
            return "internaldrive"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .microphonePermission, .screenRecordingPermission:
            return .warning
        case .networkError, .storageFull:
            return .error
        case .asrError, .llmError:
            return .error
        case .unknown:
            return .critical
        }
    }
    
    enum ErrorSeverity {
        case info
        case warning
        case error
        case critical
    }
}

// MARK: - Error Card (Compact)

struct ErrorCard: View {
    let error: AppError
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: error.icon)
                .font(.title2)
                .foregroundStyle(errorColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.subheadline.weight(.semibold))
                
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(errorColor.opacity(0.1))
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(errorColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var errorColor: Color {
        switch error.severity {
        case .info:
            return .statusInfo
        case .warning:
            return .statusWarning
        case .error:
            return .statusError
        case .critical:
            return .red
        }
    }
}

// MARK: - Error Banner (For inline display)

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusWarning)
            
            Text(message)
                .font(.caption)
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(Spacing.sm)
        .background(Color.statusWarning.opacity(0.15))
        .cornerRadius(CornerRadius.sm)
    }
}

// MARK: - Paused State View

struct PausedStateView: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.statusWarning.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.statusWarning)
            }
            
            VStack(spacing: Spacing.sm) {
                Text("Recording Paused")
                    .font(.title3.weight(.semibold))
                
                if case .paused(let duration) = appState.recordingState {
                    Text("Session paused at \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("Your conversation is still being captured. Resume when ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            HStack(spacing: Spacing.md) {
                Button(action: { appState.resumeRecording() }) {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: { appState.stopRecording() }) {
                    Label("End Session", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            
            Spacer()
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Permission Error Views

struct MicrophonePermissionErrorView: View {
    var body: some View {
        ErrorStateView(
            error: .microphonePermission,
            onRetry: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            },
            onDismiss: nil
        )
    }
}

struct ScreenRecordingPermissionErrorView: View {
    var body: some View {
        ErrorStateView(
            error: .screenRecordingPermission,
            onRetry: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            },
            onDismiss: nil
        )
    }
}
