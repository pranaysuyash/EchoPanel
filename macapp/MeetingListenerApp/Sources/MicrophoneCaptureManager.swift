import AVFoundation
import Combine
import Foundation

/// Captures microphone audio using AVAudioEngine and emits PCM16 frames.
final class MicrophoneCaptureManager: NSObject, ObservableObject {
    var onPCMFrame: ((Data, String) -> Void)? // (frame, source="mic")
    var onAudioLevelUpdate: ((Float) -> Void)?
    var onError: ((Error) -> Void)?
    
    private let audioEngine = AVAudioEngine()
    private var isRunning = false
    private var pcmRemainder: [Int16] = []
    private let frameSize = 320 // 20ms at 16kHz
    private var levelEMA: Float = 0
    
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
    
    func startCapture() throws {
        guard !isRunning else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Target format: 16kHz mono PCM Float32
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw MicCaptureError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicCaptureError.converterCreationFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        NSLog("MicrophoneCaptureManager: Started capture")
    }
    
    func stopCapture() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        pcmRemainder.removeAll()
        NSLog("MicrophoneCaptureManager: Stopped capture")
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
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
        
        guard status != .error, let channelData = outputBuffer.floatChannelData else {
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
    }
    
    private func updateAudioLevel(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var sumSquares: Float = 0
        for i in 0..<count {
            sumSquares += samples[i] * samples[i]
        }
        let rms = sqrt(sumSquares / Float(count))
        levelEMA = levelEMA * 0.9 + rms * 0.1
        onAudioLevelUpdate?(levelEMA)
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
}

enum MicCaptureError: Error {
    case formatCreationFailed
    case converterCreationFailed
}
