import Foundation

enum MockData {
    static let sampleSessions: [Session] = [
        Session(
            id: UUID(),
            title: "Team Standup",
            startTime: Date().addingTimeInterval(-7200),
            duration: 1800,
            transcript: sampleTranscript,
            highlights: sampleHighlights
        ),
        Session(
            id: UUID(),
            title: "Client Call - Acme Corp",
            startTime: Date().addingTimeInterval(-36000),
            duration: 2700,
            transcript: [],
            highlights: []
        ),
        Session(
            id: UUID(),
            title: "Sprint Planning",
            startTime: Date().addingTimeInterval(-86400),
            duration: 3600,
            transcript: [],
            highlights: []
        )
    ]
    
    static let sampleTranscript: [TranscriptItem] = [
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Good morning everyone. Let's start with updates from the backend team.",
            timestamp: Date().addingTimeInterval(-7200),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Alex Kim",
            text: "We've made good progress on the API migration. Should be ready for testing by Friday.",
            timestamp: Date().addingTimeInterval(-7180),
            isPinned: false,
            actionItem: ActionItem(
                id: UUID(),
                assignee: "Alex Kim",
                task: "Complete API migration testing",
                isCompleted: false
            )
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Great. What's the timeline for the frontend integration?",
            timestamp: Date().addingTimeInterval(-7150),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Mike Johnson",
            text: "I can start on that once Alex gives me the endpoints. Probably early next week.",
            timestamp: Date().addingTimeInterval(-7120),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Perfect. Let's aim to have everything integrated by the end of next week then.",
            timestamp: Date().addingTimeInterval(-7100),
            isPinned: true,
            actionItem: ActionItem(
                id: UUID(),
                assignee: "Team",
                task: "Complete full integration by Feb 28",
                isCompleted: false
            )
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Alex Kim",
            text: "One more thing - we should review the database migration plan before we go live.",
            timestamp: Date().addingTimeInterval(-7080),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Good point. Let's schedule a separate meeting for that. Maybe Thursday?",
            timestamp: Date().addingTimeInterval(-7050),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Mike Johnson",
            text: "Thursday works for me. Should we invite the DevOps team?",
            timestamp: Date().addingTimeInterval(-7020),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Yes, definitely. I'll send out an invite.",
            timestamp: Date().addingTimeInterval(-7000),
            isPinned: false,
            actionItem: ActionItem(
                id: UUID(),
                assignee: "Sarah Chen",
                task: "Schedule database migration review",
                isCompleted: false
            )
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Alex Kim",
            text: "Also, I noticed some performance issues with the new search feature. We should profile it before release.",
            timestamp: Date().addingTimeInterval(-6950),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Sarah Chen",
            text: "Absolutely. Performance is critical for this release. Alex, can you take point on that?",
            timestamp: Date().addingTimeInterval(-6920),
            isPinned: false
        ),
        TranscriptItem(
            id: UUID(),
            speaker: "Alex Kim",
            text: "Sure thing. I'll run some benchmarks and report back.",
            timestamp: Date().addingTimeInterval(-6890),
            isPinned: false,
            actionItem: ActionItem(
                id: UUID(),
                assignee: "Alex Kim",
                task: "Profile search performance and report findings",
                isCompleted: false
            )
        )
    ]
    
    static let sampleHighlights: [Highlight] = [
        Highlight(
            id: UUID(),
            type: .decision,
            content: "Target completion date: End of next week (Feb 28)",
            timestamp: Date().addingTimeInterval(-7100)
        ),
        Highlight(
            id: UUID(),
            type: .action,
            content: "Alex to complete API migration testing by Friday",
            timestamp: Date().addingTimeInterval(-7180)
        ),
        Highlight(
            id: UUID(),
            type: .action,
            content: "Sarah to schedule database migration review for Thursday",
            timestamp: Date().addingTimeInterval(-7000)
        ),
        Highlight(
            id: UUID(),
            type: .keyPoint,
            content: "Performance profiling needed for search feature before release",
            timestamp: Date().addingTimeInterval(-6890)
        )
    ]
    
    static let samplePeople: [Person] = [
        Person(
            id: UUID(),
            name: "Sarah Chen",
            mentionCount: 5,
            topics: ["Timeline", "Planning", "Coordination"]
        ),
        Person(
            id: UUID(),
            name: "Alex Kim",
            mentionCount: 4,
            topics: ["API Migration", "Performance", "Backend"]
        ),
        Person(
            id: UUID(),
            name: "Mike Johnson",
            mentionCount: 2,
            topics: ["Frontend", "Integration"]
        )
    ]
    
    static let sampleSummary = """
    The team discussed progress on the API migration project. Alex reported good progress and expects to have the API ready for testing by Friday. Mike will begin frontend integration work early next week.

    Key decisions:
    - Target completion date set for end of next week (February 28)
    - Database migration review meeting to be scheduled for Thursday
    - Performance profiling required for the new search feature before release

    Next steps involve coordination with the DevOps team for the database migration planning.
    """
}
