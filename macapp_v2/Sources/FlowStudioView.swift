import SwiftUI

struct FlowStudioView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedFlow: MockFlowTrack = .teamStandup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                hero
                flowCards
                journeyPreview
            }
            .padding(Spacing.xl)
        }
        .background(Color.appSecondaryBackground)
        .onAppear {
            selectedFlow = appState.activeFlow
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Flow Studio")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Explore polished meeting UX journeys with realistic mock states before backend lock-in.")
                .font(.appBody)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.md) {
                Label("Current: \(appState.activeFlow.title)", systemImage: appState.activeFlow.icon)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(appState.activeFlow.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

                Button("Load Selected Flow") {
                    appState.applyFlow(selectedFlow)
                }
                .buttonStyle(.borderedProminent)

                Button("Start Live Mock") {
                    appState.applyFlow(selectedFlow)
                    appState.startRecording()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.xl)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.7), selectedFlow.accent.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(Color.cardBorder, lineWidth: 0.7)
        )
    }

    private var flowCards: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Scenario Library")
                .font(.appHeadline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(MockFlowTrack.allCases) { flow in
                    Button {
                        selectedFlow = flow
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            HStack {
                                Image(systemName: flow.icon)
                                    .font(.title2)
                                    .foregroundStyle(flow.accent)

                                Spacer()

                                if selectedFlow == flow {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(flow.accent)
                                }
                            }

                            Text(flow.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(flow.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: Spacing.sm) {
                                token("Live")
                                token("Review")
                                token("Stress")
                            }
                        }
                        .padding(Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Material.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                                .stroke(selectedFlow == flow ? flow.accent : Color.cardBorder, lineWidth: selectedFlow == flow ? 1.4 : 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var journeyPreview: some View {
        let payload = MockData.payload(for: selectedFlow)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Journey Preview")
                .font(.appHeadline)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(payload.summary)
                    .font(.appBody)
                    .foregroundStyle(.primary)

                Divider()

                Text("Moments")
                    .font(.headline)
                ForEach(payload.transcript.prefix(4)) { item in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Circle()
                            .fill(selectedFlow.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.speaker)
                                .font(.subheadline.weight(.semibold))
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                }
            }
            .padding(Spacing.lg)
            .background(Material.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: 0.7)
            )
        }
    }

    private func token(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}
