# Local AI Landscape: Fast / SOTA / Small / Offline Options
> Research for EchoPanel — February 2026  
> Scope: **Runtime-agnostic** — covers all inference stacks, not just MLX  
> Cross-ref: [MLX_LOCAL_AUDIO_RESEARCH.md](./MLX_LOCAL_AUDIO_RESEARCH.md) · [v0.3_IMPLEMENTATION_PLAN.md](./v0.3_IMPLEMENTATION_PLAN.md)

---

## 1. Inference Runtimes — Comparison

These are the execution engines that run models. Choose based on your language, platform, and latency target.

| Runtime | Language | Platform | Best for | Apple Silicon |
|---|---|---|---|---|
| **MLX** | Swift / Python | macOS/iOS only | GPU path, zero-copy unified mem | ✅ Native |
| **whisper.cpp** | C++ (bindings everywhere) | CPU-first, cross-platform | Low VRAM, edge, no GPU needed | ✅ Metal |
| **faster-whisper** (CTranslate2) | Python | CPU + NVIDIA GPU | 2–6x faster than OG Whisper, INT8 | ⚠️ CPU only on Apple |
| **ONNX Runtime** | Python / C# / Swift | Truly cross-platform | Portability, 70% latency reduction via quant | ✅ CoreML EP |
| **CoreML** | Swift | macOS/iOS only | ANE (Neural Engine), App Store | ✅ Native ANE |
| **Candle** (HuggingFace) | Rust | Cross-platform + WASM | Lightweight binaries, serverless, browser | ✅ Metal |
| **llama.cpp** | C++ | CPU + GPU | LLMs and audio LLMs (GGUF format) | ✅ Metal |
| **WhisperKit** (Argmax) | Swift | macOS/iOS | CoreML-optimized Whisper for Apple | ✅ CoreML |

### EchoPanel Runtime Verdict

| Use case | Recommended runtime |
|---|---|
| Native Swift ASR (mac app) | **MLX** (via mlx-audio-swift) or **WhisperKit** |
| Python backend ASR server | **faster-whisper** (current) or **whisper.cpp** via subprocess |
| Cross-platform / WASM future | **ONNX Runtime** or **Candle** |
| Maximum accuracy, no speed constraint | **faster-whisper large-v3-turbo** |

---

## 2. ASR / Speech-to-Text Models

### 🏆 Open ASR Leaderboard (HuggingFace) — Top Performers, Feb 2026

| Rank | Model | WER | RTFx | Size | License |
|---|---|---|---|---|---|
| 1 | **Canary-Qwen 2.5B** (NVIDIA) | 5.63% | 418x | 2.5B | CC-BY-4.0 |
| 2 | **IBM Granite Speech 3.3 8B** | 5.85% | — | 8B | Apache 2.0 |
| 3 | **Parakeet TDT v3 0.6B** (NVIDIA) | 6.05% | **3386x** | 600M | CC-BY-4.0 |
| — | **Qwen3-ASR 1.7B** (Alibaba) | SOTA open | Fast | 1.7B | Apache 2.0 |
| — | **FAMA-small-asr** (FBK-MT) | ~Whisper large | **8x faster** | 475M | — |
| — | **Distil-Whisper large-v3** | ~Whisper large | **6x faster** | 756M | MIT |
| — | Whisper large-v3-turbo | Baseline | Medium | 809M | MIT |
| — | Whisper large-v3 | Baseline (best acc) | Slow | 1.5B | MIT |

> **RTFx** = Real-Time Factor. RTFx 3386 means 1 hour of audio transcribed in ~1 second (on A100). Apple Silicon numbers differ — see below.

### Apple Silicon Benchmarks (approx, M4 Pro)

| Model | Runtime | Apple RTF | RAM | Best for |
|---|---|---|---|---|
| **Parakeet TDT v3 0.6B** | MLX | ~110x | 800MB | Best English, fastest local |
| **Qwen3-ASR 1.7B** | MLX | Fast | ~3GB | Multilingual (52 langs) |
| **Whisper large-v3-turbo** | MLX | ~50x | 1.5GB | Multilingual fallback |
| **Whisper base** | whisper.cpp | Very fast | <200MB | Ultra-light |
| **Distil-Whisper large-v3** | faster-whisper | 4x OG | 750MB | Python backend |
| **Voxtral Mini 4B** | MLX | ~15x | 4GB | High quality, multi-lang |

### Deep-Dive: Key Models

#### Parakeet TDT v3 0.6B (NVIDIA)
- Architecture: FastConformer-TDT (Token-and-Duration Transducer)
- English-only; word-level timestamps built-in
- MLX port: `mlx-community/parakeet-tdt-0.6b-v3`
- CoreML port: available for iOS 17+ / macOS 14+
- Used by Argmax SDK Pro as primary engine
- **Best choice for English meeting ASR**

#### Qwen3-ASR 1.7B (Alibaba)
- 52 languages + dialects, Apache 2.0
- Streaming support, robust to noise
- Released Jan 2026, open-sourced immediately
- MLX: `mlx-community/Qwen3-ASR-1.7B-bf16`
- **Best choice if multilingual meetings are needed**

#### Canary-Qwen 2.5B (NVIDIA)
- Hybrid ASR + LLM architecture → also does translation
- Tops Hugging Face Open ASR leaderboard
- 418x RTFx — extremely capable despite size
- Python-first (NeMo framework), no MLX port confirmed yet
- **Best choice for Python backend when max accuracy needed**

#### Distil-Whisper large-v3
- 6x faster than Whisper large-v3, 49% smaller, <1% WER degradation
- Drop-in for faster-whisper: `ctranslate2` compatible
- `python -m faster_whisper` or `WhisperX` pipeline
- **Best drop-in for current Python `asr_stream.py`**

#### FAMA (FBK-MT)
- 475M params, 8x faster than Whisper large-v3
- Less mainstream, fewer integrations — watch this space

---

## 3. TTS / Text-to-Speech Models

Relevant if EchoPanel adds voice playback (read-back summaries, meeting assistant voice, etc.)

### Overview

| Model | Size | Latency | Voice Clone | Multilingual | License |
|---|---|---|---|---|---|
| **Kokoro v1.0** | **82M** | Ultra-low | Mix voices | EN/FR/KO/JA/ZH | Apache 2.0 |
| **Chatterbox-Turbo** | 500M | <200ms | ✅ 5s clip | 23+ languages | MIT |
| **Qwen3-TTS 0.6B** | 600M | Low | ✅ 3s clip | 10 languages | Apache 2.0 |
| **Parler TTS Mini** | 880M | <500ms | Style match | EN | Apache 2.0 |
| **CSM-1B** (Sesame) | 1B | Near-RT | ✅ Superior | EN primary | Apache 2.0 |
| **Dia 1.6B** (Nari Labs) | 1.6B | RT on A4000 | ✅ | EN only | Apache 2.0 |
| **XTTS-v2** (Coqui) | ~1.8B | Medium | ✅ Zero-shot | 17 languages | CPML (non-commercial) |
| **Orpheus 3B** (MLX) | 3B | Slower | ❌ | EN | — |

### Key Picks

**Kokoro 82M** — if you just need a clean local voice for read-back. Tiny, fast, ONNX available, runs on CPU. No GPU needed.

**Chatterbox-Turbo** — if you need a voice assistant with emotion control + multilingual + low latency. Sub-200ms, MIT, zero-shot cloning from 5s.

**CSM-1B** — best conversational naturalness today. Great for "meeting recap" read-back. 8.1GB VRAM needed (GPU).

---

## 4. Speaker Diarization

### Options Comparison

| Tool | Approach | Speed | Streaming | Accuracy | Mac/CPU |
|---|---|---|---|---|---|
| **Sortformer 4spk v2.1** (NVIDIA/MLX) | Transformer streaming | Fast | ✅ Real-time | SOTA | ✅ MLX |
| **pyannote.audio 3.1** | Pipeline (segmentation + embeddings) | Medium | ⚠️ Diart wrapper | ~DER 11-19% | ✅ CPU |
| **WhisperX + pyannote** | Whisper + pyannote post-process | Medium | ❌ | Good + word-align | ✅ CPU |
| **NVIDIA NeMo (MSDD + TitaNet)** | Multi-scale neural | Very fast (NVIDIA GPU) | ✅ Sortformer online | Best on GPU | ⚠️ CUDA-only |
| **WeSpeaker** | Embedding-centric | Medium | ❌ | Competitive | ✅ |
| **Diart** | Real-time pyannote wrapper | Low latency | ✅ | Good | ✅ |
| **Picovoice Falcon** | Proprietary on-device | Very fast | ✅ | Claims 5x > Google | ✅ SDK |
| **SpeakerKit** (Argmax, pyannote 4) | pyannote 4 | Fast | ✅ SDK | Commercial-grade | ✅ |

### For EchoPanel

- **Mac app (Swift):** Sortformer via `mlx-audio-swift` — same model Argmax Pro uses, free
- **Python backend:** `pyannote.audio 3.1` for offline batch at session end (already planned in v0.2 PR5)
- **Real-time Python:** `Diart` (pyannote streaming wrapper) if you need live diarization server-side
- **WhisperX** is the easiest drop-in for Python pipeline (Whisper + pyannote + word timestamps in one)

---

## 5. VAD — Voice Activity Detection

Needed to gate ASR and save compute. Strip silence before sending to ASR.

| Tool | Latency | Accuracy | Notes |
|---|---|---|---|
| **Silero VAD** | <1ms/frame | Excellent | ONNX, 1MB, industry standard, Python + JS |
| **WebRTC VAD** | Ultra-low | Good | C library, built into Chrome, very fast |
| **SmartTurn v3** (MLX) | Low | Good | Turn detection specifically, not just VAD |
| **pyannote VAD** | Medium | High | Bundled with pyannote pipeline |

**Recommendation:** Silero VAD for the Python backend (already trivial to add to `asr_stream.py`). WebRTC VAD in the Swift app for ultra-low-latency gating before sending audio over WS.

---

## 6. Embedding Models (for RAG / v0.3)

| Model | Size | Type | License | Apple Silicon |
|---|---|---|---|---|
| **BGE-M3** | 570M | Dense + Sparse + ColBERT | Apache 2.0 | ✅ ONNX/MLX |
| **Nomic Embed Text v1.5** | 137M | Dense, Matryoshka | Apache 2.0 | ✅ ONNX |
| **EmbeddingGemma** | ~300M | Dense | Gemma ToS | ✅ |
| **all-MiniLM-L6-v2** | 22M (!) | Dense | Apache 2.0 | ✅ CPU fast |
| **mxbai-embed-large-v1** | 335M | Dense | Apache 2.0 | ✅ |
| **text-embedding-3-small** | Cloud | Dense | OpenAI ToS | ☁️ API only |

**For EchoPanel v0.3 (LanceDB):**
- **BGE-M3** for hybrid search (dense + sparse in one model) — best overall
- **Nomic Embed v1.5** if you need smaller footprint (137M covers most meeting text cases)
- **all-MiniLM-L6-v2** as CPU-only fallback (22M, instant)

---

## 7. Small Local LLMs (for Analysis / Summarization)

Relevant for the Python backend NLP: rolling summary, card extraction, entity analysis (v0.2 PR4 + v0.3 PR4).

| Model | Size | Quality | License | Runs on | Notes |
|---|---|---|---|---|---|
| **Ministral-3B** | 3B | Very good | Apache 2.0 | CPU/GPU/MLX | v0.3 default pick |
| **Gemma 3 4B** | 4B | Excellent | Gemma ToS | CPU/GPU/MLX | Multimodal variant |
| **Phi-4 Mini** (Microsoft) | 3.8B | Strong | MIT | CPU/GPU | Reasoning focus |
| **Qwen2.5 3B** | 3B | Good | Apache 2.0 | CPU/GPU/MLX | Multilingual |
| **SmolLM2 1.7B** | 1.7B | Decent | Apache 2.0 | CPU/MLX | Ultra-light |
| **Llama 3.2 3B** | 3B | Good | Meta Llama | CPU/GPU/MLX | Widely tested |
| **Ollama** | — | — | MIT | macOS/Linux | Local LLM server, easy setup |

**Recommendation for EchoPanel backend:**
- Run **Ollama** as local server with `ministral:3b` or `phi4-mini` — zero Python server setup
- Or use **MLX-LM** (from ml-explore) to run any of these in Swift/Python

---

## 8. NER / Entity Extraction (non-LLM)

For structured analysis without burning a full LLM call per segment.

| Tool | Type | Languages | Notes |
|---|---|---|---|
| **GLiNER** | Zero-shot NER | EN + multi | Semantic labels (Decision, Action, Risk) — planned for v0.3 |
| **spaCy** | Rule + ML NER | Many | Fast, low RAM, good for names/orgs/dates |
| **flair** | Contextual string embeddings | Many | High accuracy, heavier |
| **LLM prompting** | Zero-shot | Any | Flexible but slow/expensive per-segment |

**For EchoPanel:** GLiNER for semantic labels + spaCy for entity types (PERSON, ORG, DATE) — both run in Python alongside `analysis_stream.py`.

---

## 9. Full Stack Option: WhisperX

WhisperX is a single Python pipeline that combines: faster-whisper + word-level alignment + pyannote diarization.

```bash
pip install whisperx
whisperx audio.mp3 --model large-v3-turbo --diarize --hf_token $HF_TOKEN
```

**Gives you:** transcript + word timestamps + speaker labels — in one command.  
**Limitation:** batch only (no streaming), requires pyannote HF token, heavier than individual components.

Good for **offline post-processing** (after session ends). Already aligned with v0.2 PR5 "batch diarization at session end."

---

## 10. Decision Matrix for EchoPanel

| Component | Current | Recommended upgrade | Why |
|---|---|---|---|
| Live ASR (mac app Swift) | Python WS → faster-whisper | **MLX + Parakeet v3** directly in Swift | Lower latency, no round-trip, on-device privacy |
| Live ASR (Python fallback) | faster-whisper base | **faster-whisper + Distil-Whisper large-v3** | Drop-in, 6x faster, same accuracy |
| VAD | None / custom | **Silero VAD** (Python) + **WebRTC VAD** (Swift) | Gates compute, saves ASR cost |
| Diarization (realtime, Swift) | Not implemented | **Sortformer via mlx-audio-swift** | Free, same as Argmax Pro |
| Diarization (batch, Python) | pyannote planned | **WhisperX** or **pyannote 3.1** standalone | Easy, word-aligned |
| Embeddings (v0.3) | Not implemented | **BGE-M3** via ONNX | Apache, hybrid search, best quality |
| LLM analysis | Gemini API / cloud | **Ollama + Ministral-3B** locally | Zero cost, no latency, private |
| TTS (if needed) | Not in v0.2 | **Kokoro 82M** (tiny) or **Chatterbox-Turbo** | Fast, local, MIT |

---

## 11. Quick Reference Links

| Resource | URL |
|---|---|
| HuggingFace Open ASR Leaderboard | [huggingface.co/spaces/hf-audio/open_asr_leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard) |
| whisper.cpp | [github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp) |
| faster-whisper | [github.com/SYSTRAN/faster-whisper](https://github.com/SYSTRAN/faster-whisper) |
| WhisperX | [github.com/m-bain/whisperX](https://github.com/m-bain/whisperX) |
| Distil-Whisper | [huggingface.co/distil-whisper](https://huggingface.co/distil-whisper) |
| Canary-Qwen 2.5B | [huggingface.co/nvidia/canary-qwen-2.5b](https://huggingface.co/nvidia/canary-qwen-2.5b) |
| Parakeet TDT v3 | [huggingface.co/nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| Qwen3-ASR | [huggingface.co/Qwen/Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR) |
| Kokoro TTS | [huggingface.co/hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) |
| Chatterbox TTS | [github.com/resemble-ai/chatterbox](https://github.com/resemble-ai/chatterbox) |
| Silero VAD | [github.com/snakers4/silero-vad](https://github.com/snakers4/silero-vad) |
| pyannote.audio | [github.com/pyannote/pyannote-audio](https://github.com/pyannote/pyannote-audio) |
| Sortformer (NeMo) | [huggingface.co/nvidia/diar_sortformer_4spk-v2.1](https://huggingface.co/nvidia/diar_sortformer_4spk-v2.1) |
| BGE-M3 | [huggingface.co/BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) |
| Nomic Embed v1.5 | [huggingface.co/nomic-ai/nomic-embed-text-v1.5](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5) |
| GLiNER | [github.com/urchade/GLiNER](https://github.com/urchade/GLiNER) |
| Ollama | [ollama.com](https://ollama.com) |
| Candle (HF Rust) | [github.com/huggingface/candle](https://github.com/huggingface/candle) |
| WhisperKit | [github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) |
| MLX Audio Swift (cross-ref) | [MLX_LOCAL_AUDIO_RESEARCH.md](./MLX_LOCAL_AUDIO_RESEARCH.md) |
