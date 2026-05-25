<overview>
The user (pranaysuyash, HuggingFace Pro account) wanted deep research on the Apple Silicon ML ecosystem for their EchoPanel project — a macOS menu bar app with local FastAPI backend and audio pipeline. The research covered MLX, MLX Audio, MLX Swift, MLX Audio Swift, Argmax SDK v2, Prince Canuma's GitHub work, and then expanded to cover ALL local inference options for Mac (not just MLX), including llama.cpp, Ollama, CoreML, Transformers+MPS, with live HuggingFace API data pulled using their actual token.
</overview>

<history>
1. **User asked for research on MLX, MLX Audio, MLX Swift, MLX Audio Swift, Argmax SDK v2, Prince Canuma, and HuggingFace Pro access**
   - Searched GitHub for `ml-explore/mlx`, `Blaizzy/mlx-audio`, `Blaizzy/mlx-audio-swift`, `ml-explore/mlx-swift`
   - Fetched READMEs directly from all four repos
   - Searched GitHub for Argmax/WhisperKit, fetched `argmaxinc/WhisperKit` README
   - Web-searched for Argmax SDK v2 details and Prince Canuma's identity
   - Web-searched for HuggingFace Pro and Transformers v4 local inference
   - Discovered Prince Canuma = GitHub user `Blaizzy`, author of mlx-audio (citation in README: `author = {Canuma, Prince}`)
   - Saved first report to session research folder

2. **User said they have HF Pro access and token in env — use it for live data**
   - Found token in `/Users/pranay/Projects/EchoPanel/.env`: `HF_TOKEN=[REDACTED]`
   - Confirmed account via `huggingface.co/api/whoami-v2`: user=`pranaysuyash`, `isPro: true`, `billingMode: prepaid`, token name=`model-lab-read` (read role)
   - Discovered old `api-inference.huggingface.co` is deprecated — new endpoint is `router.huggingface.co`
   - Queried warm models, meta-llama gated model list, user's own models (`pranaysuyash/example-model`)
   - Member of `25daysofagents` org

3. **User said "don't limit to my laptop" — research best small Mac-local models broadly**
   - Queried mlx-community org: 200+ models across text-gen, ASR, TTS, VLM, embeddings, VAD
   - Queried Ollama API for current model catalog (32 models, filtered Mac-feasible <70GB)
   - Queried top GGUF models by downloads
   - Queried CoreML models on HuggingFace
   - Got actual download counts for all key models

4. **User asked to expand beyond MLX — cover ALL Mac local inference options**
   - Researched llama.cpp, Ollama, Transformers+MPS, CoreML/ANE, LM Studio, Jan.ai, MLC-LLM
   - Pulled live HF API data for: top text-gen models, GGUF models, coding models, reasoning models (DeepSeek R1 distilled), VLMs, ASR, TTS, embeddings, diarization
   - Verified Ollama model sizes from live Ollama API
   - Web-searched framework performance benchmarks (tok/s on Apple Silicon)
   - Wrote comprehensive report covering all 6 frameworks + best models by category + RAM guide
</history>

<work_done>
Files created:
- `/Users/pranay/.copilot/session-state/731f3f7f-7049-4c3b-a51f-98c9de151c65/research/i-need-you-to-research-on-mlx-mlx-audio-mlx-swift-.md`
  - First research report: MLX, MLX Swift, MLX Audio, MLX Audio Swift, Argmax SDK v2, Prince Canuma, HuggingFace Pro (no live API data)

- `/Users/pranay/.copilot/session-state/731f3f7f-7049-4c3b-a51f-98c9de151c65/research/mac-local-inference-complete-guide.md`
  - Full expanded report: ALL Mac inference frameworks + best models by category + live HF API data + RAM guide + framework comparison matrix + EchoPanel-specific recommendations

Work completed:
- [x] Research MLX framework, MLX Swift, MLX LM
- [x] Research MLX Audio (Python) — Blaizzy/mlx-audio
- [x] Research MLX Audio Swift — Blaizzy/mlx-audio-swift
- [x] Research Argmax SDK v2 / WhisperKit / SpeakerKit Pro
- [x] Identify Prince Canuma = GitHub:Blaizzy, HF:prince-canuma
- [x] Verify HF token and account (pranaysuyash, isPro:true)
- [x] Live-query mlx-community models (200+ models, download counts)
- [x] Live-query Ollama current model catalog (32 models, sizes)
- [x] Live-query top GGUF models by downloads
- [x] Live-query CoreML models on HuggingFace
- [x] Research llama.cpp, Ollama, Transformers+MPS, LM Studio, Jan.ai, CoreML/ANE
- [x] Framework performance benchmark comparison
- [x] Build best-models-by-category tables with live download data
- [x] RAM requirements guide by Mac memory tier
</work_done>

<technical_details>
**HuggingFace Account:**
- User: `pranaysuyash`, token: `[REDACTED]` (in `.env`)
- Token name: `model-lab-read`, role: `read` — sufficient for API queries and gated model access
- `canPay: false` but `isPro: true` with prepaid billing, `periodEnd: 1772323200`
- Member of org: `25daysofagents`
- Old inference endpoint (`api-inference.huggingface.co`) is DEPRECATED — use `router.huggingface.co`
- `inferenceProviderMapping` field in model API response was empty `{}` for all tested models (may require write token or different endpoint to see)

**MLX Ecosystem:**
- Prince Canuma = GitHub `Blaizzy`, HF `prince-canuma` — confirmed from README citation
- MLX community org on HF has 200+ pre-converted models
- Most popular mlx-community model by downloads: `Kimi-K2.5` (3.6M), then `gemma-3-4b-it-qat-4bit` (587K for VLM)
- SwiftPM CLI cannot build Metal shaders — must use Xcode/xcodebuild
- MLX arrays live in unified memory — no CPU↔GPU transfer needed

**Argmax SDK v2:**
- No public GitHub repo `argmaxinc/argmax-sdk` exists — it's a closed Pro SDK
- GA date: February 2026 (early access December 2025)
- Open-source: `argmaxinc/WhisperKit` (free, CoreML-based)
- Pro: WhisperKit Pro (Parakeet v3) + SpeakerKit Pro (Nvidia Sortformer + pyannoteAI)
- Uses `app.argmaxinc.com` for API key access

**Model Size Formula:**
- bf16 RAM ≈ params × 2 bytes / 1e9 GB
- 4-bit RAM ≈ params × 0.5 bytes / 1e9 GB
- safetensors `total` field gives param count — many models had `total: 0` (not uploaded yet or sharded without metadata)

**Key Model Facts (live data):**
- `parakeet-tdt-0.6b-v3` in mlx-community: 286K downloads — most popular MLX ASR
- `argmaxinc/whisperkit-coreml`: 4.97M downloads — most downloaded ASR model on all of HuggingFace
- `pyannote/speaker-diarization-3.1`: 12.9M downloads, gated:auto — Pro account should auto-approve
- Qwen3-0.6B: 10M downloads — most downloaded model under 1B params
- `gemma-3-4b-it-qat-4bit` in mlx-community: 586K downloads — most popular VLM in mlx-community
- DeepSeek-R1-Distill-Qwen-7B: 7616M params (7.6B), bf16=15.2GB, 4bit=3.8GB

**Ollama:** Only 32 featured models in their API; many more via `ollama pull <name>`. Mac-feasible range starts at `ministral-3:3b` (4.7GB).

**MoE Models for Mac:** Qwen3-30B-A3B and Qwen3-Coder-30B-A3B use MoE with only ~3B active params — run at 3B speed on 32GB Mac despite 30B total capacity.

**Framework Performance (M2/M3 verified benchmarks):**
- MLX: 30–70+ tok/s (8B), best sustained throughput
- llama.cpp: 25–60 tok/s (8B), lowest idle RAM (~100MB)
- Ollama: 15–35 tok/s (8B), easiest setup
- Transformers+MPS: 10–25 tok/s (8B), slowest but most compatible
</technical_details>

<important_files>
- `/Users/pranay/Projects/EchoPanel/.env`
  - Contains `HF_TOKEN=[REDACTED]` and `ECHOPANEL_HF_TOKEN`
  - Critical: verified working HF Pro token for API access

- `/Users/pranay/.copilot/session-state/731f3f7f-7049-4c3b-a51f-98c9de151c65/research/mac-local-inference-complete-guide.md`
  - The primary comprehensive research report
  - Covers all 6 inference frameworks, best models by category, live download stats, RAM guide, framework comparison matrix, EchoPanel-specific recommendations
  - Sections: Framework Landscape, MLX, llama.cpp, Ollama, Transformers+MPS, CoreML/ANE, LM Studio/Jan.ai, Models by category (LLM/Reasoning/Coding/VLM/ASR/TTS/Embeddings/Diarization), Hardware RAM Guide, Framework Comparison Matrix, Recommended Stack by Use Case, HF Pro account details

- `/Users/pranay/.copilot/session-state/731f3f7f-7049-4c3b-a51f-98c9de151c65/research/i-need-you-to-research-on-mlx-mlx-audio-mlx-swift-.md`
  - First report — covers MLX, MLX Swift, Prince Canuma, Argmax SDK v2, HuggingFace Pro conceptually (no live API data)
  - Still useful for Argmax SDK v2 Swift code examples and detailed MLX Audio model tables
</important_files>

<next_steps>
No pending tasks — all requested research has been completed and documented.

If the user wants to continue, likely next steps based on context:
- Apply research findings to EchoPanel's architecture (server/ FastAPI backend + macapp/ Swift UI)
- Choose and integrate a specific STT model (Parakeet v3 via mlx-audio or WhisperKit for Swift)
- Set up local LLM endpoint (Ollama or mlx-lm) for the EchoPanel pipeline
- Configure pyannote/speaker-diarization-3.1 (user needs to accept terms on HF model card once)
- Implement mlx-audio-swift into macapp/ for native audio processing
</next_steps>
