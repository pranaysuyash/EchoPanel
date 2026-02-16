# EchoPanel Implementation Roadmap

**Generated:** 2026-02-14  
**Status:** ACTIVE  
**Source:** `docs/audit/pipeline-intelligence-layer-20260214.md`  
**Ticket:** TCK-20260214-079 (Audit)  

---

## Executive Summary

This roadmap prioritizes audit findings into immediate quick wins, short-term hardening, and strategic capabilities. All items trace back to the Non-Transcription Pipeline Audit findings.

**Philosophy:**
- Fix critical/thread-safety issues first (launch blockers)
- Ship quick wins immediately (user value, low risk)
- Defer major architectural changes post-launch unless they're differentiators

---

## Phase 1: Immediate Actions (This Week)

### 1.1 Audit Quick Wins

| ID | Task | File | Effort | Risk | Evidence |
|----|------|------|--------|------|----------|
| QW-001 | Activity-gated analysis | `ws_live_listener.py:938` | 2h | Low | NER-009: Fixed timers waste CPU |
| QW-002 | Embedding cache LRU eviction | `embeddings.py:82-101` | 3h | Low | EMB-002: Unbounded growth |
| QW-003 | Preload embedding model at startup | `main.py` | 2h | Low | EMB-001: Cold start latency |

**Implementation Details:**

#### QW-001: Activity-Gated Analysis
```python
# Current: Fixed timers
await asyncio.sleep(12)  # Always runs

# Target: Activity-gated
if state.transcript and has_new_segments(state.transcript, state.last_entity_analysis_t1):
    # Run extraction
else:
    await asyncio.sleep(1)  # Short poll when idle
```

**Acceptance Criteria:**
- [ ] Analysis skips when no new transcript segments
- [ ] CPU usage reduced during silence
- [ ] Still processes within 2s of new content

#### QW-002: Embedding Cache LRU
```python
# Current: Unbounded dict
self._cache: Dict[str, List[float]] = {}

# Target: LRU with max size
from functools import lru_cache
# Or: OrderedDict with max_size=10000
```

**Acceptance Criteria:**
- [ ] Max cache size configurable (default 10,000 embeddings)
- [ ] LRU eviction when limit exceeded
- [ ] Metrics log cache hit/miss ratio

#### QW-003: Preload Embeddings Model
```python
# In main.py lifespan()
@app.on_event("startup")
async def preload_models():
    # Current: Only ASR preloaded
    # Add:
    from server.services.embeddings import get_embedding_service
    service = get_embedding_service()
    if service.is_available():
        logger.info("Embedding model warmed up")
```

**Acceptance Criteria:**
- [ ] Embedding model loaded during startup
- [ ] First RAG query has no cold-start latency
- [ ] Startup time increase <5 seconds

---

### 1.2 Thread Safety Fixes (Launch Blockers)

| ID | Task | File | Evidence |
|----|------|------|----------|
| TS-001 | NSLock for AudioCaptureManager EMAs | `AudioCaptureManager.swift:192-194` | AUD-002: Thread safety gap |
| TS-002 | NSLock for MicrophoneCaptureManager level | `MicrophoneCaptureManager.swift:79` | AUD-001: Thread safety gap |

**Context:** These are from `TCK-20260214-077` and block launch due to potential race conditions in audio metrics.

---

## Phase 2: Short-Term Hardening (Next 2 Weeks)

### 2.1 Analysis Pipeline Improvements

| ID | Task | Source Finding | Effort |
|----|------|----------------|--------|
| ST-001 | Add negation detection for cards | NER-004 | 4h |
| ST-002 | Extend title patterns (Prof., Rev., etc.) | NER-002 | 1h |
| ST-003 | Add analysis queue with backpressure | Queue Analysis | 1d |

### 2.2 Observability Enhancements

| ID | Task | Source | Effort |
|----|------|--------|--------|
| OBS-001 | Add 9 metrics from audit instrumentation plan | Instrumentation Plan | 1d |
| OBS-002 | Structured logging for RAG queries | RAG-001 | 4h |

---

## Phase 3: Strategic Capabilities (Post-Launch or Pre-Launch if Time)

### 3.1 Option A: Real-Time Intelligence (High User Value)

**Goal:** Replace batch analysis with streaming insights

| Component | Current | Target | Effort |
|-----------|---------|--------|--------|
| Entity Extraction | 12s timer | On new segment | 2d |
| Card Extraction | 28s timer | On action keywords | 2d |
| Diarization | Session-end | Streaming chunks | 3d |

**Trade-offs:**
- **Pros:** Immediate feedback, lower latency, adaptive CPU usage
- **Cons:** More complex state management, potential for over-triggering

### 3.2 Option B: OCR Pipeline (Major Differentiator)

**Goal:** Extract text from screen captures (slides, documents)

```
Architecture:
┌─────────────────┐    ┌─────────────┐    ┌─────────────┐
│ ScreenCaptureKit│───▶│ Frame Buffer│───▶│  OCR Engine │
│   (existing)    │    │ (throttled) │    │ Apple Vision│
└─────────────────┘    └─────────────┘    └──────┬──────┘
                                                  │
                       ┌─────────────┐◀───────────┘
                       │  RAG Index  │
                       │  (auto-add) │
                       └─────────────┘
```

**Components:**
- Frame extraction (30s intervals during capture)
- OCR processing (Apple Vision or pytesseract)
- Deduplication (don't index duplicate slides)
- Auto-RAG indexing

**Effort:** 4 days
**Impact:** Very High (no competitor has this)

### 3.3 Option C: ML-Based NER (Quality)

**Goal:** Replace keyword matching with transformer NER

```python
# Current
if "i will" in text.lower():  # catches "i will not"

# Target
from transformers import pipeline
ner = pipeline("ner", model="dslim/bert-base-NER")
entities = ner(text)  # Context-aware
```

**Options:**
1. **spaCy** (en_core_web_sm) - 40MB, fast, good accuracy
2. **BERT-NER** - 400MB, slower, better accuracy
3. **Fine-tuned on meeting data** - Best, requires training data

**Effort:** 2 days (spaCy), 1 week (fine-tuned)

---

## Decision Framework

### If Launching in <2 Weeks

```
Must Do:
├── Phase 1.1: Quick Wins (QW-001, QW-002, QW-003)
├── Phase 1.2: Thread Safety (TS-001, TS-002)
└── UI Polish: Focus indicator (TCK-20260213-008)

Defer:
├── Phase 2 (short-term hardening)
└── Phase 3 (strategic capabilities)
```

### If Launching in 3-4 Weeks

```
Must Do:
├── Phase 1: Immediate actions
├── Phase 2: Short-term hardening
└── Pick ONE from Phase 3:
    ├── OCR Pipeline (if differentiator matters)
    ├── Real-time Intelligence (if UX polish matters)
    └── ML NER (if accuracy matters)
```

### If Iterating Before Launch

```
Do everything +:
├── OCR Pipeline (major differentiator)
├── Real-time streaming diarization
└── ML-based card extraction
```

---

## Implementation Order

### Week 1 (This Week)

| Day | Task | Owner | Output |
|-----|------|-------|--------|
| Mon | QW-001: Activity-gated analysis | Agent | PR + tests |
| Mon | QW-002: Embedding cache LRU | Agent | PR + tests |
| Tue | QW-003: Preload embedding model | Agent | PR + tests |
| Tue | TS-001/002: Thread safety fixes | Agent | PR + Swift tests |
| Wed | Code review all PRs | Pranay | Merged |
| Thu | OBS-001: Metrics implementation | Agent | PR |
| Fri | Integration testing | Pranay | Release candidate |

### Week 2-3 (If Time)

| Week | Focus | Deliverable |
|------|-------|-------------|
| 2 | Phase 2 hardening | Improved observability + negation detection |
| 3 | Phase 3 (one option) | OCR OR Real-time OR ML NER |

---

## Success Metrics

| Phase | Metric | Target | Measurement |
|-------|--------|--------|-------------|
| 1 | CPU usage during silence | <5% | Activity Monitor |
| 1 | Embedding cache hit ratio | >80% | Metrics endpoint |
| 1 | First RAG query latency | <100ms | Stopwatch |
| 2 | Analysis pipeline errors | Zero | Logs |
| 3 (OCR) | Slide text extraction | >90% accuracy | Manual test |
| 3 (Real-time) | Insight latency | <2s from speech | Stopwatch |
| 3 (ML NER) | Entity precision | >85% | Manual evaluation |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Phase 3 takes too long | Time-box to 1 week, cut scope if needed |
| OCR impacts performance | Frame throttling (max 1 per 30s) |
| ML NER increases memory | Use small model (spaCy), quantize |
| Real-time triggers too much | Debounce (min 5s between analysis) |

---

## Ticket Mapping

| This Doc | Worklog Ticket | Status |
|----------|---------------|--------|
| Phase 1.1 | TCK-20260214-080 (Quick Wins) | OPEN |
| Phase 1.2 | TCK-20260214-077 (Thread Safety) | IN_PROGRESS |
| Phase 2 | TCK-20260214-081 (Hardening) | OPEN |
| Phase 3A | TCK-20260214-082 (Real-time) | OPEN |
| Phase 3B | TCK-20260214-083 (OCR Pipeline) | OPEN |
| Phase 3C | TCK-20260214-084 (ML NER) | OPEN |

---

*Roadmap version: 2026-02-14-v1.0*  
*Review cycle: Weekly*  
*Next review: 2026-02-21*
