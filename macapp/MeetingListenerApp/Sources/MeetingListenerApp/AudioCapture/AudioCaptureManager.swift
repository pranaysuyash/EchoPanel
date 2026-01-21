import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit

final class AudioCaptureManager: NSObject {
    private var stream: SCStream?
    private let sampleHandler = AudioSampleHandler()
    private var cancellables = Set<AnyCancellable>()

    func requestPermission(completion: @escaping (Bool) -> Void) {
        if CGPreflightScreenCaptureAccess() {
            completion(true)
            return
        }

        CGRequestScreenCaptureAccess { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
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
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: config, delegate: sampleHandler)
        self.stream = stream

        try stream.addStreamOutput(sampleHandler, type: .audio, sampleHandlerQueue: .global())
        try await stream.startCapture()
    }

    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            // TODO: Surface error to UI.
        }
        stream = nil
    }
}

final class AudioSampleHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        // TODO: Convert sampleBuffer to PCM16 16 kHz mono frames.
        // TODO: Compute RMS, clipping rate, silence ratio for audio quality indicator.
    }
}

enum CaptureError: Error {
    case unsupportedOS
    case noDisplay
}
