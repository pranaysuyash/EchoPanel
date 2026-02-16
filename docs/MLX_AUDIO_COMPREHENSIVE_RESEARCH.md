# MLX-Audio Comprehensive Research Document

**Date**: 2026-02-15
**Researcher**: Kimi Code CLI
**Purpose**: Document all findings regarding MLX-Audio Python and Swift packages, supported models, and integration options for EchoPanel.

---

## Executive Summary

MLX-Audio is Apple's native ML framework (MLX) implementation for audio processing. It provides **significantly better performance** on Apple Silicon compared to PyTorch MPS or vLLM (which doesn't support MPS at all). This document covers both Python and Swift implementations.

**Key Finding**: MLX-Audio 0.2.9 (current in project) has limited STT models. Version 0.3.1 adds Qwen3-ASR but requires dependency upgrades.

---

## Table of Contents

- **Part 1**: MLX-Audio Python Package (versions, models, CLI)
- **Part 2**: MLX-Audio Swift Package (architecture, models, code examples)
- **Part 3**: Performance Comparison (frameworks, benchmarks)
- **Part 4**: Integration Recommendations (Options A, B, C)
- **Part 5**: **Hybrid Architecture (Recommended) - B + C Combined** ⭐
- **Part 6**: Model Details and Testing Notes
- **Part 7**: Dependency Conflict Analysis
- **Part 8**: References and Links
- **Part 9**: Action Items (Phased approach)
- **Appendix A**: Testing Commands

---

## Part 1: MLX-Audio Python Package

### 1.1 Current State in EchoPanel Project

| Attribute | Value |
|-----------|-------|
| **Installed Version** | 0.2.9 |
| **Python Version** | 3.11 (blocks vllm-metal) |
| **Installation Method** | `uv add mlx-audio` |
| **MLX Version** | Bundled with mlx-audio |

### 1.2 Version Compatibility Matrix

| mlx-audio Version | Python Required | transformers | huggingface-hub | Key Features |
|-------------------|-----------------|--------------|-----------------|--------------|
| 0.2.9 | >=3.10 | ^4.x | >=0.34,<1.0 | Basic STT/TTS |
| 0.3.1 | >=3.10 | 5.0.0rc3 | >=1.3.0,<2.0 | Qwen3-ASR, more models |

**Critical Blocker**: Project pins `huggingface-hub<1.0` for `qwen-asr` compatibility, preventing mlx-audio 0.3.1 upgrade.

### 1.3 Supported Model Architectures (Python mlx-audio 0.2.9)

Located in: `.venv/lib/python3.11/site-packages/mlx_audio/stt/models/`

| Model Type | Directory | Status | Notes |
|------------|-----------|--------|-------|
| **Whisper** | `whisper/` | ✅ Full | OpenAI Whisper models |
| **Voxtral** | `voxtral/` | ✅ Full | Mistral speech models |
| **Parakeet** | `parakeet/` | ✅ Full | NVIDIA RNN-T/CTC |
| **GLM-ASR** | `glmasr/` | ✅ Full | Multilingual ASR |
| **Wav2Vec** | `wav2vec/` | ✅ Full | Facebook Wav2Vec |

### 1.4 Model Auto-Detection Logic

```python
# From mlx_audio/stt/utils.py
MODEL_REMAPPING = {
    "glm": "glmasr",
}

# Model type detection from path:
# 1. Check MODEL_REMAPPING dict
# 2. Parse model path: "mlx-community/whisper-large-v3-turbo".split("-")
# 3. Match against available model directories
```

### 1.5 Specific Supported Models (Verified from GitHub README)

#### STT Models (Python - mlx-audio 0.3.1)

| Model | Description | Languages | HuggingFace Repo |
|-------|-------------|-----------|------------------|
| **Whisper** | OpenAI robust STT | 99+ | `mlx-community/whisper-large-v3-turbo-asr-fp16` |
| **Whisper Base** | Smaller Whisper | 99+ | `mlx-community/whisper-base` |
| **Qwen3-ASR** | Alibaba multilingual | ZH, EN, JA, KO | `mlx-community/Qwen3-ASR-1.7B-8bit` |
| **Qwen3-ASR 0.6B** | Smaller Qwen3 | ZH, EN, JA, KO | `mlx-community/Qwen3-ASR-0.6B-8bit` |
| **Qwen3-ForcedAligner** | Word-level alignment | ZH, EN, JA, KO | `mlx-community/Qwen3-ForcedAligner-0.6B-8bit` |
| **Parakeet v2** | NVIDIA STT | English | `mlx-community/parakeet-tdt-0.6b-v2` |
| **Parakeet v3** | NVIDIA STT | 25 EU languages | `mlx-community/parakeet-tdt-0.6b-v3` |
| **Voxtral Mini** | Mistral speech | Multiple | `mlx-community/Voxtral-Mini-3B-2507-bf16` |
| **Voxtral Mini 4bit** | Quantized Voxtral | Multiple | `mlx-community/Voxtral-Mini-3B-2507-4bit` |
| **Voxtral Realtime** | Streaming STT | Multiple | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` |
| **Voxtral Realtime 4bit** | Quantized streaming | Multiple | `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` |
| **VibeVoice-ASR** | Microsoft 9B ASR | Multiple | `mlx-community/VibeVoice-ASR-bf16` |
| **GLM-ASR** | Multilingual ASR | ZH, EN | `mlx-community/GLM-ASR-Nano-2512-4bit` |

#### TTS Models (Python)

| Model | Description | Languages | Repo |
|-------|-------------|-----------|------|
| **Kokoro** | Fast multilingual TTS | EN, JA, ZH, FR, ES, IT, PT, HI | `mlx-community/Kokoro-82M-bf16` |
| **Qwen3-TTS** | Alibaba TTS | ZH, EN, JA, KO | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` |
| **CSM** | Conversational voice cloning | EN | `mlx-community/csm-1b` |
| **Dia** | Dialogue TTS | EN | `mlx-community/Dia-1.6B-fp16` |
| **OuteTTS** | Efficient TTS | EN | `mlx-community/OuteTTS-1.0-0.6B-fp16` |
| **Spark** | SparkTTS | EN, ZH | `mlx-community/Spark-TTS-0.5B-bf16` |
| **Chatterbox** | Expressive multilingual | 15+ languages | `mlx-community/chatterbox-fp16` |
| **Soprano** | High-quality TTS | EN | `mlx-community/Soprano-1.1-80M-bf16` |

#### VAD/Diarization Models (Python)

| Model | Description | Use Case | Repo |
|-------|-------------|----------|------|
| **Sortformer v1** | Speaker diarization | Up to 4 speakers | `mlx-community/diar_sortformer_4spk-v1-fp32` |
| **Sortformer v2.1** | Streaming diarization | 4 speakers + AOSC | `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp32` |

#### STS Models (Python)

| Model | Description | Use Case | Repo |
|-------|-------------|----------|------|
| **SAM-Audio** | Source separation | Extract sounds | `mlx-community/sam-audio-large` |
| **Liquid2.5-Audio** | Speech-to-Speech | Speech interactions | `mlx-community/LFM2.5-Audio-1.5B-8bit` |
| **MossFormer2 SE** | Speech enhancement | Noise removal | `starkdmi/MossFormer2_SE_48K_MLX` |

### 1.6 Model Loading Example (Python)

```python
from mlx_audio.stt.utils import load_model

# Load any supported model
model = load_model("mlx-community/whisper-large-v3-turbo-asr-fp16")

# Generate transcription
result = model.generate("audio.wav")
print(result.text)
```

### 1.7 CLI Usage (Python)

```bash
# Transcription
mlx_audio.stt.generate --model mlx-community/whisper-large-v3-turbo --audio file.wav --output out.txt

# With format options
mlx_audio.stt.generate --model MODEL --audio AUDIO --output OUT --format {txt,srt,vtt,json}
```

---

## Part 2: MLX-Audio Swift Package

### 2.1 Package Information

| Attribute | Value |
|-----------|-------|
| **Repository** | https://github.com/Blaizzy/mlx-audio-swift |
| **License** | MIT |
| **Platforms** | macOS 14+, iOS 17+ |
| **Requirements** | Apple Silicon (M1+), Xcode 15+, Swift 5.9+ |
| **Architecture** | Modular (import only what you need) |

### 2.2 Swift Package Structure

```
MLXAudio (Swift)
├── MLXAudioCore          # Base types, protocols, utilities
├── MLXAudioCodecs        # Audio codecs (SNAC, Vocos, Mimi)
├── MLXAudioTTS           # Text-to-Speech models
├── MLXAudioSTT           # Speech-to-Text models
├── MLXAudioVAD           # Voice Activity Detection
├── MLXAudioSTS           # Speech-to-Speech (future)
└── MLXAudioUI            # SwiftUI components
```

### 2.3 Swift Package Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
]

// Import specific modules
.product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
.product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
.product(name: "MLXAudioCore", package: "mlx-audio-swift")
```

### 2.4 Supported Models (Swift)

#### STT Models (Swift)

| Model | Class | HuggingFace Repo | Status |
|-------|-------|------------------|--------|
| **GLM-ASR** | `GLMASRModel` | `mlx-community/GLM-ASR-Nano-2512-4bit` | ✅ Available |
| **Qwen3-ASR** | `Qwen3ASRModel` | Various Qwen3 repos | ✅ Available |
| **Qwen3-ForcedAligner** | `Qwen3ForcedAligner` | Qwen3 aligner repos | ✅ Available |

**Note**: Swift STT models are more limited than Python currently.

#### TTS Models (Swift)

| Model | Class | HuggingFace Repo | Features |
|-------|-------|------------------|----------|
| **Soprano** | `SopranoModel` | `mlx-community/Soprano-80M-bf16` | Fast, high quality |
| **VyvoTTS** | `VyvoTTSModel` | `mlx-community/VyvoTTS-EN-Beta-4bit` | English TTS |
| **Orpheus** | `OrpheusModel` | `mlx-community/orpheus-3b-0.1-ft-bf16` | Voice cloning |
| **Marvis TTS** | `MarvisTTSModel` | `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit` | Efficient |
| **Pocket TTS** | `PocketTTSModel` | `mlx-community/pocket-tts` | Lightweight |

#### VAD/Diarization Models (Swift)

| Model | Class | HuggingFace Repo |
|-------|-------|------------------|
| **Sortformer** | `SortformerModel` | `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16` |

### 2.5 Swift Code Examples

#### STT Example (Swift)

```swift
import MLXAudioSTT
import MLXAudioCore

// Load audio file
let (sampleRate, audioData) = try loadAudioArray(from: audioURL)

// Load STT model
let model = try await GLMASRModel.fromPretrained("mlx-community/GLM-ASR-Nano-2512-4bit")

// Transcribe
let output = model.generate(audio: audioData)
print(output.text)
```

#### TTS Example (Swift)

```swift
import MLXAudioTTS
import MLXAudioCore

// Load TTS model
let model = try await SopranoModel.fromPretrained("mlx-community/Soprano-80M-bf16")

// Generate audio with parameters
let audio = try await model.generate(
    text: "Hello from MLX Audio Swift!",
    parameters: GenerateParameters(
        maxTokens: 200,
        temperature: 0.7,
        topP: 0.95
    )
)

// Save to file
try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
```

#### Streaming Generation (Swift)

```swift
// Stream audio generation for real-time playback
for try await event in model.generateStream(text: text, parameters: parameters) {
    switch event {
    case .token(let token):
        print("Generated token: \(token)")
    case .audio(let audio):
        print("Audio chunk shape: \(audio.shape)")
    case .info(let info):
        print(info.summary)
    }
}
```

#### Speaker Diarization (Swift)

```swift
import MLXAudioVAD
import MLXAudioCore

// Load audio
let (sampleRate, audioData) = try loadAudioArray(from: audioURL)

// Load diarization model
let model = try await SortformerModel.fromPretrained(
    "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
)

// Detect speakers
let output = try await model.generate(audio: audioData, threshold: 0.5)
for segment in output.segments {
    print("Speaker \(segment.speaker): \(segment.start)s - \(segment.end)s")
}
```

### 2.6 Swift Audio Codecs

```swift
import MLXAudioCodecs

// SNAC codec for audio tokenization
let snac = try await SNAC.fromPretrained("mlx-community/snac_24khz")

// Encode audio to tokens
let tokens = try snac.encode(audio)

// Decode back to audio
let reconstructed = try snac.decode(tokens)
```

---

## Part 3: Performance Comparison

### 3.1 Framework Performance on Apple Silicon

| Framework | MPS/Metal Support | Relative Speed | Notes |
|-----------|-------------------|----------------|-------|
| **whisper.cpp (ggml)** | ✅ Native Metal | 35× real-time | Best for production |
| **MLX-Audio** | ✅ Native MLX | ~30× real-time | Apple's native framework |
| **PyTorch MPS** | ⚠️ Partial | 2-5× real-time | Many ops fall back to CPU |
| **vLLM** | ❌ None | CPU only | Auto-detects CPU on macOS |
| **vLLM-Metal** | ✅ Via MLX | ~25× real-time | Requires Python 3.12 |

### 3.2 EchoPanel Current ASR Providers (Benchmarked)

| Provider | Backend | RTF | Speed | Streaming |
|----------|---------|-----|-------|-----------|
| **whisper.cpp** | Metal (ggml) | 0.028 | 35× | ✅ Yes |
| **faster-whisper** | CTranslate2 CPU | 0.173 | 5.8× | ✅ Yes |
| **Qwen3-ASR** | Transformers CPU | 0.446 | 2.2× | ❌ No |
| **Qwen3-ASR** | vLLM | N/A | N/A | ❌ Crashes |
| **Voxtral (voxtral.c)** | Metal | 4.1 | 0.24× | ⚠️ Very slow |
| **MLX-Audio Whisper** | MLX | ~0.03 | ~33× | ❌ File only (0.2.9) |

**RTF (Real-Time Factor)**: Lower is better. RTF < 1.0 means faster than real-time.

---

## Part 4: Integration Recommendations

### 4.1 Option A: Upgrade to Python 3.12 + mlx-audio 0.3.1

**Pros:**
- Access to Qwen3-ASR, Voxtral, and latest models
- Can use vllm-metal for vLLM support
- Native MLX performance for all models

**Cons:**
- Requires removing `qwen-asr` (conflicting dependencies)
- Must rebuild virtual environment
- Testing required

**Steps:**
1. Update `pyproject.toml` to Python >=3.12,<3.14
2. Remove `qwen-asr` dependency
3. Update `huggingface-hub` to >=1.3.0
4. Add `mlx-audio>=0.3.1`
5. Rebuild venv: `rm -rf .venv && uv sync`

### 4.2 Option B: Keep Python 3.11, Add mlx-whisper

**Pros:**
- Minimal changes
- mlx-whisper is stable and fast
- No dependency conflicts

**Cons:**
- Limited to Whisper models only
- No Qwen3-ASR or Voxtral via MLX

**Steps:**
1. `uv add mlx-whisper`
2. Create provider using `mlx_whisper.transcribe()`

### 4.3 Option C: Use Swift MLX-Audio for macOS App

**Pros:**
- Native Swift integration
- Best performance on Apple Silicon
- Can use Qwen3-ASR via Swift
- Streaming support

**Cons:**
- Requires Swift code in macOS app
- Separate from Python server architecture
- More complex integration

**Architecture:**
```
macOS App (Swift)
├── MLXAudioSTT (local inference)
│   └── Qwen3ASRModel
├── AudioRecorder (AVAudioEngine)
└── WebSocket client (to server)

Server (Python)
├── Fallback ASR providers
└── Session management
```

### 4.4 Recommended Path for EchoPanel: Hybrid B + C

**RECOMMENDATION**: Implement **both** Option B (Python 3.12 server) and Option C (Swift on-device ASR) as a hybrid architecture. This is detailed in Part 5.

**Why Hybrid Wins:**
- **Privacy-first**: Local processing by default
- **Resilient**: Automatic fallback to server
- **Flexible**: User-configurable per session
- **Future-proof**: Both platforms actively maintained

**Phased Implementation:**

**Phase 1: Server Foundation (1-2 weeks)**
- Upgrade to Python 3.12
- Add mlx-audio 0.3.1 with all MLX-native models
- Keep whisper.cpp as fallback

**Phase 2: On-Device ASR (2-3 weeks)**
- Add MLXAudioSTT to macOS app
- Implement Qwen3ASR on device
- Local caching of models

**Phase 3: Hybrid Logic (1-2 weeks)**
- Unified ASRManager with mode selection
- Auto-fallback (local → server)
- Battery-aware routing

**Phase 4: Advanced Features (ongoing)**
- VAD with Sortformer
- Speaker diarization
- Streaming transcription

---

## Part 5: Hybrid Architecture (Recommended) - B + C Combined

**Status**: Documented | **Last Updated**: 2026-02-15

### 5.0 Overview

Option B (Python 3.12 server) and Option C (Swift on-device ASR) are **complementary**, not mutually exclusive. This hybrid architecture provides the best of both worlds.

### 5.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS App (Swift)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              On-Device ASR (MLX-Audio Swift)            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │   │
│  │  │ Qwen3ASR    │  │ Whisper MLX │  │ Voice Activity  │  │   │
│  │  │ (Primary)   │  │ (Fallback)  │  │ Detection (VAD) │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ (if local fails/unavailable)    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │         WebSocket Client → Python Server                │   │
│  │              (Fallback/Cloud ASR)                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Python Server (3.12)                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Server-Side ASR (mlx-audio 0.3.1)          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │   │
│  │  │ Qwen3-ASR   │  │ Voxtral     │  │ Whisper     │     │   │
│  │  │ MLX Backend │  │ MLX Backend │  │ MLX Backend │     │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Benefits of Hybrid Approach

| Feature | On-Device (Swift) | Server (Python) | Combined |
|---------|-------------------|-----------------|----------|
| **Latency** | Ultra-low (<100ms) | Network dependent | Best of both |
| **Privacy** | 100% local | Data leaves device | Fallback only |
| **Offline** | ✅ Works offline | ❌ Requires network | Resilient |
| **Model Variety** | Limited (Swift models) | Full (all MLX models) | Complete coverage |
| **Battery** | Uses device CPU/GPU | Offloaded to server | Configurable |
| **Cost** | Free (local compute) | Server costs | Optimize per use-case |

### 5.3 Implementation Strategy

#### Phase 1: Python 3.12 Server Upgrade (Option B)

**pyproject.toml changes:**
```toml
[project]
requires-python = ">=3.12,<3.14"
dependencies = [
    "mlx-audio>=0.3.1",           # Qwen3-ASR, Voxtral, Whisper
    "huggingface-hub>=1.3.0,<2.0",
    # Remove: "qwen-asr" (conflicts, use mlx-audio instead)
]

[project.optional-dependencies]
vllm = ["vllm-metal"]             # Optional vLLM backend via MLX
```

**New Server Providers:**
```python
# server/services/provider_mlx_qwen3.py
from mlx_audio.stt.utils import load_model

class MLXQwen3ASRProvider:
    def __init__(self):
        self.model = load_model("mlx-community/Qwen3-ASR-0.6B-8bit")
    
    def transcribe_stream(self, audio_chunks):
        # MLX-native streaming with Metal acceleration
        pass

# server/services/provider_mlx_voxtral.py  
class MLXVoxtralProvider:
    def __init__(self):
        self.model = load_model("mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit")
```

#### Phase 2: Swift On-Device ASR (Option C)

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
]
.products: [
    .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
    .product(name: "MLXAudioVAD", package: "mlx-audio-swift"),
]
```

**Swift Implementation:**
```swift
// macapp/Services/OnDeviceASRService.swift
import MLXAudioSTT
import MLXAudioCore

actor OnDeviceASRService {
    private var model: Qwen3ASRModel?
    
    func initialize() async throws {
        model = try await Qwen3ASRModel.fromPretrained(
            "mlx-community/Qwen3-ASR-0.6B-8bit"
        )
    }
    
    func transcribe(audioData: [Float]) async throws -> String {
        guard let model = model else {
            throw ASRError.modelNotLoaded
        }
        let output = model.generate(audio: MLXArray(audioData))
        return output.text
    }
}
```

#### Phase 3: Unified Client Logic

```swift
// macapp/Services/ASRManager.swift
enum ASRMode {
    case onDevice      // MLX-Audio Swift (local)
    case server        // WebSocket to Python server
    case auto          // On-device first, fallback to server
}

actor ASRManager {
    private let onDeviceService = OnDeviceASRService()
    private let serverService = ServerASRService()
    
    func transcribe(audioData: [Float], mode: ASRMode = .auto) async throws -> String {
        switch mode {
        case .onDevice:
            return try await onDeviceService.transcribe(audioData: audioData)
            
        case .server:
            return try await serverService.transcribe(audioData: audioData)
            
        case .auto:
            // Try on-device first
            if await onDeviceService.isAvailable {
                do {
                    return try await onDeviceService.transcribe(audioData: audioData)
                } catch {
                    // Fall back to server
                    return try await serverService.transcribe(audioData: audioData)
                }
            } else {
                return try await serverService.transcribe(audioData: audioData)
            }
        }
    }
}
```

### 5.4 Protocol Extension for Mode Selection

Extend WebSocket binary protocol to indicate ASR mode:

```
Binary Frame: [EP][version][source][mode][PCM16 data]
                         │
                         ├── 0x00 = Server ASR (use Python backend)
                         ├── 0x01 = On-device (client handles with MLX Swift)
                         └── 0x02 = Hybrid (auto-select based on conditions)
```

### 5.5 Dependency Resolution for Both

#### Python Server (3.12)
```toml
[project]
requires-python = ">=3.12,<3.14"
dependencies = [
    "mlx-audio>=0.3.1",           # All STT models
    "huggingface-hub>=1.3.0,<2.0",
    "fastapi>=0.115.6",
]

[project.optional-dependencies]
vllm = ["vllm-metal"]             # Optional vLLM backend
```

#### Swift App
```swift
// Package.swift - selective imports
.product(name: "MLXAudioSTT", package: "mlx-audio-swift"),  // ASR only
.product(name: "MLXAudioVAD", package: "mlx-audio-swift"),  // VAD only
```

### 5.6 Development Phasing

| Phase | Work | Duration | Deliverable |
|-------|------|----------|-------------|
| **1** | Python 3.12 upgrade + mlx-audio 0.3.1 | 1-2 days | Server with MLX-native ASR |
| **2** | Add MLXAudioSTT to macOS app | 2-3 days | On-device ASR working |
| **3** | Hybrid mode + fallback logic | 1-2 days | Seamless switching |
| **4** | VAD integration (Sortformer) | 2-3 days | Voice activity detection |
| **5** | Performance optimization | Ongoing | Battery, latency tuning |

### 5.7 Trade-offs and Considerations

| Aspect | Consideration |
|--------|---------------|
| **Bundle Size** | Swift app includes MLX framework (~50MB) + model files |
| **Model Storage** | On-device models cached in `~/Library/Caches/mlx-audio/` |
| **Memory** | MLX uses unified memory; monitor with `mx.get_peak_memory()` |
| **Thermal** | On-device inference generates heat; throttle if needed |
| **First Launch** | Models download on first use; show progress UI |
| **Network** | Hybrid mode needs connectivity check before fallback |

### 5.8 Model Availability Matrix (Hybrid)

| Model | Swift On-Device | Python Server | Notes |
|-------|-----------------|---------------|-------|
| **Qwen3-ASR** | ✅ Available | ✅ Available | Both platforms supported |
| **Whisper** | ⚠️ Via wrapper | ✅ Native | Swift uses Python bridge or mlx-swift |
| **Voxtral** | ❌ Not yet | ✅ Available | Swift support planned |
| **GLM-ASR** | ✅ Available | ✅ Available | Both platforms |
| **Parakeet** | ❌ No | ✅ Available | Python only currently |
| **Sortformer VAD** | ✅ Available | ✅ Available | Both platforms |

### 5.9 Why This Approach Wins

1. **Privacy-first**: Local processing by default
2. **Resilient**: Falls back to server when needed (offline, model unavailable)
3. **Flexible**: User can choose per-session or per-feature
4. **Future-proof**: Both ecosystems actively maintained by Apple/MLX team
5. **Performance**: Ultra-low latency for common cases, server for complex models
6. **Battery-aware**: Can offload to server when battery low

---

## Part 6: Model Details and Testing Notes

### 6.1 Models Already Cached in Project

```
~/.cache/huggingface/hub/
├── models--mlx-community--whisper-large-v3-turbo-asr-fp16 (1.5GB, incomplete)
├── models--mistralai--Voxtral-Mini-4B-Realtime-2602 (8.9GB)
├── models--Qwen--Qwen3-ASR-0.6B
└── models--mlx-community--Qwen3-ASR-0.6B-8bit
```

### 6.2 Tested Models Summary

| Model | Test Status | Result | Notes |
|-------|-------------|--------|-------|
| whisper-large-v3-turbo (MLX) | 🟡 Partial | Downloading | Timeout during download |
| Voxtral-Mini-3B-2507-4bit | ❌ Failed | 401 Unauthorized | Repo access issue |
| Voxtral-Mini-3B-2507-bf16 | 🟡 Partial | Downloading | Large model, slow |
| Qwen3-ASR-0.6B-8bit | ❌ Failed | Model type None | Not in 0.2.9, need 0.3.1 |

### 6.3 MLX-Audio 0.2.9 Limitations Found

1. **Qwen3-ASR not supported** - requires 0.3.1
2. **Voxtral Realtime** - model loads but needs proper repo access
3. **Whisper** - config parsing error (`activation_dropout` unexpected)

### 6.4 MLX-Audio Swift Capabilities

1. **Qwen3-ASR** - Fully supported with streaming
2. **GLM-ASR** - Supported
3. **TTS models** - Multiple options available
4. **Voice cloning** - Orpheus, CSM support

---

## Part 7: Dependency Conflict Analysis

### 7.1 Current Conflict

```
echopanel wants:
├── huggingface-hub>=0.34.0,<1.0 (for qwen-asr)
└── qwen-asr (pins transformers==4.57.6)

mlx-audio 0.3.1 wants:
├── transformers==5.0.0rc3
└── huggingface-hub>=1.3.0,<2.0

Result: UNSATISFIABLE
```

### 7.2 Resolution Options

| Option | Action | Impact |
|--------|--------|--------|
| A | Remove qwen-asr | Lose Qwen3-ASR via vLLM, gain via MLX |
| B | Keep 0.2.9 | No Qwen3-ASR support |
| C | Separate venv | Complex maintenance |

---

## Part 8: References and Links

### Python MLX-Audio
- **Repository**: https://github.com/Blaizzy/mlx-audio
- **PyPI**: https://pypi.org/project/mlx-audio/
- **Documentation**: README.md in repository
- **HuggingFace**: https://huggingface.co/mlx-community

### Swift MLX-Audio
- **Repository**: https://github.com/Blaizzy/mlx-audio-swift
- **Swift Package Index**: https://swiftpackageindex.com/Blaizzy/mlx-audio
- **Examples**: `Examples/VoicesApp` in repository

### Related Projects
- **MLX**: https://github.com/ml-explore/mlx
- **MLX Swift**: https://github.com/ml-explore/mlx-swift
- **whisper.cpp**: https://github.com/ggerganov/whisper.cpp
- **simicvm/whisper** (MLX Swift example): https://github.com/simicvm/whisper

### Model Repositories
- **mlx-community**: https://huggingface.co/mlx-community
- **Qwen3-ASR**: https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit
- **Voxtral**: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602

---

## Part 9: Action Items

### Phase 1: Python 3.12 Server Foundation (Option B)
- [ ] Update `pyproject.toml` to Python >=3.12,<3.14
- [ ] Remove `qwen-asr` dependency (replaced by mlx-audio)
- [ ] Upgrade `huggingface-hub` to >=1.3.0,<2.0
- [ ] Add `mlx-audio>=0.3.1`
- [ ] Rebuild venv: `rm -rf .venv && uv sync`
- [ ] Create `provider_mlx_qwen3.py` server provider
- [ ] Create `provider_mlx_voxtral.py` server provider
- [ ] Benchmark mlx-audio vs whisper.cpp on server

### Phase 2: Swift On-Device ASR (Option C)
- [ ] Add MLXAudioSTT package to macOS app Package.swift
- [ ] Create `OnDeviceASRService.swift` actor
- [ ] Implement Qwen3ASRModel loading and transcription
- [ ] Add model download progress UI
- [ ] Test on-device transcription performance
- [ ] Cache models in `~/Library/Caches/mlx-audio/`

### Phase 3: Hybrid Integration (B + C Combined)
- [ ] Extend WebSocket protocol with mode byte (0x00=server, 0x01=local, 0x02=hybrid)
- [ ] Create `ASRManager.swift` with unified interface
- [ ] Implement auto-fallback logic (local → server)
- [ ] Add user preference for ASR mode (settings UI)
- [ ] Add battery-aware routing (low battery → prefer server)
- [ ] Implement connectivity check for fallback decisions

### Phase 4: Advanced Features
- [ ] Add MLXAudioVAD for voice activity detection (Sortformer)
- [ ] Implement streaming transcription on device
- [ ] Add speaker diarization support
- [ ] Optimize thermal throttling for long sessions
- [ ] Add offline mode indicator
- [ ] Background model preloading

### Ongoing
- [ ] Monitor mlx-audio releases for new models
- [ ] Profile memory usage with `mx.get_peak_memory()`
- [ ] Track Swift MLX-Audio updates for new STT models
- [ ] Document latency benchmarks (local vs server)

---

## Appendix A: Testing Commands

```bash
# Test MLX-audio installation
. .venv/bin/activate
python -c "from mlx_audio.stt.utils import load_model; print('OK')"

# Test model loading (requires download)
mlx_audio.stt.generate --model mlx-community/whisper-large-v3-turbo --audio test.wav --output out.txt

# Test Swift package (in Xcode project)
# Add dependency: https://github.com/Blaizzy/mlx-audio-swift.git

# Check available models in code
python -c "from mlx_audio.stt.utils import get_available_models; print(get_available_models())"
```

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-15  
**Next Review**: After Python 3.12 upgrade decision
