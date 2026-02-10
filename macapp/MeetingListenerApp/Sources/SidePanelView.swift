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

    struct FilterCacheKey: Equatable {
        let transcriptRevision: Int
        let entityFilterID: UUID?
        let normalizedFullQuery: String
        let viewMode: ViewMode
    }

    @ObservedObject var appState: AppState
    let onEndSession: () -> Void
    let onModeChange: ((ViewMode) -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("sidePanel.viewMode") var storedViewModeRaw = ViewMode.roll.rawValue

    @State var viewMode: ViewMode = .roll
    @State var followLive = true
    @State var highlightMode: EntityHighlighter.HighlightMode = .extracted
    @State var showHighlightHelp = false
    @State var showShortcutOverlay = false
    @State var showSurfaceOverlay = false
    @State var activeSurface: Surface = .summary
    @State var fullInsightTab: FullInsightTab = .summary
    @State var fullWorkMode: FullWorkMode = .live
    @State var fullSearchQuery = ""
    @State var selectedSessionID: String = "live"
    @State var timelinePosition = 1.0
    @State var filteredCacheKey: FilterCacheKey?
    @State var filteredSegmentsCache: [TranscriptSegment] = []

    @State var focusedSegmentID: UUID?
    @State var lensSegmentID: UUID?
    @State var pinnedSegmentIDs: Set<UUID> = []

    @State var pendingNewSegments = 0
    @State var lastTranscriptCount = 0
    @State var scrollToBottomToken = UUID()
    @State var pendingScrollTarget: UUID?

    @State var selectedEntity: EntityItem?
    @State var entityFilter: EntityItem?
    @State var decisionFirstSeen: [UUID: TimeInterval] = [:]
    @State var showCaptureDetails = false

    @State var keyMonitor: Any?
    @FocusState var fullSearchFocused: Bool

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
            refreshFilteredSegmentsCache(force: true)
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
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: appState.transcriptSegments.count) { newCount in
            let diff = newCount - lastTranscriptCount
            lastTranscriptCount = newCount
            refreshFilteredSegmentsCache()
            guard diff > 0 else {
                sanitizeStateForTranscript()
                return
            }

            announceTranscriptUpdate(delta: diff)

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
        .onChange(of: appState.transcriptRevision) { _ in
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: entityFilter?.id) { _ in
            refreshFilteredSegmentsCache()
            sanitizeStateForTranscript()
        }
        .onChange(of: fullSearchQuery) { _ in
            refreshFilteredSegmentsCache()
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

}
