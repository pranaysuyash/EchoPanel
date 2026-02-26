# Decisions

This is a lightweight decision log. Prefer short entries that explain why.

## v0.1
- Capture: Use ScreenCaptureKit (macOS 13+) to capture system audio output without virtual drivers.
- Streaming: Use WebSocket; stream PCM16 16 kHz mono frames.
- UI: Three lanes only in the side panel (Transcript, Cards, Entities).
- No diarization in v0.1.

## v0.2
- Multi-source audio: JSON-tagged frames with `source: "system" | "mic"` instead of raw binary.
- Diarization: batch-only at session end via pyannote; requires user-provided HuggingFace token; disabled by default.
- Session storage: auto-save every 30s with crash recovery.
- Embedded backend: macOS app starts/stops the Python server automatically.

## v0.3 (planned)

### LLM-Powered Analysis Strategy (decided 2026-02-06, updated 2026-02-15)

**Decision**: Hybrid approach — keyword extraction as default, LLM as opt-in upgrade via user's own API key (cloud) OR local Ollama (Option D+B+A).

**Why**: Preserves "works offline out of the box" while enabling production-quality analysis for users who want it. Added Ollama support due to availability of lightweight 3B models (2025-2026).

**Options evaluated**:

| Option | Description | Status |
|--------|-------------|--------|
| A: Ollama (local LLM) | User installs Ollama + pulls 2-4GB model | **IMPLEMENTED** — 3B models (llama3.2, qwen2.5, gemma2) now viable on 8GB Macs |
| B: User's own cloud API key | User enters OpenAI/Anthropic key in Settings | **IMPLEMENTED** — OpenAI GPT-4o/4o-mini supported |
| C: Our hosted API | We run the LLM, user connects to our backend | **Rejected** — Requires servers, auth, billing, GDPR, on-call — too heavy for solo dev |
| D: Hybrid default | Keyword extraction default + optional LLM | **IMPLEMENTED** — Always-available fallback |

**Key architectural constraints**:
- The LLM never touches audio. It only processes transcript text that ASR already produced locally.
- Audio capture (ScreenCaptureKit) and ASR (faster-whisper) always run locally — this never changes.
- Privacy story: "Audio never leaves your Mac. Transcript text can optionally be sent to your own LLM provider for enhanced analysis."
- No user accounts, no auth, no billing infrastructure needed. User pays their LLM provider directly.
- Keyword extraction remains the always-available fallback (offline, zero cost, zero setup).

**Implementation scope** (completed 2026-02-15):
- ✅ `ECHOPANEL_LLM_PROVIDER` env var / Settings UI (values: `none`, `openai`, `ollama`)
- ✅ `ECHOPANEL_OPENAI_API_KEY` setting (stored in macOS Keychain, not env var)
- ✅ `analysis_stream.py`: LLM path alongside keyword path for `extract_cards()`, `generate_rolling_summary()`
- ✅ `llm_providers.py`: Provider abstraction with OpenAI + Ollama implementations
- ✅ Settings UI: "AI Analysis" tab with VAD + LLM configuration
- No changes to ASR pipeline, WebSocket protocol, or audio capture

**Recommended models (2026-02-15)**:

| Model | Params | RAM | Context | Best For |
|-------|--------|-----|---------|----------|
| **gemma3:1b** | 1B | ~0.8GB | 32k | 8GB Macs, basic extraction |
| **llama3.2:1b** | 1B | ~0.7GB | 128k | 8GB Macs, long context |
| **gemma3:4b** | 4B | ~2.5GB | 128k | 16GB Macs, best quality |
| **llama3.2:3b** | 3B | ~2GB | 128k | 16GB Macs, balanced |
| **qwen2.5:7b** | 7B | ~4.5GB | 128k | 16GB+ Macs, multilingual |
| gpt-4o-mini | - | - | - | Cloud option (best quality) |

**Model Notes**:
- **Gemma 3** (March 2025): Google's latest. 4B beats Gemma 2 27B on benchmarks. 1B perfect for 8GB Macs.
- **Llama 3.2**: Meta's edge models. 1B for low RAM, 3B for balanced quality.
- **Qwen2.5**: Alibaba's multilingual models. Excellent for non-English meetings.
- **Phi-4 Mini** (3.8B): Strong reasoning alternative.

**What changed the original decision**:
- ✅ **Ollama models now viable**: 2025-2026 brought lightweight 3B models (llama3.2, qwen2.5) that run in <3GB RAM, making Whisper + LLM feasible on 8GB Macs
- ✅ **User demand**: Beta feedback requested fully offline option
- ✅ **Implementation complete**: See `docs/LLM_ANALYSIS_ARCHITECTURE.md`

**Future considerations**:
- MLX native provider: Bypass Ollama overhead (~13-30% speed improvement on Apple Silicon) — see [LLM_ANALYSIS_ARCHITECTURE.md](LLM_ANALYSIS_ARCHITECTURE.md)
- Per-user custom prompts for domain-specific extraction
- Multi-model ensemble for higher accuracy

### Commercialization Strategy (decided 2026-02-06)

**Decision**: Hybrid (A+B) — monetize the packaged macOS app; open-source the backend/protocol.

**Why**: Privacy/local-only wedge is real and defensible. Open-sourcing the backend builds trust ("look, no exfiltration") without commoditizing the hard part (macOS capture + permissions + UX).

**Details**: See `docs/audit/COMMERCIALIZATION_STRATEGY_AUDIT_2026-02.md`

### Gap Priorities (decided 2026-02-06)

**Decision**: Address gaps in this order: (1) NLP quality via LLM, (2) Silero VAD, (3) Distribution blockers.

**Why**: NLP quality is the #1 difference between "toy" and "product." VAD prevents hallucinations. Distribution unblocks external users.

**Details**: See `docs/audit/GAPS_ANALYSIS_2026-02.md`

### ASR Provider Strategy — Voxtral Transcribe 2 (researched 2026-02-08)

**Decision**: Try Voxtral Realtime (4B, open-source) locally as alternative ASR provider. Keep pyannote for diarization. Voxtral Mini Transcribe V2 (paid API) is optional/future — only pursue if paid plan is justified.

**Why**: Voxtral Realtime is Apache 2.0 open weights — can self-host for free with no API key. 4B params is feasible on Apple Silicon. Better accuracy than Whisper large-v3 at sub-200ms latency. Diarization stays with pyannote since V2 (the only Voxtral model with native diarization) is API-only and paid.

**What we're doing**:

| Component | Now | Future (if paid justified) |
|-----------|-----|---------------------------|
| Live transcription | Faster-Whisper (default) + Voxtral Realtime local (try out) | Voxtral Realtime API ($0.006/min) |
| Diarization | pyannote (keep as-is) | Voxtral Mini Transcribe V2 API ($0.003/min) |

**Key facts**:
- Voxtral Realtime: 4B params, Apache 2.0, open weights on HuggingFace — free to self-host
- Voxtral Mini Transcribe V2: API-only (not open-source), $0.003/min, native diarization — skip for now
- Mistral API has free "Experiment" tier for testing if we want to try V2 later
- Same PCM16/16kHz input format EchoPanel already uses — no capture changes needed
- pyannote stays for diarization — already works, no reason to replace with a paid API

**What would change this decision**:
- If Voxtral Realtime runs well locally on M1 8GB → could become default over Faster-Whisper
- If Mistral open-sources V2 with diarization → could replace pyannote for free
- If paid V2 diarization quality is significantly better than pyannote → justify the API cost

**Details**: See `docs/VOXTRAL_RESEARCH_2026-02.md`

### Native Swift Primary ASR — NativeMLXBackend (decided 2026-02-25) ⬅ supersedes "ASR Provider Strategy — Voxtral Transcribe 2"

**Decision**: Use native Swift `mlx-audio-swift` (`NativeMLXBackend`) as the **primary** ASR path. Python FastAPI kept as **fallback only** (diarization hand-off, offline Python providers).

**Why**: EchoPanel is macOS-only. Native MLX runs entirely in unified memory — no CPU↔GPU transfer, no process IPC overhead, lower latency, lower power draw. The macOS app already has `NativeMLXBackend.swift`, `HybridASRManager`, and `ASRBackendProtocol` and builds successfully.

**Feature flags set**:
- `nativeBackendRolloutPercentage = 100`
- `isDevMode = true`

**What changed**:
- Primary ASR moves from Python faster-whisper/Voxtral → Swift mlx-audio-swift
- Voxtral Realtime (Python self-host) is no longer the evaluation target
- pyannote diarization is ALSO being replaced (see FluidAudio decision below)

**What stays**:
- Python FastAPI server remains for session HTTP API and complex LLM fallback until full Swift rewrite is complete

**What would change this decision**:
- If mlx-audio-swift develops a blocking bug on a required macOS release

---

### ASR Model Fallback Chain (decided 2026-02-25)

**Decision**: Use the following ordered fallback chain inside `NativeMLXBackend` / `HybridASRManager`:

1. `Qwen3-ASR-0.6B-4bit` (fastest, lowest RAM)
2. `Qwen3-ASR-1.7B-4bit`
3. `Qwen3-ASR-1.7B-8bit`
4. `GLM-ASR-Nano-2512-4bit` (batch-only — no streaming)
5. `PythonBackend` (FastAPI fallback)

**Constraints**:
- `StreamingInferenceSession` in mlx-audio-swift only works with `Qwen3ASRModel` — GLM is batch-only
- `Parakeet-TDT-0.6b-v3` (best English ASR benchmark) is **not yet available** in the Swift API — revisit when mlx-audio-swift adds support

**Fallback triggers**:
- OOM on model load
- RTF > 2.0 sustained for 3 consecutive chunks
- 3 consecutive inference errors

---

### Diarization + VAD: FluidAudio replaces pyannote (decided 2026-02-25) ⬅ supersedes "pyannote stays" from Voxtral decision

**Decision**: Replace `pyannote.audio` (Python / torch / GPU) with `FluidAudio` (Swift / CoreML / ANE) for both diarization and VAD.

**Why**: ANE execution is lower-power than pyannote's GPU path. Removes the HuggingFace token requirement. Keeps the entire pipeline inside the macOS app with no Python dependency for these two components.

**FluidAudio details**:
- Repo: `github.com/FluidInference/FluidAudio`
- Architecture: Sortformer-based diarization
- Distribution: open-source
- Used by: BoltAI, VoiceInk, Whisper Mate

**VAD**:
- Replaces Silero VAD Python with `FluidAudio VadManager` (same Silero model weights → CoreML)

**What changes**:
- `pyannote.audio` dependency removed from Python server once Swift migration complete
- Silero VAD Python path becomes unreachable after FluidAudio VAD is stable

**What would change this decision**:
- If FluidAudio diarization accuracy degrades significantly vs pyannote on our test corpus

---

### Full FastAPI Replacement Stack (decided 2026-02-25)

**Decision**: Replace each remaining Python service with a native Swift equivalent:

| Service | Python (current) | Swift replacement | Model / library |
|---------|-----------------|-------------------|-----------------|
| Embeddings | sentence-transformers | `MLXEmbedders` (ml-explore/mlx-swift-lm) | Qwen3-Embedding-0.6B-4bit |
| LLM analysis | Ollama / OpenAI | `MLXLLM ChatSession` (ml-explore/mlx-swift-lm) | Qwen3-4B-4bit or SmolLM2-1.7B |
| OCR text | pytesseract / EasyOCR | Apple Vision `VNRecognizeTextRequest` (built-in) | — |
| OCR VLM | — | `MLXVLM` (ml-explore/mlx-swift-lm) | SmolVLM2-256M |
| Storage / RAG | SQLite + pgvector | `GRDB.swift` + vDSP brute-force cosine | — |

**Why**: Eliminates Python process management overhead; keeps everything in unified memory; reduces app bundle complexity. vDSP brute-force cosine is adequate for EchoPanel's corpus size (no need for approximate nearest-neighbour index).

**Transition**: Python FastAPI kept for session HTTP API and complex LLM fallback until full Swift rewrite is validated.

**Details**: See `docs/research/NATIVE_SWIFT_STACK_RESEARCH_2026-02-25.md`

---

### Minimum Deployment Target: macOS 14.0 (confirmed 2026-02-25)

**Decision**: macOS 14.0 (Sonoma) is the minimum deployment target. Do **not** lower it.

**Why**: Required by mlx-audio-swift, FluidAudio, and SwiftData. Already set in `Package.swift`.

