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

    enum TranscriptStyle {
        case roll
        case compact
        case full

        var rowSpacing: CGFloat {
            switch self {
            case .roll:
                return ViewModeSpacing.roll.rowSpacing
            case .compact:
                return ViewModeSpacing.compact.rowSpacing
            case .full:
                return ViewModeSpacing.full.rowSpacing
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .roll:
                return ViewModeSpacing.roll.verticalPadding
            case .compact:
                return ViewModeSpacing.compact.verticalPadding
            case .full:
                return ViewModeSpacing.full.verticalPadding
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .roll:
                return ViewModeSpacing.roll.horizontalPadding
            case .compact:
                return ViewModeSpacing.compact.horizontalPadding
            case .full:
                return ViewModeSpacing.full.horizontalPadding
            }
        }
    }

    @ObservedObject var appState: AppState
    let onEndSession: () -> Void
    let onModeChange: ((ViewMode) -> Void)?
    let onAlwaysOnTopChange: ((Bool) -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("sidePanel.viewMode") var storedViewModeRaw = ViewMode.roll.rawValue
    @AppStorage("sidePanel.alwaysOnTop") var alwaysOnTop = true

    @State var viewMode: ViewMode = .roll
    @State var highlightMode: EntityHighlighter.HighlightMode = .extracted
    @State var showHighlightHelp = false
    @State var showShortcutOverlay = false
    @State var showSurfaceOverlay = false
    @State var activeSurface: Surface = .summary
    @State var fullInsightTab: FullInsightTab = .summary
    @State var fullWorkMode: FullWorkMode = .live
    @State var selectedSessionID: String = "live"
    @State var timelinePosition = 1.0
    @StateObject var transcriptUI = SidePanelTranscriptUIState()
    @State var decisionFirstSeen: [UUID: TimeInterval] = [:]
    @State var showCaptureDetails = false

    @State var keyMonitor: Any?
    @FocusState var fullSearchFocused: Bool

    init(
        appState: AppState,
        onEndSession: @escaping () -> Void,
        onModeChange: ((ViewMode) -> Void)? = nil,
        onAlwaysOnTopChange: ((Bool) -> Void)? = nil
    ) {
        self.appState = appState
        self.onEndSession = onEndSession
        self.onModeChange = onModeChange
        self.onAlwaysOnTopChange = onAlwaysOnTopChange
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
                    if let userNotice = appState.userNotice {
                        userNoticeBanner(userNotice)
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
            transcriptUI.lastTranscriptCount = appState.transcriptSegments.count
            refreshFilteredSegmentsCache(force: true)
            sanitizeStateForTranscript()
            installKeyboardMonitor()
            showCaptureDetails = false
            onModeChange?(viewMode)
            onAlwaysOnTopChange?(alwaysOnTop)
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
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: alwaysOnTop) { newValue in
            onAlwaysOnTopChange?(newValue)
        }
        .onChange(of: appState.transcriptSegments.count) { newCount in
            let diff = newCount - transcriptUI.lastTranscriptCount
            transcriptUI.lastTranscriptCount = newCount
            refreshFilteredSegmentsCache()
            guard diff > 0 else {
                sanitizeStateForTranscript()
                return
            }

            announceTranscriptUpdate(delta: diff)

            if transcriptUI.followLive {
                transcriptUI.pendingNewSegments = 0
                if transcriptUI.lensSegmentID == nil {
                    transcriptUI.focusedSegmentID = visibleTranscriptSegments.last?.id
                }
                transcriptUI.scrollToBottomToken = UUID()
            } else {
                transcriptUI.pendingNewSegments += diff
            }

            sanitizeStateForTranscript()
        }
        .onChange(of: appState.transcriptRevision) { _ in
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: transcriptUI.entityFilter?.id) { _ in
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: transcriptUI.fullSearchQuery) { _ in
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: transcriptUI.followLive) { isOn in
            if isOn {
                transcriptUI.pendingNewSegments = 0
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
        .onChange(of: transcriptUI.focusedSegmentID) { _ in
            syncTimelineToFocus()
        }
    }

}
