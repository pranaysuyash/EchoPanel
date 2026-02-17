import Foundation
import AppKit
import OSLog

/// Monitors and manages system resource usage to prevent performance issues
@MainActor
final class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()

    // MARK: - Published State
    @Published private(set) var memoryUsage: UInt64 = 0
    @Published private(set) var isUnderPressure: Bool = false

    // MARK: - Resource Limits
    private let maxMemoryUsage: UInt64 = 2_000_000_000 // 2GB
    private let warningThreshold: Double = 0.7 // 70% of limits

    // MARK: - Monitoring
    private var monitoringTimer: Timer?
    private let monitorInterval: TimeInterval = 10.0 // Check every 10 seconds

    // MARK: - Callbacks
    var onPressureDetected: (() -> Void)?
    var onPressureResolved: (() -> Void)?

    private let logger = Logger(subsystem: "com.echopanel.app", category: "ResourceMonitor")

    private init() {
        startMonitoring()
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard monitoringTimer == nil else { return }

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateMetrics()
            }
        }

        logger.debug("Resource monitoring started")
    }

    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        logger.debug("Resource monitoring stopped")
    }

    // MARK: - Metrics Update

    private func updateMetrics() async {
        let memory = await getCurrentMemoryUsage()

        self.memoryUsage = memory

        let wasUnderPressure = isUnderPressure
        isUnderPressure = memory > (maxMemoryUsage)

        // Trigger callbacks on state changes
        if isUnderPressure && !wasUnderPressure {
            logger.warning("Resource pressure detected: Memory=\(self.formatBytes(memory))")
            self.onPressureDetected?()
        } else if !isUnderPressure && wasUnderPressure {
            logger.info("Resource pressure resolved")
            self.onPressureResolved?()
        }
    }

    // MARK: - Current Metrics

    private func getCurrentMemoryUsage() async -> UInt64 {
        var stats = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size)/4

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return UInt64(stats.resident_size)
        }

        return 0
    }

    // MARK: - Resource Limits

    func shouldThrottleCPU() -> Bool {
        // Simplified CPU throttling based on memory pressure
        // If we're under memory pressure, we should also throttle CPU
        return isUnderPressure
    }

    func shouldThrottleMemory() -> Bool {
        return memoryUsage > (UInt64(Double(maxMemoryUsage) * warningThreshold))
    }

    func canAllocateAdditionalMemory(_ requestedBytes: UInt64) -> Bool {
        return (memoryUsage + requestedBytes) < maxMemoryUsage
    }

    // MARK: - Utility

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Cleanup

    deinit {
        // Note: Can't call async stopMonitoring in deinit
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}