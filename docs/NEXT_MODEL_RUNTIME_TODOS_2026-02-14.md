# Next Model Runtime TODOs (2026-02-14)

This doc captures the next concrete model/runtime exploration tasks surfaced while reviewing EchoPanel's current provider set.

## Current State (Observed In Repo)

### ASR (Speech-to-Text) Providers

Implemented providers in `/Users/pranay/Projects/EchoPanel/server/services/`:

- `provider_faster_whisper.py` (faster-whisper / CTranslate2)
- `provider_whisper_cpp.py` (whisper.cpp via `whisper-cli`, Metal on Apple Silicon)
- `provider_mlx_whisper.py` (mlx-whisper Python, Metal on Apple Silicon)
- `provider_voxtral_realtime.py` (voxtral.c `--stdin` resident streaming process)
- `provider_onnx_whisper.py` (ONNX Runtime + CoreML EP) **scaffold only**: the inference path is currently placeholder

Provider exports/registration live in:
- `/Users/pranay/Projects/EchoPanel/server/services/__init__.py`
- `/Users/pranay/Projects/EchoPanel/server/services/asr_providers.py`

### Config Surface Drift

`.env.example` historically only listed a subset of providers; updated to reflect the real provider menu and to flag ONNX as not implemented:
- `/Users/pranay/Projects/EchoPanel/.env.example`

## Gaps (Observed)

### 1) ONNX/CoreML Whisper Is Not Implemented

`provider_onnx_whisper.py` advertises ONNX+CoreML, but the actual inference path is TODO/placeholder text.

Impact:
- We cannot currently treat ONNX/CoreML as a real option for production or benchmarks.

Evidence:
- `/Users/pranay/Projects/EchoPanel/server/services/provider_onnx_whisper.py`

### 2) LLM/“Intelligence Layer” Runtime Is Still Mostly Planned

Decision doc describes an opt-in LLM provider strategy (cloud key, optional Ollama later), but the provider abstraction is not yet wired into the live pipeline.

Evidence:
- `/Users/pranay/Projects/EchoPanel/docs/DECISIONS.md`
- `/Users/pranay/Projects/EchoPanel/server/services/analysis_stream.py`

## External Candidates To Evaluate (Not Yet Integrated)

### A) MLX Swift Audio Stack (“mlx-audio-swift”)

Goal: validate whether we can run audio models (TTS and potentially ASR) via Swift-native MLX inside `macapp/` to reduce dependence on the embedded Python server for premium/offline tiers.

Notes:
- `mlx-audio` exists as a Python library for audio generation; its README references an `mlx-audio-swift` package as a Swift counterpart.

Links:
- MLX Audio (Python): [ml-explore/mlx-audio](https://github.com/ml-explore/mlx-audio)
- MLX Swift (core): [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift)

### B) Qwen3-ASR

Goal: evaluate Qwen3-ASR as an alternative ASR engine (either local weights or API-backed), and determine whether it can fit EchoPanel’s latency + memory budgets.

Links:
- Qwen3-ASR (project site): [qwenasr.com](https://qwenasr.com/)
- Qwen3-ASR technical report: [arXiv:2601.21337](https://arxiv.org/abs/2601.21337)

## Next TODOs (Concrete)

### P0 (Unblock Real Options)

1. Decide what “CoreML ASR” means for EchoPanel:
   - Either implement `onnx_whisper` end-to-end (preprocess, encoder/decoder, tokenizer) and document model conversion + supported variants.
   - Or explicitly de-scope it (delete/disable provider) and keep the option list honest.

2. Add a single “model runtime matrix” doc as the canonical truth for:
   - ASR: faster-whisper vs whisper.cpp vs MLX Whisper vs Voxtral vs Qwen3-ASR (candidate)
   - LLM: cloud key vs Ollama vs llama.cpp vs MLX (Python) vs MLX (Swift) vs ONNX Runtime GenAI
   - Embeddings: sentence-transformers vs ONNX (FastEmbed-style) vs Gemma embeddings vs Qwen embeddings

### P1 (Productize Breadth)

3. Introduce an `LLMProvider` abstraction in the server (mirroring the ASR provider abstraction):
   - `none` (keyword-only)
   - `openai` (user key)
   - `ollama` (local)
   - (future) `mlx` / `llama_cpp` / `onnxruntime_genai`

4. Wire `ECHOPANEL_LLM_PROVIDER` through:
   - settings UI (macapp)
   - backend process env injection (macapp)
   - `analysis_stream.py` routing

### P2 (Swift-Native Premium Path)

5. Investigate a Swift-native inference path for premium/offline mode:
   - Validate `mlx-audio-swift` existence and maturity.
   - Spike: run a small MLX Swift model in-process inside the mac app, measure CPU/GPU, memory, and latency.
   - If viable: define a “no-python” mode contract (what features stay, what changes).

6. Qwen3-ASR feasibility spike:
   - Determine whether we can run locally on Apple Silicon (MLX/Swift/other) or only via API.
   - If API-only: decide if it fits the product privacy story (likely opt-in only).

