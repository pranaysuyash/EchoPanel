import SwiftUI

struct SidePanelView: View {
    @ObservedObject var appState: AppState
    let onEndSession: () -> Void
    @State private var followTranscript: Bool = true
    @State private var highlightMode: EntityHighlighter.HighlightMode = .extracted
    @State private var showHighlightHelp: Bool = false
    @State private var entityFilter: EntityItem? = nil
    @State private var selectedEntity: EntityItem? = nil
    @State private var pendingScrollTarget: UUID? = nil
    @State private var activeMentionId: UUID? = nil

    var body: some View {
        VStack(spacing: 10) {
            header
            Divider()
            HStack(alignment: .top, spacing: 12) {
                transcriptLane
                cardsLane
                entitiesLane
            }
            Divider()
            controls
        }
        .padding(12)
        .frame(minWidth: 920, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Meeting Listener")
                    .font(.title2)
                    .fontWeight(.medium)
                Text(appState.statusLine)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                PermissionBanner(appState: appState)
                
                // Gap 2 fix: Silence warning banner
                if appState.noAudioDetected {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(.orange)
                        Text(appState.silenceMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                if appState.isDebugEnabled {
                    Text(appState.permissionDebugLine)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !appState.debugLine.isEmpty {
                        Text(appState.debugLine)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Risk mitigation: Show finalizing state with spinner
                if appState.sessionState == .finalizing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text("Finalizing Session...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            
            // Audio Source Picker (v0.2)
            VStack(alignment: .trailing, spacing: 4) {
                Picker("Source", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(appState.sessionState == .listening)
                
                // Dual Level Meters
                HStack(spacing: 8) {
                    if appState.audioSource == .system || appState.audioSource == .both {
                        AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                    }
                    if appState.audioSource == .microphone || appState.audioSource == .both {
                        AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                    }
                }
            }
            
            HStack(spacing: 6) {
                StatusPill(label: appState.sessionState == .listening ? "Listening" : "Idle",
                           color: appState.sessionState == .listening ? .green : .gray)
                StatusPill(label: "Audio \(appState.audioQuality.rawValue)", color: qualityColor(appState.audioQuality))
                Text(appState.timerText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    private var transcriptLane: some View {
        LaneCard(title: "Transcript") {
            VStack(spacing: 8) {
                transcriptToolbar

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(displayTranscriptSegments) { segment in
                                TranscriptRow(
                                    segment: segment,
                                    entities: appState.entities,
                                    highlightMode: highlightMode
                                ) { clicked in
                                    selectedEntity = resolveEntity(clicked)
                                }
                                .id(segment.id)
                                .transition(.opacity)
                            }

                            if appState.transcriptSegments.isEmpty {
                                Text("Waiting for speech")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: appState.transcriptSegments.count) { _ in
                        guard followTranscript else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: pendingScrollTarget) { target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        activeMentionId = target
                        pendingScrollTarget = nil
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.transcriptSegments)
        .popover(item: $selectedEntity) { entity in
            EntityDetailPopover(
                entity: entity,
                isFiltering: entityFilter?.name.caseInsensitiveCompare(entity.name) == .orderedSame,
                onToggleFilter: {
                    if entityFilter?.name.caseInsensitiveCompare(entity.name) == .orderedSame {
                        entityFilter = nil
                    } else {
                        entityFilter = entity
                    }
                },
                onNext: { scrollToNextMention(for: entity) },
                onPrev: { scrollToPreviousMention(for: entity) }
            )
            .frame(width: 320)
            .padding(12)
        }
    }

    private var transcriptToolbar: some View {
        HStack(spacing: 10) {
            Picker("Highlights", selection: $highlightMode) {
                ForEach(EntityHighlighter.HighlightMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Button {
                showHighlightHelp.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Highlight mode help")
            .popover(isPresented: $showHighlightHelp, arrowEdge: .bottom) {
                HighlightHelpView()
                    .frame(width: 320)
                    .padding(12)
            }

            Divider().frame(height: 14)

            Toggle("Follow", isOn: $followTranscript)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            Text("Follow")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            if let filter = entityFilter {
                HStack(spacing: 6) {
                    Text(filter.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Button {
                        entityFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }

            Button {
                if let entity = selectedEntity ?? entityFilter {
                    scrollToPreviousMention(for: entity)
                }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous mention")
            .disabled((selectedEntity ?? entityFilter) == nil)

            Button {
                if let entity = selectedEntity ?? entityFilter {
                    scrollToNextMention(for: entity)
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next mention")
            .disabled((selectedEntity ?? entityFilter) == nil)
        }
    }

    private var displayTranscriptSegments: [TranscriptSegment] {
        guard let entityFilter else { return appState.transcriptSegments }
        return appState.transcriptSegments.filter { segment in
            EntityHighlighter.matches(in: segment.text, entities: [entityFilter], mode: .extracted).isEmpty == false
        }
    }

    private func resolveEntity(_ clicked: EntityItem) -> EntityItem {
        // Prefer canonical entity data (count/confidence/lastSeen) if present.
        if let found = appState.entities.first(where: { $0.name.caseInsensitiveCompare(clicked.name) == .orderedSame }) {
            return found
        }
        return clicked
    }

    private func scrollToNextMention(for entity: EntityItem) {
        let segments = displayTranscriptSegments
        guard !segments.isEmpty else { return }
        let currentIndex: Int? = {
            guard let selected = activeMentionId else { return nil }
            return segments.firstIndex(where: { $0.id == selected })
        }()

        let start = (currentIndex ?? -1) + 1
        if let idx = segments[start...].firstIndex(where: { EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false }) {
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        } else if let idx = segments.firstIndex(where: { EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false }) {
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        }
    }

    private func scrollToPreviousMention(for entity: EntityItem) {
        let segments = displayTranscriptSegments
        guard !segments.isEmpty else { return }
        let currentIndex: Int? = {
            guard let selected = activeMentionId else { return nil }
            return segments.firstIndex(where: { $0.id == selected })
        }()

        let end = (currentIndex ?? segments.count)
        if end > 0, let idx = segments[..<end].lastIndex(where: { EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false }) {
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        } else if let idx = segments.lastIndex(where: { EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false }) {
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        }
    }

    private var cardsLane: some View {
        LaneCard(title: "Cards") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    CardSection(title: "Actions") {
                        if appState.actions.isEmpty {
                            EmptyStateRow(text: "No actions yet")
                        } else {
                            ForEach(appState.actions) { item in
                                CardRow(
                                    title: item.text,
                                    meta: itemMeta(owner: item.owner, due: item.due, confidence: item.confidence)
                                )
                                .transition(.opacity)
                            }
                        }
                    }
                    CardSection(title: "Decisions") {
                        if appState.decisions.isEmpty {
                            EmptyStateRow(text: "No decisions yet")
                        } else {
                            ForEach(appState.decisions) { item in
                                CardRow(title: item.text, meta: confidenceMeta(item.confidence))
                                    .transition(.opacity)
                            }
                        }
                    }
                    CardSection(title: "Risks") {
                        if appState.risks.isEmpty {
                            EmptyStateRow(text: "No risks yet")
                        } else {
                            ForEach(appState.risks) { item in
                                CardRow(title: item.text, meta: confidenceMeta(item.confidence))
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.actions)
        .animation(.easeInOut(duration: 0.2), value: appState.decisions)
        .animation(.easeInOut(duration: 0.2), value: appState.risks)
    }

    private var entitiesLane: some View {
        LaneCard(title: "Entities") {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if appState.entities.isEmpty {
                        EmptyStateRow(text: "No entities yet")
                    } else {
                        ForEach(appState.entities) { entity in
                            Button {
                                entityFilter = entity
                                selectedEntity = entity
                                scrollToNextMention(for: entity)
                            } label: {
                                EntityRow(entity: entity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Filter transcript for \(entity.name)")
                            .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.entities)
    }

    private var controls: some View {
        HStack {
            Button {
                appState.copyMarkdownToClipboard()
            } label: {
                Label("Copy Markdown", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)

            Button {
                appState.exportJSON()
            } label: {
                Label("Export JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)

            Button {
                appState.exportMarkdown()
            } label: {
                Label("Export Markdown", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty)

            Spacer()

            Button(role: .destructive) {
                onEndSession()
            } label: {
                Label("End Session", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func qualityColor(_ quality: AudioQuality) -> Color {
        switch quality {
        case .good:
            return .green
        case .ok:
            return .orange
        case .poor:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func itemMeta(owner: String?, due: String?, confidence: Double) -> String {
        var parts: [String] = []
        if let owner, !owner.isEmpty { parts.append("Owner: \(owner)") }
        if let due, !due.isEmpty { parts.append("Due: \(due)") }
        parts.append(confidenceMeta(confidence))
        return parts.joined(separator: " · ")
    }

    private func confidenceMeta(_ value: Double) -> String {
        let base = "Confidence \(formatConfidence(value))"
        // Risk mitigation: Mark low-confidence cards as Draft
        if value < 0.5 {
            return "\(base) (Draft)"
        }
        return base
    }
}

private struct HighlightHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Off")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("No in-line entity highlighting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Extracted")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Highlights entities from the backend entity list (People/Orgs/Dates/Topics, etc.). Best for filtering and consistency with the Entities lane.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("NLP")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Uses on-device Apple NLP to highlight names in the transcript (Person/Org/Place). Helpful when the backend hasn’t extracted an entity yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider()
            Text("Tip: Click a highlight to see details, filter the transcript, and jump between mentions.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct LaneCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct PermissionBanner: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        let needsScreen = appState.audioSource == .system || appState.audioSource == .both
        let needsMic = appState.audioSource == .microphone || appState.audioSource == .both

        if (needsScreen && appState.screenRecordingPermission == .denied) || (needsMic && appState.microphonePermission == .denied) {
            VStack(alignment: .leading, spacing: 6) {
                if needsScreen && appState.screenRecordingPermission == .denied {
                    permissionRow(
                        label: "Screen Recording Not Granted",
                        url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    )
                }
                if needsMic && appState.microphonePermission == .denied {
                    permissionRow(
                        label: "Microphone Not Granted",
                        url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                }
            }
            .padding(8)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if (!needsScreen || appState.screenRecordingPermission == .authorized) && (!needsMic || appState.microphonePermission == .authorized) {
             // Optional: Show "All Systems Go" or keep minimal
             HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Ready to Capture").font(.caption2).foregroundColor(.secondary)
             }
             .padding(.horizontal, 8).padding(.vertical, 4)
             .background(Color.secondary.opacity(0.08)).clipShape(Capsule())
        }
    }
    
    private func permissionRow(label: String, url: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
            Button("Open Settings") {
                if let nsUrl = URL(string: url) {
                    NSWorkspace.shared.open(nsUrl)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment
    let entities: [EntityItem]
    let highlightMode: EntityHighlighter.HighlightMode
    let onEntityClick: (EntityItem) -> Void

    // Gap 3 fix: Threshold for flagging low-confidence segments
    private let lowConfidenceThreshold = 0.5

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(formatTime(segment.t0))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                // Gap reduction: Show speaker label if available, else infer from source tag.
                if let speaker = segment.speaker, !speaker.isEmpty {
                    Text(speaker)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                } else if let source = segment.source {
                    let isMic = source == "microphone" || source == "mic"
                    Text(isMic ? "You" : "System")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(isMic ? .blue : .purple)
                }
                
                EntityTextView(
                    text: segment.text,
                    matches: EntityHighlighter.matches(in: segment.text, entities: entities, mode: highlightMode),
                    highlightsEnabled: highlightMode.isEnabled
                ) { entity in
                    onEntityClick(entity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 6) {
                    Text(formatConfidence(segment.confidence))
                        .font(.caption2)
                        .foregroundColor(confidenceColor)
                    
                    // Gap 3 fix: Show "Needs review" label for low-confidence
                    if segment.confidence < lowConfidenceThreshold {
                        Text("Needs review")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    private var textColor: Color {
        if !segment.isFinal {
            return .secondary
        }
        if segment.confidence < lowConfidenceThreshold {
            return .orange
        }
        return .primary
    }
    
    private var confidenceColor: Color {
        if segment.confidence >= 0.8 {
            return .green
        } else if segment.confidence >= 0.5 {
            return .secondary
        } else {
            return .orange
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct EntityDetailPopover: View {
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

                Spacer()

                Button {
                    onPrev()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)

                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct CardRow: View {
    let title: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
            Text(meta)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct EntityRow: View {
    let entity: EntityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entity.name)
                .font(.footnote)
            Text(entity.type.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            if entity.count > 1 {
                Text("×\(entity.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            }
            Text("Last seen \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

private struct EmptyStateRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// v0.2: Audio Level Meter
private struct AudioLevelMeter: View {
    let label: String
    let level: Float // 0.0 to 1.0 (EMA)
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    
                    // Level bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor)
                        .frame(width: max(2, CGFloat(level) * geometry.size.width))
                }
            }
            .frame(width: 60, height: 6)
        }
    }
    
    private var levelColor: Color {
        if level > 0.8 {
            return .red // Clipping
        } else if level > 0.3 {
            return .green // Good level
        } else {
            return .yellow // Low level
        }
    }
}
