import Combine
import CoreMedia
import Foundation
import QuartzCore
import ScreenCaptureKit

final class AudioCaptureManager: NSObject {
    var onPCMFrame: ((Data) -> Void)?
    var onAudioQualityUpdate: ((AudioQuality) -> Void)?
    var onSampleCount: ((Int) -> Void)?

    private let debugEnabled = ProcessInfo.processInfo.arguments.contains("--debug")
    private var stream: SCStream?
    private let sampleHandler = AudioSampleHandler()
    private let screenHandler = ScreenSampleHandler()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var pcmRemainder: [Int16] = []
    private var rmsEMA: Float = 0
    private var silenceEMA: Float = 0
    private var clipEMA: Float = 0
    private var lastQualityUpdate: TimeInterval = 0
    private var lastDebugLog: TimeInterval = 0
    private var totalSamples: Int = 0

    override init() {
        super.init()
        sampleHandler.onAudioSampleBuffer = { [weak self] sampleBuffer in
            self?.processAudio(sampleBuffer: sampleBuffer)
        }
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

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: sampleHandler)
        self.stream = stream

        try stream.addStreamOutput(screenHandler, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try stream.addStreamOutput(sampleHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
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
        stream = nil
    }

    private func processAudio(sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let inputFormat = AVAudioFormat(streamDescription: asbd)
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: asbd.pointee.mChannelsPerFrame, mDataByteSize: 0, mData: nil)
        )

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return
        }

        guard let inputFormat,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: &audioBufferList) else {
            return
        }

        inputBuffer.frameLength = AVAudioFrameCount(numSamples)
        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        guard let converter else { return }

        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
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
            return
        }

        guard let channelData = outputBuffer.floatChannelData else { return }
        let samples = channelData[0]
        let frameCount = Int(outputBuffer.frameLength)
        totalSamples += frameCount
        if debugEnabled {
            let now = CACurrentMediaTime()
            if now - lastDebugLog > 2 {
                lastDebugLog = now
                NSLog("AudioCaptureManager: received %d samples", totalSamples)
            }
        }
        onSampleCount?(totalSamples)

        updateAudioQuality(samples: samples, count: frameCount)
        emitPCMFrames(samples: samples, count: frameCount)
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

        let frameSize = 320
        var index = 0
        while index + frameSize <= pcmSamples.count {
            let slice = Array(pcmSamples[index..<index + frameSize])
            let data = slice.withUnsafeBufferPointer { Data(buffer: $0) }
            onPCMFrame?(data)
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

        rmsEMA = rmsEMA * 0.9 + rms * 0.1
        clipEMA = clipEMA * 0.9 + clipRatio * 0.1
        silenceEMA = silenceEMA * 0.9 + silenceRatio * 0.1

        let now = CACurrentMediaTime()
        if now - lastQualityUpdate < 0.5 {
            return
        }
        lastQualityUpdate = now

        let quality: AudioQuality
        if clipEMA > 0.1 || silenceEMA > 0.8 {
            quality = .poor
        } else if rmsEMA < 0.03 || silenceEMA > 0.5 {
            quality = .ok
        } else {
            quality = .good
        }

        onAudioQualityUpdate?(quality)
    }
}

final class AudioSampleHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        onAudioSampleBuffer?(sampleBuffer)
    }
}

final class ScreenSampleHandler: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Intentionally ignored. This keeps the video queue alive without processing frames.
    }
}

enum CaptureError: Error {
    case unsupportedOS
    case noDisplay
}
