import Foundation

enum ListenerState: String {
    case idle
    case listening
    case error
    case unsupported
}

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let t0: TimeInterval
    let t1: TimeInterval
    let text: String
    let isPartial: Bool
}

struct CardItem: Identifiable {
    let id = UUID()
    let text: String
    let owner: String?
    let due: String?
    let confidence: Double
}

struct DecisionItem: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Double
}

struct RiskItem: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Double
}

struct EntityItem: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let lastSeen: TimeInterval
    let confidence: Double
}
