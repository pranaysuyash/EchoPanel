import Foundation
import GRDB
import Accelerate
import os

// MARK: - Embedding Record

/// One stored embedding row: session transcript chunk + float vector.
struct EmbeddingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embeddings"

    var id: Int64?
    let sessionId: String
    let chunkIndex: Int
    let text: String
    let embeddingBlob: Data  // Float32 LE, length = dimension * 4 bytes
    let createdAt: Date
}

// MARK: - Search Result

public struct RAGSearchResult: Sendable {
    public let sessionId: String
    public let chunkIndex: Int
    public let text: String
    public let score: Float  // cosine similarity 0..1
}

// MARK: - Session RAG Store

/// SQLite-backed semantic search store for meeting transcript chunks.
///
/// Embeddings are produced by `MLXEmbeddingsEngine` (NomicBert 768-dim).
/// Cosine similarity search uses vDSP for CPU-efficient dot products.
///
/// Schema: one `embeddings` table with id, sessionId, chunkIndex, text, embeddingBlob, createdAt.
/// DB location: `~/Library/Application Support/com.echopanel/rag.sqlite`
public actor SessionRAGStore {

    // MARK: - Constants

    public static let embeddingDimension: Int = 768
    private static let dbDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("com.echopanel", isDirectory: true)
    }()
    private static let dbURL: URL = dbDirectory.appendingPathComponent("rag.sqlite")

    // MARK: - State

    private var dbPool: DatabasePool?
    public private(set) var isReady: Bool = false
    private let logger = Logger(subsystem: "com.echopanel", category: "SessionRAGStore")

    // MARK: - Init / Setup

    public init() {}

    public func setup() async throws {
        try FileManager.default.createDirectory(at: Self.dbDirectory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: Self.dbURL.path)
        try await pool.write { db in
            try db.create(table: EmbeddingRecord.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .text).notNull().indexed()
                t.column("chunkIndex", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("embeddingBlob", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
        dbPool = pool
        isReady = true
        logger.info("SessionRAGStore: ready at \(Self.dbURL.path)")
    }

    // MARK: - Insert

    /// Store a chunk embedding for a session.
    public func insert(sessionId: String, chunkIndex: Int, text: String, embedding: [Float]) async throws {
        guard let pool = dbPool else { throw RAGStoreError.notReady }
        let blob = floatArrayToData(embedding)
        let record = EmbeddingRecord(
            id: nil,
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            text: text,
            embeddingBlob: blob,
            createdAt: Date()
        )
        try await pool.write { db in
            try record.insert(db)
        }    }

    /// Chunk a transcript and insert all embeddings.
    /// - Parameters:
    ///   - transcript: Full session transcript text.
    ///   - engine: Loaded `MLXEmbeddingsEngine` to produce vectors.
    ///   - chunkSize: Approximate word count per chunk (default 80).
    public func indexTranscript(
        sessionId: String,
        transcript: String,
        engine: MLXEmbeddingsEngine,
        chunkSize: Int = 80
    ) async throws {
        let chunks = chunkText(transcript, wordsPerChunk: chunkSize)
        for (idx, chunk) in chunks.enumerated() {
            let embedding = try await engine.embed("search_document: \(chunk)")
            try await insert(sessionId: sessionId, chunkIndex: idx, text: chunk, embedding: embedding)
        }
        logger.info("SessionRAGStore: indexed \(chunks.count) chunks for session \(sessionId)")
    }

    // MARK: - Search

    /// Find the top-k most semantically similar chunks to `query`.
    public func search(query: String, engine: MLXEmbeddingsEngine, topK: Int = 5) async throws -> [RAGSearchResult] {
        guard let pool = dbPool else { throw RAGStoreError.notReady }
        let queryVec = try await engine.embed("search_query: \(query)")
        let records = try await pool.read { db in
            try EmbeddingRecord.fetchAll(db)
        }
        let scored: [(EmbeddingRecord, Float)] = records.map { record in
            let stored = dataToFloatArray(record.embeddingBlob)
            let score = vDSPCosineSimilarity(queryVec, stored)
            return (record, score)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { RAGSearchResult(sessionId: $0.0.sessionId, chunkIndex: $0.0.chunkIndex, text: $0.0.text, score: $0.1) }
    }

    // MARK: - Delete

    /// Remove all embeddings for a session (e.g., on data retention policy).
    public func deleteSession(_ sessionId: String) async throws {
        guard let pool = dbPool else { throw RAGStoreError.notReady }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM embeddings WHERE sessionId = ?", arguments: [sessionId])
        }
        logger.info("SessionRAGStore: deleted embeddings for session \(sessionId)")
    }

    // MARK: - Helpers

    private func floatArrayToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBytes { Data($0) }
    }

    private func dataToFloatArray(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self).prefix(count))
        }
    }

    /// vDSP dot-product cosine similarity (both vectors assumed L2-normalised by MLXEmbeddingsEngine).
    private func vDSPCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    private func chunkText(_ text: String, wordsPerChunk: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        var chunks: [String] = []
        var idx = 0
        while idx < words.count {
            let slice = words[idx..<min(idx + wordsPerChunk, words.count)]
            chunks.append(slice.joined(separator: " "))
            idx += wordsPerChunk
        }
        return chunks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Error

public enum RAGStoreError: Error, LocalizedError {
    case notReady

    public var errorDescription: String? { "SessionRAGStore: not set up yet — call setup() first" }
}
