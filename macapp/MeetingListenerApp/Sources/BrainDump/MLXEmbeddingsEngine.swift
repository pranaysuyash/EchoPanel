import Foundation
import MLXEmbedders
import MLXLMCommon
@preconcurrency import MLX
import MLXNN
import Tokenizers
import os

// MARK: - MLX Embeddings Engine

/// Computes local dense embeddings using MLXEmbedders.
///
/// Default model: `mlx-community/nomic-embed-text-v1.5` (NomicBert, 768-dim).
/// Used in the `.brainDump` phase for semantic search and clustering of meeting notes.
///
/// DEC-030: Brain dump runs only after analysis is complete. PhaseScheduler enforces this.
public actor MLXEmbeddingsEngine {

    // MARK: - Config

    public struct Config: Sendable {
        public var modelId: String
        public var dimension: Int
        public var normalize: Bool

        public init(
            modelId: String = "mlx-community/nomic-embed-text-v1.5",
            dimension: Int = 768,
            normalize: Bool = true
        ) {
            self.modelId = modelId
            self.dimension = dimension
            self.normalize = normalize
        }
    }

    // MARK: - State

    public private(set) var isLoaded: Bool = false
    private var embedContainer: MLXEmbedders.ModelContainer?
    private let config: Config
    private let logger = Logger(subsystem: "com.echopanel", category: "MLXEmbeddingsEngine")

    // MARK: - Init

    public init(config: Config = .init()) {
        self.config = config
    }

    // MARK: - Lifecycle

    public func load(
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws {
        logger.info("MLXEmbeddingsEngine: loading \(self.config.modelId)")
        let modelConfig = ModelConfiguration(id: config.modelId)
        let mc = try await MLXEmbedders.loadModelContainer(
            configuration: modelConfig,
            progressHandler: progressHandler
        )
        embedContainer = mc
        isLoaded = true
        logger.info("MLXEmbeddingsEngine: ready (dim=\(self.config.dimension))")
    }

    public func unload() {
        embedContainer = nil
        isLoaded = false
        Memory.clearCache()
        logger.info("MLXEmbeddingsEngine: unloaded")
    }

    // MARK: - Embedding

    /// Compute a normalized embedding vector for a single text string.
    /// - Returns: `[Float]` of length `config.dimension`.
    public func embed(_ text: String) async throws -> [Float] {
        guard let mc = embedContainer else {
            throw EmbeddingError.notLoaded
        }

        let doNormalize = config.normalize
        return try await mc.perform { (model: EmbeddingModel, tokenizer: Tokenizer, pooler: Pooling) -> [Float] in
            let encoded = tokenizer.encode(text: text, addSpecialTokens: true)
            let inputIds = MLXArray(encoded.map { Int32($0) })[.newAxis]
            let attentionMask = MLXArray.ones([1, encoded.count], dtype: .int32)
            let tokenTypes = MLXArray.zeros(like: inputIds)
            let output = model(inputIds, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: attentionMask)
            let pooled = pooler(output, mask: attentionMask, normalize: doNormalize, applyLayerNorm: true)
            pooled.eval()
            return pooled[0].asArray(Float.self)
        }
    }

    /// Batch-embed multiple texts (sequentially; MLX is single-threaded on GPU).
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }

    /// Cosine similarity between two vectors (0–1).
    public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}

// MARK: - Error

public enum EmbeddingError: Error, LocalizedError {
    case notLoaded
    case shapeMismatch

    public var errorDescription: String? {
        switch self {
        case .notLoaded:       return "MLXEmbeddingsEngine: model not loaded"
        case .shapeMismatch:   return "MLXEmbeddingsEngine: embedding shape mismatch"
        }
    }
}
