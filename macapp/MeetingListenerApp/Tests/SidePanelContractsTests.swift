import XCTest
@testable import MeetingListenerApp

final class SidePanelContractsTests: XCTestCase {
    func testViewModesHaveExpectedOrder() {
        XCTAssertEqual(
            SidePanelView.ViewMode.allCases.map(\.rawValue),
            ["Roll", "Compact", "Full"]
        )
    }

    func testSurfaceParityContractRemainsStable() {
        XCTAssertEqual(
            SidePanelView.Surface.allCases.map(\.rawValue),
            ["Summary", "Actions", "Pins", "Entities", "Raw"]
        )
    }

    func testFullInsightTabsIncludeContextAndOrder() {
        XCTAssertEqual(
            SidePanelView.FullInsightTab.allCases.map(\.rawValue),
            ["Summary", "Actions", "Pins", "Context", "Entities", "Raw"]
        )
    }

    func testFullInsightTabSurfaceMappingContract() {
        XCTAssertEqual(SidePanelView.FullInsightTab.summary.mapsToSurface, .summary)
        XCTAssertEqual(SidePanelView.FullInsightTab.actions.mapsToSurface, .actions)
        XCTAssertEqual(SidePanelView.FullInsightTab.pins.mapsToSurface, .pins)
        XCTAssertNil(SidePanelView.FullInsightTab.context.mapsToSurface)
        XCTAssertEqual(SidePanelView.FullInsightTab.entities.mapsToSurface, .entities)
        XCTAssertEqual(SidePanelView.FullInsightTab.raw.mapsToSurface, .raw)
    }
}
