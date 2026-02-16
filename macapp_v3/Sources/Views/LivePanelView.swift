import SwiftUI

struct LivePanelView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var showAudioSourcePicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            headerBar
            
            Divider()
            
            // MARK: Audio Source Control
            audioSourceControl
            
            Divider()
            
            // MARK: Tab Bar
            tabBar
            
            Divider()
            
            // MARK: Content
            contentArea
            
            Divider()
            
            // MARK: Footer Controls
            footerControls
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: Header Bar
    private var headerBar: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(recordingColor)
                    .frame(width: 8, height: 8)
                
                Text(recordingStatusText)
                    .font(.headline)
                
                if case .recording(let duration, _) = appState.recordingState {
                    Text(formatDuration(duration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if case .paused(let duration, _, _) = appState.recordingState {
                    Text(formatDuration(duration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Pin button
            Button(action: { /* Pin current moment */ }) {
                Image(systemName: "pin")
            }
            .buttonStyle(.plain)
            .help("Pin this moment (P)")
            
            // Settings
            Button(action: { /* Open quick settings */ }) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Material.bar)
    }
    
    private var recordingColor: Color {
        switch appState.recordingState {
        case .idle: return .gray
        case .recording: return .red
        case .paused: return .orange
        case .error: return .red
        }
    }
    
    private var recordingStatusText: String {
        switch appState.recordingState {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }
    
    // MARK: Audio Source Control
    private var audioSourceControl: some View {
        HStack(spacing: 12) {
            // Audio source button
            Button(action: { showAudioSourcePicker.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: appState.audioSource.icon)
                    Text(appState.audioSource.rawValue)
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAudioSourcePicker) {
                AudioSourcePicker(selectedSource: $appState.audioSource)
            }
            
            // Audio quality indicator
            HStack(spacing: 4) {
                Image(systemName: appState.audioQuality.icon)
                    .foregroundStyle(appState.audioQuality.color)
                Text("Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // ASR Provider indicator
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(appState.asrProvider.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: Tab Bar
    private var tabBar: some View {
        Picker("View", selection: $selectedTab) {
            Text("Transcript").tag(0)
            Text("Highlights").tag(1)
            Text("Entities").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: Content Area
    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case 0:
            LiveTranscriptView()
        case 1:
            LiveHighlightsView()
        case 2:
            LiveEntitiesView()
        default:
            EmptyView()
        }
    }
    
    // MARK: Footer Controls
    private var footerControls: some View {
        HStack {
            // Pause/Resume button
            if case .recording = appState.recordingState {
                Button(action: { appState.pauseRecording() }) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
            } else if case .paused = appState.recordingState {
                Button(action: { appState.resumeRecording() }) {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
            
            // End session button
            if appState.recordingState != .idle {
                Button(action: { appState.stopRecording() }) {
                    Label("End", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Source Picker
struct AudioSourcePicker: View {
    @Binding var selectedSource: AudioSource
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Source")
                .font(.headline)
            
            ForEach(AudioSource.allCases) { source in
                Button(action: {
                    selectedSource = source
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: source.icon)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.rawValue)
                                .font(.subheadline.weight(.medium))
                            Text(source.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if selectedSource == source {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                        }
                    }
                    .padding(8)
                    .background(selectedSource == source ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Live Transcript View
struct LiveTranscriptView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 12) {
                    if let session = appState.currentSession {
                        ForEach(session.liveTranscript) { segment in
                            LiveTranscriptSegmentRow(segment: segment)
                        }
                        
                        // Recording indicator at bottom
                        if appState.recordingState != .idle {
                            HStack {
                                Spacer()
                                RecordingIndicator()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    } else {
                        EmptyTranscriptState()
                    }
                }
                .padding()
            }
        }
    }
}

struct LiveTranscriptSegmentRow: View {
    let segment: LiveTranscriptSegment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Source indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(sourceColor)
                        .frame(width: 6, height: 6)
                    Text(segment.audioSource.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Timestamp
                Text(segment.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Text content
            Text(segment.text)
                .font(.body)
                .foregroundStyle(segment.isPartial ? .secondary : .primary)
                .italic(segment.isPartial)
                .opacity(segment.isPartial ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: segment.isPartial)
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(8)
    }
    
    private var sourceColor: Color {
        switch segment.audioSource {
        case .system: return .blue
        case .microphone: return .green
        case .unknown: return .gray
        }
    }
}

struct RecordingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(isAnimating ? 1.0 : 0.5)
            
            Text("Listening...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct EmptyTranscriptState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Ready to Record")
                .font(.headline)
            
            Text("Click 'Start Recording' to begin capturing your meeting")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Live Highlights View
struct LiveHighlightsView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session = appState.currentSession, !session.highlights.isEmpty {
                    ForEach(session.highlights.prefix(5)) { highlight in
                        HighlightRow(highlight: highlight)
                    }
                } else {
                    EmptyHighlightsState()
                }
            }
            .padding()
        }
    }
}

struct HighlightRow: View {
    let highlight: Highlight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: highlight.type.icon)
                .foregroundStyle(highlight.type.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.type.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                highlightContent
                
                if let evidence = highlight.evidence {
                    Text("\"\(evidence)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                }
                
                Text(highlight.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(8)
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

struct EmptyHighlightsState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Highlights Yet")
                .font(.headline)
            
            Text("Action items, decisions, and key points will appear here as they're detected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Live Entities View
struct LiveEntitiesView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session = appState.currentSession {
                    if !session.entities.people.isEmpty {
                        EntitySection(title: "People", entities: session.entities.people)
                    }
                    if !session.entities.organizations.isEmpty {
                        EntitySection(title: "Organizations", entities: session.entities.organizations)
                    }
                    if !session.entities.topics.isEmpty {
                        EntitySection(title: "Topics", entities: session.entities.topics)
                    }
                    if !session.entities.dates.isEmpty {
                        EntitySection(title: "Dates", entities: session.entities.dates)
                    }
                } else {
                    EmptyEntitiesState()
                }
            }
            .padding()
        }
    }
}

struct EntitySection: View {
    let title: String
    let entities: [SessionEntities.Entity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(entities) { entity in
                    EntityChip(entity: entity)
                }
            }
        }
    }
}

struct EntityChip: View {
    let entity: SessionEntities.Entity
    
    var body: some View {
        HStack(spacing: 4) {
            Text(entity.name)
            Text("\(entity.mentionCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct EmptyEntitiesState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Entities Detected")
                .font(.headline)
            
            Text("People, organizations, and topics will be extracted as you speak")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
