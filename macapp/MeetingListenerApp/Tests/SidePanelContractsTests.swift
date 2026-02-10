import XCTest
import AppKit
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

    func testNeedsReviewBadgeContrastMeetsWCAG() {
        // Convert SwiftUI Color to NSColor for testing
        let fgNSColor = NSColor(NeedsReviewBadgeStyle.foreground)
        let bgNSColor = NSColor(NeedsReviewBadgeStyle.background)
        
        let ratio = contrastRatio(
            foreground: fgNSColor,
            background: bgNSColor
        )
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "Needs review badge must meet WCAG AA contrast for normal text.")
    }

    private func contrastRatio(foreground: NSColor, background: NSColor) -> Double {
        let fg = foreground.usingColorSpace(.sRGB) ?? foreground
        let bg = background.usingColorSpace(.sRGB) ?? background
        let fgLum = relativeLuminance(of: fg)
        let bgLum = relativeLuminance(of: bg)
        let light = max(fgLum, bgLum)
        let dark = min(fgLum, bgLum)
        return (light + 0.05) / (dark + 0.05)
    }

    private func relativeLuminance(of color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let normalized = Double(value)
            if normalized <= 0.03928 {
                return normalized / 12.92
            }
            return pow((normalized + 0.055) / 1.055, 2.4)
        }

        let red = channel(color.redComponent)
        let green = channel(color.greenComponent)
        let blue = channel(color.blueComponent)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
