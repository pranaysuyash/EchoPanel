import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("EchoPanel")
                    .font(.title2.weight(.semibold))
                
                Text("Version 2.0.0 (Build 2000)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Text("Capture, transcribe, and understand your meetings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            VStack(spacing: 4) {
                Text("© 2025 EchoPanel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://echopanel.app")!)
                    Link("Privacy Policy", destination: URL(string: "https://echopanel.app/privacy")!)
                    Link("Support", destination: URL(string: "https://echopanel.app/support")!)
                }
                .font(.caption)
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                AcknowledgementItem(
                    icon: "apple.logo",
                    name: "SwiftUI",
                    description: "Native macOS UI"
                )
                
                AcknowledgementItem(
                    icon: "cpu",
                    name: "On-Device AI",
                    description: "Privacy-first processing"
                )
                
                AcknowledgementItem(
                    icon: "lock.shield",
                    name: "Secure Storage",
                    description: "Your data stays local"
                )
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

struct AcknowledgementItem: View {
    let icon: String
    let name: String
    let description: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text(name)
                .font(.caption.weight(.semibold))
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
