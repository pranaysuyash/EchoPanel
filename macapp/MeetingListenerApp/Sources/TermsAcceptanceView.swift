import SwiftUI

struct TermsAcceptanceView: View {
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms = false
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Welcome to EchoPanel")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Privacy-focused meeting transcription")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Your data stays on your Mac")
                            .font(.body)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("No tracking, no ads, no data selling")
                            .font(.body)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Built by a solo developer who cares about privacy")
                            .font(.body)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                Text("By using EchoPanel, you agree to our:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                HStack(spacing: 16) {
                    Button("Privacy Policy") {
                        if let url = URL(string: "https://echopanel.app/privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)

                    Button("Terms of Service") {
                        if let url = URL(string: "https://echopanel.app/terms") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Divider()

                Text("EchoPanel is designed with privacy as the foundation. Your recordings and transcripts are stored locally on your Mac, and you have complete control over your data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button("I Agree & Continue") {
                hasAcceptedTerms = true
                onAccept()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .help("Accept the terms and start using EchoPanel")

            Text("By continuing, you agree to our Privacy Policy and Terms of Service.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(width: 500, height: 400)
    }
}

#Preview {
    TermsAcceptanceView {
        print("Terms accepted")
    }
}