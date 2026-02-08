import AppKit
import SwiftUI

struct SidePanelView: View {
    enum ViewMode: String, CaseIterable, Identifiable {
        case roll = "Roll"
        case compact = "Compact"
        case full = "Full"

        var id: String { rawValue }
    }

    enum Surface: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case actions = "Actions"
        case pins = "Pins"
        case entities = "Entities"
        case raw = "Raw"

        var id: String { rawValue }
    }

    enum FullWorkMode: String, CaseIterable, Identifiable {
        case live = "Live"
        case review = "Review"
        case brief = "Brief"

        var id: String { rawValue }
    }

    enum FullInsightTab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case actions = "Actions"
        case pins = "Pins"
        case context = "Context"
        case entities = "Entities"
        case raw = "Raw"

        var id: String { rawValue }

        var mapsToSurface: Surface? {
            switch self {
            case .summary:
                return .summary
            case .actions:
                return .actions
            case .pins:
                return .pins
            case .entities:
                return .entities
            case .raw:
                return .raw
            case .context:
                return nil
            }
        }
    }

    private enum TranscriptStyle {
        case roll
        case compact
        case full

        var rowSpacing: CGFloat {
            switch self {
            case .roll:
                return 10
            case .compact:
                return 8
            case .full:
                return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .roll:
                return 14
            case .compact:
                return 10
            case .full:
                return 12
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .roll:
                return 14
            case .compact:
                return 10
            case .full:
                return 12
            }
        }
    }

    @ObservedObject var appState: AppState
    let onEndSession: () -> Void
    let onModeChange: ((ViewMode) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidePanel.viewMode") private var storedViewModeRaw = ViewMode.roll.rawValue

    @State private var viewMode: ViewMode = .roll
    @State private var followLive = true
    @State private var highlightMode: EntityHighlighter.HighlightMode = .extracted
    @State private var showHighlightHelp = false
    @State private var showShortcutOverlay = false
    @State private var showSurfaceOverlay = false
    @State private var activeSurface: Surface = .summary
    @State private var fullInsightTab: FullInsightTab = .summary
    @State private var fullWorkMode: FullWorkMode = .live
    @State private var fullSearchQuery = ""
    @State private var selectedSessionID: String = "live"
    @State private var timelinePosition = 1.0

    @State private var focusedSegmentID: UUID?
    @State private var lensSegmentID: UUID?
    @State private var pinnedSegmentIDs: Set<UUID> = []

    @State private var pendingNewSegments = 0
    @State private var lastTranscriptCount = 0
    @State private var scrollToBottomToken = UUID()
    @State private var pendingScrollTarget: UUID?

    @State private var selectedEntity: EntityItem?
    @State private var entityFilter: EntityItem?
    @State private var decisionFirstSeen: [UUID: TimeInterval] = [:]
    @State private var showCaptureDetails = false

    @State private var keyMonitor: Any?
    @FocusState private var fullSearchFocused: Bool

    init(
        appState: AppState,
        onEndSession: @escaping () -> Void,
        onModeChange: ((ViewMode) -> Void)? = nil
    ) {
        self.appState = appState
        self.onEndSession = onEndSession
        self.onModeChange = onModeChange
    }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = max(geometry.size.width - 16, 280)

            ZStack {
                VStack(spacing: 10) {
                    topBar(panelWidth: panelWidth)
                    captureBar(panelWidth: panelWidth)

                    PermissionBanner(appState: appState)
                    if appState.noAudioDetected {
                        noAudioBanner
                    }

                    content(panelWidth: panelWidth)
                        .layoutPriority(1)

                    footerControls(panelWidth: panelWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(14)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )

                if showShortcutOverlay {
                    shortcutOverlay
                }
            }
            .padding(8)
            .background(windowBackdrop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .focusable(true)
        .onAppear {
            if let restoredMode = ViewMode(rawValue: storedViewModeRaw) {
                viewMode = restoredMode
            } else {
                storedViewModeRaw = ViewMode.roll.rawValue
                viewMode = .roll
            }
            lastTranscriptCount = appState.transcriptSegments.count
            sanitizeStateForTranscript()
            installKeyboardMonitor()
            showCaptureDetails = false
            onModeChange?(viewMode)
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveFocus(by: -1)
            case .down:
                moveFocus(by: 1)
            case .left:
                handleHorizontalSurface(delta: -1)
            case .right:
                handleHorizontalSurface(delta: 1)
            default:
                break
            }
        }
        .onChange(of: viewMode) { newValue in
            if newValue == .full {
                showSurfaceOverlay = false
            }
            showCaptureDetails = false
            storedViewModeRaw = newValue.rawValue
            onModeChange?(newValue)
            sanitizeStateForTranscript()
        }
        .onChange(of: appState.transcriptSegments.count) { newCount in
            let diff = newCount - lastTranscriptCount
            lastTranscriptCount = newCount
            guard diff > 0 else {
                sanitizeStateForTranscript()
                return
            }

            if followLive {
                pendingNewSegments = 0
                if lensSegmentID == nil {
                    focusedSegmentID = visibleTranscriptSegments.last?.id
                }
                scrollToBottomToken = UUID()
            } else {
                pendingNewSegments += diff
            }

            sanitizeStateForTranscript()
        }
        .onChange(of: appState.transcriptSegments.map(\.id)) { _ in
            sanitizeStateForTranscript()
        }
        .onChange(of: followLive) { isOn in
            if isOn {
                pendingNewSegments = 0
                jumpToLive()
            }
        }
        .onChange(of: appState.decisions) { decisions in
            let now = TimeInterval(appState.elapsedSeconds)
            for decision in decisions where decisionFirstSeen[decision.id] == nil {
                decisionFirstSeen[decision.id] = now
            }
        }
        .onChange(of: activeSurface) { newSurface in
            if let mapped = FullInsightTab.allCases.first(where: { $0.mapsToSurface == newSurface }) {
                fullInsightTab = mapped
            }
        }
        .onChange(of: fullInsightTab) { newTab in
            if let surface = newTab.mapsToSurface {
                activeSurface = surface
            }
        }
        .onChange(of: focusedSegmentID) { _ in
            syncTimelineToFocus()
        }
    }

    private func topBar(panelWidth: CGFloat) -> some View {
        let isNarrow = panelWidth < 600
        let pickerWidth = min(
            max(panelWidth * (viewMode == .full ? 0.32 : 0.42), 170),
            viewMode == .full ? 300 : 250
        )

        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EchoPanel")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(statusTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isNarrow {
                    EmptyView()
                } else {
                    Picker("View mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: pickerWidth)
                    .accessibilityLabel("View mode")
                }
            }

            HStack(spacing: 6) {
                statusPill

                Text(appState.timerText)
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chipBackgroundColor)
                    .clipShape(Capsule())

                if !showCaptureDetails {
                    Button("Audio Setup") {
                        showCaptureDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            if isNarrow {
                Picker("View mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("View mode")
            }
        }
    }

    private func captureBar(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 560
        let collapsed = !showCaptureDetails

        return VStack(spacing: 8) {
            if collapsed {
                HStack(spacing: 6) {
                    Text("Audio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.audioSource.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    qualityChip
                    if captureNeedsAttention {
                        Text("Attention")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button("Audio Setup") {
                        showCaptureDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                    .font(.caption2)
                    .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                    .lineLimit(2)
            } else if stacked {
                Picker("Audio source", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appState.sessionState == .listening)
                .accessibilityLabel("Audio source")
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live")

                    Spacer()

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts")

                    Button("Hide") {
                        showCaptureDetails = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                HStack(spacing: 10) {
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

                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live")

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts")

                    Button("Hide") {
                        showCaptureDetails = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if !collapsed {
                ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if appState.audioSource == .system || appState.audioSource == .both {
                        AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                    }
                    if appState.audioSource == .microphone || appState.audioSource == .both {
                        AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                    }

                    Spacer()

                    qualityChip
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        if appState.audioSource == .system || appState.audioSource == .both {
                            AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                        }
                        if appState.audioSource == .microphone || appState.audioSource == .both {
                            AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                        }
                    }

                    qualityChip
                }
                }

                sourceDiagnosticsStrip
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.42 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    private func content(panelWidth: CGFloat) -> some View {
        Group {
            switch viewMode {
            case .roll:
                rollRenderer(panelWidth: panelWidth)
            case .compact:
                compactRenderer(panelWidth: panelWidth)
            case .full:
                fullRenderer(panelWidth: panelWidth)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: visibleTranscriptSegments)
    }

    private func rollRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)

            ZStack {
                transcriptScroller(style: .roll)
                    .background(receiptBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )

                if showSurfaceOverlay {
                    surfaceOverlay
                }
            }

            rollFooterState
        }
    }

    private func compactRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)

            ZStack {
                transcriptScroller(style: .compact)
                    .background(contentBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )

                if showSurfaceOverlay {
                    surfaceOverlay
                }
            }

            HStack(spacing: 8) {
                smallStateBadge(title: followLive ? "Follow ON" : "Follow OFF", tint: followLive ? .green : .orange)
                smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
                smallStateBadge(title: "Pins \(pinnedSegmentIDs.count)", tint: .indigo)
                Spacer()
                if !followLive {
                    Button("Live") { jumpToLive() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private func fullRenderer(panelWidth: CGFloat) -> some View {
        let stackedInsight = panelWidth < 1240
        let railWidth = min(max(panelWidth * 0.22, 220), 260)
        let insightWidth = min(max(panelWidth * 0.27, 300), 390)

        return VStack(spacing: 10) {
            fullTopChrome(panelWidth: panelWidth)

            if stackedInsight {
                HStack(alignment: .top, spacing: 10) {
                    fullSessionRail
                        .frame(width: railWidth)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                fullInsightPanel
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    fullSessionRail
                        .frame(width: railWidth)

                    fullTranscriptColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    fullInsightPanel
                        .frame(width: insightWidth, alignment: .topLeading)
                }
            }

            fullTimelineStrip
        }
        .frame(maxHeight: .infinity)
    }

    private var fullTranscriptColumn: some View {
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
                    }
                }
        }
    }

    private func fullTopChrome(panelWidth: CGFloat) -> some View {
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

    private var fullSessionRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search sessions, speakers, keywords", text: $fullSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($fullSearchFocused)
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

    private var fullMainHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSessionTitle)
                        .font(.headline)
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

    private var fullInsightPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Insight Surface")
                    .font(.headline)
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

    private var fullContextPanel: some View {
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

    private var fullTimelineStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

    private func transcriptScroller(style: TranscriptStyle) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: style.rowSpacing) {
                    if visibleTranscriptSegments.isEmpty {
                        emptyTranscriptState
                    } else {
                        ForEach(visibleTranscriptSegments) { segment in
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

    private var rollFooterState: some View {
        HStack(spacing: 8) {
            smallStateBadge(title: followLive ? "Follow ON" : "Follow OFF", tint: followLive ? .green : .orange)
            smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
            smallStateBadge(title: "Pins \(pinnedSegmentIDs.count)", tint: .indigo)

            Spacer()

            Button("Surfaces") {
                if showSurfaceOverlay {
                    showSurfaceOverlay = false
                } else {
                    showSurfaceOverlay = true
                    activeSurface = .summary
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !followLive {
                Button("Jump Live") {
                    jumpToLive()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func footerControls(panelWidth: CGFloat) -> some View {
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

    private func transcriptToolbar(panelWidth: CGFloat, showSurfaceButtons: Bool) -> some View {
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
    private func toolbarRowLayout(pickerWidth: CGFloat, compactStack: Bool, showSurfaceButtons: Bool) -> some View {
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

    private func toolbarPickerAndInfo(pickerWidth: CGFloat, fillsWidth: Bool) -> some View {
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

    private func toolbarTrailingControls(showSurfaceButtons: Bool) -> some View {
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
            }
        }
    }

    private var surfaceOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text(activeSurface.rawValue)
                    .font(.headline)
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

    private func surfaceContent(surface: Surface) -> some View {
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
                        }
                    }

                case .raw:
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Copy Raw") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rawTranscriptText, forType: .string)
                        }
                        .buttonStyle(.bordered)

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

    private var shortcutOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    showShortcutOverlay = false
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keyboard")
                        .font(.headline)
                    Spacer()
                    Button {
                        showShortcutOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close keyboard help")
                }

                ShortcutRow(label: "Move focus", key: "↑ / ↓")
                ShortcutRow(label: "Toggle lens", key: "Enter")
                ShortcutRow(label: "Pin / unpin", key: "P")
                ShortcutRow(label: "Follow live", key: "Space")
                ShortcutRow(label: "Jump to live", key: "J")
                ShortcutRow(label: "Surfaces", key: "← / →")
                ShortcutRow(label: "Close layer", key: "Esc")
                ShortcutRow(label: "Help", key: "?")

                Text("Arrows move focus unless a surface overlay is open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(width: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .onTapGesture {
                // Consume taps so only backdrop closes the overlay.
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.38),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08),
                                Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 14, x: 0, y: 8)
    }

    private var receiptBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.34 : 0.94),
                Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.22 : 0.88)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var qualityChip: some View {
        Text("Audio \(appState.audioQuality.rawValue)")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(qualityColor(appState.audioQuality).opacity(0.14))
            .foregroundColor(qualityColor(appState.audioQuality))
            .clipShape(Capsule())
    }

    private var sourceDiagnosticsStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(appState.activeSourceProbes) { probe in
                        sourceProbeChip(probe)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.activeSourceProbes) { probe in
                        sourceProbeChip(probe)
                    }
                }
            }

            Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                .font(.caption2)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                .lineLimit(2)
        }
    }

    private func sourceProbeChip(_ probe: AppState.SourceProbe) -> some View {
        HStack(spacing: 5) {
            Text(probe.label)
                .font(.caption2)
                .fontWeight(.semibold)

            Circle()
                .fill(probe.inputIsFresh ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)

            Text("In \(probe.inputAgeText)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("ASR \(probe.asrAgeText)")
                .font(.caption2)
                .foregroundColor(probe.asrIsFresh ? .green : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.24 : 0.72))
        .clipShape(Capsule())
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionStatusColor)
                .frame(width: 7, height: 7)
            Text(statusShort)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(sessionStatusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var noAudioBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill")
                .foregroundColor(.orange)
            Text(appState.silenceMessage)
                .font(.caption)
                .foregroundColor(.orange)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for speech")
                .font(.callout)
                .fontWeight(.semibold)
            Text("Source: \(appState.audioSource.rawValue) · first transcript usually appears in 2-5 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                .font(.caption2)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
            Text("Use ↑/↓ to move focus, Enter for lens, P to pin.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    private func focusLens(segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Focus Lens")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("Line \(focusedLineLabel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                lensTag("Decision", tint: .green)
                lensTag("Trade-off", tint: .orange)
                lensTag("Risk", tint: .red)
                lensTag("Entity", tint: .blue)
            }

            HStack(spacing: 6) {
                ForEach(Surface.allCases) { surface in
                    Button(surface.rawValue) {
                        activeSurface = surface
                        if viewMode == .full {
                            showSurfaceOverlay = false
                        } else {
                            showSurfaceOverlay = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    private func lensTag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    private func smallStateBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    private func surfaceEmptyState(text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.66))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func surfaceItemCard(tag: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.14))
                    .clipShape(Capsule())
                Spacer()
            }

            Text(title)
                .font(.footnote)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.56))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var windowBackdrop: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var chipBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.45 : 0.65)
    }

    private var contentBackgroundColor: Color {
        Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.26 : 0.86)
    }

    private var strokeColor: Color {
        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.58 : 0.24)
    }

    private func performAnimatedUpdate(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: 0.2), updates)
        }
    }

    private var statusTitle: String {
        switch appState.sessionState {
        case .starting:
            return "Checking permissions and connecting..."
        case .listening:
            if viewMode == .roll {
                return "Live transcript, actions, and decisions in one place"
            }
            if viewMode == .compact {
                return "Quick live companion"
            }
            return "Full review and management"
        case .finalizing:
            return "Wrapping up and saving your meeting notes"
        case .error:
            if appState.statusMessage.isEmpty {
                return "Setup needed before listening"
            }
            return appState.statusMessage
        case .idle:
            if !appState.isServerReady {
                return "Preparing local backend..."
            }
            if viewMode == .roll {
                return "Live instrument · transcript-first"
            }
            if viewMode == .compact {
                return "Minimal live companion"
            }
            return "Full review and management"
        }
    }

    private var statusShort: String {
        switch appState.sessionState {
        case .listening:
            return "Listening"
        case .finalizing:
            return "Finalizing"
        case .starting:
            return "Starting"
        case .error:
            if captureNeedsAttention {
                return "Permission needed"
            }
            return "Setup needed"
        case .idle:
            if !appState.isServerReady {
                return "Preparing"
            }
            return "Ready"
        }
    }

    private var captureNeedsAttention: Bool {
        let needsScreen = appState.audioSource == .system || appState.audioSource == .both
        let needsMic = appState.audioSource == .microphone || appState.audioSource == .both
        return (needsScreen && appState.screenRecordingPermission == .denied) ||
            (needsMic && appState.microphonePermission == .denied)
    }

    private var sessionStatusColor: Color {
        switch appState.sessionState {
        case .listening:
            return .green
        case .finalizing:
            return .orange
        case .starting:
            return .blue
        case .error:
            return .red
        case .idle:
            return .gray
        }
    }

    private var exportDisabled: Bool {
        appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty
    }

    private var filteredSegments: [TranscriptSegment] {
        var base = appState.transcriptSegments
        if let entityFilter {
            base = base.filter { segment in
                EntityHighlighter.matches(in: segment.text, entities: [entityFilter], mode: .extracted).isEmpty == false
            }
        }

        let query = fullSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewMode == .full && !query.isEmpty {
            let lowered = query.lowercased()
            base = base.filter { segment in
                let speaker = speakerLabel(for: segment).lowercased()
                let stamp = formatTime(segment.t0)
                return segment.text.lowercased().contains(lowered) || speaker.contains(lowered) || stamp.contains(lowered)
            }
        }

        return base
    }

    private var visibleTranscriptSegments: [TranscriptSegment] {
        let base = filteredSegments
        switch viewMode {
        case .roll:
            return Array(base.suffix(120))
        case .compact:
            return Array(base.suffix(36))
        case .full:
            return Array(base.suffix(500))
        }
    }

    private var pinnedSegments: [TranscriptSegment] {
        appState.transcriptSegments
            .filter { pinnedSegmentIDs.contains($0.id) }
            .sorted { $0.t0 > $1.t0 }
    }

    private var focusedLineLabel: String {
        guard let idx = currentFocusedIndex else { return "-" }
        return String(idx + 1)
    }

    private var currentFocusedIndex: Int? {
        guard let id = focusedSegmentID else { return nil }
        return visibleTranscriptSegments.firstIndex(where: { $0.id == id })
    }

    private var rawTranscriptText: String {
        appState.transcriptSegments
            .map { segment in
                "[\(formatTime(segment.t0))] \(speakerLabel(for: segment)): \(segment.text)"
            }
            .joined(separator: "\n")
    }

    private var fullSessionItems: [FullSessionItem] {
        var items: [FullSessionItem] = []

        if appState.sessionState == .listening || appState.sessionState == .starting || appState.sessionState == .finalizing {
            items.append(
                FullSessionItem(
                    id: "live",
                    name: "Current Session",
                    when: "Now",
                    duration: appState.timerText,
                    isLive: true
                )
            )
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let sessions = SessionStore.shared.listSessions()
        for session in sessions.prefix(14) {
            items.append(
                FullSessionItem(
                    id: session.id,
                    name: "Session \(session.id.prefix(8))",
                    when: formatter.string(from: session.date),
                    duration: session.hasTranscript ? "Recorded" : "No transcript",
                    isLive: false
                )
            )
        }

        if items.isEmpty {
            items.append(
                FullSessionItem(
                    id: "placeholder",
                    name: "No saved sessions yet",
                    when: "Start listening to create one",
                    duration: "--",
                    isLive: false
                )
            )
        }

        return items
    }

    private var selectedSessionTitle: String {
        fullSessionItems.first(where: { $0.id == selectedSessionID })?.name ?? "Design Sync"
    }

    private var fullSessionMeta: String {
        let speakers = Set(visibleTranscriptSegments.map { speakerLabel(for: $0) }).count
        return "\(speakers) speakers · \(appState.timerText) · \(fullWorkMode.rawValue) mode"
    }

    private var speakerChips: [SpeakerChipItem] {
        var counts: [String: Int] = [:]
        for segment in visibleTranscriptSegments {
            let key = speakerLabel(for: segment)
            counts[key, default: 0] += 1
        }

        let palette: [Color] = [.blue, .purple, .green, .orange, .teal, .indigo]
        let names = counts.keys.sorted()
        return names.enumerated().map { idx, name in
            SpeakerChipItem(
                id: name,
                label: name,
                count: counts[name] ?? 0,
                color: palette[idx % palette.count],
                searchToken: name
            )
        }
    }

    private var fullContextDocuments: [String] {
        var docs: [String] = []
        if !appState.finalSummaryMarkdown.isEmpty {
            docs.append("Final Summary Snapshot")
        }
        if !appState.actions.isEmpty {
            docs.append("Action Register")
        }
        if !appState.decisions.isEmpty {
            docs.append("Decision Register")
        }
        if docs.isEmpty {
            docs.append("Context library will populate as sessions are captured.")
        }
        return docs
    }

    private var timelineReadoutText: String {
        if let focusedSegmentID,
           let segment = visibleTranscriptSegments.first(where: { $0.id == focusedSegmentID }) {
            return "Focused \(formatTime(segment.t0))"
        }
        return "Scrub to jump"
    }

    private var decisionBeadPositions: [Double] {
        guard visibleTranscriptSegments.count > 1 else { return [] }
        var positions: [Double] = []
        for decision in appState.decisions.prefix(7) {
            let token = String(decision.text.prefix(16))
            if let idx = visibleTranscriptSegments.lastIndex(where: { segment in
                segment.text.localizedCaseInsensitiveContains(token)
            }) {
                let pos = Double(idx) / Double(max(visibleTranscriptSegments.count - 1, 1))
                positions.append(pos)
            }
        }
        return positions.isEmpty ? [0.18, 0.42, 0.7] : positions
    }

    private var surfaceSummaryItems: [SurfaceCardItem] {
        var cards: [SurfaceCardItem] = []

        for decision in appState.decisions.prefix(4) {
            cards.append(
                SurfaceCardItem(
                    tag: "Decision",
                    title: decision.text,
                    subtitle: decisionMeta(decision)
                )
            )
        }

        for action in appState.actions.prefix(4) {
            cards.append(
                SurfaceCardItem(
                    tag: "Action",
                    title: action.text,
                    subtitle: itemMeta(owner: action.owner, due: action.due, confidence: action.confidence)
                )
            )
        }

        if cards.isEmpty {
            let recent = appState.transcriptSegments.suffix(3)
            for segment in recent {
                cards.append(
                    SurfaceCardItem(
                        tag: "Live",
                        title: segment.text,
                        subtitle: "\(formatTime(segment.t0)) · \(speakerLabel(for: segment))"
                    )
                )
            }
        }

        return cards
    }

    private func sanitizeStateForTranscript() {
        let visibleIDs = Set(visibleTranscriptSegments.map(\.id))
        let sourceIDs = Set(appState.transcriptSegments.map(\.id))

        pinnedSegmentIDs = pinnedSegmentIDs.intersection(sourceIDs)

        if let focusedSegmentID, visibleIDs.contains(focusedSegmentID) == false {
            self.focusedSegmentID = nil
        }
        if let lensSegmentID, visibleIDs.contains(lensSegmentID) == false {
            self.lensSegmentID = nil
        }

        if visibleTranscriptSegments.isEmpty {
            focusedSegmentID = nil
            lensSegmentID = nil
            return
        }

        if followLive && lensSegmentID == nil {
            focusedSegmentID = visibleTranscriptSegments.last?.id
            return
        }

        if focusedSegmentID == nil {
            focusedSegmentID = visibleTranscriptSegments.last?.id
        }
    }

    private func moveFocus(by delta: Int) {
        guard !visibleTranscriptSegments.isEmpty else { return }
        if showSurfaceOverlay && viewMode != .full {
            return
        }

        let current = currentFocusedIndex ?? (visibleTranscriptSegments.count - 1)
        let next = max(0, min(visibleTranscriptSegments.count - 1, current + delta))
        focusedSegmentID = visibleTranscriptSegments[next].id

        if followLive {
            followLive = false
        }

        pendingScrollTarget = focusedSegmentID
    }

    private func toggleLens(_ id: UUID) {
        lensSegmentID = (lensSegmentID == id) ? nil : id
        if followLive {
            followLive = false
        }
        pendingScrollTarget = id
    }

    private func togglePin(_ id: UUID) {
        if pinnedSegmentIDs.contains(id) {
            pinnedSegmentIDs.remove(id)
        } else {
            pinnedSegmentIDs.insert(id)
        }
    }

    private func jumpToLive() {
        followLive = true
        pendingNewSegments = 0
        lensSegmentID = nil
        if let last = visibleTranscriptSegments.last?.id {
            focusedSegmentID = last
            pendingScrollTarget = last
        }
        timelinePosition = 1
        scrollToBottomToken = UUID()
    }

    private func focusFromTimeline(position: Double) {
        guard !visibleTranscriptSegments.isEmpty else { return }
        let clamped = max(0, min(1, position))
        let target = Int(round(clamped * Double(max(visibleTranscriptSegments.count - 1, 0))))
        focusedSegmentID = visibleTranscriptSegments[target].id
        if followLive {
            followLive = false
        }
        pendingScrollTarget = focusedSegmentID
    }

    private func syncTimelineToFocus() {
        guard !visibleTranscriptSegments.isEmpty else {
            timelinePosition = 1
            return
        }
        guard let idx = currentFocusedIndex else {
            timelinePosition = followLive ? 1 : timelinePosition
            return
        }
        let value = Double(idx) / Double(max(visibleTranscriptSegments.count - 1, 1))
        timelinePosition = value
    }

    private func handleHorizontalSurface(delta: Int) {
        if viewMode == .full {
            cycleFullInsightTab(delta)
            return
        }

        if showSurfaceOverlay {
            cycleSurface(delta)
            return
        }

        showSurfaceOverlay = true
        activeSurface = .summary
    }

    private func cycleFullInsightTab(_ delta: Int) {
        guard let idx = FullInsightTab.allCases.firstIndex(of: fullInsightTab) else { return }
        let next = (idx + delta + FullInsightTab.allCases.count) % FullInsightTab.allCases.count
        fullInsightTab = FullInsightTab.allCases[next]
    }

    private func cycleSurface(_ delta: Int) {
        guard let idx = Surface.allCases.firstIndex(of: activeSurface) else { return }
        let next = (idx + delta + Surface.allCases.count) % Surface.allCases.count
        activeSurface = Surface.allCases[next]
    }

    private func closeTopLayer() {
        if showShortcutOverlay {
            showShortcutOverlay = false
            return
        }
        if showSurfaceOverlay {
            showSurfaceOverlay = false
            return
        }
        if lensSegmentID != nil {
            lensSegmentID = nil
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if shouldIgnoreKeyEvent(event) {
                return event
            }
            if handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func shouldIgnoreKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window, window.isKeyWindow else { return true }
        if window.title != "EchoPanel" {
            return true
        }

        if let responder = window.firstResponder as? NSTextView, responder.isEditable {
            return true
        }
        return false
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let chars = event.characters ?? ""
        let charsIgnoring = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if chars == "?" || (charsIgnoring == "/" && event.modifierFlags.contains(.shift)) {
            showShortcutOverlay.toggle()
            return true
        }

        if viewMode == .full && charsIgnoring == "k" && (modifiers.contains(.command) || modifiers.contains(.control)) {
            fullSearchFocused = true
            return true
        }

        switch event.keyCode {
        case 53: // escape
            closeTopLayer()
            return true
        case 126: // up
            moveFocus(by: -1)
            return true
        case 125: // down
            moveFocus(by: 1)
            return true
        case 36: // return
            if let id = focusedSegmentID {
                toggleLens(id)
            }
            return true
        case 49: // space
            followLive.toggle()
            return true
        case 124: // right
            handleHorizontalSurface(delta: 1)
            return true
        case 123: // left
            handleHorizontalSurface(delta: -1)
            return true
        default:
            break
        }

        if charsIgnoring == "p" {
            if let id = focusedSegmentID {
                togglePin(id)
            }
            return true
        }

        if charsIgnoring == "j" {
            jumpToLive()
            return true
        }

        return false
    }

    private func resolveEntity(_ clicked: EntityItem) -> EntityItem {
        if let found = appState.entities.first(where: { $0.name.caseInsensitiveCompare(clicked.name) == .orderedSame }) {
            return found
        }
        return clicked
    }

    private func scrollToNextMention(for entity: EntityItem) {
        let segments = visibleTranscriptSegments
        guard !segments.isEmpty else { return }

        let currentIndex: Int? = {
            guard let selected = focusedSegmentID else { return nil }
            return segments.firstIndex(where: { $0.id == selected })
        }()

        let start = (currentIndex ?? -1) + 1
        if start < segments.count,
            let idx = segments[start...].firstIndex(where: {
                EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false
            }) {
            focusedSegmentID = segments[idx].id
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
            return
        }

        if let idx = segments.firstIndex(where: {
            EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false
        }) {
            focusedSegmentID = segments[idx].id
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        }
    }

    private func scrollToPreviousMention(for entity: EntityItem) {
        let segments = visibleTranscriptSegments
        guard !segments.isEmpty else { return }

        let currentIndex: Int? = {
            guard let selected = focusedSegmentID else { return nil }
            return segments.firstIndex(where: { $0.id == selected })
        }()

        let end = currentIndex ?? segments.count
        if end > 0,
            let idx = segments[..<end].lastIndex(where: {
                EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false
            }) {
            focusedSegmentID = segments[idx].id
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
            return
        }

        if let idx = segments.lastIndex(where: {
            EntityHighlighter.matches(in: $0.text, entities: [entity], mode: .extracted).isEmpty == false
        }) {
            focusedSegmentID = segments[idx].id
            pendingScrollTarget = segments[idx].id
            selectedEntity = resolveEntity(entity)
        }
    }

    private func speakerLabel(for segment: TranscriptSegment) -> String {
        if let speaker = segment.speaker, !speaker.isEmpty {
            return speaker
        }
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? "You" : "System"
        }
        return "Speaker"
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func itemMeta(owner: String?, due: String?, confidence: Double) -> String {
        var parts: [String] = []
        if let owner, !owner.isEmpty {
            parts.append("Owner: \(owner)")
        }
        if let due, !due.isEmpty {
            parts.append("Due: \(due)")
        }
        parts.append(confidenceMeta(confidence))
        return parts.joined(separator: " · ")
    }

    private func confidenceMeta(_ value: Double) -> String {
        let base = "Confidence \(formatConfidence(value))"
        if value < 0.5 {
            return "\(base) (Draft)"
        }
        return base
    }

    private func decisionMeta(_ item: DecisionItem) -> String {
        let timestamp = decisionFirstSeen[item.id] ?? TimeInterval(appState.elapsedSeconds)
        return "\(formatTime(timestamp)) · \(confidenceMeta(item.confidence))"
    }
}

private struct SurfaceCardItem: Identifiable {
    let id = UUID()
    let tag: String
    let title: String
    let subtitle: String
}

private struct FullSessionItem: Identifiable {
    let id: String
    let name: String
    let when: String
    let duration: String
    let isLive: Bool
}

private struct SpeakerChipItem: Identifiable {
    let id: String
    let label: String
    let count: Int
    let color: Color
    let searchToken: String
}

private struct TranscriptLineRow: View {
    @Environment(\.colorScheme) private var colorScheme

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
                    matches: EntityHighlighter.matches(in: segment.text, entities: entities, mode: highlightMode),
                    highlightsEnabled: highlightMode.isEnabled
                ) { entity in
                    onEntityClick(entity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(formatConfidence(segment.confidence))
                        .font(.caption2)
                        .foregroundColor(confidenceColor)

                    if segment.confidence < lowConfidenceThreshold {
                        Text("Needs review")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(Capsule())
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

    private var speakerBadge: some View {
        let label = speakerInitial
        return Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .frame(width: 24, height: 24)
            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.9))
            .clipShape(Circle())
            .overlay(Circle().stroke(speakerTint.opacity(0.7), lineWidth: 1))
            .foregroundColor(speakerTint)
    }

    private func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rowBackground: Color {
        if isFocused {
            return Color.blue.opacity(0.11)
        }
        if isPinned {
            return Color.indigo.opacity(0.1)
        }
        return Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.18 : 0.75)
    }

    private var rowStroke: Color {
        if isFocused {
            return Color.blue.opacity(0.5)
        }
        if isPinned {
            return Color.indigo.opacity(0.45)
        }
        return Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.55 : 0.25)
    }

    private var speakerInitial: String {
        if let speaker = segment.speaker, let c = speaker.first {
            return String(c).uppercased()
        }
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? "Y" : "S"
        }
        return "•"
    }

    private var speakerTint: Color {
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? .blue : .purple
        }
        return .teal
    }

    private var confidenceColor: Color {
        if segment.confidence >= 0.8 {
            return .green
        }
        if segment.confidence >= 0.5 {
            return .secondary
        }
        return .orange
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

private struct ShortcutRow: View {
    @Environment(\.colorScheme) private var colorScheme

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

private struct HighlightHelpView: View {
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

private struct PermissionBanner: View {
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

    private var issues: [(label: String, url: String)] {
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

private struct AudioLevelMeter: View {
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

    private var levelColor: Color {
        if level > 0.8 {
            return .red
        }
        if level > 0.3 {
            return .green
        }
        return .yellow
    }
}
