import AVFoundation
import Foundation

/// Voice note capture manager for recording short voice notes during meetings.
/// Reuses AVAudioEngine patterns from MicrophoneCaptureManager but optimized for short recordings.
final class VoiceNoteCaptureManager: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isRecording = false
    @Published private(set) var currentLevel: Float = 0
    @Published private(set) var error: VoiceNoteCaptureError?
    
    // MARK: - Configuration
    
    /// Maximum duration for a single voice note (60 seconds)
    let maxDuration: TimeInterval = 60.0
    
    /// Audio format: 16kHz mono PCM16 (same as main audio pipeline)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1
    
    // MARK: - Callbacks
    
    /// Called with PCM audio data chunks during recording
    var onPCMFrame: ((Data) -> Void)?
    
    /// Called when recording starts
    var onRecordingStarted: (() -> Void)?
    
    /// Called when recording stops (with final audio duration)
    var onRecordingStopped: ((TimeInterval) -> Void)?
    
    // MARK: - Private State
    
    private lazy var audioEngine = AVAudioEngine()
    private var isRunning = false
    private var recordingStartTime: Date?
    private var pcmRemainder: [Int16] = []
    private let frameSize = 320 // 20ms at 16kHz
    
    private var levelEMA: Float = 0
    private let levelLock = NSLock()
    
    private var maxDurationTimer: Timer?
    
    // MARK: - Errors
    
    enum VoiceNoteCaptureError: Error, LocalizedError {
        case permissionDenied
        case engineStartFailed(Error)
        case recordingTooLong
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission denied. Please enable in System Settings."
            case .engineStartFailed(let error):
                return "Failed to start audio engine: \(error.localizedDescription)"
            case .recordingTooLong:
                return "Voice note exceeded maximum duration."
            }
        }
    }
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
    }
    
    deinit {
        Task { @MainActor in
            await stopRecording()
        }
    }
    
    // MARK: - Permission
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func checkPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    // MARK: - Recording Control
    
    /// Start recording a voice note
    @MainActor
    func startRecording() async throws {
        guard !isRecording else { return }
        
        // Check permission
        let hasPermission = checkPermission()
        if !hasPermission {
            let granted = await requestPermission()
            if !granted {
                error = .permissionDenied
                throw VoiceNoteCaptureError.permissionDenied
            }
        }
        
        // Reset state
        error = nil
        pcmRemainder = []
        recordingStartTime = Date()
        
        do {
            try startAudioEngine()
        } catch {
            self.error = .engineStartFailed(error)
            throw VoiceNoteCaptureError.engineStartFailed(error)
        }
        
        isRecording = true
        onRecordingStarted?()
        
        // Start max duration timer
        self.maxDurationTimer = Timer.scheduledTimer(
            withTimeInterval: maxDuration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.stopRecording()
            }
        }
    }
    
    /// Stop recording the current voice note
    @MainActor
    func stopRecording() async {
        guard isRecording else { return }
        
        // Cancel max duration timer
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        
        // Stop audio engine
        stopAudioEngine()
        
        // Calculate duration
        let duration: TimeInterval
        if let startTime = recordingStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = 0
        }
        
        // Flush any remaining PCM data
        flushRemainingPCM()
        
        // Reset state
        isRecording = false
        recordingStartTime = nil
        currentLevel = 0
        levelEMA = 0
        
        onRecordingStopped?(duration)
    }
    
    // MARK: - Audio Engine
    
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create target format (16kHz mono Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            throw VoiceNoteCaptureError.engineStartFailed(
                NSError(domain: "VoiceNoteCapture", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Failed to create target format"])
            )
        }
        
        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(frameSize),
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer: buffer, targetFormat: targetFormat)
        }
        
        // Start engine
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }
    
    private func stopAudioEngine() {
        guard isRunning else { return }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let samples = channelData[0]
        
        // Update audio level
        updateAudioLevel(samples: samples, count: frameCount)
        
        // Convert to PCM16 and emit frames
        convertAndEmitFrames(samples: samples, count: frameCount)
    }
    
    private func updateAudioLevel(samples: UnsafePointer<Float>, count: Int) {
        var sumSquares: Float = 0
        for i in 0..<count {
            let sample = samples[i]
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Float(count))
        
        levelLock.lock()
        let alpha: Float = 0.3
        levelEMA = alpha * rms + (1 - alpha) * levelEMA
        let level = levelEMA
        levelLock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.currentLevel = level
        }
    }
    
    private func convertAndEmitFrames(samples: UnsafePointer<Float>, count: Int) {
        // Convert Float32 to Int16
        var pcmSamples: [Int16] = []
        pcmSamples.reserveCapacity(count)
        
        for i in 0..<count {
            let value = max(-1.0, min(1.0, samples[i]))
            let int16Value = Int16(value * Float(Int16.max))
            pcmSamples.append(int16Value)
        }
        
        // Combine with remainder and emit frames
        pcmRemainder.append(contentsOf: pcmSamples)
        
        while pcmRemainder.count >= frameSize {
            let frameData = Array(pcmRemainder.prefix(frameSize))
            pcmRemainder.removeFirst(frameSize)
            
            // Convert to Data
            let data = frameData.withUnsafeBufferPointer { Data(buffer: $0) }
            onPCMFrame?(data)
        }
    }
    
    private func flushRemainingPCM() {
        // Emit any remaining samples as final frame
        guard !pcmRemainder.isEmpty else { return }
        
        // Pad to frame size if needed
        while pcmRemainder.count < frameSize {
            pcmRemainder.append(0)
        }
        
        let frameData = pcmRemainder.withUnsafeBufferPointer { Data(buffer: $0) }
        onPCMFrame?(frameData)
        pcmRemainder = []
    }
}
