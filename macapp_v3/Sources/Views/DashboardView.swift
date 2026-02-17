import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var showingShareSheet = false
    @State private var showingMOMGenerator = false
    @State private var showingCalendar = false
    
    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return appState.sessions
        }
        return appState.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.summary?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            sidebar
            detailView
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Calendar button
                Button(action: { showingCalendar = true }) {
                    Image(systemName: "calendar")
                }
                .help("Calendar")
                
                // MOM Generator
                Button(action: { showingMOMGenerator = true }) {
                    Image(systemName: "doc.text.fill")
                }
                .help("Generate Meeting Minutes")
                
                // Share
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
                
                // Export
                Button(action: { showingExportSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Export")
                
                Divider()
                
                // Record button
                RecordButton()
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet()
        }
        .sheet(isPresented: $showingMOMGenerator) {
            MOMGeneratorSheet()
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarView()
        }
    }
    
    // MARK: Sidebar
    private var sidebar: some View {
        List(selection: $appState.selectedSession) {
            if appState.recordingState != .idle {
                Section("Recording Now") {
                    if let current = appState.currentSession {
                        NavigationLink(value: current) {
                            RecordingRow(session: current)
                        }
                    }
                }
            }
            
            Section("Sessions") {
                ForEach(filteredSessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search sessions")
        .navigationTitle("EchoPanel")
        .frame(minWidth: 250)
    }
    
    // MARK: Detail View
    @ViewBuilder
    private var detailView: some View {
        if let session = appState.selectedSession {
            SessionDetailView(session: session, selectedTab: $selectedTab)
        } else {
            EmptyDashboardState()
        }
    }
}

// MARK: - Recording Row
struct RecordingRow: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    
    var body: some View {
        HStack {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text("Recording...")
                    .font(.headline)
                
                if case .recording(let duration, _) = appState.recordingState {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .paused(let duration, _, _) = appState.recordingState {
                    Text(formatDuration(duration) + " (paused)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let session: Session
    
    var body: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.accentColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Text(session.formattedDuration)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(session.formattedDate)
                    
                    if !session.highlights.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Label("\(session.highlights.count)", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Session Detail View
struct SessionDetailView: View {
    let session: Session
    @Binding var selectedTab: Int
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            
            Divider()
            
            // Tab Bar
            tabBar
            
            Divider()
            
            // Content
            contentArea
        }
    }
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.title2.weight(.semibold))
                
                HStack(spacing: 12) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.formattedDate, systemImage: "calendar")
                    
                    if !session.highlights.isEmpty {
                        Label("\(session.highlights.count) highlights", systemImage: "sparkles")
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: session.audioSource.icon)
                        Text(session.audioSource.rawValue)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(session.provider.rawValue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Recording indicator if this is current session
            if appState.recordingState != .idle && session.id == appState.currentSession?.id {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
    }
    
    private var tabBar: some View {
        Picker("View", selection: $selectedTab) {
            Text("Summary").tag(0)
            Text("Transcript").tag(1)
            Text("Highlights").tag(2)
            Text("People").tag(3)
            Text("Raw").tag(4)
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case 0:
            SummaryTab(session: session)
        case 1:
            TranscriptTab(session: session)
        case 2:
            HighlightsTab(session: session)
        case 3:
            PeopleTab(session: session)
        case 4:
            RawTab(session: session)
        default:
            EmptyView()
        }
    }
}

// MARK: - Summary Tab
struct SummaryTab: View {
    let session: Session
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI Summary
                if let summary = session.summary {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("AI Summary", systemImage: "brain")
                            .font(.headline)
                        
                        Text(summary)
                            .font(.body)
                            .lineSpacing(4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Stats
                HStack(spacing: 16) {
                    StatCard(
                        icon: "checkmark.circle",
                        value: "\(session.actionItems.count)",
                        label: "Action Items"
                    )
                    
                    StatCard(
                        icon: "star",
                        value: "\(session.highlights.filter { $0.type.title == "Decision" }.count)",
                        label: "Decisions"
                    )
                    
                    StatCard(
                        icon: "person.3",
                        value: "\(session.entities.people.count)",
                        label: "People"
                    )
                    
                    StatCard(
                        icon: "text.bubble",
                        value: "\(session.finalTranscript.count)",
                        label: "Messages"
                    )
                }
                
                // Action Items
                if !session.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Action Items", systemImage: "bolt")
                            .font(.headline)
                        
                        ForEach(session.actionItems) { action in
                            ActionItemRow(action: action)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                // Key Decisions
                let decisions = session.highlights.compactMap { highlight -> Decision? in
                    if case .decision(let decision) = highlight.type {
                        return decision
                    }
                    return nil
                }
                
                if !decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Key Decisions", systemImage: "arrow.decision")
                            .font(.headline)
                        
                        ForEach(decisions) { decision in
                            DecisionRow(decision: decision)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding()
            .frame(maxWidth: 800, alignment: .leading)
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2.weight(.semibold))
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct ActionItemRow: View {
    let action: ActionItem
    
    var body: some View {
        HStack {
            Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(action.isCompleted ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(action.task)
                    .strikethrough(action.isCompleted)
                
                HStack {
                    Text(action.assignee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let dueDate = action.dueDateText {
                        Text("• Due \(dueDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DecisionRow: View {
    let decision: Decision
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "arrow.decision")
                .foregroundStyle(.purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(decision.statement)
                
                if !decision.stakeholders.isEmpty {
                    Text("Stakeholders: \(decision.stakeholders.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Transcript Tab
struct TranscriptTab: View {
    let session: Session
    @State private var searchText = ""
    @State private var selectedSpeaker: String? = nil
    
    var filteredTranscript: [FinalTranscriptSegment] {
        var result = session.finalTranscript
        
        if let speaker = selectedSpeaker {
            result = result.filter { $0.displaySpeaker == speaker }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.displaySpeaker.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    var uniqueSpeakers: [String] {
        Array(Set(session.finalTranscript.map { $0.displaySpeaker })).sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                SearchBar(text: $searchText, placeholder: "Search transcript...")
                
                // Speaker filter
                Menu {
                    Button("All Speakers") {
                        selectedSpeaker = nil
                    }
                    
                    Divider()
                    
                    ForEach(uniqueSpeakers, id: \.self) { speaker in
                        Button(speaker) {
                            selectedSpeaker = speaker
                        }
                    }
                } label: {
                    Image(systemName: "person.2")
                        .foregroundColor(selectedSpeaker != nil ? .accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            
            Divider()
            
            // Transcript content
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredTranscript) { segment in
                        FinalTranscriptRow(segment: segment)
                    }
                }
                .padding()
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct FinalTranscriptRow: View {
    let segment: FinalTranscriptSegment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Speaker badge
                Text(segment.displaySpeaker)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
                
                Spacer()
                
                Text(segment.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(segment.text)
                .font(.body)
                .lineSpacing(2)
            
            if !segment.highlights.isEmpty {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("\(segment.highlights.count) highlights")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Highlights Tab
struct HighlightsTab: View {
    let session: Session
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(session.highlights) { highlight in
                    DashboardHighlightRow(highlight: highlight)
                }
            }
            .padding()
        }
    }
}

struct DashboardHighlightRow: View {
    let highlight: Highlight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: highlight.type.icon)
                .foregroundStyle(highlight.type.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(highlight.type.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Confidence badge
                    Text("\(Int(highlight.confidence * 100))%")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                
                highlightContent
                
                if let evidence = highlight.evidence {
                    Text("\"\(evidence)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var confidenceColor: Color {
        if highlight.confidence >= 0.8 {
            return .green
        } else if highlight.confidence >= 0.6 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    @ViewBuilder
    private var highlightContent: some View {
        switch highlight.type {
        case .action(let action):
            VStack(alignment: .leading, spacing: 2) {
                Text(action.task)
                    .font(.subheadline.weight(.medium))
                HStack {
                    Text(action.assignee)
                        .font(.caption)
                    if let dueDate = action.dueDateText {
                        Text("• Due \(dueDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
        case .decision(let decision):
            Text(decision.statement)
                .font(.subheadline.weight(.medium))
            
        case .risk(let risk):
            VStack(alignment: .leading, spacing: 2) {
                Text(risk.description)
                    .font(.subheadline.weight(.medium))
                HStack {
                    Text(risk.severity.rawValue)
                        .font(.caption)
                        .foregroundStyle(risk.severity.color)
                    if let mitigation = risk.mitigation {
                        Text("• \(mitigation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
        case .keyPoint(let text):
            Text(text)
                .font(.subheadline.weight(.medium))
        }
    }
}

// MARK: - People Tab
struct PeopleTab: View {
    let session: Session
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !session.entities.people.isEmpty {
                    EntityListSection(title: "People", entities: session.entities.people)
                }
                
                if !session.entities.organizations.isEmpty {
                    EntityListSection(title: "Organizations", entities: session.entities.organizations)
                }
                
                if !session.entities.topics.isEmpty {
                    EntityListSection(title: "Topics", entities: session.entities.topics)
                }
                
                if !session.entities.dates.isEmpty {
                    EntityListSection(title: "Dates Mentioned", entities: session.entities.dates)
                }
            }
            .padding()
        }
    }
}

struct EntityListSection: View {
    let title: String
    let entities: [SessionEntities.Entity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            ForEach(entities) { entity in
                EntityDetailRow(entity: entity)
            }
        }
    }
}

struct EntityDetailRow: View {
    let entity: SessionEntities.Entity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entity.name)
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                Label("\(entity.mentionCount)", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !entity.quotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entity.quotes.prefix(2), id: \.self) { quote in
                        Text("\"\(quote)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Raw Tab
struct RawTab: View {
    let session: Session
    @State private var selectedFormat = 0
    
    let formats = ["Markdown", "JSON", "Plain Text"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Format selector
            Picker("Format", selection: $selectedFormat) {
                ForEach(0..<formats.count, id: \.self) { index in
                    Text(formats[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                Text(rawContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Export button
            HStack {
                Spacer()
                Button(action: { /* Copy to clipboard */ }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Button(action: { /* Export file */ }) {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    private var rawContent: String {
        switch selectedFormat {
        case 0:
            return generateMarkdown()
        case 1:
            return generateJSON()
        default:
            return generatePlainText()
        }
    }
    
    private func generateMarkdown() -> String {
        var md = "# \(session.title)\n\n"
        md += "**Duration:** \(session.formattedDuration)  \n"
        md += "**Date:** \(session.startTime)\n\n"
        
        if let summary = session.summary {
            md += "## Summary\n\n\(summary)\n\n"
        }
        
        md += "## Transcript\n\n"
        for segment in session.finalTranscript {
            md += "**\(segment.displaySpeaker)** [\(segment.formattedTime)]:\n"
            md += "\(segment.text)\n\n"
        }
        
        return md
    }
    
    private func generateJSON() -> String {
        // Simplified JSON representation
        return """
        {
          "session": {
            "id": "\(session.id.uuidString)",
            "title": "\(session.title)",
            "duration": "\(session.formattedDuration)",
            "transcript_count": \(session.finalTranscript.count),
            "highlights_count": \(session.highlights.count)
          }
        }
        """
    }
    
    private func generatePlainText() -> String {
        var text = "\(session.title)\n"
        text += "Duration: \(session.formattedDuration)\n\n"
        
        for segment in session.finalTranscript {
            text += "[\(segment.formattedTime)] \(segment.displaySpeaker): \(segment.text)\n"
        }
        
        return text
    }
}

// MARK: - Empty States
struct EmptyDashboardState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Welcome to EchoPanel")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Select a session from the sidebar to view details, or start a new recording")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toolbar Buttons
struct RecordButton: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        Button(action: {
            if appState.recordingState == .idle {
                appState.startRecording()
            } else {
                appState.stopRecording()
            }
        }) {
            Label(
                appState.recordingState == .idle ? "Record" : "Stop",
                systemImage: appState.recordingState == .idle ? "record.circle" : "stop.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.recordingState == .idle ? .accentColor : .red)
    }
}

struct ExportButton: View {
    var body: some View {
        Menu {
            Button("Export as Markdown") {}
            Button("Export as JSON") {}
            Button("Export as Text") {}
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Export Sheet
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var includeTranscript = true
    @State private var includeHighlights = true
    @State private var includeSummary = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Session").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Format").font(.subheadline.weight(.semibold))
                    
                    FormatPickerView(selectedFormat: $selectedFormat)
                    
                    Divider()
                    
                    Text("Include").font(.subheadline.weight(.semibold))
                    Toggle("Full Transcript", isOn: $includeTranscript)
                    Toggle("Highlights", isOn: $includeHighlights)
                    Toggle("Summary", isOn: $includeSummary)
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Export") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
    }
}

struct FormatPickerView: View {
    @Binding var selectedFormat: ExportFormat
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(ExportFormat.allCases) { format in
                FormatRowView(format: format, isSelected: selectedFormat == format) {
                    selectedFormat = format
                }
            }
        }
    }
}

struct FormatRowView: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: format.icon).frame(width: 24)
                VStack(alignment: .leading) {
                    Text(format.rawValue).font(.subheadline)
                    Text(format.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDestination: ShareDestination = .clipboard
    @State private var includeSummary = true
    @State private var includeActionItems = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Share").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Share to").font(.subheadline.weight(.semibold))
                    ShareDestinationPickerView(selectedDestination: $selectedDestination)
                    
                    Divider()
                    
                    Text("Include").font(.subheadline.weight(.semibold))
                    Toggle("Summary", isOn: $includeSummary)
                    Toggle("Action Items", isOn: $includeActionItems)
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Share") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 380, height: 400)
    }
}

struct ShareDestinationPickerView: View {
    @Binding var selectedDestination: ShareDestination
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(ShareDestination.allCases) { dest in
                ShareDestRowView(dest: dest, isSelected: selectedDestination == dest) {
                    selectedDestination = dest
                }
            }
        }
    }
}

struct ShareDestRowView: View {
    let dest: ShareDestination
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: dest.icon).frame(width: 24).foregroundStyle(dest.color)
                Text(dest.rawValue)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MOM Generator Sheet
struct MOMGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateIndex = 0
    @State private var selectedStyleIndex = 0
    @State private var isGenerating = false
    
    let styles = ["Formal", "Casual", "Executive", "Technical"]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meeting Minutes").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Meeting Type").font(.subheadline.weight(.semibold))
                    
                    Text("Daily Standup, Weekly 1:1, Sprint Planning, etc.")
                        .font(.caption).foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Text("Style").font(.subheadline.weight(.semibold))
                    
                    Picker("Style", selection: $selectedStyleIndex) {
                        ForEach(0..<styles.count, id: \.self) { i in
                            Text(styles[i]).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Divider()
                    
                    Button(action: {
                        isGenerating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isGenerating = false
                            dismiss()
                        }
                    }) {
                        HStack {
                            if isGenerating { ProgressView().scaleEffect(0.8) }
                            Text(isGenerating ? "Generating..." : "Generate Minutes")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Copy") { }
                Button("Share") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Date()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Upcoming Meetings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            
            Divider()
            
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 8) {
                    if appState.calendarEvents.isEmpty {
                        Text("No upcoming meetings")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(appState.calendarEvents.sorted { $0.startTime < $1.startTime }) { event in
                            EventRowView(event: event)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Button("Sync") { }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Add Meeting") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
    }
}

struct EventRowView: View {
    let event: CalendarEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.title).font(.subheadline.weight(.semibold))
                Spacer()
                if event.isrecurring {
                    Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(event.startTime, style: .time)
                Text("•")
                Text(event.attendees.prefix(2).joined(separator: ", "))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
