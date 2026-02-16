import AppKit
import SwiftUI

// MARK: - Transcript Surfaces Extension
// HIG-compliant transcript scroller, toolbar, and surface overlays

extension SidePanelView {

    // MARK: - Transcript Scroller
    func transcriptScroller(style: TranscriptStyle) -> some View {
        transcriptScrollerBody(style: style)
        .accessibilityLabel("Transcript, \(visibleTranscriptSegments.count) segments")
        .accessibilityElement(children: .contain)
        .accessibilityRotor("Transcript Segments") {
            ForEach(visibleTranscriptSegments) { segment in
                AccessibilityRotorEntry(transcriptRotorLabel(for: segment), id: segment.id)
            }
        }
        .popover(item: $transcriptUI.selectedEntity) { entity in
            EntityDetailPopover(
                entity: entity,
                isFiltering: transcriptUI.entityFilter?.name.caseInsensitiveCompare(entity.name) == .orderedSame,
                onToggleFilter: {
                    if transcriptUI.entityFilter?.name.caseInsensitiveCompare(entity.name) == .orderedSame {
                        transcriptUI.entityFilter = nil
                    } else {
                        transcriptUI.entityFilter = entity
                    }
                },
                onNext: { scrollToNextMention(for: entity) },
                onPrev: { scrollToPreviousMention(for: entity) }
            )
            .frame(width: 320)
            .padding(Spacing.md)
        }
    }

    private func transcriptScrollerBody(style: TranscriptStyle) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                transcriptRows(style: style)
            }
            .onChange(of: transcriptUI.pendingScrollTarget) { target in
                guard let target else { return }
                performAnimatedUpdate {
                    proxy.scrollTo(target, anchor: .center)
                }
                transcriptUI.pendingScrollTarget = nil
            }
            .onChange(of: transcriptUI.scrollToBottomToken) { _ in
                guard let last = visibleTranscriptSegments.last?.id else { return }
                performAnimatedUpdate {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func transcriptRows(style: TranscriptStyle) -> some View {
        let spacing = ViewModeSpacing(from: style)
        
        // VNI: Use timeline items for Roll/Compact modes to show voice note markers
        if style == .full {
            // Full mode uses only transcript segments
            return fullTranscriptRows(style: style, spacing: spacing)
        } else {
            // Roll/Compact modes use timeline items (transcript + voice notes)
            return timelineRows(style: style, spacing: spacing)
        }
    }
    
    private func fullTranscriptRows(style: TranscriptStyle, spacing: ViewModeSpacing) -> some View {
        LazyVStack(alignment: .leading, spacing: spacing.rowSpacing) {
            if visibleTranscriptSegments.isEmpty {
                emptyTranscriptState
            } else {
                ForEach(Array(visibleTranscriptSegments.enumerated()), id: \.element.id) { index, segment in
                    transcriptRow(segment: segment)
                        .id(segment.id)
                        .transaction { transaction in
                            if appState.sessionState == .listening && !transcriptUI.followLive {
                                transaction.animation = nil
                            }
                        }
                }
            }
        }
        .padding(.vertical, spacing.verticalPadding)
        .padding(.horizontal, spacing.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .gesture(
            DragGesture(minimumDistance: 3).onChanged { _ in
                if transcriptUI.followLive {
                    transcriptUI.followLive = false
                }
            }
        )
    }
    
    private func timelineRows(style: TranscriptStyle, spacing: ViewModeSpacing) -> some View {
        let items = visibleTimelineItems
        
        return LazyVStack(alignment: .leading, spacing: spacing.rowSpacing) {
            if items.isEmpty {
                emptyTranscriptState
            } else {
                ForEach(items) { item in
                    timelineRow(item: item, style: style)
                        .transaction { transaction in
                            if appState.sessionState == .listening && !transcriptUI.followLive {
                                transaction.animation = nil
                            }
                        }
                }
            }
        }
        .padding(.vertical, spacing.verticalPadding)
        .padding(.horizontal, spacing.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .gesture(
            DragGesture(minimumDistance: 3).onChanged { _ in
                if transcriptUI.followLive {
                    transcriptUI.followLive = false
                }
            }
        )
    }
    
    private func timelineRow(item: TimelineItem, style: TranscriptStyle) -> some View {
        switch item {
        case .transcript(let segment):
            return transcriptRow(segment: segment)
        case .voiceNote(let note):
            return voiceNoteMarker(note: note, style: style)
        }
    }
    
    private func voiceNoteMarker(note: VoiceNote, style: TranscriptStyle) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp badge
            Text(formatTime(note.startTime))
                .font(Typography.captionSmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(Capsule())
            
            // Voice note card
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Voice Note")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                Text(note.text)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(style == .compact ? 1 : 3)
            }
            .padding(8)
            .background(BackgroundStyle.card.color(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .onTapGesture {
            appState.currentVoiceNote = note
        }
        .accessibilityLabel("Voice note: \(note.text)")
    }
                        }
                }
            }
        }
        .padding(.vertical, spacing.verticalPadding)
        .padding(.horizontal, spacing.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .gesture(
            DragGesture(minimumDistance: 3).onChanged { _ in
                if transcriptUI.followLive {
                    transcriptUI.followLive = false
                }
            }
        )
    }

    private func transcriptRow(segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TranscriptLineRow(
                segment: segment,
                entities: appState.entities,
                highlightMode: highlightMode,
                isFocused: transcriptUI.focusedSegmentID == segment.id,
                isPinned: transcriptUI.pinnedSegmentIDs.contains(segment.id),
                onPin: {
                    transcriptUI.focusedSegmentID = segment.id
                    togglePin(segment.id)
                },
                onLens: {
                    transcriptUI.focusedSegmentID = segment.id
                    toggleLens(segment.id)
                },
                onJump: {
                    transcriptUI.focusedSegmentID = segment.id
                    jumpToLive()
                },
                onEntityClick: { clicked in
                    transcriptUI.selectedEntity = resolveEntity(clicked)
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .onTapGesture {
                transcriptUI.focusedSegmentID = segment.id
                if transcriptUI.followLive {
                    transcriptUI.followLive = false
                }
            }
            .onTapGesture(count: 2) {
                transcriptUI.focusedSegmentID = segment.id
                if transcriptUI.followLive {
                    transcriptUI.followLive = false
                }
                toggleLens(segment.id)
            }

            if transcriptUI.lensSegmentID == segment.id {
                focusLens(segment: segment)
            }
        }
    }

    // MARK: - Footer Controls
    func footerControls(panelWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            // Expanded layout
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.copyMarkdownToClipboard()
                } label: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(exportDisabled)

                Button {
                    appState.exportJSON()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportDisabled)

                Button {
                    appState.exportMarkdown()
                } label: {
                    Label("Export Markdown", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(exportDisabled)

                Menu {
                    Button("Export SRT") { appState.exportSRT() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                    Button("Export WebVTT") { appState.exportWebVTT() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                } label: {
                    Image(systemName: "captions.bubble")
                }
                .menuStyle(.borderlessButton)
                .help("Caption exports (SRT/WebVTT)")
                .disabled(exportDisabled)

                Spacer()

                Button(role: .destructive) {
                    onEndSession()
                } label: {
                    Label("End Session", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            // Compact layout
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.copyMarkdownToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy Markdown")
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(exportDisabled)

                Menu {
                    Button("Export JSON") { appState.exportJSON() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                    Button("Export Markdown") { appState.exportMarkdown() }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                    Divider()
                    Button("Export SRT") { appState.exportSRT() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                    Button("Export WebVTT") { appState.exportWebVTT() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .disabled(exportDisabled)

                Spacer()

                Menu {
                    Button("Export SRT") { appState.exportSRT() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                    Button("Export WebVTT") { appState.exportWebVTT() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .disabled(exportDisabled)
                } label: {
                    Image(systemName: "captions.bubble")
                }
                .menuStyle(.borderlessButton)
                .help("Caption exports (SRT/WebVTT)")
                .disabled(exportDisabled)

                Button(role: .destructive) {
                    onEndSession()
                } label: {
                    Label(panelWidth < 380 ? "End" : "End Session", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Transcript Toolbar
    func transcriptToolbar(panelWidth: CGFloat, showSurfaceButtons: Bool) -> some View {
        let pickerCap: CGFloat = viewMode == .compact ? 190 : 250
        let pickerWidth = min(max(panelWidth * 0.4, 150), pickerCap)

        return ViewThatFits(in: .horizontal) {
            toolbarRowLayout(
                pickerWidth: pickerWidth,
                compactStack: false,
                showSurfaceButtons: showSurfaceButtons
            )

            toolbarRowLayout(
                pickerWidth: min(max(panelWidth - 90, 150), pickerCap),
                compactStack: true,
                showSurfaceButtons: showSurfaceButtons
            )
        }
    }

    @ViewBuilder
    func toolbarRowLayout(pickerWidth: CGFloat, compactStack: Bool, showSurfaceButtons: Bool) -> some View {
        if compactStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                toolbarPickerAndInfo(pickerWidth: pickerWidth, fillsWidth: true)
                toolbarTrailingControls(showSurfaceButtons: showSurfaceButtons)
            }
        } else {
            HStack(spacing: Spacing.md) {
                toolbarPickerAndInfo(pickerWidth: pickerWidth, fillsWidth: false)
                toolbarTrailingControls(showSurfaceButtons: showSurfaceButtons)
            }
        }
    }

    func toolbarPickerAndInfo(pickerWidth: CGFloat, fillsWidth: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Picker("", selection: $highlightMode) {
                ForEach(EntityHighlighter.HighlightMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: fillsWidth ? .infinity : pickerWidth)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Highlights")

            Button {
                showHighlightHelp.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showHighlightHelp, arrowEdge: .bottom) {
                HighlightHelpView()
                    .frame(width: 320)
                    .padding(Spacing.md)
            }
        }
    }

    func toolbarTrailingControls(showSurfaceButtons: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            if let filter = transcriptUI.entityFilter {
                HStack(spacing: 5) {
                    Text(filter.name)
                        .font(Typography.captionSmall)
                    Button {
                        transcriptUI.entityFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear entity filter")
                    .accessibilityHint("Shows all transcript lines.")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.14))
                .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            if !transcriptUI.followLive {
                Button {
                    jumpToLive()
                } label: {
                    if transcriptUI.pendingNewSegments > 0 {
                        Text("Jump Live (\(transcriptUI.pendingNewSegments))")
                    } else {
                        Text("Jump Live")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if showSurfaceButtons {
                Menu("Surface") {
                    ForEach(Surface.allCases) { surface in
                        Button(surface.rawValue) {
                            activeSurface = surface
                            if viewMode == .full {
                                showSurfaceOverlay = false
                            } else {
                                showSurfaceOverlay = true
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Choose insight surface")
            }
        }
    }

    // MARK: - Surface Overlay
    var surfaceOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text(activeSurface.rawValue)
                    .font(Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("←/→ cycle · Esc close")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
                Button {
                    showSurfaceOverlay = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            .padding(Spacing.sm + 2)
            .background(BackgroundStyle.container.color(for: colorScheme))

            Divider()

            surfaceContent(surface: activeSurface)
                .padding(Spacing.sm + 2)
                .background(BackgroundStyle.container.color(for: colorScheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
        .padding(Spacing.sm)
        .transition(.opacity)
    }

    // MARK: - Surface Content
    @ViewBuilder
    func surfaceContent(surface: Surface) -> some View {
        if surface == .raw {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
        } else if surface == .summary {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
                // Non-transcript rotor channels for fast navigation within insight surfaces.
                .accessibilityRotor("Summary Items") {
                    ForEach(surfaceSummaryItems) { item in
                        AccessibilityRotorEntry(
                            "\(item.tag). \(rotorPreview(item.title))",
                            id: item.id
                        )
                    }
                }
        } else if surface == .actions {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
                .accessibilityRotor("Actions") {
                    ForEach(appState.actions) { action in
                        AccessibilityRotorEntry("Action. \(rotorPreview(action.text))", id: action.id)
                    }
                }
                .accessibilityRotor("Risks") {
                    ForEach(appState.risks) { risk in
                        AccessibilityRotorEntry("Risk. \(rotorPreview(risk.text))", id: risk.id)
                    }
                }
        } else if surface == .pins {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
                .accessibilityRotor("Pins") {
                    ForEach(pinnedSegments) { segment in
                        AccessibilityRotorEntry(
                            "Pin. \(formatTime(segment.t0)) \(speakerLabel(for: segment)). \(rotorPreview(segment.text))",
                            id: segment.id
                        )
                    }
                }
        } else if surface == .entities {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
                .accessibilityRotor("Entities") {
                    ForEach(appState.entities) { entity in
                        AccessibilityRotorEntry(
                            "Entity. \(entity.type.uppercased()) \(entity.name). Count \(entity.count).",
                            id: entity.id
                        )
                    }
                }
        } else {
            surfaceContentBody(surface: surface)
                .accessibilityLabel("\(surface.rawValue) surface")
                .accessibilityElement(children: .contain)
        }
    }

    private func surfaceContentBody(surface: Surface) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm + 2) {
                switch surface {
                case .summary:
                    if surfaceSummaryItems.isEmpty {
                        surfaceEmptyState(text: "Summary will appear as decisions and actions emerge.")
                    } else {
                        ForEach(surfaceSummaryItems) { item in
                            surfaceItemCard(tag: item.tag, title: item.title, subtitle: item.subtitle)
                                .id(item.id)
                        }
                    }

                case .actions:
                    if appState.actions.isEmpty && appState.risks.isEmpty {
                        surfaceEmptyState(text: "No actions or risks yet.")
                    } else {
                        ForEach(appState.actions) { action in
                            surfaceItemCard(
                                tag: "Action",
                                title: action.text,
                                subtitle: itemMeta(owner: action.owner, due: action.due, confidence: action.confidence)
                            )
                            .id(action.id)
                        }
                        ForEach(appState.risks) { risk in
                            surfaceItemCard(
                                tag: "Risk",
                                title: risk.text,
                                subtitle: confidenceMeta(risk.confidence)
                            )
                            .id(risk.id)
                        }
                    }

                case .pins:
                    if pinnedSegments.isEmpty {
                        surfaceEmptyState(text: "No pins yet. Focus a line and press P.")
                    } else {
                        ForEach(pinnedSegments) { segment in
                            Button {
                                transcriptUI.focusedSegmentID = segment.id
                                transcriptUI.lensSegmentID = segment.id
                                transcriptUI.followLive = false
                                showSurfaceOverlay = false
                                transcriptUI.pendingScrollTarget = segment.id
                            } label: {
                                surfaceItemCard(
                                    tag: "Pin",
                                    title: segment.text,
                                    subtitle: "\(formatTime(segment.t0)) · \(speakerLabel(for: segment))"
                                )
                            }
                            .id(segment.id)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open pinned transcript line")
                            .accessibilityHint("Moves focus to this pinned line in the transcript.")
                        }
                    }

                case .entities:
                    if appState.entities.isEmpty {
                        surfaceEmptyState(text: "No entities detected yet.")
                    } else {
                        ForEach(appState.entities) { entity in
                            Button {
                                transcriptUI.entityFilter = entity
                                transcriptUI.followLive = false
                            } label: {
                                surfaceItemCard(
                                    tag: entity.type.uppercased(),
                                    title: entity.name,
                                    subtitle: "Count \(entity.count) · Last \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))"
                                )
                            }
                            .id(entity.id)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Filter by entity \(entity.name)")
                            .accessibilityHint("Shows transcript lines that mention this entity.")
                        }
                    }

                case .raw:
                    VStack(alignment: .leading, spacing: Spacing.sm + 2) {
                        Button("Copy Raw") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rawTranscriptText, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Copy raw transcript text")
                        .accessibilityHint("Copies the full transcript in plain text.")

                        Text(rawTranscriptText)
                            .font(Typography.mono)
                            .textSelection(.enabled)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BackgroundStyle.card.color(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
                    }
                }
            }
        }
    }

    private func rotorPreview(_ text: String, limit: Int = 72) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func transcriptRotorLabel(for segment: TranscriptSegment) -> String {
        let preview = String(segment.text.prefix(48))
        return "\(formatTime(segment.t0)) \(speakerLabel(for: segment)): \(preview)"
    }
}

// MARK: - ViewModeSpacing Helper
extension ViewModeSpacing {
    init(from style: SidePanelView.TranscriptStyle) {
        switch style {
        case .roll:
            self = .roll
        case .compact:
            self = .compact
        case .full:
            self = .full
        }
    }
}
