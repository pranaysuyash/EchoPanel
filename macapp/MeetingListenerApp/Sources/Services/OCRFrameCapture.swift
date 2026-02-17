import Foundation
import ScreenCaptureKit
import AppKit
import Vision
import OSLog

/// Manages screen frame capture for OCR pipeline
@MainActor
class OCRFrameCapture: NSObject {

    struct Configuration {
        var enabled: Bool = false
        var interval: TimeInterval = 30.0
        var jpegQuality: CGFloat = 0.7
        var maxDimension: CGFloat = 1280
    }

    private var configuration: Configuration
    private var timer: Timer?
    private var isCapturing = false

    weak var streamer: WebSocketStreamer?
    var sessionId: String?

    private var lastCaptureTime: Date?
    private let minCaptureInterval: TimeInterval = 5.0
    private let resourceMonitor = ResourceMonitor.shared
    private let logger = Logger(subsystem: "com.echopanel.app", category: "OCRFrameCapture")

    // Resource-aware capture throttling
    private var adaptiveInterval: TimeInterval {
        // Increase interval when under resource pressure
        if resourceMonitor.shouldThrottleCPU() {
            return configuration.interval * 2.0 // Double the interval
        } else if resourceMonitor.shouldThrottleMemory() {
            return configuration.interval * 1.5 // 1.5x the interval
        } else {
            return configuration.interval
        }
    }
    
    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        super.init()
    }
    
    func updateConfiguration(_ config: Configuration) {
        let wasEnabled = self.configuration.enabled
        self.configuration = config
        
        if wasEnabled != config.enabled {
            if config.enabled && isCapturing {
                stopCapture()
                startCapture()
            } else if !config.enabled {
                stopCapture()
            }
        }
    }
    
    func startCapture() {
        guard configuration.enabled else { return }
        guard !isCapturing else { return }
        guard streamer?.isConnected == true else { return }
        
        isCapturing = true
        
        Task { await captureFrame() }
        
        timer = Timer.scheduledTimer(withTimeInterval: adaptiveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureFrame() }
        }
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        timer?.invalidate()
        timer = nil
    }
    
    private func captureFrame() async {
        guard isCapturing, let streamer = streamer, streamer.isConnected else { return }

        // Skip capture if under resource pressure
        if resourceMonitor.shouldThrottleCPU() {
            logger.debug("Skipping OCR capture due to CPU pressure")
            return
        }

        if let lastTime = lastCaptureTime,
           Date().timeIntervalSince(lastTime) < minCaptureInterval {
            return
        }

        lastCaptureTime = Date()

        // Capture screen and perform OCR using Vision framework
        if let screenImage = CGDisplayCreateImage(CGMainDisplayID()) {
            let image = NSImage(cgImage: screenImage, size: NSZeroSize)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else { return }
            guard let ciImage = CIImage(bitmapImageRep: bitmap) else { return }
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    NSLog("OCR error: \(error.localizedDescription)")
                    return
                }
                guard let results = request.results as? [VNRecognizedTextObservation] else { return }
                let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
                let fullText = recognizedStrings.joined(separator: "\n")
                // Send the recognized text via the streamer (if needed)
                if let streamer = self.streamer {
                    streamer.sendOCRText(fullText)
                }
            }
            request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("Failed to perform OCR request: \(error.localizedDescription)")
            }
        }
    }
}

enum OCRError: Error {
    case noFrameReceived
    case compressionFailed
}
