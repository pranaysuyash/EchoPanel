import SwiftUI

struct SidePanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 16) {
                transcriptLane
                cardsLane
                entitiesLane
            }
            footer
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 520)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Meeting Listener")
                    .font(.headline)
                Text(appState.statusLine)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("Audio: \(appState.audioQuality)")
                .font(.subheadline)
            Divider()
                .frame(height: 24)
            Text(timerText)
                .font(.subheadline)
                .monospacedDigit()
        }
    }

    private var transcriptLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.transcriptSegments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(timestamp(for: segment.t0))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(segment.text)
                                .font(segment.isPartial ? .callout : .body)
                                .foregroundColor(segment.isPartial ? .secondary : .primary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardsLane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)
            cardList(appState.actions.map { item in
                CardRow(text: item.text, meta: itemMeta(item.owner, item.due, item.confidence))
            })
            Text("Decisions")
                .font(.headline)
            cardList(appState.decisions.map { item in
                CardRow(text: item.text, meta: confidenceMeta(item.confidence))
            })
            Text("Risks")
                .font(.headline)
            cardList(appState.risks.map { item in
                CardRow(text: item.text, meta: confidenceMeta(item.confidence))
            })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entitiesLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entities")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.entities) { entity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entity.name)
                                .font(.body)
                            Text("\(entity.type) · Last seen \(timestamp(for: entity.lastSeen)) · \(confidenceMeta(entity.confidence))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("Copy Markdown") {
                // TODO: Implement copy action.
            }
            Button("Export JSON") {
                // TODO: Implement export action.
            }
            Spacer()
            Button("End Session") {
                appState.stopSession()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var timerText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var elapsedSeconds: Int {
        appState.elapsedSeconds
    }

    private func timestamp(for seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func cardList(_ rows: [CardRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No items yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(rows) { row in
                    row
                }
            }
        }
    }

    private func itemMeta(_ owner: String?, _ due: String?, _ confidence: Double) -> String {
        var parts: [String] = []
        if let owner {
            parts.append("Owner: \(owner)")
        }
        if let due {
            parts.append("Due: \(due)")
        }
        parts.append(confidenceMeta(confidence))
        return parts.joined(separator: " · ")
    }

    private func confidenceMeta(_ confidence: Double) -> String {
        String(format: "Confidence %.0f%%", confidence * 100)
    }
}

struct CardRow: View, Identifiable {
    let id = UUID()
    let text: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.body)
            Text(meta)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
