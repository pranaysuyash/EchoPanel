import AppKit
import SwiftUI

enum NeedsReviewBadgeStyle {
    static let foreground = NSColor.black
    static let background = NSColor.systemOrange
}

struct SurfaceCardItem: Identifiable {
    let id = UUID()
    let tag: String
    let title: String
    let subtitle: String
}

struct FullSessionItem: Identifiable {
    let id: String
    let name: String
    let when: String
    let duration: String
    let isLive: Bool
}

struct SpeakerChipItem: Identifiable {
    let id: String
    let label: String
    let count: Int
    let color: Color
    let searchToken: String
}

struct TranscriptLineRow: View {
    @Environment(\.colorScheme) var colorScheme

    let segment: TranscriptSegment
    let entities: [EntityItem]
    let highlightMode: EntityHighlighter.HighlightMode
    let isFocused: Bool
    let isPinned: Bool
    let onPin: () -> Void
    let onLens: () -> Void
    let onJump: () -> Void
    let onEntityClick: (EntityItem) -> Void

    private let lowConfidenceThreshold = 0.5

    var body: some View {
        let highlightMatches = EntityHighlighter.matches(in: segment.text, entities: entities, mode: highlightMode)
        HStack(alignment: .top, spacing: 10) {
            Text(formatTime(segment.t0))
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)

            speakerBadge

            VStack(alignment: .leading, spacing: 4) {
                EntityTextView(
                    text: segment.text,
                    matches: highlightMatches,
                    highlightsEnabled: highlightMode.isEnabled
                ) { entity in
                    onEntityClick(entity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityRepresentation {
                    EntityHighlightsAccessibilityRepresentation(
                        transcriptText: segment.text,
                        entities: accessibilityEntities(from: highlightMatches),
                        onEntityClick: onEntityClick
                    )
                }

                HStack(spacing: 8) {
                    Text(formatConfidence(segment.confidence))
                        .font(.caption2)
                        .foregroundColor(confidenceColor)

                    if segment.confidence < lowConfidenceThreshold {
                        needsReviewBadge
                    }
                }
            }

            if isFocused {
                HStack(spacing: 4) {
                    iconButton(
                        systemName: isPinned ? "pin.fill" : "pin",
                        accessibilityLabel: isPinned ? "Unpin line" : "Pin line",
                        action: onPin
                    )
                    iconButton(
                        systemName: "arrow.up.left.and.arrow.down.right",
                        accessibilityLabel: "Toggle focus lens",
                        action: onLens
                    )
                    iconButton(
                        systemName: "arrow.down.circle",
                        accessibilityLabel: "Jump to live",
                        action: onJump
                    )
                }
            }
        }
        .padding(10)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        )
    }

    var speakerBadge: some View {
        let label = speakerInitial
        let accessibilityLabel = speakerAccessibilityLabel
        return Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .frame(width: 24, height: 24)
            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.9))
            .clipShape(Circle())
            .overlay(Circle().stroke(speakerTint.opacity(0.7), lineWidth: 1))
            .foregroundColor(speakerTint)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isStaticText)
    }
    
    var speakerAccessibilityLabel: String {
        if let speaker = segment.speaker, !speaker.isEmpty {
            return "Speaker: \(speaker)"
        }
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? "Speaker: You" : "Speaker: System"
        }
        return "Unknown speaker"
    }

    func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(accessibilityLabel)
    }

    var rowBackground: Color {
        if isFocused {
            return Color.blue.opacity(0.11)
        }
        if isPinned {
            return Color.indigo.opacity(0.1)
        }
        return Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.18 : 0.75)
    }

    var rowStroke: Color {
        if isFocused {
            return Color.blue.opacity(0.5)
        }
        if isPinned {
            return Color.indigo.opacity(0.45)
        }
        return Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.55 : 0.25)
    }

    var speakerInitial: String {
        if let speaker = segment.speaker, let c = speaker.first {
            return String(c).uppercased()
        }
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? "Y" : "S"
        }
        return "•"
    }

    var speakerTint: Color {
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? .blue : .purple
        }
        return .teal
    }

    var confidenceColor: Color {
        if segment.confidence >= 0.8 {
            return .green
        }
        if segment.confidence >= 0.5 {
            return .secondary
        }
        return .orange
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    func accessibilityEntities(from matches: [EntityMatch]) -> [EntityItem] {
        var seen: Set<String> = []
        var ordered: [EntityItem] = []
        for match in matches {
            let key = "\(match.entity.type.lowercased())::\(match.entity.name.lowercased())"
            if seen.insert(key).inserted {
                ordered.append(match.entity)
            }
        }
        return ordered
    }

    var needsReviewBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("Needs review")
                .font(.caption2)
        }
        .foregroundColor(Color(nsColor: NeedsReviewBadgeStyle.foreground))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(nsColor: NeedsReviewBadgeStyle.background))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(nsColor: NeedsReviewBadgeStyle.foreground).opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityLabel("Needs review low confidence transcript line")
    }
}

struct EntityHighlightsAccessibilityRepresentation: View {
    let transcriptText: String
    let entities: [EntityItem]
    let onEntityClick: (EntityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transcriptText)
            if entities.isEmpty {
                Text("No highlighted entities")
                    .foregroundColor(.secondary)
            } else {
                ForEach(entities) { entity in
                    Button {
                        onEntityClick(entity)
                    } label: {
                        Text("Open entity \(entity.name)")
                    }
                    .accessibilityLabel("Open entity \(entity.name)")
                    .accessibilityHint("Shows entity details and mention navigation.")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

struct ShortcutRow: View {
    @Environment(\.colorScheme) var colorScheme

    let label: String
    let key: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(key)
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

struct HighlightHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(.headline)

            Text("Off")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("No in-line entity highlighting.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Extracted")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Uses backend entities for consistent names across transcript and entity surface.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("NLP")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Uses on-device Apple NLP for quick name/place/org highlighting.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
            Text("Tip: click a highlight to filter and jump mentions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct EntityDetailPopover: View {
    let entity: EntityItem
    let isFiltering: Bool
    let onToggleFilter: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.name)
                        .font(.headline)
                    Text(entity.type.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Label("\(entity.count)", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("\(Int(entity.confidence * 100))%", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button(isFiltering ? "Clear Filter" : "Filter Transcript") {
                    onToggleFilter()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isFiltering ? "Clear entity filter" : "Filter transcript by entity")
                .accessibilityHint("Limits transcript lines to this entity.")

                Spacer()

                Button {
                    onPrev()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Previous mention")
                .accessibilityHint("Moves focus to the previous mention of this entity.")

                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Next mention")
                .accessibilityHint("Moves focus to the next mention of this entity.")
            }
        }
    }
}

struct PermissionBanner: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if issues.isEmpty == false {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(issues.map(\.label).joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                Spacer()
                Button("Open") {
                    if let primary = issues.first, let nsURL = URL(string: primary.url) {
                        NSWorkspace.shared.open(nsURL)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    var issues: [(label: String, url: String)] {
        let needsScreen = appState.audioSource == .system || appState.audioSource == .both
        let needsMic = appState.audioSource == .microphone || appState.audioSource == .both
        var rows: [(String, String)] = []

        if needsScreen && appState.screenRecordingPermission == .denied {
            rows.append((
                "Screen recording not granted",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ))
        }
        if needsMic && appState.microphonePermission == .denied {
            rows.append((
                "Microphone not granted",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ))
        }

        return rows
    }
}

struct AudioLevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor)
                        .frame(width: max(2, CGFloat(level) * geometry.size.width))
                }
            }
            .frame(width: 72, height: 7)
        }
    }

    var levelColor: Color {
        if level > 0.8 {
            return .red
        }
        if level > 0.3 {
            return .green
        }
        return .yellow
    }
}
