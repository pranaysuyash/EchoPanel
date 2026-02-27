import Foundation
import MLXLLM
import MLXLMCommon
@preconcurrency import MLX
import os

// MARK: - Analysis Request

public enum AnalysisRequest: Sendable {
    /// Produce a structured summary with action items, decisions, and attendees.
    case summarize(transcript: String)
    /// Extract action items as a flat list.
    case extractActionItems(transcript: String)
    /// Identify decisions made during the meeting.
    case extractDecisions(transcript: String)
    /// Freeform analysis with a custom prompt.
    case custom(systemPrompt: String, userPrompt: String)
}

// MARK: - MLX Analysis Engine

/// Runs local meeting analysis using MLXLLM `ChatSession`.
///
/// Default model: `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (~900 MB).
/// Called only during the `.analysis` phase (enforced by `PhaseScheduler`).
///
/// DEC-030: Analysis must not run while recording — the phase scheduler
/// guarantees this at the application level.
public actor MLXAnalysisEngine {

    // MARK: - Config

    public struct Config: Sendable {
        public var modelId: String
        public var maxTokens: Int
        public var temperature: Float

        public init(
            modelId: String = "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            maxTokens: Int = 1024,
            temperature: Float = 0.2
        ) {
            self.modelId = modelId
            self.maxTokens = maxTokens
            self.temperature = temperature
        }
    }

    // MARK: - State

    public private(set) var isLoaded: Bool = false
    private var container: ModelContainer?
    private let config: Config
    private let logger = Logger(subsystem: "com.echopanel", category: "MLXAnalysisEngine")

    // MARK: - Init

    public init(config: Config = .init()) {
        self.config = config
    }

    // MARK: - Lifecycle

    public func load(progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws {
        logger.info("MLXAnalysisEngine: loading \(self.config.modelId)")
        let mc = try await loadModelContainer(id: config.modelId, progressHandler: progressHandler)
        container = mc
        isLoaded = true
        logger.info("MLXAnalysisEngine: ready")
    }

    public func unload() {
        container = nil
        isLoaded = false
        Memory.clearCache()
        logger.info("MLXAnalysisEngine: unloaded")
    }

    // MARK: - Analysis

    /// Run an analysis request and return the full response as a String.
    public func analyze(_ request: AnalysisRequest) async throws -> String {
        guard let mc = container else {
            throw AnalysisError.notLoaded
        }

        let (system, user) = prompts(for: request)
        let params = GenerateParameters(maxTokens: config.maxTokens, temperature: config.temperature)
        let session = ChatSession(mc, instructions: system, generateParameters: params)
        let result = try await session.respond(to: user)
        logger.info("MLXAnalysisEngine: generated \(result.count) chars")
        return result
    }

    // MARK: - Prompts

    private func prompts(for request: AnalysisRequest) -> (system: String, user: String) {
        switch request {
        case .summarize(let transcript):
            return (
                system: """
                    You are an expert meeting analyst. Produce a concise structured summary with these sections:
                    **Overview**, **Key Decisions**, **Action Items** (as a bullet list), **Attendees Mentioned**.
                    Be factual. Do not invent content not in the transcript.
                    """,
                user: "Transcript:\n\(transcript)"
            )
        case .extractActionItems(let transcript):
            return (
                system: "Extract every action item from the transcript. Format: '- [Owner if mentioned] Task description'.",
                user: "Transcript:\n\(transcript)"
            )
        case .extractDecisions(let transcript):
            return (
                system: "List every decision made in this meeting. One decision per line starting with 'DECISION:'.",
                user: "Transcript:\n\(transcript)"
            )
        case .custom(let sys, let usr):
            return (system: sys, user: usr)
        }
    }
}

// MARK: - Error

public enum AnalysisError: Error, LocalizedError {
    case notLoaded
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded:                    return "MLXAnalysisEngine: model not loaded"
        case .generationFailed(let msg):    return "MLXAnalysisEngine generation failed: \(msg)"
        }
    }
}
