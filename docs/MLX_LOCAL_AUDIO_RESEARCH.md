# MLX Swift & Local Audio Model Research
> Research for EchoPanel — February 2026  
> Covers: MLX Swift · MLX Audio Swift · Prince Canuma (Blaizzy) · Argmax SDK v2 · HuggingFace Pro · New local models  
> **Cross-ref:** [v0.3 Implementation Plan](file:///Users/pranay/Projects/EchoPanel/docs/v0.3_IMPLEMENTATION_PLAN.md) · [v0.2 Implementation Plan](file:///Users/pranay/Projects/EchoPanel/docs/IMPLEMENTATION_PLAN_v0.2.md)

---

## 1. MLX & MLX Swift

**MLX** is Apple's open-source ML framework purpose-built for Apple Silicon. It exposes zero-copy unified memory (CPU + GPU share the same buffer), lazy evaluation, and composable function transforms for autodiff and graph optimization. **MLX Swift** wraps the same in a Swift-native API with async/await support.

| Property | Detail |
|---|---|
| Released | Feb 2024 (WWDC 2025 highlighted) |
| Primary audience | ML research & on-device app inference |
| Platforms | macOS, iOS, iPadOS, visionOS (Apple Silicon required) |
| GitHub | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) |
| Swift version | 5.9+ |
| Key wins for EchoPanel | Zero-copy audio buffers, Metal GPU acceleration, unified memory = no tensor copies between captures |

**What it gives you that CoreML doesn't:** Full model weight control, fine-tuning/LoRA, Python-parity API, direct HuggingFace Hub download in Swift. CoreML is better for App Store shipping and ANE (Neural Engine) — MLX targets the GPU path primarily.

---

## 2. MLX Audio Swift — `Blaizzy/mlx-audio-swift`

> **"Canuma"** = **Prince Canuma** — the developer's name. GitHub handle: **Blaizzy**. This is the repo the user was referring to.

**Repo:** [github.com/Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)  
**License:** MIT (free, open-source)  
**Swift Package Manager** — add directly to Xcode project  
**HuggingFace integration:** Auto-downloads model weights from `mlx-community` on first use

### Architecture (modular — import only what you need)

```
MLXAudioCore    ← base types, protocols, utilities
MLXAudioCodecs  ← SNAC, Encodec, Vocos
MLXAudioTTS     ← Text-to-Speech
MLXAudioSTT     ← Speech-to-Text (ASR)
MLXAudioSTS     ← Speech-to-Speech
MLXAudioVAD     ← Voice Activity Detection + Speaker Diarization
MLXAudioUI      ← SwiftUI components for audio UIs
```

### Supported Models (as of Feb 2026)

#### 🔊 TTS Models
| Model | HuggingFace slug | Notes |
|---|---|---|
| Qwen3-TTS 0.6B | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` | 10 languages, voice cloning from 3s audio |
| Soprano 80M | `mlx-community/Soprano-80M-bf16` | Ultra-lightweight |
| VyvoTTS | `mlx-community/VyvoTTS-EN-Beta-4bit` | EN, 4-bit quant |
| Orpheus 3B | `mlx-community/orpheus-3b-0.1-ft-bf16` | Highest quality |
| Marvis TTS 250M | `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit` | — |
| Pocket TTS | `mlx-community/pocket-tts` | Tiny, on-device |

#### 🎤 STT / ASR Models
| Model | HuggingFace slug | Notes |
|---|---|---|
| **Qwen3-ASR 1.7B** | `mlx-community/Qwen3-ASR-1.7B-bf16` | **52 languages**, SOTA open-source, Apache 2 |
| Qwen3 ForcedAligner 0.6B | `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` | Word-level timestamps |
| **Voxtral Mini 4B Realtime** | `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` | Realtime mode, Mistral-based |
| **Parakeet TDT v3 0.6B** | `mlx-community/parakeet-tdt-0.6b-v3` | NVIDIA model, ~110x RTF on M4 Pro, 800MB |
| GLM-ASR Nano | `mlx-community/GLM-ASR-Nano-2512-4bit` | 4-bit quant, tiny |

#### 🔄 Speech-to-Speech (STS) Models
| Model | HuggingFace slug |
|---|---|
| LFM2.5 Audio 1.5B | `mlx-community/LFM2.5-Audio-1.5B-6bit` |
| SAM Audio Large | `mlx-community/sam-audio-large-fp16` |
| MossFormer2-SE | `starkdmi/MossFormer2-SE-fp16` |

#### 👥 VAD / Speaker Diarization Models
| Model | HuggingFace slug | Notes |
|---|---|---|
| **Sortformer 4-speaker** | `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16` | **Real-time streaming diarization**, NVIDIA's model |
| SmartTurn v3 | `mlx-community/smart-turn-v3` | Turn detection |

### Quick Start (STT in Swift)

```swift
import MLXAudioSTT

let model = try await STTModel.load("mlx-community/Qwen3-ASR-1.7B-bf16")
let transcription = try await model.transcribe(audioURL: recordingURL)
print(transcription.text)
```

### Quick Start (Speaker Diarization)

```swift
import MLXAudioVAD

let diarizer = try await VADModel.load("mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16")
let segments = try await diarizer.diarize(audioURL: recordingURL)
// segments: [{speaker: "A", t0: 0.0, t1: 3.2}, ...]
```

---

## 3. Argmax SDK v2

Argmax builds on WhisperKit (open-source) and adds a commercial SDK layer with production-grade features.

### Pricing (as of Feb 2026)

| Plan | Price | Min | What's included |
|---|---|---|---|
| **Free** | $0 | — | Open-source WhisperKit, public Discord |
| **Pro** | **$1.33/device/month** | 1,000 licenses ($1,330/mo) | WhisperKit Pro + **SpeakerKit Pro** (diarization) + Parakeet support + private Slack |
| **Enterprise** | Custom | — | All Pro + custom models + implementation support + volume discount |

> **14-day trial:** $14 upfront → 30 Pro device licenses. Unused roll over for 12 months.

### Key SDK v2 Features

- **Real-time speaker diarization** powered by NVIDIA Sortformer (SpeakerKit)
- **NVIDIA Parakeet V3** support (up to 5x faster than WhisperKit)
- **Custom vocabulary** — beats Apple SpeechAnalyzer in keyword accuracy
- **Apple SpeechAnalyzer integration** — fallback to pre-downloaded Apple models while Argmax models download
- **SpeakerKit open-sourced** — based on pyannote 4 (diarization only)
- WhisperKit paper presented at ICML 2025

### vs. MLX Audio Swift

| | Argmax SDK v2 (Pro) | MLX Audio Swift |
|---|---|---|
| Cost | $1.33/device/month | Free (MIT) |
| Diarization | Sortformer real-time ✅ | Sortformer MLX ✅ (same model) |
| ASR models | Parakeet V3, Whisper | Parakeet v3, Qwen3-ASR, Voxtral |
| TTS | ❌ | Qwen3-TTS, Soprano, Orpheus ✅ |
| Infra/support | Commercial SLA | Community |
| Swift SPM | ✅ | ✅ |
| HuggingFace auto-download | via CoreML | ✅ native |

**Verdict for EchoPanel:** For an internal macOS app with one or few devices, **MLX Audio Swift is the better starting point** — same Sortformer diarization model, Parakeet v3, zero cost, MIT license. Argmax Pro only pays off at scale (1,000+ deployed devices) or if you need commercial SLA.

---

## 4. HuggingFace Pro Subscription

**Cost:** $9/month  
**[huggingface.co/pricing](https://huggingface.co/pricing)**

### Benefits relevant to EchoPanel dev

| Feature | Detail |
|---|---|
| **1TB private model storage** | Host custom fine-tuned models privately |
| **Inference Credits** | Use Serverless Inference API for testing (not production) |
| **ZeroGPU priority** | Pre-empt queue on GPU Spaces (great for Qwen3-ASR/TTS demos) |
| **Dev Mode for Spaces** | SSH into Spaces for debugging |
| **Early feature access** | First access to new Hub capabilities |

### Key MLX-compatible models available on HuggingFace (via Pro)

All `mlx-community/` models above are free/public, but Pro gives you priority access + ability to host your own private variants.

**Recommended for EchoPanel exploratory testing via ZeroGPU Spaces:**
- `mlx-community/Qwen3-ASR-1.7B-bf16` (52 languages, SOTA)
- `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` (realtime, Mistral)
- `mlx-community/parakeet-tdt-0.6b-v3` (fastest high-accuracy English)
- `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16` (real-time diarization up to 4 speakers)

**HuggingFace acquired ggml.ai (llama.cpp / whisper.cpp)** in early 2026 — GGUF is now the standard quantized model format, fully supported on HF Hub. This means whisper.cpp-style models are now first-class citizens.

---

## 5. Key New Local Models Breakdown

### For ASR (Speech-to-Text) — EchoPanel's Core Need

| Model | Size | Languages | Speed | Best for |
|---|---|---|---|---|
| **Parakeet TDT v3 0.6B** | 600M | English | ~110x RTF on M4 Pro, 800MB RAM | Best English realtime |
| **Qwen3-ASR 1.7B** | 1.7B | **52 langs** | Fast | Multilingual meetings |
| **Voxtral Mini 4B Realtime** | 4B | Multi | Realtime mode | Mistral audio, high quality |
| GLM-ASR Nano | tiny | EN/CN | Very fast | Ultra-low memory |
| Whisper large-v3-turbo | 809M | 99 langs | Medium | Fallback baseline |

### For Diarization — EchoPanel PR5

| Model | Capability | Notes |
|---|---|---|
| **Sortformer 4spk-v2.1** | **Real-time streaming**, up to 4 speakers | NVIDIA model, MLX port available, used by Argmax Pro |
| pyannote 4 (SpeakerKit) | Offline batch | Open-sourced by Argmax |

### For TTS (if adding voice playback features)

| Model | Size | Notes |
|---|---|---|
| Qwen3-TTS 0.6B | 600M | 10 langs, voice cloning from 3s |
| Soprano 80M | 80M | Tiny, fastest |
| Orpheus 3B | 3B | Highest quality |

---

## 6. v0.3 Stack: RAG, NER, Embeddings & Vision Models

The v0.3 plan (`Evidence-First Memory`) introduces a separate model stack beyond audio. Documented here for completeness.

### Embedding Models (for LanceDB RAG)
| Model | License | Notes |
|---|---|---|
| **BGE-M3** | Apache 2.0 | Multilingual, dense+sparse hybrid, recommended for redistribution |
| **EmbeddingGemma** | Gemma ToS | High-performance local alternative, not for commercial redistribution |

### Synthesis LLMs (Grounded Summarization)
| Model | License | Notes |
|---|---|---|
| **Ministral-3B** | Apache 2.0 | Core default, safe for redistribution |
| **Gemma 3** | Gemma ToS | Multimodal (text+vision), higher quality, non-commercial |

### NER / Entity Extraction
| Model | Notes |
|---|---|
| **GLiNER** | Semantic labels (Decision, Action Item, Risk) — modular interface in `analysis_stream.py` |

### Visual Memory Models (PR-6 / ScreenCaptureKit path)
| Model | Role | Notes |
|---|---|---|
| **Apple Vision Framework** | OCR / object detection | Always-on, zero cost, on-device |
| **LightOnOCR-2-1B** | Document structure extraction | Fast, structured layout understanding |
| **SmolVLM2** | Semantic screen summarization | Small VLM, Apple Silicon optimized |

### Hybrid Search / Vector DB
| Tool | Role |
|---|---|
| **LanceDB** | Local embedded vector DB with hybrid search (dense + sparse), RRF fusion |
| **pyannote 4 / SpeakerKit** | Speaker diarization (open-sourced by Argmax) |

> [!NOTE]
> v0.3 uses **LanceDB** (embedded, Rust, runs fully local) — no external DB server needed. All embeddings stay on-device.

---

## 7. EchoPanel Integration Recommendations

### Immediate Wins (low effort, high value)

1. **Add `mlx-audio-swift` as SPM dep** — replaces Python-based `asr_stream.py` for the mac app's local ASR path
2. **Use `Parakeet TDT v3`** for English meeting ASR — 110x realtime, 800MB, most accurate open-source English model
3. **Use `Sortformer 4spk-v2.1`** for diarization (PR5) — this is literally the same model as Argmax Pro uses, free via MLX Audio Swift
4. **Prototype `Qwen3-ASR-1.7B`** for multilingual support (if needed for non-English meetings)

### Architecture Implication (v0.2 spec alignment)

The current v0.2 plan uses Python backend (`server/services/asr_stream.py`) with `faster-whisper`. The MLX Audio Swift approach enables:

- **Native Swift ASR** (no Python server dependency for core transcription)
- **Lower latency** (no WS round-trip for audio frames)
- **On-device privacy** (audio never leaves the Mac)

**Trade-off:** Python backend still useful for: rolling summary / NER / analysis (LLM calls), cloud ASR fallback, and session management.

**Recommended hybrid:** Swift handles ASR + diarization locally via MLX Audio Swift → sends only transcript text over WS to Python backend for analysis/summarization.

### Argmax SDK v2 — When to Consider

- If EchoPanel goes **commercial** with 1000+ deployments: Argmax Pro at $1.33/device is reasonable
- The 14-day $14 trial is worth running to benchmark Parakeet V3 accuracy vs. the free MLX port
- SpeakerKit (diarization) is now open-sourced — can integrate without the paid SDK

---

## 8. What Was NOT Documented / Open Questions

- [ ] **Voxtral Mini** — is this the right realtime model? Needs benchmark vs Parakeet on M-series
- [ ] **Apple SpeechAnalyzer** (new in macOS Tahoe / iOS 26) — when available, evaluate as free fallback ASR
- [ ] **SmolVLM2 + LightOnOCR** — no MLX Swift bindings confirmed yet; may need Python sidecar for v0.3 PR-6
- [ ] **BGE-M3 MLX port** — confirm `mlx-community/bge-m3` exists and is usable from Swift
- [ ] **GLiNER in Swift** — currently Python-only; needs ONNX or MLX port for full native path
- [ ] **Lisa Pro** — separate paid product by Prince Canuma (~$150 one-time); not relevant to EchoPanel
- [ ] **HF Pro inference credits** — need to check current credit allotment per month for Pro tier

---

## 9. Quick Reference Links

| Resource | URL |
|---|---|
| MLX Swift GitHub | [github.com/ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) |
| MLX Audio Swift (Prince Canuma) | [github.com/Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) |
| mlx-community on HuggingFace | [huggingface.co/mlx-community](https://huggingface.co/mlx-community) |
| Argmax SDK v2 | [argmaxinc.com](https://www.argmaxinc.com) |
| Argmax Pricing | [argmaxinc.com/pricing](https://www.argmaxinc.com/pricing) |
| WhisperKit (free, open-source) | [github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) |
| Qwen3-ASR HF | [huggingface.co/Qwen/Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR) |
| Parakeet TDT v3 MLX | [mlx-community/parakeet-tdt-0.6b-v3](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3) |
| Sortformer MLX | [mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16](https://huggingface.co/mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16) |
| HuggingFace Pro | [huggingface.co/pricing](https://huggingface.co/pricing) |
| LanceDB | [lancedb.com](https://lancedb.com) |
| BGE-M3 | [huggingface.co/BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) |
| GLiNER | [github.com/urchade/GLiNER](https://github.com/urchade/GLiNER) |
| SmolVLM2 | [huggingface.co/HuggingFaceTB/SmolVLM2](https://huggingface.co/HuggingFaceTB/SmolVLM2) |
| EchoPanel v0.3 Plan | [v0.3_IMPLEMENTATION_PLAN.md](file:///Users/pranay/Projects/EchoPanel/docs/v0.3_IMPLEMENTATION_PLAN.md) |
