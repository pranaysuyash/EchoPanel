import SwiftUI
import UniformTypeIdentifiers

struct ExportDialog: View {
    let session: Session
    @Binding var isPresented: Bool
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var includeTranscript = true
    @State private var includeHighlights = true
    @State private var includeActionItems = true
    @State private var isExporting = false
    @State private var showSuccess = false
    @State private var showFileExporter = false
    
    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case json = "JSON"
        case text = "Plain Text"
        case srt = "Subtitles (SRT)"
        
        var icon: String {
            switch self {
            case .markdown: return "doc.text"
            case .json: return "curlybraces"
            case .text: return "doc.plaintext"
            case .srt: return "captions.bubble"
            }
        }
        
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            case .text: return "txt"
            case .srt: return "srt"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Session")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Session info
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Label(session.formattedDuration, systemImage: "clock")
                                Label(session.formattedDate, systemImage: "calendar")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Format selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Format")
                            .font(.subheadline.weight(.semibold))
                        
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Label(format.rawValue, systemImage: format.icon)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(formatDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Content options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Include")
                            .font(.subheadline.weight(.semibold))
                        
                        Toggle("Full transcript", isOn: $includeTranscript)
                        Toggle("Highlights & insights", isOn: $includeHighlights)
                        Toggle("Action items", isOn: $includeActionItems)
                    }
                    
                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.subheadline.weight(.semibold))
                        
                        ScrollView {
                            Text(exportPreview)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 120)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if showSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Exported!")
                            .foregroundStyle(.green)
                    }
                    .font(.callout)
                } else if isExporting {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Exporting...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        isExporting = true
                        showFileExporter = true
                    }) {
                        Label("Export", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 560)
        .fileExporter(
            isPresented: $showFileExporter,
            document: ExportDocument(
                session: session,
                format: selectedFormat,
                includeTranscript: includeTranscript,
                includeHighlights: includeHighlights,
                includeActionItems: includeActionItems
            ),
            contentType: .data,
            defaultFilename: "\(session.title).\(selectedFormat.fileExtension)"
        ) { result in
            switch result {
            case .success:
                showSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isPresented = false
                }
            case .failure(let error):
                isExporting = false
                print("Export failed: \(error.localizedDescription)")
            }
        }
    }
    
    private var formatDescription: String {
        switch selectedFormat {
        case .markdown:
            return "Beautifully formatted document with headers, lists, and code blocks. Perfect for sharing."
        case .json:
            return "Machine-readable format with complete metadata. Ideal for integrations and backups."
        case .text:
            return "Simple plain text without formatting. Compatible with any text editor."
        case .srt:
            return "Subtitle format for video players. Includes timestamps for each segment."
        }
    }
    
    private var exportPreview: String {
        switch selectedFormat {
        case .markdown:
            return generateMarkdownPreview()
        case .json:
            return generateJSONPreview()
        case .text:
            return generateTextPreview()
        case .srt:
            return generateSRTPreview()
        }
    }
    
    private func generateMarkdownPreview() -> String {
        var preview = "# \(session.title)\n"
        preview += "Duration: \(session.formattedDuration) | Date: \(session.formattedDate)\n\n"
        
        if includeHighlights && !session.highlights.isEmpty {
            preview += "## Highlights\n"
            for highlight in session.highlights.prefix(3) {
                preview += "- **[\(highlight.type.displayName)]** \(highlight.content)\n"
            }
            preview += "\n"
        }
        
        if includeActionItems {
            let actions = session.transcript.compactMap { $0.actionItem }
            if !actions.isEmpty {
                preview += "## Action Items\n"
                for action in actions {
                    preview += "- [ ] **\(action.assignee)**: \(action.task)\n"
                }
                preview += "\n"
            }
        }
        
        if includeTranscript && !session.transcript.isEmpty {
            preview += "## Transcript\n\n"
            for item in session.transcript.prefix(5) {
                let time = formatTimestamp(item.timestamp)
                preview += "**[\(time)] \(item.speaker)**\n\(item.text)\n\n"
            }
            if session.transcript.count > 5 {
                preview += "_... and \(session.transcript.count - 5) more entries_\n"
            }
        }
        
        return preview
    }
    
    private func generateJSONPreview() -> String {
        let data: [String: Any] = [
            "title": session.title,
            "duration": session.formattedDuration,
            "date": session.formattedDate,
            "highlights": includeHighlights ? session.highlights.prefix(3).map { ["type": $0.type.displayName, "content": $0.content] } : [],
            "actionItems": includeActionItems ? session.transcript.compactMap { $0.actionItem }.prefix(3).map { ["assignee": $0.assignee, "task": $0.task] } : [],
            "transcript": includeTranscript ? session.transcript.prefix(5).map { ["speaker": $0.speaker, "text": $0.text, "timestamp": formatTimestamp($0.timestamp)] } : []
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return String(jsonString.prefix(500)) + (jsonString.count > 500 ? "\n..." : "")
        }
        return "{}"
    }
    
    private func generateTextPreview() -> String {
        var preview = "\(session.title)\n"
        preview += "Duration: \(session.formattedDuration) | Date: \(session.formattedDate)\n"
        preview += String(repeating: "=", count: 40) + "\n\n"
        
        if includeHighlights && !session.highlights.isEmpty {
            preview += "HIGHLIGHTS\n"
            for highlight in session.highlights.prefix(3) {
                preview += "• [\(highlight.type.displayName.uppercased())] \(highlight.content)\n"
            }
            preview += "\n"
        }
        
        if includeActionItems {
            let actions = session.transcript.compactMap { $0.actionItem }
            if !actions.isEmpty {
                preview += "ACTION ITEMS\n"
                for action in actions.prefix(3) {
                    preview += "☐ \(action.assignee): \(action.task)\n"
                }
                preview += "\n"
            }
        }
        
        if includeTranscript && !session.transcript.isEmpty {
            preview += "TRANSCRIPT\n"
            for item in session.transcript.prefix(5) {
                let time = formatTimestamp(item.timestamp)
                preview += "[\(time)] \(item.speaker): \(item.text)\n\n"
            }
        }
        
        return preview
    }
    
    private func generateSRTPreview() -> String {
        var srt = ""
        let items = session.transcript.prefix(5)
        
        for (index, item) in items.enumerated() {
            let startTime = formatSRTTime(item.timestamp)
            let endTime = formatSRTTime(item.timestamp.addingTimeInterval(30))
            
            srt += "\(index + 1)\n"
            srt += "\(startTime) --> \(endTime)\n"
            srt += "[\(item.speaker)]: \(item.text)\n\n"
        }
        
        if session.transcript.count > 5 {
            srt += "... and \(session.transcript.count - 5) more entries"
        }
        
        return srt
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatSRTTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss,SSS"
        return formatter.string(from: date)
    }
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.data] }
    
    let session: Session
    let format: ExportDialog.ExportFormat
    let includeTranscript: Bool
    let includeHighlights: Bool
    let includeActionItems: Bool
    
    init(session: Session, format: ExportDialog.ExportFormat, includeTranscript: Bool, includeHighlights: Bool, includeActionItems: Bool) {
        self.session = session
        self.format = format
        self.includeTranscript = includeTranscript
        self.includeHighlights = includeHighlights
        self.includeActionItems = includeActionItems
    }
    
    init(configuration: ReadConfiguration) throws {
        session = Session(id: UUID(), title: "Exported Session", startTime: Date(), duration: 0, transcript: [], highlights: [])
        format = .markdown
        includeTranscript = true
        includeHighlights = true
        includeActionItems = true
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let content: String
        switch format {
        case .markdown:
            content = generateMarkdown()
        case .json:
            content = generateJSON()
        case .text:
            content = generateText()
        case .srt:
            content = generateSRT()
        }
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
    
    private func generateMarkdown() -> String {
        var content = "# \(session.title)\n\n"
        content += "**Duration:** \(session.formattedDuration)\n"
        content += "**Date:** \(session.formattedDate)\n\n"
        
        if includeHighlights && !session.highlights.isEmpty {
            content += "## Highlights\n\n"
            for highlight in session.highlights {
                content += "- **[\(highlight.type.displayName)]** \(highlight.content)\n"
            }
            content += "\n"
        }
        
        if includeActionItems {
            let actions = session.transcript.compactMap { $0.actionItem }
            if !actions.isEmpty {
                content += "## Action Items\n\n"
                for action in actions {
                    let checkbox = action.isCompleted ? "[x]" : "[ ]"
                    content += "- \(checkbox) **\(action.assignee):** \(action.task)\n"
                }
                content += "\n"
            }
        }
        
        if includeTranscript && !session.transcript.isEmpty {
            content += "## Transcript\n\n"
            for item in session.transcript {
                let time = formatTimestamp(item.timestamp)
                content += "**[\(time)] \(item.speaker)**\n\(item.text)\n\n"
            }
        }
        
        content += "---\n*Exported from EchoPanel*"
        return content
    }
    
    private func generateJSON() -> String {
        var dict: [String: Any] = [
            "title": session.title,
            "duration": session.formattedDuration,
            "date": session.formattedDate,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]
        
        if includeHighlights {
            dict["highlights"] = session.highlights.map { highlight in
                [
                    "type": highlight.type.displayName,
                    "content": highlight.content,
                    "timestamp": ISO8601DateFormatter().string(from: highlight.timestamp)
                ]
            }
        }
        
        if includeActionItems {
            dict["actionItems"] = session.transcript.compactMap { $0.actionItem }.map { action in
                [
                    "assignee": action.assignee,
                    "task": action.task,
                    "completed": action.isCompleted
                ]
            }
        }
        
        if includeTranscript {
            dict["transcript"] = session.transcript.map { item in
                [
                    "speaker": item.speaker,
                    "text": item.text,
                    "timestamp": ISO8601DateFormatter().string(from: item.timestamp),
                    "pinned": item.isPinned
                ]
            }
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
    
    private func generateText() -> String {
        var content = "\(session.title)\n"
        content += String(repeating: "=", count: 50) + "\n\n"
        content += "Duration: \(session.formattedDuration)\n"
        content += "Date: \(session.formattedDate)\n\n"
        
        if includeHighlights && !session.highlights.isEmpty {
            content += "HIGHLIGHTS\n"
            content += String(repeating: "-", count: 30) + "\n"
            for highlight in session.highlights {
                content += "[\(highlight.type.displayName.uppercased())] \(highlight.content)\n"
            }
            content += "\n"
        }
        
        if includeActionItems {
            let actions = session.transcript.compactMap { $0.actionItem }
            if !actions.isEmpty {
                content += "ACTION ITEMS\n"
                content += String(repeating: "-", count: 30) + "\n"
                for action in actions {
                    let mark = action.isCompleted ? "✓" : "○"
                    content += "\(mark) \(action.assignee): \(action.task)\n"
                }
                content += "\n"
            }
        }
        
        if includeTranscript && !session.transcript.isEmpty {
            content += "TRANSCRIPT\n"
            content += String(repeating: "-", count: 30) + "\n"
            for item in session.transcript {
                let time = formatTimestamp(item.timestamp)
                content += "[\(time)] \(item.speaker):\n\(item.text)\n\n"
            }
        }
        
        return content
    }
    
    private func generateSRT() -> String {
        var srt = ""
        
        for (index, item) in session.transcript.enumerated() {
            let startTime = formatSRTTime(item.timestamp)
            let endTime = formatSRTTime(item.timestamp.addingTimeInterval(5))
            
            srt += "\(index + 1)\n"
            srt += "\(startTime) --> \(endTime)\n"
            srt += "[\(item.speaker)]: \(item.text)\n\n"
        }
        
        return srt
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatSRTTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss,SSS"
        return formatter.string(from: date)
    }
}

// MARK: - Batch Export Dialog

struct BatchExportDialog: View {
    @Binding var isPresented: Bool
    @State private var selectedSessions: Set<UUID> = []
    @State private var selectedFormat: ExportDialog.ExportFormat = .markdown
    @State private var isExporting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Multiple Sessions")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Select sessions to export:")
                    .font(.subheadline)
                
                // Session list
                List(MockData.sampleSessions, selection: $selectedSessions) { session in
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading) {
                            Text(session.title)
                            Text("\(session.formattedDate) · \(session.formattedDuration)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(session.id)
                }
                .frame(height: 200)
                .listStyle(.plain)
                
                // Format
                Picker("Format:", selection: $selectedFormat) {
                    ForEach(ExportDialog.ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("\(selectedSessions.count) sessions selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: exportSessions) {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Export \(selectedSessions.count) Sessions")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSessions.isEmpty || isExporting)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
    }
    
    private func exportSessions() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isExporting = false
            isPresented = false
        }
    }
}
