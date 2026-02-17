import XCTest
@testable import MeetingListenerApp

final class MinutesOfMeetingGeneratorTests: XCTestCase {

    func testStandardTemplateIncludesCoreSections() {
        let input = MinutesOfMeetingInput(
            title: "Meeting Minutes",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 366,
            attendees: ["You", "Speaker 1"],
            summary: "Reviewed project milestones and risks.",
            actions: [MinutesOfMeetingAction(text: "Send updated timeline", owner: "Alex", due: "Fri")],
            decisions: ["Ship v0.4 by end of month"],
            risks: ["Scope creep if API changes"],
            topics: ["Timeline", "API"],
            highlights: ["You: We should prioritize stability"]
        )

        let markdown = MinutesOfMeetingGenerator.generate(from: input, template: .standard)

        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("## Action Items"))
        XCTAssertTrue(markdown.contains("## Risks / Blockers"))
        XCTAssertTrue(markdown.contains("## Key Topics"))
        XCTAssertTrue(markdown.contains("## Follow-up Agenda"))
        XCTAssertTrue(markdown.contains("Alex: Send updated timeline (Due: Fri)"))
    }

    func testExecutiveTemplateOmitsEngineeringSections() {
        let input = MinutesOfMeetingInput(
            title: "Meeting Minutes",
            date: Date(),
            durationSeconds: 120,
            attendees: ["You"],
            summary: "Aligned on launch criteria.",
            actions: [],
            decisions: [],
            risks: [],
            topics: [],
            highlights: ["You: We'll finalize specs"]
        )

        let markdown = MinutesOfMeetingGenerator.generate(from: input, template: .executive)

        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Follow-up Agenda"))
        XCTAssertFalse(markdown.contains("## Highlights"))
        XCTAssertFalse(markdown.contains("## Risks / Blockers"))
    }

    func testSnapshotInputUsesTranscriptFallbackSummary() {
        let snapshot: [String: Any] = [
            "session": [
                "started_at": "2026-02-16T10:00:00Z",
                "ended_at": "2026-02-16T10:10:00Z"
            ],
            "transcript": [
                ["text": "We need to ship on Friday.", "t0": 1.0, "t1": 2.0, "is_final": true, "source": "mic"],
                ["text": "I will update the docs.", "t0": 3.0, "t1": 4.0, "is_final": true, "source": "system"]
            ]
        ]

        let input = MinutesOfMeetingGenerator.buildInput(from: snapshot, fallbackTitle: "Meeting Minutes")

        XCTAssertFalse(input.summary.isEmpty)
        XCTAssertEqual(input.attendees, ["You"])
        XCTAssertEqual(input.durationSeconds, 600)
    }
}
