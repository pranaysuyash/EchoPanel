import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    
    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return appState.sessions
        }
        return appState.sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Session History")
                    .font(.title3.weight(.semibold))
                
                Spacer()
                
                HStack(spacing: 12) {
                    SearchField(text: $searchText)
                        .frame(width: 250)
                    
                    Button(action: {}) {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding()
            .background(Material.thinMaterial)
            
            Divider()
            
            // Content
            if filteredSessions.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: searchText.isEmpty ? "No Sessions" : "No Results",
                    subtitle: searchText.isEmpty 
                        ? "Your recorded sessions will appear here"
                        : "Try a different search term"
                )
            } else {
                List(filteredSessions) { session in
                    SessionRow(session: session)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

struct SessionRow: View {
    let session: Session
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.formattedDate, systemImage: "calendar")
                    
                    if !session.highlights.isEmpty {
                        Label("\(session.highlights.count) highlights", systemImage: "sparkles")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SearchField: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search sessions...", text: $text)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Material.regularMaterial)
        .cornerRadius(6)
    }
}
