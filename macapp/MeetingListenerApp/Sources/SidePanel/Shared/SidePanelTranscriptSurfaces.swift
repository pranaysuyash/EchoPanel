import AppKit
import SwiftUI

extension SidePanelView {
    func transcriptScroller(style: TranscriptStyle) -> some View {
        transcriptScrollerBody(style: style)
        .accessibilityLabel("Transcript, \(visibleTranscriptSegments.count) segments")
        .accessibilityElement(children: .contain)
        .accessibilityRotor("Transcript Segments") {
            ForEach(visibleTranscriptSegments) { segment in
                AccessibilityRotorEntry(transcriptRotorLabel(for: segment), id: segment.id)
            }
        }
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

    private func transcriptScrollerBody(style: TranscriptStyle) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                transcriptRows(style: style)
            }
            .onChange(of: pendingScrollTarget) { target in
                guard let target else { return }
                performAnimatedUpdate {
                    proxy.scrollTo(target, anchor: .center)
                }
                pendingScrollTarget = nil
            }
            .onChange(of: scrollToBottomToken) { _ in
                guard let last = visibleTranscriptSegments.last?.id else { return }
                performAnimatedUpdate {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func transcriptRows(style: TranscriptStyle) -> some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if visibleTranscriptSegments.isEmpty {
                emptyTranscriptState
            } else {
                ForEach(visibleTranscriptSegments) { segment in
                    transcriptRow(segment: segment)
                        .id(segment.id)
                }
            }
        }
        .padding(.vertical, style.verticalPadding)
        .padding(.horizontal, style.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gesture(
            DragGesture(minimumDistance: 3).onChanged { _ in
                if followLive {
                    followLive = false
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
                isFocused: focusedSegmentID == segment.id,
                isPinned: pinnedSegmentIDs.contains(segment.id),
                onPin: {
                    focusedSegmentID = segment.id
                    togglePin(segment.id)
                },
                onLens: {
                    focusedSegmentID = segment.id
                    toggleLens(segment.id)
                },
                onJump: {
                    focusedSegmentID = segment.id
                    jumpToLive()
                },
                onEntityClick: { clicked in
                    selectedEntity = resolveEntity(clicked)
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                focusedSegmentID = segment.id
                if followLive {
                    followLive = false
                }
            }
            .onTapGesture(count: 2) {
                focusedSegmentID = segment.id
                if followLive {
                    followLive = false
                }
                toggleLens(segment.id)
            }

            if lensSegmentID == segment.id {
                focusLens(segment: segment)
            }
        }
    }

    func footerControls(panelWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
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

                Spacer()

                Button(role: .destructive) {
                    onEndSession()
                } label: {
                    Label("End Session", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            HStack(spacing: 8) {
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
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .disabled(exportDisabled)

                Spacer()

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
            VStack(alignment: .leading, spacing: 8) {
                toolbarPickerAndInfo(pickerWidth: pickerWidth, fillsWidth: true)
                toolbarTrailingControls(showSurfaceButtons: showSurfaceButtons)
            }
        } else {
            HStack(spacing: 10) {
                toolbarPickerAndInfo(pickerWidth: pickerWidth, fillsWidth: false)
                toolbarTrailingControls(showSurfaceButtons: showSurfaceButtons)
            }
        }
    }

    func toolbarPickerAndInfo(pickerWidth: CGFloat, fillsWidth: Bool) -> some View {
        HStack(spacing: 10) {
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
                    .padding(12)
            }
        }
    }

    func toolbarTrailingControls(showSurfaceButtons: Bool) -> some View {
        HStack(spacing: 10) {
            if let filter = entityFilter {
                HStack(spacing: 5) {
                    Text(filter.name)
                        .font(.caption2)
                    Button {
                        entityFilter = nil
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

            if !followLive {
                Button {
                    jumpToLive()
                } label: {
                    if pendingNewSegments > 0 {
                        Text("Jump Live (\(pendingNewSegments))")
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

    var surfaceOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text(activeSurface.rawValue)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("←/→ cycle · Esc close")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    showSurfaceOverlay = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(contentBackgroundColor)

            Divider()

            surfaceContent(surface: activeSurface)
                .padding(10)
                .background(contentBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .padding(8)
        .transition(.opacity)
    }

    func surfaceContent(surface: Surface) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch surface {
                case .summary:
                    if surfaceSummaryItems.isEmpty {
                        surfaceEmptyState(text: "Summary will appear as decisions and actions emerge.")
                    } else {
                        ForEach(surfaceSummaryItems) { item in
                            surfaceItemCard(tag: item.tag, title: item.title, subtitle: item.subtitle)
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
                        }
                        ForEach(appState.risks) { risk in
                            surfaceItemCard(
                                tag: "Risk",
                                title: risk.text,
                                subtitle: confidenceMeta(risk.confidence)
                            )
                        }
                    }

                case .pins:
                    if pinnedSegments.isEmpty {
                        surfaceEmptyState(text: "No pins yet. Focus a line and press P.")
                    } else {
                        ForEach(pinnedSegments) { segment in
                            Button {
                                focusedSegmentID = segment.id
                                lensSegmentID = segment.id
                                followLive = false
                                showSurfaceOverlay = false
                                pendingScrollTarget = segment.id
                            } label: {
                                surfaceItemCard(
                                    tag: "Pin",
                                    title: segment.text,
                                    subtitle: "\(formatTime(segment.t0)) · \(speakerLabel(for: segment))"
                                )
                            }
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
                                entityFilter = entity
                                followLive = false
                            } label: {
                                surfaceItemCard(
                                    tag: entity.type.uppercased(),
                                    title: entity.name,
                                    subtitle: "Count \(entity.count) · Last \(formatTime(entity.lastSeen)) · \(formatConfidence(entity.confidence))"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Filter by entity \(entity.name)")
                            .accessibilityHint("Shows transcript lines that mention this entity.")
                        }
                    }

                case .raw:
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Copy Raw") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rawTranscriptText, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Copy raw transcript text")
                        .accessibilityHint("Copies the full transcript in plain text.")

                        Text(rawTranscriptText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func transcriptRotorLabel(for segment: TranscriptSegment) -> String {
        let preview = String(segment.text.prefix(48))
        return "\(formatTime(segment.t0)) \(speakerLabel(for: segment)): \(preview)"
    }
}
