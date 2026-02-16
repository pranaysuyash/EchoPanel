import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Full View Mode
// HIG-compliant implementation with capture bar and consistent styling

extension SidePanelView {
    func fullRenderer(panelWidth: CGFloat) -> some View {
        let stackedInsight = panelWidth < 1240
        let railWidth = min(max(panelWidth * 0.22, 220), 260)
        let insightWidth = min(max(panelWidth * 0.27, 300), 390)

        return VStack(spacing: Spacing.sm + 2) {  // 10pt spacing
            // HIG Fix: Added capture bar for audio controls (F2)
            fullCaptureBar(panelWidth: panelWidth)
                .accessibilitySortPriority(Accessibility.SortPriority.chrome)

            fullTopChrome(panelWidth: panelWidth)
                .accessibilitySortPriority(Accessibility.SortPriority.chrome)

            if stackedInsight {
                HStack(alignment: .top, spacing: Spacing.sm + 2) {
                    fullSessionRail
                        .frame(width: railWidth)
                        .accessibilitySortPriority(Accessibility.SortPriority.navigation)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilitySortPriority(Accessibility.SortPriority.content)
                }

                fullInsightPanel
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .accessibilitySortPriority(Accessibility.SortPriority.secondary)
            } else {
                HStack(alignment: .top, spacing: Spacing.sm + 2) {
                    fullSessionRail
                        .frame(width: railWidth)
                        .accessibilitySortPriority(Accessibility.SortPriority.navigation)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilitySortPriority(Accessibility.SortPriority.content)

                    fullInsightPanel
                        .frame(width: insightWidth, alignment: .topLeading)
                        .accessibilitySortPriority(Accessibility.SortPriority.secondary)
                }
            }

            fullTimelineStrip
                .accessibilitySortPriority(Accessibility.SortPriority.footer)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Capture Bar (HIG Fix: Added for F2)
    func fullCaptureBar(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 560

        return VStack(spacing: Spacing.sm) {
            if stacked {
                // Stacked layout for narrow widths
                Picker("Audio source", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appState.sessionState == .listening)
                .accessibilityLabel("Audio source")

                HStack(spacing: Spacing.md) {
                    Toggle("Follow Live", isOn: $transcriptUI.followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live transcript")

                    Spacer()

                    qualityChip

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts help")
                }
            } else {
                // Horizontal layout for wider widths
                HStack(spacing: Spacing.md) {
                    Picker("Audio source", selection: $appState.audioSource) {
                        ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(appState.sessionState == .listening)
                    .accessibilityLabel("Audio source")
                    .layoutPriority(1)

                    Toggle("Follow Live", isOn: $transcriptUI.followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live transcript")

                    Spacer()

                    qualityChip

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts help")
                }
            }

            // Audio level meters and diagnostics
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) {
                    if appState.audioSource == .system || appState.audioSource == .both {
                        AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                            .accessibilityLabel("System audio level \(Int(appState.systemAudioLevel * 100)) percent")
                    }
                    if appState.audioSource == .microphone || appState.audioSource == .both {
                        AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                            .accessibilityLabel("Microphone level \(Int(appState.microphoneAudioLevel * 100)) percent")
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        if appState.audioSource == .system || appState.audioSource == .both {
                            AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                        }
                        if appState.audioSource == .microphone || appState.audioSource == .both {
                            AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                        }
                    }
                }
            }

            if let hint = appState.sourceTroubleshootingHint {
                Text(hint)
                    .font(Typography.captionSmall)
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .accessibilityLabel("Audio troubleshooting: \(hint)")
            } else {
                Text(appState.captureRouteDescription)
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(Spacing.sm + 2)  // 10pt padding
        .background(BackgroundStyle.control.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    var fullTranscriptColumn: some View {
        VStack(spacing: Spacing.sm) {
            fullMainHeader
            transcriptScroller(style: .full)
                .background(BackgroundStyle.container.color(for: colorScheme))
                // HIG Fix: Standardized corner radius
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if !transcriptUI.followLive {
                        // HIG Fix: Standardized button label
                        Button("Jump Live") {
                            jumpToLive()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(Spacing.sm + 2)
                        .accessibilityLabel("Jump to live transcript")
                        .accessibilityHint("Moves focus to the latest transcript line. Press J to activate.")
                    }
                }
        }
    }

    func fullTopChrome(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 1080
        let pickerWidth = min(max(panelWidth * 0.24, 190), 240)

        return VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm + 2) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EchoPanel")
                            .font(Typography.title)
                        Text("Live transcript, memory pins, and decision beads")
                            .font(Typography.captionSmall)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: Spacing.sm)

                if !stacked {
                    Picker("Work mode", selection: $fullWorkMode) {
                        ForEach(FullWorkMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: pickerWidth)
                    .accessibilityLabel("Work mode")
                }
            }

            if stacked {
                Picker("Work mode", selection: $fullWorkMode) {
                    ForEach(FullWorkMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Work mode")
            }
        }
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    var fullSessionRail: some View {
        VStack(alignment: .leading, spacing: Spacing.sm + 2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                searchTextField
            }
            .padding(Spacing.sm)
            .background(BackgroundStyle.input.color(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous)
                    .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
            )

            HStack {
                Text("Sessions")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(fullSessionItems.count)")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(fullSessionItems) { session in
                        Button {
                            selectedSessionID = session.id
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(session.name)
                                        .font(Typography.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    if session.isLive {
                                        Text("Live")
                                            .font(Typography.captionSmall)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(session.when) · \(session.duration)")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.secondary)
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedSessionID == session.id ?
                                    Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.16) :
                                    BackgroundStyle.control.color(for: colorScheme)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(session.name)")
                        .accessibilityHint("Loads transcript and insights for this session.")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                Text("↑/↓ focus · Enter lens · P pin")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
                Text("Space follow · J live · ? help · Cmd+K search")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BackgroundStyle.control.color(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
        }
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    var fullMainHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSessionTitle)
                        .font(Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(fullSessionMeta)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(speakerChips) { speaker in
                        Button {
                            transcriptUI.fullSearchQuery = speaker.searchToken
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(speaker.color)
                                    .frame(width: 6, height: 6)
                                Text(speaker.label)
                                    .font(Typography.captionSmall)
                                Text("\(speaker.count)")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BackgroundStyle.control.color(for: colorScheme))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filter transcript by speaker \(speaker.label)")
                        .accessibilityHint("Shows transcript lines for this speaker.")
                    }
                }
            }
        }
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    var fullInsightPanel: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("Insight Surface")
                    .font(Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(fullWorkMode.rawValue)
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
            }

            Picker("Insight tab", selection: $fullInsightTab) {
                ForEach(FullInsightTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Insight tab")

            Group {
                if fullInsightTab == .context {
                    fullContextPanel
                } else if let mapped = fullInsightTab.mapsToSurface {
                    surfaceContent(surface: mapped)
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.sm + 2)
            .background(BackgroundStyle.container.color(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
            )
        }
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    var fullContextPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm + 2) {
                surfaceItemCard(
                    tag: "Context",
                    title: "Local context library",
                    subtitle: "Index documents, query snippets, and keep retrieval local."
                )

                HStack(spacing: Spacing.sm) {
                    TextField("Query local context", text: $appState.contextQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appState.queryContextDocuments()
                        }

                    Button("Search") {
                        appState.queryContextDocuments()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.contextBusy)
                }

                HStack(spacing: Spacing.sm) {
                    Button("Upload Document...") {
                        pickContextFileForIndexing()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.contextBusy)

                    Button("Refresh") {
                        appState.refreshContextDocuments(force: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.contextBusy)

                    if appState.contextBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !appState.contextStatusMessage.isEmpty {
                    Text(appState.contextStatusMessage)
                        .font(Typography.captionSmall)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if appState.contextDocuments.isEmpty {
                    surfaceEmptyState(text: "No indexed documents yet. Upload a local text/markdown/json/csv file.")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Indexed Documents")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(appState.contextDocuments) { doc in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.title)
                                            .font(.footnote)
                                        Text("\(doc.chunkCount) chunks · \(doc.source)")
                                            .font(Typography.captionSmall)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        appState.deleteContextDocument(documentID: doc.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete document")
                                }
                                if !doc.preview.isEmpty {
                                    Text(doc.preview)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .id(doc.id)
                            .padding(Spacing.sm + 2)
                            .background(BackgroundStyle.control.color(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md + 1, style: .continuous))
                        }
                    }
                }

                if !appState.contextQueryResults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Matches")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(appState.contextQueryResults) { result in
                            surfaceItemCard(
                                tag: String(format: "Score %.2f", result.score),
                                title: "\(result.title) · chunk \(result.chunkIndex + 1)",
                                subtitle: result.snippet
                            )
                            .id(result.id)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        // Non-transcript rotor channels for navigating context surfaces quickly.
        .accessibilityRotor("Indexed Documents") {
            ForEach(appState.contextDocuments) { doc in
                AccessibilityRotorEntry("Document. \(doc.title)", id: doc.id)
            }
        }
        .accessibilityRotor("Context Matches") {
            ForEach(appState.contextQueryResults) { result in
                AccessibilityRotorEntry(
                    "Match. \(result.title). Score \(String(format: "%.2f", result.score)).",
                    id: result.id
                )
            }
        }
        .onAppear {
            appState.refreshContextDocuments()
        }
    }

    private func pickContextFileForIndexing() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,
            .utf8PlainText,
            .text,
            .commaSeparatedText,
            .json,
            .sourceCode,
        ]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appState.indexContextDocument(from: url)
        }
    }

    // MARK: - Timeline Strip (HIG Fix: Added accessibility)
    var fullTimelineStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Timeline")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(timelineReadoutText)
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
                    .accessibilityLabel(timelineReadoutText)
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.5 : 0.3))
                    .frame(height: 6)

                HStack(spacing: 0) {
                    ForEach(decisionBeadPositions, id: \.self) { position in
                        Circle()
                            .fill(Color.orange.opacity(0.75))
                            .frame(width: 7, height: 7)
                            .offset(x: CGFloat(position) * 6)
                            .accessibilityHidden(true)  // Beads are decorative
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 4)

                Slider(
                    value: Binding(
                        get: { timelinePosition },
                        set: { newValue in
                            timelinePosition = newValue
                            focusFromTimeline(position: newValue)
                        }
                    ),
                    in: 0...1
                )
                .opacity(0.9)
                .accessibilityLabel("Timeline scrubber")
                .accessibilityValue(timelineReadoutText)
                .accessibilityHint("Drag to navigate through transcript history")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        timelinePosition = min(1, timelinePosition + 0.05)
                    case .decrement:
                        timelinePosition = max(0, timelinePosition - 0.05)
                    default:
                        break
                    }
                    focusFromTimeline(position: timelinePosition)
                }
            }
        }
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var searchTextField: some View {
        if #available(macOS 14.0, *) {
            TextField("Search sessions, speakers, keywords", text: $transcriptUI.fullSearchQuery)
                .textFieldStyle(.plain)
                .focused($fullSearchFocused)
                .accessibilityLabel("Search sessions, speakers, and keywords")
                .onKeyPress(.escape) {
                    transcriptUI.fullSearchQuery = ""
                    fullSearchFocused = false
                    return .handled
                }
                // macOS-standard Escape behavior for search fields.
                .onExitCommand {
                    transcriptUI.fullSearchQuery = ""
                    fullSearchFocused = false
                }
        } else {
            TextField("Search sessions, speakers, keywords", text: $transcriptUI.fullSearchQuery)
                .textFieldStyle(.plain)
                .focused($fullSearchFocused)
                .accessibilityLabel("Search sessions, speakers, and keywords")
                // macOS 13: still provide Escape-to-clear behavior via exit command.
                .onExitCommand {
                    transcriptUI.fullSearchQuery = ""
                    fullSearchFocused = false
                }
        }
    }
}
