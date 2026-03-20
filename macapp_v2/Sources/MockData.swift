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

    // MARK: - Expanded Flow Payloads
    
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
            // 15 items, 5 highlights, 4 people - angry customer, escalation steps, ownership
            let transcript: [TranscriptItem] = [
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "Urgent escalation from Orion Labs - they're seeing sync failures across their entire team since this morning.", timestamp: Date().addingTimeInterval(-4500), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Raj (Engineering)", text: "How many users are affected? This sounds like it could be related to yesterday's gateway patch.", timestamp: Date().addingTimeInterval(-4470)),
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "They're saying around 200 users affected. The CEO is personally asking for an update.", timestamp: Date().addingTimeInterval(-4440)),
                TranscriptItem(id: UUID(), speaker: "Iris (Product)", text: "What's the business impact? Are they losing revenue?", timestamp: Date().addingTimeInterval(-4410)),
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "Teams can't collaborate on shared documents. They're considering switching vendors if we can't fix this today.", timestamp: Date().addingTimeInterval(-4380), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Raj (Engineering)", text: "I think I found it - the token refresh window is using stale credentials after the patch. Classic cache invalidation bug.", timestamp: Date().addingTimeInterval(-4320)),
                TranscriptItem(id: UUID(), speaker: "Leo (Backend)", text: "That matches the error logs I'm seeing. Should be a quick fix - just need to invalidate the old tokens.", timestamp: Date().addingTimeInterval(-4290)),
                TranscriptItem(id: UUID(), speaker: "Iris (Product)", text: "We need to send an update to Orion's CTO in the next 20 minutes with our diagnosis and ETA.", timestamp: Date().addingTimeInterval(-4260), actionItem: ActionItem(id: UUID(), assignee: "Iris", task: "Send status update to Orion Labs CTO within 20 min")),
                TranscriptItem(id: UUID(), speaker: "Raj (Engineering)", text: "Hotfix is ready. We need a 15-minute deployment window. Leo, can you prep the rollback?", timestamp: Date().addingTimeInterval(-4200), actionItem: ActionItem(id: UUID(), assignee: "Raj", task: "Prepare hotfix deployment")),
                TranscriptItem(id: UUID(), speaker: "Leo (Backend)", text: "Rollback plan is ready. Deploying in 5 minutes.", timestamp: Date().addingTimeInterval(-4170)),
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "I've identified the top 15 affected enterprise accounts. I'll monitor recovery and keep them updated.", timestamp: Date().addingTimeInterval(-4140), actionItem: ActionItem(id: UUID(), assignee: "Maya", task: "Monitor top 15 accounts and report recovery")),
                TranscriptItem(id: UUID(), speaker: "Raj (Engineering)", text: "Hotfix deployed. Tokens are being refreshed. Seeing recovery in the dashboards now.", timestamp: Date().addingTimeInterval(-4080), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Iris (Product)", text: "Excellent. Maya, please send a follow-up confirming full resolution and our post-mortem timeline.", timestamp: Date().addingTimeInterval(-4050), actionItem: ActionItem(id: UUID(), assignee: "Iris", task: "Send resolution confirmation to Orion Labs")),
                TranscriptItem(id: UUID(), speaker: "Maya (Support Lead)", text: "Confirmed 94% recovery. Final users should clear within 10 minutes. Post-mortem scheduled for tomorrow 9am.", timestamp: Date().addingTimeInterval(-3990)),
                TranscriptItem(id: UUID(), speaker: "Leo (Backend)", text: "Adding automated token refresh validation to prevent this from happening again. Should be in next release.", timestamp: Date().addingTimeInterval(-3960), actionItem: ActionItem(id: UUID(), assignee: "Leo", task: "Add token refresh validation to CI pipeline"))
            ]
            
            let highlights: [Highlight] = [
                Highlight(id: UUID(), type: .keyPoint, content: "Root cause: stale token refresh cache after gateway patch", timestamp: Date().addingTimeInterval(-4320)),
                Highlight(id: UUID(), type: .decision, content: "Deploy hotfix with forced one-time token re-authentication", timestamp: Date().addingTimeInterval(-4200)),
                Highlight(id: UUID(), type: .action, content: "Iris to send status update to Orion CTO within 20 min", timestamp: Date().addingTimeInterval(-4260)),
                Highlight(id: UUID(), type: .action, content: "Maya to monitor top 15 accounts and report recovery", timestamp: Date().addingTimeInterval(-4140)),
                Highlight(id: UUID(), type: .decision, content: "Post-mortem scheduled for next day 9am", timestamp: Date().addingTimeInterval(-3990))
            ]
            
            let summary = """
            Emergency triage for Orion Labs sync outage affecting 200 users.
            
            Root cause identified as stale token refresh cache after yesterday's gateway patch.
            
            Hotfix deployed successfully with 94% recovery within 30 minutes of incident start.
            
            Actions assigned:
            - Iris: Customer communication and resolution follow-up
            - Maya: Ongoing account monitoring  
            - Leo: CI pipeline improvement to prevent recurrence
            
            Post-mortem scheduled to address systemic prevention.
            """
            
            return payloadFrom(
                flowTitle: "Customer Escalation - Orion Labs",
                summary: summary,
                transcript: transcript,
                highlights: highlights,
                participants: ["Maya (Support Lead)", "Raj (Engineering)", "Iris (Product)", "Leo (Backend)"]
            )
            
        case .hiringLoop:
            // 20 items, 4 highlights, 5 people - structured Q&A, feedback, no-hire recommendation
            let transcript: [TranscriptItem] = [
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "Let's debrief the interview loop for the senior backend engineer role. 4 interviews, 2 strong hires, 1 no-hire.", timestamp: Date().addingTimeInterval(-5400)),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "I'll start with the coding round. Problem was medium-difficulty: design a rate limiter. Candidate got to optimal solution but had one off-by-one bug.", timestamp: Date().addingTimeInterval(-5370), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Nina (Product)", text: "What was their debugging approach like?", timestamp: Date().addingTimeInterval(-5340)),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "Calm and methodical. They walked through test cases, found the bug themselves, and fixed it cleanly. Good process.", timestamp: Date().addingTimeInterval(-5310)),
                TranscriptItem(id: UUID(), speaker: "Sam (Architecture)", text: "Systems design was excellent. They designed a distributed rate limiter with clear trade-offs discussed - Redis vs Lua vs token bucket.", timestamp: Date().addingTimeInterval(-5280), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "Strong technical signal overall. What about the product sense round?", timestamp: Date().addingTimeInterval(-5250)),
                TranscriptItem(id: UUID(), speaker: "Nina (Product)", text: "Practical approach to user problems. They asked good questions about the target users and constraints. Not all candidates do that.", timestamp: Date().addingTimeInterval(-5220)),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "They did seem to struggle when I introduced ambiguity about priorities. Got a bit paralyzed.", timestamp: Date().addingTimeInterval(-5190)),
                TranscriptItem(id: UUID(), speaker: "Nina (Product)", text: "I noticed that too. They defaulted to technical solutions when stakeholder alignment might have been faster. Worth a follow-up on communication.", timestamp: Date().addingTimeInterval(-5160), actionItem: ActionItem(id: UUID(), assignee: "Nina", task: "Schedule 20-min communication follow-up interview")),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "What about the behavioral round?", timestamp: Date().addingTimeInterval(-5130)),
                TranscriptItem(id: UUID(), speaker: "Priya (HR)", text: "Good stories about past projects. Showed they can work across teams. One concern - they left their last job after only 14 months.", timestamp: Date().addingTimeInterval(-5100)),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "Did they explain why?", timestamp: Date().addingTimeInterval(-5070)),
                TranscriptItem(id: UUID(), speaker: "Priya (HR)", text: "Said the company shifted direction and their role changed. Seems legitimate, but worth validating with reference check.", timestamp: Date().addingTimeInterval(-5040)),
                TranscriptItem(id: UUID(), speaker: "Sam (Architecture)", text: "Technical skills are definitely there. I'd feel comfortable having them on my team.", timestamp: Date().addingTimeInterval(-5010)),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "Same. They exceeded bar on system design and coding.", timestamp: Date().addingTimeInterval(-4980)),
                TranscriptItem(id: UUID(), speaker: "Nina (Product)", text: "I'd want to see how they handle the stakeholder communication aspect before I'd recommend.", timestamp: Date().addingTimeInterval(-4950)),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "So we're looking at: strong technical, good product sense, but uncertain about communication under pressure.", timestamp: Date().addingTimeInterval(-4920), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Priya (HR)", text: "We could do a targeted follow-up? 20 minutes on a scenario where they need to align conflicting stakeholders.", timestamp: Date().addingTimeInterval(-4890)),
                TranscriptItem(id: UUID(), speaker: "Anya (Hiring Manager)", text: "That's reasonable. Let's make it a strong hire if they pass, no-hire if they don't. Nina, can you own the follow-up?", timestamp: Date().addingTimeInterval(-4860), actionItem: ActionItem(id: UUID(), assignee: "Nina", task: "Conduct 20-min stakeholder alignment follow-up")),
                TranscriptItem(id: UUID(), speaker: "Leo (Engineering)", text: "I'll prepare the scenario. Should have something ready by end of week.", timestamp: Date().addingTimeInterval(-4830), actionItem: ActionItem(id: UUID(), assignee: "Leo", task: "Prepare stakeholder alignment scenario for follow-up"))
            ]
            
            let highlights: [Highlight] = [
                Highlight(id: UUID(), type: .keyPoint, content: "Strong technical skills: exceeded bar on system design and coding", timestamp: Date().addingTimeInterval(-5280)),
                Highlight(id: UUID(), type: .question, content: "Concern: struggles with ambiguity and stakeholder communication under pressure", timestamp: Date().addingTimeInterval(-5190)),
                Highlight(id: UUID(), type: .decision, content: "Provisional strong-hire pending 20-min communication follow-up with Nina", timestamp: Date().addingTimeInterval(-4860)),
                Highlight(id: UUID(), type: .action, content: "Leo to prepare stakeholder alignment scenario by end of week", timestamp: Date().addingTimeInterval(-4830))
            ]
            
            let summary = """
            Hiring debrief for Senior Backend Engineer position.
            
            Consensus: Strong technical signal (coding, system design both exceeded bar) with one concern around stakeholder communication under ambiguity.
            
            Decision: Provisional strong-hire pending targeted 20-minute follow-up interview on communication scenarios.
            
            Follow-up assigned to Nina. Leo to prepare scenario material.
            
            Reference check flagged for short tenure at previous employer - appears legitimate but worth validation.
            """
            
            return payloadFrom(
                flowTitle: "Hiring Debrief - Senior Backend Engineer",
                summary: summary,
                transcript: transcript,
                highlights: highlights,
                participants: ["Anya (Hiring Manager)", "Leo (Engineering)", "Nina (Product)", "Sam (Architecture)", "Priya (HR)"]
            )
            
        case .launchWarRoom:
            // 12 items, 4 highlights, 3 people - feature launch pressure, deadline decisions, go/no-go
            let transcript: [TranscriptItem] = [
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "We're 48 hours from GA and traffic is spiking to 2.2x forecast. Checkout latency is already at 1.8 seconds - p95 target is 500ms.", timestamp: Date().addingTimeInterval(-2400), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Noah (Infra)", text: "Autoscaling is triggering but the new instances are hitting cold start latency. Takes 90 seconds to warm up.", timestamp: Date().addingTimeInterval(-2370)),
                TranscriptItem(id: UUID(), speaker: "Evan (Frontend)", text: "Our personalization engine is doing 4 API calls per page render. That's killing Time to Interactive.", timestamp: Date().addingTimeInterval(-2340)),
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "What's our conversion impact? Are we seeing cart abandonment?", timestamp: Date().addingTimeInterval(-2310)),
                TranscriptItem(id: UUID(), speaker: "Evan (Frontend)", text: "Early signals show 12% increase in cart abandonment. Every 100ms of latency costs us roughly 1% conversion.", timestamp: Date().addingTimeInterval(-2280), isPinned: true),
                TranscriptItem(id: UUID(), speaker: "Noah (Infra)", text: "I have a pre-warm script ready. If we deploy now, instances will be warm before peak traffic hits in 30 minutes.", timestamp: Date().addingTimeInterval(-2220), actionItem: ActionItem(id: UUID(), assignee: "Noah", task: "Deploy pre-warm script for instance fleet")),
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "What's the risk if we temporarily disable the personalization engine?", timestamp: Date().addingTimeInterval(-2190)),
                TranscriptItem(id: UUID(), speaker: "Evan (Frontend)", text: "Users will see generic recommendations instead of personalized. We might see a 5% dip in average order value. But latency drops to under 200ms.", timestamp: Date().addingTimeInterval(-2160)),
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "Decision: we need to protect conversion rate over personalization for the launch window. Evan, can you toggle the lightweight checkout?", timestamp: Date().addingTimeInterval(-2100), isPinned: true, actionItem: ActionItem(id: UUID(), assignee: "Evan", task: "Enable lightweight checkout mode - no personalization")),
                TranscriptItem(id: UUID(), speaker: "Noah (Infra)", text: "Deploying pre-warm script now. Should be complete in 8 minutes.", timestamp: Date().addingTimeInterval(-2040)),
                TranscriptItem(id: UUID(), speaker: "Evan (Frontend)", text: "Lightweight checkout is live. Latency is down to 180ms. Abandonment should normalize.", timestamp: Date().addingTimeInterval(-1980), actionItem: ActionItem(id: UUID(), assignee: "Evan", task: "Monitor checkout abandonment rate post-launch")),
                TranscriptItem(id: UUID(), speaker: "Priya (Launch Lead)", text: "Good. We're green for GA. Let's reconvene in 4 hours to reassess. If metrics stabilize, we re-enable personalization incrementally.", timestamp: Date().addingTimeInterval(-1920), isPinned: true, actionItem: ActionItem(id: UUID(), assignee: "Priya", task: "Schedule 4-hour check-in to reassess personalization rollout"))
            ]
            
            let highlights: [Highlight] = [
                Highlight(id: UUID(), type: .keyPoint, content: "Traffic 2.2x forecast causing checkout latency at 1.8s (target: 500ms)", timestamp: Date().addingTimeInterval(-2400)),
                Highlight(id: UUID(), type: .decision, content: "Disable personalization engine temporarily to protect conversion rate", timestamp: Date().addingTimeInterval(-2100)),
                Highlight(id: UUID(), type: .action, content: "Noah to deploy pre-warm script for instance fleet (8 min ETA)", timestamp: Date().addingTimeInterval(-2040)),
                Highlight(id: UUID(), type: .decision, content: "GA approved with lightweight checkout; re-evaluate personalization in 4 hours", timestamp: Date().addingTimeInterval(-1920))
            ]
            
            let summary = """
            Emergency war room to address checkout performance crisis 48 hours before GA.
            
            Situation: Traffic at 2.2x forecast causing 12% cart abandonment spike due to personalization engine overhead.
            
            Decision: Ship lightweight checkout mode (no personalization) to bring latency from 1.8s to under 200ms.
            
            Actions:
            - Noah: Deploy pre-warm script for instance fleet
            - Evan: Monitor abandonment metrics post-launch
            - Priya: 4-hour reassessment meeting scheduled
            
            GA proceeding as planned with degraded personalization feature.
            """
            
            return payloadFrom(
                flowTitle: "Launch War Room - Feature GA",
                summary: summary,
                transcript: transcript,
                highlights: highlights,
                participants: ["Priya (Launch Lead)", "Noah (Infra)", "Evan (Frontend)"]
            )
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
                let topics = topicsFor(speaker: speaker)
                return Person(id: UUID(), name: speaker, mentionCount: mentions, topics: topics)
            }
    }
    
    private static func topicsFor(speaker: String) -> [String] {
        let lowercased = speaker.lowercased()
        if lowercased.contains("engineering") || lowercased.contains("backend") || lowercased.contains("leo") || lowercased.contains("raj") || lowercased.contains("alex") {
            return ["Architecture", "Backend", "Performance"]
        } else if lowercased.contains("product") || lowercased.contains("iris") || lowercased.contains("nina") || lowercased.contains("priya") {
            return ["Strategy", "Roadmap", "Prioritization"]
        } else if lowercased.contains("support") || lowercased.contains("maya") || lowercased.contains("hr") {
            return ["Customer Success", "People", "Operations"]
        } else if lowercased.contains("frontend") || lowercased.contains("evan") || lowercased.contains("mike") {
            return ["UI/UX", "Integration", "Frontend"]
        } else if lowercased.contains("infra") || lowercased.contains("noah") || lowercased.contains("devops") {
            return ["Infrastructure", "Scaling", "Reliability"]
        } else if lowercased.contains("architecture") || lowercased.contains("sam") {
            return ["System Design", "Technical Strategy"]
        } else if lowercased.contains("hiring") || lowercased.contains("anya") {
            return ["Talent", "Interviewing", "Team Building"]
        } else {
            return ["General", "Meetings", "Planning"]
        }
    }

    private static func payloadFrom(
        flowTitle: String,
        summary: String,
        transcript: [TranscriptItem],
        highlights: [Highlight],
        participants: [String]
    ) -> MockFlowPayload {
        let people = participants.map { speaker in
            let mentions = transcript.filter { $0.speaker == speaker }.count
            return Person(
                id: UUID(),
                name: speaker,
                mentionCount: mentions,
                topics: topicsFor(speaker: speaker)
            )
        }

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
            people: people,
            sessions: [primary, recent, archive]
        )
    }
    
    // MARK: - Long Transcript for Stress Testing
    
    static func generateLongTranscript(count: Int = 50) -> [TranscriptItem] {
        let speakers = ["Alice", "Bob", "Charlie", "Diana", "Eve"]
        var items: [TranscriptItem] = []
        
        for i in 0..<count {
            let speaker = speakers[i % speakers.count]
            let timestamp = Date().addingTimeInterval(Double(-3600 + i * 72))
            
            let texts = [
                "I think we should focus on the core functionality first before adding more features.",
                "Has anyone looked at the performance metrics from last week's deployment?",
                "The new API endpoints are working well, but we need better error handling.",
                "I'm concerned about the third-party dependency. Should we consider alternatives?",
                "Let's schedule a deeper dive into the architecture for next sprint.",
                "The user feedback has been positive overall, but there are some edge cases.",
                "I can take point on the documentation update. Should be done by Thursday.",
                "We need to balance speed with quality. Rushing could introduce bugs.",
                "What's the rollback plan if something goes wrong during the deployment?",
                "The testing coverage has improved significantly since last quarter."
            ]
            
            let text = texts[i % texts.count]
            let hasAction = i % 7 == 0
            let isPinned = i % 11 == 0
            
            var actionItem: ActionItem? = nil
            if hasAction {
                actionItem = ActionItem(
                    id: UUID(),
                    assignee: speaker,
                    task: "Follow up on item \(i)",
                    isCompleted: false
                )
            }
            
            items.append(TranscriptItem(
                id: UUID(),
                speaker: speaker,
                text: text,
                timestamp: timestamp,
                isPinned: isPinned,
                actionItem: actionItem
            ))
        }
        
        return items
    }
    
    static var longTranscript: [TranscriptItem] {
        generateLongTranscript(count: 50)
    }
}
