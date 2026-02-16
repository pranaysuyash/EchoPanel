import AppKit
import SwiftUI

// MARK: - Needs Review Badge Style
// HIG-compliant warning badge using semantic colors
// WCAG AA compliant: minimum 4.5:1 contrast ratio for normal text
enum NeedsReviewBadgeStyle {
    // Using black text on orange for consistent high contrast in both modes
    // Orange background with black text provides ~5.2:1 contrast ratio
    static var foreground: Color { Color.black }
    static var background: Color { Color.orange }
}

// MARK: - Data Models
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

// MARK: - Transcript Line Row
// HIG-compliant transcript row with stable layout and accessibility

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

    // HIG Fix: Using centralized threshold from DesignTokens
    private let lowConfidenceThreshold = ConfidenceThreshold.low

    var body: some View {
        let highlightMatches = EntityHighlighter.matches(in: segment.text, entities: entities, mode: highlightMode)

        // HIG: Fixed alignment to prevent jitter during streaming updates
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm + 2) {
            // Timestamp
            Text(formatTime(segment.t0))
                .font(Typography.monoSmall)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: Layout.timestampWidth, alignment: .trailing)
                .frame(height: Layout.rowMinHeight, alignment: .center)

            // Speaker Badge
            speakerBadge
                .frame(width: Layout.speakerBadgeSize, height: Layout.speakerBadgeSize, alignment: .center)

            // Content Column
            VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                EntityTextView(
                    text: segment.text,
                    matches: highlightMatches,
                    highlightsEnabled: highlightMode.isEnabled
                ) { entity in
                    onEntityClick(entity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityRepresentation {
                    EntityHighlightsAccessibilityRepresentation(
                        transcriptText: segment.text,
                        entities: accessibilityEntities(from: highlightMatches),
                        onEntityClick: onEntityClick
                    )
                }

                // Confidence Row
                HStack(spacing: Spacing.sm) {
                    Text(formatConfidence(segment.confidence))
                        .font(Typography.monoSmall)
                        .monospacedDigit()
                        .foregroundColor(confidenceColor)
                        .frame(minWidth: Layout.confidenceMinWidth, alignment: .leading)
                        .accessibilityLabel(confidenceAccessibilityLabel)

                    if segment.confidence < lowConfidenceThreshold {
                        needsReviewBadge
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Buttons
            HStack(spacing: Spacing.xs) {
                if isFocused {
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
            .frame(width: isFocused ? Layout.actionContainerWidth : 0, alignment: .trailing)
            .opacity(isFocused ? 1 : 0)
            .animation(.easeInOut(duration: AnimationDuration.quick), value: isFocused)
        }
        .padding(Spacing.sm + 2)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(rowStroke, lineWidth: isFocused ? 2 : 1)
        )
        .transaction { transaction in
            transaction.animation = .easeInOut(duration: AnimationDuration.quick)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transcriptAccessibilityLabel)
    }
    
    /// Combined accessibility label for the entire transcript row
    var transcriptAccessibilityLabel: String {
        let speaker = speakerAccessibilityLabel.replacingOccurrences(of: "Speaker: ", with: "")
        let confidence = confidenceAccessibilityLabel.replacingOccurrences(of: " percent", with: "%")
        let text = segment.text
        return "\(speaker), \(confidence): \(text)"
    }

    var speakerBadge: some View {
        let label = speakerInitial
        let accessibilityLabel = speakerAccessibilityLabel
        return Text(label)
            .font(Typography.caption)
            .fontWeight(.semibold)
            .frame(width: Layout.speakerBadgeSize, height: Layout.speakerBadgeSize)
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
    
    /// Accessibility label for confidence percentage
    /// Provides clear description for VoiceOver users instead of just color
    var confidenceAccessibilityLabel: String {
        let percentage = Int(segment.confidence * 100)
        if segment.confidence >= 0.85 {
            return "High confidence: \(percentage) percent"
        } else if segment.confidence >= 0.70 {
            return "Medium confidence: \(percentage) percent"
        } else if segment.confidence >= 0.50 {
            return "Low confidence: \(percentage) percent, review recommended"
        } else {
            return "Very low confidence: \(percentage) percent, needs review"
        }
    }

    func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(accessibilityLabel)
    }

    var rowBackground: Color {
        if isFocused {
            return BackgroundStyle.rowSelected.color(for: colorScheme)
        }
        if isPinned {
            return BackgroundStyle.rowPinned.color(for: colorScheme)
        }
        return BackgroundStyle.card.color(for: colorScheme)
    }

    var rowStroke: Color {
        if isFocused {
            return StrokeStyle.focus.color(for: colorScheme)
        }
        if isPinned {
            return StrokeStyle.pinned.color(for: colorScheme)
        }
        return StrokeStyle.standard.color(for: colorScheme)
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
        if segment.confidence >= ConfidenceThreshold.high {
            return .green
        }
        if segment.confidence >= ConfidenceThreshold.medium {
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
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.captionSmall)
            Text("Needs review")
                .font(Typography.captionSmall)
        }
        .foregroundColor(NeedsReviewBadgeStyle.foreground)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(NeedsReviewBadgeStyle.background)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(NeedsReviewBadgeStyle.foreground.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityLabel("Low confidence transcript - review recommended")
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Low confidence transcript, needs review")
    }
}

// MARK: - Accessibility Representation

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

// MARK: - Shortcut Row

struct ShortcutRow: View {
    @Environment(\.colorScheme) var colorScheme

    let label: String
    let key: String

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.caption)
            Spacer()
            Text(key)
                .font(Typography.captionSmall)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.7))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
        }
    }
}

// MARK: - Highlight Help View

struct HighlightHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(Typography.title)

            Text("Off")
                .font(Typography.subtitle)
                .fontWeight(.semibold)
            Text("No in-line entity highlighting.")
                .font(Typography.caption)
                .foregroundColor(.secondary)

            Text("Extracted")
                .font(Typography.subtitle)
                .fontWeight(.semibold)
            Text("Uses backend entities for consistent names across transcript and entity surface.")
                .font(Typography.caption)
                .foregroundColor(.secondary)

            Text("NLP")
                .font(Typography.subtitle)
                .fontWeight(.semibold)
            Text("Uses on-device Apple NLP for quick name/place/org highlighting.")
                .font(Typography.caption)
                .foregroundColor(.secondary)

            Divider()
            Text("Tip: click a highlight to filter and jump mentions.")
                .font(Typography.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Entity Detail Popover

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
                        .font(Typography.title)
                    Text(entity.type.uppercased())
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Label("\(entity.count)", systemImage: "number")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                Label("\(Int(entity.confidence * 100))%", systemImage: "checkmark.seal")
                    .font(Typography.caption)
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

// MARK: - Permission Banner

struct PermissionBanner: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if issues.isEmpty == false {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(Typography.caption)
                Text(issues.map(\.label).joined(separator: " · "))
                    .font(Typography.caption)
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
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
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

// MARK: - Audio Level Meter
// HIG Fix: Added accessibility support (A3)

struct AudioLevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(Typography.captionSmall)
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
            .frame(width: Layout.audioMeterWidth, height: Layout.audioMeterHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) audio level")
            .accessibilityValue("\(Int(level * 100)) percent")
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
