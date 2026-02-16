import CryptoKit
import Foundation

enum TranscriptIDs {
    static func normalizeText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Collapse whitespace for determinism across minor formatting differences.
        return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func segmentID(source: String?, t0: TimeInterval, t1: TimeInterval, text: String) -> String {
        let src = (source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "system"
        let normalized = normalizeText(text)
        let content = "\(src)|\(formatSeconds(t0))|\(formatSeconds(t1))|\(normalized)"
        let digest = SHA256.hash(data: Data(content.utf8))

        // Match the server scheme: prefix + first 16 bytes of SHA256.
        return "seg_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func formatSeconds(_ value: TimeInterval) -> String {
        // Fixed precision to avoid small float representation variance.
        String(format: "%.3f", value)
    }
}

