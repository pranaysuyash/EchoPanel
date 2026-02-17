# Video Understanding VLM Integration

**Created:** 2026-02-17  
**Status:** PLANNED

---

## Executive Summary

Add video understanding capability using VLM to analyze screen recordings, extract visual context, and generate narrative descriptions that complement ASR transcripts.

---

## Research Findings

### Current State
- **Existing**: `server/services/ocr_smolvlm.py` uses SmolVLM-256M for slide OCR
- **Hybrid Pipeline**: `server/services/ocr_hybrid.py` combines PaddleOCR + SmolVLM

### Model Options (2026)

| Model | Params | Video-MME | GPU Memory | Notes |
|-------|--------|-----------|------------|-------|
| SmolVLM-256M | 256M | 33.7% | ~1GB | Current |
| **SmolVLM2-500M** | 500M | 42.2% | ~2GB | Recommended upgrade |
| **SmolVLM2-2.2B** | 2.2B | 52.1% | ~5GB | Best quality |
| Qwen2.5-VL-3B | 3B | 60.9% | ~8GB | SOTA small |

### Key Insights from Research
1. **Frame Sampling**: Uniform-FPS (2 fps) works best for most video content
2. **Video-MME**: Comprehensive benchmark for diverse video types (11s to 1hr)
3. **SmolVLM2**: Native video support, processes frames like images
4. **Parallel Processing**: VLM should run async, not in critical path

---

## Use Cases

1. **Meeting Context Enrichment**
   - Identify slides, diagrams, code shown during meeting
   - Extract presentation structure

2. **Video Narration**
   - Generate textual description of visual content
   - Narrate what's shown when audio is unclear

3. **Visual QA**
   - Answer questions about visual content ("What chart was shown?")

4. **Action Item Detection**
   - Identify UI interactions shown in screen recordings

---

## Implementation Plan

### Phase 1: Infrastructure (P1)
- [ ] Upgrade SmolVLM-256M → SmolVLM2-500M in `ocr_smolvlm.py`
- [ ] Add video frame sampling utility
- [ ] Create `VideoUnderstandingPipeline` class
- [ ] Add environment configuration for VLM model selection

### Phase 2: Integration (P2)
- [ ] Add keyframe extraction from video/audio sessions
- [ ] Integrate with existing OCR pipeline
- [ ] Async processing (non-blocking)
- [ ] Add backpressure handling for VLM calls

### Phase 3: Features (P3)
- [ ] Video narration endpoint
- [ ] Visual context in search results
- [ ] Export video summary

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Audio Capture  │────▶│   ASR Pipeline   │────▶│  Transcript DB  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                                │
         ▼                                                ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Frame Extractor │────▶│  Video VLM Pipe  │────▶│ Visual Context  │
│  (keyframes)    │     │ (SmolVLM2-500M) │     │    (enriched)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

---

## Configuration

```bash
# Environment variables
ECHOPANEL_VLM_ENABLED=true
ECHOPANEL_VLM_MODEL=HuggingFaceTB/SmolVLM2-500M-Instruct
ECHOPANEL_VLM_FRAME_INTERVAL=10  # Process every N seconds of video
ECHOPANEL_VLM_MAX_FRAMES=20      # Max frames per segment
ECHOPANEL_VLM_DEVICE=auto         # auto, cuda, cpu
```

---

## Testing Strategy

1. Unit tests for frame sampling
2. Integration tests with sample videos
3. Performance benchmarks (latency, memory)
4. Quality evaluation on known meeting recordings

---

## References

- SmolVLM2 Blog: https://huggingface.co/blog/smolvlm2
- Video-MME Benchmark: https://video-mme.github.io/home
- Frame Sampling Paper: https://arxiv.org/html/2509.14769v1
