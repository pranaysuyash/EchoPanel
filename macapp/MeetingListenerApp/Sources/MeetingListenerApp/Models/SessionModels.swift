import Foundation

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let t0: TimeInterval
    let t1: TimeInterval
    let isFinal: Bool
    let confidence: Double
}

struct ActionItem: Identifiable {
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

enum SessionState: String {
    case idle
    case listening
    case error
}

enum AudioQuality: String {
    case good = "Good"
    case ok = "OK"
    case poor = "Poor"
    case unknown = "Unknown"
}

enum StreamStatus: String {
    case streaming = "Streaming"
    case reconnecting = "Reconnecting"
    case error = "Backend unavailable"
}
