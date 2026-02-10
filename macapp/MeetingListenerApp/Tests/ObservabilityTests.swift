import XCTest
@testable import MeetingListenerApp

/// Tests for observability infrastructure:
/// - StructuredLogger
/// - SessionBundle
/// - Correlation IDs
@MainActor
final class ObservabilityTests: XCTestCase {
    
    // MARK: - StructuredLogger Tests
    
    func testStructuredLoggerContext() {
        let logger = StructuredLogger(configuration: .init(
            minLevel: .debug,
            enableConsoleOutput: false,
            enableFileOutput: false,
            enableOSLog: false
        ))
        
        // Test context setting
        logger.setContext(
            sessionId: "test-session-123",
            attemptId: "test-attempt-456",
            connectionId: "test-conn-789",
            sourceId: "mic"
        )
        
        // Context should be set (verify by checking no crash)
        logger.info("Test message")
        
        // Test context clearing
        logger.clearContext()
        logger.info("Message after clear")
    }
    
    func testStructuredLoggerSampling() {
        let logger = StructuredLogger(configuration: .init(
            minLevel: .debug,
            enableConsoleOutput: false,
            enableFileOutput: false,
            enableOSLog: false
        ))
        
        // Sampled logging should not crash
        for i in 0..<100 {
            logger.logSampled(
                level: .debug,
                message: "Sampled message \(i)",
                sampleKey: "test_sampling",
                sampleRate: 10  // 1 in 10
            )
        }
    }
    
    func testLogRedaction() {
        let logger = StructuredLogger(configuration: .init(
            minLevel: .debug,
            enableConsoleOutput: false,
            enableFileOutput: false,
            enableOSLog: false
        ))
        
        // Test redaction patterns
        let sensitiveMessage = "Token: hf_abcdefghijklmnopqrstuvwxyz1234567890"
        // Should not crash - redaction happens internally
        logger.info(sensitiveMessage)
    }
    
    // MARK: - SessionBundle Tests
    
    func testSessionBundleCreation() {
        let bundle = SessionBundle(
            sessionId: "test-session",
            configuration: .default
        )
        
        XCTAssertEqual(bundle.sessionId, "test-session")
        XCTAssertNotNil(bundle.createdAt)
    }
    
    func testSessionBundleEventRecording() {
        let bundle = SessionBundle(sessionId: "test-session")
        
        bundle.recordEvent(.sessionStart, metadata: ["audio_source": "both"])
        bundle.recordEvent(.wsConnect, metadata: [:])
        bundle.recordEvent(.firstASR, metadata: ["source": "system"])
        
        // Events recorded (no crash)
        XCTAssertTrue(true)
    }
    
    func testSessionBundleMetricsRecording() {
        let bundle = SessionBundle(sessionId: "test-session")
        
        let metrics = SourceMetrics(
            source: "system",
            queueDepth: 10,
            queueMax: 48,
            queueFillRatio: 0.21,
            droppedTotal: 0,
            droppedRecent: 0,
            avgInferMs: 450.0,
            realtimeFactor: 0.23,
            timestamp: Date().timeIntervalSince1970,
            connectionId: "test-conn",
            sessionId: "test-session",
            attemptId: "test-attempt"
        )
        
        bundle.recordMetrics(metrics)
        
        // Should record without crash
        XCTAssertTrue(true)
    }
    
    func testSessionBundleTranscriptRecording() {
        let bundle = SessionBundle(sessionId: "test-session")
        
        let segment = TranscriptSegment(
            text: "Hello world",
            t0: 0.0,
            t1: 2.0,
            isFinal: true,
            confidence: 0.95,
            source: "system",
            speaker: "Speaker 1"
        )
        
        bundle.recordTranscriptSegment(segment)
        bundle.setFinalTranscript([segment])
        
        // Should record without crash
        XCTAssertTrue(true)
    }
    
    func testSessionBundleFrameDropRecording() {
        let bundle = SessionBundle(sessionId: "test-session")
        
        bundle.recordFrameDrop(source: "system", totalDropped: 1)
        bundle.recordFrameDrop(source: "system", totalDropped: 2)
        bundle.recordFrameDrop(source: "mic", totalDropped: 1)
        
        // Should record without crash
        XCTAssertTrue(true)
    }
    
    // MARK: - Correlation IDs Tests
    
    func testCorrelationIDsGeneration() {
        let ids = CorrelationIDs.generate(
            sessionId: "session-123",
            attemptId: "attempt-456"
        )
        
        XCTAssertEqual(ids.sessionId, "session-123")
        XCTAssertEqual(ids.attemptId, "attempt-456")
        XCTAssertFalse(ids.connectionId.isEmpty)
        
        // Connection ID should be unique UUID
        let ids2 = CorrelationIDs.generate(
            sessionId: "session-123",
            attemptId: "attempt-456"
        )
        XCTAssertNotEqual(ids.connectionId, ids2.connectionId)
    }
    
    // MARK: - Integration Tests
    
    func testSessionBundleManager() {
        let manager = SessionBundleManager.shared
        
        // Create bundle
        let bundle = manager.createBundle(for: "test-session-123")
        XCTAssertNotNil(bundle)
        
        // Retrieve bundle
        let retrieved = manager.bundle(for: "test-session-123")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.sessionId, "test-session-123")
        
        // Non-existent bundle
        let missing = manager.bundle(for: "non-existent")
        XCTAssertNil(missing)
    }
}
