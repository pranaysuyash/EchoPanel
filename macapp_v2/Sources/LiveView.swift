import SwiftUI

struct PanelContainerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .highlights
    
    enum Tab {
        case highlights
        case transcript
        case people
    }
    
    var body: some View {
        Group {
            if appState.currentSession != nil {
                LiveView(selectedTab: $selectedTab)
            } else if let session = appState.sessions.first {
                ReviewView(session: session)
            } else {
                EmptyStateView(
                    icon: "waveform",
                    title: "No Sessions Yet",
                    subtitle: "Click Start Recording in the menu bar to begin capturing your first meeting"
                )
            }
        }
        .frame(minWidth: 320, minHeight: 500)
    }
}

struct LiveView: View {
    @Binding var selectedTab: PanelContainerView.Tab
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack(spacing: 6) {
                    StatusDot(status: .active)
                    Text("Recording")
                        .font(.headline)
                    if case .recording(let duration) = appState.recordingState {
                        Text(formatDuration(duration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: { appState.alwaysOnTop.toggle() }) {
                        Image(systemName: appState.alwaysOnTop ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Material.thinMaterial)
            
            // Tab bar
            Picker("View", selection: $selectedTab) {
                Text("Highlights").tag(PanelContainerView.Tab.highlights)
                Text("Transcript").tag(PanelContainerView.Tab.transcript)
                Text("People").tag(PanelContainerView.Tab.people)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Content
            ScrollView {
                switch selectedTab {
                case .highlights:
                    HighlightsView()
                case .transcript:
                    TranscriptView()
                case .people:
                    PeopleView()
                }
            }
            
            // Footer
            HStack {
                Toggle("Always on Top", isOn: $appState.alwaysOnTop)
                    .toggleStyle(.checkbox)
                
                Spacer()
                
                Button(action: { appState.stopRecording() }) {
                    Label("End Session", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .background(Material.thinMaterial)
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct HighlightsView: View {
    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            if MockData.sampleHighlights.isEmpty {
                EmptyStateView(
                    icon: "sparkles",
                    title: "No Highlights Yet",
                    subtitle: "Key points and action items will appear here as the conversation develops"
                )
            } else {
                ForEach(MockData.sampleHighlights) { highlight in
                    HighlightCard(highlight: highlight)
                }
            }
        }
        .padding()
    }
}

struct HighlightCard: View {
    let highlight: Highlight
    
    var icon: String {
        switch highlight.type {
        case .action: return "checkmark.circle"
        case .decision: return "arrow.decision"
        case .keyPoint: return "star"
        case .question: return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch highlight.type {
        case .action: return .blue
        case .decision: return .purple
        case .keyPoint: return .orange
        case .question: return .green
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(highlight.content)
                    .font(.body)
                
                Text(formatTime(highlight.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.cardBorder, lineWidth: 0.5)
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TranscriptView: View {
    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(MockData.sampleTranscript) { item in
                TranscriptCard(item: item)
            }
        }
        .padding()
    }
}

struct TranscriptCard: View {
    let item: TranscriptItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(item.speaker)
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Text(item.text)
                .font(.body)
            
            if let action = item.actionItem {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                    Text("\(action.assignee): \(action.task)")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(CornerRadius.xs)
            }
            
            HStack {
                Spacer()
                Text(item.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.cardBorder, lineWidth: 0.5)
        )
    }
}

struct PeopleView: View {
    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(MockData.samplePeople) { person in
                PersonCard(person: person)
            }
        }
        .padding()
    }
}

struct PersonCard: View {
    let person: Person
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.headline)
                    Text("\(person.mentionCount) mentions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if !person.topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(person.topics, id: \.self) { topic in
                        Text(topic)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(CornerRadius.xs)
                    }
                }
            }
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.cardBorder, lineWidth: 0.5)
        )
    }
}

// Helper for wrapping tags
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
