import Foundation
import MLXAudioSTT
import MLXAudioCore
@preconcurrency import MLX
@preconcurrency import AVFoundation
import os

// MARK: - Configuration

public struct MLXBackendConfiguration: Sendable {
    public let modelId: String
    public let maxTokens: Int
    public let temperature: Float
    public let chunkDuration: Float
    public let streamingDelayMs: Int
    
    public static let `default` = MLXBackendConfiguration(
        modelId: "mlx-community/Qwen3-ASR-0.6B-4bit",
        maxTokens: 1024,
        temperature: 0.0,
        chunkDuration: 30.0,
        streamingDelayMs: 480
    )
    
    public init(
        modelId: String = "mlx-community/Qwen3-ASR-0.6B-4bit",
        maxTokens: Int = 1024,
        temperature: Float = 0.0,
        chunkDuration: Float = 30.0,
        streamingDelayMs: Int = 480
    ) {
        self.modelId = modelId
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.chunkDuration = chunkDuration
        self.streamingDelayMs = streamingDelayMs
    }
}
// MARK: - Thread-Safe Audio Buffer

final class ThreadSafeAudioBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private let lock = NSLock()
    private let maxCapacity: Int
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
    
    var isOverflow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count >= maxCapacity
    }
    
    init(capacity: Int = 32768) {
        self.maxCapacity = capacity
    }
    
    func write(_ samples: [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if buffer.count + samples.count > maxCapacity {
            return false
        }
        buffer.append(contentsOf: samples)
        return true
    }
    
    func read(upTo count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let readCount = min(count, buffer.count)
        let result = Array(buffer.prefix(readCount))
        buffer.removeFirst(readCount)
        return result
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }
}

// MARK: - Native MLX Backend

public actor NativeMLXBackend: ASRBackend {
    
    // MARK: - Properties
    
    public nonisolated let name: String = "Native MLX"
    
    private nonisolated(unsafe) var _isAvailableCache: Bool = false
    public nonisolated var isAvailable: Bool {
        return _isAvailableCache
    }
    
    private func updateAvailabilityCache(_ value: Bool) {
        _isAvailableCache = value
    }
    
    public private(set) var status: BackendStatus = BackendStatus(
        backendName: "Native MLX",
        state: .unknown
    )
    
    public nonisolated let capabilities: BackendCapabilities = BackendCapabilities(
        supportsStreaming: true,
        supportsBatch: true,
        supportsDiarization: false,
        supportsOffline: true,
        requiresNetwork: false,
        supportedLanguages: Language.allCases,
        estimatedRTF: 0.08
    )
    
    // MARK: - ASR Model (via fallback chain)
    
    /// Priority chain: Qwen3-0.6B → Qwen3-1.7B → Parakeet → Python
    private var chain: ASRFallbackChain?
    /// Fallback tiers derived from configuration — allows overriding default chain at init time.
    private let chainTiers: [ASRTier]

    /// Direct reference to the Qwen3 model within the chain (for StreamingInferenceSession).
    /// Populated after initialize(); nil if chain loaded a non-Qwen3 primary.
    private var qwen3Model: Qwen3ASRModel?
    private var isModelLoaded: Bool = false
    private var loadedModelId: String = ""
    
    // MARK: - Streaming
    
    private var streamingSession: StreamingInferenceSession?
    public private(set) var isStreaming: Bool = false
    private var streamingAudioDuration: TimeInterval = 0
    private var lastSegmentEndTime: TimeInterval = 0
    private let audioBuffer = ThreadSafeAudioBuffer(capacity: 32768)
    private var bufferConsumerTask: Task<Void, Error>?
    private var modelSampleRate: Int = 16000  // Default, updated when model loads
    
    // MARK: - Metrics
    
    private var metrics = PerformanceMetrics()
    
    // MARK: - Configuration
    
    public var configuration: MLXBackendConfiguration
    
    // MARK: - Initialization
    
    /// - Parameter tiers: Override the ASR fallback chain. Defaults to Qwen3-0.6B → 1.7B → Parakeet.
    public init(configuration: MLXBackendConfiguration = .default,
                chainTiers: [ASRTier] = [.qwen3_0_6B, .qwen3_1_7B, .parakeet]) {
        self.configuration = configuration
        self.chainTiers = chainTiers
    }
    
    // MARK: - ASRBackend Protocol
    
    public func initialize() async throws {
        await updateStatus(.initializing, message: "Loading ASR model chain...")
        
        let newChain = ASRFallbackChain(tiers: chainTiers)
        do {
            try await newChain.initialize()
        } catch {
            updateAvailabilityCache(false)
            await updateStatus(.error, message: "All ASR tiers failed: \(error.localizedDescription)")
            throw ASRError.initializationFailed(reason: "ASR chain exhausted: \(error)")
        }
        
        chain = newChain
        isModelLoaded = true
        loadedModelId = await newChain.activeTier?.modelId ?? configuration.modelId
        modelSampleRate = await newChain.modelSampleRate
        updateAvailabilityCache(true)

        // Cache Qwen3 model reference for StreamingInferenceSession (streaming path)
        if case .qwen3_0_6B = await newChain.activeTier {
            // Re-load Qwen3 directly for streaming — chain loaded it already, but
            // StreamingInferenceSession needs a direct Qwen3ASRModel reference.
            qwen3Model = try? await Qwen3ASRModel.fromPretrained(loadedModelId)
        } else if case .qwen3_1_7B = await newChain.activeTier {
            qwen3Model = try? await Qwen3ASRModel.fromPretrained(loadedModelId)
        }

        await updateStatus(.ready, message: "ASR ready (\(await newChain.activeTier?.displayName ?? "unknown"))")
        
        if FeatureFlagManager.shared.enableVerboseLogging {
            print("NativeMLXBackend: chain loaded \(await newChain.activeTier?.displayName ?? "?"), sr=\(modelSampleRate)Hz")
        }
    }
    
    public func reloadModel(newConfiguration: MLXBackendConfiguration? = nil) async throws {
        await stopStreaming()
        chain = nil
        qwen3Model = nil
        isModelLoaded = false
        loadedModelId = ""
        updateAvailabilityCache(false)
        Memory.clearCache()
        
        if let newConfig = newConfiguration {
            configuration = newConfig
        }
        
        try await initialize()
    }
    
    public func transcribe(audio: Data, config: TranscriptionConfig) async throws -> TranscriptionResult {
        guard isModelLoaded, let currentChain = chain else {
            throw ASRError.backendNotAvailable(backend: name)
        }
        
        let startTime = Date()
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        let (sampleRate, audioData): (Int, MLXArray)
        
        if #available(macOS 14.0, *) {
            (sampleRate, audioData) = try await Task.detached(priority: .userInitiated) {
                try audio.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                return try loadAudioArray(from: tempURL)
            }.value
        } else {
            try audio.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            (sampleRate, audioData) = try loadAudioArray(from: tempURL)
        }
        
        let targetRate = await currentChain.modelSampleRate
        
        let resampled: MLXArray
        if sampleRate != targetRate {
            resampled = try resampleAudio(audioData, from: sampleRate, to: targetRate)
        } else {
            resampled = audioData
        }
        
        let fullText = try await currentChain.transcribe(
            audio: resampled,
            language: config.language.displayName,
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature,
            chunkDuration: configuration.chunkDuration
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        let sampleCount = Double(audioData.shape[0])
        let duration = sampleCount / Double(sampleRate)
        
        let transcriptionResult = TranscriptionResult(
            segments: [
                TranscriptionSegment(
                    text: fullText,
                    startTime: 0,
                    endTime: duration,
                    confidence: 0.0,
                    isFinal: true
                )
            ],
            fullText: fullText,
            duration: duration,
            processingTime: processingTime,
            backendName: name,
            language: config.language,
            confidence: 0.0
        )
        
        metrics.recordSuccess(duration: duration, processingTime: processingTime, confidence: 0.0)
        
        return transcriptionResult
    }
    
    public func startStreaming(config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        guard isModelLoaded, let currentModel = qwen3Model else {
            // Streaming requires Qwen3 (StreamingInferenceSession is Qwen3-only).
            // Fall back to batch transcription error if chain loaded Parakeet.
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ASRError.backendNotAvailable(backend: name))
            }
        }
        
        guard !isStreaming else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ASRError.transcriptionFailed(reason: "Streaming session already active"))
            }
        }
        
        isStreaming = true
        streamingAudioDuration = 0
        lastSegmentEndTime = 0
        audioBuffer.clear()
        
        let streamingConfig = StreamingConfig(
            decodeIntervalSeconds: 1.0,
            maxCachedWindows: 60,
            delayPreset: .custom(ms: configuration.streamingDelayMs),
            language: config.language.displayName,
            temperature: configuration.temperature,
            maxTokensPerPass: configuration.maxTokens
        )
        
        let session = StreamingInferenceSession(
            model: currentModel,
            config: streamingConfig
        )
        streamingSession = session
        
        startBufferConsumer()
        
        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.stopStreaming()
                }
            }
            
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                
                for await event in session.events {
                    guard await self.isStreaming else { break }
                    
                    switch event {
                    case .displayUpdate(let confirmed, let provisional):
                        let text = confirmed + provisional
                        continuation.yield(.partial(text: text, confidence: 0.0))
                        
                    case .confirmed(let text):
                        let currentDuration = await self.streamingAudioDuration
                        let segment = TranscriptionSegment(
                            text: text,
                            startTime: await self.lastSegmentEndTime,
                            endTime: currentDuration,
                            confidence: 0.0,
                            isFinal: true
                        )
                        await self.setLastSegmentEndTime(currentDuration)
                        continuation.yield(.final(segment: segment))
                        
                    case .provisional:
                        break
                        
                    case .stats(let stats):
                        if FeatureFlagManager.shared.enableVerboseLogging {
                            print("Native MLX: \(stats.tokensPerSecond) tok/s, \(stats.peakMemoryGB) GB")
                        }
                        
                    case .ended(let fullText):
                        let result = TranscriptionResult(
                            segments: [
                                TranscriptionSegment(
                                    text: fullText,
                                    startTime: 0,
                                    endTime: await self.streamingAudioDuration,
                                    confidence: 0.0,
                                    isFinal: true
                                )
                            ],
                            fullText: fullText,
                            backendName: self.name,
                            language: config.language
                        )
                        continuation.yield(.completed(result: result))
                    }
                }
                
                continuation.finish()
            }
        }
    }
    
    private func setLastSegmentEndTime(_ time: TimeInterval) {
        lastSegmentEndTime = time
    }
    
    private func startBufferConsumer() {
        bufferConsumerTask = Task { [weak self, modelSampleRate] in
            guard let self = self else { return }
            
            var consecutiveEmptyReads = 0
            let maxEmptyReads = 100  // Exit after ~1 second of empty reads when not streaming
            
            while await self.isStreaming {
                let samples = await self.audioBuffer.read(upTo: 2048)
                
                if !samples.isEmpty {
                    consecutiveEmptyReads = 0
                    let duration = Double(samples.count) / Double(modelSampleRate)
                    await self.addStreamingDuration(duration)
                    
                    if let session = await self.streamingSession {
                        session.feedAudio(samples: samples)
                    }
                } else {
                    consecutiveEmptyReads += 1
                    
                    // Use adaptive sleep based on buffer state
                    let sleepNanos: UInt64
                    if consecutiveEmptyReads < 10 {
                        sleepNanos = 5_000_000  // 5ms when buffer was recently active
                    } else {
                        sleepNanos = 20_000_000  // 20ms when buffer is consistently empty
                    }
                    
                    do {
                        try await Task.sleep(nanoseconds: sleepNanos)
                    } catch is CancellationError {
                        // Task was cancelled, exit cleanly
                        break
                    } catch {
                        // Other errors, continue loop
                    }
                    
                    // Check if we should stop due to inactivity
                    let stillStreaming = await self.isStreaming
                    if consecutiveEmptyReads >= maxEmptyReads && !stillStreaming {
                        break
                    }
                }
            }
        }
    }
    
    private func addStreamingDuration(_ duration: TimeInterval) {
        streamingAudioDuration += duration
    }
    
    public func stopStreaming() async {
        isStreaming = false
        bufferConsumerTask?.cancel()
        bufferConsumerTask = nil
        streamingSession?.stop()
        streamingSession = nil
        audioBuffer.clear()
        streamingAudioDuration = 0
        lastSegmentEndTime = 0
    }
    
    public enum FeedAudioResult: Sendable {
        case success
        case notStreaming
        case bufferOverflow
    }
    
    public func feedAudio(samples: [Float]) -> FeedAudioResult {
        guard isStreaming else {
            if FeatureFlagManager.shared.enableVerboseLogging {
                print("Native MLX: feedAudio called but not streaming")
            }
            return .notStreaming
        }
        
        let success = audioBuffer.write(samples)
        if !success {
            if FeatureFlagManager.shared.enableVerboseLogging {
                print("Native MLX: Audio buffer overflow, \(samples.count) samples dropped")
            }
            return .bufferOverflow
        }
        
        return .success
    }
    
    public func feedAudioSync(samples: [Float]) {
        _ = feedAudio(samples: samples)
    }
    
    public func health() async -> BackendStatus {
        var updatedStatus = status
        updatedStatus.performanceMetrics = metrics
        return updatedStatus
    }
    
    public func unload() async {
        await stopStreaming()
        await chain?.unload()
        chain = nil
        qwen3Model = nil
        isModelLoaded = false
        loadedModelId = ""
        updateAvailabilityCache(false)
        Memory.clearCache()
        await updateStatus(.unknown, message: "Unloaded")
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ state: BackendState, message: String? = nil) async {
        status = BackendStatus(
            backendName: name,
            state: state,
            message: message,
            capabilities: capabilities
        )
    }
    
    private func resampleAudio(_ audio: MLXArray, from sourceSR: Int, to targetSR: Int) throws -> MLXArray {
        let samples = audio.asArray(Float.self)
        
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(sourceSR), channels: 1, interleaved: false
        ), let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(targetSR), channels: 1, interleaved: false
        ) else {
            throw ASRError.audioFormatError("Failed to create audio formats")
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw ASRError.audioFormatError("Failed to create audio converter")
        }
        
        let inputFrameCount = AVAudioFrameCount(samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            throw ASRError.audioFormatError("Failed to create input buffer")
        }
        inputBuffer.frameLength = inputFrameCount
        
        samples.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                memcpy(inputBuffer.floatChannelData![0], baseAddress, samples.count * MemoryLayout<Float>.size)
            }
        }
        
        let ratio = Double(targetSR) / Double(sourceSR)
        let outputFrameCount = AVAudioFrameCount(Double(samples.count) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw ASRError.audioFormatError("Failed to create output buffer")
        }
        
        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        
        if let error = conversionError {
            throw ASRError.audioFormatError("Resampling failed: \(error)")
        }
        
        let outputSamples = Array(UnsafeBufferPointer(
            start: outputBuffer.floatChannelData![0], count: Int(outputBuffer.frameLength)
        ))
        return MLXArray(outputSamples)
    }
}
