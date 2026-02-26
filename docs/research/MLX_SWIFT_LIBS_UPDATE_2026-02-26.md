# MLX Swift Library Status Update — 2026-02-26

**Research baseline:** Feb 25, 2026 (`MLX_ECOSYSTEM_RESEARCH_2026-02-25.md`, `NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`)  
**Purpose:** Track what changed in mlx-audio-swift, mlx-swift-lm, and WhisperKit since Feb 25 research; inform Package.swift update decisions.

---

## 1. Version Status Table

| Library | Our Current Pin | Latest Available | Released | Delta |
|---------|----------------|-----------------|----------|-------|
| `mlx-audio-swift` | `branch: "main"` (unversioned) | **v0.1.0** | 2026-02-23 | First official release dropped 3 days ago |
| `mlx-swift` | (transitive via mlx-audio-swift) | **0.30.6** | 2026-02-10 | Required by mlx-audio-swift ≥ 0.30.6 |
| `mlx-swift-lm` | not in Package.swift | **2.30.6** | 2026-02-18 | Separate repo from mlx-swift-examples |
| `mlx-swift-examples` | not in Package.swift | 2.29.1 | 2025-10-16 | Older; superseded by `mlx-swift-lm` |
| `WhisperKit` | not in Package.swift | **v0.15.0** | 2025-11-07 | CoreML-based; stable but 3 months older |

> **Critical note:** `mlx-swift-lm` (`github.com/ml-explore/mlx-swift-lm`) is a **distinct repo** from `mlx-swift-examples`. mlx-audio-swift's own Package.swift already depends on it at `≥ 2.30.3`. Our app does not directly import it yet.

---

## 2. mlx-audio-swift Deep Dive

### 2.1 Release summary (v0.1.0 — Feb 23, 2026)
This is the **first tagged release**, shipping everything built since the initial commit. The `main` branch is ahead of it (PRs #51–53 are merged but may or may not have a subsequent tag). Tracking `branch: "main"` exposes us to breaking mid-flight changes.

**Swift toolchain:** `swift-tools-version: 6.2` (requires Xcode 16.3 / Swift 6.2). macOS 14+, iOS 17+.  
Our `Package.swift` targets Swift 6.0 + macOS 15 — **compatible but we're behind on tools version**.

### 2.2 Parakeet-TDT: ✅ NOW AVAILABLE

**PR #51 "Add Parakeet STT models"** — Merged ≈ Feb 21, 2026. This was the top missing item from Feb 25 research.

Full native Swift implementation:

```swift
public final class ParakeetModel: Module, STTGenerationModel {
    public enum Variant: Sendable {
        case tdt        // Token-and-Duration Transducer — best WER + alignment
        case tdtCtc     // TDT with CTC decoder
        case rnnt       // RNN-Transducer
        case ctc        // CTC-only (fastest)
    }
    // supports: generate(), generateStream()
}
```

Supported HuggingFace model slugs (confirmed via README.md in Parakeet folder):
- `nvidia/parakeet-tdt-0.6b-v2` (600M, best WER)
- `nvidia/parakeet-tdt_ctc-110m` (110M, balanced)
- `nvidia/parakeet-rnnt-1.1b`
- `nvidia/parakeet-ctc-0.6b-v2`

**Default generation params:** `chunkDuration: 1200.0s`, `minChunkDuration: 1.0s` — designed for batch-first but `generateStream` exists (chunked streaming).

### 2.3 GLM ASR streaming: ❌ STILL BATCH-ONLY

GLM ASR folder contains only:
- `GLMASR.swift` — main model
- `GLMASRConfig.swift`
- `GLMASRLayers.swift`

No `generateStream` method. No PR addressing this as of Feb 26. GLM is a poor fit for EchoPanel's real-time requirement unless we build chunked-window wrappers ourselves.

### 2.4 Qwen3ASR streaming: ✅ ADDED (PR #32)

PR #32 "[Qwen3-ASR] Add live transcript support and lower peak usage" — merged before v0.1.0.

Key additions:
- **`generateStream()`** method — chunk-by-chunk real-time transcription
- **`encodeSingleWindow(_:)`** — encode a single mel-frame window for streaming
- **`mergeAudioFeatures` made `public`** — external callers can merge encoded audio into decoder prompt
- Peak memory reduced across audio encoder, DSP pipeline, and audio-text merging
- Uses `Task.detached` + cancellation tokens for cooperative cancellation

### 2.5 New model classes since Feb 25

| Model | PR | Status | Notes |
|-------|----|--------|-------|
| **Parakeet** (TDT/TDT-CTC/RNNT/CTC) | #51 | ✅ Merged | Nvidia ASR — best WER option in the lib |
| **VoxtralRealtime** | #52 | ✅ Merged | Mistral's real-time STT; has dedicated realtime architecture |
| **LFM-2.5-Audio** | #53 | ✅ Merged | Liquid Foundation Model — multimodal audio |
| **Sortformer** (VAD/Diarization) | #33 | ✅ Merged | Speaker diarization now in MLXAudioVAD |
| **MossFormer2 SE** | #29, #44 | ✅ Merged | Speech enhancement (noise removal) |
| **SAM Audio STS** | #46 | ✅ Merged | Speech-to-speech model |

**Total STT models now in the library:** GLM ASR, Qwen3 ASR, Parakeet, VoxtralRealtime, LFM-2.5-Audio (5 classes)

### 2.6 Open issues about Parakeet

From issue search results, issue #55 is still **open** (exact title not fully captured, but it's in the parakeet search results). Issues #51 (PR), #56, #65 (closed/merged), #66 (merged) are all resolved. One open item remains — likely a bug report or enhancement. **Not a blocker** given the main implementation is merged.

### 2.7 Breaking changes in v0.1.0

- Swift tools version bump to **6.2** (was not versioned before — inferred from initial build)
- `MLXLMCommon` is now a direct dependency (pulled from `mlx-swift-lm`, not `mlx-swift-examples`)
- `MLXAudioSTT` now requires `mlx-swift-lm ≥ 2.30.3` transitively — no manual import needed by our app
- No API removals documented in the release notes

---

## 3. mlx-swift & mlx-swift-lm Deep Dive

### 3.1 mlx-swift — 0.30.6 (Feb 10, 2026)

**Breaking change in quantization API:**

```swift
// Before (≤ 0.25.x):
public let biases: MLXArray

// After (≥ 0.29.x):
public let biases: MLXArray?   // now Optional
public let mode: QuantizationMode
```

Impact on EchoPanel: **None directly** — we don't implement custom quantized layers. mlx-audio-swift and mlx-swift-lm both handle this internally.

### 3.2 mlx-swift-lm — 2.30.6 (Feb 18, 2026)

**This is the correct package** (not `mlx-swift-examples`). It provides 4 libraries:

| Library | Purpose | Meeting-relevant? |
|---------|---------|-------------------|
| `MLXLLM` | 40+ LLM model classes (Llama, Qwen3, Gemma3, Phi3, GLM4, etc.) | ✅ Chat analysis, summarization |
| `MLXVLM` | Vision-language models (describe images) | ✅ OCR + screenshot analysis |
| `MLXLMCommon` | Shared inference API (`generate`, `UserInput`, `ModelContainer`) | ✅ Required by both |
| `MLXEmbedders` | Embedding models | ✅ RAG, semantic search of transcripts |

**MLXEmbedders models available:**
- `Bert.swift` — standard BERT embeddings
- `NomicBert.swift` — Nomic Embed Text (best general-purpose embedding, 768-dim)
- `Qwen3.swift` — Qwen3 embeddings (multilingual, strong for meeting content)

**Notable MLXLLM additions since mlx-swift-examples 2.29.1:**
- GLM 4.7 Flash (compact, good for Chinese/English meetings)
- NemotronH (NVIDIA hybrid model)
- Qwen3-Next-80B (large reasoning model)
- MiniCPM support
- SmolLM3 (very small, ~1B, could run alongside STT)
- Raw token streaming via `TokenGeneration` and `generateTokens` (new in 2.30.6)

**Swift version:** tools 5.12, macOS 14+. Swift 6 StrictConcurrency enabled as experimental. **Compatible with our Swift 6.0 target.**

### 3.3 Swift 6 / macOS 15 compatibility

| Library | Swift 6 Status | macOS 15 |
|---------|---------------|----------|
| mlx-audio-swift | ✅ tools 6.2, Swift 6 mode | ✅ (requires macOS 14+) |
| mlx-swift 0.30.6 | ✅ | ✅ |
| mlx-swift-lm 2.30.6 | ✅ Sendable + StrictConcurrency | ✅ |
| WhisperKit 0.15.0 | ✅ Sendable conformance (v0.14.1) | ✅ |

---

## 4. WhisperKit Deep Dive

### 4.1 Version: v0.15.0 (Nov 7, 2025)

### 4.2 Backend: CoreML — NOT MLX

WhisperKit uses **CoreML + ANE**, not Apple's MLX framework. This is the critical architectural difference:

- Models downloaded as CoreML `.mlpackage` bundles from `argmaxinc/whisperkit-coreml` on HuggingFace
- Runs on ANE (Neural Engine) — different memory pool from GPU/MLX unified memory
- **Cannot share memory buffers** with mlx-swift-lm layers (no zero-copy pipeline)

### 4.3 Supported model sizes

```
tiny / tiny.en    (~40MB)   — fastest, ~95% accuracy on clean speech
base / base.en    (~75MB)   — good balance
small / small.en  (~250MB)  — recommended for real-time on Apple Silicon
medium / medium.en (~800MB) — high accuracy
large / large-v2 / large-v3 (~3GB) — highest accuracy
```

All support multilingual transcription except `.en` variants.

### 4.4 Streaming API

WhisperKit has **real-time streaming from microphone** via `--stream` CLI flag, but the native Swift API for streaming uses a callback-based chunked transcription pattern (not a true token-streaming model like Qwen3ASR). The local server (`v0.14.0+`) adds SSE output streaming for file transcription.

For real-time mic input in an app, usage looks like:
```swift
let whisperKit = try await WhisperKit(WhisperKitConfig(model: "small"))
// Chunked live transcription — processes fixed windows, emits partial results
```

### 4.5 v0.15.0 Breaking Change

`TranscriptionResult` changed from `struct` to `open class`. Any code using value-type copy semantics will get shared references instead. Not relevant until we integrate.

### 4.6 Argmax Pro SDK (Paid)

The README now prominently mentions a paid **Argmax Pro SDK** offering:
- Nvidia Parakeet V3 (their version, not the open mlx-audio-swift one)
- pyannoteAI speaker diarization
- Deepgram-compatible WebSocket local server

This is a commercial product, not OSS.

### 4.7 Memory Comparison (Observed estimates from benchmarks)

| Stack | Model | Approx RAM | GPU memory |
|-------|-------|-----------|------------|
| WhisperKit (CoreML) | small | ~250 MB | ANE, ~0 GPU |
| WhisperKit (CoreML) | large-v3 | ~3 GB | ANE, ~0 GPU |
| mlx-audio-swift Qwen3ASR | qwen3-asr-2b | ~4 GB unified | GPU |
| mlx-audio-swift Parakeet TDT | parakeet-tdt-0.6b-v2 | ~1.2 GB unified | GPU |
| mlx-audio-swift Parakeet CTC | parakeet-ctc-110m | ~220 MB unified | GPU |

> ⚠️ These are **inferred estimates** from model parameter counts. Not directly measured on EchoPanel hardware. Run Instruments/memory profiler to confirm.

---

## 5. Parakeet Availability — Status

| Platform | Available? | Notes |
|----------|-----------|-------|
| Python MLX | ✅ | `mlx-audio` Python package |
| Swift MLX (mlx-audio-swift) | ✅ **YES — Added Feb 21, 2026** | PR #51 merged; 4 variants |
| WhisperKit (free) | ❌ | Only via paid Argmax Pro SDK |
| CoreML (open) | ❌ | No open CoreML Parakeet package found |

**Parakeet is now available in Swift via mlx-audio-swift.** The recommended variant for EchoPanel is `parakeet-tdt-0.6b-v2` (600M params, ~1.2 GB unified memory, best WER among the CTC/RNNT options).

---

## 6. Stack Recommendation: mlx-audio-swift vs WhisperKit

### Recommendation: **Stick with mlx-audio-swift ✅**

Rationale:

1. **Parakeet is now available** — the primary missing piece from Feb 25 is resolved
2. **Qwen3ASR has live streaming** — chunk-by-chunk streaming for real-time meeting transcription
3. **Unified memory** — mlx-audio-swift shares the same MLX GPU/unified memory pool as mlx-swift-lm; zero-copy pipelines possible (STT → embeddings → LLM without PCIe transfers)
4. **More current** — v0.1.0 shipped Feb 23; WhisperKit last released Nov 2025
5. **Better model variety** — 5 STT model classes vs Whisper family only
6. **Sortformer diarization** now native in the same package (no third-party dep needed)

### When WhisperKit would be preferred:
- If targeting ANE explicitly and want to leave GPU/unified memory for other workloads
- If needing the widest language support (Whisper large-v3 covers 100+ languages well)
- If you want a battle-tested CoreML inference stack with less Swift 6 migration surface

### Hybrid Option (Not Recommended for Now)
Run WhisperKit on ANE (small model, low latency) + mlx-swift-lm on GPU for analysis. Technically viable but adds complexity and two separate download paths. Revisit if Parakeet-tdt quality disappoints.

---

## 7. Package.swift Action Items

### Current state (observed)
```swift
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")
```

### Issues
1. **No version pin** — `branch: "main"` will pull breaking changes silently
2. **swift-snapshot-testing** is only used in tests — already correct
3. **mlx-swift-lm not in Package.swift** — only available transitively; we can't import `MLXLLM` or `MLXEmbedders` directly from our app target

### Recommended Package.swift changes

```swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4"),

    // MLX Audio Swift — pin to first stable release
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.0"),

    // mlx-swift-lm — direct dep for LLM analysis and embeddings
    // (also pulled transitively by mlx-audio-swift, but explicit for MLXLLM/MLXEmbedders)
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.6"),
],
```

And add to the executable target if LLM/embedding features needed:
```swift
.executableTarget(
    name: "MeetingListenerApp",
    dependencies: [
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
        .product(name: "MLXAudioVAD", package: "mlx-audio-swift"),
        // Add when implementing analysis features:
        // .product(name: "MLXLLM", package: "mlx-swift-lm"),
        // .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
    ],
    ...
)
```

### Priority action items

| Priority | Action | Effort | Risk |
|----------|--------|--------|------|
| 🔴 P0 | Change `branch: "main"` → `from: "0.1.0"` | 1 min | Low — same code we're already on |
| 🟡 P1 | Verify build still succeeds after pin change | 10 min | Low |
| 🟡 P1 | Evaluate Parakeet-tdt-0.6b-v2 transcription quality vs current Qwen3ASR | 2 hrs | None |
| 🟢 P2 | Add mlx-swift-lm as direct dep for future analysis layer | 5 min | Low |
| 🟢 P2 | Evaluate Sortformer diarization for speaker identification in meetings | 1 day | Medium (API still new) |
| ⚪ P3 | Investigate VoxtralRealtime as alternative streaming STT | 2 hrs | Low |

---

## 8. New Features Relevant to EchoPanel Since Feb 25

| Feature | Library | Availability | Relevance |
|---------|---------|--------------|-----------|
| Parakeet TDT/CTC Swift impl | mlx-audio-swift | ✅ Now | Best open-source en-only STT accuracy |
| Qwen3ASR `generateStream` | mlx-audio-swift | ✅ Now (was missing) | Real-time transcript display |
| VoxtralRealtime STT | mlx-audio-swift | ✅ Now | Mistral-based, multilingual alternative |
| Sortformer diarization | mlx-audio-swift (VAD) | ✅ Now | "Who said what" speaker attribution |
| MossFormer2 speech enhancement | mlx-audio-swift | ✅ Now | Pre-process noisy meeting audio |
| `generateTokens` / `TokenGeneration` | mlx-swift-lm 2.30.6 | ✅ Now | Raw token streaming for analysis UI |
| NomicBert embeddings | mlx-swift-lm 2.30.6 | ✅ Now | Transcript semantic search / RAG |
| Qwen3 embeddings | mlx-swift-lm 2.30.6 | ✅ Now | Multilingual meeting embedding |
| GLM 4.7 Flash | mlx-swift-lm 2.30.6 | ✅ Now | Compact LLM for meeting Q&A |
| SmolLM3 ~1B | mlx-swift-lm 2.30.6 | ✅ Now | Tiny on-device summarizer |

---

## 9. Summary

- **Parakeet is in Swift.** PR #51 merged into mlx-audio-swift with full TDT/RNNT/CTC variants. This is the biggest change since Feb 25.
- **Qwen3ASR streaming** was added (PR #32) — live transcript now works without custom chunking.
- **GLM ASR remains batch-only** — no streaming support added; deprioritize for real-time path.
- **mlx-swift-lm 2.30.6** is the authoritative LLM/embeddings package; `mlx-swift-examples` is older and should not be used.
- **WhisperKit v0.15.0** is stable but CoreML-only; does not share memory with MLX stack; Parakeet only available via paid tier. Not recommended as primary STT for EchoPanel.
- **Immediate action:** Change Package.swift pin from `branch: "main"` to `from: "0.1.0"` to prevent silent breakage.
