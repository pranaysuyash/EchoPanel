# Research Report: MLX Ecosystem, Argmax SDK v2, Prince Canuma & HuggingFace Pro

**Date:** February 25, 2026  
**Context:** EchoPanel project — Apple Silicon audio/AI pipeline research

---

## Executive Summary

This report covers the full Apple Silicon ML stack relevant to EchoPanel: Apple's MLX framework and its Swift bindings; Prince Canuma's (`Blaizzy`) MLX-Audio and MLX-Audio-Swift libraries for on-device TTS/STT/STS; Argmax's SDK v2 (WhisperKit + SpeakerKit Pro) for production-grade transcription and diarization; and HuggingFace Pro's serverless inference access to SOTA models alongside the local Transformers v4+ ecosystem. Together, these form a complete, fully-local, Apple-optimized ML audio pipeline that is directly applicable to EchoPanel's architecture.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Apple Silicon (M1–M4)                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    MLX (Array Framework)                        │  │
│  │  Python API  │  C++ API  │  C API  │  Swift API (MLX Swift)    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│         │                                    │                        │
│  ┌──────┴──────┐                    ┌────────┴──────────┐            │
│  │  MLX-LM     │                    │  MLX-Audio Swift  │            │
│  │  (Python)   │                    │  (Swift SDK)      │            │
│  └─────────────┘                    └───────────────────┘            │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                      MLX-Audio (Python)                       │    │
│  │    TTS: Kokoro, Qwen3-TTS, CSM, Dia, Chatterbox              │    │
│  │    STT: Whisper, Qwen3-ASR, Parakeet, Voxtral                │    │
│  │    STS: SAM-Audio, LFM2.5-Audio, MossFormer2-SE              │    │
│  │    VAD: Sortformer v1/v2.1                                    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                 Argmax SDK v2 (Swift/CoreML)                   │    │
│  │    WhisperKit (open-source STT)                               │    │
│  │    WhisperKit Pro (Parakeet v3, faster)                       │    │
│  │    SpeakerKit Pro (Nvidia Sortformer diarization)             │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
           │                                       │
    HuggingFace Hub                     HuggingFace Pro / Serverless
    mlx-community/ models               Inference Providers
```

---

## 1. MLX — Apple's Array Framework

### What It Is

MLX is an open-source array framework for machine learning on Apple Silicon, developed and released by **Apple Machine Learning Research** in December 2023.[^1] It is designed by researchers for researchers, providing both a Python API closely following NumPy, and fully-featured C++, C, and Swift APIs mirroring the same semantics.

### Key Features

| Feature | Description |
|---------|-------------|
| **Unified Memory** | Arrays live in shared memory — no CPU↔GPU transfers needed |
| **Lazy Computation** | Arrays only materialize when required |
| **Dynamic Graph Construction** | No slow recompilation on shape changes |
| **Composable Transforms** | `mx.grad`, `mx.vmap`, `mx.compile` |
| **Multi-device** | CPU and GPU (Metal) on Apple Silicon |
| **CUDA backend** | Linux CUDA support added later |
| **Higher-level APIs** | `mlx.nn` (PyTorch-like), `mlx.optimizers` |

### Installation

```bash
pip install mlx               # macOS Apple Silicon
pip install mlx[cuda]         # Linux CUDA
pip install mlx[cpu]          # Linux CPU-only
```

### Key Sub-Packages

| Package | Purpose | GitHub |
|---------|---------|--------|
| `mlx` | Core array framework | [ml-explore/mlx](https://github.com/ml-explore/mlx) |
| `mlx-lm` | LLM text generation + fine-tuning on Apple Silicon | [ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm) |
| `mlx-examples` | Reference implementations (Whisper, Stable Diffusion, LLaMA, etc.) | [ml-explore/mlx-examples](https://github.com/ml-explore/mlx-examples) |

### MLX-LM (LLM Inference + Fine-tuning)

```bash
pip install mlx-lm
mlx_lm.generate --prompt "How tall is Mt Everest?"
mlx_lm.chat  # interactive REPL
```

Python API:
```python
from mlx_lm import load, generate

model, tokenizer = load("mlx-community/Mistral-7B-Instruct-v0.3-4bit")
text = generate(model, tokenizer, prompt="Write a story about Einstein")
```

Key capabilities[^2]:
- HuggingFace Hub integration (thousands of models in `mlx-community`)
- LoRA and full fine-tuning with quantized models
- Distributed inference/fine-tuning via `mx.distributed`
- Prompt caching for long-context reuse
- Rotating key-value cache for memory management
- Requires macOS 15+ for large model wired memory optimization

---

## 2. MLX Swift

### What It Is

MLX Swift is the official Swift API for MLX, maintained by **David Koski** and the ML-Explore team.[^3] It exposes the full MLX Python feature set in Swift, enabling ML research and deployment directly in Swift/Xcode apps — for macOS, iOS, and more.

### Installation (Swift Package Manager)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.10.0")
]

// Target dependencies
dependencies: [
    .product(name: "MLX", package: "mlx-swift"),
    .product(name: "MLXNN", package: "mlx-swift"),
    .product(name: "MLXOptimizers", package: "mlx-swift")
]
```

> ⚠️ SwiftPM CLI cannot build Metal shaders — must use `xcodebuild` or Xcode IDE.

### Modules

| Module | Purpose |
|--------|---------|
| `MLX` | Core array operations |
| `MLXNN` | Neural network layers |
| `MLXOptimizers` | Gradient-based optimizers |
| `MLXRandom` | Random number generation |

### Key Repos

| Repo | Purpose |
|------|---------|
| [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | Core Swift bindings |
| [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | LLM/VLM implementations |
| [ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) | Example apps (MNISTTrainer, MLXChatExample, LLMEval, StableDiffusion) |

### Community Swift Projects (mlx-community org)

| Repo | Description |
|------|-------------|
| [mlx-community/paddleocr-vl.swift](https://github.com/mlx-community/paddleocr-vl.swift) | Native Swift OCR/doc VLM |
| [mlx-community/speculative-decoding](https://github.com/mlx-community/speculative-decoding) | Fast LLM inference via speculative decoding |
| [mlx-community/nano-reasoning](https://github.com/mlx-community/nano-reasoning) | FastRL port for reasoning models |

---

## 3. MLX-Audio (Python)

### What It Is

[`mlx-audio`](https://github.com/Blaizzy/mlx-audio) is the flagship audio processing library for Apple Silicon, authored by **Prince Canuma** (GitHub: `Blaizzy`). It provides TTS, STT, and STS with quantization support, an OpenAI-compatible REST API, and a web UI.[^4]

### Installation

```bash
pip install mlx-audio
# Or via uv:
uv tool install --force mlx-audio --prerelease=allow
```

### Supported Models

#### Text-to-Speech (TTS)

| Model | Languages | HuggingFace |
|-------|-----------|-------------|
| **Kokoro** (82M) | EN, JA, ZH, FR, ES, IT, PT, HI | `mlx-community/Kokoro-82M-bf16` |
| **Qwen3-TTS** (1.7B) | ZH, EN, JA, KO, + | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` |
| **CSM** (1B) | EN | `mlx-community/csm-1b` |
| **Dia** (1.6B) | EN (dialogue) | `mlx-community/Dia-1.6B-fp16` |
| **OuteTTS** | EN | `mlx-community/OuteTTS-1.0-0.6B-fp16` |
| **Spark** (0.5B) | EN, ZH | `mlx-community/Spark-TTS-0.5B-bf16` |
| **Chatterbox** | 16 languages | `mlx-community/chatterbox-fp16` |
| **Soprano** (80M) | EN | `mlx-community/Soprano-1.1-80M-bf16` |

#### Speech-to-Text (STT)

| Model | Description |
|-------|-------------|
| **Whisper large-v3 turbo** | 99+ languages, OpenAI's best |
| **Qwen3-ASR** (1.7B) | ZH/EN/JA/KO |
| **Parakeet TDT** | NVIDIA, 25 EU languages |
| **Voxtral Mini** (3B/4B) | Mistral streaming STT |
| **VibeVoice-ASR** | Microsoft 9B, with diarization + timestamps |

#### VAD / Speaker Diarization

| Model | Description |
|-------|-------------|
| **Sortformer v1** | NVIDIA, up to 4 speakers |
| **Sortformer v2.1** | NVIDIA streaming, AOSC compression |

#### Speech-to-Speech (STS)

| Model | Use Case |
|-------|---------|
| **SAM-Audio** | Text-guided source separation |
| **LFM2.5-Audio** (1.5B) | Full speech-to-speech |
| **MossFormer2 SE** | Speech enhancement / noise removal |

### Quick Python Usage

```python
from mlx_audio.tts.utils import load_model

model = load_model("mlx-community/Kokoro-82M-bf16")
for result in model.generate("Hello from MLX-Audio!", voice="af_heart"):
    print(f"Generated {result.audio.shape[0]} samples")
    # result.audio is mx.array waveform
```

### OpenAI-Compatible API Server

```bash
mlx_audio.server --host 0.0.0.0 --port 8000

# TTS:
curl -X POST http://localhost:8000/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model": "mlx-community/Kokoro-82M-bf16", "input": "Hello!", "voice": "af_heart"}' \
  --output speech.wav

# STT:
curl -X POST http://localhost:8000/v1/audio/transcriptions \
  -F "file=@audio.wav" \
  -F "model=mlx-community/whisper-large-v3-turbo-asr-fp16"
```

### Quantization / Model Conversion

```bash
python -m mlx_audio.convert \
    --hf-path prince-canuma/Kokoro-82M \
    --mlx-path ./Kokoro-82M-4bit \
    --quantize \
    --q-bits 4 \
    --upload-repo username/Kokoro-82M-4bit
```

Supported quantization bits: 3, 4, 6, 8.

### Requirements

- Python 3.10+
- Apple Silicon Mac (M1/M2/M3/M4)
- MLX framework
- ffmpeg (for MP3/FLAC encoding)

---

## 4. MLX-Audio Swift

### What It Is

[`mlx-audio-swift`](https://github.com/Blaizzy/mlx-audio-swift) is a **modular Swift SDK** for audio processing on Apple Silicon, also authored by Prince Canuma. It wraps `MLX Swift` and `swift-transformers` to expose TTS, STT, STS, and VAD models in idiomatic Swift.[^5]

### Platform Requirements

- macOS 14+ or iOS 17+
- Apple Silicon (M1+) recommended
- Xcode 15+, Swift 5.9+

### Modular Architecture

```swift
// Import only what you need (reduces app binary size)
import MLXAudioCore     // Base types, protocols, utilities
import MLXAudioTTS      // Text-to-Speech models
import MLXAudioSTT      // Speech-to-Text models
import MLXAudioSTS      // Speech-to-Speech models
import MLXAudioVAD      // VAD & Speaker Diarization
import MLXAudioCodecs   // SNAC, Encodec, Vocos, Mimi, DACVAE
import MLXAudioUI       // SwiftUI components
```

### Installation (SPM)

```swift
dependencies: [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
]
```

### Quick Start Examples

**TTS:**
```swift
import MLXAudioTTS
import MLXAudioCore

let model = try await SopranoModel.fromPretrained("mlx-community/Soprano-80M-bf16")
let audio = try await model.generate(
    text: "Hello from MLX Audio Swift!",
    parameters: GenerateParameters(maxTokens: 200, temperature: 0.7, topP: 0.95)
)
try saveAudioArray(audio, sampleRate: Double(model.sampleRate), to: outputURL)
```

**STT:**
```swift
import MLXAudioSTT
import MLXAudioCore

let (sampleRate, audioData) = try loadAudioArray(from: audioURL)
let model = try await GLMASRModel.fromPretrained("mlx-community/GLM-ASR-Nano-2512-4bit")
let output = model.generate(audio: audioData)
print(output.text)
```

**Speaker Diarization:**
```swift
import MLXAudioVAD
import MLXAudioCore

let model = try await SortformerModel.fromPretrained(
    "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
)
let output = try await model.generate(audio: audioData, threshold: 0.5)
for segment in output.segments {
    print("Speaker \(segment.speaker): \(segment.start)s - \(segment.end)s")
}
```

**Streaming:**
```swift
for try await event in model.generateStream(text: text, parameters: parameters) {
    switch event {
    case .token(let token): print("Token: \(token)")
    case .audio(let audio): print("Audio shape: \(audio.shape)")
    case .info(let info):   print(info.summary)
    }
}
```

### Supported Models in Swift SDK

**TTS Models:**
| Model | HuggingFace |
|-------|-------------|
| Qwen3-TTS | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` |
| Soprano | `mlx-community/Soprano-80M-bf16` |
| VyvoTTS | `mlx-community/VyvoTTS-EN-Beta-4bit` |
| Orpheus (3B) | `mlx-community/orpheus-3b-0.1-ft-bf16` |
| Marvis TTS | `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit` |
| Pocket TTS | `mlx-community/pocket-tts` |

**STT Models:**
| Model | HuggingFace |
|-------|-------------|
| Qwen3-ASR | `mlx-community/Qwen3-ASR-1.7B-bf16` |
| Voxtral Realtime | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` |
| Parakeet TDT | `mlx-community/parakeet-tdt-0.6b-v3` |
| GLMASR | `mlx-community/GLM-ASR-Nano-2512-4bit` |

**VAD/Diarization:**
| Model | HuggingFace |
|-------|-------------|
| Sortformer streaming | `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16` |
| SmartTurn | `mlx-community/smart-turn-v3` |

---

## 5. Prince Canuma (Blaizzy)

### Who He Is

Prince Canuma is an ML engineer and open-source developer who has become one of the **central contributors to the Apple MLX ecosystem**, particularly for audio AI. He is the primary author and maintainer of both `mlx-audio` (Python) and `mlx-audio-swift` (Swift SDK).[^6]

### Online Presence

| Platform | URL |
|----------|-----|
| **GitHub** | [github.com/Blaizzy](https://github.com/Blaizzy) |
| **HuggingFace** | [huggingface.co/prince-canuma](https://huggingface.co/prince-canuma) |
| **HF Community Org** | [huggingface.co/mlx-community](https://huggingface.co/mlx-community) |
| **YouTube** | [youtube.com/@princecanuma](https://www.youtube.com/@princecanuma) |
| **TWIML Podcast** | [twimlai.com/podcast/twimlai/multimodal-ai-models-on-apple-silicon-with-mlx/](https://twimlai.com/podcast/twimlai/multimodal-ai-models-on-apple-silicon-with-mlx/) |

### Key Repositories

| Repo | Stars | Description |
|------|-------|-------------|
| [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) | 6,064 | Python TTS/STT/STS for Apple Silicon |
| [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | 360 | Modular Swift SDK |
| [Blaizzy/mlx-vlm](https://github.com/Blaizzy/mlx-vlm) | — | Vision-Language Models for MLX |

### HuggingFace `mlx-community` Organization

Prince Canuma maintains (and contributes to) the [`mlx-community`](https://huggingface.co/mlx-community) HuggingFace organization, which hosts quantized/converted versions of SOTA models in MLX format. This is the primary source for ready-to-use MLX models (Kokoro, Whisper, Qwen3, Parakeet, Orpheus, etc.).

---

## 6. Argmax SDK v2

### Company Overview

[Argmax Inc.](https://www.argmaxinc.com) (takeargmax.com) builds on-device AI inference frameworks optimized for Apple Silicon and Android. Their open-source foundation is **WhisperKit**; their commercial offering is the **Argmax Pro SDK** (v2).

### WhisperKit (Open Source)

[WhisperKit](https://github.com/argmaxinc/WhisperKit) is Argmax's Swift framework for deploying Whisper-class STT on-device.[^7]

**Features:**
- Real-time streaming transcription
- Word-level timestamps
- Voice activity detection
- Multi-language support
- Local OpenAI-compatible server (`whisperkit-cli serve`)
- TestFlight demo app available
- Android port: [argmaxinc/WhisperKitAndroid](https://github.com/argmaxinc/WhisperKitAndroid)

**Installation:**
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]
```

```bash
# Homebrew CLI
brew install whisperkit-cli
```

**Quick Start:**
```swift
import WhisperKit

Task {
    let pipe = try? await WhisperKit()
    let transcription = try? await pipe!.transcribe(audioPath: "path/to/audio.wav")?.text
    print(transcription)
}
```

**Local Server (Deepgram-compatible WebSocket):**
```bash
BUILD_ALL=1 swift run whisperkit-cli serve --host 0.0.0.0 --port 8080
```

OpenAI-compatible endpoints:
- `POST /v1/audio/transcriptions`
- `POST /v1/audio/translations`

### Argmax Pro SDK (SDK v2)

**General Availability:** February 2026 (Early access: December 17, 2025).[^8]

**Components:**

| Component | Description |
|-----------|-------------|
| **WhisperKit Pro** | Industry-leading on-device STT (Nvidia Parakeet v2/v3, 9x faster, higher accuracy than cloud APIs) |
| **SpeakerKit Pro** | Real-time speaker diarization with Nvidia Sortformer + pyannoteAI's flagship model |
| **Local Server** | Deepgram-compatible WebSocket server for non-Swift integrations |

**Swift Init:**
```swift
import Argmax

await ArgmaxSDK.with(ArgmaxConfig(apiKey: "YOUR_API_KEY"))
let config = WhisperKitProConfig(
    model: "large-v3-v20240930",
    modelRepo: "argmaxinc/whisperkit-pro",
    modelToken: "YOUR_HUGGINGFACE_TOKEN"
)
let whisperKitPro = try await WhisperKitPro(config)
let transcript = try? await whisperKitPro.transcribe(audioPath: "audio.m4a").text
```

**Supported Platforms:**
- macOS 14+ (M1+)
- iOS 17+ (A14+)
- iPadOS 17+ (A14 or M1+)

**Key Improvements in v2:**
- Nvidia Parakeet v3 STT: outperforms Whisper large-v3 in speed and accuracy
- Nvidia Sortformer for real-time speaker diarization surpassing Deepgram, AssemblyAI
- pyannoteAI's flagship diarization model integrated
- Models compressed to ~0.4 GB for local deployment
- SpeakerKit (pyannote 4 engine) open-sourced alongside v2

**Access:** 14-day trial at [app.argmaxinc.com](https://app.argmaxinc.com) | Early access: early-access@argmaxinc.com

**Documentation:** [app.argmaxinc.com/docs](https://app.argmaxinc.com/docs)

---

## 7. HuggingFace Pro — SOTA Models & Local Inference

### Pro Subscription Benefits

HuggingFace Pro ($20+/month) gives you[^9]:

1. **Serverless Inference API** — direct HTTP endpoint access to a curated list of SOTA models
2. **Higher rate limits** vs. free tier
3. **Gated model access** — automatic approval for many gated/restricted models (Llama 3, Mixtral, etc.)
4. **ZeroGPU priority** — priority compute allocation on Spaces
5. **Inference Providers** — unified access to 15+ compute backends

### Inference Providers (2025)

As of 2025, HuggingFace has shifted from "Inference API" to a unified **Inference Providers** system:

| Provider | Type |
|----------|------|
| Fal | Image/video gen |
| Replicate | General models |
| Sambanova | LLM inference |
| Together AI | LLM/multimodal |
| Fireworks | Fast LLM |
| Groq | Ultra-fast LLM (LPU) |
| Nscale | GPU cloud |
| Hyperbolic | LLM inference |
| Novita | Gen AI |
| Scaleway | EU-based cloud |
| Cerebras | Wafer-scale inference |
| OVHcloud | EU sovereignty |
| HF Inference | Native HF endpoint |

### Gated Model Access

Models requiring gated access (agree to terms → approval):

**LLMs:**
- Meta Llama 3 (8B, 70B) Instruct
- Llama 2 Chat (7B, 13B, 70B)
- Code Llama (7B–70B)
- Mistral/Mixtral 8x7B
- Nous Hermes 2, OpenHermes

**Multimodal:**
- Stable Diffusion XL (SDXL)
- Various VLMs

**Audio:**
- Bark (Suno TTS)
- Some Qwen audio models

### Local Inference with Transformers v4+

The `transformers` library (currently v4.x, transitioning to v5 in 2026) supports full local inference[^10]:

```bash
pip install transformers
```

```python
from transformers import pipeline

# ASR locally
asr = pipeline("automatic-speech-recognition", model="openai/whisper-large-v3")
result = asr("audio.wav")

# LLM locally
generator = pipeline("text-generation", model="meta-llama/Llama-3.2-3B-Instruct")
```

**Local Model Saving:**
```python
model.save_pretrained("./my_local_model")
tokenizer.save_pretrained("./my_local_model")
# Later:
model = AutoModel.from_pretrained("./my_local_model")
```

**MLX Backend in Transformers:**

The `transformers` ecosystem also supports MLX as a backend:

```python
# Use MLX-optimized model loading
from mlx_lm import load, generate
model, tokenizer = load("meta-llama/Llama-3.2-3B-Instruct")
```

### Key SOTA Models Available Locally (via HF + Transformers)

| Domain | Model | Notes |
|--------|-------|-------|
| LLM | Llama 3.3 70B Instruct | Gated, Pro auto-approved |
| LLM | Qwen 2.5 72B | Open access |
| LLM | Mistral 7B v0.3 | Open access |
| LLM | DeepSeek R1 | Open access |
| STT | Whisper large-v3 turbo | Open access |
| STT | Qwen3-ASR 1.7B | Open access |
| STT | Nvidia Parakeet v3 | Open access |
| TTS | Kokoro 82M | Open access |
| TTS | Qwen3-TTS 1.7B | Open access |
| VLM | Qwen2.5-VL 7B | Open access |
| VLM | LLaVA-1.5 13B | Open access |
| Embedding | nomic-embed-text | Open access |

### MLX Community on HuggingFace

The [mlx-community](https://huggingface.co/mlx-community) organization (maintained largely by Prince Canuma and community contributors) hosts **thousands of pre-converted, quantized MLX models** ready for Apple Silicon:

- `mlx-community/Llama-3.2-3B-Instruct-4bit` (default for mlx-lm)
- `mlx-community/Kokoro-82M-bf16`
- `mlx-community/whisper-large-v3-turbo-asr-fp16`
- `mlx-community/Qwen3-ASR-1.7B-8bit`
- `mlx-community/parakeet-tdt-0.6b-v3`
- + thousands more

---

## 8. Relevance to EchoPanel

Based on the EchoPanel project structure (macOS menu bar app, local FastAPI backend, audio pipeline), here's how each component maps:

| EchoPanel Component | Recommended Tool | Notes |
|--------------------|-----------------|-------|
| **Real-time STT** | `mlx-audio` (Qwen3-ASR / Parakeet) | Python FastAPI backend |
| **High-accuracy transcription** | WhisperKit Pro (Argmax SDK v2) | Swift macOS app layer |
| **Speaker diarization** | SpeakerKit Pro OR mlx-audio Sortformer v2.1 | Both use Nvidia Sortformer |
| **TTS response** | `mlx-audio-swift` MLXAudioTTS | Native macOS/iOS Swift |
| **LLM inference** | `mlx-lm` | Local, zero cloud cost |
| **Model source** | `mlx-community` on HuggingFace | Pre-quantized, ready |
| **Gated model access** | HuggingFace Pro | Llama 3+, auto-approved |

---

## Key Repositories Summary

| Repository | Purpose | Stars |
|-----------|---------|-------|
| [ml-explore/mlx](https://github.com/ml-explore/mlx) | Core MLX array framework (Python/C++/C) | — |
| [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | Swift bindings for MLX | — |
| [ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm) | LLM inference + fine-tuning (Python) | — |
| [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | Swift LLM/VLM implementations | — |
| [ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) | MNISTTrainer, Chat, LLMEval, StableDiffusion | — |
| [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) | TTS/STT/STS Python library | 6,064 ⭐ |
| [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | Modular Swift audio SDK | 360 ⭐ |
| [Blaizzy/mlx-vlm](https://github.com/Blaizzy/mlx-vlm) | Vision-Language Models for MLX | — |
| [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) | On-device STT (Swift/CoreML) | — |
| [argmaxinc/WhisperKitAndroid](https://github.com/argmaxinc/WhisperKitAndroid) | Android port | — |
| [huggingface/transformers](https://github.com/huggingface/transformers) | SOTA ML library (v4+/v5) | — |

---

## Confidence Assessment

| Claim | Confidence | Basis |
|-------|-----------|-------|
| MLX framework features and APIs | **High** | Verified from ml-explore/mlx README[^1] |
| MLX-LM capabilities | **High** | Verified from ml-explore/mlx-lm README[^2] |
| MLX Swift installation and modules | **High** | Verified from ml-explore/mlx-swift README[^3] |
| MLX-Audio model support table | **High** | Verified from Blaizzy/mlx-audio README[^4] |
| MLX-Audio Swift architecture | **High** | Verified from Blaizzy/mlx-audio-swift README[^5] |
| Prince Canuma identity (=Blaizzy) | **High** | Citation in mlx-audio README + web sources[^6] |
| Argmax SDK v2 features | **High** | Web search confirmed, WhisperKit README cross-referenced[^7][^8] |
| Argmax v2 GA date (Feb 2026) | **Medium-High** | Web search result, not directly confirmed from GitHub |
| HuggingFace Pro model list | **Medium** | Web search, model availability changes frequently[^9] |
| Transformers v4 local inference | **High** | Documented, well-established[^10] |

---

## Footnotes

[^1]: `ml-explore/mlx` README — [github.com/ml-explore/mlx](https://github.com/ml-explore/mlx) — MLX framework features and design philosophy
[^2]: `ml-explore/mlx-lm` README — [github.com/ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm) — LLM generation, LoRA, distributed inference
[^3]: `ml-explore/mlx-swift` README — [github.com/ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) — Swift API, installation, modules
[^4]: `Blaizzy/mlx-audio` README — [github.com/Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) — Full supported model list, API, quantization
[^5]: `Blaizzy/mlx-audio-swift` README — [github.com/Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) — Swift SDK architecture and supported models
[^6]: mlx-audio Citation field (`author = {Canuma, Prince}`); web sources confirming GitHub:`Blaizzy` = Prince Canuma; HF: [huggingface.co/prince-canuma](https://huggingface.co/prince-canuma)
[^7]: `argmaxinc/WhisperKit` README — [github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) — Open-source STT features, local server
[^8]: Argmax SDK 2 Blog — [argmaxinc.com/blog/argmax-sdk-2](https://www.argmaxinc.com/blog/argmax-sdk-2); Argmax Docs — [app.argmaxinc.com/docs](https://app.argmaxinc.com/docs)
[^9]: HuggingFace Inference Providers — [huggingface.co/docs/inference-providers/index](https://huggingface.co/docs/inference-providers/index); Inference for PROs — [huggingface.co/blog/inference-pro](https://huggingface.co/blog/inference-pro)
[^10]: HuggingFace Transformers docs — [huggingface.co/docs/transformers/index](https://huggingface.co/docs/transformers/index)
