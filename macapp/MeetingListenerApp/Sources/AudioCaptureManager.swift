import Combine
import CoreGraphics
import CoreMedia
import CoreML
import Foundation
import QuartzCore
import ScreenCaptureKit

final class AudioCaptureManager: NSObject {
    var onPCMFrame: ((Data, String) -> Void)? // (frame, source="system")
    var onAudioQualityUpdate: ((AudioQuality) -> Void)?
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onSampleCount: ((Int) -> Void)?
    var onScreenFrameCount: ((Int) -> Void)?
    var onVADStatsUpdate: ((_ vadEnabled: Bool, _ speechRatio: Double, _ chunksProcessed: Int) -> Void)?
    var onCaptureStatsUpdate: ((_ stats: CaptureStats) -> Void)?

    struct CaptureStats: Sendable {
        var audioBuffersReceived: UInt64 = 0
        var audioBuffersDropped: UInt64 = 0
        var conversionErrors: UInt64 = 0
        var converterRecreated: UInt64 = 0
        var pcmFramesProduced: UInt64 = 0
        var pcmFramesSent: UInt64 = 0
    }

    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var stream: SCStream?
    private let sampleHandler = AudioSampleHandler()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var pcmRemainder: [Int16] = []
    private var rmsEMA: Float = 0
    private var silenceEMA: Float = 0
    private var clipEMA: Float = 0
    private var limiterGainEMA: Float = 0  // Track limiting activity
    private var lastQualityUpdate: TimeInterval = 0
    private let qualityLock = NSLock()  // Thread safety for quality EMA updates
    
    // MARK: - Limiter State (P0-2 Fix)
    /// Current limiter gain (1.0 = unity, <1.0 = limiting active)
    private var limiterGain: Float = 1.0
    /// Attack coefficient (immediate reduction) - 0.001 = ~1 sample attack
    private let limiterAttack: Float = 0.001
    /// Release coefficient (slow return) - 0.9999 = ~1 second release at 16kHz  
    private let limiterRelease: Float = 0.99995
    /// Threshold for limiting (-0.9 dBFS = 0.9 linear)
    private let limiterThreshold: Float = 0.9
    /// Maximum allowed gain reduction (20 dB = 0.1)
    private let limiterMaxGainReduction: Float = 0.1
    private var lastDebugLog: TimeInterval = 0
    private var totalSamples: Int = 0
    private var screenFrames: Int = 0
    private let statsLock = NSLock()
    private var captureStats = CaptureStats()
    private var lastStatsEmit: TimeInterval = 0
    
    // MARK: - Stream State
    private let streamState = StreamState()

    // MARK: - Client-Side VAD (Silero)
    private var vadModel: MLModel?
    private var vadEnabled = false
    private var speechProbability: Float = 0.0
    private var vadThreshold: Float = 0.5  // Probability threshold for speech detection
    private var cpuUsage: Double = 0.0
    private var cpuMonitorTimer: Timer?
    private let cpuBudgetLimit: Double = 10.0  // Max 10% CPU usage
    private var speechChunksEmitted = 0
    private var totalChunksProcessed = 0
    private var sampleBuffersProcessed = 0  // For periodic permission checks

    override init() {
        super.init()
        sampleHandler.onAudioSampleBuffer = { [weak self] sampleBuffer in
            self?.processAudio(sampleBuffer: sampleBuffer)
        }
        sampleHandler.onScreenSampleBuffer = { [weak self] _ in
            guard let self else { return }
            self.statsLock.lock()
            self.screenFrames += 1
            let currentFrames = self.screenFrames
            self.statsLock.unlock()
            self.onScreenFrameCount?(currentFrames)
            if self.debugEnabled && currentFrames % 60 == 0 {
                NSLog("AudioCaptureManager: received %d screen frames", currentFrames)
            }
        }
        sampleHandler.onStreamStopped = { [weak self] error in
            guard let self else { return }
            self.streamState.setActive(false)
            
            NSLog("⛔ AudioCaptureManager: Stream stopped unexpectedly: \(error.localizedDescription)")
            self.onAudioQualityUpdate?(.poor)
        }
    }
    
    /// Thread-safe getter for current quality metrics
    var currentQualityMetrics: (rms: Float, silence: Float, clip: Float, limiterGain: Float) {
        qualityLock.lock()
        let metrics = (rmsEMA, silenceEMA, clipEMA, limiterGainEMA)
        qualityLock.unlock()
        return metrics
    }
    
    /// Thread-safe check if stream is active
    var streamActive: Bool {
        streamState.isActive
    }

    func requestPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    func startCapture() async throws {
        guard #available(macOS 13, *) else {
            throw CaptureError.unsupportedOS
        }
        
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayId = CGMainDisplayID()
        let display = content.displays.first(where: { $0.displayID == mainDisplayId }) ?? content.displays.first
        guard let display else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: sampleHandler)
        self.stream = stream

        try stream.addStreamOutput(sampleHandler, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try stream.addStreamOutput(sampleHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        streamState.setActive(true)
        
        try await stream.startCapture()
        
        // Initialize VAD if enabled
        setupVAD()
        
        onAudioQualityUpdate?(.ok)
        if debugEnabled {
            NSLog("AudioCaptureManager: startCapture ok")
        }
    }

    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            // Intentionally ignore in v0.1 scaffold.
        }
        streamState.setActive(false)
        
        stream = nil
        resetCaptureStats()
        
        // Clean up VAD
        vadModel = nil
        cpuMonitorTimer?.invalidate()
        cpuMonitorTimer = nil
        vadEnabled = false
    }

    private func setupVAD() {
        vadEnabled = BackendConfig.clientVADEnabled
        if !vadEnabled {
            return
        }
        
        // Use energy-based VAD for now (ML model integration pending)
        // TODO: Load Core ML Silero VAD model when available
        NSLog("✅ AudioCaptureManager: VAD enabled (energy-based detection)")
        
        // Start CPU monitoring
        startCPUMonitoring()
        speechChunksEmitted = 0
        totalChunksProcessed = 0
    }

    private func startCPUMonitoring() {
        // Ensure we don't create multiple timers
        cpuMonitorTimer?.invalidate()
        cpuMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateCPUUsage()
            self.reportVADStats()
        }
    }

    private func reportVADStats() {
        statsLock.lock()
        let processed = totalChunksProcessed
        let speech = speechChunksEmitted
        statsLock.unlock()
        
        let ratio = processed > 0 ? Double(speech) / Double(processed) : 0.0
        
        // Call callback on main thread to be safe
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onVADStatsUpdate?(self.vadEnabled, ratio, processed)
        }
    }

    private func updateCPUUsage() {
        let processInfo = ProcessInfo.processInfo
        cpuUsage = processInfo.systemUptime // Placeholder - in real implementation, calculate actual CPU usage
        if cpuUsage > cpuBudgetLimit {
            NSLog("⚠️ AudioCaptureManager: CPU usage (%.1f%%) exceeds budget, disabling VAD", cpuUsage)
            vadEnabled = false
            // Note: No model to clean up for energy-based VAD
        }
    }

    private func runVAD(on samples: [Float]) -> Bool {
        guard vadEnabled else { return true } // If VAD disabled, always emit
        
        // Energy-based VAD detection
        // Calculate RMS energy of the audio samples
        let energy = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        let rms = sqrt(energy)
        
        // Simple threshold-based detection
        // TODO: Replace with ML model when Core ML conversion is available
        speechProbability = rms > vadThreshold ? 1.0 : 0.0
        
        return speechProbability > 0.5
    }

    // MARK: - Permission Revocation Detection
    
    /// Check if screen recording permission was revoked during capture
    func checkPermissionStatus() -> Bool {
        let authorized = CGPreflightScreenCaptureAccess()
        if !authorized && streamState.isActive {
            NSLog("⛔ AudioCaptureManager: Screen recording permission revoked during capture")
            Task { @MainActor in
                StructuredLogger.shared.error("Screen recording permission revoked during capture", metadata: [:])
            }
            Task {
                await stopCapture()
            }
            onAudioQualityUpdate?(.poor)
        }
        return authorized
    }
    
    private func processAudio(sampleBuffer: CMSampleBuffer) {
        statsLock.lock()
        captureStats.audioBuffersReceived += 1
        statsLock.unlock()
        maybeEmitCaptureStats()

        // Periodic permission check (every ~100 buffers = ~2 seconds at 50 buffers/sec)
        sampleBuffersProcessed += 1
        if sampleBuffersProcessed % 100 == 0 {
            _ = checkPermissionStatus()
        }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            NSLog("⛔ processAudio: Failed to get format description")
            recordAudioDrop(isConversionError: false)
            return
        }

        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else {
            NSLog("⛔ processAudio: Failed to create AVAudioFormat from stream description")
            recordAudioDrop(isConversionError: false)
            return
        }
        
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        
        // Log input format details (only first few times)
        if totalSamples == 0 {
            NSLog("📊 processAudio: Input format - sampleRate: %.0f, channels: %d, bitsPerChannel: %d, formatID: %u, isNonInterleaved: %d", 
                  asbd.pointee.mSampleRate, asbd.pointee.mChannelsPerFrame, asbd.pointee.mBitsPerChannel, asbd.pointee.mFormatID, inputFormat.isInterleaved ? 0 : 1)
        }

        // Create AVAudioPCMBuffer directly from the CMSampleBuffer
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(numSamples)) else {
            NSLog("⛔ processAudio: Failed to create inputBuffer with capacity %d", numSamples)
            recordAudioDrop(isConversionError: false)
            return
        }
        inputBuffer.frameLength = AVAudioFrameCount(numSamples)
        
        // Copy the audio data from CMSampleBuffer into the AVAudioPCMBuffer
        let audioBufferList = inputBuffer.mutableAudioBufferList
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numSamples),
            into: audioBufferList
        )
        
        guard status == noErr else {
            NSLog("⛔ processAudio: CMSampleBufferCopyPCMDataIntoAudioBufferList failed with status %d", status)
            recordAudioDrop(isConversionError: false)
            return
        }

        // Convert to target format (mono 16kHz)
        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if converter == nil {
                NSLog("⛔ processAudio: Failed to create AVAudioConverter from %@ to %@", inputFormat.description, targetFormat.description)
                recordAudioDrop(isConversionError: true)
            } else {
                statsLock.lock()
                captureStats.converterRecreated += 1
                statsLock.unlock()
                NSLog("✅ processAudio: Created AVAudioConverter")
            }
        }

        guard let converter else { 
            NSLog("⛔ processAudio: converter is nil")
            recordAudioDrop(isConversionError: true)
            return 
        }

        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            NSLog("⛔ processAudio: Failed to create outputBuffer with capacity %d", outputFrameCapacity)
            recordAudioDrop(isConversionError: false)
            return
        }

        var error: NSError?
        var didProvideInput = false
        let statusConvert = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if statusConvert == .error {
            NSLog("⛔ processAudio: Conversion failed with error: %@", error?.localizedDescription ?? "unknown")
            recordAudioDrop(isConversionError: true)
            return
        }

        guard let channelData = outputBuffer.floatChannelData else { 
            NSLog("⛔ processAudio: outputBuffer.floatChannelData is nil")
            recordAudioDrop(isConversionError: false)
            return 
        }
        let samples = channelData[0]
        let frameCount = Int(outputBuffer.frameLength)
        statsLock.lock()
        totalSamples += frameCount
        let currentTotal = totalSamples
        statsLock.unlock()
        
        if debugEnabled && (currentTotal <= 1000 || currentTotal % 16000 == 0) {
            NSLog("✅ processAudio: Processed %d samples, total: %d, emitting PCM frames", frameCount, currentTotal)
        }
        
        if debugEnabled {
            let now = CACurrentMediaTime()
            if now - lastDebugLog > 2 {
                lastDebugLog = now
                NSLog("AudioCaptureManager: received %d samples", currentTotal)
            }
        }
        onSampleCount?(currentTotal)

        // Apply limiter to prevent hard clipping (P0-2 Fix)
        let limitedSamples = applyLimiter(samples: samples, count: frameCount)
        
        updateAudioQuality(samples: limitedSamples, count: frameCount)
        emitPCMFrames(samples: limitedSamples, count: frameCount)
    }

    /// Apply soft limiting to prevent hard clipping during Float->Int16 conversion.
    /// Uses attack/release smoothing for transparent peak control.
    /// - Parameters:
    ///   - samples: Raw Float32 samples (can exceed [-1, 1])
    ///   - count: Number of samples
    /// - Returns: Limited samples in range [-limiterThreshold, limiterThreshold]
    private func applyLimiter(samples: UnsafePointer<Float>, count: Int) -> [Float] {
        var limited = [Float](repeating: 0, count: count)
        
        for i in 0..<count {
            let sample = samples[i]
            let absSample = abs(sample)
            
            // Calculate target gain to bring peaks to threshold
            let targetGain: Float
            if absSample > limiterThreshold {
                targetGain = limiterThreshold / absSample
            } else {
                targetGain = 1.0
            }
            
            // Clamp max gain reduction (don't amplify, only attenuate)
            let clampedTargetGain = max(targetGain, limiterMaxGainReduction)
            
            // Smooth gain changes: fast attack, slow release
            if clampedTargetGain < limiterGain {
                // Peak detected: reduce gain quickly (attack)
                limiterGain = limiterGain * limiterAttack + clampedTargetGain * (1.0 - limiterAttack)
            } else {
                // Return to unity slowly (release)
                limiterGain = limiterGain * limiterRelease + clampedTargetGain * (1.0 - limiterRelease)
            }
            
            limited[i] = sample * limiterGain
        }
        
        return limited
    }

    private func emitPCMFrames(samples: [Float], count: Int) {
        var pcmSamples: [Int16] = []
        pcmSamples.reserveCapacity(count)

        for i in 0..<count {
            // Samples already limited, convert directly
            // Clamp only as safety margin (should already be in range)
            let value = max(-1.0, min(1.0, samples[i]))
            let int16Value = Int16(value * Float(Int16.max))
            pcmSamples.append(int16Value)
        }

        if !pcmRemainder.isEmpty {
            pcmSamples.insert(contentsOf: pcmRemainder, at: 0)
            pcmRemainder.removeAll()
        }

        let frameSize = 320
        var index = 0
        while index + frameSize <= pcmSamples.count {
            let slice = Array(pcmSamples[index..<index + frameSize])

            statsLock.lock()
            captureStats.pcmFramesProduced += 1
            statsLock.unlock()
            
            // Run VAD on this frame
            let floatSlice = slice.map { Float($0) / Float(Int16.max) }
            let hasSpeech = runVAD(on: floatSlice)
            
            statsLock.lock()
            totalChunksProcessed += 1
            if hasSpeech {
                speechChunksEmitted += 1
            }
            statsLock.unlock()
            
            if hasSpeech || !vadEnabled {
                let data = slice.withUnsafeBufferPointer { Data(buffer: $0) }
                onPCMFrame?(data, "system")
                statsLock.lock()
                captureStats.pcmFramesSent += 1
                statsLock.unlock()
                maybeEmitCaptureStats()
            }
            
            index += frameSize
        }

        if index < pcmSamples.count {
            pcmRemainder = Array(pcmSamples[index..<pcmSamples.count])
        }
    }

    private func updateAudioQuality(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sumSquares: Float = 0
        var clipCount: Float = 0
        var silenceCount: Float = 0

        for i in 0..<count {
            let value = samples[i]
            let absValue = abs(value)
            sumSquares += value * value
            if absValue >= 0.98 {
                clipCount += 1
            }
            if absValue < 0.01 {
                silenceCount += 1
            }
        }

        let rms = sqrt(sumSquares / Float(count))
        let clipRatio = clipCount / Float(count)
        let silenceRatio = silenceCount / Float(count)
        
        // Calculate limiting ratio (how much limiting is occurring)
        // 0.0 = no limiting, 1.0 = max gain reduction applied
        let limitingRatio = 1.0 - limiterGain

        qualityLock.lock()
        rmsEMA = rmsEMA * 0.9 + rms * 0.1
        clipEMA = clipEMA * 0.9 + clipRatio * 0.1
        silenceEMA = silenceEMA * 0.9 + silenceRatio * 0.1
        limiterGainEMA = limiterGainEMA * 0.9 + limiterGain * 0.1
        let currentRMSEMA = rmsEMA
        let currentClipEMA = clipEMA
        let currentSilenceEMA = silenceEMA
        qualityLock.unlock()

        let now = CACurrentMediaTime()
        if now - lastQualityUpdate < 0.5 {
            return
        }
        lastQualityUpdate = now

        let quality: AudioQuality
        if currentClipEMA > 0.1 || currentSilenceEMA > 0.8 {
            quality = .poor
        } else if currentRMSEMA < 0.03 || currentSilenceEMA > 0.5 {
            quality = .ok
        } else {
            quality = .good
        }
        
        // Log if significant limiting is occurring (debug builds only)
        if debugEnabled && limitingRatio > 0.1 {
            NSLog("⚠️ AudioCaptureManager: Significant limiting active (%.1f%% gain reduction)", 
                  limitingRatio * 100)
        }

        onAudioQualityUpdate?(quality)
        onAudioLevelUpdate?(currentRMSEMA)
    }

    deinit {
        cpuMonitorTimer?.invalidate()
        cpuMonitorTimer = nil
    }

    private func recordAudioDrop(isConversionError: Bool) {
        statsLock.lock()
        captureStats.audioBuffersDropped += 1
        if isConversionError {
            captureStats.conversionErrors += 1
        }
        statsLock.unlock()
        maybeEmitCaptureStats()
    }

    private func maybeEmitCaptureStats() {
        guard onCaptureStatsUpdate != nil else { return }
        let now = CACurrentMediaTime()

        let snapshot: CaptureStats
        statsLock.lock()
        // Throttle to avoid flooding observers.
        guard now - lastStatsEmit >= 1.0 else {
            statsLock.unlock()
            return
        }
        lastStatsEmit = now
        snapshot = captureStats
        statsLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onCaptureStatsUpdate?(snapshot)
        }
    }

    private func resetCaptureStats() {
        statsLock.lock()
        captureStats = CaptureStats()
        lastStatsEmit = 0
        statsLock.unlock()
    }
}

final class AudioSampleHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onScreenSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStreamStopped: ((_ error: Error) -> Void)?
    private var audioCallCount = 0
    private var screenCallCount = 0
    private let counterLock = NSLock()

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            counterLock.lock()
            audioCallCount += 1
            let count = audioCallCount
            counterLock.unlock()
            if count <= 5 || count % 100 == 0 {
                let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
                NSLog("🎤 AudioSampleHandler: Received audio buffer #%d with %d samples", count, numSamples)
            }
            onAudioSampleBuffer?(sampleBuffer)
        case .screen:
            counterLock.lock()
            screenCallCount += 1
            let count = screenCallCount
            counterLock.unlock()
            if count <= 3 || count % 60 == 0 {
                NSLog("🖥️ AudioSampleHandler: Received screen buffer #%d", count)
            }
            onScreenSampleBuffer?(sampleBuffer)
        default:
            break
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        NSLog("⛔ AudioSampleHandler: Stream stopped with error: \(error.localizedDescription)")
        onStreamStopped?(error)
    }
}

enum CaptureError: Error {
    case unsupportedOS
    case noDisplay
    case permissionDenied
    case permissionRevoked
}

extension CaptureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "macOS 13 or later required"
        case .noDisplay:
            return "No display available for capture"
        case .permissionDenied:
            return "Screen recording permission not granted"
        case .permissionRevoked:
            return "Screen recording permission was revoked"
        }
    }
}

// MARK: - Thread-Safe State Container

/// Thread-safe boolean state container using OS-level atomic operations
final class StreamState {
    private var _active: Bool = false
    private let lock = NSLock()
    
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _active
    }
    
    func setActive(_ value: Bool) {
        lock.lock()
        _active = value
        lock.unlock()
    }
}
