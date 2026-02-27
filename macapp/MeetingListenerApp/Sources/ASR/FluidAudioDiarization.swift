import Foundation
import FluidAudio
import os

// MARK: - Speaker Segment

/// Speaker-labelled time segment (RTTM-compatible).
public struct SpeakerSegment: Sendable {
    public let speakerId: String
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public var durationSeconds: Double { endTimeSeconds - startTimeSeconds }

    /// RTTM line format: `SPEAKER session 1 <start> <dur> <NA> <NA> <speaker> <NA> <NA>`
    public func rttmLine(sessionId: String = "session") -> String {
        String(format: "SPEAKER %@ 1 %.3f %.3f <NA> <NA> %@ <NA> <NA>",
               sessionId, startTimeSeconds, durationSeconds, speakerId)
    }
}

// MARK: - FluidAudio Diarization

/// Post-recording batch diarization using `OfflineDiarizerManager` (VBx clustering).
///
/// Designed for the session-close flow: after ASR finishes, run diarization over
/// the full recording to produce speaker-labelled RTTM segments.
///
/// DEC-036: `OfflineDiarizerManager` is primary diarization path (better DER than online).
/// macOS 14+ required (`@available` gate enforced at call sites).
@available(macOS 14.0, *)
public final class FluidAudioDiarization: @unchecked Sendable {

    // MARK: - State

    private let diarizer: OfflineDiarizerManager
    public private(set) var isReady: Bool = false

    private let logger = Logger(subsystem: "com.echopanel", category: "FluidAudioDiarization")

    // MARK: - Init

    public init(config: OfflineDiarizerConfig = .default) {
        self.diarizer = OfflineDiarizerManager(config: config)
    }

    // MARK: - Lifecycle

    /// Download and compile CoreML models (cached after first use in ~/Library/Application Support/FluidAudio/Models/).
    public func prepareModels(forceRedownload: Bool = false) async throws {
        logger.info("FluidAudioDiarization: preparing models (forceRedownload=\(forceRedownload))")
        try await diarizer.prepareModels(forceRedownload: forceRedownload)
        isReady = true
        logger.info("FluidAudioDiarization: models ready")
    }

    // MARK: - Diarization

    /// Run batch diarization over a 16kHz Float32 audio buffer.
    /// - Parameter audio: PCM Float32 samples at 16kHz.
    /// - Returns: Array of speaker segments in chronological order.
    public func diarize(audio: [Float]) async throws -> [SpeakerSegment] {
        guard isReady else {
            throw DiarizationError.notReady("Call prepareModels() before diarizing")
        }

        logger.info("FluidAudioDiarization: diarizing \(audio.count) samples (\(String(format: "%.1f", Double(audio.count) / 16000.0))s)")
        let result = try await diarizer.process(audio: audio)
        let segments = result.segments.map { seg in
            SpeakerSegment(
                speakerId: seg.speakerId,
                startTimeSeconds: Double(seg.startTimeSeconds),
                endTimeSeconds: Double(seg.endTimeSeconds)
            )
        }
        logger.info("FluidAudioDiarization: found \(segments.count) segments, \(Set(segments.map(\.speakerId)).count) speaker(s)")
        return segments
    }

    /// Run batch diarization from an audio file URL.
    public func diarize(url: URL) async throws -> [SpeakerSegment] {
        guard isReady else {
            throw DiarizationError.notReady("Call prepareModels() before diarizing")
        }

        let result = try await diarizer.process(url)
        return result.segments.map { seg in
            SpeakerSegment(
                speakerId: seg.speakerId,
                startTimeSeconds: Double(seg.startTimeSeconds),
                endTimeSeconds: Double(seg.endTimeSeconds)
            )
        }
    }

    // MARK: - RTTM Export

    /// Export segments as RTTM-format string.
    public func exportRTTM(segments: [SpeakerSegment], sessionId: String = "session") -> String {
        segments.map { $0.rttmLine(sessionId: sessionId) }.joined(separator: "\n")
    }
}

// MARK: - Error

public enum DiarizationError: Error, LocalizedError {
    case notReady(String)
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let msg):            return "Diarization not ready: \(msg)"
        case .processingFailed(let msg):    return "Diarization failed: \(msg)"
        }
    }
}
