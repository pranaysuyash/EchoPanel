import Foundation
import OSLog
import SwiftUI

/// Performance monitoring utility for tracking and optimizing app performance
@MainActor
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private let logger = Logger(subsystem: "com.echopanel.app", category: "Performance")

    // Performance thresholds
    private let warningThreshold: TimeInterval = 0.1 // 100ms
    private let criticalThreshold: TimeInterval = 0.5 // 500ms

    // Performance tracking
    private var measurements: [String: [TimeInterval]] = [:]
    private let maxMeasurementsPerOperation = 100

    private init() {}

    // MARK: - Performance Measurement

    /// Measure the execution time of an operation
    func measure<T>(_ label: String, operation: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let duration = CFAbsoluteTimeGetCurrent() - start

        recordMeasurement(label: label, duration: duration)
        logPerformance(label: label, duration: duration)

        return result
    }

    /// Measure async operations
    func measure<T>(_ label: String, operation: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let duration = CFAbsoluteTimeGetCurrent() - start

        recordMeasurement(label: label, duration: duration)
        logPerformance(label: label, duration: duration)

        return result
    }

    // MARK: - Performance Tracking

    private func recordMeasurement(label: String, duration: TimeInterval) {
        if measurements[label] == nil {
            measurements[label] = []
        }

        measurements[label]?.append(duration)

        // Keep only recent measurements
        if let count = measurements[label]?.count, count > maxMeasurementsPerOperation {
            measurements[label]?.removeFirst()
        }
    }

    private func logPerformance(label: String, duration: TimeInterval) {
        if duration > criticalThreshold {
            logger.error("Performance CRITICAL: \(label) took \(String(format: "%.1f", duration * 1000))ms")
        } else if duration > warningThreshold {
            logger.warning("Performance WARNING: \(label) took \(String(format: "%.1f", duration * 1000))ms")
        } else {
            logger.debug("Performance OK: \(label) took \(String(format: "%.1f", duration * 1000))ms")
        }
    }

    // MARK: - Performance Statistics

    /// Get statistics for a specific operation
    func getStats(for label: String) -> PerformanceStats? {
        guard let durations = measurements[label], !durations.isEmpty else {
            return nil
        }

        let sorted = durations.sorted()
        let count = durations.count
        let sum = durations.reduce(0, +)

        return PerformanceStats(
            label: label,
            count: count,
            average: sum / Double(count),
            median: sorted[count / 2],
            min: sorted.first!,
            max: sorted.last!,
            percentile95: sorted[Int(Double(count) * 0.95)]
        )
    }

    /// Get all available statistics
    func getAllStats() -> [PerformanceStats] {
        return measurements.keys.compactMap { getStats(for: $0) }
            .sorted { $0.average < $1.average }
    }

    // MARK: - Performance Health Check

    /// Check if overall app performance is healthy
    func performHealthCheck() -> PerformanceHealth {
        let stats = getAllStats()

        var criticalCount = 0
        var warningCount = 0
        var healthyCount = 0

        for stat in stats {
            if stat.percentile95 > criticalThreshold {
                criticalCount += 1
            } else if stat.percentile95 > warningThreshold {
                warningCount += 1
            } else {
                healthyCount += 1
            }
        }

        return PerformanceHealth(
            status: criticalCount > 0 ? .critical : warningCount > 0 ? .warning : .healthy,
            criticalOperations: criticalCount,
            warningOperations: warningCount,
            healthyOperations: healthyCount
        )
    }

    // MARK: - Reset

    /// Reset all performance measurements
    func reset() {
        measurements.removeAll()
    }

    /// Reset measurements for a specific operation
    func reset(label: String) {
        measurements[label] = nil
    }
}

// MARK: - Supporting Types

struct PerformanceStats {
    let label: String
    let count: Int
    let average: TimeInterval
    let median: TimeInterval
    let min: TimeInterval
    let max: TimeInterval
    let percentile95: TimeInterval

    var averageMs: Double { average * 1000 }
    var medianMs: Double { median * 1000 }
    var maxMs: Double { max * 1000 }
    var percentile95Ms: Double { percentile95 * 1000 }
}

struct PerformanceHealth {
    enum Status {
        case healthy, warning, critical
    }

    let status: Status
    let criticalOperations: Int
    let warningOperations: Int
    let healthyOperations: Int

    var totalOperations: Int { criticalOperations + warningOperations + healthyOperations }

    var statusMessage: String {
        switch status {
        case .healthy:
            return "All operations performing well"
        case .warning:
            return "\(warningOperations) operations need attention"
        case .critical:
            return "\(criticalOperations) operations require immediate attention"
        }
    }
}

// MARK: - Convenience Extensions

extension View {
    /// Measure and log performance of view rendering
    func measurePerformance(_ label: String) -> some View {
        self.onAppear {
            let start = CFAbsoluteTimeGetCurrent()

            // Defer until next run loop
            DispatchQueue.main.async {
                let duration = CFAbsoluteTimeGetCurrent() - start
                let logger = Logger(subsystem: "com.echopanel.app", category: "ViewPerformance")

                if duration > 0.1 {
                    logger.warning("View render SLOW: \(label) took \(String(format: "%.1f", duration * 1000))ms")
                } else {
                    logger.debug("View render OK: \(label) took \(String(format: "%.1f", duration * 1000))ms")
                }
            }
        }
    }
}