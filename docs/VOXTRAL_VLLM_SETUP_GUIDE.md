# Voxtral vLLM Setup Guide

**Date:** 2026-02-14  
**Model:** mistralai/Voxtral-Mini-4B-Realtime-2602  
**Status:** ⚠️ Platform Limitations on macOS

---

## Overview

The official Voxtral Realtime model requires **vLLM** for serving. However, there are significant platform limitations on macOS.

---

## ⚠️ macOS Limitations

### 1. No Metal/MPS Support
**vLLM does not support Apple Silicon GPUs (Metal/MPS).**  
vLLM only supports:
- CUDA (NVIDIA GPUs)
- CPU (slow)
- TPU, HPU, XPU (Intel), Neuron (AWS)

**Impact on Mac:** Voxtral must run on CPU, which will be **very slow** compared to MLX or whisper.cpp with Metal.

### 2. Tokenizer Compatibility Issues
Current vLLM (0.7.3) has compatibility issues with the Voxtral model tokenizer:
```
ValueError: Kwargs ['max_loras', '_from_auto'] are not supported 
by `MistralCommonTokenizer.from_pretrained`.
```

### 3. Audio Model Support
Voxtral Realtime requires specific audio model support in vLLM that may not be fully implemented in current versions.

---

## Recommended Alternatives for macOS

Given these limitations, **MLX Whisper is strongly recommended for macOS**:

| Provider | RTF | GPU Support | Status |
|----------|-----|-------------|--------|
| **mlx_whisper** | 0.08x | ✅ Metal | ✅ Best for Mac |
| whisper_cpp | 0.16x | ✅ Metal | ✅ Good alternative |
| voxtral_official | ~1.0x+ | ❌ CPU only | ⚠️ Slow, issues |

---

## Linux Setup (Recommended for Voxtral)

If you have access to a Linux machine with NVIDIA GPU:

### 1. Install vLLM
```bash
pip install vllm
```

### 2. Download Model
```bash
export HF_TOKEN=your_hf_token_here
huggingface-cli download mistralai/Voxtral-Mini-4B-Realtime-2602 \
    --local-dir ./models/voxtral-mini \
    --local-dir-use-symlinks False
```

### 3. Start vLLM
```bash
vllm serve ./models/voxtral-mini \
    --max-model-len 4096 \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.9
```

### 4. Configure EchoPanel
```bash
export ECHOPANEL_ASR_PROVIDER=voxtral_official
export VOXTRAL_VLLM_URL=http://localhost:8000
export VOXTRAL_STREAMING_DELAY_MS=480
```

---

## macOS CPU Setup (Not Recommended)

If you still want to try on macOS (expect very slow performance):

### 1. Install vLLM
```bash
pip install vllm
```

### 2. Download Model
```bash
export HF_TOKEN=your_hf_token_here
huggingface-cli download mistralai/Voxtral-Mini-4B-Realtime-2602 \
    --local-dir ./models/voxtral-mini
```

### 3. Start vLLM (CPU Mode)
```bash
vllm serve ./models/voxtral-mini \
    --max-model-len 4096 \
    --device cpu \
    --dtype float16
```

**Note:** This will likely fail with tokenizer errors on current vLLM versions.

---

## Troubleshooting

### Tokenizer Error
```
ValueError: Kwargs ['max_loras', '_from_auto'] are not supported
```

**Solution:** Update vLLM to latest version or wait for Voxtral-specific support:
```bash
pip install --upgrade vllm
```

### Model Not Loading
Check vLLM logs:
```bash
curl http://localhost:8000/health
```

### GPU Out of Memory
Reduce memory usage:
```bash
vllm serve ./models/voxtral-mini \
    --max-model-len 2048 \
    --gpu-memory-utilization 0.7
```

---

## Cloud Alternative

Use Mistral's official API instead of local vLLM:

```bash
export VOXTRAL_MODE=api
export VOXTRAL_MISTRAL_API_KEY=your_api_key_here
pip install mistralai[realtime]
```

---

## Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Provider implementation | ✅ Complete | `provider_voxtral_official.py` |
| vLLM local mode | ⚠️ Limited | macOS CPU only, slow |
| Mistral API mode | ✅ Complete | Requires API key |
| Streaming architecture | ⚠️ Partial | HTTP chunks vs WebSocket |
| Configurable delay | ✅ Complete | 240-2400ms |

---

## Recommendation

**For macOS users:** Use `mlx_whisper` provider instead. It provides:
- 50× real-time performance with Metal GPU
- No setup complexity
- Better accuracy than CPU-based Voxtral

**For Linux + NVIDIA users:** Voxtral via vLLM is a good option once tokenizer issues are resolved.
