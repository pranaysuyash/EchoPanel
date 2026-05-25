import AVFoundation
import Combine
import CoreAudio
import Foundation
import AudioToolbox

/// Captures microphone audio using AVAudioEngine and emits PCM16 frames.
final class MicrophoneCaptureManager: NSObject, ObservableObject {
    var onPCMFrame: ((Data, String) -> Void)? // (frame, source="mic")
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onError: ((Error) -> Void)?
    var onActiveDeviceChanged: ((String?, String?) -> Void)?
    
    private lazy var audioEngine = AVAudioEngine()
    private var isRunning = false
    private var pcmRemainder: [Int16] = []
    private let frameSize = 320 // 20ms at 16kHz
    private var levelEMA: Float = 0
    private let levelLock = NSLock()  // Thread safety for level EMA updates
    private var preferredDeviceID: String?
    private var activeDeviceID: String?
    private var activeDeviceName: String?
    
    // MARK: - Metrics (AUD-002 Improvement)
    private var metricsLock = NSLock()
    nonisolated private(set) var framesProcessed: UInt64 = 0
    nonisolated private(set) var framesDropped: UInt64 = 0
    nonisolated private(set) var bufferUnderruns: UInt64 = 0
    private var lastProcessTime: TimeInterval = 0
    
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
    
    // MARK: - Device Change Monitoring (AUD-002 Improvement)
    // Uses AVCaptureDevice notifications (macOS compatible)
    private var deviceConnectedObserver: NSObjectProtocol?
    private var deviceDisconnectedObserver: NSObjectProtocol?
    private var lastDeviceID: String?
    
    deinit {
        stopCapture()
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
    
    // MARK: - Capture Lifecycle

    var isCapturing: Bool { isRunning }

    func setPreferredDevice(id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        preferredDeviceID = (normalized?.isEmpty == true) ? nil : normalized
    }
    
    func startCapture() throws {
        guard !isRunning else { 
            NSLog("MicrophoneCaptureManager: Already running")
            return 
        }
        
        // Check permission before starting
        guard checkPermission() else {
            NSLog("MicrophoneCaptureManager: Permission not granted")
            throw MicCaptureError.permissionDenied
        }
        
        let inputNode = audioEngine.inputNode

        try applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Target format: 16kHz mono PCM Float32
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            NSLog("MicrophoneCaptureManager: Failed to create target format")
            throw MicCaptureError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            NSLog("MicrophoneCaptureManager: Failed to create converter from %@ to %@", inputFormat.description, targetFormat.description)
            throw MicCaptureError.converterCreationFailed
        }
        
        // Install tap with error handling
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRunning = true
            updateActiveDeviceMetadata()
            
            // Reset metrics
            resetMetrics()
            
            // Setup device change observers
            setupDeviceObservers()
            
            // Log on main actor
            Task { @MainActor in
                StructuredLogger.shared.info("Microphone capture started", metadata: [
                    "targetSampleRate": "16000",
                    "targetChannels": "1"
                ])
            }
            NSLog("MicrophoneCaptureManager: Started capture")
        } catch {
            NSLog("MicrophoneCaptureManager: Failed to start audio engine: %@", error.localizedDescription)
            inputNode.removeTap(onBus: 0)
            throw MicCaptureError.engineStartFailed(error)
        }
    }
    
    func stopCapture() {
        guard isRunning else { return }
        
        removeDeviceObservers()
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        pcmRemainder.removeAll()
        
        // Log final metrics
        let (processed, dropped, _) = getMetrics()
        Task { @MainActor in
            StructuredLogger.shared.info("Microphone capture stopped", metadata: [
                "framesProcessed": processed,
                "framesDropped": dropped
            ])
        }
        NSLog("MicrophoneCaptureManager: Stopped capture (processed: %llu, dropped: %llu)", processed, dropped)
    }
    
    // MARK: - Device Change Monitoring (macOS)
    
    private func setupDeviceObservers() {
        // Register current device
        updateActiveDeviceMetadata()
        
        // Monitor for device connection changes
        deviceConnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDeviceConnected(notification)
        }
        
        // Monitor for device disconnections
        deviceDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDeviceDisconnected(notification)
        }
    }
    
    private func removeDeviceObservers() {
        if let observer = deviceConnectedObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceConnectedObserver = nil
        }
        if let observer = deviceDisconnectedObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceDisconnectedObserver = nil
        }
    }
    
    private func handleDeviceConnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.audio) else { return }
        
        let deviceName = device.localizedName
        let deviceID = device.uniqueID

        NSLog("MicrophoneCaptureManager: Audio device connected - \(deviceName)")
        
        Task { @MainActor in
            StructuredLogger.shared.info("Audio device connected", metadata: [
                "deviceName": deviceName,
                "deviceID": deviceID
            ])
        }

        if let preferredDeviceID, preferredDeviceID == deviceID, isRunning {
            do {
                try applyPreferredInputDeviceIfNeeded(inputNode: audioEngine.inputNode)
                updateActiveDeviceMetadata()
            } catch {
                onError?(error)
            }
        }
    }
    
    private func handleDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.audio) else { return }
        
        let deviceName = device.localizedName
        let deviceID = device.uniqueID
        
        // Check if this was our active device
        if deviceID == lastDeviceID {
            NSLog("MicrophoneCaptureManager: Active device disconnected - \(deviceName)")
            
            Task { @MainActor in
                StructuredLogger.shared.error("Active microphone disconnected", metadata: [
                    "deviceName": deviceName,
                    "deviceID": deviceID
                ])
            }
            
            // Stop capture and report error
            if isRunning {
                stopCapture()
                onError?(MicCaptureError.deviceDisconnected)
            }
            
            lastDeviceID = nil
            activeDeviceID = nil
            activeDeviceName = nil
            onActiveDeviceChanged?(nil, nil)
        }
    }

    private func applyPreferredInputDeviceIfNeeded(inputNode: AVAudioInputNode) throws {
        guard let preferredDeviceID, !preferredDeviceID.isEmpty else {
            return
        }

        guard AVCaptureDevice.devices(for: .audio).contains(where: { $0.uniqueID == preferredDeviceID }) else {
            throw MicCaptureError.preferredDeviceUnavailable(preferredDeviceID)
        }

        guard let audioDeviceID = resolveAudioDeviceID(forUID: preferredDeviceID) else {
            throw MicCaptureError.unableToResolveAudioDeviceID(preferredDeviceID)
        }

        var targetDeviceID = audioDeviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard let audioUnit = inputNode.audioUnit else {
            throw MicCaptureError.audioUnitUnavailable
        }

        var status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &targetDeviceID,
            size
        )

        if status != noErr {
            status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                1,
                &targetDeviceID,
                size
            )
        }

        guard status == noErr else {
            throw MicCaptureError.deviceSelectionFailed(status: status, deviceID: preferredDeviceID)
        }

        lastDeviceID = preferredDeviceID
    }

    private func updateActiveDeviceMetadata() {
        let currentID = preferredDeviceID ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        lastDeviceID = currentID
        activeDeviceID = currentID
        activeDeviceName = currentID.flatMap { id in
            AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == id })?.localizedName
        }
        onActiveDeviceChanged?(activeDeviceID, activeDeviceName)
    }

    private func resolveAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var cfUID: CFString?
            status = AudioObjectGetPropertyData(
                deviceID,
                &uidAddress,
                0,
                nil,
                &uidSize,
                &cfUID
            )
            if status == noErr, let cfUID, cfUID as String == uid {
                return deviceID
            }
        }

        return nil
    }
    
    // MARK: - Permission Revocation Detection (AUD-002 Improvement)
    
    /// Check if permission was revoked during capture
    func checkPermissionStatus() -> Bool {
        let authorized = checkPermission()
        if !authorized && isRunning {
            NSLog("MicrophoneCaptureManager: Permission revoked during capture")
            Task { @MainActor in
                StructuredLogger.shared.error("Microphone permission revoked during capture", metadata: [:])
            }
            stopCapture()
            onError?(MicCaptureError.permissionRevoked)
        }
        return authorized
    }
    
    // MARK: - Buffer Processing
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let startTime = CACurrentMediaTime()
        
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        
        // Handle buffer allocation failure (AUD-002 Improvement)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            NSLog("MicrophoneCaptureManager: Failed to allocate output buffer (capacity: %u)", outputFrameCapacity)
            incrementFramesDropped()
            return
        }
        
        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        // Handle conversion failure (AUD-002 Improvement)
        guard status != .error, let channelData = outputBuffer.floatChannelData else {
            if let err = error {
                NSLog("MicrophoneCaptureManager: Audio conversion failed: %@", err.localizedDescription)
            } else {
                NSLog("MicrophoneCaptureManager: Audio conversion failed - no channel data")
            }
            incrementFramesDropped()
            return
        }
        
        let samples = channelData[0]
        let frameCount = Int(outputBuffer.frameLength)
        
        // Apply limiter to prevent hard clipping (P0-2 Fix)
        let limitedSamples = applyLimiter(samples: samples, count: frameCount)
        
        // Update audio level
        updateAudioLevel(samples: limitedSamples, count: frameCount)
        
        // Emit PCM frames
        emitPCMFrames(samples: limitedSamples, count: frameCount)
        
        // Update metrics
        incrementFramesProcessed()
        
        // Check for buffer processing delays (AUD-002 Improvement)
        let processingTime = CACurrentMediaTime() - startTime
        if processingTime > 0.01 { // 10ms threshold
            NSLog("MicrophoneCaptureManager: Slow buffer processing (%.2f ms, %d frames)", processingTime * 1000, frameCount)
        }
        
        // Periodic permission check (every ~100 buffers = ~2 seconds at 50 buffers/sec)
        if framesProcessed % 100 == 0 {
            _ = checkPermissionStatus()
        }
    }
    
    private func updateAudioLevel(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sumSquares: Float = 0
        for i in 0..<count {
            sumSquares += samples[i] * samples[i]
        }
        let rms = sqrt(sumSquares / Float(count))
        levelLock.lock()
        levelEMA = levelEMA * 0.9 + rms * 0.1
        let currentLevel = levelEMA
        levelLock.unlock()
        onAudioLevelUpdate?(currentLevel)
    }
    
    /// Thread-safe getter for current audio level
    nonisolated var currentLevel: Float {
        levelLock.lock()
        let level = levelEMA
        levelLock.unlock()
        return level
    }
    
    /// Apply soft limiting to prevent hard clipping during Float->Int16 conversion.
    /// Uses attack/release smoothing for transparent peak control.
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
        
        var index = 0
        while index + frameSize <= pcmSamples.count {
            let slice = Array(pcmSamples[index..<index + frameSize])
            let data = slice.withUnsafeBufferPointer { Data(buffer: $0) }
            onPCMFrame?(data, "mic")
            index += frameSize
        }
        
        if index < pcmSamples.count {
            pcmRemainder = Array(pcmSamples[index..<pcmSamples.count])
        }
    }
    
    // MARK: - Metrics (AUD-002 Improvement)
    
    private func resetMetrics() {
        metricsLock.lock()
        framesProcessed = 0
        framesDropped = 0
        bufferUnderruns = 0
        lastProcessTime = 0
        metricsLock.unlock()
    }
    
    private func incrementFramesProcessed() {
        metricsLock.lock()
        framesProcessed += 1
        metricsLock.unlock()
    }
    
    private func incrementFramesDropped() {
        metricsLock.lock()
        framesDropped += 1
        metricsLock.unlock()
    }
    
    /// Get current metrics (thread-safe)
    func getMetrics() -> (processed: UInt64, dropped: UInt64, underruns: UInt64) {
        metricsLock.lock()
        let result = (framesProcessed, framesDropped, bufferUnderruns)
        metricsLock.unlock()
        return result
    }
}

enum MicCaptureError: Error {
    case permissionDenied
    case permissionRevoked
    case formatCreationFailed
    case converterCreationFailed
    case engineStartFailed(Error)
    case mediaServicesReset
    case audioUnitUnavailable
    case deviceDisconnected
    case preferredDeviceUnavailable(String)
    case unableToResolveAudioDeviceID(String)
    case deviceSelectionFailed(status: OSStatus, deviceID: String)
    
    var localizedDescription: String {
        switch self {
        case .permissionDenied:
            return "Microphone permission not granted"
        case .permissionRevoked:
            return "Microphone permission was revoked"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .mediaServicesReset:
            return "Media services were reset"
        case .audioUnitUnavailable:
            return "Unable to access microphone audio unit"
        case .deviceDisconnected:
            return "Microphone device was disconnected"
        case .preferredDeviceUnavailable(let deviceID):
            return "Selected microphone is unavailable (\(deviceID))"
        case .unableToResolveAudioDeviceID(let deviceID):
            return "Unable to resolve CoreAudio device for selected microphone (\(deviceID))"
        case .deviceSelectionFailed(let status, let deviceID):
            return "Failed to bind selected microphone (\(deviceID)); OSStatus=\(status)"
        }
    }
}
