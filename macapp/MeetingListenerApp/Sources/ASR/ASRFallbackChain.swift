import Foundation
import MLXAudioSTT
@preconcurrency import MLX
import os

// MARK: - ASR Tier

/// Priority-ordered ASR model tiers. Lower raw value = higher priority.
public enum ASRTier: Int, Sendable, CaseIterable {
    case qwen3_0_6B = 1   // ~720 MB  — default for all Mac tiers
    case qwen3_1_7B = 2   // ~1.6 GB  — opt-in when ≥16 GB RAM
    case parakeet   = 4   // ~1.2 GB  — fallback P4 (CTC/TDT, NVIDIA-trained)
    case python     = 5   // FastAPI  — ultimate fallback

    public var modelId: String? {
        switch self {
        case .qwen3_0_6B: return "mlx-community/Qwen3-ASR-0.6B-4bit"
        case .qwen3_1_7B: return "mlx-community/Qwen3-ASR-1.7B-4bit"
        case .parakeet:   return "mlx-community/parakeet-tdt-0.6b-v2"
        case .python:     return nil
        }
    }

    public var displayName: String {
        switch self {
        case .qwen3_0_6B: return "Qwen3-ASR 0.6B"
        case .qwen3_1_7B: return "Qwen3-ASR 1.7B"
        case .parakeet:   return "Parakeet TDT 0.6B"
        case .python:     return "Python FastAPI"
        }
    }

    /// Approximate peak RAM in MB.
    public var approximateRAMMB: Int {
        switch self {
        case .qwen3_0_6B: return 720
        case .qwen3_1_7B: return 1600
        case .parakeet:   return 1200
        case .python:     return 0
        }
    }
}

// MARK: - Loaded Model Union

private enum LoadedASRModel: @unchecked Sendable {
    case qwen3(Qwen3ASRModel)
    case parakeet(ParakeetModel)
}

// MARK: - ASR Fallback Chain

/// Manages a priority-ordered chain of ASR models.
///
/// On `initialize()`, tries tiers in priority order and loads the first that succeeds.
/// Falls back automatically if model download or load fails.
///
/// DEC-031: Never run ASR + LLM simultaneously — the caller must enforce this.
public actor ASRFallbackChain {

    // MARK: - State

    public private(set) var activeTier: ASRTier?
    public private(set) var isLoaded: Bool = false

    private var loadedModel: LoadedASRModel?
    private let allowedTiers: [ASRTier]
    private let logger = Logger(subsystem: "com.echopanel", category: "ASRFallbackChain")

    // MARK: - Init

    /// - Parameter tiers: Ordered list of tiers to try. Defaults to all MLX tiers
    ///   (Python tier is excluded and handled by `HybridASRManager`).
    public init(tiers: [ASRTier] = [.qwen3_0_6B, .qwen3_1_7B, .parakeet]) {
        self.allowedTiers = tiers
    }

    // MARK: - Lifecycle

    /// Try each tier in priority order; stop at first successful load.
    public func initialize() async throws {
        for tier in allowedTiers {
            guard let modelId = tier.modelId else { continue }
            do {
                logger.info("ASRFallbackChain: trying \(tier.displayName) [\(modelId)]")
                switch tier {
                case .qwen3_0_6B, .qwen3_1_7B:
                    let model = try await Qwen3ASRModel.fromPretrained(modelId)
                    loadedModel = .qwen3(model)
                case .parakeet:
                    let model = try await ParakeetModel.fromPretrained(modelId)
                    loadedModel = .parakeet(model)
                case .python:
                    break
                }
                activeTier = tier
                isLoaded = true
                logger.info("ASRFallbackChain: loaded \(tier.displayName)")
                return
            } catch {
                logger.warning("ASRFallbackChain: \(tier.displayName) failed — \(error.localizedDescription)")
                Memory.clearCache()
            }
        }
        throw ASRError.initializationFailed(reason: "All ASR tiers exhausted")
    }

    public func unload() async {
        loadedModel = nil
        activeTier = nil
        isLoaded = false
        Memory.clearCache()
        logger.info("ASRFallbackChain: unloaded")
    }

    // MARK: - Transcription

    /// Transcribe a pre-loaded `MLXArray` (already at model sample rate).
    public func transcribe(
        audio: MLXArray,
        language: String = "en",
        maxTokens: Int = 1024,
        temperature: Float = 0.0,
        chunkDuration: Float = 30.0
    ) async throws -> String {
        guard let model = loadedModel else {
            throw ASRError.backendNotAvailable(backend: "ASRFallbackChain")
        }

        var fullText = ""

        switch model {
        case .qwen3(let m):
            for try await event in m.generateStream(
                audio: audio,
                maxTokens: maxTokens,
                temperature: temperature,
                language: language,
                chunkDuration: chunkDuration
            ) {
                if case .token(let t) = event { fullText += t }
            }

        case .parakeet(let m):
            let params = STTGenerateParameters(
                maxTokens: maxTokens,
                language: language,
                chunkDuration: chunkDuration
            )
            for try await event in m.generateStream(audio: audio, generationParameters: params) {
                if case .token(let t) = event { fullText += t }
            }
        }

        return fullText
    }

    // MARK: - Sample Rate

    public var modelSampleRate: Int {
        guard let model = loadedModel else { return 16000 }
        switch model {
        case .qwen3(let m):  return m.sampleRate
        case .parakeet:      return 16000
        }
    }
}
