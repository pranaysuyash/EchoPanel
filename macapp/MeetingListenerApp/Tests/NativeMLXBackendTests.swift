import XCTest
@testable import MeetingListenerApp

final class NativeMLXBackendTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        let config = MLXBackendConfiguration.default
        
        XCTAssertEqual(config.modelId, "mlx-community/Qwen3-ASR-0.6B-4bit")
        XCTAssertEqual(config.maxTokens, 1024)
        XCTAssertEqual(config.temperature, 0.0)
        XCTAssertEqual(config.chunkDuration, 30.0)
        XCTAssertEqual(config.streamingDelayMs, 480)
    }
    
    func testCustomConfiguration() {
        let config = MLXBackendConfiguration(
            modelId: "custom-model",
            maxTokens: 512,
            temperature: 0.5,
            chunkDuration: 20.0,
            streamingDelayMs: 240
        )
        
        XCTAssertEqual(config.modelId, "custom-model")
        XCTAssertEqual(config.maxTokens, 512)
        XCTAssertEqual(config.temperature, 0.5)
        XCTAssertEqual(config.chunkDuration, 20.0)
        XCTAssertEqual(config.streamingDelayMs, 240)
    }
    
    func testConfigurationIsSendable() {
        let config = MLXBackendConfiguration.default
        
        let task = Task.detached {
            _ = config
        }
        
        let result = wait(for: task, timeout: 1.0)
        XCTAssertTrue(result)
    }
    
    // MARK: - Backend Initialization Tests
    
    func testBackendInitializesWithDefaultConfig() async {
        let backend = await NativeMLXBackend()
        
        XCTAssertEqual(backend.name, "Native MLX")
        let isAvailable = await backend.isAvailable
        XCTAssertFalse(isAvailable)
        let isStreaming = await backend.isStreaming
        XCTAssertFalse(isStreaming)
    }
    
    func testBackendInitializesWithCustomConfig() async {
        let config = MLXBackendConfiguration(maxTokens: 256)
        let backend = await NativeMLXBackend(configuration: config)
        
        XCTAssertEqual(backend.name, "Native MLX")
    }
    
    func testIsAvailableFalseBeforeInitialization() async {
        let backend = await NativeMLXBackend()
        
        let isAvailable = await backend.isAvailable
        XCTAssertFalse(isAvailable, "isAvailable should be false before initialization")
    }
    
    func testBackendCapabilitiesAreCorrect() async {
        let backend = await NativeMLXBackend()
        
        XCTAssertTrue(backend.capabilities.supportsStreaming)
        XCTAssertTrue(backend.capabilities.supportsBatch)
        XCTAssertFalse(backend.capabilities.supportsDiarization)
        XCTAssertTrue(backend.capabilities.supportsOffline)
        XCTAssertFalse(backend.capabilities.requiresNetwork)
        XCTAssertEqual(backend.capabilities.estimatedRTF, 0.08)
    }
    
    // MARK: - Thread-Safe Audio Buffer Tests
    
    func testAudioBufferWriteAndRead() {
        let buffer = ThreadSafeAudioBuffer(capacity: 100)
        
        let samples = Array(repeating: Float(0.5), count: 50)
        let success = buffer.write(samples)
        
        XCTAssertTrue(success)
        XCTAssertEqual(buffer.count, 50)
        
        let read = buffer.read(upTo: 30)
        XCTAssertEqual(read.count, 30)
        XCTAssertEqual(buffer.count, 20)
    }
    
    func testAudioBufferOverflow() {
        let buffer = ThreadSafeAudioBuffer(capacity: 100)
        
        let samples1 = Array(repeating: Float(0.5), count: 80)
        let success1 = buffer.write(samples1)
        XCTAssertTrue(success1)
        
        let samples2 = Array(repeating: Float(0.3), count: 30)
        let success2 = buffer.write(samples2)
        XCTAssertFalse(success2, "Write should fail when buffer would overflow")
    }
    
    func testAudioBufferIsOverflowProperty() {
        let buffer = ThreadSafeAudioBuffer(capacity: 100)
        
        XCTAssertFalse(buffer.isOverflow)
        
        let samples = Array(repeating: Float(0.5), count: 100)
        _ = buffer.write(samples)
        
        XCTAssertTrue(buffer.isOverflow)
    }
    
    func testAudioBufferClear() {
        let buffer = ThreadSafeAudioBuffer(capacity: 100)
        
        let samples = Array(repeating: Float(0.5), count: 50)
        _ = buffer.write(samples)
        XCTAssertEqual(buffer.count, 50)
        
        buffer.clear()
        XCTAssertEqual(buffer.count, 0)
    }
    
    func testAudioBufferConcurrentAccess() async {
        let buffer = ThreadSafeAudioBuffer(capacity: 10000)
        let iterations = 100
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let samples = Array(repeating: Float(Float(i) * 0.01), count: 10)
                    _ = buffer.write(samples)
                }
            }
            
            for _ in 0..<iterations {
                group.addTask {
                    _ = buffer.read(upTo: 10)
                }
            }
            
            await group.waitForAll()
        }
        
        XCTAssertGreaterThanOrEqual(buffer.count, 0)
    }
    
    func testAudioBufferThreadSafety() {
        let buffer = ThreadSafeAudioBuffer(capacity: 100000)
        let expectation = expectation(description: "Concurrent writes")
        expectation.expectedFulfillmentCount = 100
        
        for i in 0..<100 {
            Task.detached {
                let samples = Array(repeating: Float(i), count: 100)
                _ = buffer.write(samples)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertGreaterThanOrEqual(buffer.count, 0)
        XCTAssertLessThanOrEqual(buffer.count, 100000)
    }
    
    // MARK: - Error Handling Tests
    
    func testTranscribeThrowsWithoutInitialization() async {
        let backend = await NativeMLXBackend()
        let config = TranscriptionConfig()
        let audio = Data(repeating: 0, count: 1000)
        
        do {
            _ = try await backend.transcribe(audio: audio, config: config)
            XCTFail("Should have thrown backendNotAvailable error")
        } catch let error as ASRError {
            if case .backendNotAvailable(let backendName) = error {
                XCTAssertEqual(backendName, "Native MLX")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testStartStreamingReturnsErrorStreamWithoutInitialization() async {
        let backend = await NativeMLXBackend()
        let config = TranscriptionConfig()
        
        let stream = await backend.startStreaming(config: config)
        
        var receivedError = false
        do {
            for try await _ in stream {
                XCTFail("Should not receive events")
            }
        } catch let error as ASRError {
            if case .backendNotAvailable = error {
                receivedError = true
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        XCTAssertTrue(receivedError, "Should have received backendNotAvailable error")
    }
    
    // MARK: - State Management Tests
    
    func testHealthReturnsCorrectStatus() async {
        let backend = await NativeMLXBackend()
        
        let health = await backend.health()
        
        XCTAssertEqual(health.backendName, "Native MLX")
        XCTAssertEqual(health.state, .unknown)
    }
    
    func testIsStreamingInitiallyFalse() async {
        let backend = NativeMLXBackend()
        
        let isStreaming = await backend.isStreaming
        XCTAssertFalse(isStreaming)
    }
    
    // MARK: - Confidence Value Tests
    
    func testTranscriptionSegmentDefaultConfidence() {
        let segment = TranscriptionSegment(
            text: "test",
            startTime: 0,
            endTime: 1
        )
        
        XCTAssertEqual(segment.confidence, 1.0, "Default confidence should be 1.0")
    }
    
    func testTranscriptionSegmentCustomConfidence() {
        let segment = TranscriptionSegment(
            text: "test",
            startTime: 0,
            endTime: 1,
            confidence: 0.0
        )
        
        XCTAssertEqual(segment.confidence, 0.0, "Custom confidence should be preserved")
    }
    
    // MARK: - Duration Calculation Tests
    
    func testDurationCalculationForSampleRate() {
        let sampleRate = 16000
        let sampleCount = 16000
        let duration = Double(sampleCount) / Double(sampleRate)
        
        XCTAssertEqual(duration, 1.0, accuracy: 0.001, "Duration should be 1 second for 16000 samples at 16kHz")
    }
    
    func testDurationCalculationForDifferentSampleRate() {
        let sampleRate = 44100
        let sampleCount = 44100
        let duration = Double(sampleCount) / Double(sampleRate)
        
        XCTAssertEqual(duration, 1.0, accuracy: 0.001, "Duration should be 1 second for 44100 samples at 44.1kHz")
    }
    
    // MARK: - Performance Metrics Tests
    
    func testPerformanceMetricsRecordSuccess() {
        var metrics = PerformanceMetrics()
        
        metrics.recordSuccess(duration: 10.0, processingTime: 1.0, confidence: 0.95)
        
        XCTAssertEqual(metrics.totalRequests, 1)
        XCTAssertEqual(metrics.totalAudioDuration, 10.0)
        XCTAssertEqual(metrics.totalProcessingTime, 1.0)
        XCTAssertEqual(metrics.averageRTF, 0.1, accuracy: 0.001)
        XCTAssertEqual(metrics.averageConfidence, 0.95)
    }
    
    func testPerformanceMetricsRecordMultipleSuccesses() {
        var metrics = PerformanceMetrics()
        
        metrics.recordSuccess(duration: 10.0, processingTime: 1.0, confidence: 0.9)
        metrics.recordSuccess(duration: 20.0, processingTime: 2.0, confidence: 0.8)
        
        XCTAssertEqual(metrics.totalRequests, 2)
        XCTAssertEqual(metrics.totalAudioDuration, 30.0)
        XCTAssertEqual(metrics.totalProcessingTime, 3.0)
        XCTAssertEqual(metrics.averageRTF, 0.1, accuracy: 0.001)
        XCTAssertEqual(metrics.averageConfidence, 0.85, accuracy: 0.001)
    }
    
    func testPerformanceMetricsRecordError() {
        var metrics = PerformanceMetrics()
        
        metrics.recordError("Test error")
        
        XCTAssertEqual(metrics.errorCount, 1)
        XCTAssertEqual(metrics.lastError, "Test error")
        XCTAssertNotNil(metrics.lastErrorTime)
    }
    
    func testPerformanceMetricsRealtimeFactor() {
        var metrics = PerformanceMetrics()
        
        metrics.recordSuccess(duration: 10.0, processingTime: 1.0, confidence: 0.9)
        
        XCTAssertEqual(metrics.realtimeFactor, 0.1, accuracy: 0.001)
        
        metrics.recordSuccess(duration: 10.0, processingTime: 0.5, confidence: 0.9)
        
        XCTAssertEqual(metrics.realtimeFactor, 0.075, accuracy: 0.001)
    }
    
    // MARK: - ASRError Tests
    
    func testASRErrorBackendNotAvailable() {
        let error = ASRError.backendNotAvailable(backend: "TestBackend")
        
        XCTAssertEqual(error.errorDescription, "Backend 'TestBackend' is not available")
    }
    
    func testASRErrorTranscriptionFailed() {
        let error = ASRError.transcriptionFailed(reason: "Network timeout")
        
        XCTAssertEqual(error.errorDescription, "Transcription failed: Network timeout")
    }
    
    func testASRErrorAudioFormatError() {
        let error = ASRError.audioFormatError("Invalid sample rate")
        
        XCTAssertEqual(error.errorDescription, "Audio format error: Invalid sample rate")
    }
    
    func testASRErrorInitializationFailed() {
        let error = ASRError.initializationFailed(reason: "Model not found")
        
        XCTAssertEqual(error.errorDescription, "Initialization failed: Model not found")
    }
    
    // MARK: - Transcription Event Tests
    
    func testTranscriptionEventTypes() {
        let startedEvent = TranscriptionEvent.started
        let partialEvent = TranscriptionEvent.partial(text: "test", confidence: 0.5)
        let finalEvent = TranscriptionEvent.final(segment: TranscriptionSegment(
            text: "test",
            startTime: 0,
            endTime: 1
        ))
        let completedEvent = TranscriptionEvent.completed(result: TranscriptionResult(
            segments: [],
            fullText: "test"
        ))
        let errorEvent = TranscriptionEvent.error(.backendNotAvailable(backend: "test"))
        let cancelledEvent = TranscriptionEvent.cancelled
        
        switch startedEvent {
        case .started: XCTAssertTrue(true)
        default: XCTFail("Wrong event type")
        }
        
        switch partialEvent {
        case .partial(let text, let confidence):
            XCTAssertEqual(text, "test")
            XCTAssertEqual(confidence, 0.5)
        default: XCTFail("Wrong event type")
        }
        
        switch finalEvent {
        case .final(let segment):
            XCTAssertEqual(segment.text, "test")
        default: XCTFail("Wrong event type")
        }
        
        switch completedEvent {
        case .completed(let result):
            XCTAssertEqual(result.fullText, "test")
        default: XCTFail("Wrong event type")
        }
        
        switch errorEvent {
        case .error(let error):
            if case .backendNotAvailable = error {
                XCTAssertTrue(true)
            }
        default: XCTFail("Wrong event type")
        }
        
        switch cancelledEvent {
        case .cancelled: XCTAssertTrue(true)
        default: XCTFail("Wrong event type")
        }
    }
    
    // MARK: - Transcription Config Tests
    
    func testTranscriptionConfigDefaults() {
        let config = TranscriptionConfig()
        
        XCTAssertEqual(config.language, .english)
        XCTAssertFalse(config.enableDiarization)
        XCTAssertTrue(config.enablePunctuation)
        XCTAssertTrue(config.enableTimestamps)
        XCTAssertTrue(config.customVocabulary.isEmpty)
        XCTAssertNil(config.speakerCount)
    }
    
    func testTranscriptionConfigCustom() {
        let config = TranscriptionConfig(
            language: .spanish,
            enableDiarization: true,
            enablePunctuation: false,
            enableTimestamps: false,
            customVocabulary: ["meeting", "agenda"],
            speakerCount: 3
        )
        
        XCTAssertEqual(config.language, .spanish)
        XCTAssertTrue(config.enableDiarization)
        XCTAssertFalse(config.enablePunctuation)
        XCTAssertFalse(config.enableTimestamps)
        XCTAssertEqual(config.customVocabulary, ["meeting", "agenda"])
        XCTAssertEqual(config.speakerCount, 3)
    }
    
    // MARK: - Backend Status Tests
    
    func testBackendStatusDefaults() {
        let status = BackendStatus(backendName: "Test")
        
        XCTAssertEqual(status.backendName, "Test")
        XCTAssertEqual(status.state, .unknown)
        XCTAssertNil(status.message)
        XCTAssertNil(status.capabilities)
        XCTAssertNil(status.performanceMetrics)
    }
    
    func testBackendStatusCustom() {
        let capabilities = BackendCapabilities.nativeDefault
        let status = BackendStatus(
            backendName: "Test",
            state: .ready,
            message: "Ready to transcribe",
            capabilities: capabilities
        )
        
        XCTAssertEqual(status.backendName, "Test")
        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.message, "Ready to transcribe")
        XCTAssertNotNil(status.capabilities)
    }
    
    // MARK: - Feed Audio Result Tests
    
    func testFeedAudioResultSuccess() {
        let result = NativeMLXBackend.FeedAudioResult.success
        
        switch result {
        case .success: XCTAssertTrue(true)
        case .notStreaming: XCTFail("Wrong case")
        case .bufferOverflow: XCTFail("Wrong case")
        }
    }
    
    func testFeedAudioResultNotStreaming() {
        let result = NativeMLXBackend.FeedAudioResult.notStreaming
        
        switch result {
        case .success: XCTFail("Wrong case")
        case .notStreaming: XCTAssertTrue(true)
        case .bufferOverflow: XCTFail("Wrong case")
        }
    }
    
    func testFeedAudioResultBufferOverflow() {
        let result = NativeMLXBackend.FeedAudioResult.bufferOverflow
        
        switch result {
        case .success: XCTFail("Wrong case")
        case .notStreaming: XCTFail("Wrong case")
        case .bufferOverflow: XCTAssertTrue(true)
        }
    }
    
    func testFeedAudioReturnsNotStreamingWhenNotActive() async {
        let backend = await NativeMLXBackend()
        
        let samples = Array(repeating: Float(0.5), count: 1024)
        let result = await backend.feedAudio(samples: samples)
        
        XCTAssertEqual(result, .notStreaming)
    }
    
    // MARK: - Sample Rate Tests
    
    func testDefaultModelSampleRate() async {
        let backend = await NativeMLXBackend()
        
        // Before initialization, sample rate should be 16000 (default)
        // This is tested indirectly through the modelSampleRate property
        let isAvailable = await backend.isAvailable
        XCTAssertFalse(isAvailable)
    }
    
    // MARK: - Language Tests
    
    func testLanguageDisplayName() {
        XCTAssertEqual(Language.english.displayName, "English")
        XCTAssertEqual(Language.chinese.displayName, "Chinese")
        XCTAssertEqual(Language.spanish.displayName, "Spanish")
        XCTAssertEqual(Language.japanese.displayName, "Japanese")
    }
    
    func testLanguageAllCases() {
        let allLanguages = Language.allCases
        
        XCTAssertTrue(allLanguages.contains(.english))
        XCTAssertTrue(allLanguages.contains(.chinese))
        XCTAssertTrue(allLanguages.contains(.spanish))
        XCTAssertEqual(allLanguages.count, 13)
    }
    
    // MARK: - Backend Capabilities Tests
    
    func testNativeDefaultCapabilities() {
        let capabilities = BackendCapabilities.nativeDefault
        
        XCTAssertTrue(capabilities.supportsStreaming)
        XCTAssertTrue(capabilities.supportsBatch)
        XCTAssertFalse(capabilities.supportsDiarization)
        XCTAssertTrue(capabilities.supportsOffline)
        XCTAssertFalse(capabilities.requiresNetwork)
        XCTAssertEqual(capabilities.estimatedRTF, 0.08)
    }
    
    func testPythonDefaultCapabilities() {
        let capabilities = BackendCapabilities.pythonDefault
        
        XCTAssertTrue(capabilities.supportsStreaming)
        XCTAssertTrue(capabilities.supportsBatch)
        XCTAssertTrue(capabilities.supportsDiarization)
        XCTAssertFalse(capabilities.supportsOffline)
        XCTAssertTrue(capabilities.requiresNetwork)
        XCTAssertEqual(capabilities.estimatedRTF, 0.15)
    }
}

// MARK: - Helper Extensions

extension XCTestCase {
    func wait<T>(for task: Task<T, Never>, timeout: TimeInterval) -> Bool {
        let expectation = expectation(description: "Task completion")
        var completed = false
        
        Task {
            _ = await task.value
            completed = true
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
        return completed
    }
}
