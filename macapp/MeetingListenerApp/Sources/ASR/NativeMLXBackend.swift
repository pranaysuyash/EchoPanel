@preconcurrency import Foundation
import MLXAudioSTT
import MLXAudioCore
import MLX
@preconcurrency import AVFoundation

// MARK: - Native MLX Backend

/// Native ASR backend using MLX Audio Swift for on-device transcription
public actor NativeMLXBackend: ASRBackend {
    
    // MARK: - Properties
    
    public nonisolated let name: String = "Native MLX"
    
    public nonisolated var isAvailable: Bool {
        // Check without accessing actor-isolated state
        // This is a simplified check - in production you'd use an atomic or actor hopping
        return true  // Assume available, actual check done in initialize
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
    
    // MARK: - MLX Model
    
    private var model: Qwen3ASRModel?
    private var isModelLoaded: Bool = false
    private var loadedModelId: String = ""
    
    // MARK: - Streaming
    
    private var streamingSession: StreamingInferenceSession?
    private var isStreaming: Bool = false
    
    // MARK: - Metrics
    
    private var metrics = PerformanceMetrics()
    
    // MARK: - Configuration
    
    public var modelId: String = "mlx-community/Qwen3-ASR-0.6B-4bit"
    public var maxTokens: Int = 1024
    public var temperature: Float = 0.0
    public var chunkDuration: Float = 30.0
    public var streamingDelayMs: Int = 480
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - ASRBackend Protocol
    
    public func initialize() async throws {
        await updateStatus(.initializing, message: "Loading MLX model: \(modelId)...")
        
        do {
            model = try await Qwen3ASRModel.fromPretrained(modelId)
            isModelLoaded = true
            loadedModelId = modelId
            
            await updateStatus(.ready, message: "Model loaded successfully")
            
            if FeatureFlagManager.shared.enableVerboseLogging {
                print("✅ Native MLX: Model loaded (\(modelId))")
            }
            
        } catch {
            await updateStatus(.error, message: "Failed to load model: \(error.localizedDescription)")
            throw ASRError.initializationFailed(reason: "MLX model load failed: \(error)")
        }
    }
    
    public func reloadModel() async throws {
        model = nil
        isModelLoaded = false
        loadedModelId = ""
        Memory.clearCache()
        try await initialize()
    }
    
    public func transcribe(audio: Data, config: TranscriptionConfig) async throws -> TranscriptionResult {
        guard isAvailable else {
            throw ASRError.backendNotAvailable(backend: name)
        }
        
        let startTime = Date()
        
        // Convert Data to temporary file for loading
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        try audio.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Load audio using MLXAudioSTT helper
        let (sampleRate, audioData) = try loadAudioArray(from: tempURL)
        let targetRate = model!.sampleRate
        
        // Resample if needed
        let resampled: MLXArray
        if sampleRate != targetRate {
            resampled = try resampleAudio(audioData, from: sampleRate, to: targetRate)
        } else {
            resampled = audioData
        }
        
        // Transcribe
        var fullText = ""
        var tokenCount = 0
        var finalTokensPerSecond: Double = 0
        var finalPeakMemory: Double = 0
        
        for try await event in model!.generateStream(
            audio: resampled,
            maxTokens: maxTokens,
            temperature: temperature,
            language: config.language.displayName,
            chunkDuration: chunkDuration
        ) {
            switch event {
            case .token(let token):
                fullText += token
                tokenCount += 1
            case .info(let info):
                finalTokensPerSecond = info.tokensPerSecond
                finalPeakMemory = info.peakMemoryUsage
            case .result:
                break
            }
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        let duration = Double(audio.count) / 16000.0 / 2.0  // PCM 16-bit @ 16kHz
        
        let transcriptionResult = TranscriptionResult(
            segments: [
                TranscriptionSegment(
                    text: fullText,
                    startTime: 0,
                    endTime: duration,
                    confidence: 0.95,
                    isFinal: true
                )
            ],
            fullText: fullText,
            duration: duration,
            processingTime: processingTime,
            backendName: name,
            language: config.language,
            confidence: 0.95
        )
        
        // Update metrics
        metrics.recordSuccess(duration: duration, processingTime: processingTime, confidence: 0.95)
        
        return transcriptionResult
    }
    
    public func startStreaming(config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard self.isAvailable else {
                        throw ASRError.backendNotAvailable(backend: self.name)
                    }
                    
                    continuation.yield(.started)
                    self.isStreaming = true
                    
                    // Create streaming session
                    let streamingConfig = StreamingConfig(
                        decodeIntervalSeconds: 1.0,
                        maxCachedWindows: 60,
                        delayPreset: .custom(ms: self.streamingDelayMs),
                        language: config.language.displayName,
                        temperature: self.temperature,
                        maxTokensPerPass: self.maxTokens
                    )
                    
                    let session = StreamingInferenceSession(
                        model: self.model!,
                        config: streamingConfig
                    )
                    self.streamingSession = session
                    
                    // Process events from session
                    for await event in session.events {
                        switch event {
                        case .displayUpdate(let confirmed, let provisional):
                            let text = confirmed + provisional
                            continuation.yield(.partial(text: text, confidence: 0.9))
                            
                        case .confirmed(let text):
                            let segment = TranscriptionSegment(
                                text: text,
                                startTime: 0,
                                endTime: 0,
                                confidence: 0.95,
                                isFinal: true
                            )
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
                                        endTime: 0,
                                        confidence: 0.95,
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
                    
                } catch {
                    continuation.yield(.error(ASRError.transcriptionFailed(reason: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func stopStreaming() async {
        isStreaming = false
        streamingSession?.stop()
        streamingSession = nil
    }
    
    public func feedAudio(samples: [Float]) {
        streamingSession?.feedAudio(samples: samples)
    }
    
    public func health() async -> BackendStatus {
        var updatedStatus = status
        updatedStatus.performanceMetrics = metrics
        return updatedStatus
    }
    
    public func unload() async {
        await stopStreaming()
        model = nil
        isModelLoaded = false
        loadedModelId = ""
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
        memcpy(inputBuffer.floatChannelData![0], samples, samples.count * MemoryLayout<Float>.size)
        
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
