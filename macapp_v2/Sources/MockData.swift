import Foundation

struct MockFlowPayload {
    let summary: String
    let transcript: [TranscriptItem]
    let highlights: [Highlight]
    let people: [Person]
    let sessions: [Session]
}

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

    static func payload(for flow: MockFlowTrack) -> MockFlowPayload {
        switch flow {
        case .teamStandup:
            return MockFlowPayload(
                summary: sampleSummary,
                transcript: sampleTranscript,
                highlights: sampleHighlights,
                people: samplePeople,
                sessions: sampleSessions
            )
        case .customerEscalation:
            let transcript = [
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "Escalation from Orion Labs: sync failures after yesterday's patch.", timestamp: Date().addingTimeInterval(-3400), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Ravi (Backend)", text: "Root cause looks like stale token refresh in the websocket gateway.", timestamp: Date().addingTimeInterval(-3340)),
                TranscriptItem(id: UUID(), speaker: "Iris (Product)", text: "We need a customer update in 30 minutes with mitigation and ETA.", timestamp: Date().addingTimeInterval(-3290), actionItem: ActionItem(id: UUID(), assignee: "Iris", task: "Send customer mitigation note in 30 minutes")),
                TranscriptItem(id: UUID(), speaker: "Ravi (Backend)", text: "Hotfix proposal: invalidate old refresh window and force re-auth once.", timestamp: Date().addingTimeInterval(-3210), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "I'll track the top 10 affected accounts and monitor recovery trend.", timestamp: Date().addingTimeInterval(-3140), actionItem: ActionItem(id: UUID(), assignee: "Maya", task: "Monitor top 10 affected accounts"))
            ]
            let highlights = [
                Highlight(id: UUID(), type: .decision, content: "Ship websocket token hotfix with forced one-time re-auth", timestamp: Date().addingTimeInterval(-3210)),
                Highlight(id: UUID(), type: .action, content: "Iris to send mitigation and ETA update to Orion Labs", timestamp: Date().addingTimeInterval(-3290)),
                Highlight(id: UUID(), type: .keyPoint, content: "Incident scope narrowed to stale refresh window", timestamp: Date().addingTimeInterval(-3340))
            ]
            let summary = """
            Customer escalation triage focused on websocket sync failures linked to token refresh behavior.
            The team agreed on a hotfix with forced re-auth and set immediate customer communication.
            Monitoring ownership and a short recovery window were assigned.
            """
            return payloadFrom(flowTitle: flow.title, summary: summary, transcript: transcript, highlights: highlights)
        case .hiringLoop:
            let transcript = [
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "Candidate showed strong systems design and clear trade-off reasoning.", timestamp: Date().addingTimeInterval(-5200), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "Coding round had one bug, but debugging approach was calm and methodical.", timestamp: Date().addingTimeInterval(-5140)),
                TranscriptItem(id: UUID(), speaker: "Nina (Product)", text: "Product sense was practical. I'd like one follow-up on stakeholder communication.", timestamp: Date().addingTimeInterval(-5060), actionItem: ActionItem(id: UUID(), assignee: "Nina", task: "Run 20-min stakeholder communication follow-up")),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "Tentative signal is strong hire pending follow-up panel outcome.", timestamp: Date().addingTimeInterval(-4980), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "I'll draft final rubric notes before EOD.", timestamp: Date().addingTimeInterval(-4920), actionItem: ActionItem(id: UUID(), assignee: "Leo", task: "Submit final rubric notes by EOD"))
            ]
            let highlights = [
                Highlight(id: UUID(), type: .decision, content: "Provisional strong-hire decision pending communication follow-up", timestamp: Date().addingTimeInterval(-4980)),
                Highlight(id: UUID(), type: .action, content: "Nina to run communication follow-up panel", timestamp: Date().addingTimeInterval(-5060)),
                Highlight(id: UUID(), type: .question, content: "Can candidate align executives without over-indexing on technical detail?", timestamp: Date().addingTimeInterval(-5030))
            ]
            let summary = """
            Debrief converged on a strong technical signal with one communication gap to validate.
            Team selected a focused follow-up interview rather than extending the loop.
            """
            return payloadFrom(flowTitle: flow.title, summary: summary, transcript: transcript, highlights: highlights)
        case .launchWarRoom:
            let transcript = [
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "Traffic is 2.2x forecast; checkout latency is breaching p95 target.", timestamp: Date().addingTimeInterval(-1800), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Noah (Infra)", text: "Autoscaling is active, but warmup lag is causing spikes during bursts.", timestamp: Date().addingTimeInterval(-1740)),
                TranscriptItem(id: UUID(), speaker: "Evan (Frontend)", text: "We'll temporarily disable heavy personalization module to reduce render cost.", timestamp: Date().addingTimeInterval(-1680), actionItem: ActionItem(id: UUID(), assignee: "Evan", task: "Toggle lightweight checkout experience")),
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "Decision: prioritize conversion stability over personalization for this window.", timestamp: Date().addingTimeInterval(-1600), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Noah (Infra)", text: "Infra patch ready in 12 minutes with pre-warm strategy.", timestamp: Date().addingTimeInterval(-1530), actionItem: ActionItem(id: UUID(), assignee: "Noah", task: "Deploy infra pre-warm patch"))
            ]
            let highlights = [
                Highlight(id: UUID(), type: .decision, content: "Temporarily disable heavy personalization to protect conversion", timestamp: Date().addingTimeInterval(-1600)),
                Highlight(id: UUID(), type: .action, content: "Noah to deploy pre-warm infra patch in 12 minutes", timestamp: Date().addingTimeInterval(-1530)),
                Highlight(id: UUID(), type: .keyPoint, content: "Traffic 2.2x forecast causing checkout latency spikes", timestamp: Date().addingTimeInterval(-1800))
            ]
            let summary = """
            Launch war room optimized for stability under elevated traffic.
            Team aligned on a temporary UX trade-off while infrastructure catches up.
            """
            return payloadFrom(flowTitle: flow.title, summary: summary, transcript: transcript, highlights: highlights)
        }
    }

    static func people(from transcript: [TranscriptItem], fallback: [Person] = samplePeople) -> [Person] {
        guard !transcript.isEmpty else { return fallback }

        var counts: [String: Int] = [:]
        for item in transcript {
            counts[item.speaker, default: 0] += 1
        }

        return counts
            .sorted { $0.value > $1.value }
            .map { speaker, mentions in
                Person(id: UUID(), name: speaker, mentionCount: mentions, topics: ["Flow rehearsal", "Mock scenario"])
            }
    }

    private static func payloadFrom(
        flowTitle: String,
        summary: String,
        transcript: [TranscriptItem],
        highlights: [Highlight]
    ) -> MockFlowPayload {
        let derivedPeople = people(from: transcript)

        let primary = Session(
            id: UUID(),
            title: flowTitle,
            startTime: Date().addingTimeInterval(-5400),
            duration: max(900, transcript.count * 180),
            transcript: transcript,
            highlights: highlights
        )

        let recent = Session(
            id: UUID(),
            title: "\(flowTitle) Follow-up",
            startTime: Date().addingTimeInterval(-86400),
            duration: max(600, transcript.count * 120),
            transcript: Array(transcript.prefix(max(2, transcript.count / 2))),
            highlights: Array(highlights.prefix(2))
        )

        let archive = Session(
            id: UUID(),
            title: "\(flowTitle) Archive",
            startTime: Date().addingTimeInterval(-172800),
            duration: max(480, transcript.count * 100),
            transcript: [],
            highlights: []
        )

        return MockFlowPayload(
            summary: summary,
            transcript: transcript,
            highlights: highlights,
            people: derivedPeople,
            sessions: [primary, recent, archive]
        )
    }
}
