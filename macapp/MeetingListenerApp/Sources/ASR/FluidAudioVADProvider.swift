import Foundation
import FluidAudio
import os

// MARK: - VAD Event

public enum VADEvent: Sendable {
    case speechStart(timeSeconds: Double)
    case speechEnd(timeSeconds: Double)
    case probability(Float)
}

// MARK: - FluidAudio VAD Provider

/// Wraps FluidAudio's `VadManager` actor to provide Silero VAD for the streaming pipeline.
///
/// Usage:
/// ```swift
/// let vad = try await FluidAudioVADProvider()
/// var streamState = await vad.makeStreamState()
/// let result = try await vad.processChunk(samples, state: &streamState)
/// ```
///
/// `VadManager` is an actor — all methods are async/await.
/// Chunk size must be 4096 samples (256ms at 16kHz) for streaming mode.
public actor FluidAudioVADProvider {

    // MARK: - Constants

    /// Required chunk size for streaming VAD (256ms at 16kHz).
    public static let chunkSize: Int = VadManager.chunkSize   // 4096
    public static let sampleRate: Int = VadManager.sampleRate // 16000

    // MARK: - State

    private let vad: VadManager
    public private(set) var isAvailable: Bool = false

    private let logger = Logger(subsystem: "com.echopanel", category: "FluidAudioVAD")

    // MARK: - Init

    /// Load Silero VAD model (auto-downloads from HuggingFace on first use).
    public init(config: VadConfig = .default) async throws {
        self.vad = try await VadManager(config: config)
        self.isAvailable = true
        Logger(subsystem: "com.echopanel", category: "FluidAudioVAD")
            .info("FluidAudioVADProvider: Silero VAD loaded")
    }

    // MARK: - Streaming API

    /// Create a fresh stream state for a new recording session.
    public func makeStreamState() async -> VadStreamState {
        await vad.makeStreamState()
    }

    /// Process one 4096-sample chunk (256ms). Returns updated state + optional speech event.
    /// - Parameters:
    ///   - samples: PCM Float32 at 16kHz. Must be exactly `chunkSize` samples.
    ///   - state: Mutable stream state; pass the same instance across successive calls.
    /// - Returns: `VadStreamResult` with `event` (`.speechStart`/`.speechEnd`) if a transition occurred.
    public func processChunk(
        _ samples: [Float],
        state: VadStreamState,
        config: VadSegmentationConfig = .default
    ) async throws -> VadStreamResult {
        try await vad.processStreamingChunk(
            samples,
            state: state,
            config: config,
            returnSeconds: true,
            timeResolution: 1
        )
    }

    // MARK: - Batch API

    /// Run VAD over a full audio buffer (non-streaming, for post-processing).
    public func processBuffer(_ samples: [Float]) async throws -> [VadResult] {
        try await vad.process(samples)
    }

    /// Segment speech regions from a buffer; returns array of speech-only sample arrays.
    public func segmentSpeech(_ samples: [Float], config: VadSegmentationConfig = .default) async throws -> [[Float]] {
        try await vad.segmentSpeechAudio(samples, config: config)
    }
}
