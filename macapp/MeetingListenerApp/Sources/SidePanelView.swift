import SwiftUI

struct SidePanelView: View {
    @ObservedObject var appState: AppState
    let onEndSession: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            HStack(alignment: .top, spacing: 12) {
                transcriptLane
                cardsLane
                entitiesLane
            }
            Divider()
            controls
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Meeting Listener")
                    .font(.title2)
                    .fontWeight(.medium)
                Text(appState.statusLine)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                StatusPill(label: appState.sessionState == .listening ? "Listening" : "Idle",
                           color: appState.sessionState == .listening ? .green : .gray)
                StatusPill(label: "Audio \(appState.audioQuality.rawValue)", color: qualityColor(appState.audioQuality))
                Text(appState.timerText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    private var transcriptLane: some View {
        LaneCard(title: "Transcript") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.transcriptSegments) { segment in
                        TranscriptRow(segment: segment)
                            .transition(.opacity)
                    }
                    if appState.transcriptSegments.isEmpty {
                        Text("Waiting for speech")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.transcriptSegments)
    }

    private var cardsLane: some View {
        LaneCard(title: "Cards") {
            VStack(alignment: .leading, spacing: 12) {
                CardSection(title: "Actions") {
                    if appState.actions.isEmpty {
                        EmptyStateRow(text: "No actions yet")
                    } else {
                        ForEach(appState.actions) { item in
                            CardRow(
                                title: item.text,
                                meta: itemMeta(owner: item.owner, due: item.due, confidence: item.confidence)
                            )
                            .transition(.opacity)
                        }
                    }
                }
                CardSection(title: "Decisions") {
                    if appState.decisions.isEmpty {
                        EmptyStateRow(text: "No decisions yet")
                    } else {
                        ForEach(appState.decisions) { item in
                            CardRow(title: item.text, meta: confidenceMeta(item.confidence))
                                .transition(.opacity)
                        }
                    }
                }
                CardSection(title: "Risks") {
                    if appState.risks.isEmpty {
                        EmptyStateRow(text: "No risks yet")
                    } else {
                        ForEach(appState.risks) { item in
                            CardRow(title: item.text, meta: confidenceMeta(item.confidence))
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.actions)
        .animation(.easeInOut(duration: 0.2), value: appState.decisions)
        .animation(.easeInOut(duration: 0.2), value: appState.risks)
    }

    private var entitiesLane: some View {
        LaneCard(title: "Entities") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if appState.entities.isEmpty {
                        EmptyStateRow(text: "No entities yet")
                    } else {
                        ForEach(appState.entities) { entity in
                            EntityRow(entity: entity)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.entities)
    }

    private var controls: some View {
        HStack {
            Button {
                appState.copyMarkdownToClipboard()
            } label: {
                Label("Copy Markdown", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command])

            Button {
                appState.exportJSON()
            } label: {
                Label("Export JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                appState.exportMarkdown()
            } label: {
                Label("Export Markdown", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Spacer()

            Button(role: .destructive) {
                onEndSession()
            } label: {
                Label("End Session", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func qualityColor(_ quality: AudioQuality) -> Color {
        switch quality {
        case .good:
            return .green
        case .ok:
            return .orange
        case .poor:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func itemMeta(owner: String?, due: String?, confidence: Double) -> String {
        var parts: [String] = []
        if let owner, !owner.isEmpty { parts.append("Owner: \(owner)") }
        if let due, !due.isEmpty { parts.append("Due: \(due)") }
        parts.append(confidenceMeta(confidence))
        return parts.joined(separator: " · ")
    }

    private func confidenceMeta(_ value: Double) -> String {
        "Confidence \(formatConfidence(value))"
    }
}

private struct LaneCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(formatTime(segment.t0))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.text)
                    .font(.footnote)
                    .foregroundColor(segment.isFinal ? .primary : .secondary)
                Text(formatConfidence(segment.confidence))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct CardRow: View {
    let title: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
            Text(meta)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct EntityRow: View {
    let entity: EntityItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entity.name)
                .font(.footnote)
            Text(entity.type.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            Spacer()
        }
        Text("Last seen \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))")
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct EmptyStateRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
