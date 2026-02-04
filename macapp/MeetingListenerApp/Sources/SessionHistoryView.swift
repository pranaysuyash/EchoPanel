import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SessionHistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var sessionStore: SessionStore

    @State private var sessions: [(id: String, date: Date, hasTranscript: Bool)] = []
    @State private var selectedSessionId: String?
    @State private var selectedSnapshot: [String: Any]?
    @State private var searchText: String = ""
    @State private var selectedTab: Tab = .summary
    @State private var showDeleteConfirmation: Bool = false

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case transcript = "Transcript"
        case json = "JSON"

        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionHistoryShouldRefresh)) { _ in
            reload()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            HStack(spacing: 6) {
                TextField("Search by date/time", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 12)

            List(selection: $selectedSessionId) {
                ForEach(filteredSessions, id: \.id) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.date, style: .date)
                                .font(.subheadline)
                            Text(session.date, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if session.id == sessionStore.recoverableSessionId {
                            Text("RECOVER")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .tag(session.id)
                }
            }
        }
        .frame(width: 260)
        .onChange(of: selectedSessionId) { newValue in
            guard let newValue else {
                selectedSnapshot = nil
                return
            }
            loadSnapshot(for: newValue)
            selectedTab = .summary
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
                if selectedSnapshot != nil {
                    Button {
                        exportSelectedMarkdown()
                    } label: {
                        Label("Export Markdown…", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportSelectedSnapshot()
                    } label: {
                        Label("Export JSON…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Picker("View", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            GroupBox {
                if let snapshot = selectedSnapshot {
                    switch selectedTab {
                    case .summary:
                        ScrollView {
                            Text(snapshotMarkdown(snapshot))
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                    case .transcript:
                        transcriptPane(snapshot)
                    case .json:
                        ScrollView {
                            Text(prettyJSON(snapshot))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Select a session to view details.")
                            .foregroundColor(.secondary)
                        if sessionStore.hasRecoverableSession {
                            Text("A recoverable session is available.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack {
                if sessionStore.hasRecoverableSession {
                    Button(role: .destructive) {
                        sessionStore.discardRecoverableSession()
                        reload()
                    } label: {
                        Label("Discard Recoverable Session", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(12)
        }
        .alert("Delete this session?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let selectedSessionId else { return }
                sessionStore.deleteSession(sessionId: selectedSessionId)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session snapshot and transcript from local storage. This can’t be undone.")
        }
    }

    private func reload() {
        sessions = sessionStore.listSessions()
        if selectedSessionId == nil {
            selectedSessionId = sessions.first?.id
        } else if let selectedSessionId, sessions.first(where: { $0.id == selectedSessionId }) == nil {
            self.selectedSessionId = sessions.first?.id
        }
    }

    private var filteredSessions: [(id: String, date: Date, hasTranscript: Bool)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }

        return sessions.filter { session in
            let dateString = dateFormatter.string(from: session.date)
            let timeString = timeFormatter.string(from: session.date)
            return dateString.localizedCaseInsensitiveContains(query)
                || timeString.localizedCaseInsensitiveContains(query)
                || "\(dateString) \(timeString)".localizedCaseInsensitiveContains(query)
        }
    }

    private func loadSnapshot(for sessionId: String) {
        selectedSnapshot = sessionStore.loadSnapshot(sessionId: sessionId)
    }

    private func prettyJSON(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func snapshotMarkdown(_ snapshot: [String: Any]) -> String {
        if let finalSummary = (snapshot["final_summary"] as? [String: Any])?["markdown"] as? String,
           !finalSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return finalSummary
        }
        return renderSnapshotMarkdown(snapshot)
    }

    private func transcriptPane(_ snapshot: [String: Any]) -> some View {
        let lines = snapshotTranscriptLines(snapshot)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if lines.isEmpty {
                    Text("No transcript found in this session snapshot.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(lines, id: \.id) { line in
                        Text("- [\(formatTime(line.t0))] **\(line.who)**: \(line.text)")
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(12)
        }
    }

    private struct SnapshotTranscriptLine {
        let id: Int
        let t0: TimeInterval
        let who: String
        let text: String
    }

    private func snapshotTranscriptLines(_ snapshot: [String: Any]) -> [SnapshotTranscriptLine] {
        guard let transcript = snapshot["transcript"] as? [[String: Any]] else { return [] }

        var lines: [SnapshotTranscriptLine] = []
        for (index, segment) in transcript.enumerated() {
            guard let isFinal = segment["is_final"] as? Bool, isFinal else { continue }
            guard let t0 = segment["t0"] as? TimeInterval else { continue }
            guard let text = segment["text"] as? String else { continue }

            let who: String
            if let speaker = segment["speaker"] as? String, !speaker.isEmpty {
                who = speaker
            } else if let source = segment["source"] as? String {
                who = (source == "mic" || source == "microphone") ? "You" : "System"
            } else {
                who = "Unknown"
            }

            lines.append(SnapshotTranscriptLine(id: index, t0: t0, who: who, text: text))
        }
        return lines
    }

    private func renderSnapshotMarkdown(_ snapshot: [String: Any]) -> String {
        var lines: [String] = []
        lines.append("# Notes")
        lines.append("")

        lines.append("## Transcript")
        for line in snapshotTranscriptLines(snapshot) {
            lines.append("- [\(formatTime(line.t0))] **\(line.who)**: \(line.text)")
        }
        lines.append("")

        lines.append("## Actions")
        if let actions = snapshot["actions"] as? [[String: Any]], !actions.isEmpty {
            for item in actions {
                if let text = item["text"] as? String {
                    lines.append("- \(text)")
                }
            }
        }
        lines.append("")

        lines.append("## Decisions")
        if let decisions = snapshot["decisions"] as? [[String: Any]], !decisions.isEmpty {
            for item in decisions {
                if let text = item["text"] as? String {
                    lines.append("- \(text)")
                }
            }
        }
        lines.append("")

        lines.append("## Risks")
        if let risks = snapshot["risks"] as? [[String: Any]], !risks.isEmpty {
            for item in risks {
                if let text = item["text"] as? String {
                    lines.append("- \(text)")
                }
            }
        }
        lines.append("")

        lines.append("## Entities")
        if let entities = snapshot["entities"] as? [[String: Any]], !entities.isEmpty {
            for item in entities {
                let name = item["name"] as? String ?? "Unknown"
                let type = item["type"] as? String ?? "unknown"
                lines.append("- \(name) (\(type))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func exportSelectedMarkdown() {
        guard let selectedSnapshot else { return }

        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: markdownFilenameExtension) {
            panel.allowedContentTypes = [markdownType]
        } else {
            panel.allowedContentTypes = [UTType.plainText]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "echopanel-notes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try snapshotMarkdown(selectedSnapshot).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("SessionHistory export markdown failed: %@", error.localizedDescription)
            }
        }
    }

    private func exportSelectedSnapshot() {
        guard let selectedSnapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "echopanel-session.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: selectedSnapshot, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url)
            } catch {
                NSLog("SessionHistory export failed: %@", error.localizedDescription)
            }
        }
    }

    private let markdownFilenameExtension = "md"

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
