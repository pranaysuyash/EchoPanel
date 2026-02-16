import Combine
import Foundation

// Transcript-related UI state extracted from SidePanelView to keep the view thinner
// and make behavior easier to reason about and eventually unit test.

struct SidePanelTranscriptFilterCacheKey: Equatable {
    let transcriptRevision: Int
    let entityFilterID: UUID?
    let normalizedFullQuery: String
    let viewModeRaw: String
}

@MainActor
final class SidePanelTranscriptUIState: ObservableObject {
    // Interaction / navigation
    @Published var followLive: Bool = true
    @Published var focusedSegmentID: UUID?
    @Published var lensSegmentID: UUID?
    @Published var pinnedSegmentIDs: Set<UUID> = []

    // Filtering / search
    @Published var fullSearchQuery: String = ""
    @Published var entityFilter: EntityItem?
    @Published var selectedEntity: EntityItem?

    // Streaming + scroll behavior
    @Published var pendingNewSegments: Int = 0
    @Published var lastTranscriptCount: Int = 0
    @Published var scrollToBottomToken: UUID = UUID()
    @Published var pendingScrollTarget: UUID?

    // Filter cache (kept here to avoid re-computation churn on every view access)
    @Published var filteredCacheKey: SidePanelTranscriptFilterCacheKey?
    @Published var filteredSegmentsCache: [TranscriptSegment] = []
}

