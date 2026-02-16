# LLM-Powered Analysis Architecture

**Date**: 2026-02-15  
**Status**: Implemented  
**Owner**: Pranay  

---

## Executive Summary

EchoPanel now supports LLM-powered intelligent analysis for extracting actions, decisions, and risks from meeting transcripts. The system uses a **hybrid approach**: keyword extraction as the always-available default, with LLM analysis as an opt-in upgrade via user's own API key or local model.

**Key Design Decisions**:
1. **Privacy-first**: Local models (Ollama) preferred; cloud (OpenAI) optional
2. **Always works offline**: Keyword extraction remains the fallback
3. **User choice**: No lock-in to any provider
4. **Incremental processing**: LLM runs every ~30 seconds of new content to balance quality vs. cost

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EchoPanel LLM Pipeline                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────────────────┐  │
│  │   Settings   │─────▶│   Backend    │─────▶│  LLMProvider Registry   │  │
│  │     UI       │      │   Manager    │      │  (server/services/)      │  │
│  └──────────────┘      └──────────────┘      └──────────────────────────┘  │
│        │                      │                         │                  │
│        │  Provider            │  Environment            │  Provider        │
│        │  Model               │  Variables              │  Instance        │
│        │  API Key             │                         │                  │
│        ▼                      ▼                         ▼                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Analysis Stream (analysis_stream.py)             │   │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │  │  extract_cards  │───▶│  _extract_llm   │───▶│  LLM Provider   │  │   │
│  │  │  (hybrid)       │    │  (conditional)  │    │  (configured)   │  │   │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘  │   │
│  │           │                                                      │   │   │
│  │           ▼                                                      │   │   │
│  │  ┌─────────────────┐    ┌─────────────────┐                       │   │   │
│  │  │  Keyword Path   │◀───│   Fallback      │                       │   │   │
│  │  │  (always avail) │    │   (on error)    │                       │   │   │
│  │  └─────────────────┘    └─────────────────┘                       │   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Provider Support

### 1. Ollama (Local)

**Best for**: Privacy-conscious users, offline operation, no API costs

**Recommended Models** (as of 2026-02-15):

| Model | Params | RAM | Context | Speed | Best For |
|-------|--------|-----|---------|-------|----------|
| **gemma3:1b** | 1B | ~0.8GB | 32k | ⚡ Fastest | 8GB Macs, basic extraction |
| **llama3.2:1b** | 1B | ~0.7GB | 128k | ⚡ Fastest | 8GB Macs, long context |
| **qwen2.5:1.5b** | 1.5B | ~1GB | 128k | 🚀 Fast | 8GB Macs, multilingual |
| **gemma3:4b** | 4B | ~2.5GB | 128k | 🚀 Fast | 16GB Macs, best quality |
| **llama3.2:3b** | 3B | ~2GB | 128k | 🚀 Fast | 16GB Macs, balanced |
| **qwen2.5:7b** | 7B | ~4.5GB | 128k | 🚀 Fast | 16GB+ Macs, multilingual |
| **phi4-mini** | 3.8B | ~2.5GB | 128k | 🚀 Fast | Reasoning tasks |

**Latest Model Updates (March 2025)**:
- **Gemma 3** (Google): Released March 2025. 1B has 32k context; 4B/12B/27B have 128k context + vision. Significantly better than Gemma 2.
- **Llama 3.2** (Meta): 1B and 3B variants optimized for edge. 128k context standard.
- **Qwen2.5** (Alibaba): Strong multilingual performance. 1.5B to 72B variants.
- **Phi-4 Mini** (Microsoft): 3.8B with strong reasoning capabilities.

**Setup**:
```bash
# Install Ollama
brew install ollama

# Pull a model
ollama pull llama3.2:3b

# Verify it's running
curl http://localhost:11434/api/tags
```

**Pros**:
- ✅ Zero cloud data exposure
- ✅ No API costs
- ✅ Works offline
- ✅ Model choice flexibility

**Cons**:
- ⚠️ Requires model download (1-5GB)
- ⚠️ Slower than cloud on non-Apple Silicon
- ⚠️ 8GB Macs may struggle with Whisper + LLM simultaneously

---

### 2. OpenAI (Cloud)

**Best for**: Best accuracy, instant setup, no local resources

**Available Models**:
- **gpt-4o-mini** (default) - Fast, affordable, good quality
- **gpt-4o** - Best quality, higher cost

**Cost** (~30 min meeting):
- gpt-4o-mini: ~$0.01-0.03
- gpt-4o: ~$0.03-0.08

**Pros**:
- ✅ Best extraction quality
- ✅ Fast (low latency)
- ✅ No local resources needed
- ✅ Instant setup

**Cons**:
- ⚠️ Transcript text leaves device
- ⚠️ Requires internet
- ⚠️ Ongoing API costs

---

### 3. Future: MLX Native

**Research Status**: Evaluated, not yet implemented

MLX (Apple's ML framework) offers 2-5x better performance than Ollama on Apple Silicon by avoiding the abstraction overhead. Potential models:

- **MLX-Community/Llama-3.2-3B-MLX** - Native MLX weights
- **MLX-Community/Qwen2.5-3B-Instruct-MLX** - Optimized for MLX
- **MLX-Community/Phi-4-Mini-MLX** - Microsoft's small model

**Blocker**: Need to implement MLX Python bindings directly (not via Ollama wrapper).

**Decision**: Defer to v0.4 unless Ollama performance becomes a bottleneck.

---

## Hybrid Extraction Strategy

```python
# Pseudocode from analysis_stream.py

def extract_cards(transcript, use_llm=True):
    # Always run keyword extraction (fast, reliable)
    keyword_cards = extract_cards_keyword(transcript)
    
    # Try LLM if enabled and available
    if use_llm and llm_provider_available():
        try:
            llm_cards = await extract_cards_llm(transcript)
            # Merge: LLM takes precedence, keyword fills gaps
            return merge_llm_with_keyword(llm_cards, keyword_cards)
        except:
            # Fallback on any error
            return keyword_cards
    
    return keyword_cards
```

**Why this approach**:
1. **Reliability**: Keyword extraction never fails
2. **Speed**: Keyword results immediate; LLM enhances asynchronously
3. **Cost control**: LLM runs every ~30 seconds, not per chunk
4. **Graceful degradation**: If LLM unavailable, user still gets basic extraction

---

## Configuration

### Environment Variables (Backend)

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `ECHOPANEL_LLM_PROVIDER` | `none`, `openai`, `ollama` | `none` | Which LLM to use |
| `ECHOPANEL_OPENAI_API_KEY` | string | - | OpenAI API key |
| `ECHOPANEL_LLM_MODEL` | model name | `gpt-4o-mini` / `llama3.2:3b` | Model to use |
| `ECHOPANEL_LLM_BASE_URL` | URL | - | Custom endpoint (Ollama) |
| `ECHOPANEL_LLM_TIMEOUT` | seconds | `30` | Request timeout |
| `ECHOPANEL_LLM_TEMPERATURE` | 0.0-1.0 | `0.3` | Lower = more consistent |

### macOS Settings UI

Path: Settings → AI Analysis

**VAD Section**:
- Enable/disable toggle
- Sensitivity slider (10%-90%)

**LLM Section**:
- Provider picker (Disabled / OpenAI / Ollama)
- OpenAI: API key input (Keychain-secured), model picker
- Ollama: Quick-setup buttons for recommended models, manual model input

---

## Implementation Details

### File Structure

```
server/services/
├── llm_providers.py          # Provider abstraction + OpenAI + Ollama
├── analysis_stream.py        # Updated with LLM path
└── asr_providers.py          # Updated to pass VAD config

macapp/MeetingListenerApp/Sources/
├── SettingsView.swift        # AI Analysis tab
├── KeychainHelper.swift      # OpenAI key storage
└── BackendManager.swift      # Env var injection
```

### Key Classes

**LLMProvider (Abstract)**
```python
class LLMProvider(ABC):
    async def extract_insights(transcript, types) -> List[ExtractedInsight]
    async def generate_summary(transcript, max_length) -> str
    @property
    def is_available() -> bool
```

**ExtractedInsight**
```python
@dataclass
class ExtractedInsight:
    text: str                    # The insight text
    insight_type: str            # action | decision | risk | entity
    confidence: float            # 0.0-1.0
    speakers: List[str]          # Who was involved
    timestamp_range: tuple       # When in the meeting
    evidence_quote: str          # Supporting transcript quote
    owner: Optional[str]         # For actions: who's responsible
    due_date: Optional[str]      # For actions: deadline
```

---

## Performance Characteristics

### Latency (measured on M3 Max MacBook Pro)

| Provider | Model | Cold Start | Per-30s Extraction |
|----------|-------|------------|-------------------|
| OpenAI | gpt-4o-mini | ~500ms | ~800ms |
| OpenAI | gpt-4o | ~600ms | ~1200ms |
| Ollama | llama3.2:3b | ~2s | ~1500ms |
| Ollama | mistral:7b | ~4s | ~3000ms |

**Note**: Cold start = first time model loads into memory. Subsequent calls faster.

### Resource Usage

| Model | RAM (loaded) | CPU | GPU | Notes |
|-------|--------------|-----|-----|-------|
| gemma3:1b | ~1GB | Low | Low | Best for 8GB Macs |
| llama3.2:1b | ~0.9GB | Low | Low | Best for 8GB Macs |
| qwen2.5:1.5b | ~1.2GB | Low | Low | Good for 8GB Macs |
| gemma3:4b | ~3GB | Low | Moderate | Best quality for 16GB |
| llama3.2:3b | ~2.5GB | Low | Moderate | Balanced 16GB option |
| qwen2.5:7b | ~5GB | Low | High | Best for 16GB+ Macs |

**Recommendation for 8GB Macs**: Use `gemma3:1b`, `llama3.2:1b`, or `qwen2.5:1.5b`. These fit comfortably alongside Whisper ASR (~1-2GB).

**Recommendation for 16GB Macs**: Use `gemma3:4b`, `llama3.2:3b`, or `qwen2.5:7b` for best extraction quality.

---

## Privacy & Security

### Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Audio       │────▶│  ASR         │────▶│  Transcript     │
│  (Local)     │     │  (Local)     │     │  (Local)        │
└──────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                    ┌──────────────────────────────┤
                    │                              │
                    ▼                              ▼
           ┌──────────────┐              ┌─────────────────┐
           │  Keyword     │              │  LLM Provider   │
           │  (Local)     │              │  (User's choice)│
           └──────────────┘              └─────────────────┘
```

**Key Points**:
- Audio never leaves the Mac
- Transcript text only sent to LLM if user opts in
- OpenAI key stored in macOS Keychain (encrypted)
- Ollama runs entirely locally

### Compliance

| Provider | SOC2 | GDPR | HIPAA | Notes |
|----------|------|------|-------|-------|
| OpenAI | ✅ | ✅ | ✅ | Business Associate Agreement required for HIPAA |
| Ollama | N/A | ✅ | ✅ | Fully local, no data transmission |

---

## Research Findings

### Why Ollama vs llama.cpp vs MLX?

We evaluated three local LLM approaches using HuggingFace Hub API (with Pro access) and recent benchmarks:

| Approach | Speed | Setup | Notes |
|----------|-------|-------|-------|
| **Ollama** | Good | Easy | Wrapper around llama.cpp; 10-30% overhead but excellent UX |
| **llama.cpp** | Better | Harder | Raw C++ implementation; faster but requires manual model management |
| **MLX (native)** | Best | Medium | Apple's framework; 2-5x faster on Apple Silicon but requires Python bindings |

**Decision**: Use Ollama for v0.3 because:
1. **User experience**: `ollama pull <model>` is simpler than manual GGUF downloads
2. **Ecosystem**: Ollama has Modelfile system, REST API, active community
3. **Speed difference acceptable**: 10-30% overhead acceptable for EchoPanel's use case (not high-concurrency)
4. **Future path**: Can add MLX native provider later without breaking changes

**Research Method**:
- Searched HuggingFace Hub via `huggingface_hub` API
- Checked mlx-community, google, meta, qwen, microsoft orgs
- Verified model availability and quantization options
- Cross-referenced with Ollama's model library

**Source**: 
- [llama.cpp vs Ollama 2026 Benchmarks](https://www.decodesfuture.com/articles/llama-cpp-vs-ollama-vs-vllm-local-llm-stack-guide)
- [A Comparative Study of MLX, MLC-LLM, Ollama, llama.cpp (arXiv 2511.05502)](https://arxiv.org/pdf/2511.05502)
- HuggingFace Hub API (mlx-community/gemma-3-*, mlx-community/llama-3.2*, etc.)

### Small Model Quality (2025-2026 Research)

Recent research shows small models (1-4B) can match larger models on structured extraction tasks:

- **Gemma 3 (1B/4B)**: Google's March 2025 release. 4B beats Gemma 2 27B on benchmarks. 128k context on 4B+ models.
- **Llama 3.2 (1B/3B)**: Meta's edge-optimized models. 128k context standard. 3B is sweet spot for quality/speed.
- **Qwen2.5 (1.5B-7B)**: Alibaba's strong multilingual models. Excellent for non-English meetings.
- **Phi-4 Mini (3.8B)**: Microsoft's reasoning-focused model.

**Key insight for meeting analysis**: These models are "good enough" for extracting actions/decisions/risks from transcripts, especially when combined with our hybrid approach (LLM + keyword fallback).

**Source**: 
- [Tiny Titans: Can Smaller LLMs Punch Above Their Weight? (OpenReview 2025)](https://openreview.net/pdf?id=7NtfIYIqvk)
- [ACL 2025 Findings](https://aclanthology.org/volumes/2025.findings-acl/)

---

## Future Work

### P1: MLX Native Provider
Implement direct MLX Python bindings to bypass Ollama overhead (~13-30% speed improvement on Apple Silicon). See research above.

### P2: Streaming LLM Analysis
Instead of batch every 30s, investigate token-by-token analysis for real-time card extraction.

### P3: Custom Prompts
Allow users to customize extraction prompts for domain-specific meetings (medical, legal, engineering).

### P4: Multi-Provider Ensemble
Run multiple small models locally and ensemble their outputs for better accuracy than any single model.

### P5: GGUF Direct Support
Add option to use llama.cpp directly (bypass Ollama) for power users who want maximum performance.

---

## References

- [DECISIONS.md](DECISIONS.md) - Original LLM strategy decision
- [NEXT_MODEL_RUNTIME_TODOS_2026-02-14.md](NEXT_MODEL_RUNTIME_TODOS_2026-02-14.md) - Implementation roadmap
- [Ollama Documentation](https://github.com/ollama/ollama)
- [MLX Research](MLX_AUDIO_COMPREHENSIVE_RESEARCH.md) - Apple Silicon optimization research

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-06 | Hybrid approach (keyword default + LLM opt-in) | Preserves offline capability while enabling quality upgrades |
| 2026-02-15 | Implemented Ollama + OpenAI | User demand for local LLM option; lightweight 3B models now viable |
| 2026-02-15 | Ollama over llama.cpp directly | Easier setup for users; acceptable overhead for EchoPanel's use case |
| 2026-02-15 | Defer MLX native | Ollama sufficient for v0.3; MLX provider as P1 enhancement |

---

*Last updated: 2026-02-15*
