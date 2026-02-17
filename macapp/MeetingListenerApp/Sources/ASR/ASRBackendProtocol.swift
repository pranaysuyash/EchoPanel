import Foundation

// MARK: - ASR Backend Protocol

public protocol ASRBackend: Actor {
    /// Unique name for this backend
    nonisolated var name: String { get }
    
    /// Whether the backend is currently available
    nonisolated var isAvailable: Bool { get }
    
    /// Current status of the backend
    var status: BackendStatus { get }
    
    /// Backend capabilities
    nonisolated var capabilities: BackendCapabilities { get }
    
    /// Initialize the backend (load models, connect, etc.)
    func initialize() async throws
    
    /// Transcribe audio data
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> TranscriptionResult
    
    /// Start streaming transcription
    func startStreaming(config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error>
    
    /// Stop streaming
    func stopStreaming() async
    
    /// Get health/status metrics
    func health() async -> BackendStatus
    
    /// Unload/release resources
    func unload() async
}

// MARK: - Backend Selection Context

public struct BackendSelectionContext {
    public let isOffline: Bool
    public let networkQuality: NetworkQuality
    public let requiresDiarization: Bool
    public let requiresAdvancedNLP: Bool
    public let privacyRequirement: PrivacyRequirement
    public let audioDuration: TimeInterval?
    public let language: Language
    
    public init(
        isOffline: Bool = false,
        networkQuality: NetworkQuality = .good,
        requiresDiarization: Bool = false,
        requiresAdvancedNLP: Bool = false,
        privacyRequirement: PrivacyRequirement = .standard,
        audioDuration: TimeInterval? = nil,
        language: Language = .english
    ) {
        self.isOffline = isOffline
        self.networkQuality = networkQuality
        self.requiresDiarization = requiresDiarization
        self.requiresAdvancedNLP = requiresAdvancedNLP
        self.privacyRequirement = privacyRequirement
        self.audioDuration = audioDuration
        self.language = language
    }
    
    public static let `default` = BackendSelectionContext()
}

public enum NetworkQuality {
    case excellent  // WiFi, strong signal
    case good       // WiFi, normal signal
    case poor       // Cellular, weak signal
    case none       // No connectivity
    
    public var isSuitableForCloud: Bool {
        switch self {
        case .excellent, .good: return true
        case .poor, .none: return false
        }
    }
}

public enum PrivacyRequirement {
    case strict     // Must be on-device (sensitive data)
    case standard   // Prefer on-device but cloud OK
    case none       // No restrictions
    
    public var prefersLocal: Bool {
        switch self {
        case .strict: return true
        case .standard: return true
        case .none: return false
        }
    }
}

// MARK: - Backend Selection Strategy

public protocol BackendSelectionStrategy {
    func selectBackend(
        native: ASRBackend,
        python: ASRBackend,
        context: BackendSelectionContext
    ) async -> ASRBackend
}

public struct SmartBackendSelection: BackendSelectionStrategy {
    
    public init() {}
    
    public func selectBackend(
        native: ASRBackend,
        python: ASRBackend,
        context: BackendSelectionContext
    ) async -> ASRBackend {
        // Priority 1: Offline mode - must use native
        if context.isOffline {
            return native
        }
        
        // Priority 2: Privacy requirement - use native
        if context.privacyRequirement == .strict {
            return native
        }
        
        // Priority 3: Diarization required - use Python
        if context.requiresDiarization {
            let pythonAvailable = await python.isAvailable
            if pythonAvailable {
                return python
            }
            // Fall back to native if Python unavailable
            return native
        }
        
        // Priority 4: Advanced NLP required - use Python
        if context.requiresAdvancedNLP {
            let pythonAvailable = await python.isAvailable
            if pythonAvailable {
                return python
            }
            return native
        }
        
        // Priority 5: Poor network - use native
        if !context.networkQuality.isSuitableForCloud {
            return native
        }
        
        // Priority 6: Default to native (privacy-first)
        return native
    }
}

// MARK: - Subscription Tier (Dev mode bypasses)

public enum SubscriptionTier: String, CaseIterable {
    case free = "free"
    case pro = "pro"
    case proCloud = "pro_cloud"
    case enterprise = "enterprise"
    
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .proCloud: return "Pro + Cloud"
        case .enterprise: return "Enterprise"
        }
    }
    
    /// Features available at each tier
    public func canUseBackend(_ mode: BackendMode) -> Bool {
        // In dev mode, all features are available regardless of tier
        if FeatureFlagManager.shared.isDevMode {
            return true
        }
        
        switch self {
        case .free:
            return mode == .autoSelect
        case .pro:
            return mode == .autoSelect || mode == .nativeMLX
        case .proCloud, .enterprise:
            return true
        }
    }
    
    public func canUseDiarization() -> Bool {
        if FeatureFlagManager.shared.isDevMode { return true }
        return self == .proCloud || self == .enterprise
    }
    
    public func canUseDualMode() -> Bool {
        if FeatureFlagManager.shared.isDevMode { return true }
        return self == .enterprise
    }
}
