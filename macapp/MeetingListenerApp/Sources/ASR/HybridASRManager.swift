import Foundation
import Combine

// MARK: - Hybrid ASR Manager

/// Main orchestrator for hybrid ASR with smart backend selection
@MainActor
public final class HybridASRManager: ObservableObject, Sendable {
    
    // MARK: - Published State
    
    /// Currently selected backend mode
    @Published public var selectedMode: BackendMode = .autoSelect {
        didSet {
            if selectedMode != oldValue {
                Task {
                    await handleModeChange(from: oldValue, to: selectedMode)
                }
            }
        }
    }
    
    /// Currently active backend (for auto-select mode)
    @Published public private(set) var activeBackend: ASRBackend?
    
    /// Status of each backend
    @Published public private(set) var backendStatus: [String: BackendStatus] = [: ]
    
    /// Whether transcription is in progress
    @Published public private(set) var isTranscribing: Bool = false
    
    /// Current transcription result
    @Published public private(set) var currentResult: TranscriptionResult?
    
    /// Current streaming text
    @Published public private(set) var streamingText: String = ""
    
    /// Last comparison result (for dual mode)
    @Published public private(set) var lastComparison: BackendComparisonResult?
    
    /// Error message
    @Published public private(set) var errorMessage: String?
    
    // MARK: - Backends
    
    public let nativeBackend: ASRBackend
    public let pythonBackend: ASRBackend
    
    // MARK: - Configuration
    
    public var selectionStrategy: BackendSelectionStrategy = SmartBackendSelection()
    public var subscriptionTier: SubscriptionTier = .free
    
    // MARK: - Private State
    
    private var streamingTask: Task<Void, Never>?
    private var comparisonBuffer: [(native: TranscriptionResult?, python: TranscriptionResult?)] = []
    
    // MARK: - Initialization
    
    public init(
        nativeBackend: ASRBackend,
        pythonBackend: ASRBackend,
        subscriptionTier: SubscriptionTier = .free
    ) {
        self.nativeBackend = nativeBackend
        self.pythonBackend = pythonBackend
        self.subscriptionTier = subscriptionTier
        
        // Check feature flags
        if !FeatureFlagManager.shared.enableHybridBackend {
            print("⚠️ Hybrid backend disabled by feature flag")
        }
        
        // Load saved mode preference
        if let savedMode = UserDefaults.standard.string(forKey: "hybrid_asr_mode"),
           let mode = BackendMode(rawValue: savedMode) {
            // Only restore if allowed by subscription (or dev mode)
            if subscriptionTier.canUseBackend(mode) || FeatureFlagManager.shared.isDevMode {
                self.selectedMode = mode
            }
        }
    }
    
    // MARK: - Lifecycle
    
    public func initialize() async {
        // Initialize both backends
        await updateBackendStatus(nativeBackend, state: .initializing)
        await updateBackendStatus(pythonBackend, state: .initializing)
        
        do {
            try await nativeBackend.initialize()
            await updateBackendStatus(nativeBackend, state: .ready)
        } catch {
            await updateBackendStatus(nativeBackend, state: .error, message: error.localizedDescription)
        }
        
        do {
            try await pythonBackend.initialize()
            await updateBackendStatus(pythonBackend, state: .ready)
        } catch {
            await updateBackendStatus(pythonBackend, state: .unavailable, message: error.localizedDescription)
        }
        
        // Set initial active backend for auto mode
        if selectedMode == .autoSelect {
            await selectBestBackend()
        }
    }
    
    public func unload() async {
        streamingTask?.cancel()
        streamingTask = nil
        
        await nativeBackend.unload()
        await pythonBackend.unload()
        
        await MainActor.run {
            activeBackend = nil
            backendStatus.removeAll()
        }
    }
    
    // MARK: - Backend Selection
    
    /// Get the appropriate backend for the current mode
    public func currentBackend() async -> ASRBackend {
        let mode = FeatureFlagManager.shared.effectiveBackendMode(selectedMode)
        
        switch mode {
        case .autoSelect:
            return await selectBestBackend()
        case .nativeMLX:
            return nativeBackend
        case .pythonServer:
            return pythonBackend
        case .dualMode:
            // In dual mode, use native as primary but both will run
            return nativeBackend
        }
    }
    
    /// Smart backend selection based on context
    public func selectBestBackend(context: BackendSelectionContext? = nil) async -> ASRBackend {
        let ctx = context ?? BackendSelectionContext.default
        
        let backend = await selectionStrategy.selectBackend(
            native: nativeBackend,
            python: pythonBackend,
            context: ctx
        )
        
        await MainActor.run {
            activeBackend = backend
        }
        
        return backend
    }
    
    /// Check if a backend mode is available
    public func isModeAvailable(_ mode: BackendMode) -> Bool {
        // Dev mode bypasses all checks
        if FeatureFlagManager.shared.isDevMode {
            return true
        }
        
        // Check feature flags
        switch mode {
        case .autoSelect:
            return FeatureFlagManager.shared.enableHybridBackend
        case .nativeMLX:
            return FeatureFlagManager.shared.enableNativeBackend
        case .pythonServer:
            return FeatureFlagManager.shared.enablePythonBackend
        case .dualMode:
            return FeatureFlagManager.shared.shouldEnableDualMode()
        }
    }
    
    /// Check if mode is allowed by subscription
    public func isModeAllowed(_ mode: BackendMode) -> Bool {
        return subscriptionTier.canUseBackend(mode) || FeatureFlagManager.shared.isDevMode
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio with automatic backend selection and fallback
    public func transcribe(
        audio: Data,
        config: TranscriptionConfig = TranscriptionConfig()
    ) async throws -> TranscriptionResult {
        guard !isTranscribing else {
            throw ASRError.transcriptionFailed(reason: "Transcription already in progress")
        }
        
        await MainActor.run {
            isTranscribing = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isTranscribing = false
            }
        }
        
        // Get appropriate backend
        let backend = await currentBackend()
        
        do {
            // Attempt transcription
            let result = try await transcribeWithBackend(backend, audio: audio, config: config)
            
            // In dual mode, also run other backend for comparison
            if selectedMode == .dualMode {
                let otherBackend = (backend as? NativeMLXBackend) != nil ? pythonBackend : nativeBackend
                Task {
                    do {
                        let otherResult = try await transcribeWithBackend(otherBackend, audio: audio, config: config)
                        await storeComparison(native: result, python: otherResult)
                    } catch {
                        print("Dual mode: Second backend failed: \(error)")
                    }
                }
            }
            
            await MainActor.run {
                currentResult = result
            }
            
            return result
            
        } catch {
            // Try fallback if primary fails
            let fallback = (backend as? NativeMLXBackend) != nil ? pythonBackend : nativeBackend
            
            if fallback.isAvailable {
                print("Primary backend failed, trying fallback...")
                let result = try await transcribeWithBackend(fallback, audio: audio, config: config)
                
                await MainActor.run {
                    currentResult = result
                }
                
                return result
            }
            
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            
            throw error
        }
    }
    
    /// Stream transcription with real-time results
    public func transcribeStream(
        audioStream: AsyncStream<[Float]>,
        config: TranscriptionConfig = TranscriptionConfig()
    ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            self.streamingTask = Task {
                do {
                    await MainActor.run {
                        self.isTranscribing = true
                        self.streamingText = ""
                        self.errorMessage = nil
                    }
                    
                    // In dual mode, run both backends
                    if self.selectedMode == .dualMode {
                        await self.runDualStreamTranscription(
                            audioStream: audioStream,
                            config: config,
                            continuation: continuation
                        )
                    } else {
                        // Single backend mode
                        let backend = await self.currentBackend()
                        
                        let stream = await backend.startStreaming(config: config)
                        for try await event in stream {
                            await self.handleStreamEvent(event, continuation: continuation)
                        }
                    }
                    
                    continuation.finish()
                    
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                    continuation.yield(.error(ASRError.transcriptionFailed(reason: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
                
                await MainActor.run {
                    self.isTranscribing = false
                }
            }
        }
    }
    
    public func stopTranscription() async {
        streamingTask?.cancel()
        streamingTask = nil
        
        await nativeBackend.stopStreaming()
        await pythonBackend.stopStreaming()
        
        isTranscribing = false
    }
    
    // MARK: - Comparison Testing
    
    /// Compare both backends on the same audio
    public func compareBackends(
        audio: Data,
        config: TranscriptionConfig = TranscriptionConfig()
    ) async throws -> BackendComparisonResult {
        guard FeatureFlagManager.shared.shouldEnableDualMode() else {
            throw ASRError.subscriptionRequired(feature: "Dual mode comparison")
        }
        
        // Run both backends
        let nativeResult = try await transcribeWithBackend(nativeBackend, audio: audio, config: config)
        let pythonResult = try await transcribeWithBackend(pythonBackend, audio: audio, config: config)
        
        let nativeMetrics = await nativeBackend.health().performanceMetrics ?? PerformanceMetrics()
        let pythonMetrics = await pythonBackend.health().performanceMetrics ?? PerformanceMetrics()
        
        // Calculate WER (Word Error Rate)
        let wer = calculateWER(nativeResult.fullText, pythonResult.fullText)
        
        let comparison = BackendComparisonResult(
            nativeResult: nativeResult,
            pythonResult: pythonResult,
            nativeMetrics: nativeMetrics,
            pythonMetrics: pythonMetrics,
            wordErrorRate: wer,
            accuracyMatch: wer < 0.1  // Within 10% WER considered matching
        )
        
        await MainActor.run {
            lastComparison = comparison
        }
        
        return comparison
    }
    
    // MARK: - Private Methods
    
    private func transcribeWithBackend(
        _ backend: ASRBackend,
        audio: Data,
        config: TranscriptionConfig
    ) async throws -> TranscriptionResult {
        await updateBackendStatus(backend, state: .busy)
        defer {
            Task {
                await updateBackendStatus(backend, state: .ready)
            }
        }
        
        return try await backend.transcribe(audio: audio, config: config)
    }
    
    private func handleModeChange(from oldMode: BackendMode, to newMode: BackendMode) async {
        // Save preference
        UserDefaults.standard.set(newMode.rawValue, forKey: "hybrid_asr_mode")
        
        // Update active backend for auto mode
        if newMode == .autoSelect {
            await selectBestBackend()
        } else if newMode == .nativeMLX {
            activeBackend = nativeBackend
        } else if newMode == .pythonServer {
            activeBackend = pythonBackend
        }
    }
    
    private func handleStreamEvent(
        _ event: TranscriptionEvent,
        continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
    ) async {
        switch event {
        case .partial(let text, _):
            await MainActor.run {
                streamingText = text
            }
            continuation.yield(event)
            
        case .final(let segment):
            await MainActor.run {
                streamingText = segment.text
            }
            continuation.yield(event)
            
        default:
            continuation.yield(event)
        }
    }
    
    private func runDualStreamTranscription(
        audioStream: AsyncStream<[Float]>,
        config: TranscriptionConfig,
        continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
    ) async {
        // Start both backends
        let nativeStream = await nativeBackend.startStreaming(config: config)
        let pythonStream = await pythonBackend.startStreaming(config: config)
        
        // Feed audio to both
        Task {
            for await samples in audioStream {
                if let native = nativeBackend as? NativeMLXBackend {
                    await native.feedAudio(samples: samples)
                }
                // Python backend handles audio via WebSocket
            }
        }
        
        // Collect results from both
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await event in nativeStream {
                        await continuation.yield(event)
                    }
                }
                
                group.addTask {
                    for try await event in pythonStream {
                        await continuation.yield(event)
                    }
                }
                
                try await group.waitForAll()
            }
        } catch {
            continuation.yield(.error(ASRError.streamingError(error.localizedDescription)))
        }
    }
    
    private func storeComparison(native: TranscriptionResult, python: TranscriptionResult) async {
        // Store for analysis
        comparisonBuffer.append((native: native, python: python))
        
        // Keep only last 100 comparisons
        if comparisonBuffer.count > 100 {
            comparisonBuffer.removeFirst()
        }
    }
    
    private func updateBackendStatus(
        _ backend: ASRBackend,
        state: BackendState,
        message: String? = nil
    ) async {
        let name = backend.name  // nonisolated
        let caps = backend.capabilities  // nonisolated
        let status = BackendStatus(
            backendName: name,
            state: state,
            message: message,
            capabilities: caps
        )
        
        await MainActor.run {
            backendStatus[name] = status
        }
    }
    
    private func calculateWER(_ reference: String, _ hypothesis: String) -> Double {
        // Simple word error rate calculation
        let refWords = reference.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let hypWords = hypothesis.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        let refSet = Set(refWords)
        let hypSet = Set(hypWords)
        
        let errors = refSet.symmetricDifference(hypSet).count
        let total = max(refSet.count, hypSet.count)
        
        return total > 0 ? Double(errors) / Double(total) : 0.0
    }
}

// MARK: - Dependency Container

@MainActor
public final class ASRContainer {
    public static let shared = ASRContainer()
    
    public private(set) lazy var hybridASRManager: HybridASRManager = {
        let native = NativeMLXBackend()
        let python = PythonBackend()
        
        return HybridASRManager(
            nativeBackend: native,
            pythonBackend: python,
            subscriptionTier: .free  // Will be updated from actual subscription
        )
    }()
    
    private init() {}
    
    public func updateSubscription(_ tier: SubscriptionTier) {
        // Create new manager with updated tier
        let native = NativeMLXBackend()
        let python = PythonBackend()
        
        hybridASRManager = HybridASRManager(
            nativeBackend: native,
            pythonBackend: python,
            subscriptionTier: tier
        )
    }
}
