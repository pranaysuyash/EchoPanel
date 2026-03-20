import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var appState: AppState
    let session: Session
    @State private var selectedSection: ReviewSection = .summary
    
    enum ReviewSection: String, CaseIterable {
        case summary = "Summary"
        case highlights = "Highlights"
        case transcript = "Transcript"
        case people = "People"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selectedSection) {
                Section("Session") {
                    ForEach(ReviewSection.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: iconForSection(section))
                            .tag(section)
                    }
                }
                
                Section("Other Sessions") {
                    ForEach(appState.sessions.filter { $0.id != session.id }) { session in
                        Label(session.title, systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            
            Divider()
            
            // Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.title3.weight(.semibold))
                        
                        HStack(spacing: 12) {
                            Label(session.formattedDuration, systemImage: "clock")
                            Label(session.formattedDate, systemImage: "calendar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {}) {
                            Label("Share", systemImage: "person.wave.2")
                        }
                    }
                }
                .padding()
                .background(Material.thinMaterial)
                
                Divider()
                
                // Content based on selection
                ScrollView {
                    switch selectedSection {
                    case .summary:
                        SummaryContent(session: session, summaryText: appState.reviewSummary, people: appState.livePeople)
                    case .highlights:
                        HighlightsContent(highlights: session.highlights)
                    case .transcript:
                        TranscriptContent(transcript: session.transcript)
                    case .people:
                        PeopleContent(people: appState.livePeople)
                    }
                }
            }
        }
    }
    
    private func iconForSection(_ section: ReviewSection) -> String {
        switch section {
        case .summary: return "text.alignleft"
        case .highlights: return "sparkles"
        case .transcript: return "text.bubble"
        case .people: return "person.3"
        }
    }
}

struct SummaryContent: View {
    let session: Session
    let summaryText: String
    let people: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // AI Summary
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("AI Summary", systemImage: "brain")
                    .font(.headline)

                Text(summaryText)
                    .font(.body)
                    .lineSpacing(4)
            }
            .padding()
            // ✅ HIG-compliant: cardBackground instead of Material.regularMaterial
            .background(AppMaterial.cardBackground)
            .cornerRadius(CornerRadius.md)
            
            // Key stats
            HStack(spacing: Spacing.lg) {
                StatCard(
                    icon: "checkmark.circle",
                    value: "\(session.transcript.compactMap { $0.actionItem }.count)",
                    label: "Action Items"
                )
                
                StatCard(
                    icon: "star",
                    value: "\(session.highlights.filter { $0.type == .decision }.count)",
                    label: "Key Decisions"
                )
                
                StatCard(
                    icon: "person.3",
                    value: "\(people.count)",
                    label: "Participants"
                )
                
                StatCard(
                    icon: "text.bubble",
                    value: "\(session.transcript.count)",
                    label: "Messages"
                )
            }
            
            // Quick actions
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Quick Actions", systemImage: "bolt")
                    .font(.headline)
                
                VStack(spacing: Spacing.sm) {
                    ForEach(session.highlights.filter { $0.type == .action }) { action in
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.blue)
                            Text(action.content)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
            .background(AppMaterial.cardBackground)
            .cornerRadius(CornerRadius.md)
        }
        .padding()
        .frame(maxWidth: 700, alignment: .leading)
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
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
        .background(AppMaterial.cardBackground)
        .cornerRadius(CornerRadius.md)
    }
}

struct HighlightsContent: View {
    let highlights: [Highlight]

    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(highlights) { highlight in
                HighlightCard(highlight: highlight)
            }
        }
        .padding()
    }
}

struct TranscriptContent: View {
    let transcript: [TranscriptItem]

    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(transcript) { item in
                TranscriptCard(item: item)
            }
        }
        .padding()
    }
}

struct PeopleContent: View {
    let people: [Person]

    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(people) { person in
                PersonCard(person: person)
            }
        }
        .padding()
    }
}
