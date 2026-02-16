import SwiftUI

/// Keyboard shortcut cheatsheet for EchoPanel
/// Provides discoverability for all keyboard shortcuts
struct KeyboardCheatsheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    // MARK: - Shortcut Categories
    
    struct ShortcutCategory: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let shortcuts: [Shortcut]
    }
    
    struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
        let context: String
    }
    
    private var categories: [ShortcutCategory] {
        [
            sessionCategory,
            navigationCategory,
            exportCategory,
            viewCategory,
            globalCategory
        ]
    }
    
    private var filteredCategories: [ShortcutCategory] {
        if searchText.isEmpty {
            return categories
        }
        return categories.compactMap { category in
            let filteredShortcuts = category.shortcuts.filter {
                $0.keys.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.context.localizedCaseInsensitiveContains(searchText)
            }
            if filteredShortcuts.isEmpty {
                return nil
            }
            return ShortcutCategory(name: category.name, icon: category.icon, shortcuts: filteredShortcuts)
        }
    }
    
    // MARK: - Categories
    
    private var sessionCategory: ShortcutCategory {
        ShortcutCategory(
            name: "Session Control",
            icon: "record.circle",
            shortcuts: [
                Shortcut(keys: "⌘⇧L", description: "Start/Stop listening", context: "Global"),
                Shortcut(keys: "F1", description: "Start session", context: "Global hotkey"),
                Shortcut(keys: "F2", description: "Stop session", context: "Global hotkey"),
                Shortcut(keys: "F6", description: "Pause/Resume", context: "Global hotkey"),
                Shortcut(keys: "F3", description: "Insert marker", context: "Global hotkey")
            ]
        )
    }
    
    private var navigationCategory: ShortcutCategory {
        ShortcutCategory(
            name: "Navigation",
            icon: "arrow.up.arrow.down",
            shortcuts: [
                Shortcut(keys: "↑ ↓", description: "Navigate transcript lines", context: "Side Panel"),
                Shortcut(keys: "← →", description: "Navigate between speakers", context: "Side Panel"),
                Shortcut(keys: "J", description: "Jump to live", context: "Side Panel"),
                Shortcut(keys: "Space", description: "Toggle follow live", context: "Side Panel"),
                Shortcut(keys: "⌘F", description: "Search transcript", context: "Full Mode")
            ]
        )
    }
    
    private var exportCategory: ShortcutCategory {
        ShortcutCategory(
            name: "Export",
            icon: "square.and.arrow.up",
            shortcuts: [
                Shortcut(keys: "⌘⇧M", description: "Export as Markdown", context: "Global"),
                Shortcut(keys: "⌘⇧J", description: "Export as JSON", context: "Global"),
                Shortcut(keys: "⌘⇧C", description: "Copy Markdown", context: "Global"),
                Shortcut(keys: "F5", description: "Export transcript", context: "Global hotkey")
            ]
        )
    }
    
    private var viewCategory: ShortcutCategory {
        ShortcutCategory(
            name: "View Modes",
            icon: "rectangle.split.3x1",
            shortcuts: [
                Shortcut(keys: "⌘1", description: "Roll mode (live meetings)", context: "Side Panel"),
                Shortcut(keys: "⌘2", description: "Compact mode (quick look)", context: "Side Panel"),
                Shortcut(keys: "⌘3", description: "Full mode (review)", context: "Side Panel"),
                Shortcut(keys: "⇥", description: "Switch surface tab", context: "Side Panel")
            ]
        )
    }
    
    private var globalCategory: ShortcutCategory {
        ShortcutCategory(
            name: "Global",
            icon: "globe",
            shortcuts: [
                Shortcut(keys: "⌘⇧L", description: "Toggle listening", context: "Menu Bar"),
                Shortcut(keys: "⌘⇧S", description: "Show session summary", context: "Menu Bar"),
                Shortcut(keys: "⌘⇧D", description: "Show diagnostics", context: "Menu Bar"),
                Shortcut(keys: "⌘,", description: "Open settings", context: "Standard"),
                Shortcut(keys: "⌘?", description: "Show this cheatsheet", context: "Global")
            ]
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            // Search
            SearchField(text: $searchText)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(filteredCategories) { category in
                        CategorySection(category: category)
                    }
                }
                .padding()
            }
            
            // Footer
            HStack {
                Text("Press ⌘? anytime to show this cheatsheet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Subviews

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search shortcuts..."
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        searchField.font = NSFont.systemFont(ofSize: 13)
        return searchField
    }
    
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let searchField = obj.object as? NSSearchField {
                text = searchField.stringValue
            }
        }
    }
}

private struct CategorySection: View {
    let category: KeyboardCheatsheetView.ShortcutCategory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category header
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.accentColor)
                Text(category.name)
                    .font(.headline)
            }
            
            // Shortcuts table
            VStack(alignment: .leading, spacing: 6) {
                ForEach(category.shortcuts) { shortcut in
                    CheatsheetShortcutRow(shortcut: shortcut)
                }
            }
            .padding(.leading, 4)
        }
    }
}

private struct CheatsheetShortcutRow: View {
    let shortcut: KeyboardCheatsheetView.Shortcut
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Keys
            HStack(spacing: 2) {
                ForEach(Array(shortcut.keys), id: \.self) { char in
                    KeyBadge(character: String(char))
                }
            }
            .frame(width: 100, alignment: .leading)
            
            // Description
            Text(shortcut.description)
                .font(.body)
            
            Spacer()
            
            // Context
            Text(shortcut.context)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
    }
}

private struct KeyBadge: View {
    let character: String
    
    var body: some View {
        Text(character)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 0.5, x: 0, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Preview

#Preview {
    KeyboardCheatsheetView()
}
