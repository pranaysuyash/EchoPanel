# Comprehensive Audio AI Model Research Report

**Date**: February 2026  
**Scope**: Local Models, API Services, Browser-Based, Full Audio Landscape  
**Goal**: Identify all audio models for EchoPanel and future speech experiments

---

## Executive Summary

This audit identified **60+ production-ready audio AI models** across **9 major categories**, compiled from official documentation, Hugging Face, GitHub repos, and Twitter/X community research.

### Key Discoveries

1. **Mistral has audio models**: Voxtral family (Mini-3B, Small-24B, Realtime-4B) launched July 2025
2. **Whisper is a family, not one model**: 20+ deployable variants across weights × runtime × quantization
3. **Unified audio-LLMs are displacing pipelines**: gpt-audio, Step-Audio 2 mini, Qwen2-Audio offer 10-100x latency reduction
4. **The smallest viable ASR is Moonshine Tiny**: 27M params, ~50MB, 5-15x faster than Whisper Tiny

### Implementation Priority Summary

| Priority | Model | Size | Category | Rationale |
|----------|-------|------|----------|-----------|
| **P0** | faster-whisper base.en | 150MB | ASR | Current default, proven |
| **P0** | Silero VAD | <10MB | VAD | Chunking for streaming |
| **P1** | Voxtral Realtime 4B | ~4GB | Streaming ASR | Sub-200ms latency |
| **P1** | Step-Audio 2 mini | ~2GB | Audio-LLM | End-to-end voice agent |
| **P2** | CLAP | ~500MB | Embeddings | Audio search/retrieval |
| **P2** | Demucs | ~100MB | Enhancement | Source separation |

---

## 1. ASR Models: The Complete Taxonomy

### 1.1 Whisper Ecosystem (Treat as 20+ Models)

**Key Insight**: "Whisper" is not one model—it's a matrix of:
- **Base weights** (tiny → large-v3-turbo)
- **Runtime** (PyTorch, CTranslate2, whisper.cpp, CoreML)
- **Quantization** (fp16, int8, int4, GGUF)
- **Feature forks** (timestamps, alignment, diarization)

#### Base Weights (OpenAI Whisper)

| Model | Params | Download | WER (en) | Languages | Notes |
|-------|--------|----------|----------|-----------|-------|
| tiny | 39M | ~75MB | ~15% | 99 | Fastest |
| tiny.en | 39M | ~75MB | ~12% | English-only | Better for English |
| base | 74M | ~150MB | ~10% | 99 | **Current EchoPanel default** |
| base.en | 74M | ~150MB | ~8% | English-only | Recommended |
| small | 244M | ~500MB | ~6% | 99 | Good balance |
| small.en | 244M | ~500MB | ~5% | English-only | Best small |
| medium | 769M | ~1.5GB | ~4% | 99 | High accuracy |
| medium.en | 769M | ~1.5GB | ~4% | English-only | Production quality |
| large-v2 | 1.55B | ~3GB | ~3% | 99 | Previous best |
| large-v3 | 1.55B | ~3GB | ~2.5% | 99 | Current best |
| large-v3-turbo | 809M | ~1.6GB | ~3% | 99 | Speed-optimized |

#### Production Runtimes (Each is a Separate "Product")

| Runtime | Speed | Platform | Best For |
|---------|-------|----------|----------|
| **faster-whisper** (CTranslate2) | 4x faster | Linux/macOS/Windows | Server batch processing |
| **whisper.cpp** | Near-native | Apple Silicon, CPU | Edge, mobile, real-time |
| **Transformers** | 1x (baseline) | Any | HF ecosystem integration |
| **Whisper JAX** | TPU-optimized | Google Cloud | Massive batch throughput |

#### Feature Forks (Add-on Capabilities)

| Fork | Adds | Use Case |
|------|------|----------|
| **WhisperX** | Word timestamps + speaker diarization | "Who said what when" |
| **stable-ts** | Timestamp stabilization, forced alignment | Professional subtitles |
| **whisper-timestamped** | Alternative word timestamps | Subtitle generation |
| **Distil-Whisper** | Smaller distilled models | Resource-constrained |

**EchoPanel Recommendation**: `faster-whisper base.en` (current) → upgrade path to `faster-whisper large-v3-turbo` with int8 quantization.

---

### 1.2 Mistral Voxtral Family (NEW - July 2025)

**Source**: [mistral.ai](https://mistral.ai), [Hugging Face](https://huggingface.co/mistralai)

| Model | Params | Features | Latency | License |
|-------|--------|----------|---------|---------|
| **Voxtral-Mini-3B** | 3B | Batch transcription, 40min context | Non-streaming | Apache 2.0 |
| **Voxtral-Small-24B** | 24B | High accuracy, summarization | Non-streaming | Apache 2.0 |
| **Voxtral-Mini-4B-Realtime** | 4B | Real-time streaming | <200ms configurable | Apache 2.0 |

**Key Claims**:
- Outperforms Whisper Large-v3+
- 13 languages
- Open-weight, Apache 2.0
- Designed for edge devices

**Verdict**: Voxtral-Mini-4B-Realtime is the top candidate for v0.3 streaming upgrade.

---

### 1.3 Self-Supervised ASR (wav2vec 2.0, HuBERT, WavLM)

| Model | Params | Key Strength | Best For | License |
|-------|--------|--------------|----------|---------|
| **wav2vec 2.0** | 95M-2B | Low-resource adaptation | Fine-tuning with 10min data | MIT |
| **HuBERT** | 95M-1B | Discrete units, speaker ID | Speech synthesis from codes | MIT |
| **WavLM** | 94M-316M | Unified speaker+ASR | Transcription + diarization | MIT |

**When to Use**: Low-resource languages, domain adaptation, research into representations.

---

### 1.4 NVIDIA Parakeet TDT

| Model | Params | WER | RTFx | Notes |
|-------|--------|-----|------|-------|
| Parakeet TDT 0.6B V2 | 600M | 6.05% | 3386x | 3-5x faster than Whisper |
| Parakeet V3 | ~1B | ~5% | — | Best for German |

**Pros**: 3-5x faster than Whisper, NeMo framework  
**Cons**: GPU-focused, complex integration  
**Verdict**: Consider for v0.3 if targeting NVIDIA GPUs.

---

### 1.5 Moonshine Tiny (Edge-Optimized)

| Params | Download | WER | Speed |
|--------|----------|-----|-------|
| 27M | ~50MB | ~10% (better than Whisper Tiny) | 5-15x faster than Whisper |

**Best For**: Truly tiny first-run bundle, edge devices  
**Verdict**: Worth testing as smallest viable ASR.

---

### 1.6 Vosk (Lightweight Offline)

| Model | Download | Memory | WER |
|-------|----------|--------|-----|
| small-en-us-0.15 | 40MB | ~300MB | ~15% |
| en-us-0.22 | 1.8GB | ~4GB | ~8% |
| spk-0.4 (speaker ID) | 13MB | - | - |

**Best For**: Raspberry Pi, IoT, offline without GPU.

---

### 1.7 Chinese Models (Alibaba Qwen, Paraformer)

| Model | Type | Params | Latency | Notes |
|-------|------|--------|---------|-------|
| **Paraformer 2.0** | Non-autoregressive | - | 5-10x faster | Mandarin-optimized |
| **Qwen3-Coder-Next** | Sparse MoE | 80B (3B active) | - | Coding-focused, 256K context |

---

## 2. TTS Models

### 2.1 Local TTS

| Model | Params | Latency | Key Feature | License |
|-------|--------|---------|-------------|---------|
| **CosyVoice2-0.5B** | 0.5B | Real-time CPU | Voice cloning, emotional control | Apache 2.0 |
| **Fish Speech V1.5** | ~1.2B | Real-time GPU | Cross-lingual voice cloning | Apache 2.0 |
| **IndexTTS-2** | Minimized | <100ms | ARM/embedded | Apache 2.0 |
| **Piper** | Varies | Fast | Many voices, on-device | MIT |
| **XTTS (Coqui)** | ~1B | Moderate | Multilingual + cloning | CPML |
| **Bark** | ~1B | Slow | Expressive, sound effects | MIT |
| **StyleTTS2** | ~100M | Fast | High-quality neural TTS | MIT |

### 2.2 Voice Cloning & Conversion

| Model | Type | Use Case |
|-------|------|----------|
| **RVC** | Voice Conversion | "Sound like X" |
| **so-vits-svc** | Singing Voice Conversion | Music covers |
| **OpenVoice** | Voice Cloning | Multi-style cloning |

---

## 3. Audio-Language Models (Unified End-to-End)

> **Key Insight**: These models replace ASR→LLM→TTS pipelines with single-architecture solutions.

| Model | Type | Architecture | Latency | Access | Pricing |
|-------|------|--------------|---------|--------|---------|
| **gpt-audio** (OpenAI) | API | End-to-end unified | Real-time | API | $2.50-20/M tokens |
| **Step-Audio 2 mini** | Local | End-to-end unified | 150ms streaming | Open (Apache 2.0) | Free |
| **Qwen2-Audio** | Local | Audio encoder + LLM | Non-streaming | Apache 2.0 | Free |
| **SALMONN** | Local | Multi-task unified | Non-streaming | Research | Free |
| **Gemma 3n audio** | Local | Speech + translation | Non-streaming | Apache 2.0 | Free |

### Step-Audio 2 mini (Top Open-Source End-to-End)

**Benchmark Performance** (February 2026):
- MMAU: 73.2 (top open-source)
- URO Bench: Leading basic/professional dialogue
- Chinese ASR CER: 3.19%
- English ASR WER: 3.50%
- **Claims to outperform GPT-4o Audio on select benchmarks**

**Availability**: GitHub, Hugging Face, ModelScope

**Verdict**: Best open-source option for unified voice agents.

---

## 4. Speech Translation

### 4.1 Local Speech-to-Text Translation

| Model | Languages | Streaming | Use Case |
|-------|-----------|-----------|----------|
| **Gemma 3n audio** | 100+ spoken | No | Local S2TT |
| **SeamlessM4T v2** | 100+ | Yes (SeamlessStreaming) | S2TT and S2ST |
| **TranslateGemma** | 55 languages | Text-only | Cascaded pipeline |

### 4.2 API Translation

| Service | Streaming | Latency | Pricing |
|---------|-----------|---------|---------|
| **Deepgram Nova-3** | Yes | <300ms | ~$0.0125/min |
| **AssemblyAI** | Yes | ~300ms | ~$0.65/hour |
| **Seamless Streaming** (Meta) | Yes | <200ms | $0.01/1K chars |

---

## 5. Enhancement, Separation, Restoration

| Model | Category | Best For | License |
|-------|----------|----------|---------|
| **Demucs v4** | Source Separation | Music stems, vocal isolation | MIT |
| **DeepFilterNet2** | Noise Suppression | VoIP, real-time | MIT |
| **RNNoise** | Noise Suppression | Ultra-low CPU | BSD |
| **AudioSR** | Super Resolution | Bandwidth extension | Open |
| **SpeechBrain** | Enhancement/Separation | Research toolkit | Apache 2.0 |

---

## 6. Audio Embeddings, Classification, Tagging

| Model | Classes/Dims | Best For | Platform |
|-------|--------------|----------|----------|
| **YAMNet** | 521 AudioSet | Mobile event detection | TensorFlow Lite |
| **VGGish** | 128-dim embeddings | Similarity search | TensorFlow Hub |
| **PANNs (CNN14)** | 527 AudioSet | Tagging, localization | Hugging Face |
| **CLAP** | Text-audio aligned | Zero-shot classification, retrieval | Hugging Face |
| **BEATs** | General embeddings | Transfer learning backbone | GitHub |
| **OpenL3** | Audio-visual | Cross-modal retrieval | GitHub |

---

## 7. Music Generation & Processing

### 7.1 Music Generation

| Model | Control | Access | License |
|-------|---------|--------|---------|
| **MusicGen** | Text prompt | Open (Audiocraft) | MIT |
| **JASCO** | Chord + beat + melody | Open (inference) | MIT |
| **AudioLDM** | Text + style | Open | Open |
| **Stable Audio Open** | Text prompt | Open | Open |
| **Lyria 2 / RealTime** | Text + style | API (Google) | Commercial |

### 7.2 Music Transcription

| Model | Target | Output |
|-------|--------|--------|
| **Basic Pitch** (Spotify) | Polyphonic pitch | Note events |
| **MT3** | Multi-instrument | MIDI + labels |
| **Onsets and Frames** | Piano | Note events |

---

## 8. Neural Audio Codecs

| Model | Bitrate | Quality | Access |
|-------|---------|---------|--------|
| **EnCodec** | 6-24 kbps | High-fidelity | Open (MIT) |
| **SoundStream** | 3-18 kbps | Scalable | API (limited) |
| **Descript DAC** | Variable | High-fidelity | Open |
| **Lyra** | 3 kbps | Ultra-low | Open (limited) |

---

## 9. Audio Forensics & Security

| Model | Approach | Best For |
|-------|----------|----------|
| **AudioSeal** | Watermarking (proactive) | AI provenance |
| **RawNet2** | Raw waveform analysis | Deepfake detection |
| **AASIST** | Graph neural network | Spoof detection |

---

## 10. Bioacoustics & Specialized

| Model | Target | Use Case |
|-------|--------|----------|
| **BirdNET** | 3000+ bird species | Ecological monitoring |
| **DeepSqueak** | Rodent ultrasonic | Neuroscience research |

---

## 11. February 2026 Twitter/X Discoveries

### Major Releases with High Community Buzz

| Model | Org | Release | Key Innovation |
|-------|-----|---------|----------------|
| **Grok 3** | xAI | Feb 2026 | 100K H100s, real-time X integration |
| **Grok 3 Mini** | xAI | Feb 2026 | 70% compute reduction |
| **Qwen3-Coder-Next** | Alibaba | Feb 4, 2026 | 80B params, 3B active (ultra-sparse MoE) |
| **Qwen3-Max-Thinking** | Alibaba | Feb 2026 | Beats "Humanity's Last Exam" |
| **Doubao 2.0** | ByteDance | Mid-Feb 2026 | 163M MAU consumer app |
| **Seedream 5.0** | ByteDance | Feb 2026 | 4K image generation |
| **DeepSeek V4** | DeepSeek | Mid-Feb 2026 | Coding specialist |
| **LongCat-Flash-Thinking** | Meituan | Jan 15, 2026 | 560B MoE, 8 expert modules |
| **Incredible Small 1.0** | Incredible | Feb 2026 | Near-zero hallucination automation |

### Community Sentiment Themes (Twitter/X)

1. **"Perfect size"** enthusiasm for Qwen3-Coder-Next (3B active)
2. **Local deployment** preference over API dependency
3. **Efficiency metrics** (active params, throughput) valued over raw capability
4. **Open-source Apache 2.0** licensing strongly preferred

---

## 12. VAD & Diarization (The Glue Layer)

| Model | Category | Use Case |
|-------|----------|----------|
| **Silero VAD** | Voice Activity Detection | Chunking for streaming |
| **pyannote.audio** | Speaker Diarization | "Who said what" |
| **WhisperX** | Integrated | ASR + timestamps + diarization |

---

## 13. Implementation Roadmap for EchoPanel

### Phase 1: Core ASR (Months 1-2)

| Priority | Model | Capability | Success Criteria |
|----------|-------|------------|------------------|
| P0 | faster-whisper base.en | Baseline ASR | <10% WER clean, <15% noisy |
| P0 | Silero VAD | Streaming chunking | Reliable voice detection |
| P0 | WhisperX (optional) | Diarization glue | Speaker labels working |

### Phase 2: Streaming & Quality Upgrade (Months 3-4)

| Priority | Model | Capability | Criteria |
|----------|-------|------------|----------|
| P1 | Voxtral-Mini-4B-Realtime | Streaming ASR | <200ms latency |
| P1 | faster-whisper large-v3-turbo | Quality upgrade | <5% WER |
| P1 | Step-Audio 2 mini | End-to-end voice agent | Benchmark validation |

### Phase 3: Full Audio Capabilities (Months 5-6)

| Priority | Model | Capability |
|----------|-------|------------|
| P2 | CLAP | Audio search/retrieval |
| P2 | Demucs | Source separation |
| P2 | DeepFilterNet2 | Noise suppression |
| P2 | EnCodec | Neural compression |

---

## 14. Database Schema for Model Tracking

```csv
model_id,family,version,local_or_api,category,tasks_supported,languages,streaming_support,realtime_latency_target_ms,base_weights,runtime,quantization,hardware_reqs,context_or_max_audio,benchmarks,license,pricing,docs_url,community_signal,integration_complexity,known_failure_modes,ideal_use_cases,avoid_when,notes
```

---

## Sources

- [Mistral AI Voxtral](https://mistral.ai)
- [faster-whisper GitHub](https://github.com/SYSTRAN/faster-whisper)
- [whisper.cpp GitHub](https://github.com/ggerganov/whisper.cpp)
- [NVIDIA NeMo Parakeet](https://nvidia.github.io/NeMo)
- [Vosk Models](https://alphacephei.com/vosk/models)
- [Step-Audio 2 mini](https://github.com/stepfun-ai/Step-Audio)
- [Qwen2-Audio](https://github.com/QwenLM/Qwen2-Audio)
- [Deepgram Nova-3](https://deepgram.com)
- [AssemblyAI](https://assemblyai.com)
- [AudioCraft (MusicGen, EnCodec)](https://github.com/facebookresearch/audiocraft)
- [Hugging Face Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard)
- [Silero VAD](https://github.com/snakers4/silero-vad)
- [pyannote.audio](https://github.com/pyannote/pyannote-audio)
- [CLAP](https://github.com/LAION-AI/CLAP)
- [BirdNET](https://github.com/kahst/BirdNET)
- [Twitter/X research (Feb 2026)](https://x.com)
