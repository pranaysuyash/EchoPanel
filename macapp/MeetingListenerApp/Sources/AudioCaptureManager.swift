import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit

final class AudioCaptureManager: NSObject {
    var onPCMFrame: ((Data) -> Void)?
    var onAudioQualityUpdate: ((AudioQuality) -> Void)?

    private var stream: SCStream?
    private let sampleHandler = AudioSampleHandler()

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

        try stream.addStreamOutput(sampleHandler, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await stream.startCapture()
        onAudioQualityUpdate?(.ok)
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
        // TODO(v0.1): Convert ScreenCaptureKit CMSampleBuffer audio to PCM16 16 kHz mono frames.
        // Steps:
        // 1) Downmix to mono if needed.
        // 2) Resample to 16 kHz.
        // 3) Convert float/int format to Int16 little-endian.
        // 4) Chunk into 20 ms frames (320 samples = 640 bytes) and call onPCMFrame.
        _ = sampleBuffer
    }
}

final class AudioSampleHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        onAudioSampleBuffer?(sampleBuffer)
    }
}

enum CaptureError: Error {
    case unsupportedOS
    case noDisplay
}
