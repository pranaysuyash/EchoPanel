import Foundation

enum MinutesOfMeetingTemplate: String, CaseIterable, Identifiable {
    case standard = "Default"
    case executive = "Executive"
    case engineering = "Engineering"

    var id: String { rawValue }

    var filenameSuffix: String {
        switch self {
        case .standard:
            return "mom"
        case .executive:
            return "mom-executive"
        case .engineering:
            return "mom-engineering"
        }
    }
}

struct MinutesOfMeetingAction: Equatable {
    let text: String
    let owner: String?
    let due: String?
}

struct MinutesOfMeetingInput: Equatable {
    let title: String
    let date: Date?
    let durationSeconds: Int?
    let attendees: [String]
    let summary: String
    let actions: [MinutesOfMeetingAction]
    let decisions: [String]
    let risks: [String]
    let topics: [String]
    let highlights: [String]
}

enum MinutesOfMeetingGenerator {
    static func generate(from input: MinutesOfMeetingInput, template: MinutesOfMeetingTemplate) -> String {
        var lines: [String] = []
        lines.append("# \(input.title)")
        lines.append("")

        if let date = input.date {
            lines.append("**Date:** \(formatDate(date))")
        }
        if let durationSeconds = input.durationSeconds {
            lines.append("**Duration:** \(formatDuration(durationSeconds))")
        }
        if !input.attendees.isEmpty {
            lines.append("**Attendees:** \(input.attendees.joined(separator: ", "))")
        }
        if !lines.last.map({ $0.isEmpty })! {
            lines.append("")
        }

        switch template {
        case .standard:
            appendSummarySection(to: &lines, summary: input.summary)
            appendDecisionsSection(to: &lines, decisions: input.decisions)
            appendActionsSection(to: &lines, actions: input.actions)
            appendRisksSection(to: &lines, risks: input.risks)
            appendTopicsSection(to: &lines, topics: input.topics)
            appendAgendaSection(to: &lines, items: agendaItems(from: input))
        case .executive:
            appendSummarySection(to: &lines, summary: input.summary)
            appendDecisionsSection(to: &lines, decisions: input.decisions)
            appendActionsSection(to: &lines, actions: input.actions)
            appendAgendaSection(to: &lines, items: agendaItems(from: input))
        case .engineering:
            appendSummarySection(to: &lines, summary: input.summary)
            appendDecisionsSection(to: &lines, decisions: input.decisions)
            appendActionsSection(to: &lines, actions: input.actions)
            appendRisksSection(to: &lines, risks: input.risks)
            appendTopicsSection(to: &lines, topics: input.topics)
            appendHighlightsSection(to: &lines, highlights: input.highlights)
        }

        return lines.joined(separator: "\n")
    }

    static func buildInput(
        title: String,
        sessionStart: Date?,
        sessionEnd: Date?,
        transcriptSegments: [TranscriptSegment],
        actions: [ActionItem],
        decisions: [DecisionItem],
        risks: [RiskItem],
        entities: [EntityItem],
        finalSummaryMarkdown: String
    ) -> MinutesOfMeetingInput {
        let attendees = extractAttendees(from: transcriptSegments)
        let summary = extractSummary(from: finalSummaryMarkdown, fallbackSegments: transcriptSegments)
        let actionItems = actions.map { MinutesOfMeetingAction(text: $0.text, owner: $0.owner, due: $0.due) }
        let decisionItems = decisions.map { $0.text }
        let riskItems = risks.map { $0.text }
        let topicItems = extractTopics(from: entities)
        let highlights = extractHighlights(from: transcriptSegments)
        let durationSeconds = sessionDurationSeconds(start: sessionStart, end: sessionEnd)

        return MinutesOfMeetingInput(
            title: title,
            date: sessionStart,
            durationSeconds: durationSeconds,
            attendees: attendees,
            summary: summary,
            actions: actionItems,
            decisions: decisionItems,
            risks: riskItems,
            topics: topicItems,
            highlights: highlights
        )
    }

    static func buildInput(from snapshot: [String: Any], fallbackTitle: String) -> MinutesOfMeetingInput {
        let session = snapshot["session"] as? [String: Any]
        let transcript = snapshot["transcript"] as? [[String: Any]] ?? []
        let actions = snapshot["actions"] as? [[String: Any]] ?? []
        let decisions = snapshot["decisions"] as? [[String: Any]] ?? []
        let risks = snapshot["risks"] as? [[String: Any]] ?? []
        let entities = snapshot["entities"] as? [[String: Any]] ?? []
        let finalSummary = (snapshot["final_summary"] as? [String: Any])?["markdown"] as? String ?? ""

        let sessionStart = parseISO8601(session?["started_at"] as? String)
        let sessionEnd = parseISO8601(session?["ended_at"] as? String)
        let durationSeconds = sessionDurationSeconds(start: sessionStart, end: sessionEnd)

        let segments = transcript.compactMap { item -> TranscriptSegment? in
            guard let text = item["text"] as? String,
                  let t0 = item["t0"] as? TimeInterval,
                  let t1 = item["t1"] as? TimeInterval else { return nil }
            let confidence = (item["confidence"] as? Double) ?? 0.0
            let isFinal = (item["is_final"] as? Bool) ?? true
            let source = item["source"] as? String
            var segment = TranscriptSegment(text: text, t0: t0, t1: t1, isFinal: isFinal, confidence: confidence, source: source)
            segment.speaker = item["speaker"] as? String
            return segment
        }

        let attendees = extractAttendees(from: segments)
        let summary = extractSummary(from: finalSummary, fallbackSegments: segments)

        let actionItems = actions.compactMap { item -> MinutesOfMeetingAction? in
            guard let text = item["text"] as? String else { return nil }
            return MinutesOfMeetingAction(
                text: text,
                owner: item["owner"] as? String,
                due: item["due"] as? String
            )
        }

        let decisionItems = decisions.compactMap { item in
            item["text"] as? String
        }

        let riskItems = risks.compactMap { item in
            item["text"] as? String
        }

        let topicItems = entities.compactMap { item in
            item["name"] as? String
        }
        let highlights = extractHighlights(from: segments)

        return MinutesOfMeetingInput(
            title: fallbackTitle,
            date: sessionStart,
            durationSeconds: durationSeconds,
            attendees: attendees,
            summary: summary,
            actions: actionItems,
            decisions: decisionItems,
            risks: riskItems,
            topics: topicItems,
            highlights: highlights
        )
    }

    private static func agendaItems(from input: MinutesOfMeetingInput) -> [String] {
        var items: [String] = []
        if !input.actions.isEmpty {
            items.append("Review action items and ownership")
        }
        if !input.decisions.isEmpty {
            items.append("Confirm decisions and next steps")
        }
        if !input.risks.isEmpty {
            items.append("Address open risks or blockers")
        }
        if items.isEmpty {
            items.append("Confirm next meeting objectives")
        }
        return items
    }

    private static func appendSummarySection(to lines: inout [String], summary: String) {
        lines.append("## Summary")
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("_No summary available._")
        } else {
            lines.append(summary)
        }
        lines.append("")
    }

    private static func appendDecisionsSection(to lines: inout [String], decisions: [String]) {
        lines.append("## Decisions")
        if decisions.isEmpty {
            lines.append("_No decisions recorded._")
        } else {
            decisions.forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private static func appendActionsSection(to lines: inout [String], actions: [MinutesOfMeetingAction]) {
        lines.append("## Action Items")
        if actions.isEmpty {
            lines.append("_No action items recorded._")
        } else {
            actions.forEach { action in
                var line = "- [ ]"
                if let owner = action.owner, !owner.isEmpty {
                    line += " \(owner):"
                }
                line += " \(action.text)"
                if let due = action.due, !due.isEmpty {
                    line += " (Due: \(due))"
                }
                lines.append(line)
            }
        }
        lines.append("")
    }

    private static func appendRisksSection(to lines: inout [String], risks: [String]) {
        lines.append("## Risks / Blockers")
        if risks.isEmpty {
            lines.append("_No risks recorded._")
        } else {
            risks.forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private static func appendTopicsSection(to lines: inout [String], topics: [String]) {
        lines.append("## Key Topics")
        if topics.isEmpty {
            lines.append("_No key topics recorded._")
        } else {
            topics.prefix(8).forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private static func appendHighlightsSection(to lines: inout [String], highlights: [String]) {
        lines.append("## Highlights")
        if highlights.isEmpty {
            lines.append("_No highlights recorded._")
        } else {
            highlights.forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private static func appendAgendaSection(to lines: inout [String], items: [String]) {
        lines.append("## Follow-up Agenda")
        if items.isEmpty {
            lines.append("_No follow-up agenda recorded._")
        } else {
            items.forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private static func extractAttendees(from segments: [TranscriptSegment]) -> [String] {
        var seen = Set<String>()
        var attendees: [String] = []

        for segment in segments where segment.isFinal {
            if let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines), !speaker.isEmpty {
                if seen.insert(speaker).inserted {
                    attendees.append(speaker)
                }
                continue
            }
            if let source = segment.source?.lowercased() {
                let name: String?
                if source == "mic" || source == "microphone" {
                    name = "You"
                } else if source == "system" {
                    name = nil
                } else {
                    name = source.capitalized
                }
                if let name, seen.insert(name).inserted {
                    attendees.append(name)
                }
            }
        }

        return attendees
    }

    private static func extractTopics(from entities: [EntityItem]) -> [String] {
        let sorted = entities.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }
        return sorted.map { $0.name }
    }

    private static func extractHighlights(from segments: [TranscriptSegment]) -> [String] {
        let finalSegments = segments.filter { $0.isFinal }
        return finalSegments.prefix(5).map { segment in
            let who: String
            if let speaker = segment.speaker, !speaker.isEmpty {
                who = speaker
            } else if let source = segment.source?.lowercased() {
                who = (source == "mic" || source == "microphone") ? "You" : "System"
            } else {
                who = "Unknown"
            }
            return "\(who): \(segment.text)"
        }
    }

    private static func extractSummary(from markdown: String, fallbackSegments: [TranscriptSegment]) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let lines = trimmed
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { !$0.hasPrefix("#") }
                .map { line in
                    if line.hasPrefix("- ") {
                        return String(line.dropFirst(2))
                    }
                    return line
                }

            if !lines.isEmpty {
                return lines.prefix(3).joined(separator: " ")
            }
        }

        let fallback = fallbackSegments
            .filter { $0.isFinal }
            .prefix(3)
            .map { $0.text }
            .joined(separator: " ")

        return fallback
    }

    private static func sessionDurationSeconds(start: Date?, end: Date?) -> Int? {
        guard let start, let end else { return nil }
        let seconds = Int(end.timeIntervalSince(start))
        return max(seconds, 0)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
