import Foundation
import Combine

// MARK: - Feature Flags

/// Central manager for feature flags - enables gradual rollout and dev testing
public final class FeatureFlagManager: ObservableObject {
    public static let shared = FeatureFlagManager()
    
    // MARK: - Published Flags
    
    /// Master switch for hybrid backend system
    @Published public var enableHybridBackend: Bool = true
    
    /// Enable native MLX backend
    @Published public var enableNativeBackend: Bool = true
    
    /// Enable Python backend
    @Published public var enablePythonBackend: Bool = true
    
    /// Show backend selection UI in settings
    @Published public var enableBackendSelectionUI: Bool = true
    
    /// Enable dual mode for A/B testing (dev only)
    @Published public var enableDualMode: Bool = false
    
    /// Percentage of users who get native backend (0-100)
    @Published public var nativeBackendRolloutPercentage: Double = 100.0
    
    /// Force specific backend mode (for testing)
    @Published public var forcedBackendMode: BackendMode?
    
    /// Dev mode bypasses all subscription checks
    @Published public var isDevMode: Bool = true  // Default ON for local testing
    
    /// Enable detailed logging
    @Published public var enableVerboseLogging: Bool = true
    
    /// Enable backend comparison metrics
    @Published public var enableComparisonMetrics: Bool = true
    
    // MARK: - User Defaults Keys
    
    private enum Keys {
        static let enableHybridBackend = "feature_enableHybridBackend"
        static let enableNativeBackend = "feature_enableNativeBackend"
        static let enablePythonBackend = "feature_enablePythonBackend"
        static let enableBackendSelectionUI = "feature_enableBackendSelectionUI"
        static let enableDualMode = "feature_enableDualMode"
        static let nativeBackendRolloutPercentage = "feature_nativeBackendRolloutPercentage"
        static let forcedBackendMode = "feature_forcedBackendMode"
        static let isDevMode = "feature_isDevMode"
        static let enableVerboseLogging = "feature_enableVerboseLogging"
        static let enableComparisonMetrics = "feature_enableComparisonMetrics"
    }
    
    // MARK: - Initialization
    
    private init() {
        loadFromUserDefaults()
    }
    
    // MARK: - Persistence
    
    private func loadFromUserDefaults() {
        let defaults = UserDefaults.standard
        
        enableHybridBackend = defaults.object(forKey: Keys.enableHybridBackend) as? Bool ?? true
        enableNativeBackend = defaults.object(forKey: Keys.enableNativeBackend) as? Bool ?? true
        enablePythonBackend = defaults.object(forKey: Keys.enablePythonBackend) as? Bool ?? true
        enableBackendSelectionUI = defaults.object(forKey: Keys.enableBackendSelectionUI) as? Bool ?? true
        enableDualMode = defaults.object(forKey: Keys.enableDualMode) as? Bool ?? false
        nativeBackendRolloutPercentage = defaults.object(forKey: Keys.nativeBackendRolloutPercentage) as? Double ?? 100.0
        isDevMode = defaults.object(forKey: Keys.isDevMode) as? Bool ?? true  // Default true for testing
        enableVerboseLogging = defaults.object(forKey: Keys.enableVerboseLogging) as? Bool ?? true
        enableComparisonMetrics = defaults.object(forKey: Keys.enableComparisonMetrics) as? Bool ?? true
        
        if let modeString = defaults.string(forKey: Keys.forcedBackendMode),
           let mode = BackendMode(rawValue: modeString) {
            forcedBackendMode = mode
        }
    }
    
    public func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        
        defaults.set(enableHybridBackend, forKey: Keys.enableHybridBackend)
        defaults.set(enableNativeBackend, forKey: Keys.enableNativeBackend)
        defaults.set(enablePythonBackend, forKey: Keys.enablePythonBackend)
        defaults.set(enableBackendSelectionUI, forKey: Keys.enableBackendSelectionUI)
        defaults.set(enableDualMode, forKey: Keys.enableDualMode)
        defaults.set(nativeBackendRolloutPercentage, forKey: Keys.nativeBackendRolloutPercentage)
        defaults.set(isDevMode, forKey: Keys.isDevMode)
        defaults.set(enableVerboseLogging, forKey: Keys.enableVerboseLogging)
        defaults.set(enableComparisonMetrics, forKey: Keys.enableComparisonMetrics)
        
        if let mode = forcedBackendMode {
            defaults.set(mode.rawValue, forKey: Keys.forcedBackendMode)
        } else {
            defaults.removeObject(forKey: Keys.forcedBackendMode)
        }
    }
    
    // MARK: - Helpers
    
    /// Check if native backend should be enabled for this user
    public func shouldEnableNativeBackend() -> Bool {
        // Dev mode always enabled
        if isDevMode { return true }
        
        // Check master switch
        guard enableHybridBackend && enableNativeBackend else { return false }
        
        // Check rollout percentage
        let userPercentage = Double.random(in: 0...100)
        return userPercentage <= nativeBackendRolloutPercentage
    }
    
    /// Check if Python backend should be enabled
    public func shouldEnablePythonBackend() -> Bool {
        if isDevMode { return true }
        return enableHybridBackend && enablePythonBackend
    }
    
    /// Check if dual mode should be available
    public func shouldEnableDualMode() -> Bool {
        if isDevMode { return true }
        return enableDualMode
    }
    
    /// Get effective backend mode (respecting forced mode)
    public func effectiveBackendMode(_ requested: BackendMode) -> BackendMode {
        if let forced = forcedBackendMode {
            return forced
        }
        return requested
    }
    
    /// Reset all flags to defaults (for testing)
    public func resetToDefaults() {
        enableHybridBackend = true
        enableNativeBackend = true
        enablePythonBackend = true
        enableBackendSelectionUI = true
        enableDualMode = false
        nativeBackendRolloutPercentage = 100.0
        forcedBackendMode = nil
        isDevMode = true
        enableVerboseLogging = true
        enableComparisonMetrics = true
        saveToUserDefaults()
    }
    
    /// Enable all features (for dev testing)
    public func enableAllForDev() {
        enableHybridBackend = true
        enableNativeBackend = true
        enablePythonBackend = true
        enableBackendSelectionUI = true
        enableDualMode = true
        nativeBackendRolloutPercentage = 100.0
        forcedBackendMode = nil
        isDevMode = true
        enableVerboseLogging = true
        enableComparisonMetrics = true
        saveToUserDefaults()
    }
}

// MARK: - Feature Flag Debug View Model

#if DEBUG
public final class FeatureFlagDebugViewModel: ObservableObject {
    @Published public var flags: FeatureFlagManager
    
    public init(flags: FeatureFlagManager = .shared) {
        self.flags = flags
    }
    
    public var allFlags: [(name: String, value: String)] {
        [
            ("Hybrid Backend", String(flags.enableHybridBackend)),
            ("Native Backend", String(flags.enableNativeBackend)),
            ("Python Backend", String(flags.enablePythonBackend)),
            ("Backend Selection UI", String(flags.enableBackendSelectionUI)),
            ("Dual Mode", String(flags.enableDualMode)),
            ("Rollout %", String(format: "%.0f%%", flags.nativeBackendRolloutPercentage)),
            ("Forced Mode", flags.forcedBackendMode?.displayName ?? "None"),
            ("Dev Mode", String(flags.isDevMode)),
            ("Verbose Logging", String(flags.enableVerboseLogging)),
            ("Comparison Metrics", String(flags.enableComparisonMetrics)),
        ]
    }
    
    public func reset() {
        flags.resetToDefaults()
    }
    
    public func enableAll() {
        flags.enableAllForDev()
    }
}
#endif
