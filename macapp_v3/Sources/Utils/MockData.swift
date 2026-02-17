import Foundation

enum MockData {
    static func generateSessions() -> [Session] {
        [
            generateTeamStandupSession(),
            generateClientCallSession(),
            generateSprintPlanningSession()
        ]
    }
    
    static func generateCalendarEvents() -> [CalendarEvent] {
        let now = Date()
        return [
            CalendarEvent(
                id: UUID(),
                title: "Team Standup",
                startTime: now.addingTimeInterval(3600),
                endTime: now.addingTimeInterval(3900),
                meetingURL: "https://zoom.us/j/123456",
                attendees: ["Sarah Chen", "Alex Kim", "Mike Johnson", "You"],
                isrecurring: true
            ),
            CalendarEvent(
                id: UUID(),
                title: "1:1 with Sarah",
                startTime: now.addingTimeInterval(86400),
                endTime: now.addingTimeInterval(88200),
                meetingURL: "https://meet.google.com/abc-defg-hij",
                attendees: ["Sarah Chen", "You"],
                isrecurring: false
            ),
            CalendarEvent(
                id: UUID(),
                title: "Sprint Planning",
                startTime: now.addingTimeInterval(172800),
                endTime: now.addingTimeInterval(180000),
                meetingURL: "https://zoom.us/j/789012",
                attendees: ["Alex Kim", "Mike Johnson", "Jordan Lee", "Taylor Swift", "You"],
                isrecurring: true
            ),
            CalendarEvent(
                id: UUID(),
                title: "Client Call - Acme Corp",
                startTime: now.addingTimeInterval(259200),
                endTime: now.addingTimeInterval(267000),
                meetingURL: "https://teams.microsoft.com/l/meetup-join/abc123",
                attendees: ["John Smith", "Jane Doe", "You"],
                isrecurring: false
            ),
            CalendarEvent(
                id: UUID(),
                title: "Design Review",
                startTime: now.addingTimeInterval(345600),
                endTime: now.addingTimeInterval(352800),
                meetingURL: "https://zoom.us/j/456789",
                attendees: ["Design Team", "You"],
                isrecurring: true
            )
        ]
    }
    
    static func generateTeamStandupSession() -> Session {
        let sessionId = UUID()
        let startTime = Date().addingTimeInterval(-7200) // 2 hours ago
        
        // Live transcript segments (as they would appear during recording)
        let liveTranscript: [LiveTranscriptSegment] = [
            LiveTranscriptSegment(
                id: UUID(),
                text: "Good morning everyone. Let's start with updates from the backend team.",
                timestamp: startTime,
                isPartial: false,
                confidence: 0.95,
                audioSource: .microphone
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "We've made good progress on the API migration.",
                timestamp: startTime.addingTimeInterval(5),
                isPartial: false,
                confidence: 0.92,
                audioSource: .system
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Should be ready for testing by Friday.",
                timestamp: startTime.addingTimeInterval(8),
                isPartial: false,
                confidence: 0.94,
                audioSource: .system
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Great. What's the timeline for the frontend integration?",
                timestamp: startTime.addingTimeInterval(15),
                isPartial: false,
                confidence: 0.96,
                audioSource: .microphone
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "I can start on that once Alex gives me the endpoints. Probably early next week.",
                timestamp: startTime.addingTimeInterval(20),
                isPartial: false,
                confidence: 0.91,
                audioSource: .system
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Perfect. Let's aim to have everything integrated by the end of next week then.",
                timestamp: startTime.addingTimeInterval(28),
                isPartial: false,
                confidence: 0.93,
                audioSource: .microphone
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "One more thing - we should review the database migration plan before we go live.",
                timestamp: startTime.addingTimeInterval(35),
                isPartial: false,
                confidence: 0.90,
                audioSource: .system
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Good point. Let's schedule a separate meeting for that. Maybe Thursday?",
                timestamp: startTime.addingTimeInterval(42),
                isPartial: false,
                confidence: 0.94,
                audioSource: .microphone
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Thursday works for me. Should we invite the DevOps team?",
                timestamp: startTime.addingTimeInterval(48),
                isPartial: false,
                confidence: 0.92,
                audioSource: .system
            ),
            LiveTranscriptSegment(
                id: UUID(),
                text: "Yes, definitely. I'll send out an invite.",
                timestamp: startTime.addingTimeInterval(54),
                isPartial: false,
                confidence: 0.95,
                audioSource: .microphone
            )
        ]
        
        // Final transcript with speaker labels (after diarization)
        let finalTranscript: [FinalTranscriptSegment] = [
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Good morning everyone. Let's start with updates from the backend team.",
                timestamp: startTime,
                confidence: 0.95,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_2",
                speakerName: "Alex Kim",
                text: "We've made good progress on the API migration. Should be ready for testing by Friday.",
                timestamp: startTime.addingTimeInterval(5),
                confidence: 0.92,
                highlights: ["highlight_1"]
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Great. What's the timeline for the frontend integration?",
                timestamp: startTime.addingTimeInterval(15),
                confidence: 0.96,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_3",
                speakerName: "Mike Johnson",
                text: "I can start on that once Alex gives me the endpoints. Probably early next week.",
                timestamp: startTime.addingTimeInterval(20),
                confidence: 0.91,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Perfect. Let's aim to have everything integrated by the end of next week then.",
                timestamp: startTime.addingTimeInterval(28),
                confidence: 0.93,
                highlights: ["highlight_2"]
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_2",
                speakerName: "Alex Kim",
                text: "One more thing - we should review the database migration plan before we go live.",
                timestamp: startTime.addingTimeInterval(35),
                confidence: 0.90,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Good point. Let's schedule a separate meeting for that. Maybe Thursday?",
                timestamp: startTime.addingTimeInterval(42),
                confidence: 0.94,
                highlights: ["highlight_3"]
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_3",
                speakerName: "Mike Johnson",
                text: "Thursday works for me. Should we invite the DevOps team?",
                timestamp: startTime.addingTimeInterval(48),
                confidence: 0.92,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Yes, definitely. I'll send out an invite.",
                timestamp: startTime.addingTimeInterval(54),
                confidence: 0.95,
                highlights: ["highlight_3"]
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_2",
                speakerName: "Alex Kim",
                text: "Also, I noticed some performance issues with the new search feature. We should profile it before release.",
                timestamp: startTime.addingTimeInterval(62),
                confidence: 0.88,
                highlights: ["highlight_4"]
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_1",
                speakerName: "Sarah Chen",
                text: "Absolutely. Performance is critical for this release. Alex, can you take point on that?",
                timestamp: startTime.addingTimeInterval(70),
                confidence: 0.94,
                highlights: []
            ),
            FinalTranscriptSegment(
                id: UUID(),
                speakerId: "speaker_2",
                speakerName: "Alex Kim",
                text: "Sure thing. I'll run some benchmarks and report back.",
                timestamp: startTime.addingTimeInterval(76),
                confidence: 0.93,
                highlights: ["highlight_5"]
            )
        ]
        
        // Highlights
        let highlights: [Highlight] = [
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001") ?? UUID(),
                type: .action(ActionItem(
                    id: UUID(),
                    assignee: "Alex Kim",
                    task: "Complete API migration testing",
                    dueDate: Date().addingTimeInterval(86400 * 3), // Friday
                    isCompleted: false
                )),
                timestamp: startTime.addingTimeInterval(5),
                confidence: 0.85,
                transcriptSegmentId: finalTranscript[1].id,
                evidence: "Should be ready for testing by Friday"
            ),
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440002") ?? UUID(),
                type: .decision(Decision(
                    id: UUID(),
                    statement: "Complete full integration by end of next week",
                    stakeholders: ["Sarah Chen", "Alex Kim", "Mike Johnson"]
                )),
                timestamp: startTime.addingTimeInterval(28),
                confidence: 0.92,
                transcriptSegmentId: finalTranscript[4].id,
                evidence: "Let's aim to have everything integrated by the end of next week"
            ),
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440003") ?? UUID(),
                type: .action(ActionItem(
                    id: UUID(),
                    assignee: "Sarah Chen",
                    task: "Schedule database migration review meeting",
                    dueDate: Date().addingTimeInterval(86400), // Tomorrow
                    isCompleted: false
                )),
                timestamp: startTime.addingTimeInterval(42),
                confidence: 0.88,
                transcriptSegmentId: finalTranscript[6].id,
                evidence: "I'll send out an invite"
            ),
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440004") ?? UUID(),
                type: .risk(Risk(
                    id: UUID(),
                    description: "Performance issues with new search feature",
                    severity: .medium,
                    mitigation: "Profile before release"
                )),
                timestamp: startTime.addingTimeInterval(62),
                confidence: 0.75,
                transcriptSegmentId: finalTranscript[9].id,
                evidence: "We should profile it before release"
            ),
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440005") ?? UUID(),
                type: .action(ActionItem(
                    id: UUID(),
                    assignee: "Alex Kim",
                    task: "Profile search performance and report findings",
                    dueDate: nil,
                    isCompleted: false
                )),
                timestamp: startTime.addingTimeInterval(76),
                confidence: 0.90,
                transcriptSegmentId: finalTranscript[11].id,
                evidence: "I'll run some benchmarks and report back"
            ),
            Highlight(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440006") ?? UUID(),
                type: .keyPoint("Database migration review needed before go-live"),
                timestamp: startTime.addingTimeInterval(35),
                confidence: 0.82,
                transcriptSegmentId: finalTranscript[5].id,
                evidence: "we should review the database migration plan"
            )
        ]
        
        // Entities
        let entities = SessionEntities(
            people: [
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Sarah Chen",
                    mentionCount: 5,
                    firstMentioned: startTime,
                    lastMentioned: startTime.addingTimeInterval(76),
                    quotes: ["Let's aim to have everything integrated", "I'll send out an invite"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Alex Kim",
                    mentionCount: 4,
                    firstMentioned: startTime.addingTimeInterval(5),
                    lastMentioned: startTime.addingTimeInterval(76),
                    quotes: ["We've made good progress", "Should be ready for testing by Friday"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Mike Johnson",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(20),
                    lastMentioned: startTime.addingTimeInterval(48),
                    quotes: ["I can start on that once Alex gives me the endpoints"]
                )
            ],
            organizations: [
                SessionEntities.Entity(
                    id: UUID(),
                    name: "DevOps Team",
                    mentionCount: 1,
                    firstMentioned: startTime.addingTimeInterval(48),
                    lastMentioned: startTime.addingTimeInterval(48),
                    quotes: ["Should we invite the DevOps team?"]
                )
            ],
            dates: [
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Friday",
                    mentionCount: 1,
                    firstMentioned: startTime.addingTimeInterval(5),
                    lastMentioned: startTime.addingTimeInterval(5),
                    quotes: ["Should be ready for testing by Friday"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Next Week",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(20),
                    lastMentioned: startTime.addingTimeInterval(28),
                    quotes: ["Probably early next week", "by the end of next week"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Thursday",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(42),
                    lastMentioned: startTime.addingTimeInterval(48),
                    quotes: ["Maybe Thursday?", "Thursday works for me"]
                )
            ],
            topics: [
                SessionEntities.Entity(
                    id: UUID(),
                    name: "API Migration",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(5),
                    lastMentioned: startTime.addingTimeInterval(20),
                    quotes: ["progress on the API migration", "Alex gives me the endpoints"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Database Migration",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(35),
                    lastMentioned: startTime.addingTimeInterval(42),
                    quotes: ["review the database migration plan", "Schedule database migration review"]
                ),
                SessionEntities.Entity(
                    id: UUID(),
                    name: "Performance",
                    mentionCount: 2,
                    firstMentioned: startTime.addingTimeInterval(62),
                    lastMentioned: startTime.addingTimeInterval(76),
                    quotes: ["performance issues", "Profile search performance"]
                )
            ]
        )
        
        return Session(
            id: sessionId,
            title: "Team Standup",
            startTime: startTime,
            duration: 1800,
            status: .finalized,
            liveTranscript: liveTranscript,
            finalTranscript: finalTranscript,
            highlights: highlights,
            entities: entities,
            summary: "The team discussed progress on the API migration project. Alex reported good progress and expects to have the API ready for testing by Friday. Mike will begin frontend integration work early next week. Key decisions: Target completion date set for end of next week (February 28). Database migration review meeting to be scheduled for Thursday. Performance profiling required for the new search feature before release. Next steps involve coordination with the DevOps team for the database migration planning.",
            audioSource: .systemAndMic,
            provider: .fasterWhisper,
            isPinned: false,
            tags: ["standup", "api", "planning"],
            voiceNotes: [],
            pinnedMoments: [],
            meetingTemplate: MeetingTemplate.defaults[0]
        )
    }
    
    static func generateClientCallSession() -> Session {
        let sessionId = UUID()
        let startTime = Date().addingTimeInterval(-36000) // 10 hours ago
        
        return Session(
            id: sessionId,
            title: "Client Call - Acme Corp",
            startTime: startTime,
            duration: 2700,
            status: .finalized,
            liveTranscript: [],
            finalTranscript: [],
            highlights: [],
            entities: SessionEntities(people: [], organizations: [], dates: [], topics: []),
            summary: nil,
            audioSource: .systemOnly,
            provider: .whisperCpp,
            isPinned: true,
            tags: ["client", "acme-corp"],
            voiceNotes: [],
            pinnedMoments: [],
            meetingTemplate: nil
        )
    }
    
    static func generateSprintPlanningSession() -> Session {
        let sessionId = UUID()
        let startTime = Date().addingTimeInterval(-86400)
        
        return Session(
            id: sessionId,
            title: "Sprint Planning",
            startTime: startTime,
            duration: 3600,
            status: .finalized,
            liveTranscript: [],
            finalTranscript: [],
            highlights: [],
            entities: SessionEntities(people: [], organizations: [], dates: [], topics: []),
            summary: nil,
            audioSource: .systemAndMic,
            provider: .auto,
            isPinned: false,
            tags: ["sprint", "planning", "agile"],
            voiceNotes: [],
            pinnedMoments: [],
            meetingTemplate: MeetingTemplate.defaults[2]
        )
    }
    
    // Generate final transcript from live transcript (simulating post-processing)
    static func generateFinalTranscript(from liveTranscript: [LiveTranscriptSegment]) -> [FinalTranscriptSegment] {
        let speakerNames = ["Alice Johnson", "Bob Chen", "Carol Davis", "David Martinez"]
        let voiceCharacteristics = ["host", "guest", "moderator", "expert"]

        return liveTranscript.enumerated().map { index, live in
            let speakerIndex = index % speakerNames.count
            let voiceIndex = index % voiceCharacteristics.count

            return FinalTranscriptSegment(
                id: live.id,
                speakerId: "speaker_\(speakerIndex + 1)_\(voiceCharacteristics[voiceIndex])",
                speakerName: speakerNames[speakerIndex],
                text: live.text,
                timestamp: live.timestamp,
                confidence: live.confidence,
                highlights: []
            )
        }
    }
    
    static func generateEntities() -> SessionEntities {
        SessionEntities(
            people: [],
            organizations: [],
            dates: [],
            topics: []
        )
    }
    
    static func generateHighlights() -> [Highlight] {
        []
    }
    
    static func generateSummary() -> String {
        "Meeting summary would be generated here by LLM or extraction algorithms."
    }
}
