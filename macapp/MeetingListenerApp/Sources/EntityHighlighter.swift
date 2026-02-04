import AppKit
import NaturalLanguage
import SwiftUI

struct EntityMatch: Identifiable, Equatable {
    let id = UUID()
    let range: NSRange
    let entity: EntityItem
}

enum EntityHighlighter {
    enum HighlightMode: String, CaseIterable, Identifiable {
        case off = "Off"
        case extracted = "Extracted"
        case nlp = "NLP"

        var id: String { rawValue }

        var isEnabled: Bool { self != .off }
    }

    private static var nlpCache: [String: [EntityMatch]] = [:]
    private static let nlpCacheLimit = 400

    static func matches(in text: String, entities: [EntityItem]) -> [EntityMatch] {
        guard !text.isEmpty, !entities.isEmpty else { return [] }

        // Sort longer names first to avoid nested overlaps.
        let sorted = entities
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.name.count > $1.name.count }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var used: [NSRange] = []
        var results: [EntityMatch] = []

        for entity in sorted {
            let needle = entity.name
            var searchRange = fullRange

            while true {
                let found = nsText.range(of: needle, options: [.caseInsensitive], range: searchRange)
                if found.location == NSNotFound { break }

                // Ensure we don't overlap previously claimed ranges.
                if !used.contains(where: { NSIntersectionRange($0, found).length > 0 }) {
                    used.append(found)
                    results.append(EntityMatch(range: found, entity: entity))
                }

                let nextLocation = found.location + max(1, found.length)
                if nextLocation >= fullRange.length { break }
                searchRange = NSRange(location: nextLocation, length: fullRange.length - nextLocation)
            }
        }

        // Sort by position for rendering.
        results.sort { $0.range.location < $1.range.location }
        return results
    }

    static func nlpMatches(in text: String) -> [EntityMatch] {
        guard !text.isEmpty else { return [] }

        let cacheKey = "\(text.hashValue)"
        if let cached = nlpCache[cacheKey] {
            return cached
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let fullRange = text.startIndex..<text.endIndex
        var results: [EntityMatch] = []

        tagger.enumerateTags(
            in: fullRange,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard let tag else { return true }

            let label: String
            switch tag {
            case .personalName:
                label = "person"
            case .organizationName:
                label = "org"
            case .placeName:
                label = "place"
            default:
                return true
            }

            let nsRange = NSRange(range, in: text)
            let name = String(text[range])
            let entity = EntityItem(name: name, type: label, count: 1, lastSeen: 0, confidence: 0.0)
            results.append(EntityMatch(range: nsRange, entity: entity))
            return true
        }

        results.sort { $0.range.location < $1.range.location }

        // Tiny bounded cache (best-effort) to reduce repeated tagging work.
        if nlpCache.count > nlpCacheLimit {
            nlpCache.removeAll(keepingCapacity: true)
        }
        nlpCache[cacheKey] = results
        return results
    }

    static func matches(in text: String, entities: [EntityItem], mode: HighlightMode) -> [EntityMatch] {
        switch mode {
        case .off:
            return []
        case .extracted:
            return matches(in: text, entities: entities)
        case .nlp:
            return nlpMatches(in: text)
        }
    }

    static func color(for type: String) -> NSColor {
        switch type.lowercased() {
        case "person":
            return NSColor.systemBlue
        case "org":
            return NSColor.systemIndigo
        case "project":
            return NSColor.systemTeal
        case "topic":
            return NSColor.systemPurple
        case "place":
            return NSColor.systemGreen
        case "date":
            return NSColor.systemOrange
        default:
            return NSColor.systemGray
        }
    }

    static func linkURL(for entity: EntityItem) -> URL {
        // Custom scheme; parsed by EntityTextView delegate.
        let name = entity.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entity.name
        return URL(string: "echopanel-entity://\(entity.type)/\(name)")!
    }
}

struct EntityTextView: NSViewRepresentable {
    let text: String
    let matches: [EntityMatch]
    let highlightsEnabled: Bool
    let onEntityClick: (EntityItem) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.onEntityClick = onEntityClick

        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ],
            range: NSRange(location: 0, length: attributed.length)
        )

        if highlightsEnabled {
            for match in matches {
                let baseColor = EntityHighlighter.color(for: match.entity.type)
                let bg = baseColor.withAlphaComponent(0.12)
                attributed.addAttributes(
                    [
                        .backgroundColor: bg,
                        .link: EntityHighlighter.linkURL(for: match.entity),
                    ],
                    range: match.range
                )
            }
        }

        nsView.textStorage?.setAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEntityClick: ((EntityItem) -> Void)?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            guard url.scheme == "echopanel-entity" else { return false }

            let type = url.host ?? "unknown"
            let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let decoded = name.removingPercentEncoding ?? name
            onEntityClick?(EntityItem(name: decoded, type: type, count: 1, lastSeen: 0, confidence: 0.0))
            return true
        }
    }
}
