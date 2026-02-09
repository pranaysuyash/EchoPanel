import AppKit
import SwiftUI

extension SidePanelView {
    var statusTitle: String {
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

    var statusShort: String {
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

    var captureNeedsAttention: Bool {
        let needsScreen = appState.audioSource == .system || appState.audioSource == .both
        let needsMic = appState.audioSource == .microphone || appState.audioSource == .both
        return (needsScreen && appState.screenRecordingPermission == .denied) ||
            (needsMic && appState.microphonePermission == .denied)
    }

    var sessionStatusColor: Color {
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

    var exportDisabled: Bool {
        appState.transcriptSegments.isEmpty && appState.actions.isEmpty && appState.decisions.isEmpty && appState.risks.isEmpty
    }

    var filteredSegments: [TranscriptSegment] {
        let key = currentFilterCacheKey
        if filteredCacheKey == key {
            return filteredSegmentsCache
        }

        // First render can happen before .onAppear seeds cache.
        return Self.filterTranscriptSegments(
            appState.transcriptSegments,
            entityFilter: entityFilter,
            normalizedFullQuery: key.normalizedFullQuery,
            viewMode: viewMode
        )
    }

    var visibleTranscriptSegments: [TranscriptSegment] {
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

    var pinnedSegments: [TranscriptSegment] {
        appState.transcriptSegments
            .filter { pinnedSegmentIDs.contains($0.id) }
            .sorted { $0.t0 > $1.t0 }
    }

    var focusedLineLabel: String {
        guard let idx = currentFocusedIndex else { return "-" }
        return String(idx + 1)
    }

    var currentFocusedIndex: Int? {
        guard let id = focusedSegmentID else { return nil }
        return visibleTranscriptSegments.firstIndex(where: { $0.id == id })
    }

    var rawTranscriptText: String {
        appState.transcriptSegments
            .map { segment in
                "[\(formatTime(segment.t0))] \(speakerLabel(for: segment)): \(segment.text)"
            }
            .joined(separator: "\n")
    }

    var fullSessionItems: [FullSessionItem] {
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

    var selectedSessionTitle: String {
        fullSessionItems.first(where: { $0.id == selectedSessionID })?.name ?? "Design Sync"
    }

    var fullSessionMeta: String {
        let speakers = Set(visibleTranscriptSegments.map { speakerLabel(for: $0) }).count
        return "\(speakers) speakers · \(appState.timerText) · \(fullWorkMode.rawValue) mode"
    }

    func refreshFilteredSegmentsCache(force: Bool = false) {
        let nextKey = currentFilterCacheKey

        if !force, filteredCacheKey == nextKey {
            return
        }

        filteredSegmentsCache = Self.filterTranscriptSegments(
            appState.transcriptSegments,
            entityFilter: entityFilter,
            normalizedFullQuery: nextKey.normalizedFullQuery,
            viewMode: viewMode
        )
        filteredCacheKey = nextKey
    }

    var currentFilterCacheKey: FilterCacheKey {
        FilterCacheKey(
            transcriptRevision: appState.transcriptRevision,
            entityFilterID: entityFilter?.id,
            normalizedFullQuery: normalizedFullSearchQuery,
            viewMode: viewMode
        )
    }

    var normalizedFullSearchQuery: String {
        if viewMode != .full {
            return ""
        }
        return fullSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var speakerChips: [SpeakerChipItem] {
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

    var fullContextDocuments: [String] {
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

    var timelineReadoutText: String {
        if let focusedSegmentID,
           let segment = visibleTranscriptSegments.first(where: { $0.id == focusedSegmentID }) {
            return "Focused \(formatTime(segment.t0))"
        }
        return "Scrub to jump"
    }

    var decisionBeadPositions: [Double] {
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

    var surfaceSummaryItems: [SurfaceCardItem] {
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

    func sanitizeStateForTranscript() {
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

    func announceTranscriptUpdate(delta: Int) {
        guard delta > 0 else { return }
        guard appState.sessionState == .listening else { return }
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }

        let message: String
        if delta == 1, let segment = visibleTranscriptSegments.last {
            message = "New transcript line from \(speakerLabel(for: segment))."
        } else {
            message = "\(delta) new transcript lines."
        }

        guard let app = NSApp else { return }

        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    func moveFocus(by delta: Int) {
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

    func toggleLens(_ id: UUID) {
        lensSegmentID = (lensSegmentID == id) ? nil : id
        if followLive {
            followLive = false
        }
        pendingScrollTarget = id
    }

    func togglePin(_ id: UUID) {
        if pinnedSegmentIDs.contains(id) {
            pinnedSegmentIDs.remove(id)
        } else {
            pinnedSegmentIDs.insert(id)
        }
    }

    func jumpToLive() {
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

    func focusFromTimeline(position: Double) {
        guard !visibleTranscriptSegments.isEmpty else { return }
        let clamped = max(0, min(1, position))
        let target = Int(round(clamped * Double(max(visibleTranscriptSegments.count - 1, 0))))
        focusedSegmentID = visibleTranscriptSegments[target].id
        if followLive {
            followLive = false
        }
        pendingScrollTarget = focusedSegmentID
    }

    func syncTimelineToFocus() {
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

    func handleHorizontalSurface(delta: Int) {
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

    func cycleFullInsightTab(_ delta: Int) {
        guard let idx = FullInsightTab.allCases.firstIndex(of: fullInsightTab) else { return }
        let next = (idx + delta + FullInsightTab.allCases.count) % FullInsightTab.allCases.count
        fullInsightTab = FullInsightTab.allCases[next]
    }

    func cycleSurface(_ delta: Int) {
        guard let idx = Surface.allCases.firstIndex(of: activeSurface) else { return }
        let next = (idx + delta + Surface.allCases.count) % Surface.allCases.count
        activeSurface = Surface.allCases[next]
    }

    func closeTopLayer() {
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

    func installKeyboardMonitor() {
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

    func removeKeyboardMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    func shouldIgnoreKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window, window.isKeyWindow else { return true }
        if window.title != "EchoPanel" {
            return true
        }

        if let responder = window.firstResponder as? NSTextView, responder.isEditable {
            return true
        }
        return false
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
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

    func resolveEntity(_ clicked: EntityItem) -> EntityItem {
        if let found = appState.entities.first(where: { $0.name.caseInsensitiveCompare(clicked.name) == .orderedSame }) {
            return found
        }
        return clicked
    }

    func scrollToNextMention(for entity: EntityItem) {
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

    func scrollToPreviousMention(for entity: EntityItem) {
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

    func speakerLabel(for segment: TranscriptSegment) -> String {
        Self.defaultSpeakerLabel(for: segment)
    }

    func qualityColor(_ quality: AudioQuality) -> Color {
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

    func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    func formatConfidence(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    func itemMeta(owner: String?, due: String?, confidence: Double) -> String {
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

    func confidenceMeta(_ value: Double) -> String {
        let base = "Confidence \(formatConfidence(value))"
        if value < 0.5 {
            return "\(base) (Draft)"
        }
        return base
    }

    func decisionMeta(_ item: DecisionItem) -> String {
        let timestamp = decisionFirstSeen[item.id] ?? TimeInterval(appState.elapsedSeconds)
        return "\(formatTime(timestamp)) · \(confidenceMeta(item.confidence))"
    }

    static func filterTranscriptSegments(
        _ segments: [TranscriptSegment],
        entityFilter: EntityItem?,
        normalizedFullQuery: String,
        viewMode: ViewMode
    ) -> [TranscriptSegment] {
        var base = segments
        if let entityFilter {
            base = base.filter { segment in
                EntityHighlighter.matches(in: segment.text, entities: [entityFilter], mode: .extracted).isEmpty == false
            }
        }

        if viewMode == .full && !normalizedFullQuery.isEmpty {
            base = base.filter { segment in
                let speaker = defaultSpeakerLabel(for: segment).lowercased()
                let stamp = formattedTimeForSearch(segment.t0)
                return segment.text.lowercased().contains(normalizedFullQuery) ||
                    speaker.contains(normalizedFullQuery) ||
                    stamp.contains(normalizedFullQuery)
            }
        }

        return base
    }

    static func defaultSpeakerLabel(for segment: TranscriptSegment) -> String {
        if let speaker = segment.speaker, !speaker.isEmpty {
            return speaker
        }
        if let source = segment.source {
            let isMic = source == "microphone" || source == "mic"
            return isMic ? "You" : "System"
        }
        return "Speaker"
    }

    static func formattedTimeForSearch(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
