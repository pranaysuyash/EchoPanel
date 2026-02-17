# Video Understanding VLM Integration

**Created:** 2026-02-17  
**Status:** IN_PROGRESS 🟡

---

## Executive Summary

Add video understanding capability using VLM to analyze screen recordings, extract visual context, and generate narrative descriptions that complement ASR transcripts.

---

## Research Findings

### Current State
- **Upgraded**: `server/services/ocr_smolvlm.py` now uses SmolVLM2-500M for slide OCR and video understanding
- **Hybrid Pipeline**: `server/services/ocr_hybrid.py` combines PaddleOCR + SmolVLM
- **New**: `server/services/video_understanding.py` provides session-level visual context tracking

### Model Options (2026)

| Model | Params | Video-MME | GPU Memory | Notes |
|-------|--------|-----------|------------|-------|
| SmolVLM-256M | 256M | 33.7% | ~1GB | Legacy |
| **SmolVLM2-500M** | 500M | 42.2% | ~2GB | ✅ Current default |
| SmolVLM2-2.2B | 2.2B | 52.1% | ~5GB | Upgrade path |
| Qwen2.5-VL-3B | 3B | 60.9% | ~8GB | Future consideration |

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

### Phase 1: Infrastructure (P1) ✅ DONE
- [x] Upgrade SmolVLM-256M → SmolVLM2-500M in `ocr_smolvlm.py`
- [x] Add video frame sampling utility (`VideoFrameSampler`)
- [x] Create `VideoUnderstandingPipeline` class
- [x] Add environment configuration for VLM model selection

### Phase 2: Integration (P2) ✅ DONE
- [x] Add keyframe extraction from video/audio sessions (`video_understanding.py`)
- [x] Integrate with existing OCR pipeline (session context tracking)
- [x] Async processing (non-blocking)
- [ ] Add backpressure handling for VLM calls

### Phase 3: Features (P3) ✅ DONE
- [x] Video narration endpoint (`POST /brain-dump/video/analyze`)
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
# Video understanding
ECHOPANEL_VLM_VIDEO_ENABLED=true
ECHOPANEL_VLM_VIDEO_ASYNC=true

# VLM settings
ECHOPANEL_VLM_MODEL=HuggingFaceTB/SmolVLM2-500M-Instruct
ECHOPANEL_VLM_FRAME_INTERVAL=10  # Process every N seconds of video
ECHOPANEL_VLM_MAX_FRAMES=20      # Max frames per segment
ECHOPANEL_VLM_FRAME_SAMPLING=uniform  # uniform, center, keyframe
ECHOPANEL_VLM_DEVICE=auto         # auto, cuda, cpu
```

---

## API Endpoints

### Analyze Session Video
```
POST /brain-dump/video/analyze
{
    "session_id": "uuid-here",
    "analyze": true
}

Response:
{
    "session_id": "uuid",
    "overall_summary": "Quarterly review meeting...",
    "key_scenes": ["Q4 metrics", "Product roadmap"],
    "narrative": "Visual Summary: ...",
    "analyzed_frames": 10,
    "created_at": "2026-02-17T12:00:00"
}
```

### Get Video Stats
```
GET /brain-dump/video/stats
```

---

## Testing

- Unit tests: `tests/test_video_understanding.py`
- Tests cover: Frame sampling, analysis results, pipeline stats

---

## References

- SmolVLM2 Blog: https://huggingface.co/blog/smolvlm2
- Video-MME Benchmark: https://video-mme.github.io/home
- Frame Sampling Paper: https://arxiv.org/html/2509.14769v1
