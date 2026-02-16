# Voxtral & Qwen Audio Models - Online Research

**Date:** 2026-02-14  
**Status:** Research Complete  

---

## 🔍 Voxtral Realtime - Key Findings

### What It Actually Is

**Voxtral Realtime** is a **natively streaming ASR model** (not just a wrapper):

- **Architecture:** 4B parameters (3.4B LM + 970M audio encoder)
- **Design:** Built from scratch for streaming (causal audio encoder)
- **Latency:** Configurable 80ms - 2.4s delay
- **Performance:** Matches Whisper at 480ms delay
- **License:** Apache 2.0 (fully open)

### The Issue With Our Testing

We tested with `antirez/voxtral.c` - a **pure C implementation**:
- ✅ Works for file-based transcription
- ❌ Not optimized for streaming
- ❌ Our test showed RTF 4.1 (too slow)

**Why:** The C implementation is reference code, not production-optimized.

### Proper Deployment: vLLM

Voxtral Realtime is designed for **vLLM** deployment:

```bash
# Install vLLM (nightly)
uv pip install -U vllm --torch-backend=auto \
  --extra-index-url https://wheels.vllm.ai/nightly

# Serve the model
vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 \
  --max-model-len 131072

# Use WebSocket realtime API
# Endpoint: /v1/realtime
```

**Features:**
- Native streaming via WebSocket
- 12.5 tokens/second throughput
- 480ms recommended delay (configurable)
- Supports 3+ hour continuous transcription

### Voxtral Transcribe 2 (Non-Realtime)

Mistral also released offline transcription models:
- Better accuracy than Realtime
- Not for streaming (batch only)
- Two variants: Mini and Small

---

## 🔍 Qwen Audio Models

### Qwen2-Audio (Released Aug 2024)

**What it is:**
- 7B parameter audio-language model
- Voice chat + audio analysis
- Supports 8+ languages
- Apache 2.0 license

**Capabilities:**
- ASR (speech to text)
- S2TT (speech translation)
- Audio understanding (sounds, music)
- Voice chat (no ASR intermediate)

**Usage:**
```python
from transformers import Qwen2AudioForConditionalGeneration, AutoProcessor

model = Qwen2AudioForConditionalGeneration.from_pretrained(
    "Qwen/Qwen2-Audio-7B-Instruct", 
    device_map="auto"
)
```

**Issue:** NOT natively streaming - designed for offline/batch processing.

### Qwen2.5-Omni (Released March 2025)

**What it is:**
- End-to-end multimodal model
- Text, image, audio, video understanding
- 3B parameter variant available

**Status:** Work in progress for streaming support

### Qwen Real-Time Speech Recognition (Cloud API)

**Available:** Alibaba Cloud Model Studio
- Real-time streaming API
- Chinese + English optimized
- Cloud-only (not local)

---

## 📊 Comparison Summary

| Model | Streaming | Local | Size | Speed | Best For |
|-------|-----------|-------|------|-------|----------|
| **Voxtral Realtime** | ✅ Native | ✅ | 4B | 12.5 tok/s | Production streaming |
| **whisper.cpp** | ✅ Chunked | ✅ | 74M | Very fast | Current best for EchoPanel |
| **Qwen2-Audio** | ❌ Offline | ✅ | 7B | Medium | Audio understanding |
| **faster-whisper** | ⚠️ Chunked | ✅ | 74M | Medium | Fallback |

---

## 🎯 Implications for EchoPanel

### Current Best Option: whisper.cpp

```
Why: RTF 0.024, Metal GPU, proven stable
Use: Keep as primary provider
```

### Future Upgrade: Voxtral + vLLM

```
Why: Native streaming, better quality (4B vs 74M)
When: When vLLM integration is ready
Cost: Needs 16GB+ GPU, more complex setup
```

### Qwen Models

```
Verdict: Not suitable for EchoPanel
Why: Not streaming-native, larger models
Use: Audio Q&A features (future consideration)
```

---

## 🔧 Recommended Next Steps

### Immediate (whisper.cpp)
```bash
# Keep current setup - it's working well
echo "ECHOPANEL_ASR_PROVIDER=whisper_cpp" >> .env
```

### Short-term (Voxtral via vLLM)
```bash
# Test vLLM deployment
# 1. Install vLLM nightly
# 2. Serve Voxtral
# 3. Test WebSocket streaming
# 4. Compare latency/quality vs whisper.cpp
```

### Evaluate Trade-offs

| Factor | whisper.cpp | Voxtral + vLLM |
|--------|-------------|----------------|
| Setup | Simple | Complex |
| Dependencies | None | vLLM, PyTorch |
| Memory | 300MB | 9GB+ |
| Speed | Very fast | Moderate |
| Quality | Good | Better (4B) |
| Streaming | Chunked | Native |

---

## 📚 References

- Voxtral Realtime: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602
- Voxtral Paper: https://arxiv.org/abs/2602.11298
- vLLM Streaming: https://blog.vllm.ai/2026/01/31/streaming-realtime.html
- Qwen2-Audio: https://qwenlm.github.io/blog/qwen2-audio/
- antirez/voxtral.c: https://github.com/antirez/voxtral.c (reference impl)

---

## ✅ Conclusion

**Voxtral is a real streaming ASR model** - not just a wrapper. But to get the advertised performance:

1. ✅ Use **vLLM** (not the C implementation)
2. ✅ Deploy with **WebSocket streaming API**
3. ✅ Configure **480ms delay** for best quality/speed tradeoff

**For EchoPanel now:** Keep **whisper.cpp** - it's simpler, faster, and sufficient.

**For EchoPanel v0.3:** Evaluate **Voxtral + vLLM** if better quality is needed.
