import AppKit
import SwiftUI

extension SidePanelView {
    func fullRenderer(panelWidth: CGFloat) -> some View {
        let stackedInsight = panelWidth < 1240
        let railWidth = min(max(panelWidth * 0.22, 220), 260)
        let insightWidth = min(max(panelWidth * 0.27, 300), 390)

        return VStack(spacing: 10) {
            fullTopChrome(panelWidth: panelWidth)
                .accessibilitySortPriority(500)

            if stackedInsight {
                HStack(alignment: .top, spacing: 10) {
                    fullSessionRail
                        .frame(width: railWidth)
                        .accessibilitySortPriority(400)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilitySortPriority(300)
                }

                fullInsightPanel
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                    .accessibilitySortPriority(200)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    fullSessionRail
                        .frame(width: railWidth)
                        .accessibilitySortPriority(400)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilitySortPriority(300)

                    fullInsightPanel
                        .frame(width: insightWidth, alignment: .topLeading)
                        .accessibilitySortPriority(200)
                }
            }

            fullTimelineStrip
                .accessibilitySortPriority(100)
        }
        .frame(maxHeight: .infinity)
    }

    var fullTranscriptColumn: some View {
        VStack(spacing: 8) {
            fullMainHeader
            transcriptScroller(style: .full)
                .background(contentBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if !followLive {
                        Button("LIVE · J") {
                            jumpToLive()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(10)
                        .accessibilityLabel("Jump to live transcript")
                        .accessibilityHint("Moves focus to the latest transcript line.")
                    }
                }
        }
    }

    func fullTopChrome(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 1080
        let pickerWidth = min(max(panelWidth * 0.24, 190), 240)

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EchoPanel")
                            .font(.headline)
                        Text("Live transcript, memory pins, and decision beads")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if stacked {
                    EmptyView()
                } else {
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
        .padding(10)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    var fullSessionRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions, speakers, keywords", text: $fullSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($fullSearchFocused)
                    .accessibilityLabel("Search sessions, speakers, and keywords")
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.24 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )

            HStack {
                Text("Sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(fullSessionItems.count)")
                    .font(.caption2)
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
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    if session.isLive {
                                        Text("Live")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(session.when) · \(session.duration)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedSessionID == session.id ?
                                    Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.16) :
                                    Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.32 : 0.58)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(session.name)")
                        .accessibilityHint("Loads transcript and insights for this session.")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("↑/↓ focus · Enter lens · P pin")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Space follow · J live · ? help · Cmd+K search")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.32 : 0.58))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(10)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    var fullMainHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSessionTitle)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(fullSessionMeta)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(speakerChips) { speaker in
                        Button {
                            fullSearchQuery = speaker.searchToken
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(speaker.color)
                                    .frame(width: 6, height: 6)
                                Text(speaker.label)
                                    .font(.caption2)
                                Text("\(speaker.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.55))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filter transcript by speaker \(speaker.label)")
                        .accessibilityHint("Shows transcript lines for this speaker.")
                    }
                }
            }
        }
        .padding(10)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    var fullInsightPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Insight Surface")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(fullWorkMode.rawValue)
                    .font(.caption2)
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
            .padding(10)
            .background(contentBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
        }
        .padding(10)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    var fullContextPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                surfaceItemCard(tag: "Context", title: "Local context library", subtitle: "RAG-ready slot for documents and snippet references.")

                ForEach(fullContextDocuments, id: \.self) { doc in
                    surfaceItemCard(tag: "Doc", title: doc, subtitle: "Indexed · local")
                }

                surfaceItemCard(
                    tag: "Snippet",
                    title: "Instrument panel framing appears in current transcript.",
                    subtitle: "Derived from live transcript + actions/decisions context."
                )
            }
        }
    }

    var fullTimelineStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(timelineReadoutText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            }
        }
        .padding(10)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
}
