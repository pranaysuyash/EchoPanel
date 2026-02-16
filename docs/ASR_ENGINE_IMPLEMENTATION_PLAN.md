# ASR Engine Implementation Plan: Apple Silicon Optimization

**Date:** 2026-02-14  
**Status:** IN PROGRESS - Parallel Implementation Track  
**Goal:** Maximize Apple Silicon utilization (M1/M2/M3/M4)

---

## Executive Summary

After benchmarking, we discovered:

1. **faster-whisper on CPU**: Actually performs well (RTF ~0.07x on 10s chunks)
2. **mlx-whisper**: Has compatibility issues with current model downloads
3. **ONNX Runtime**: CoreML execution provider available
4. **whisper.cpp**: Not installed but best long-term option

**Key Insight:** The overload issue may not be raw inference speed, but **streaming architecture** (queue sizing, chunk overlap, parallel processing).

---

## Engine Comparison Matrix

| Engine | Metal/GPU | Status | Pros | Cons | Priority |
|--------|-----------|--------|------|------|----------|
| **faster-whisper** | ❌ CPU | ✅ Working | Mature, reliable | CTranslate2 no Metal support | P2 (fallback) |
| **mlx-whisper** | ✅ Metal | ⚠️ Broken | Native Apple, fast | Model download issues | P1 (fix needed) |
| **whisper.cpp** | ✅ Metal | ❌ Missing | Best performance, streaming | Requires binary build | P0 (implement) |
| **ONNX + CoreML** | ✅ Neural Engine | ❌ Missing | Apple's optimized runtime | Model conversion needed | P1 (explore) |
| **PyTorch MPS** | ✅ GPU | ❌ Missing | Native PyTorch | Memory heavy, slower | P3 (low) |

---

## Implementation Tracks (Parallel)

### Track 1: MLX-Whisper Provider (P1 - 1 day)

**Status:** Package installed but broken

**Issue:** Model download compatibility
```
Error: ModelDimensions.__init__() got an unexpected keyword argument '_name_or_path'
```

**Fix Strategy:**
1. Download models manually via HF Hub
2. Load from local path instead of auto-download
3. Test streaming capability

**Code Sketch:**
```python
# server/services/provider_mlx_whisper.py
import mlx_whisper
import mlx.core as mx

class MLXWhisperProvider(ASRProvider):
    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self.model_path = self._get_model_path()
        
    def _get_model_path(self) -> str:
        # Download/cache model locally
        from huggingface_hub import snapshot_download
        return snapshot_download(
            repo_id=f"openai/whisper-{self.config.model_name}",
            cache_dir="~/.cache/whisper-mlx"
        )
    
    async def transcribe_stream(self, pcm_stream, ...):
        # mlx-whisper processes full audio, not streaming
        # Need to buffer and process chunks
        buffer = bytearray()
        async for chunk in pcm_stream:
            buffer.extend(chunk)
            if len(buffer) >= self.chunk_bytes:
                # Convert to numpy, transcribe
                audio = np.frombuffer(buffer[:chunk_bytes], ...)
                result = mlx_whisper.transcribe(
                    audio, 
                    path_or_hf_repo=self.model_path
                )
                # Yield segments
```

**Challenges:**
- mlx-whisper is batch-only (not streaming)
- Need to manage chunk boundaries
- Model format different from faster-whisper

---

### Track 2: whisper.cpp Provider (P0 - 2 days)

**Status:** Not installed, needs implementation

**Why P0:**
- Best performance on Apple Silicon
- True streaming support
- GGML format = smaller models
- Industry standard for edge ASR

**Implementation Steps:**

1. **Install whisper.cpp**
```bash
# Option A: Homebrew
brew install whisper-cpp

# Option B: Build from source
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make -j  # Builds with Metal support on macOS
```

2. **Download GGML Models**
```bash
# Download script
./models/download-ggml-model.sh base.en
./models/download-ggml-model.sh small.en
```

3. **Python Provider**
```python
# server/services/provider_whisper_cpp.py
class WhisperCppProvider(ASRProvider):
    """Provider using whisper.cpp via subprocess or ctypes."""
    
    def __init__(self, config: ASRConfig):
        self.bin_path = os.getenv("WHISPER_CPP_BIN", "whisper-cpp")
        self.model_path = f"~/.cache/whisper/ggml-{config.model_name}.bin"
        self.process = None  # For --stdin streaming mode
        
    async def _ensure_process(self):
        """Start whisper.cpp in streaming mode."""
        if self.process is None:
            self.process = await asyncio.create_subprocess_exec(
                self.bin_path,
                "-m", self.model_path,
                "--stdin",  # Read PCM from stdin
                "-l", "en",
                "--output-txt",  # Text output
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
    
    async def transcribe_stream(self, pcm_stream, ...):
        await self._ensure_process()
        
        async for chunk in pcm_stream:
            # Write PCM to stdin
            self.process.stdin.write(chunk)
            await self.process.stdin.drain()
            
            # Read results from stdout
            # Parse format: [start>end] text
```

**Advantages:**
- True streaming (process stays resident)
- Metal GPU acceleration (`-ng` flag for GPU layers)
- Smaller models (Q5_0 quantized = ~100MB for base)
- C++ performance

**Challenges:**
- Subprocess management complexity
- Parsing stdout reliably
- Chunk boundary handling

---

### Track 3: ONNX CoreML Provider (P1 - 2 days)

**Status:** ONNX Runtime installed, CoreML EP available

**Why:** Uses Apple Neural Engine (ANE) - most power-efficient

**Steps:**
1. Convert Whisper to ONNX
2. Use CoreMLExecutionProvider
3. Implement streaming

**Model Conversion:**
```bash
# Using optimum-cli
optimum-cli export onnx \
  --model openai/whisper-base.en \
  --task automatic-speech-recognition \
  whisper-base-en-onnx/
```

**Provider Code:**
```python
# server/services/provider_onnx_whisper.py
import onnxruntime as ort

class ONNXWhisperProvider(ASRProvider):
    def __init__(self, config: ASRConfig):
        # Use CoreML on macOS
        providers = ['CoreMLExecutionProvider', 'CPUExecutionProvider']
        self.session = ort.InferenceSession(
            "whisper-base-en-onnx/model.onnx",
            providers=providers
        )
        
    async def transcribe_stream(self, pcm_stream, ...):
        # ONNX models are batch-only
        # Need to buffer and process
        ...
```

**Challenges:**
- Model conversion complexity
- ONNX Whisper models are large
- Not truly streaming (encoder-decoder architecture)

---

## Testing Strategy for Parallel Agent

### 1. Functional Tests
```bash
# Test each provider independently
pytest tests/test_provider_faster_whisper.py -v
pytest tests/test_provider_mlx_whisper.py -v
pytest tests/test_provider_whisper_cpp.py -v
pytest tests/test_provider_onnx_whisper.py -v
```

### 2. Performance Benchmarks
```bash
# RTF benchmark
python scripts/benchmark_asr_engines.py --duration 30 --output results.json

# Streaming stress test
python scripts/streaming_stress_test.py --sources 2 --duration 300
```

### 3. Regression Tests
```bash
# Ensure no drops with base.en
python scripts/test_no_drops.py --model base.en --duration 60

# Ensure VAD works
python scripts/test_vad.py --silence-ratio 0.8
```

### 4. Breaking Tests (Find Limits)
```bash
# Find RTF limit
python scripts/find_rtf_limit.py --model small.en

# Memory leak test
python scripts/memory_leak_test.py --duration 600

# Concurrent session test
python scripts/concurrent_test.py --sessions 5
```

---

## Parallel Agent Coordination

### Agent 1: MLX Implementation
**Focus:** Fix mlx-whisper integration
**Tasks:**
- [ ] Fix model download/caching
- [ ] Implement streaming buffer management
- [ ] Test RTF vs faster-whisper
- [ ] Document memory usage

**Deliverable:** Working `provider_mlx_whisper.py`

### Agent 2: whisper.cpp Implementation
**Focus:** Native performance champion
**Tasks:**
- [ ] Install whisper.cpp with Metal
- [ ] Implement subprocess-based provider
- [ ] Test --stdin streaming mode
- [ ] Compare Q5_0 vs Q8_0 quantization

**Deliverable:** Working `provider_whisper_cpp.py`

### Agent 3: ONNX CoreML Implementation
**Focus:** Neural Engine utilization
**Tasks:**
- [ ] Convert Whisper to ONNX
- [ ] Implement CoreML provider
- [ ] Test ANE vs GPU vs CPU
- [ ] Document power efficiency

**Deliverable:** Working `provider_onnx_whisper.py`

### Agent 4: Testing & Integration
**Focus:** Validation and selection logic
**Tasks:**
- [ ] Create benchmark harness
- [ ] Run head-to-head comparisons
- [ ] Update capability_detector.py
- [ ] Document recommendations

**Deliverable:** Test results + auto-selection logic

---

## Decision Matrix (After Testing)

| Scenario | Recommended Engine | Model | Reason |
|----------|-------------------|-------|--------|
| M3 Max, High Quality | whisper.cpp | small.en Q5_0 | Best RTF, Metal GPU |
| M3 Max, Low Latency | whisper.cpp | base.en Q5_0 | Fastest, still good quality |
| M2/M1, Balanced | mlx-whisper | base | Native Apple, good speed |
| Intel Mac | faster-whisper | base.en | CPU-optimized, reliable |
| Low Memory (8GB) | whisper.cpp | tiny.en | Smallest footprint |
| Cloud Fallback | faster-whisper | base.en | Don't add cloud dependency |

---

## Environment Variables

```bash
# Provider selection
export ECHOPANEL_ASR_PROVIDER=whisper_cpp  # or mlx_whisper, faster_whisper, onnx_whisper

# whisper.cpp specific
export WHISPER_CPP_BIN=/opt/homebrew/bin/whisper-cpp
export WHISPER_CPP_MODELS_DIR=~/.cache/whisper

# MLX specific
export WHISPER_MLX_CACHE=~/.cache/whisper-mlx

# ONNX specific
export WHISPER_ONNX_MODEL_PATH=./models/whisper-base-en.onnx

# Benchmark mode (runs all providers, compares)
export ECHOPANEL_ASR_BENCHMARK=1
```

---

## Testing Commands for Parallel Agent

```bash
# Quick validation
source .venv/bin/activate
python scripts/benchmark_asr_engines.py --duration 30

# Full test suite
pytest tests/test_asr_providers.py -v --tb=short

# Stress test
python scripts/soak_test.py --duration 300 --sources 2

# RTF comparison
python scripts/compare_rtf.py --engines faster_whisper,mlx_whisper,whisper_cpp --model base.en
```

---

## Current Status Checklist

- [x] faster-whisper: ✅ Working (CPU)
- [x] mlx-whisper: ⚠️ Installed, needs fix
- [ ] whisper.cpp: ❌ Not installed
- [ ] ONNX CoreML: ❌ Not implemented
- [x] Benchmark harness: ✅ Created

---

## Next Actions

1. **Install whisper.cpp** (any agent)
   ```bash
   brew install whisper-cpp
   # OR build from source
   ```

2. **Fix mlx-whisper model loading** (Agent 1)
   - Download models via HF Hub
   - Test local loading

3. **Implement whisper.cpp provider** (Agent 2)
   - Subprocess management
   - Streaming interface

4. **Run comparative benchmarks** (Agent 4)
   - RTF, memory, quality
   - Document findings

---

*Plan created: 2026-02-14*  
*Parallel implementation: START*  
*Target: Working providers by EOD*
