import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    let totalSteps = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            
            // Content - switch based on current step
            Group {
                switch currentStep {
                case 0:
                    WelcomeStep()
                        .transition(.opacity)
                case 1:
                    TipsStep()
                        .transition(.opacity)
                case 2:
                    ReadyStep(isPresented: $isPresented)
                        .transition(.opacity)
                default:
                    EmptyView()
                }
            }
            .frame(height: 320)
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        hasCompletedOnboarding = true
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 420)
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 12) {
                Text("Welcome to EchoPanel")
                    .font(.title2.weight(.semibold))
                
                Text("Capture any meeting with one click. Get transcripts, action items, and highlights automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct TipsStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Quick Tips")
                .font(.title2.weight(.semibold))
            
            VStack(alignment: .leading, spacing: 20) {
                TipRow(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "Keyboard Shortcuts",
                    description: "Press ⌘⇧R anytime to start recording, even when the panel is closed"
                )
                
                TipRow(
                    icon: "pin",
                    iconColor: .orange,
                    title: "Pin Important Moments",
                    description: "Press 'P' during recording to mark key points for later review"
                )
                
                TipRow(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Automatic Highlights",
                    description: "EchoPanel extracts action items, decisions, and key people automatically"
                )
            }
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct TipRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReadyStep: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.title2.weight(.semibold))
                
                Text("Your first recording will ask for microphone and screen recording permissions. These are required to capture audio.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            VStack(spacing: 8) {
                Button("Open Panel") {
                    isPresented = false
                    appState.panelVisible = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Start Recording") {
                    isPresented = false
                    appState.startRecording()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
