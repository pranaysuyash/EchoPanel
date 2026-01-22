import SwiftUI

/// First-run Onboarding Wizard for EchoPanel
/// Guides users through permissions and setup before first session.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep: OnboardingStep = .welcome
    @Binding var isPresented: Bool
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case permissions
        case sourceSelection
        case diarization // B4 Fix
        case ready
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .sourceSelection:
                    sourceSelectionStep
                case .diarization:
                    diarizationStep
                case .ready:
                    readyStep
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            // Navigation buttons
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation { previousStep() }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep == .ready {
                    Button("Start Listening") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") {
                        withAnimation { nextStep() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Step Views
    
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Welcome to EchoPanel")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Your AI-powered meeting companion that captures, transcribes, and analyzes conversations in real-time.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
    
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("EchoPanel needs the following permissions to capture meeting audio:")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    description: "Required to capture system audio from meetings",
                    status: appState.screenRecordingPermission == .authorized ? .granted : .notGranted,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Optional: Capture your voice in addition to meeting audio",
                    status: appState.microphonePermission == .authorized ? .granted : .optional,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(.top, 8)
            
            Text("Click 'Open Settings' and add EchoPanel to the allowed apps.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Gap reduction: Self-test button (plays sound)
            Button {
                NSSound.beep()
            } label: {
                Label("Test Audio System (Play Beep)", systemImage: "speaker.wave.3.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }
    
    private var sourceSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Source")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose which audio sources to capture:")
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                    SourceOptionRow(
                        source: source,
                        isSelected: appState.audioSource == source,
                        action: { appState.audioSource = source }
                    )
                }
            }
            .padding(.top, 8)
            
            Text("You can change this later from the main panel.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // B4 Fix: Diarization Step
    private var diarizationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speaker Labels (Optional)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("To identify who is speaking (Diarization), EchoPanel uses a model that requires a HuggingFace User Access Token due to license restrictions.")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("HuggingFace Token (Read-only)")
                    .font(.caption)
                    .fontWeight(.medium)
                
                SecureField("hf_...", text: Binding(
                    get: { UserDefaults.standard.string(forKey: "hfToken") ?? "" },
                    set: { UserDefaults.standard.set($0, forKey: "hfToken") }
                ))
                .textFieldStyle(.roundedBorder)
                
                Link("Get a token ->", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                    .font(.caption)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text("You can leave this empty and set it later. Speaker labels won't be available without it.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Note: Speaker identification is performed after the meeting ends.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("EchoPanel is ready to capture and analyze your meetings. Click 'Start Listening' to begin your first session.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                    Text("Audio: \(appState.audioSource.rawValue)")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // H9 Fix: Server Status Feedback
            if appState.serverStatus == .error {
                VStack(spacing: 4) {
                    Label("Backend Error", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("The python server failed to start. Check if Python 3.10+ is installed.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            } else if !appState.isServerReady {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting server...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Navigation
    
    private func nextStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }
    
    private func previousStep() {
        if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        isPresented = false
        appState.startSession()
    }
}

// MARK: - Supporting Views

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void
    
    enum PermissionStatus {
        case granted, notGranted, optional
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    statusBadge
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if status != .granted {
                Button("Open Settings") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .notGranted:
            Label("Required", systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        case .optional:
            Label("Optional", systemImage: "minus.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct SourceOptionRow: View {
    let source: AppState.AudioSource
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.rawValue)
                        .fontWeight(.medium)
                    
                    Text(sourceDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private var sourceDescription: String {
        switch source {
        case .system:
            return "Capture audio from Zoom, Meet, Teams, etc."
        case .microphone:
            return "Capture your voice using the microphone"
        case .both:
            return "Capture both meeting audio and your voice"
        }
    }
}
