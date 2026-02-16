import XCTest
@testable import MeetingListenerApp

@MainActor
final class CaptionExportTests: XCTestCase {
    func testSRTExportFormatting() {
        let appState = AppState()
        appState.transcriptSegments = [
            TranscriptSegment(
                text: "Hello world",
                t0: 3661.234,
                t1: 3663.5,
                isFinal: true,
                confidence: 0.9
            )
        ]

        let srt = appState.renderSRTForExport()
        XCTAssertTrue(srt.hasPrefix("1\n01:01:01,234 --> 01:01:03,500\nHello world\n\n"))
    }

    func testWebVTTExportFormatting() {
        let appState = AppState()
        appState.transcriptSegments = [
            TranscriptSegment(
                text: "Hello world",
                t0: 3661.234,
                t1: 3663.5,
                isFinal: true,
                confidence: 0.9
            )
        ]

        let vtt = appState.renderWebVTTForExport()
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n01:01:01.234 --> 01:01:03.500\nHello world\n\n"))
    }

    func testSRTUsesOneBasedIndicesForMultipleCues() {
        let appState = AppState()
        appState.transcriptSegments = [
            TranscriptSegment(text: "A", t0: 0.0, t1: 1.0, isFinal: true, confidence: 1.0),
            TranscriptSegment(text: "B", t0: 1.0, t1: 2.0, isFinal: true, confidence: 1.0),
        ]

        let srt = appState.renderSRTForExport()
        XCTAssertTrue(srt.contains("1\n00:00:00,000 --> 00:00:01,000\nA\n\n"))
        XCTAssertTrue(srt.contains("2\n00:00:01,000 --> 00:00:02,000\nB\n\n"))
    }
}

