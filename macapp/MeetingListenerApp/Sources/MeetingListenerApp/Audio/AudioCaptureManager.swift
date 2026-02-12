import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class AudioCaptureManager: NSObject {
    var onPcmFrame: ((Data) -> Void)?
    var onAudioQualityUpdate: ((AudioQuality) -> Void)?
    var onPermissionRequired: (() -> Void)?

    private var stream: SCStream?

    func startCapture() {
        guard requestPermissionsIfNeeded() else {
            onPermissionRequired?()
            return
        }

        if #available(macOS 13.0, *) {
            startScreenCaptureKit()
        }
    }

    func stopCapture() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
    }

    private func requestPermissionsIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    @available(macOS 13.0, *)
    private func startScreenCaptureKit() {
        Task { @MainActor in
            // TODO: fetch SCShareableContent and configure SCStream for audio only.
            // TODO: attach SCStreamOutput to receive audio sample buffers.
            onAudioQualityUpdate?(.ok)
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // TODO: downmix to mono, resample to 16 kHz, convert to Int16 PCM.
        // Then send bytes via onPcmFrame.
        _ = buffer
    }
}
