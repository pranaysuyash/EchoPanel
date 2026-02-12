import SwiftUI

struct SidePanelView: View {
    @ObservedObject var appState: AppState

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
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Status: \(appState.streamStatus.rawValue)\(appState.statusMessage.isEmpty ? "" : " - \(appState.statusMessage)")")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.sessionState == .listening ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(appState.sessionState == .listening ? "Listening" : "Idle")
                .font(.footnote)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.black.opacity(0.05))
        .cornerRadius(12)
    }

    private var transcriptLane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.transcript) { segment in
                        TranscriptRow(segment: segment)
                    }
                    if appState.transcript.isEmpty {
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
            Text("Cards")
                .font(.headline)
            GroupBox(label: Text("Actions")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.actions) { item in
                        Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                            .font(.footnote)
                    }
                    if appState.actions.isEmpty {
                        Text("No actions yet")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            GroupBox(label: Text("Decisions")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.decisions) { item in
                        Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                            .font(.footnote)
                    }
                    if appState.decisions.isEmpty {
                        Text("No decisions yet")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            GroupBox(label: Text("Risks")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.risks) { item in
                        Text("• \(item.text) (\(formatConfidence(item.confidence)))")
                            .font(.footnote)
                    }
                    if appState.risks.isEmpty {
                        Text("No risks yet")
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
            Text("Entities")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.entities) { entity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entity.name) · \(entity.type)")
                                .font(.footnote)
                            Text("Last seen \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if appState.entities.isEmpty {
                        Text("No entities yet")
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio quality: \(appState.audioQuality.rawValue)")
                    .font(.footnote)
                Text("Session time: \(formatElapsed(appState.elapsedTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Copy Markdown") {
                // TODO: implement clipboard export
            }
            .keyboardShortcut("c", modifiers: [.command])
            Button("Export JSON") {
                // TODO: implement JSON export
            }
            Button("End Session") {
                appState.stopSession()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(segment.text)
                .font(.footnote)
                .foregroundColor(segment.isFinal ? .primary : .secondary)
            Text("\(formatTime(segment.t0)) - \(formatTime(segment.t1)) · \(formatConfidence(segment.confidence))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
