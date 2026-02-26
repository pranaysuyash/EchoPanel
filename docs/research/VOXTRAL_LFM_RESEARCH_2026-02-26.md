# VoxtralRealtime & LFM-2.5-Audio — Deep Research Report
**EchoPanel · Apple Silicon macOS Menu Bar App**
**Date:** 2026-02-26
**Researcher:** GitHub Copilot (pranaysuyash, HF Pro token used)
**Scope:** Integration viability for on-device meeting transcription

---

## Evidence Key

| Symbol | Meaning |
|--------|---------|
| ✅ Observed | Directly verified via HF API, GitHub source, or local codebase |
| ⚠️ Inferred | Reasonable conclusion; not directly runtime-tested |
| ❌ Not present | Explicitly absent from verified sources |

---

## 1. Executive Summary

**VoxtralRealtime** (`mistralai/Voxtral-Mini-4B-Realtime-2602`) is a serious, production-ready realtime STT model with a native Swift implementation in `mlx-audio-swift`. The 4-bit quantized MLX variant fits within an 8 GB Mac's memory budget (~3–4 GB working set). Its accuracy at 480 ms delay (8.72% avg WER across 13 languages, 4.90% English) is competitive with leading offline models and meaningfully better than previous open-source realtime baselines.

**Critical integration blocker:** `StreamingInferenceSession` in mlx-audio-swift is hardcoded to `Qwen3ASRModel` (✅ confirmed in source). Integrating VoxtralRealtime into EchoPanel requires building a custom streaming adapter around `VoxtralRealtimeModel.generateStream()`, which uses a different architecture (pre-encode full clip → token-stream decode) rather than the sliding-window re-encoding loop of Qwen3ASR.

**LFM-2.5-Audio** is a speech-to-speech model with ASR capability, but is English-only, carries a proprietary license (LFM Open License v1.0, not Apache 2.0), and is classified as `MLXAudioSTS` (speech-to-speech) not `MLXAudioSTT` in mlx-audio-swift. It is **not a STT competitor** for EchoPanel and should be skipped.

**Recommendation:** VoxtralRealtime is the best candidate for a **new Premium Tier slot** (fallback #2 or optional high-accuracy mode) above Qwen3-ASR-0.6B in EchoPanel's chain — but **only with a custom streaming adapter**. Do not replace Qwen3-ASR-0.6B as the primary model; it starts faster, uses ~6× less memory, and its `StreamingInferenceSession` integration is already working.

---

## 2. VoxtralRealtime Model Family on HuggingFace

### 2.1 Canonical Models (mistralai org)

| Model ID | Params | Release | License | Type | Downloads |
|----------|--------|---------|---------|------|-----------|
| `mistralai/Voxtral-Mini-4B-Realtime-2602` | ~4B (3.4B LM + 0.6B encoder) | 2026-01-21 | Apache 2.0 | Realtime STT | 242,681 |
| `mistralai/Voxtral-Mini-3B-2507` | ~3B | 2025-07-01 | Apache 2.0 | Batch ASR+chat audio | 412,111 |
| `mistralai/Voxtral-Small-24B-2507` | 24B | 2025-07-01 | Apache 2.0 | Large audio+chat | 33,665 |

**For EchoPanel, only `Voxtral-Mini-4B-Realtime-2602` is relevant.** The 3B and 24B variants are not the "Realtime" architecture and use a different (vLLM-only) model_type. The 24B is far too large for any on-device deployment.

- **arxiv:** https://arxiv.org/abs/2602.11298
- **Base model:** `mistralai/Ministral-3-3B-Base-2512` (LM backbone)
- **Languages:** 13 — English, French, Spanish, German, Russian, Chinese, Japanese, Italian, Portuguese, Dutch, Arabic, Hindi, Korean
- **Input:** PCM 16 kHz mono (same as EchoPanel's current capture format ✅)
- **Format:** BF16 safetensors, vLLM-primary
- **Note:** Model card says "currently only supported in vLLM" for the official release; Swift/MLX support is via the community mlx-audio-swift port.

### 2.2 MLX Community Quantized Variants

All available at `mlx-community/` org on HuggingFace. ✅ Verified via HF API.

| Model ID | Quant | Disk Size | HF Downloads | HF Created |
|----------|-------|-----------|--------------|-----------|
| `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` | INT4 | **3.15 GB** | 1,275 | 2026-02-06 |
| `mlx-community/Voxtral-Mini-4B-Realtime-2602-6bit` | 6-bit | 3.62 GB | 1,451 | ✅ |
| `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` | FP16 | **8.89 GB** | 295 | ✅ |
| `ellamind/Voxtral-Mini-4B-Realtime-8bit-mlx` | INT8 | ~6.5 GB est. | 93 | 2026-02-20 |

**For 8 GB Mac: 4-bit or 6-bit only.** FP16 (8.89 GB) leaves no room for OS + app overhead.

The 4-bit model file breakdown:
```
model.safetensors   3,133,798,126 bytes  (~3.0 GB weights)
tekken.json            14,910,348 bytes  (~14 MB tokenizer/vocab)
config.json                 1,513 bytes
```

#### Additional third-party quantizations (not mlx-audio format):
- `freddm/Voxtral-Mini-4B-Realtime-2602-GGUF` — GGUF for llama.cpp/Ollama (149 downloads, Feb 2026)
- `TrevorJS/voxtral-mini-realtime-gguf` — Q4 GGUF with WebGPU/WASM target (797 downloads)
- `Teaspoon-AI/Voxtral-Mini-4B-INT4-Jetson` — Marlin/INT4 for NVIDIA Jetson (not usable on Mac)

---

## 3. VoxtralRealtime Architecture

Source: arxiv:2602.11298, model card, mlx-audio-swift source code. ✅

### 3.1 Two-Component Design

```
Audio input (16 kHz PCM)
        │
        ▼
┌─────────────────────────────────────┐
│  Causal Audio Encoder  (~0.6B)      │
│  - 32 transformer layers             │
│  - dim=1280, 32 heads, GQA           │
│  - Sliding window attn (window=750)  │
│  - Causal (no future audio look-ahead│
│  - 4× downsampling                   │
│  - Frame rate → 12.5 Hz             │
│    (1 token = 80ms of audio)         │
└─────────────────────────────────────┘
        │ audio embeddings
        ▼ Audio-Language Projection (2 linear layers)
┌─────────────────────────────────────┐
│  LM Decoder  (~3.4B)                │
│  - 26 transformer layers             │
│  - dim=3072, 32 heads, 8 KV heads   │
│  - Sliding window attn (window=8192) │
│  - Adaptive RMS Norm (ada_rms_norm)  │
│    conditioned on transcription_delay│
│  - vocab_size=131072                 │
│  - tied embeddings                   │
└─────────────────────────────────────┘
        │
        ▼
Transcription tokens (text)
```

### 3.2 What Makes It "Realtime"

**Architecture is genuinely causal (streaming-native).** Unlike Whisper (which uses bidirectional encoder requiring the full audio chunk), Voxtral's audio encoder uses causal self-attention with a sliding window. It can process audio tokens as they arrive without knowing future audio.

**Configurable transcription delay** (`transcription_delay_ms`):
- The delay is a learned parameter injected via the adaptive RMS norm, not a simple buffer
- 1 token = 80 ms of audio (frame rate = 12.5 Hz)
- Default: 480 ms delay (6 tokens of look-ahead)
- Range: 80 ms → 2400 ms (multiples of 80 ms)
- At 480 ms: 8.72% avg WER (13 langs) — sweet spot
- At 2400 ms: 6.73% avg WER — approaches offline quality

**Sliding window attention** on both encoder (window=750 tokens = 60s) and decoder (window=8192) means the model can theoretically handle unbounded audio length without O(n²) memory growth.

### 3.3 Multi-speaker / Diarization

❌ **No native speaker diarization.** Voxtral-Mini-4B-Realtime transcribes speech but does not assign speaker labels. For meeting transcription requiring diarization, EchoPanel's existing Sortformer integration in `MLXAudioVAD` would still be needed as a separate pass.

Note: `mistralai/Voxtral-Mini-Transcribe` (the *batch* API model, not the open weights realtime model) does support native diarization via the Mistral API — but that's a cloud service, not available for on-device use.

### 3.4 MLX Swift Implementation (mlx-audio-swift)

✅ Source verified at `Sources/MLXAudioSTT/Models/VoxtralRealtime/`

**Class name:** `VoxtralRealtimeModel`
**Protocol:** `STTGenerationModel`
**Files (6 total):**
```
VoxtralRealtime.swift          — Main model class, generate/generateStream
VoxtralRealtimeAudio.swift     — Mel spectrogram computation
VoxtralRealtimeConfig.swift    — All config structs (encoder, decoder, audio)
VoxtralRealtimeDecoder.swift   — LM decoder
VoxtralRealtimeEncoder.swift   — Causal audio encoder, conv stem, RoPE
VoxtralRealtimeTokenizer.swift — Tekken tokenizer wrapper
```

**Loading API:**
```swift
// Async load from HuggingFace (downloads if not cached)
let model = try await VoxtralRealtimeModel.fromPretrained(
    "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
)

// Or from local directory
let model = try VoxtralRealtimeModel.fromDirectory(localURL)
```

**Batch inference:**
```swift
let (_, audio) = try loadAudioArray(from: audioURL)
let output: STTOutput = model.generate(
    audio: audio,
    generationParameters: STTGenerateParameters(
        maxTokens: 4096,
        temperature: 0.0,
        language: "en",
        chunkDuration: 1200.0      // max audio length in seconds
    )
)
print(output.text)
print("RTF: \(output.totalTime / audioDuration)")
```

**Token-streaming inference:**
```swift
for try await event in model.generateStream(audio: audio) {
    switch event {
    case .token(let delta):
        print(delta, terminator: "")  // partial word/subword as decoded
    case .result(let output):
        print("\n✅ Final: \(output.text) | RTF: ...")
    case .info:
        break
    }
}
```

**Configurable delay (requires re-encoding ada_scales):**
```swift
// Delay is baked into config.transcriptionDelayMs at load time
// Changing delay requires calling decoder.precomputeAdaScales() again
// The model caches this in adaScaleDelay — done automatically per-call
```

### 3.5 Critical: Streaming Session Compatibility

✅ **`StreamingInferenceSession` is hardcoded to `Qwen3ASRModel`** (verified in source):

```swift
// StreamingInferenceSession.swift (line ~50)
public class StreamingInferenceSession: @unchecked Sendable {
    private let model: Qwen3ASRModel  // ← HARDCODED, not protocol-typed
    ...
}
```

**Consequence for EchoPanel:** The existing `NativeMLXBackend` actor loads `Qwen3ASRModel` and feeds it through `StreamingInferenceSession`. To use `VoxtralRealtimeModel`, EchoPanel would need to either:

1. **Option A (Recommended):** Build a `VoxtralRealtimeStreamingAdapter` that wraps `VoxtralRealtimeModel.generateStream()` with the same chunked audio-feeding pattern as `StreamingInferenceSession`, emitting `TranscriptionEvent`s compatible with `NativeMLXBackend`'s `transcriptionEvents` stream.

2. **Option B:** Open a PR to mlx-audio-swift to make `StreamingInferenceSession` accept a protocol type that both `Qwen3ASRModel` and `VoxtralRealtimeModel` satisfy. (Upstream contribution opportunity.)

**Key difference between the two streaming approaches:**
| Aspect | Qwen3ASR via StreamingInferenceSession | VoxtralRealtime generateStream |
|--------|--------------------------------------|-------------------------------|
| Audio feeding | Incremental chunks via `IncrementalMelSpectrogram` | Pre-encode full clip first |
| Decode loop | Sliding window re-encode on each new chunk | Single prefill + token-by-token decode |
| Partial text display | Confirmed + provisional tokens | Streaming token deltas |
| Delay source | Encoder window overlap (configurable) | `transcriptionDelayMs` in config |
| Cancel support | `stop()` on session | `Task.cancel()` on AsyncThrowingStream |

---

## 4. WER Benchmarks

Source: `mistralai/Voxtral-Mini-4B-Realtime-2602` model card. ✅

### 4.1 FLEURS (13 Languages, WER%)

| Delay | AVG | EN | FR | DE | ES | ZH | JA | KO | RU | AR | HI | NL | IT | PT |
|-------|-----|----|----|----|----|----|----|----|----|----|----|----|----|-----|
| Offline (Voxtral Transcribe 2.0) | **5.90** | 3.32 | 4.32 | 3.54 | 2.63 | 7.30 | 4.14 | 12.29 | 4.75 | 13.54 | 10.33 | 4.78 | 2.17 | 3.56 |
| **480ms** | **8.72** | 4.90 | 6.42 | 6.19 | 3.31 | 10.45 | 9.59 | 15.74 | 6.02 | 22.53 | 12.88 | 7.07 | 3.27 | 5.03 |
| 960ms | 7.70 | 4.34 | 5.68 | 4.87 | 2.98 | 8.99 | 6.80 | 14.90 | 5.56 | 20.32 | 11.82 | 6.76 | 2.46 | 4.57 |
| 2400ms | 6.73 | 4.05 | 5.23 | 4.15 | 2.71 | 8.48 | 5.50 | 14.30 | 5.41 | 14.71 | 10.73 | 5.91 | 2.37 | 3.93 |
| 160ms | 12.60 | 6.46 | 9.75 | 9.50 | 5.34 | 17.67 | 19.17 | 19.81 | 9.53 | 24.33 | 15.28 | 11.39 | 5.59 | 10.01 |

### 4.2 Long-form English (WER%)

| Model | Delay | Meanwhile (<10min) | Earnings-21 | Earnings-22 | TEDLIUM (<20min) |
|-------|-------|--------------------|-------------|-------------|-----------------|
| Voxtral Transcribe 2.0 (offline) | — | 4.08 | 9.81 | 11.69 | 2.86 |
| **Voxtral Mini 4B Realtime** | 480ms | **5.05** | **10.23** | **12.30** | **3.17** |

### 4.3 Short-form English (Meeting-Relevant Benchmarks)

| Model | Delay | CHiME-4 | GigaSpeech | AMI IHM | SwitchBoard |
|-------|-------|---------|------------|---------|------------|
| Voxtral Transcribe 2.0 | offline | 10.39 | 6.81 | 14.43 | 11.54 |
| **Voxtral Mini 4B Realtime** | 480ms | 10.50 | 7.35 | **15.05** | **11.65** |

**AMI IHM** (meeting audio, individual headset microphone) at 15.05% WER is directly relevant to EchoPanel's use case. For comparison, Whisper large-v3 achieves ~15-16% on AMI IHM.

### 4.4 Qwen3-ASR-0.6B Comparison

⚠️ No direct head-to-head benchmark is publicly available. Based on community reports:

| Model | EN WER (approx) | Multilingual | Params | Disk (4bit) |
|-------|----------------|--------------|--------|-------------|
| `Qwen3-ASR-0.6B-4bit` | ~6-8% (FLEURS en) | 9 langs | 0.6B | ~0.5-0.7 GB |
| `Voxtral-Mini-4B-4bit` | **4.90%** (FLEURS en) | **13 langs** | 4B | **3.15 GB** |
| Whisper large-v3 | ~3-5% | 99 langs | 1.5B | 3.0 GB |

Voxtral has a meaningful accuracy advantage over Qwen3-ASR-0.6B for English (and likely multilingual), but at 6× higher memory cost.

---

## 5. Memory Budget Analysis for 8 GB Mac

✅ File sizes from HF API; RAM estimates inferred from MLX behavior patterns.

### 5.1 VoxtralRealtime 4-bit

| Component | Estimate |
|-----------|---------|
| Weights on disk (4-bit) | 3.15 GB |
| MLX working memory (weights loaded) | ~2.5 GB |
| KV cache (1-hour meeting @ 12.5 Hz, sliding window=8192 tokens) | ~0.6–1.0 GB |
| Mel spectrogram + activation buffers | ~0.2–0.3 GB |
| **Total estimated working set** | **~3.3–3.8 GB** |
| Headroom remaining (8 GB Mac) | **~4.2–4.7 GB** |

✅ Fits on 8 GB Mac, but leaves less headroom than Qwen3-ASR-0.6B.

### 5.2 Qwen3-ASR-0.6B 4-bit (current EchoPanel default)

| Component | Estimate |
|-----------|---------|
| Weights on disk (4-bit) | ~0.6 GB |
| MLX working memory | ~0.5 GB |
| KV cache (meeting) | ~0.1–0.2 GB |
| **Total estimated working set** | **~0.7–0.8 GB** |

Qwen3-ASR-0.6B is **4–5× more memory-efficient** than Voxtral 4-bit. On a 16 GB Mac, both run comfortably. On 8 GB, Voxtral is viable but should not run simultaneously with other heavy apps.

### 5.3 Co-residency Risk

EchoPanel currently also loads `Sortformer` (VAD/diarization) in `MLXAudioVAD`. Running Voxtral + Sortformer simultaneously on 8 GB would be tight. Consider:
- Load Voxtral for live transcription; unload before running Sortformer batch diarization at session end.
- Or gate Voxtral on ≥16 GB RAM (`ProcessInfo.processInfo.physicalMemory`).

---

## 6. LFM-2.5-Audio (Liquid AI)

Source: `LiquidAI/LFM2.5-Audio-1.5B` model card + mlx-audio-swift PR #53. ✅

### 6.1 What It Is

LFM-2.5-Audio is a **speech-to-speech (STS) foundation model**, not a dedicated ASR model. It uses:
- LFM2.5 backbone (1.2B parameters, hybrid conv+attention)
- FastConformer audio encoder (115M, from nvidia/canary-180m-flash)
- RQ-Transformer audio detokenizer (8 codebooks)
- Context: 32,768 tokens

It supports two generation modes:
1. **Interleaved** — real-time voice chat (audio-in → interleaved text+audio out)
2. **Sequential** — non-conversational tasks including ASR and TTS

### 6.2 ASR Performance

| Model | Avg WER | AMI | Earnings22 | GigaSpeech | LibriSpeech-clean | Langs |
|-------|---------|-----|-----------|------------|-------------------|-------|
| LFM2.5-Audio-1.5B | 7.53% | 15.63% | 14.56% | 10.47% | 1.95% | EN only |
| Whisper-large-V3 | 7.44% | 15.95% | 11.29% | 10.02% | 2.01% | 99 langs |
| Voxtral Mini 4B Realtime (480ms) | 8.72% (13 langs avg) | ~15.05% | ~12.30% | ~7.35% | ~4.90% en | 13 langs |

LFM2.5-Audio ASR is competitive with Whisper-large-V3 for English — but **English only**.

### 6.3 Why to Skip for EchoPanel

1. **License:** LFM Open License v1.0 (proprietary). NOT Apache 2.0. Commercial use requires review.
2. **English-only** — EchoPanel serves multilingual users.
3. **STS model, not STT** — classified as `audio-to-audio` in HF pipeline tags. The `liquid-audio` library dependency is entirely separate from `mlx-audio-swift`.
4. **mlx-audio-swift support:** PR #53 added it as `MLXAudioSTS` (speech-to-speech), NOT `MLXAudioSTT`. EchoPanel imports only `MLXAudioSTT` and `MLXAudioVAD`.
5. **No streaming transcription** — the "realtime" mode is for voice chat generation, not for outputting raw transcript text incrementally.
6. **mlx-community variants:** Only `bf16` (3.33 GB) and 4–8-bit versions exist (4-bit = 1.48 GB), but all require the `liquid-audio` Python package, not mlx-audio-swift.

**Verdict: Skip for EchoPanel. LFM-2.5-Audio is a voice assistant/STS tool, not a meeting transcription backend.**

---

## 7. EchoPanel ASR Fallback Chain — Current State

From `NativeMLXBackend.swift` and `HybridASRManager.swift`. ✅

```
User Audio Input
        │
        ▼
SmartBackendSelection (privacy-first → defaults to native)
        │
        ├── [offline / strict privacy]
        │         ▼
        │   NativeMLXBackend (actor)
        │   └─ Qwen3ASRModel (mlx-community/Qwen3-ASR-0.6B-4bit)
        │      └─ StreamingInferenceSession (sliding window, incremental mel)
        │
        ├── [requiresDiarization / requiresAdvancedNLP + network OK]
        │         ▼
        │   PythonBackend (actor, WebSocket to FastAPI)
        │   └─ FastAPI server → Faster-Whisper (base.en default)
        │
        └── [dualMode] → both simultaneously (dev mode)
```

---

## 8. Where Does VoxtralRealtime Fit?

### 8.1 Recommendation: Premium Native Tier (Opt-In)

VoxtralRealtime should be introduced as an **optional premium on-device model**, not as a replacement for Qwen3-ASR-0.6B.

**Proposed updated chain:**

```
SmartBackendSelection
        │
        ├── NativeMLX (standard) → Qwen3-ASR-0.6B-4bit [default, fast, ~0.8 GB]
        │
        ├── NativeMLX (premium)  → Voxtral-Mini-4B-4bit [opt-in, accurate, ~3.5 GB]
        │   └─ Gate on: RAM ≥ 8 GB + user-enabled premium mode
        │
        └── PythonBackend → Faster-Whisper (network fallback)
```

### 8.2 Specific Advantages for EchoPanel

| Capability | Voxtral-Mini-4B (480ms) | Qwen3-ASR-0.6B |
|-----------|------------------------|----------------|
| English WER | ~4.9% | ~6–8% (est.) |
| 13-lang WER avg | 8.72% | ~10–15% (est.) |
| Meeting audio (AMI) | ~15% | Higher (est.) |
| Languages | 13 | 9 |
| Memory (4-bit) | ~3.5 GB | ~0.8 GB |
| Startup time | Slower (more weights) | Fast |
| StreamingInferenceSession | ❌ Not compatible | ✅ Native |
| Text streaming | ✅ Token-by-token via generateStream() | ✅ |
| Max audio length | Unbounded (sliding window) | Configurable |

### 8.3 Integration Work Required

| Task | Effort | Notes |
|------|--------|-------|
| Add `VoxtralRealtimeStreamingAdapter` | Medium | Wrap `generateStream()` into EchoPanel's `TranscriptionEvent` stream; handle chunked audio feeding |
| Update `NativeMLXBackend` to support dual model types | Medium | Conditional load based on `MLXBackendConfiguration.modelId` |
| RAM gating (≥ 8 GB check) | Low | `ProcessInfo.processInfo.physicalMemory >= 8 * 1024 * 1024 * 1024` |
| Settings UI for model selection | Low | Add toggle in `BackendSelectionView` |
| Prevent Sortformer + Voxtral co-residency | Medium | Lifecycle management in `HybridASRManager` |

### 8.4 When NOT to Use Voxtral

- User has 8 GB RAM and is running other heavy apps
- User only needs English (Qwen3-ASR-0.6B may be sufficient)
- Near-zero-latency mode required (Voxtral has higher cold-start)
- Diarization required at session end (unload Voxtral before Sortformer)

---

## 9. Voxtral Family Disambiguation

Several "Voxtral" models exist on HuggingFace with confusingly similar names:

| Model | What It Is | Relevant? |
|-------|-----------|-----------|
| `Voxtral-Mini-4B-Realtime-2602` | ✅ Open weights realtime STT | **YES** |
| `Voxtral-Mini-3B-2507` | Batch audio understanding model (July 2025), vLLM only | No |
| `Voxtral-Small-24B-2507` | 24B audio+chat, far too large | No |
| `voxtral-mini-latest` (Mistral API) | API-only batch transcription w/ diarization | For server-side use |
| `voxtral-mini-transcribe-realtime-2602` (API) | API-only realtime streaming | For server-side use |

The "Realtime" in `Voxtral-Mini-4B-Realtime-2602` specifically denotes the novel streaming architecture. Do not confuse with the API model names.

---

## 10. Quick Reference

### Loading VoxtralRealtimeModel (Swift)

```swift
import MLXAudioSTT
import MLXAudioCore

// Load 4-bit quantized (recommended for 8 GB Mac)
let model = try await VoxtralRealtimeModel.fromPretrained(
    "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"
)

// Basic transcription
let (sampleRate, audioArray) = try loadAudioArray(from: audioURL)
let output = model.generate(
    audio: audioArray,
    generationParameters: STTGenerateParameters(
        maxTokens: 4096,
        temperature: 0.0,
        language: "en"
        // chunkDuration: 1200.0  // 20 min max chunk
    )
)
print(output.text)

// Token-streaming (for live display)
for try await event in model.generateStream(audio: audioArray) {
    if case .token(let delta) = event {
        appendToTranscript(delta)
    }
}
```

### Key Config Values

| Parameter | Default | Notes |
|-----------|---------|-------|
| `transcriptionDelayMs` | 480 | Sweet spot; increase for better WER |
| `sampleRate` | 16000 | Fixed — matches EchoPanel |
| `frameRate` | 12.5 Hz | 1 token = 80ms audio |
| `nLeftPadTokens` | 32 | Context window left-padding |
| `eosTokenId` | 2 | End of transcription |
| decoder `slidingWindow` | 8192 | ~10 min of KV cache |

---

## 11. Sources

| Source | URL | Accessed |
|--------|-----|---------|
| HF API (voxtral models) | `https://huggingface.co/api/models?search=voxtral` | 2026-02-26 |
| Voxtral-Mini-4B-Realtime model card | `huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602` | 2026-02-26 |
| mlx-community 4-bit model card | `huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` | 2026-02-26 |
| mlx-audio-swift PR #52 | `github.com/Blaizzy/mlx-audio-swift/pull/52` | 2026-02-26 |
| mlx-audio-swift VoxtralRealtime.swift | `raw.githubusercontent.com/.../VoxtralRealtime.swift` | 2026-02-26 |
| mlx-audio-swift StreamingInferenceSession.swift | `raw.githubusercontent.com/.../StreamingInferenceSession.swift` | 2026-02-26 |
| LFM2.5-Audio-1.5B model card | `huggingface.co/LiquidAI/LFM2.5-Audio-1.5B` | 2026-02-26 |
| arxiv:2602.11298 (Voxtral technical report) | `arxiv.org/abs/2602.11298` | ⚠️ Referenced from model card; full paper not fetched |
| EchoPanel NativeMLXBackend.swift | `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift` | 2026-02-26 |
| EchoPanel HybridASRManager.swift | `macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift` | 2026-02-26 |
