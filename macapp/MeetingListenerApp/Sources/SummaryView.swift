import SwiftUI

struct SummaryView: View {
    @ObservedObject var appState: AppState

    @State private var selectedTab: Tab = .markdown
    @Environment(\.openWindow) private var openWindow

    enum Tab: String, CaseIterable, Identifiable {
        case markdown = "Markdown"
        case details = "Details"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let banner = statusBanner {
                banner
                    .padding(.horizontal, 12)
            }

            Picker("View", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            Group {
                switch selectedTab {
                case .markdown:
                    markdownPane
                case .details:
                    detailsPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(12)
        .frame(minWidth: 780, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Summary")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var subtitle: String {
        let transcriptCount = appState.transcriptSegments.filter { $0.isFinal }.count
        let actionsCount = appState.actions.count
        let decisionsCount = appState.decisions.count
        let risksCount = appState.risks.count
        return "\(transcriptCount) transcript lines · \(actionsCount) actions · \(decisionsCount) decisions · \(risksCount) risks"
    }

    private var statusBanner: AnyView? {
        switch appState.finalizationOutcome {
        case .none:
            return AnyView(EmptyView())
        case .complete:
            return AnyView(
                BannerView(
                    tone: .success,
                    title: "Finalization complete",
                    message: "Your final summary is ready."
                )
            )
        case .incompleteTimeout, .incompleteError:
            return AnyView(
                BannerView(
                    tone: .warning,
                    title: "Finalization incomplete",
                    message: "The backend didn’t return a final summary. You can still export partial notes, or open Diagnostics."
                ) {
                    Button("Open Diagnostics") {
                        openWindow(id: "diagnostics")
                    }
                    .buttonStyle(.bordered)
                }
            )
        }
    }

    private var markdownPane: some View {
        GroupBox {
            ScrollView {
                Text(appState.finalSummaryMarkdown.isEmpty ? appState.renderLiveMarkdownForSummary() : appState.finalSummaryMarkdown)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .padding(.horizontal, 4)
    }

    private var detailsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Actions") {
                    if appState.actions.isEmpty {
                        Text("No actions detected.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.actions) { item in
                                Text("• \(item.text)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                GroupBox("Decisions") {
                    if appState.decisions.isEmpty {
                        Text("No decisions detected.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.decisions) { item in
                                Text("• \(item.text)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                GroupBox("Risks") {
                    if appState.risks.isEmpty {
                        Text("No risks detected.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.risks) { item in
                                Text("• \(item.text)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                GroupBox("Entities") {
                    if appState.entities.isEmpty {
                        Text("No entities detected.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.entities) { entity in
                                Text("• \(entity.name) (\(entity.type))")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(4)
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            Button {
                appState.copyMarkdownToClipboard()
            } label: {
                Label("Copy Markdown", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                appState.exportMarkdown()
            } label: {
                Label("Export Markdown", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)

            Button {
                appState.exportJSON()
            } label: {
                Label("Export JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }
}

private struct BannerView<Actions: View>: View {
    enum Tone {
        case success
        case warning
        case error
    }

    let tone: Tone
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(tone: Tone, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.tone = tone
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                actions
            }
            Spacer()
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch tone {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.10)
        case .error: return Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .success: return Color.green.opacity(0.18)
        case .warning: return Color.orange.opacity(0.22)
        case .error: return Color.red.opacity(0.22)
        }
    }
}
