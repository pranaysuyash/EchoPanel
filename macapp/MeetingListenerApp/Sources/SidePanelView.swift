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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Meeting Listener")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(appState.statusLine)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Text("Audio: \(appState.audioQuality.rawValue)")
                    .font(.footnote)
                Text(appState.timerText)
                    .font(.footnote)
                    .monospacedDigit()
            }
        }
    }

    private var transcriptLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.transcriptSegments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTime(segment.t0))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.text)
                                    .font(.footnote)
                                    .foregroundColor(segment.isFinal ? .primary : .secondary)
                                Text("\(formatConfidence(segment.confidence))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.03))
        .cornerRadius(12)
    }

    private var cardsLane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cards").font(.headline)
            GroupBox(label: Text("Actions")) {
                VStack(alignment: .leading, spacing: 6) {
                    if appState.actions.isEmpty {
                        Text("No actions yet").font(.footnote).foregroundColor(.secondary)
                    } else {
                        ForEach(appState.actions) { item in
                            Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                                .font(.footnote)
                        }
                    }
                }
            }
            GroupBox(label: Text("Decisions")) {
                VStack(alignment: .leading, spacing: 6) {
                    if appState.decisions.isEmpty {
                        Text("No decisions yet").font(.footnote).foregroundColor(.secondary)
                    } else {
                        ForEach(appState.decisions) { item in
                            Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                                .font(.footnote)
                        }
                    }
                }
            }
            GroupBox(label: Text("Risks")) {
                VStack(alignment: .leading, spacing: 6) {
                    if appState.risks.isEmpty {
                        Text("No risks yet").font(.footnote).foregroundColor(.secondary)
                    } else {
                        ForEach(appState.risks) { item in
                            Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.03))
        .cornerRadius(12)
    }

    private var entitiesLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entities").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if appState.entities.isEmpty {
                        Text("No entities yet").font(.footnote).foregroundColor(.secondary)
                    } else {
                        ForEach(appState.entities) { entity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entity.name) · \(entity.type)")
                                    .font(.footnote)
                                Text("Last seen \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.03))
        .cornerRadius(12)
    }

    private var controls: some View {
        HStack {
            Button("Copy Markdown") {
                appState.copyMarkdownToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command])

            Spacer()

            Button("End session") {
                onEndSession()
            }
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
}

