import Foundation

enum SessionState: String {
    case idle
    case starting
    case listening
    case finalizing
    case error
}

enum StreamStatus {
    case streaming
    case reconnecting
    case error
}

enum AudioQuality: String {
    case good = "Good"
    case ok = "OK"
    case poor = "Poor"
    case unknown = "Unknown"
}

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let t0: TimeInterval
    let t1: TimeInterval
    let isFinal: Bool
    let confidence: Double
    var source: String? = nil // "microphone" or "system"
    var speaker: String? = nil // "Speaker 1"
}

struct ActionItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let owner: String?
    let due: String?
    let confidence: Double
}

struct DecisionItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Double
}

struct RiskItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Double
}

struct EntityItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: String
    let count: Int
    let lastSeen: TimeInterval
    let confidence: Double
}
