import Foundation
@preconcurrency import MLX
import os

// MARK: - App Phase

/// Mutually exclusive app execution phases.
/// DEC-030: Recording phase must complete before analysis starts;
/// analysis must complete before brain dump (never simultaneous).
public enum AppPhase: String, Sendable, CaseIterable {
    case idle       = "idle"
    case recording  = "recording"
    case analysis   = "analysis"
    case brainDump  = "brainDump"
    case exporting  = "exporting"
}

// MARK: - Phase Transition Result

public enum PhaseTransitionResult: Sendable {
    case success
    case rejected(reason: String)
}

// MARK: - Phase Scheduler

/// Enforces sequential, non-overlapping phase execution.
///
/// Valid transitions:
///   idle → recording → analysis → brainDump → idle
///   any  → idle        (abort/reset)
///   any  → exporting   (only from idle)
///
/// On high memory pressure (`memoryPressureLevel >= .critical`):
///   - Clears the MLX GPU cache automatically.
///   - Blocks transitions into memory-heavy phases (analysis, brainDump).
public actor PhaseScheduler {

    // MARK: - State

    public private(set) var currentPhase: AppPhase = .idle
    public private(set) var lastTransitionAt: Date = .distantPast

    private var memoryPressureLevel: DispatchSource.MemoryPressureEvent = .normal
    private var pressureSource: DispatchSourceMemoryPressure?

    private let logger = Logger(subsystem: "com.echopanel", category: "PhaseScheduler")

    // MARK: - Init / Deinit

    public init() {
        // Note: DispatchSource registration happens in setup() to avoid actor isolation issues.
    }

    /// Must be called after init (sets up memory pressure monitoring).
    public func setup() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak source] in
            guard let source else { return }
            let data = source.data
            Task { await self.handleMemoryPressure(data) }
        }
        source.resume()
        pressureSource = source
        logger.info("PhaseScheduler: memory pressure monitoring active")
    }

    // MARK: - Transitions

    /// Attempt to advance to `next`. Returns `.rejected` with reason if illegal.
    @discardableResult
    public func transition(to next: AppPhase) async -> PhaseTransitionResult {
        let current = currentPhase

        guard isValidTransition(from: current, to: next) else {
            let reason = "illegal transition \(current.rawValue) → \(next.rawValue)"
            logger.warning("PhaseScheduler: \(reason)")
            return .rejected(reason: reason)
        }

        if memoryPressureLevel == .critical {
            clearMLXCache()
            if next == .analysis || next == .brainDump {
                let reason = "blocked: memory pressure is critical"
                logger.warning("PhaseScheduler: \(reason) — cannot enter \(next.rawValue)")
                return .rejected(reason: reason)
            }
        }

        logger.info("PhaseScheduler: \(current.rawValue) → \(next.rawValue)")
        currentPhase = next
        lastTransitionAt = Date()
        return .success
    }

    /// Force reset to idle (e.g., after crash recovery).
    public func reset() {
        logger.warning("PhaseScheduler: force-reset to idle from \(self.currentPhase.rawValue)")
        currentPhase = .idle
        lastTransitionAt = Date()
        clearMLXCache()
    }

    // MARK: - Memory

    public var isRAM16GB: Bool {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return bytes >= 16 * 1024 * 1024 * 1024
    }

    public var isRAM24GBOrMore: Bool {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return bytes >= 24 * 1024 * 1024 * 1024
    }

    private func clearMLXCache() {
        logger.info("PhaseScheduler: clearing MLX GPU cache")
        Memory.clearCache()
    }

    // MARK: - Helpers

    private func isValidTransition(from current: AppPhase, to next: AppPhase) -> Bool {
        if next == .idle { return true }  // always allowed (abort/reset path)
        switch current {
        case .idle:       return next == .recording || next == .exporting
        case .recording:  return next == .analysis
        case .analysis:   return next == .brainDump
        case .brainDump:  return next == .idle
        case .exporting:  return next == .idle
        }
    }

    private func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
        memoryPressureLevel = event
        switch event {
        case .warning:
            logger.warning("PhaseScheduler: memory pressure WARNING")
        case .critical:
            logger.critical("PhaseScheduler: memory pressure CRITICAL — clearing MLX cache")
            clearMLXCache()
        default:
            break
        }
    }
}
