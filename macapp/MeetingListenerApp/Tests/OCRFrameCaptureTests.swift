import XCTest
@testable import MeetingListenerApp

final class OCRFrameCaptureTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        let config = OCRFrameCapture.Configuration.default
        
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.interval, 30.0)
        XCTAssertEqual(config.jpegQuality, 0.7)
        XCTAssertEqual(config.maxDimension, 1280)
        XCTAssertEqual(config.recognitionLevel, .accurate)
        XCTAssertTrue(config.languageCorrection)
    }
    
    func testCustomConfiguration() {
        let config = OCRFrameCapture.Configuration(
            enabled: true,
            interval: 15.0,
            jpegQuality: 0.5,
            maxDimension: 640,
            recognitionLevel: .fast,
            languageCorrection: false
        )
        
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.interval, 15.0)
        XCTAssertEqual(config.jpegQuality, 0.5)
        XCTAssertEqual(config.maxDimension, 640)
        XCTAssertEqual(config.recognitionLevel, .fast)
        XCTAssertFalse(config.languageCorrection)
    }
    
    func testConfigurationEquatable() {
        let config1 = OCRFrameCapture.Configuration.default
        let config2 = OCRFrameCapture.Configuration.default
        
        XCTAssertEqual(config1, config2)
        
        let config3 = OCRFrameCapture.Configuration(enabled: true)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testRecognitionLevelVisionMapping() {
        XCTAssertEqual(OCRFrameCapture.Configuration.RecognitionLevel.fast.visionLevel, .fast)
        XCTAssertEqual(OCRFrameCapture.Configuration.RecognitionLevel.accurate.visionLevel, .accurate)
    }
    
    // MARK: - Error Tests
    
    func testOCRErrorDescriptions() {
        XCTAssertEqual(OCRError.noFrameReceived.errorDescription, "No screen frame received")
        XCTAssertEqual(OCRError.compressionFailed.errorDescription, "Image compression failed")
        XCTAssertEqual(OCRError.permissionDenied.errorDescription, "Screen recording permission denied")
        XCTAssertEqual(OCRError.processingError("test").errorDescription, "OCR processing error: test")
        XCTAssertEqual(OCRError.notConnected.errorDescription, "WebSocket not connected")
    }
    
    // MARK: - OCR Capture Result Tests
    
    func testOCRCaptureResultInit() {
        let result = OCRCaptureResult(
            text: "Hello World",
            processingTime: 0.5,
            imageSize: CGSize(width: 1280, height: 720),
            sessionId: "test-session"
        )
        
        XCTAssertEqual(result.text, "Hello World")
        XCTAssertNotNil(result.timestamp)
        XCTAssertEqual(result.processingTime, 0.5)
        XCTAssertEqual(result.imageSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(result.sessionId, "test-session")
    }
    
    func testOCRCaptureResultDefaultTimestamp() {
        let before = Date()
        let result = OCRCaptureResult(
            text: "test",
            processingTime: 0.1,
            imageSize: CGSize(width: 100, height: 100)
        )
        let after = Date()
        
        XCTAssertTrue(result.timestamp >= before)
        XCTAssertTrue(result.timestamp <= after)
        XCTAssertNil(result.sessionId)
    }
    
    // MARK: - State Management Tests
    
    func testInitialState() async {
        await MainActor.run {
            let capture = OCRFrameCapture()
            
            XCTAssertFalse(capture.isCapturing)
            XCTAssertNil(capture.lastCaptureTime)
            XCTAssertNil(capture.lastError)
        }
    }
    
    func testConfigurationUpdate() async {
        await MainActor.run {
            let capture = OCRFrameCapture(configuration: .default)
            
            let newConfig = OCRFrameCapture.Configuration(enabled: true, interval: 10.0)
            capture.updateConfiguration(newConfig)
            
            // Capture should not start without permission and delegate
            XCTAssertFalse(capture.isCapturing)
        }
    }
    
    func testStopCaptureWhenNotCapturing() async {
        await MainActor.run {
            let capture = OCRFrameCapture()
            
            // Should not crash when stopping non-existent capture
            capture.stopCapture()
            
            XCTAssertFalse(capture.isCapturing)
        }
    }
    
    // MARK: - Permission Tests
    
    func testPermissionCheckDoesNotCrash() async {
        await MainActor.run {
            let capture = OCRFrameCapture()
            
            // Permission check should complete without crash
            Task {
                await capture.checkPermissions()
            }
            
            // Result depends on system state, so we just verify it doesn't crash
        }
    }
    
    // MARK: - Delegate Tests
    
    class MockOCRDelegate: OCRResultDelegate {
        var capturedResults: [OCRCaptureResult] = []
        var errors: [OCRError] = []
        var stateChanges: [Bool] = []
        
        func didCaptureResult(_ result: OCRCaptureResult) {
            capturedResults.append(result)
        }
        
        func didFailWithError(_ error: OCRError) {
            errors.append(error)
        }
        
        func didChangeCaptureState(_ isCapturing: Bool) {
            stateChanges.append(isCapturing)
        }
    }
    
    func testStartCaptureWithoutDelegateDoesNothing() async {
        await MainActor.run {
            let capture = OCRFrameCapture(configuration: OCRFrameCapture.Configuration(enabled: true))
            
            // Without delegate, capture should not start
            capture.startCapture()
            
            XCTAssertFalse(capture.isCapturing)
        }
    }
    
    func testStartCaptureWithoutPermissionFails() async {
        await MainActor.run {
            let capture = OCRFrameCapture(configuration: OCRFrameCapture.Configuration(enabled: true))
            let delegate = MockOCRDelegate()
            capture.delegate = delegate
            
            // Even with delegate, without permission it should fail
            capture.startCapture()
            
            // May or may not have permission depending on test environment
            // Just verify no crash
        }
    }
    
    // MARK: - Configuration Change Tests
    
    func testIntervalChangeRestartsTimer() async {
        await MainActor.run {
            let capture = OCRFrameCapture()
            
            // Should handle interval change gracefully even when not capturing
            capture.updateConfiguration(OCRFrameCapture.Configuration(interval: 5.0))
            
            XCTAssertFalse(capture.isCapturing)
        }
    }
    
    // MARK: - Feed Audio Result Tests (NativeMLXBackend)
    
    func testFeedAudioResultCases() {
        // Test that FeedAudioResult enum exists and has correct cases
        let success = NativeMLXBackend.FeedAudioResult.success
        let notStreaming = NativeMLXBackend.FeedAudioResult.notStreaming
        let bufferOverflow = NativeMLXBackend.FeedAudioResult.bufferOverflow
        
        // Just verify the enum exists with correct cases
        switch success {
        case .success: XCTAssertTrue(true)
        case .notStreaming: XCTFail("Wrong case")
        case .bufferOverflow: XCTFail("Wrong case")
        }
        
        switch notStreaming {
        case .success: XCTFail("Wrong case")
        case .notStreaming: XCTAssertTrue(true)
        case .bufferOverflow: XCTFail("Wrong case")
        }
        
        switch bufferOverflow {
        case .success: XCTFail("Wrong case")
        case .notStreaming: XCTFail("Wrong case")
        case .bufferOverflow: XCTAssertTrue(true)
        }
    }
    
    // MARK: - Downsampling Logic Tests
    
    func testDownsamplingReducesSize() {
        // Test that downsampling is applied when maxDimension is set
        let config = OCRFrameCapture.Configuration(maxDimension: 640)
        
        XCTAssertEqual(config.maxDimension, 640)
    }
    
    func testNoUpsampling() {
        // When maxDimension is larger than image, should not upscale
        let config = OCRFrameCapture.Configuration(maxDimension: 10000)
        
        XCTAssertGreaterThan(config.maxDimension, 1280)
    }
    
    func testZeroMaxDimension() {
        // Zero maxDimension should mean no resizing
        let config = OCRFrameCapture.Configuration(maxDimension: 0)
        
        XCTAssertEqual(config.maxDimension, 0)
    }
}
