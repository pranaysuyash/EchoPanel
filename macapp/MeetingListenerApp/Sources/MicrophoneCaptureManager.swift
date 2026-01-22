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
        
        // Update audio level
        updateAudioLevel(samples: samples, count: frameCount)
        
        // Emit PCM frames
        emitPCMFrames(samples: samples, count: frameCount)
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
    
    private func emitPCMFrames(samples: UnsafePointer<Float>, count: Int) {
        var pcmSamples: [Int16] = []
        pcmSamples.reserveCapacity(count)
        
        for i in 0..<count {
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
