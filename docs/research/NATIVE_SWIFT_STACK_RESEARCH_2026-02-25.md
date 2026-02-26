# EchoPanel — Native Swift Stack Research
**Date:** 2026-02-25 | **Scope:** Replace FastAPI Python backend with native Swift/MLX where possible

---

## Executive Summary

**6 of 7 backend areas have production-ready Swift replacements today.**  
The only partial gap is vector search at scale — a brute-force vDSP approach covers EchoPanel's corpus size.  
Key discovery: **FluidAudio** (open-source SDK) replaces pyannote.audio + Silero VAD entirely in Swift via CoreML/ANE.

---

## ASR Model Fallback Chain (mlx-audio-swift)

### Constraint (observed from source)
`StreamingInferenceSession` in mlx-audio-swift is **Qwen3ASRModel-only**.  
`GLMASRModel` has its own `generateStream` — different API, batch-only friendly.

### Chain Design

| Priority | Model | HF ID | Downloads | Notes |
|----------|-------|--------|-----------|-------|
| 1 (Primary) | Qwen3-ASR-0.6B-4bit | `mlx-community/Qwen3-ASR-0.6B-4bit` | 1,052 | Streaming ✅ Fast |
| 2 | Qwen3-ASR-1.7B-4bit | `mlx-community/Qwen3-ASR-1.7B-4bit` | 300 | Streaming ✅ More accurate |
| 3 | Qwen3-ASR-1.7B-8bit | `mlx-community/Qwen3-ASR-1.7B-8bit` | 2,034 | Streaming ✅ Best native quality |
| 4 | GLM-ASR-Nano-2512-4bit | `mlx-community/GLM-ASR-Nano-2512-4bit` | 344 | Batch only ⚠️ Different arch, diversity fallback |
| 5 (Final) | Python FastAPI | existing PythonBackend | — | Ultimate fallback, diarization |

**Trigger to fall back:**
- Model fails to load (OOM, corrupt download)
- RTF > 2.0 sustained over 3 chunks (model too slow for this device)
- 3 consecutive transcription errors

**Note:** Parakeet-TDT-0.6b-v3 (`mlx-community/parakeet-tdt-0.6b-v3`, 286k downloads) is NOT supported by mlx-audio-swift's current Swift API — it uses a different model class not yet ported to Swift. It's only available via Python `mlx-audio`. Revisit when mlx-audio-swift adds Parakeet support.

**CoreML option (no streaming, but ANE-powered):**
`FluidInference/qwen3-asr-0.6b-coreml` (292 downloads) — runs on ANE, lowest power draw. Add as optional Tier 1A for battery-critical mode.

---

## Area 1 — Speaker Diarization

**Replaces:** `server/services/diarization.py` (pyannote.audio, torch, GPU)

### ✅ FluidAudio — production-ready, open-source

```
github.com/FluidInference/FluidAudio
```

- Based on NVIDIA Sortformer (same as mlx-audio-swift's VAD module)
- Runs on **Apple Neural Engine** via CoreML — minimal CPU/power
- Handles overlapping speech (Sortformer's key strength over pyannote)
- Used in production by: BoltAI, VoiceInk, Spokenly, Whisper Mate
- Models: `FluidInference/diar-streaming-sortformer-coreml` (488 downloads), `mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16` (418 downloads)

```swift
import FluidAudio
let diarizer = try await DiarizerManager(model: .sortformer)
let segments = try await diarizer.diarize(audioURL: sessionURL)
// [DiarizationSegment(speaker: "SPEAKER_0", start: 0.0, end: 2.4), ...]
```

**Note:** mlx-audio-swift already includes Sortformer source at `Sources/MLXAudioVAD/` with full `DiarizationOutput`, `DiarizationSegment`, `StreamingState` types — but it lacks the high-level `DiarizerManager` orchestration. FluidAudio provides that on top.

---

## Area 2 — Voice Activity Detection

**Replaces:** `server/services/vad_filter.py` (Silero VAD via torch.hub)

### ✅ FluidAudio VadManager — same Silero model, native ANE

```swift
import FluidAudio
let vad = try await VadManager(model: .sileroV4)
vad.processAudioChunk(samples: pcmBuffer) { event in
    switch event {
    case .speechStart(let ts): ...
    case .speechEnd(let ts, let audio): ...
    }
}
```

Exact same Silero VAD v4/v5 model as Python version, converted to CoreML.

**Note on `aufklarer/Silero-VAD-v5-MLX`** (HF, 0 downloads) — unverified, not recommended.

---

## Area 3 — Embeddings

**Replaces:** `server/services/embeddings.py` (sentence-transformers)

### ✅ MLXEmbedders (ml-explore/mlx-swift-lm)

```
github.com/ml-explore/mlx-swift-lm
Target: MLXEmbedders
```

Pre-registered models (verified in Libraries/MLXEmbedders/Models.swift):

| Constant | Model | Best for |
|----------|-------|----------|
| `.minilm_l6` | all-MiniLM-L6-v2 | Fast, lightweight |
| `.bge_small` | BAAI/bge-small-en-v1.5 | Retrieval |
| `.bge_m3` | BAAI/bge-m3 | Multilingual |
| `.qwen3_embedding` | mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ | Best quality/size (7,340 DL) |
| `.nomic_text_v1_5` | nomic-ai/nomic-embed-text-v1.5 | Long context |

**Recommendation for EchoPanel Brain Dump:** `Qwen3-Embedding-0.6B-4bit-DWQ` — 4-bit, fast, high quality.

**Also available:** `mlx-community/embeddinggemma-300m-4bit` (4,624 downloads) — smaller, very fast.

---

## Area 4 — LLM Analysis

**Replaces:** `server/services/llm_providers.py` (OpenAI / Ollama)  
**Replaces:** `server/services/analysis_stream.py` (card/entity extraction)

### ✅ MLXLLM (ml-explore/mlx-swift-lm)

```swift
import MLXLMCommon
let model = try await loadModel(id: "mlx-community/Qwen3-4B-4bit")
let session = ChatSession(model)
let response = try await session.respond(to: "Extract action items from: \(transcript)")
```

**Recommended models for analysis:**

| Model | Size | Use case |
|-------|------|----------|
| `mlx-community/SmolLM2-1.7B-Instruct-4bit` | ~1GB | Fast card/entity extraction |
| `mlx-community/Qwen3-4B-4bit` | ~2.5GB | Balanced reasoning + analysis |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | ~2GB | Reliable instruction following |
| `mlx-community/gemma-3-1b-it-qat-4bit` | ~0.6GB | Ultra-light, always-on |

---

## Area 5 — OCR

**Replaces:** `server/services/ocr_hybrid.py` (PaddleOCR + SmolVLM)

### ✅ Two-tier native approach

**Tier 1 — Apple Vision (text extraction from slides/docs)**
```swift
import Vision
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
try VNImageRequestHandler(cgImage: image).perform([request])
let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
```
- Zero model download, runs on ANE, excellent on clean text
- Direct replacement for PaddleOCR in slide/document context

**Tier 2 — MLXVLM (screenshot understanding)**
```swift
import MLXVLM
// mlx-community/SmolVLM-Instruct-4bit (452 DL) or SmolVLM2-256M (689 DL)
let model = try await loadModel(id: "mlx-community/SmolVLM2-256M-Video-Instruct-mlx")
```
Use only when Vision OCR confidence < threshold or for contextual understanding.

---

## Area 6 — Brain Dump / RAG Storage

**Replaces:** `server/db/` (SQLite), `server/services/rag_store.py`

### ✅ GRDB.swift + brute-force vDSP vector search

```swift
// GRDB for FTS5 + structured storage
// vDSP for cosine similarity (sufficient for ≤50k chunks)
import Accelerate

func cosineTopK(query: [Float], corpus: [[Float]], k: Int) -> [(Int, Float)] {
    corpus.enumerated().map { i, vec in
        var dot: Float = 0
        vDSP_dotpr(query, 1, vec, 1, &dot, vDSP_Length(query.count))
        return (i, dot)
    }.sorted { $0.1 > $1.1 }.prefix(k).map { $0 }
}
```

**Note:** No native Swift ANN package exists yet. sqlite-vec (C extension) is an option for >50k chunks but requires C bridging. For EchoPanel's corpus size, brute-force is fast enough.

---

## Full Migration Decision Matrix

| Service | Python File | Swift Replacement | Package | Status |
|---------|-------------|-------------------|---------|--------|
| STT (streaming) | `asr_stream.py` | `NativeMLXBackend` (Qwen3ASR) | `mlx-audio-swift` ✅ already in Package.swift | **DONE** |
| STT (fallback) | `provider_faster_whisper.py` | WhisperKit | `argmaxinc/WhisperKit` | Add |
| VAD | `vad_filter.py` | FluidAudio VadManager | `FluidInference/FluidAudio` | Add |
| Diarization | `diarization.py` | FluidAudio DiarizerManager | `FluidInference/FluidAudio` | Add |
| Embeddings | `embeddings.py` | MLXEmbedders | `ml-explore/mlx-swift-lm` | Add |
| LLM analysis | `llm_providers.py` | MLXLLM + ChatSession | `ml-explore/mlx-swift-lm` | Add |
| OCR text | `ocr_paddle.py` | VNRecognizeTextRequest | Apple Vision (built-in) | Implement |
| OCR VLM | `ocr_smolvlm.py` | MLXVLM | `ml-explore/mlx-swift-lm` | Add |
| RAG storage | `rag_store.py` | GRDB + SwiftData | `groue/GRDB.swift` | Add |
| Vector search | `hybrid_search.py` | vDSP brute-force | Accelerate (built-in) | Implement |
| Brain dump | `brain_dump_indexer.py` | SwiftData + GRDB | `groue/GRDB.swift` | Add |

### What stays in Python (for now)
| Service | Reason |
|---------|--------|
| `analysis_stream.py` | Migrate to Swift MLXLLM gradually; currently handles sliding window logic |
| Session HTTP API | Keep minimal FastAPI for settings sync / session management until full Swift rewrite |

---

## Recommended Package.swift Update

```swift
dependencies: [
    // Already present
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4"),

    // Add these
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),          // STT fallback + ANE
    .package(url: "https://github.com/FluidInference/FluidAudio", branch: "main"),         // Diarization + VAD
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.29.1")), // LLM + VLM + Embeddings
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),              // RAG storage
],
```

**Min deployment target:** macOS 14.0 (already set in Package.swift ✅)

---

## Risks & Caveats

1. **FluidAudio precompiled frameworks** — CoreML models are pre-converted binaries. Cannot customize without their `möbius` tool.
2. **mlx-swift-lm version churn** — `MLXEmbedders` and `MLXLLM` moved from mlx-swift-examples to mlx-swift-lm. Pin to `.upToNextMinor` to avoid breakage.
3. **Parakeet not yet in Swift** — mlx-audio-swift only has Qwen3ASR + GLMASR. Parakeet (best English ASR) is Python-only for now.
4. **MLXLLM first-run download** — Qwen3-4B-4bit = ~2.5GB. Need UX for first-launch model fetch.
5. **WhisperKit vs mlx-audio-swift coexistence** — both can run simultaneously but both use Metal/MLX. Test memory pressure on 8GB Macs.
