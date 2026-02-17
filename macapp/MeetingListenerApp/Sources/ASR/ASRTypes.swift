import Foundation

// MARK: - Backend Mode

public enum BackendMode: String, CaseIterable, Identifiable {
    case autoSelect = "auto"
    case nativeMLX = "native"
    case pythonServer = "python"
    case dualMode = "dual"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .autoSelect: return "Auto-Select"
        case .nativeMLX: return "Native (Local)"
        case .pythonServer: return "Cloud (Python)"
        case .dualMode: return "Dual (Compare)"
        }
    }
    
    public var description: String {
        switch self {
        case .autoSelect:
            return "Automatically selects the best backend based on network, privacy needs, and features"
        case .nativeMLX:
            return "On-device transcription with MLX. Fast, private, works offline. Best for single-user."
        case .pythonServer:
            return "Cloud transcription with advanced NLP, diarization, and team features. Requires internet."
        case .dualMode:
            return "Run both backends simultaneously and compare results (developer mode)"
        }
    }
}

// MARK: - Backend Status

public enum BackendState: String {
    case unknown = "unknown"
    case initializing = "initializing"
    case ready = "ready"
    case busy = "busy"
    case error = "error"
    case unavailable = "unavailable"
    
    public var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .initializing: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .busy: return "waveform"
        case .error: return "exclamationmark.triangle.fill"
        case .unavailable: return "xmark.circle"
        }
    }
    
    public var color: String {
        switch self {
        case .unknown: return "gray"
        case .initializing: return "blue"
        case .ready: return "green"
        case .busy: return "orange"
        case .error: return "red"
        case .unavailable: return "gray"
        }
    }
}

public struct BackendStatus {
    public let backendName: String
    public var state: BackendState
    public var message: String?
    public var lastUpdated: Date
    public var capabilities: BackendCapabilities?
    public var performanceMetrics: PerformanceMetrics?
    
    public init(
        backendName: String,
        state: BackendState = .unknown,
        message: String? = nil,
        capabilities: BackendCapabilities? = nil
    ) {
        self.backendName = backendName
        self.state = state
        self.message = message
        self.lastUpdated = Date()
        self.capabilities = capabilities
        self.performanceMetrics = nil
    }
}

// MARK: - Capabilities

public struct BackendCapabilities {
    public let supportsStreaming: Bool
    public let supportsBatch: Bool
    public let supportsDiarization: Bool
    public let supportsOffline: Bool
    public let requiresNetwork: Bool
    public let supportedLanguages: [Language]
    public let maxAudioDuration: TimeInterval?
    public let estimatedRTF: Double?
    
    public init(
        supportsStreaming: Bool = true,
        supportsBatch: Bool = true,
        supportsDiarization: Bool = false,
        supportsOffline: Bool = true,
        requiresNetwork: Bool = false,
        supportedLanguages: [Language] = [.english],
        maxAudioDuration: TimeInterval? = nil,
        estimatedRTF: Double? = nil
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsBatch = supportsBatch
        self.supportsDiarization = supportsDiarization
        self.supportsOffline = supportsOffline
        self.requiresNetwork = requiresNetwork
        self.supportedLanguages = supportedLanguages
        self.maxAudioDuration = maxAudioDuration
        self.estimatedRTF = estimatedRTF
    }
    
    public static let nativeDefault = BackendCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        supportsDiarization: false,
        supportsOffline: true,
        requiresNetwork: false,
        supportedLanguages: Language.allCases,
        estimatedRTF: 0.08
    )
    
    public static let pythonDefault = BackendCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        supportsDiarization: true,
        supportsOffline: false,
        requiresNetwork: true,
        supportedLanguages: Language.allCases,
        estimatedRTF: 0.15
    )
}

// MARK: - Language

public enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case dutch = "nl"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        case .dutch: return "Dutch"
        }
    }
}

// MARK: - Transcription Types

public struct TranscriptionConfig {
    public let language: Language
    public let enableDiarization: Bool
    public let enablePunctuation: Bool
    public let enableTimestamps: Bool
    public let customVocabulary: [String]
    public let speakerCount: Int?
    
    public init(
        language: Language = .english,
        enableDiarization: Bool = false,
        enablePunctuation: Bool = true,
        enableTimestamps: Bool = true,
        customVocabulary: [String] = [],
        speakerCount: Int? = nil
    ) {
        self.language = language
        self.enableDiarization = enableDiarization
        self.enablePunctuation = enablePunctuation
        self.enableTimestamps = enableTimestamps
        self.customVocabulary = customVocabulary
        self.speakerCount = speakerCount
    }
}

public struct TranscriptionSegment: Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Double
    public let speakerId: String?
    public let isFinal: Bool
    
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double = 1.0,
        speakerId: String? = nil,
        isFinal: Bool = true
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerId = speakerId
        self.isFinal = isFinal
    }
}

public struct TranscriptionResult {
    public let segments: [TranscriptionSegment]
    public let fullText: String
    public let duration: TimeInterval
    public let processingTime: TimeInterval
    public let backendName: String
    public let language: Language
    public let confidence: Double
    
    public init(
        segments: [TranscriptionSegment],
        fullText: String? = nil,
        duration: TimeInterval = 0,
        processingTime: TimeInterval = 0,
        backendName: String = "",
        language: Language = .english,
        confidence: Double = 1.0
    ) {
        self.segments = segments
        self.fullText = fullText ?? segments.map { $0.text }.joined(separator: " ")
        self.duration = duration
        self.processingTime = processingTime
        self.backendName = backendName
        self.language = language
        self.confidence = confidence
    }
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    public var totalRequests: Int = 0
    public var totalAudioDuration: TimeInterval = 0
    public var totalProcessingTime: TimeInterval = 0
    public var averageRTF: Double = 0
    public var averageConfidence: Double = 0
    public var errorCount: Int = 0
    public var lastError: String?
    public var lastErrorTime: Date?
    
    public var realtimeFactor: Double {
        guard totalAudioDuration > 0 else { return 0 }
        return totalProcessingTime / totalAudioDuration
    }
    
    public mutating func recordSuccess(duration: TimeInterval, processingTime: TimeInterval, confidence: Double) {
        totalRequests += 1
        totalAudioDuration += duration
        totalProcessingTime += processingTime
        averageConfidence = (averageConfidence * Double(totalRequests - 1) + confidence) / Double(totalRequests)
        averageRTF = realtimeFactor
    }
    
    public mutating func recordError(_ error: String) {
        errorCount += 1
        lastError = error
        lastErrorTime = Date()
    }
}

// MARK: - Comparison Results

public struct BackendComparisonResult {
    public let nativeResult: TranscriptionResult
    public let pythonResult: TranscriptionResult
    public let nativeMetrics: PerformanceMetrics
    public let pythonMetrics: PerformanceMetrics
    public let speedup: Double
    public let wordErrorRate: Double
    public let accuracyMatch: Bool
    public let timestamp: Date
    
    public init(
        nativeResult: TranscriptionResult,
        pythonResult: TranscriptionResult,
        nativeMetrics: PerformanceMetrics,
        pythonMetrics: PerformanceMetrics,
        wordErrorRate: Double = 0,
        accuracyMatch: Bool = false
    ) {
        self.nativeResult = nativeResult
        self.pythonResult = pythonResult
        self.nativeMetrics = nativeMetrics
        self.pythonMetrics = pythonMetrics
        self.speedup = pythonMetrics.realtimeFactor / max(nativeMetrics.realtimeFactor, 0.001)
        self.wordErrorRate = wordErrorRate
        self.accuracyMatch = accuracyMatch
        self.timestamp = Date()
    }
}

// MARK: - Errors

public enum ASRError: Error, LocalizedError {
    case backendNotAvailable(backend: String)
    case transcriptionFailed(reason: String)
    case networkError(Error)
    case audioFormatError(String)
    case modelNotLoaded
    case streamingError(String)
    case subscriptionRequired(feature: String)
    case initializationFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .backendNotAvailable(let backend):
            return "Backend '\(backend)' is not available"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .audioFormatError(let details):
            return "Audio format error: \(details)"
        case .modelNotLoaded:
            return "ASR model not loaded"
        case .streamingError(let details):
            return "Streaming error: \(details)"
        case .subscriptionRequired(let feature):
            return "Subscription required for \(feature)"
        case .initializationFailed(let reason):
            return "Initialization failed: \(reason)"
        }
    }
}

// MARK: - Events

public enum TranscriptionEvent {
    case started
    case partial(text: String, confidence: Double)
    case final(segment: TranscriptionSegment)
    case completed(result: TranscriptionResult)
    case error(ASRError)
    case cancelled
}
