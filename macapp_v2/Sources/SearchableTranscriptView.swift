import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
}

struct SearchableTranscriptView: View {
    let transcript: [TranscriptItem]
    @State private var searchText = ""
    @State private var selectedSpeaker: String? = nil
    
    var filteredTranscript: [TranscriptItem] {
        var result = transcript
        
        // Filter by speaker
        if let speaker = selectedSpeaker {
            result = result.filter { $0.speaker == speaker }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.speaker.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    var uniqueSpeakers: [String] {
        Array(Set(transcript.map { $0.speaker })).sorted()
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
                        .foregroundColor(selectedSpeaker == speaker ? .accentColor : .primary)
                    }
                } label: {
                    Image(systemName: "person.2")
                        .foregroundColor(selectedSpeaker != nil ? .accentColor : .secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding()
            
            Divider()
            
            // Results
            if filteredTranscript.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: searchText.isEmpty ? "No Transcript" : "No Results",
                    subtitle: searchText.isEmpty 
                        ? "Start recording to see transcript here"
                        : "Try a different search term"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredTranscript) { item in
                            SearchableTranscriptCard(item: item, searchText: searchText)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct SearchableTranscriptCard: View {
    let item: TranscriptItem
    let searchText: String
    @EnvironmentObject private var appState: AppState
    @State private var isPinned: Bool
    
    init(item: TranscriptItem, searchText: String) {
        self.item = item
        self.searchText = searchText
        _isPinned = State(initialValue: item.isPinned)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.speaker)
                    .font(.subheadline.weight(.semibold))
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Pin button
                    Button(action: togglePin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.caption)
                            .foregroundStyle(isPinned ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "Unpin this moment" : "Pin this moment (P)")
                    
                    // Copy button
                    Button(action: copyText) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy text")
                    
                    Text(item.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Highlight search matches
            if searchText.isEmpty {
                Text(item.text)
                    .font(.body)
            } else {
                HighlightedText(text: item.text, highlight: searchText)
                    .font(.body)
            }
            
            if let action = item.actionItem {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("\(action.assignee): \(action.task)")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Material.regularMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isPinned ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    private func togglePin() {
        isPinned.toggle()
        // In real app, would update the model
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(item.speaker)] \(item.text)", forType: .string)
    }
}

struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        let parts = text.components(separatedBy: highlight)

        return parts.enumerated().reduce(Text("")) { result, element in
            let (index, part) = element
            if index < parts.count - 1 {
                return result + Text(part) + Text(highlight).bold()
            } else {
                return result + Text(part)
            }
        }
    }
}
