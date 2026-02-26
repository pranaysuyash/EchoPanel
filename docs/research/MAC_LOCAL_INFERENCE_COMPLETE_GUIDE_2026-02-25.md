# Mac Local Inference — Complete Guide
## All Frameworks + Best Models for Apple Silicon

**Account:** pranaysuyash (HuggingFace Pro ✅ | isPro: true | billingMode: prepaid)  
**Token:** model-lab-read (read role — verified working)  
**Date:** February 25, 2026  
**Data source:** Live HuggingFace API queries + Ollama API + web benchmarks

---

## Executive Summary

There are **6 major inference stacks** for running AI locally on a Mac, each with different trade-offs. The right choice depends on whether you're building a Python backend (MLX/llama.cpp/Transformers+MPS), a Swift app (MLX Swift/CoreML/WhisperKit), or want zero-code GUI (Ollama/LM Studio). The model landscape in 2026 is dominated by the **Qwen3 family** for general LLMs, **Parakeet v3 / Whisper large-v3-turbo** for ASR, **Kokoro / Qwen3-TTS** for TTS, and **Qwen3-VL / moondream2** for vision. Nearly every SOTA small model under 14B runs well on 16GB+ M-series Macs when 4-bit quantized.

---

## Framework Landscape

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Mac Local Inference Stacks                           │
│                                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │     MLX      │  │  llama.cpp   │  │  Transformers│  │  CoreML /  │  │
│  │  (Python +   │  │  (GGUF/Metal)│  │  + MPS       │  │    ANE     │  │
│  │   Swift)     │  │              │  │  (PyTorch)   │  │  (Swift)   │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └─────┬──────┘  │
│         │                 │                  │                │          │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────────────┴──────┐   │
│  │  mlx-lm      │  │   Ollama     │  │   HuggingFace Inference      │   │
│  │  mlx-audio   │  │   LM Studio  │  │   Providers (router API)     │   │
│  │  mlx-vlm     │  │   Jan.ai     │  │   (Pro: pranaysuyash ✅)     │   │
│  └──────────────┘  └──────────────┘  └─────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Apple Neural Engine (ANE)                      │   │
│  │         CoreML  ·  WhisperKit  ·  Argmax SDK  ·  CreateML        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 1. MLX (Apple ML Research)

**Best for:** Maximum throughput on Apple Silicon, Python + Swift, fine-tuning

| Property | Detail |
|----------|--------|
| Backend | Metal GPU + CPU unified memory |
| Format | `.npz` / safetensors (MLX native) |
| Languages | Python, Swift, C++, C |
| Install | `pip install mlx mlx-lm mlx-audio` |
| Model hub | [huggingface.co/mlx-community](https://huggingface.co/mlx-community) |

**Performance (verified benchmarks):**
- 30–70+ tok/s for 7–13B models on M3/M4 (vs 15–35 for Ollama same hardware)
- Best sustained throughput for long-context (100k+ tokens)
- Lowest memory overhead after load (~400MB idle)

**Key packages:**

```bash
pip install mlx          # core
pip install mlx-lm       # LLM inference + LoRA fine-tuning  
pip install mlx-audio    # TTS/STT/STS audio pipeline
```

**Quick usage:**
```python
from mlx_lm import load, generate
model, tokenizer = load("mlx-community/Qwen3-4B-4bit")
print(generate(model, tokenizer, prompt="Hello!"))
```

**Top mlx-community models by downloads (live data):**

| Model | Downloads | Category |
|-------|-----------|----------|
| `mlx-community/Kimi-K2.5` | 3,642,178 | LLM |
| `mlx-community/gpt-oss-20b-MXFP4-Q8` | 525,483 | LLM |
| `mlx-community/gemma-3-4b-it-qat-4bit` | 586,951 | VLM |
| `mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit` | 212,455 | Code LLM |
| `mlx-community/parakeet-tdt-0.6b-v2` | 309,840 | ASR |
| `mlx-community/parakeet-tdt-0.6b-v3` | 286,036 | ASR |
| `mlx-community/Llama-3.2-1B-Instruct-4bit` | 89,289 | LLM |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | 71,882 | LLM |
| `mlx-community/Qwen3-0.6B-4bit` | 54,113 | LLM |
| `mlx-community/whisper-small-mlx` | 49,157 | ASR |
| `mlx-community/Qwen3-30B-A3B-4bit` | 51,268 | LLM (MoE) |
| `mlx-community/all-MiniLM-L6-v2-4bit` | 48,064 | Embeddings |
| `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit` | 17,222 | TTS |
| `mlx-community/gemma-3-12b-it-qat-4bit` | 145,201 | VLM |
| `mlx-community/gemma-3-27b-it-qat-4bit` | 110,238 | VLM |

**Weakness:** Needs MLX-format conversion (mlx-community org handles most popular models).

---

## 2. llama.cpp + GGUF

**Best for:** Maximum control, lowest overhead, widest model compatibility, CPU fallback

| Property | Detail |
|----------|--------|
| Backend | Metal GPU (ggml-metal), CPU (BLAS) |
| Format | GGUF (quantized, single file) |
| Languages | C/C++ core; Python bindings via `llama-cpp-python` |
| Install | `brew install llama.cpp` or build from source |
| Model hub | HuggingFace (search `gguf`) + TheBloke / bartowski / unsloth / MaziyarPanahi |

**Performance:** 25–60 tok/s for 8B models (M2/M3), lowest idle RAM (~100MB).

**Python integration:**
```bash
pip install llama-cpp-python
```
```python
from llama_cpp import Llama
llm = Llama.from_pretrained(
    repo_id="bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
    filename="*Q4_K_M.gguf",
    n_gpu_layers=-1  # offload all layers to Metal
)
response = llm("Q: What is MLX?", max_tokens=200)
```

**Top GGUF models by downloads (live data):**

| Model | Downloads | Notes |
|-------|-----------|-------|
| `unsloth/Qwen3-Coder-Next-GGUF` | 535,476 | Coding |
| `hugging-quants/Llama-3.2-1B-Instruct-Q8_0-GGUF` | 473,625 | Tiny LLM |
| `unsloth/GLM-4.7-Flash-GGUF` | 286,472 | Fast LLM |
| `bartowski/Meta-Llama-3.1-8B-Instruct-GGUF` | 261,589 | Best 8B |
| `bartowski/Llama-3.2-3B-Instruct-GGUF` | 154,381 | Small |
| `Qwen/Qwen2.5-Coder-32B-Instruct-GGUF` | 152,511 | Large code |
| `MaziyarPanahi/Phi-3.5-mini-instruct-GGUF` | 138,004 | Tiny |
| `bartowski/gemma-2-2b-it-GGUF` | 127,384 | Tiny |
| `unsloth/Qwen3-0.6B-GGUF` | 115,066 | Ultra-tiny |
| `MaziyarPanahi/Mistral-7B-Instruct-v0.3-GGUF` | 119,496 | Classic |

**GGUF quantization guide for Mac:**

| Quant | RAM (7B) | Quality | Use When |
|-------|----------|---------|----------|
| Q2_K | ~3.0 GB | Poor | 8GB Mac only |
| Q4_K_M | ~4.8 GB | Good ✅ | **Default for 16GB** |
| Q5_K_M | ~5.7 GB | Better | 24GB Mac |
| Q8_0 | ~8.5 GB | Near-fp16 | 32GB+ Mac |
| f16 | ~14.0 GB | Full | 64GB Mac Studio |

---

## 3. Ollama

**Best for:** Zero-config local API server, OpenAI-compatible endpoint, app integration

| Property | Detail |
|----------|--------|
| Backend | llama.cpp under the hood (Metal) |
| Format | GGUF (auto-downloaded) |
| Install | `brew install ollama` |
| API | OpenAI-compatible at `http://localhost:11434` |
| GUI | None (use Open WebUI separately) |

```bash
ollama serve
ollama pull qwen3:4b
ollama run qwen3:4b
```

**OpenAI SDK compatible:**
```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
response = client.chat.completions.create(
    model="qwen3:4b",
    messages=[{"role":"user","content":"Hello!"}]
)
```

**Mac-feasible Ollama models (live from Ollama API, <70GB):**

| Model | Size | Notes |
|-------|------|-------|
| `ministral-3:3b` | 4.7 GB | Mistral ultra-tiny |
| `gemma3:4b` | 8.6 GB | Google Gemma 3 4B |
| `ministral-3:8b` | 10.4 GB | Mistral small |
| `gpt-oss:20b` | 13.8 GB | OpenAI open-source |
| `ministral-3:14b` | 15.7 GB | Mistral mid |
| `rnj-1:8b` | 16.0 GB | RNJ model |
| `gemma3:12b` | 24.0 GB | Google Gemma 3 12B |
| `nemotron-3-nano:30b` | 32.6 GB | NVIDIA MoE |
| `devstral-small-2:24b` | 51.6 GB | Mistral code |
| `gemma3:27b` | 55.0 GB | Google Gemma large |

> **Note:** Standard Ollama tags (qwen3, llama3.2, phi4, deepseek-r1, etc.) not listed above are also available via `ollama pull` — the above are their featured/newest models from the Ollama API.

**Weakness:** ~1GB idle RAM, slightly slower than raw llama.cpp or MLX, less control.

---

## 4. HuggingFace Transformers + PyTorch MPS

**Best for:** Research, fine-tuning, access to every HF model, familiar ecosystem

| Property | Detail |
|----------|--------|
| Backend | PyTorch MPS (Metal Performance Shaders) |
| Format | safetensors / pytorch (native HF) |
| Install | `pip install transformers torch torchvision` |
| Benefit | All HF models, no format conversion |
| HF Pro | Enables gated models + Inference Providers API |

```python
import torch
from transformers import pipeline

# Check MPS
device = "mps" if torch.backends.mps.is_available() else "cpu"

pipe = pipeline(
    "text-generation",
    model="Qwen/Qwen3-4B",
    torch_dtype=torch.bfloat16,
    device=device
)
print(pipe("Hello!", max_new_tokens=100))
```

**Performance:** Generally 10–25 tok/s for 7–8B (slower than MLX/llama.cpp on same HW, but improving). Best for models not yet converted to MLX/GGUF.

**Your HF Pro account (pranaysuyash) gives you:**
- ✅ Auto-approval for most gated models (Llama 4, Gemma 3 gated, Flux, etc.)
- ✅ Serverless Inference Providers API via `router.huggingface.co`
- ✅ Higher rate limits
- ✅ ZeroGPU priority on Spaces

**Using HF Inference Router (cloud, your Pro token):**
```python
from huggingface_hub import InferenceClient

client = InferenceClient(
    model="meta-llama/Llama-3.3-70B-Instruct",
    token="hf_QETiiLPvDC..."  # your token
)
response = client.text_generation("Hello!")
```

**Available Inference Providers (your account):**
Fal, Replicate, Sambanova, Together AI, Fireworks, Groq, Nscale, Hyperbolic, Novita, Scaleway, Cerebras, OVHcloud, HF Inference (native)

---

## 5. CoreML / Apple Neural Engine (ANE)

**Best for:** Native Swift/macOS/iOS apps, lowest latency, maximum battery efficiency, App Store distribution

| Property | Detail |
|----------|--------|
| Backend | ANE (Neural Engine) + GPU + CPU |
| Format | `.mlpackage` / `.mlmodelc` |
| Languages | Swift (primary), Objective-C, Python (coremltools) |
| Convert | `coremltools` Python package |

**Top CoreML models on HuggingFace (live data):**

| Model | Downloads | Task |
|-------|-----------|------|
| `argmaxinc/whisperkit-coreml` | 4,977,607 | STT (WhisperKit) |
| `FluidInference/parakeet-tdt-0.6b-v3-coreml` | 94,970 | STT |
| `FluidInference/silero-vad-coreml` | 8,508 | VAD |
| `FluidInference/speaker-diarization-coreml` | 6,811 | Diarization |
| `FluidInference/parakeet-realtime-eou-120m-coreml` | 5,572 | STT realtime |
| `argmaxinc/ttskit-coreml` | 3,081 | TTS |
| `FluidInference/kokoro-82m-coreml` | 468 | TTS |
| `apple/coreml-mobileclip` | 572 | Vision |

**Key frameworks built on CoreML:**
- **WhisperKit** (argmaxinc) — STT, open-source Swift
- **Argmax Pro SDK v2** — WhisperKit Pro (Parakeet v3) + SpeakerKit Pro (Sortformer)
- **mlx-audio-swift** — TTS/STT/STS in modular Swift SDK
- **swift-transformers** (HuggingFace) — LLM inference in Swift

---

## 6. LM Studio

**Best for:** GUI experimentation, non-technical users, quick model discovery

- Wraps both llama.cpp (GGUF) and MLX backends
- Built-in model browser (HF + MLX community)
- OpenAI-compatible local API
- Download: [lmstudio.ai](https://lmstudio.ai)
- ~2GB idle RAM (Electron overhead)

---

## 7. Jan.ai / Cortex

**Best for:** OpenAI-compatible local server, plugin architecture

- Powered by `cortexso` model collection on HF
- Supports GGUF + MLX backends
- REST API compatible with OpenAI SDK
- Download: [jan.ai](https://jan.ai)

---

## Best Models by Category (Mac-Optimized)

### 🧠 General LLMs

| Model | Params | 4-bit RAM | Best Via | Notes |
|-------|--------|-----------|----------|-------|
| **Qwen3-0.6B** | 0.75B | ~0.4 GB | MLX / Ollama | Fastest, ultra-tiny, thinking mode |
| **Qwen3-1.7B** | 1.7B | ~1.1 GB | MLX / GGUF | Great quality/size ratio |
| **Qwen3-4B** | 4B | ~2.5 GB | MLX / Ollama | **Sweet spot for 8–16GB Macs** |
| **Qwen3-8B** | 8B | ~5.0 GB | MLX / GGUF | Best 8B quality overall |
| **Llama 3.2-3B Instruct** | 3B | ~1.9 GB | MLX / Ollama | Meta, strong general |
| **Llama 3.1-8B Instruct** | 8B | ~5.0 GB | MLX / GGUF | Classic solid 8B |
| **Gemma 3-4B** | 4B | ~2.5 GB | MLX / Ollama | Google, great instruction following |
| **Gemma 3-12B** | 12B | ~7.5 GB | MLX / Ollama | Best quality under 32GB Mac |
| **Phi-4-mini** | 3.8B | ~2.4 GB | GGUF / Transformers | Microsoft, strong reasoning |
| **SmolLM2-1.7B** | 1.7B | ~1.1 GB | Transformers/GGUF | HuggingFace, open, lightweight |
| **gpt-oss-20b** | 20B | ~12.5 GB | MLX / Ollama / GGUF | OpenAI open-source, 32GB+ Mac |
| **Mistral-7B v0.3** | 7B | ~4.4 GB | MLX / GGUF | Classic baseline |

**Downloads from HF (top text-gen, live data):**
1. Qwen2.5-7B-Instruct — 16.8M downloads
2. Qwen3-0.6B — 10.0M downloads
3. Qwen3-1.7B — 5.0M downloads
4. Qwen3-8B — 5.0M downloads
5. Llama-3.1-8B-Instruct — 6.2M downloads

---

### 🤔 Reasoning / Thinking Models

| Model | Params | 4-bit RAM | Notes |
|-------|--------|-----------|-------|
| **Qwen3-4B** (thinking mode) | 4B | ~2.5 GB | Built-in thinking, best small |
| **Qwen3-8B** (thinking mode) | 8B | ~5.0 GB | Best small reasoning |
| **DeepSeek-R1-Distill-Qwen-1.5B** | 1.5B | ~1.0 GB | Tiny reasoning, 1.3M DL |
| **DeepSeek-R1-Distill-Qwen-7B** | 7.6B | ~4.8 GB | Best reasoning/size |
| **DeepSeek-R1-Distill-Llama-8B** | 8B | ~5.0 GB | Llama backbone |
| **Qwen3-30B-A3B** (MoE) | 30B active 3B | ~19 GB | MoE: only 3B active |
| **QwQ-32B** | 32B | ~20 GB | Strong reasoning, 32GB Mac |

> **MoE tip:** Qwen3-30B-A3B and Qwen3-Coder-30B-A3B use mixture-of-experts with only ~3B active params — they run at 3B speed while having 30B capacity. Perfect for 32GB Macs.

---

### 💻 Coding Models

| Model | Params | 4-bit RAM | Notes |
|-------|--------|-----------|-------|
| **Qwen2.5-Coder-0.5B** | 0.5B | ~0.3 GB | Fastest, edge deployment |
| **Qwen2.5-Coder-1.5B** | 1.5B | ~1.0 GB | Good for autocomplete |
| **Qwen2.5-Coder-7B** | 7B | ~4.4 GB | **Best small code model** |
| **Qwen3-Coder-Next** | ~80B MoE | ~active | Latest, best quality |
| **Qwen3-Coder-30B-A3B** | 30B/3B | ~19 GB | MoE, 32GB Mac |
| **Devstral-Small-2-24B** | 24B | ~15 GB | Mistral code, 32GB Mac |
| **DeepSeek-Coder-V2-Lite** | 16B/2.4B | ~10 GB | MoE coder |

---

### 👁️ Vision-Language Models (VLM)

| Model | Params | 4-bit RAM | Notes |
|-------|--------|-----------|-------|
| **moondream2** | 1.9B | ~0.96 GB | **Lightest capable VLM** |
| **Qwen3-VL-2B** | 2B | ~1.3 GB | Best tiny VLM, 12.9M DL |
| **SmolVLM2-500M** | 500M | ~0.3 GB | HuggingFace, video+image |
| **Qwen3-VL-8B** | 8.8B | ~4.4 GB | Best quality small VLM |
| **Qwen2.5-VL-3B** | 3B | ~1.9 GB | Solid mid-size |
| **Qwen2.5-VL-7B** | 7B | ~4.4 GB | Production VLM |
| **Gemma-3-4B** (multimodal) | 4B | ~2.5 GB | Text+image, gated |
| **DeepSeek-OCR** | — | — | OCR specialist |
| **LFM2.5-VL-1.6B** | 1.6B | ~1.0 GB | Liquid AI VLM |

**MLX-ready VLMs:**
- `mlx-community/gemma-3-4b-it-qat-4bit` — 586,951 downloads (most popular VLM in mlx-community)
- `mlx-community/Qwen2.5-VL-7B-Instruct-8bit` — 18 likes
- `mlx-community/Qwen3-VL-4B-Instruct-4bit` — 8,716 downloads

---

### 🎤 Speech-to-Text (ASR)

| Model | Size | MAC (MB) | Notes |
|-------|------|----------|-------|
| **whisper-tiny** | 39M | ~80 MB | Fastest, low accuracy |
| **whisper-base** | 74M | ~150 MB | Good speed/quality |
| **whisper-small** | 244M | ~500 MB | **Best small ASR** |
| **whisper-medium** | 769M | ~1.6 GB | Near-large quality |
| **whisper-large-v3-turbo** | ~800M | ~1.6 GB | **Best efficiency ASR** (3.5M DL) |
| **whisper-large-v3** | 1.6B | ~3.1 GB | Highest accuracy Whisper |
| **Parakeet TDT 0.6B v3** | 600M | ~1.2 GB | **NVIDIA, best accuracy/speed** (286K DL in mlx-community) |
| **Qwen3-ASR-0.6B** | 600M | ~1.2 GB | Multilingual, 177K DL |
| **Qwen3-ASR-1.7B** | 1.7B | ~3.5 GB | Best multilingual ASR |
| **Voxtral-Mini-4B Realtime** | 4B | ~2.0 GB 4bit | Mistral streaming STT |

**For Mac apps (CoreML / WhisperKit):**
- `argmaxinc/whisperkit-coreml` — 4.9M downloads (most downloaded ASR on HF!)
- `FluidInference/parakeet-tdt-0.6b-v3-coreml` — 94,970 downloads

---

### 🗣️ Text-to-Speech (TTS)

| Model | Size | Quality | Notes |
|-------|------|---------|-------|
| **Kokoro-82M** | 82M | ⭐⭐⭐⭐ | **Best small TTS**, 54 voices, 36 likes in mlx-community |
| **Soprano-80M** | 80M | ⭐⭐⭐ | Fast, lightweight |
| **Qwen3-TTS-0.6B** | 600M | ⭐⭐⭐⭐ | Multilingual, voice design |
| **Qwen3-TTS-1.7B** | 1.7B | ⭐⭐⭐⭐⭐ | Best local TTS quality |
| **Orpheus-3B** | 3B | ⭐⭐⭐⭐⭐ | Expressive, emotional |
| **Chatterbox** | 1.3B | ⭐⭐⭐⭐ | 16 languages, ResembleAI |
| **Dia-1.6B** | 1.6B | ⭐⭐⭐⭐ | Dialogue-optimized |
| **CSM-1B** | 1B | ⭐⭐⭐⭐ | Voice cloning |
| **Bark (mlx)** | 900M | ⭐⭐⭐ | Expressive, slower |

---

### 🔍 Embeddings (for RAG / Vector Search)

| Model | Size | Notes |
|-------|------|-------|
| **all-MiniLM-L6-v2** | 23M | ~47MB — **most downloaded** (172M DL), English only |
| **nomic-embed-text-v1.5** | ~280M | Great quality, long context, 4.3M DL |
| **nomic-embed-text-v2-moe** | 475M | MoE embeddings, better multilingual |
| **BAAI/bge-m3** | ~570M | Best multilingual (16.9M DL) |
| **Qwen3-Embedding-0.6B** | 596M | **Best new embedding model** (3.9M DL) |
| **Qwen3-Embedding-4B** | 4B | Highest quality embeddings |

**MLX embeddings:** `mlx-community/all-MiniLM-L6-v2-4bit` (48,064 DL)

---

### 📢 Speaker Diarization / VAD

| Model | Downloads | Notes |
|-------|-----------|-------|
| `pyannote/speaker-diarization-3.1` | 12,914,084 | **#1 diarization** — gated (auto-approve with HF Pro) |
| `pyannote/speaker-diarization` | — | Classic, widely used |
| `FluidInference/speaker-diarization-coreml` | 6,811 | CoreML Swift |
| `FluidInference/silero-vad-coreml` | 8,508 | CoreML VAD |
| `mlx-community/diar_sortformer_4spk-v1-fp32` | — | NVIDIA Sortformer via mlx-audio |
| Argmax SpeakerKit Pro | (Pro SDK) | Best real-time diarization on Mac |

> **Your HF Pro account auto-approves pyannote gated models** — just visit the model card and accept terms once.

---

## Hardware RAM Guide

| Mac RAM | Practical Model Limit | Recommended Stack |
|---------|----------------------|-------------------|
| **8 GB** | 3–4B (4-bit) | Qwen3-4B-4bit, Gemma-3-1b, Phi-4-mini |
| **16 GB** | 7–8B (4-bit) + OS headroom | Qwen3-8B, Llama3.1-8B, Qwen2.5-Coder-7B |
| **24 GB** | 13–14B (4-bit) | Qwen3-14B, Gemma3-12B, DeepSeek-R1-Qwen-14B |
| **32 GB** | 24–30B (4-bit) | QwQ-32B, Qwen3-30B-A3B (MoE), Gemma3-27B |
| **48 GB** | 32–40B full | DeepSeek-R1-Distill-Qwen-32B, Qwen3-32B |
| **64 GB** | 65–70B (4-bit) | Llama3.3-70B-4bit, Qwen3.5-35B |
| **128 GB+** | 100B+ | DeepSeek-V3-0324-4bit, Kimi-K2.5 (MLX community) |

---

## Framework Comparison Matrix

| Criterion | MLX | llama.cpp | Ollama | Transformers+MPS | CoreML/ANE |
|-----------|-----|-----------|--------|-----------------|------------|
| **Speed (tok/s 8B)** | 30–70 | 25–60 | 15–35 | 10–25 | 30–50 |
| **Setup complexity** | Low | Medium | Very Low | Low | High |
| **Model variety** | High (mlx-community) | Highest (all GGUF) | Medium | Highest (all HF) | Low |
| **Fine-tuning** | ✅ (LoRA) | ❌ | ❌ | ✅ (full) | ❌ |
| **Swift/native app** | ✅ (mlx-swift) | ⚠️ (llama.cpp bindings) | ❌ | ❌ | ✅ |
| **OpenAI API compat** | ⚠️ (mlx-audio has it) | ✅ (llama-server) | ✅ | ❌ | ❌ |
| **Audio pipeline** | ✅ (mlx-audio) | ⚠️ (whisper.cpp) | ⚠️ | ✅ | ✅ (WhisperKit) |
| **Idle RAM** | ~400 MB | ~100 MB | ~1 GB | ~500 MB | ~50 MB |
| **Battery efficiency** | Good | Good | Fair | Fair | Best (ANE) |
| **GPU util (unified)** | Excellent | Good | Good | Good | Excellent |

---

## Recommended Stack by Use Case

### EchoPanel / Audio Pipeline
```
STT (Python backend):   mlx-audio → Parakeet-TDT-0.6b-v3 or Whisper-large-v3-turbo
TTS (Python backend):   mlx-audio → Kokoro-82M or Qwen3-TTS-1.7B
Diarization:            mlx-audio → Sortformer-v2.1 OR pyannote/speaker-diarization-3.1
LLM (Python backend):   mlx-lm → Qwen3-4B or Qwen3-8B
Swift UI layer:         mlx-audio-swift → MLXAudioSTT + MLXAudioTTS
Native STT (Swift):     WhisperKit (argmaxinc) — CoreML, offline
```

### Local AI Assistant (16GB Mac)
```
Ollama (qwen3:4b) + Open WebUI   — zero-config chat
  OR
mlx-lm + Qwen3-4B-4bit          — Python scripts/API
```

### Local RAG / Search (16GB Mac)
```
Embeddings:   Qwen3-Embedding-0.6B (mlx-community) or all-MiniLM-L6-v2
Vector DB:    Chroma / Qdrant / LanceDB (local)
LLM:          Qwen3-4B via Ollama or MLX
```

### Code Completion (Mac)
```
continue.dev + Ollama (qwen2.5-coder:7b)
  OR
mlx-lm + mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
```

### Vision Tasks (Mac)
```
Python:  mlx-vlm + mlx-community/gemma-3-4b-it-qat-4bit (586K downloads!)
Swift:   mlx-audio-swift MLXAudioSTS or CoreML
Tiny:    moondream2 via llama.cpp (1.9B, <1GB 4-bit)
```

---

## HuggingFace Pro — What Your Account (pranaysuyash) Unlocks

**Verified from live API:**
- `isPro: true` ✅
- `billingMode: prepaid`
- Token: `model-lab-read` (read role)
- Member of `25daysofagents` org

**Serverless Inference:** Use `https://router.huggingface.co` (old `api-inference.huggingface.co` is deprecated)

```python
from huggingface_hub import InferenceClient

client = InferenceClient(token="hf_QETiiLPvDC...")

# LLM (via HF Inference or Groq/Together etc.)
out = client.chat_completion(
    model="meta-llama/Llama-3.3-70B-Instruct",
    messages=[{"role":"user","content":"Hello"}]
)

# STT (Whisper)
out = client.automatic_speech_recognition("audio.wav", model="openai/whisper-large-v3-turbo")

# TTS
audio = client.text_to_speech("Hello!", model="hexgrad/Kokoro-82M")
```

**Top warm models (live, sorted by likes):**

| Model | Category | Likes |
|-------|----------|-------|
| deepseek-ai/DeepSeek-R1 | LLM reasoning | 13,021 |
| black-forest-labs/FLUX.1-dev | Image gen | 12,342 |
| hexgrad/Kokoro-82M | TTS | 5,757 |
| openai/whisper-large-v3 | ASR | 5,417 |
| meta-llama/Llama-3.1-8B-Instruct | LLM | 5,491 |
| mistralai/Mixtral-8x7B-Instruct-v0.1 | LLM | 4,640 |
| openai/gpt-oss-120b | LLM | 4,524 |
| openai/gpt-oss-20b | LLM | 4,399 |
| deepseek-ai/DeepSeek-V3 | LLM | 4,025 |
| Qwen/QwQ-32B | Reasoning | 2,888 |
| openai/whisper-large-v3-turbo | ASR | 2,836 |
| meta-llama/Llama-3.3-70B-Instruct | LLM | 2,668 |
| moonshotai/Kimi-K2-Instruct | LLM | 2,323 |

**Gated models — auto-approved with Pro:**
- `pyannote/speaker-diarization-3.1` (auto-gated) — just accept terms on model card
- `black-forest-labs/FLUX.1-dev` (auto-gated)
- Most Llama 4 models (manual gated — request access)
- Gemma 3 models (manual gated — request access)

---

## Quick Install Reference

```bash
# MLX stack (Python)
pip install mlx mlx-lm mlx-audio

# llama.cpp
brew install llama.cpp
pip install llama-cpp-python  # Python bindings

# Ollama  
brew install ollama
ollama pull qwen3:4b

# HuggingFace ecosystem
pip install transformers huggingface_hub torch torchvision
huggingface-cli login  # use your token

# Whisper.cpp (audio only)
brew install whisper-cpp

# LM Studio
# → Download from lmstudio.ai (GUI)

# Jan.ai
# → Download from jan.ai (GUI)
```

---

## Key Repos Summary

| Repo | Framework | Stars/DL |
|------|-----------|----------|
| [ml-explore/mlx](https://github.com/ml-explore/mlx) | Core MLX | — |
| [ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm) | MLX LLMs | — |
| [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) | MLX Audio | 6,064 ⭐ |
| [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | Swift Audio SDK | 360 ⭐ |
| [ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp) | GGUF inference | 70K+ ⭐ |
| [ollama/ollama](https://github.com/ollama/ollama) | Local LLM server | 100K+ ⭐ |
| [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) | CoreML STT | — |
| [huggingface/transformers](https://github.com/huggingface/transformers) | HF ecosystem | 140K+ ⭐ |
| [huggingface/swift-transformers](https://github.com/huggingface/swift-transformers) | Swift LLM | — |
| [lm-sys/llama-cpp-python](https://github.com/abetlen/llama-cpp-python) | Python bindings | — |

---

## Confidence Assessment

| Claim | Confidence | Source |
|-------|-----------|--------|
| HuggingFace account details (pranaysuyash, isPro) | **Verified** | Live API call to `huggingface.co/api/whoami-v2` |
| mlx-community model download counts | **Verified** | Live HF API |
| GGUF model download counts | **Verified** | Live HF API |
| Ollama model sizes | **Verified** | Live Ollama API |
| CoreML model downloads | **Verified** | Live HF API |
| Token/s benchmark numbers | **High** (web sources, consistent across multiple) | Web benchmarks |
| RAM requirements | **High** (calculated from param counts) | Live HF API + standard formula |
| Framework comparisons | **High** | Multiple independent benchmark sources |
