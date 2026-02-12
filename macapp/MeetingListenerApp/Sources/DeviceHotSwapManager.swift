import AVFoundation
import Foundation
import Combine
import SwiftUI

/// Manages USB audio device hot-swap for broadcast reliability.
/// macOS Implementation: Uses AVCaptureDevice notifications and engine monitoring.
@MainActor
final class DeviceHotSwapManager: ObservableObject {
    
    // MARK: - Published State
    
    /// Current device connection status
    @Published var deviceStatus: DeviceStatus = .unknown
    
    /// True if a hot-swap recovery is in progress
    @Published var isRecovering = false
    
    /// Last error message (if any)
    @Published var lastError: String?
    
    // MARK: - Types
    
    enum DeviceStatus: String {
        case unknown = "Unknown"
        case connected = "Connected"
        case disconnected = "Disconnected"
        case recovering = "Recovering"
        case failed = "Failed"
    }
    
    struct DeviceInfo {
        let id: String
        let name: String
        let manufacturer: String
        let isInput: Bool
        let sampleRate: Double
    }
    
    // MARK: - Private Properties
    
    private var deviceConnectedObserver: NSObjectProtocol?
    private var deviceDisconnectedObserver: NSObjectProtocol?
    private var recoveryTask: Task<Void, Never>?
    private var lastDeviceID: String?
    private var checkTimer: Timer?
    private var audioEngine: AVAudioEngine?
    
    private let recoveryDelay: TimeInterval
    private let retryDelay: TimeInterval
    private let maxRecoveryAttempts: Int
    private let restartCaptureTimeout: TimeInterval
    
    var onDeviceDisconnected: (() -> Void)?
    var onDeviceReconnected: (() -> Void)?
    var onShouldRestartCapture: (@Sendable () async throws -> Void)?
    
    // MARK: - Initialization
    
    init(
        recoveryDelay: TimeInterval = 1.0,
        retryDelay: TimeInterval = 0.5,
        maxRecoveryAttempts: Int = 3,
        restartCaptureTimeout: TimeInterval = 5.0
    ) {
        self.recoveryDelay = max(0, recoveryDelay)
        self.retryDelay = max(0, retryDelay)
        self.maxRecoveryAttempts = max(1, maxRecoveryAttempts)
        self.restartCaptureTimeout = max(0.1, restartCaptureTimeout)
        // macOS uses different APIs than iOS for device monitoring
        NSLog("DeviceHotSwapManager: Initialized (macOS)")
    }
    
    nonisolated deinit {
        // Cleanup handled by stopMonitoring() when app closes
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        setupDeviceMonitoring()
        startPeriodicChecks()
        NSLog("DeviceHotSwapManager: Started monitoring")
    }
    
    func stopMonitoring() {
        removeDeviceObservers()
        checkTimer?.invalidate()
        checkTimer = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        isRecovering = false
        NSLog("DeviceHotSwapManager: Stopped monitoring")
    }
    
    func registerCurrentDevice() {
        // Get current default input device
        if let device = AVCaptureDevice.default(for: .audio) {
            lastDeviceID = device.uniqueID
            deviceStatus = .connected
            NSLog("DeviceHotSwapManager: Registered device \(device.localizedName)")
        }
    }
    
    func triggerManualRecovery() {
        guard !isRecovering else { return }
        NSLog("DeviceHotSwapManager: Manual recovery triggered")
        attemptRecovery()
    }
    
    func availableInputDevices() -> [DeviceInfo] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        
        return discoverySession.devices.map { device in
            DeviceInfo(
                id: device.uniqueID,
                name: device.localizedName,
                manufacturer: device.manufacturer,
                isInput: true,
                sampleRate: 48000 // Default sample rate for display
            )
        }
    }
    
    /// Monitor an audio engine for failures (macOS approach)
    func monitorAudioEngine(_ engine: AVAudioEngine) {
        self.audioEngine = engine
        // In a full implementation, we'd observe engineConfigurationChangeNotification
    }
    
    // MARK: - Private Methods
    
    private func setupDeviceMonitoring() {
        guard deviceConnectedObserver == nil && deviceDisconnectedObserver == nil else { return }

        // Monitor for device connection changes
        deviceConnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleDeviceConnected(notification)
            }
        }
        
        // Also monitor for disconnections
        deviceDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleDeviceDisconnected(notification)
            }
        }
    }
    
    private func handleDeviceConnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.audio) else { return }
        
        NSLog("DeviceHotSwapManager: Audio device connected - \(device.localizedName)")
        
        // If we were disconnected, attempt recovery
        if deviceStatus == .disconnected || deviceStatus == .failed {
            attemptRecovery()
        }
    }
    
    private func handleDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.audio) else { return }
        
        // Check if this was our active device
        if device.uniqueID == lastDeviceID {
            NSLog("DeviceHotSwapManager: Active device disconnected - \(device.localizedName)")
            deviceStatus = .disconnected
            lastDeviceID = nil
            onDeviceDisconnected?()
        }
    }
    
    private func startPeriodicChecks() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.verifyDeviceConnection()
            }
        }
    }
    
    private func verifyDeviceConnection() {
        let hasDefaultDevice = AVCaptureDevice.default(for: .audio) != nil
        
        switch deviceStatus {
        case .connected:
            if !hasDefaultDevice && lastDeviceID != nil {
                NSLog("DeviceHotSwapManager: Device unexpectedly unavailable")
                deviceStatus = .disconnected
                onDeviceDisconnected?()
            }
            
        case .disconnected:
            if hasDefaultDevice {
                NSLog("DeviceHotSwapManager: Device became available")
                attemptRecovery()
            }
            
        default:
            break
        }
    }
    
    private func attemptRecovery() {
        guard !isRecovering else { return }
        
        isRecovering = true
        deviceStatus = .recovering
        lastError = nil
        
        recoveryTask = Task { [weak self] in
            guard let self = self else { return }
            
            try? await Task.sleep(nanoseconds: UInt64(self.recoveryDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            var success = false
            var attempts = 0
            var lastRecoveryError: Error?
            
            while !success && attempts < self.maxRecoveryAttempts && !Task.isCancelled {
                attempts += 1
                NSLog("DeviceHotSwapManager: Recovery attempt \(attempts)/\(self.maxRecoveryAttempts)")
                
                do {
                    try await self.restartCaptureWithTimeout()
                    success = true
                } catch {
                    lastRecoveryError = error
                    NSLog("DeviceHotSwapManager: Recovery attempt failed - \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                    if attempts < self.maxRecoveryAttempts {
                        try? await Task.sleep(nanoseconds: self.durationToNanoseconds(self.retryDelay))
                    }
                }
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if success {
                    self.deviceStatus = .connected
                    self.registerCurrentDevice()
                    self.onDeviceReconnected?()
                    StructuredLogger.shared.info("Device hot-swap recovery successful", metadata: ["attempts": attempts])
                } else {
                    self.deviceStatus = .failed
                    StructuredLogger.shared.error("Device hot-swap recovery failed", metadata: [
                        "max_attempts": self.maxRecoveryAttempts,
                        "last_error": self.lastError ?? "unknown",
                        "error_type": String(describing: type(of: lastRecoveryError ?? RecoveryError.restartCallbackMissing))
                    ])
                }
                self.isRecovering = false
            }
        }
    }

    private func restartCaptureWithTimeout() async throws {
        guard let restartCapture = onShouldRestartCapture else {
            throw RecoveryError.restartCallbackMissing
        }

        let restartTask = Task.detached {
            try await restartCapture()
        }
        let timeoutSeconds = restartCaptureTimeout
        let timeoutNanoseconds = durationToNanoseconds(timeoutSeconds)
        let timeoutTask = Task.detached {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw RecoveryError.restartTimedOut(seconds: timeoutSeconds)
        }

        defer { timeoutTask.cancel() }

        // Whichever finishes first (restart completion/failure or timeout) wins.
        // Cancellation keeps the loser from leaking into the next retry.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                defer { timeoutTask.cancel() }
                _ = try await restartTask.value
            }
            group.addTask {
                defer { restartTask.cancel() }
                _ = try await timeoutTask.value
            }
            defer { group.cancelAll() }
            _ = try await group.next()
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

    private func durationToNanoseconds(_ value: TimeInterval) -> UInt64 {
        UInt64(max(0, value) * 1_000_000_000)
    }

    var activeObserverCountForTesting: Int {
        var count = 0
        if deviceConnectedObserver != nil { count += 1 }
        if deviceDisconnectedObserver != nil { count += 1 }
        return count
    }
    
    enum RecoveryError: LocalizedError {
        case restartCallbackMissing
        case restartTimedOut(seconds: TimeInterval)
        
        var errorDescription: String? {
            switch self {
            case .restartCallbackMissing:
                return "Restart callback is not configured."
            case .restartTimedOut(let seconds):
                return "Restart callback timed out after \(String(format: "%.1f", seconds))s."
            }
        }
    }
}

// MARK: - SwiftUI Views

struct DeviceHotSwapStatusView: View {
    @StateObject private var manager = DeviceHotSwapManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: manager.deviceStatus))
                .frame(width: 8, height: 8)
            
            Text("Device: \(manager.deviceStatus.rawValue)")
                .font(.caption)
            
            if manager.isRecovering {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            }
            
            if manager.deviceStatus == .failed {
                Button("Retry") {
                    manager.triggerManualRecovery()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(4)
    }
    
    private func statusColor(for status: DeviceHotSwapManager.DeviceStatus) -> Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .red
        case .recovering: return .orange
        case .failed: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Shared Instance

extension DeviceHotSwapManager {
    static let shared = DeviceHotSwapManager()
}

// MARK: - Integration Extension

extension BroadcastFeatureManager {
    /// Enable hot-swap monitoring
    var useDeviceHotSwap: Bool {
        get { UserDefaults.standard.bool(forKey: "broadcast_useDeviceHotSwap") }
        set { UserDefaults.standard.set(newValue, forKey: "broadcast_useDeviceHotSwap") }
    }
    
    /// Access hot-swap manager
    var hotSwapManager: DeviceHotSwapManager {
        DeviceHotSwapManager.shared
    }
}
