import SwiftUI

struct ExportDialog: View {
    let session: Session
    @Binding var isPresented: Bool
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var includeTranscript = true
    @State private var includeHighlights = true
    @State private var includeActionItems = true
    @State private var isExporting = false
    @State private var showSuccess = false
    
    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case json = "JSON"
        case text = "Plain Text"
        
        var icon: String {
            switch self {
            case .markdown: return "doc.text"
            case .json: return "curlybraces"
            case .text: return "doc.plaintext"
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
                } else {
                    Button(action: exportSession) {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 560)
    }
    
    private var formatDescription: String {
        switch selectedFormat {
        case .markdown:
            return "Beautifully formatted document with headers, lists, and code blocks. Perfect for sharing."
        case .json:
            return "Machine-readable format with complete metadata. Ideal for integrations and backups."
        case .text:
            return "Simple plain text without formatting. Compatible with any text editor."
        }
    }
    
    private var exportPreview: String {
        var preview = "# \(session.title)\n"
        preview += "Duration: \(session.formattedDuration) | Date: \(session.formattedDate)\n\n"
        
        if includeHighlights && !session.highlights.isEmpty {
            preview += "## Highlights\n"
            for highlight in session.highlights.prefix(2) {
                preview += "- \(highlight.content)\n"
            }
            preview += "\n"
        }
        
        if includeActionItems {
            let actions = session.transcript.compactMap { $0.actionItem }
            if !actions.isEmpty {
                preview += "## Action Items\n"
                for action in actions.prefix(2) {
                    preview += "- [ ] \(action.assignee): \(action.task)\n"
                }
                preview += "\n"
            }
        }
        
        if includeTranscript && !session.transcript.isEmpty {
            preview += "## Transcript\n"
            for item in session.transcript.prefix(3) {
                preview += "**\(item.speaker)**: \(item.text)\n\n"
            }
        }
        
        return preview
    }
    
    private func exportSession() {
        isExporting = true
        
        // Simulate export delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isExporting = false
            showSuccess = true
            
            // Close after showing success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isPresented = false
            }
        }
    }
}

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
