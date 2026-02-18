import Foundation
import ScreenCaptureKit
import AppKit
import Vision
import OSLog

/// Errors that can occur during OCR capture
public enum OCRError: Error, LocalizedError {
    case noFrameReceived
    case compressionFailed
    case permissionDenied
    case processingError(String)
    case notConnected
    
    public var errorDescription: String? {
        switch self {
        case .noFrameReceived:
            return "No screen frame received"
        case .compressionFailed:
            return "Image compression failed"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .processingError(let details):
            return "OCR processing error: \(details)"
        case .notConnected:
            return "WebSocket not connected"
        }
    }
}

/// Result of an OCR capture operation
public struct OCRCaptureResult {
    public let text: String
    public let timestamp: Date
    public let processingTime: TimeInterval
    public let imageSize: CGSize
    public let sessionId: String?
    
    public init(text: String, timestamp: Date = Date(), processingTime: TimeInterval, imageSize: CGSize, sessionId: String? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.processingTime = processingTime
        self.imageSize = imageSize
        self.sessionId = sessionId
    }
}

/// Protocol for OCR result handling
public protocol OCRResultDelegate: AnyObject {
    func didCaptureResult(_ result: OCRCaptureResult)
    func didFailWithError(_ error: OCRError)
    func didChangeCaptureState(_ isCapturing: Bool)
}

/// Manages screen frame capture for OCR pipeline
/// Thread-safe implementation with background processing
@MainActor
public final class OCRFrameCapture: NSObject, ObservableObject {
    
    // MARK: - Configuration
    
    public struct Configuration: Equatable, Sendable {
        public var enabled: Bool = false
        public var interval: TimeInterval = 30.0
        public var jpegQuality: CGFloat = 0.7
        public var maxDimension: CGFloat = 1280
        public var recognitionLevel: RecognitionLevel = .accurate
        public var languageCorrection: Bool = true
        
        public enum RecognitionLevel: Sendable {
            case fast
            case accurate
            
            var visionLevel: VNRequestTextRecognitionLevel {
                switch self {
                case .fast: return .fast
                case .accurate: return .accurate
                }
            }
        }
        
        public init(
            enabled: Bool = false,
            interval: TimeInterval = 30.0,
            jpegQuality: CGFloat = 0.7,
            maxDimension: CGFloat = 1280,
            recognitionLevel: RecognitionLevel = .accurate,
            languageCorrection: Bool = true
        ) {
            self.enabled = enabled
            self.interval = interval
            self.jpegQuality = jpegQuality
            self.maxDimension = maxDimension
            self.recognitionLevel = recognitionLevel
            self.languageCorrection = languageCorrection
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - Published State
    
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastCaptureTime: Date?
    @Published public private(set) var lastError: OCRError?
    @Published public private(set) var hasPermission = false
    
    // MARK: - Properties
    
    public weak var delegate: OCRResultDelegate?
    public var sessionId: String?
    
    private var configuration: Configuration {
        didSet {
            handleConfigurationChange(oldValue: oldValue)
        }
    }
    
    private var timer: Timer?
    private var isProcessing = false
    private let minCaptureInterval: TimeInterval = 5.0
    private let resourceMonitor = ResourceMonitor.shared
    private let logger = Logger(subsystem: "com.echopanel.app", category: "OCRFrameCapture")
    
    // MARK: - Adaptive Interval
    
    private var adaptiveInterval: TimeInterval {
        if resourceMonitor.shouldThrottleCPU() {
            return configuration.interval * 2.0
        } else if resourceMonitor.shouldThrottleMemory() {
            return configuration.interval * 1.5
        } else {
            return configuration.interval
        }
    }
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        super.init()
        
        Task {
            await checkPermissions()
        }
    }
    
    // MARK: - Permission Management
    
    public func checkPermissions() async {
        // Check screen recording permission using ScreenCaptureKit
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            hasPermission = !content.windows.isEmpty || !content.displays.isEmpty
        } catch {
            hasPermission = false
            logger.warning("Screen recording permission check failed: \(error.localizedDescription)")
        }
    }
    
    public func requestPermission() async -> Bool {
        // Use CGRequestScreenCaptureAccess for legacy permission
        let granted = CGRequestScreenCaptureAccess()
        hasPermission = granted
        
        if !granted {
            logger.warning("Screen recording permission denied")
        }
        
        return granted
    }
    
    // MARK: - Configuration Management
    
    public func updateConfiguration(_ config: Configuration) {
        self.configuration = config
    }
    
    private func handleConfigurationChange(oldValue: Configuration) {
        // Handle enabled state change
        if oldValue.enabled != configuration.enabled {
            if configuration.enabled {
                startCapture()
            } else {
                stopCapture()
            }
        }
        
        // Handle interval change while capturing
        if oldValue.interval != configuration.interval && isCapturing {
            restartTimer()
        }
    }
    
    // MARK: - Capture Control
    
    public func startCapture() {
        guard configuration.enabled else {
            logger.debug("Capture not enabled in configuration")
            return
        }
        
        guard !isCapturing else {
            logger.debug("Capture already in progress")
            return
        }
        
        guard hasPermission else {
            logger.error("Cannot start capture: screen recording permission not granted")
            lastError = .permissionDenied
            delegate?.didFailWithError(.permissionDenied)
            return
        }
        
        guard delegate != nil else {
            logger.warning("No delegate set for OCR results")
            return
        }
        
        isCapturing = true
        delegate?.didChangeCaptureState(true)
        
        logger.info("Starting OCR capture with interval: \(self.configuration.interval)s, maxDimension: \(self.configuration.maxDimension)")
        
        // Immediate first capture
        Task { await captureFrame() }
        
        // Start timer with adaptive interval
        restartTimer()
    }
    
    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: adaptiveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureFrame()
            }
        }
    }
    
    public func stopCapture() {
        guard isCapturing else { return }
        
        isCapturing = false
        timer?.invalidate()
        timer = nil
        
        delegate?.didChangeCaptureState(false)
        logger.info("Stopped OCR capture")
    }
    
    // MARK: - Frame Capture
    
    private func captureFrame() async {
        // State guards
        guard isCapturing else { return }
        guard !isProcessing else {
            logger.debug("Skipping capture: previous frame still processing")
            return
        }
        
        // Resource throttling
        if resourceMonitor.shouldThrottleCPU() {
            logger.debug("Skipping capture due to CPU pressure")
            return
        }
        
        if resourceMonitor.shouldThrottleMemory() {
            logger.debug("Skipping capture due to memory pressure")
            return
        }
        
        // Minimum interval check
        if let lastTime = lastCaptureTime,
           Date().timeIntervalSince(lastTime) < minCaptureInterval {
            logger.debug("Skipping capture: minimum interval not reached")
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        lastCaptureTime = Date()
        let startTime = Date()
        
        // Offload heavy work to background thread
        let result = await Task.detached(priority: .utility) { [weak self, configuration, sessionId] in
            await Self.performOCRCapture(
                configuration: configuration,
                sessionId: sessionId
            )
        }.value
        
        // Handle result back on MainActor
        switch result {
        case .success(let ocrResult):
            let processingTime = Date().timeIntervalSince(startTime)
            let finalResult = OCRCaptureResult(
                text: ocrResult.text,
                timestamp: startTime,
                processingTime: processingTime,
                imageSize: ocrResult.imageSize,
                sessionId: sessionId
            )
            
            if !finalResult.text.isEmpty {
                delegate?.didCaptureResult(finalResult)
                logger.debug("OCR capture completed: \(ocrResult.text.count) characters in \(processingTime)s")
            }
            
        case .failure(let error):
            lastError = error
            delegate?.didFailWithError(error)
            logger.error("OCR capture failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Static OCR Processing (Background Thread)
    
    private static func performOCRCapture(
        configuration: Configuration,
        sessionId: String?
    ) async -> Result<(text: String, imageSize: CGSize), OCRError> {
        
        // Capture screen using CoreGraphics
        guard let screenImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            return .failure(.noFrameReceived)
        }
        
        let originalSize = CGSize(width: screenImage.width, height: screenImage.height)
        
        // Downsample if needed
        let processedImage: CGImage
        if configuration.maxDimension > 0 && CGFloat(screenImage.width) > configuration.maxDimension {
            guard let downsampled = downsample(image: screenImage, maxDimension: configuration.maxDimension) else {
                return .failure(.compressionFailed)
            }
            processedImage = downsampled
        } else {
            processedImage = screenImage
        }
        
        let finalSize = CGSize(width: processedImage.width, height: processedImage.height)
        
        // Perform OCR using Swift Concurrency
        let text = await performOCR(
            on: processedImage,
            recognitionLevel: configuration.recognitionLevel,
            languageCorrection: configuration.languageCorrection
        )
        
        return .success((text: text, imageSize: finalSize))
    }
    
    private static func performOCR(
        on image: CGImage,
        recognitionLevel: Configuration.RecognitionLevel,
        languageCorrection: Bool
    ) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    os_log(.error, "OCR error: %@", error.localizedDescription)
                    continuation.resume(returning: "")
                    return
                }
                
                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
                let fullText = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: fullText)
            }
            
            request.recognitionLevel = recognitionLevel.visionLevel
            request.usesLanguageCorrection = languageCorrection
            
            // Use CGImage directly - no NSImage/Data conversion needed
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                os_log(.error, "OCR perform error: %@", error.localizedDescription)
                continuation.resume(returning: "")
            }
        }
    }
    
    // MARK: - Image Processing
    
    private static func downsample(image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let widthRatio = maxDimension / CGFloat(image.width)
        let heightRatio = maxDimension / CGFloat(image.height)
        let ratio = min(widthRatio, heightRatio, 1.0) // Don't upscale
        
        let newSize = CGSize(
            width: CGFloat(image.width) * ratio,
            height: CGFloat(image.height) * ratio
        )
        
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: newSize))
        
        return context.makeImage()
    }
    
    // MARK: - Manual Capture
    
    public func captureNow() async -> Result<OCRCaptureResult, OCRError> {
        guard hasPermission else {
            return .failure(.permissionDenied)
        }
        
        let startTime = Date()
        
        let result = await Task.detached(priority: .utility) { [configuration, sessionId] in
            await Self.performOCRCapture(
                configuration: configuration,
                sessionId: sessionId
            )
        }.value
        
        switch result {
        case .success(let ocrResult):
            let processingTime = Date().timeIntervalSince(startTime)
            return .success(OCRCaptureResult(
                text: ocrResult.text,
                timestamp: startTime,
                processingTime: processingTime,
                imageSize: ocrResult.imageSize,
                sessionId: sessionId
            ))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        timer?.invalidate()
    }
}
