import Foundation
import ScreenCaptureKit
import AppKit

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
        
        timer = Timer.scheduledTimer(withTimeInterval: configuration.interval, repeats: true) { [weak self] _ in
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
        
        if let lastTime = lastCaptureTime,
           Date().timeIntervalSince(lastTime) < minCaptureInterval {
            return
        }
        
        lastCaptureTime = Date()
        
        // Placeholder - actual implementation would capture screen
        // and send via WebSocket
    }
}

enum OCRError: Error {
    case noFrameReceived
    case compressionFailed
}
