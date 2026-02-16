# Hybrid Backend Implementation Guide

**Date:** 2026-02-14  
**Goal:** Implement dual ASR backend support (Native MLX + Python)  
**Estimated Time:** 3-5 days

---

## Overview

This guide shows how to implement a hybrid architecture supporting both:
- **Native MLX** (MLX Audio Swift) - Local, fast, private
- **Python Backend** - Cloud, advanced features, team collaboration

---

## Step 1: Define Protocols

Create file: `macapp/MeetingListenerApp/Sources/ASR/ASRBackendProtocol.swift`

```swift
import Foundation

/// Protocol for all ASR backends
protocol ASRBackend: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get async }
    var capabilities: ASRCapabilities { get }
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription
    func transcribeStream(audioStream: AsyncStream<Data>, config: TranscriptionConfig) -> AsyncThrowingStream<TranscriptionEvent, Error>
}

struct ASRCapabilities {
    let supportsStreaming: Bool
    let supportsDiarization: Bool
    let supportsOffline: Bool
    let supportedLanguages: [Language]
    let maxAudioDuration: TimeInterval
}

struct TranscriptionConfig {
    let language: Language
    let enableDiarization: Bool
    let enablePunctuation: Bool
    let vocabulary: [String]?  // Custom vocabulary
}

enum TranscriptionEvent {
    case partial(text: String, confidence: Double)
    case final(text: String, segments: [TranscriptionSegment])
    case diarization(speakers: [SpeakerSegment])
    case error(Error)
    case completed
}

struct Transcription {
    let text: String
    let segments: [TranscriptionSegment]
    let speakers: [SpeakerSegment]?
    let processingTime: TimeInterval
    let backend: String
}

struct TranscriptionSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Double
}

struct SpeakerSegment {
    let speakerId: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
}
```

---

## Step 2: Implement Native MLX Backend

Create file: `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift`

```swift
import Foundation
import MLXAudioSTT
import MLXAudioVAD

/// Native MLX Audio Swift backend
@MainActor
class NativeMLXBackend: ASRBackend {
    let name = "Native MLX"
    
    private var asrModel: GLMASRModel?
    private var diarizationModel: SortformerModel?
    private var currentModelName: String?
    
    var capabilities: ASRCapabilities {
        ASRCapabilities(
            supportsStreaming: true,
            supportsDiarization: diarizationModel != nil,
            supportsOffline: true,
            supportedLanguages: Language.allCases,  // Depends on model
            maxAudioDuration: 3600  // 1 hour
        )
    }
    
    var isAvailable: Bool {
        get async {
            return asrModel != nil
        }
    }
    
    /// Load model
    func loadModel(_ modelName: String = "mlx-community/GLM-ASR-Nano-2512-4bit") async throws {
        guard modelName != currentModelName else { return }
        
        print("📥 Loading MLX model: \(modelName)")
        asrModel = try await GLMASRModel.fromPretrained(modelName)
        currentModelName = modelName
        print("✅ Model loaded")
    }
    
    /// Load diarization model
    func loadDiarizationModel() async throws {
        guard diarizationModel == nil else { return }
        
        diarizationModel = try await SortformerModel.fromPretrained(
            "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
        )
    }
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
        guard let model = asrModel else {
            throw ASRError.modelNotLoaded
        }
        
        let startTime = Date()
        
        // Convert audio data to MLX array
        let audioArray = try convertToMLXArray(audio)
        
        // Generate transcription
        let output = model.generate(audio: audioArray)
        
        // Perform diarization if enabled
        var speakers: [SpeakerSegment]?
        if config.enableDiarization, let diarModel = diarizationModel {
            let diarOutput = try await diarModel.generate(audio: audioArray, threshold: 0.5)
            speakers = diarOutput.segments.map { seg in
                SpeakerSegment(
                    speakerId: seg.speaker,
                    startTime: Double(seg.start),
                    endTime: Double(seg.end)
                )
            }
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return Transcription(
            text: output.text,
            segments: [],  // MLX models may not provide segments
            speakers: speakers,
            processingTime: processingTime,
            backend: name
        )
    }
    
    func transcribeStream(
        audioStream: AsyncStream<Data>,
        config: TranscriptionConfig
    ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let model = self.asrModel else {
                        throw ASRError.modelNotLoaded
                    }
                    
                    for await audioChunk in audioStream {
                        let audioArray = try self.convertToMLXArray(audioChunk)
                        
                        // Stream tokens
                        for try await event in model.generateStream(audio: audioArray) {
                            switch event {
                            case .token(let token):
                                continuation.yield(.partial(text: token, confidence: 0.9))
                            case .info:
                                break  // Ignore info events
                            default:
                                break
                            }
                        }
                    }
                    
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func convertToMLXArray(_ data: Data) throws -> MLXArray {
        // Convert Data to MLXArray
        let floatArray = data.withUnsafeBytes { buffer -> [Float] in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / 32768.0 }
        }
        return MLXArray(floatArray)
    }
}

enum ASRError: Error {
    case modelNotLoaded
    case conversionFailed
    case unsupportedLanguage
}
```

---

## Step 3: Implement Python Backend

Create file: `macapp/MeetingListenerApp/Sources/ASR/PythonBackend.swift`

```swift
import Foundation

/// Python backend via WebSocket/HTTP
class PythonBackend: ASRBackend {
    let name = "Python Server"
    
    private let webSocketManager: WebSocketStreamer
    private let apiClient: BackendAPIClient
    
    var capabilities: ASRCapabilities {
        ASRCapabilities(
            supportsStreaming: true,
            supportsDiarization: true,
            supportsOffline: false,  // Requires server
            supportedLanguages: Language.allCases,
            maxAudioDuration: 7200  // 2 hours
        )
    }
    
    var isAvailable: Bool {
        get async {
            return await apiClient.healthCheck()
        }
    }
    
    init(webSocketManager: WebSocketStreamer, apiClient: BackendAPIClient) {
        self.webSocketManager = webSocketManager
        self.apiClient = apiClient
    }
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
        let startTime = Date()
        
        // Upload audio and get transcription
        let result = try await apiClient.transcribe(
            audio: audio,
            language: config.language.code,
            enableDiarization: config.enableDiarization
        )
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return Transcription(
            text: result.text,
            segments: result.segments.map { seg in
                TranscriptionSegment(
                    startTime: seg.start,
                    endTime: seg.end,
                    text: seg.text,
                    confidence: seg.confidence
                )
            },
            speakers: result.speakers?.map { speaker in
                SpeakerSegment(
                    speakerId: speaker.id,
                    startTime: speaker.start,
                    endTime: speaker.end
                )
            },
            processingTime: processingTime,
            backend: name
        )
    }
    
    func transcribeStream(
        audioStream: AsyncStream<Data>,
        config: TranscriptionConfig
    ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        webSocketManager.transcribeStream(audioStream: audioStream, config: config)
    }
}
```

---

## Step 4: Create Hybrid Manager

Create file: `macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift`

```swift
import Foundation
import Combine

/// Manages multiple ASR backends with smart selection
@MainActor
class HybridASRManager: ObservableObject {
    // MARK: - Published State
    @Published var currentBackend: ASRBackend?
    @Published var isTranscribing: Bool = false
    @Published var currentTranscription: String = ""
    @Published var selectedMode: BackendMode = .autoSelect
    
    // MARK: - Backends
    let nativeBackend: NativeMLXBackend
    let pythonBackend: PythonBackend
    
    // MARK: - Settings
    @AppStorage("asrBackendMode") private var savedMode: BackendMode = .autoSelect
    @AppStorage("preferredNativeModel") private var preferredNativeModel: String = "mlx-community/GLM-ASR-Nano-2512-4bit"
    
    // MARK: - Subscription
    private var subscriptionManager: SubscriptionManager
    
    enum BackendMode: String, CaseIterable, Identifiable {
        case autoSelect = "auto"
        case nativeMLX = "native"
        case pythonServer = "python"
        case dualMode = "dual"  // Dev only
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .autoSelect: return "Automatic"
            case .nativeMLX: return "Native (Fast & Private)"
            case .pythonServer: return "Cloud (Advanced Features)"
            case .dualMode: return "Dual (Dev Mode)"
            }
        }
        
        var description: String {
            switch self {
            case .autoSelect:
                return "Automatically chooses the best backend based on your needs"
            case .nativeMLX:
                return "Runs on your Mac. Fast, private, works offline."
            case .pythonServer:
                return "Uses cloud servers. Advanced NLP, team features."
            case .dualMode:
                return "Runs both backends for comparison (developers only)"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(
        nativeBackend: NativeMLXBackend,
        pythonBackend: PythonBackend,
        subscriptionManager: SubscriptionManager
    ) {
        self.nativeBackend = nativeBackend
        self.pythonBackend = pythonBackend
        self.subscriptionManager = subscriptionManager
        self.selectedMode = savedMode
        
        // Initialize native backend
        Task {
            try? await nativeBackend.loadModel(preferredNativeModel)
        }
    }
    
    // MARK: - Backend Selection
    
    func selectBackend(for config: TranscriptionConfig) async -> ASRBackend {
        // Check subscription tier
        let tier = subscriptionManager.currentTier
        
        switch selectedMode {
        case .autoSelect:
            return await autoSelectBackend(for: config, tier: tier)
            
        case .nativeMLX:
            if tier.canUseBackend(.nativeMLX) {
                return nativeBackend
            } else {
                // Fallback if not available
                return await autoSelectBackend(for: config, tier: tier)
            }
            
        case .pythonServer:
            if tier.canUseBackend(.pythonServer) {
                return pythonBackend
            } else {
                showUpgradePrompt(for: .proCloud)
                return await autoSelectBackend(for: config, tier: tier)
            }
            
        case .dualMode:
            #if DEBUG
            return DualModeBackend(native: nativeBackend, python: pythonBackend)
            #else
            return await autoSelectBackend(for: config, tier: tier)
            #endif
        }
    }
    
    private func autoSelectBackend(
        for config: TranscriptionConfig,
        tier: SubscriptionTier
    ) async -> ASRBackend {
        
        // Priority 1: Check if native supports requirements
        let nativeAvailable = await nativeBackend.isAvailable
        let nativeSupportsLanguage = nativeBackend.capabilities.supportedLanguages
            .contains(config.language)
        
        // Priority 2: Check if advanced features needed
        let needsAdvancedFeatures = config.enableDiarization &&
            !nativeBackend.capabilities.supportsDiarization
        
        // Priority 3: Check network
        let isOffline = !NetworkMonitor.shared.isConnected
        
        // Priority 4: Check subscription
        let canUsePython = tier.canUseBackend(.pythonServer)
        
        // Decision tree
        if isOffline {
            if nativeAvailable {
                return nativeBackend
            } else {
                // Can't transcribe offline without native model
                throw ASRError.offlineAndNoNativeModel
            }
        }
        
        if needsAdvancedFeatures && canUsePython {
            return pythonBackend
        }
        
        if nativeAvailable && nativeSupportsLanguage {
            return nativeBackend
        }
        
        if canUsePython {
            return pythonBackend
        }
        
        // Fallback
        return nativeBackend
    }
    
    // MARK: - Transcription
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
        let backend = await selectBackend(for: config)
        currentBackend = backend
        
        isTranscribing = true
        defer { isTranscribing = false }
        
        do {
            let result = try await backend.transcribe(audio: audio, config: config)
            currentTranscription = result.text
            return result
        } catch {
            // Try fallback
            let fallback = (backend === nativeBackend) ? pythonBackend : nativeBackend
            if await fallback.isAvailable {
                print("Primary backend failed, trying fallback...")
                return try await fallback.transcribe(audio: audio, config: config)
            }
            throw error
        }
    }
    
    func transcribeStream(
        audioStream: AsyncStream<Data>,
        config: TranscriptionConfig
    ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let backend = await self.selectBackend(for: config)
                    self.currentBackend = backend
                    
                    self.isTranscribing = true
                    
                    for try await event in backend.transcribeStream(
                        audioStream: audioStream,
                        config: config
                    ) {
                        continuation.yield(event)
                    }
                    
                    continuation.finish()
                    self.isTranscribing = false
                } catch {
                    continuation.finish(throwing: error)
                    self.isTranscribing = false
                }
            }
        }
    }
    
    // MARK: - UI Helpers
    
    func availableModes(for tier: SubscriptionTier) -> [BackendMode] {
        BackendMode.allCases.filter { mode in
            switch mode {
            case .autoSelect:
                return true
            case .nativeMLX:
                return tier.canUseBackend(.nativeMLX)
            case .pythonServer:
                return tier.canUseBackend(.pythonServer)
            case .dualMode:
                #if DEBUG
                return true
                #else
                return false
                #endif
            }
        }
    }
    
    private func showUpgradePrompt(for tier: SubscriptionTier) {
        // Post notification to show upgrade UI
        NotificationCenter.default.post(
            name: .showUpgradePrompt,
            object: tier
        )
    }
}

// MARK: - Dual Mode Backend (Dev Only)

#if DEBUG
class DualModeBackend: ASRBackend {
    let name = "Dual Mode (Dev)"
    let native: ASRBackend
    let python: ASRBackend
    
    var capabilities: ASRCapabilities {
        // Combine capabilities
        ASRCapabilities(
            supportsStreaming: true,
            supportsDiarization: true,
            supportsOffline: true,
            supportedLanguages: Language.allCases,
            maxAudioDuration: 3600
        )
    }
    
    var isAvailable: Bool {
        get async {
            await native.isAvailable && python.isAvailable
        }
    }
    
    init(native: ASRBackend, python: ASRBackend) {
        self.native = native
        self.python = python
    }
    
    func transcribe(audio: Data, config: TranscriptionConfig) async throws -> Transcription {
        // Run both in parallel
        async let nativeResult = native.transcribe(audio: audio, config: config)
        async let pythonResult = python.transcribe(audio: audio, config: config)
        
        let (nativeTranscription, pythonTranscription) = try await (nativeResult, pythonResult)
        
        // Log comparison
        print("=== Dual Mode Comparison ===")
        print("Native: \(nativeTranscription.text)")
        print("Python: \(pythonTranscription.text)")
        print("Match: \(nativeTranscription.text == pythonTranscription.text)")
        print("Native time: \(nativeTranscription.processingTime)")
        print("Python time: \(pythonTranscription.processingTime)")
        
        // Return native (faster) but include comparison data
        return nativeTranscription
    }
    
    func transcribeStream(
        audioStream: AsyncStream<Data>,
        config: TranscriptionConfig
    ) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        // Just use native for streaming in dual mode
        native.transcribeStream(audioStream: audioStream, config: config)
    }
}
#endif
```

---

## Step 5: UI Integration

Create file: `macapp/MeetingListenerApp/Sources/ASR/BackendSelectionView.swift`

```swift
import SwiftUI

struct BackendSelectionView: View {
    @StateObject private var asrManager: HybridASRManager
    @EnvironmentObject private var subscription: SubscriptionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Backend")
                .font(.headline)
            
            // Backend selector
            Picker("Backend Mode", selection: $asrManager.selectedMode) {
                ForEach(availableModes) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            
            // Description
            Text(asrManager.selectedMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Current status
            BackendStatusCard(backend: asrManager.currentBackend)
            
            // Upgrade prompt if needed
            if asrManager.selectedMode == .pythonServer &&
               !subscription.currentTier.canUseBackend(.pythonServer) {
                UpgradePromptCard(targetTier: .proCloud)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private var availableModes: [HybridASRManager.BackendMode] {
        asrManager.availableModes(for: subscription.currentTier)
    }
}

struct BackendStatusCard: View {
    let backend: ASRBackend?
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading) {
                Text(backend?.name ?? "No backend selected")
                    .font(.subheadline)
                
                if let backend = backend {
                    Text(capabilitiesText(backend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        guard let _ = backend else { return "xmark.circle" }
        return "checkmark.circle"
    }
    
    private var statusColor: Color {
        guard let _ = backend else { return .red }
        return .green
    }
    
    private func capabilitiesText(_ backend: ASRBackend) -> String {
        let caps = backend.capabilities
        var parts: [String] = []
        
        if caps.supportsStreaming { parts.append("Streaming") }
        if caps.supportsDiarization { parts.append("Diarization") }
        if caps.supportsOffline { parts.append("Offline") }
        
        return parts.joined(separator: " • ")
    }
}

struct UpgradePromptCard: View {
    let targetTier: SubscriptionTier
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Upgrade Required")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
            }
            
            Text("Cloud backend requires \(targetTier.displayName) subscription")
                .font(.caption)
            
            Button("Upgrade Now") {
                showUpgradeFlow(for: targetTier)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func showUpgradeFlow(for tier: SubscriptionTier) {
        // Open upgrade/payment flow
        NotificationCenter.default.post(
            name: .showUpgradeFlow,
            object: tier
        )
    }
}
```

---

## Step 6: Integration with Existing Code

Replace existing ASR calls in `AudioCaptureManager`:

```swift
// OLD: Direct WebSocket
class AudioCaptureManager {
    func processAudio(_ data: Data) {
        webSocket.send(data)
    }
}

// NEW: Through HybridASRManager
class AudioCaptureManager {
    var hybridASR: HybridASRManager?
    
    func processAudio(_ data: Data) {
        guard let asr = hybridASR else { return }
        
        Task {
            let config = TranscriptionConfig(
                language: .english,
                enableDiarization: true,
                enablePunctuation: true,
                vocabulary: nil
            )
            
            do {
                let result = try await asr.transcribe(audio: data, config: config)
                print("Transcription: \(result.text)")
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
```

---

## Step 7: Testing Checklist

### Native MLX Backend Tests
- [ ] Load model successfully
- [ ] Transcribe audio file
- [ ] Transcribe streaming audio
- [ ] Works offline
- [ ] Performance < 0.5s for 10s audio

### Python Backend Tests
- [ ] Connect to server
- [ ] Transcribe via WebSocket
- [ ] Fallback when server unavailable
- [ ] Team features work

### Hybrid Logic Tests
- [ ] Auto-select chooses correctly
- [ ] Mode switching works
- [ ] Subscription gating works
- [ ] Dual mode (dev) works

### UI Tests
- [ ] Backend selection visible
- [ ] Upgrade prompts show correctly
- [ ] Status updates in real-time
- [ ] Settings persist

---

## Migration Timeline

| Week | Task |
|------|------|
| 1 | Implement protocols and native backend |
| 2 | Implement Python backend wrapper |
| 3 | Build HybridASRManager |
| 4 | UI integration and testing |
| 5 | Beta rollout (internal) |
| 6 | Beta rollout (select users) |
| 7 | Production rollout with feature flags |

---

## Success Metrics

- **Native backend usage:** Target 60%+
- **Fallback rate:** Target <5%
- **User satisfaction:** Target 4.5/5+
- **Revenue impact:** Track by tier

---

## Resources

- **MLX Audio Swift:** https://github.com/Blaizzy/mlx-audio-swift
- **Hybrid Strategy:** See `docs/ECHOPANEL_HYBRID_ARCHITECTURE_STRATEGY.md`
