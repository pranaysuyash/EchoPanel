# EchoPanel Non-Transcription Pipeline Audit

**Generated:** 2026-02-14  
**Status:** IN_PROGRESS  
**Type:** AUDIT  
**Ticket:** TCK-20260214-079  
**Priority:** P1  
**Scope:** NER, RAG, Embeddings, Diarization, Card Extraction, Analysis Stream  

---

## Files Inspected

| File | Lines | Purpose |
|------|-------|---------|
| `server/services/analysis_stream.py` | 783 | NER, card extraction, rolling summary |
| `server/services/rag_store.py` | 416 | Document storage, lexical/semantic search |
| `server/services/embeddings.py` | 327 | Embedding generation, semantic similarity |
| `server/services/diarization.py` | 243 | Speaker identification, segmentation |
| `server/api/ws_live_listener.py` | 1502 | WebSocket handler, analysis orchestration |
| `server/api/documents.py` | 107 | REST API for RAG operations |

---

## Executive Summary

1. **Entity Extraction** uses rule-based NLP with regex patterns and known lists; no ML model (fast but limited accuracy) (`analysis_stream.py:280-493`)
2. **Card Extraction** (actions/decisions/risks) relies on keyword matching with fuzzy deduplication; no semantic understanding (`analysis_stream.py:101-163`)
3. **RAG Store** implements BM25-style lexical search with optional semantic search via embeddings; no vector database (`rag_store.py:34-416`)
4. **Embeddings Service** uses sentence-transformers with local JSON cache; no vector indexing or approximate nearest neighbor (`embeddings.py:25-327`)
5. **Speaker Diarization** runs at session-end only (not real-time) using pyannote.audio; requires HuggingFace token (`diarization.py:36-243`)
6. **Analysis Loop** runs on fixed timers (12s entities, 28s cards) regardless of transcript activity; no adaptive scheduling (`ws_live_listener.py:935-975`)
7. **Incremental Processing** tracks `last_t1` timestamps but re-processes entire window for deduplication; memory grows unbounded (`analysis_stream.py:165-204`)
8. **No OCR Pipeline** exists for screen capture content; missed opportunity for slide/document extraction
9. **Hybrid Search** combines lexical (BM25) and semantic but lacks re-ranking or cross-encoder scoring (`rag_store.py:170-204`)
10. **Diarization Memory** accumulates PCM buffers per source with configurable max but no early eviction strategy (`ws_live_listener.py:216-228`)

---

## Component Architecture

### Pipeline Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WEBSOCKET SESSION                                    │
│                    (ws_live_listener.py:1148-1502)                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────────┐  │
│  │ Audio Ingest│───▶│    ASR      │───▶│  Transcript Buffer (state.)     │  │
│  └─────────────┘    └─────────────┘    └─────────────────────────────────┘  │
│                                                    │                         │
└────────────────────────────────────────────────────┼─────────────────────────┘
                                                     │
                              ┌──────────────────────┼──────────────────────┐
                              │                      │                      │
                              ▼                      ▼                      ▼
                    ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐
                    │  Analysis Loop  │  │  Analysis Loop   │  │  Session End    │
                    │  (12s interval) │  │  (28s interval)  │  │  (on "stop")    │
                    │                 │  │                  │  │                 │
                    │ Entity Extraction│ │ Card Extraction  │  │  Diarization    │
                    │ (extract_entities_│▶│ (extract_cards_  │  │  (per source)   │
                    │  incremental)   │  │  incremental)    │  │                 │
                    └─────────────────┘  └──────────────────┘  │  Final Summary  │
                              │                      │         │  Final Cards    │
                              ▼                      ▼         │  Final Entities │
                    ┌─────────────────┐  ┌──────────────────┐  └─────────────────┘
                    │ entities_update │  │  cards_update    │           │
                    │   WebSocket     │  │   WebSocket      │           ▼
                    └─────────────────┘  └──────────────────┘  ┌─────────────────┐
                                                                 │ final_summary  │
                                                                 │   WebSocket    │
                                                                 └─────────────────┘
```

### NER/Card Extraction State Machine

```
                    ┌──────────────┐
         ┌─────────▶│   START      │◀────────────────┐
         │          │ (session     │                 │
         │          │  started)    │                 │
         │          └──────────────┘                 │
         │                  │                        │
         │                  ▼                        │
         │          ┌──────────────┐                 │
         │          │  WAITING     │                 │
         │          │ (transcript  │                 │
         │          │  buffer)     │                 │
         │          └──────────────┘                 │
         │                  │                        │
    12s  │                  │ new segment            │
   timer │                  ▼                        │
  fired  │          ┌──────────────┐                 │
         │    ┌────│ EXTRACTING   │────┐            │
         │    │    │ ENTITIES     │    │ 28s timer  │
         │    │    │ (10s timeout)│    │ fired      │
         │    │    └──────────────┘    │            │
         │    │            │           ▼            │
         │    │            │    ┌──────────────┐    │
         │    │            │    │  EXTRACTING  │    │
         │    │            │    │    CARDS     │    │
         │    │            │    │ (15s timeout)│    │
         │    │            │    └──────────────┘    │
         │    │            │           │            │
         │    │            ▼           │            │
         │    │    ┌──────────────┐    │            │
         │    └───▶│   SEND       │◀───┘            │
         │         │  RESULTS     │                 │
         │         └──────────────┘                 │
         │                  │                        │
         │                  │ session end            │
         │                  ▼                        │
         │         ┌──────────────┐                 │
         └────────│     END      │─────────────────┘
                   │ (cleanup)    │
                   └──────────────┘
```

---

## Failure Modes Table (20+ Entries)

| ID | Component | Failure Mode | Severity | Detection | Evidence |
|----|-----------|--------------|----------|-----------|----------|
| NER-001 | Entity Extraction | Regex fails on multilingual text | Medium | Silent omission | `analysis_stream.py:426` - only matches `[A-Z][a-zA-Z0-9\.]+` |
| NER-002 | Entity Extraction | Title pattern misses "Prof.", "Rev." | Low | Silent omission | `analysis_stream.py:358` - only Mr./Mrs./Ms./Dr. |
| NER-003 | Entity Extraction | Common names list is static (60 names) | Medium | False negatives | `analysis_stream.py:345-350` - limited coverage |
| NER-004 | Card Extraction | Keyword matching misses implicit actions | High | Silent omission | `analysis_stream.py:113-118` - no semantic parsing |
| NER-005 | Card Extraction | Fuzzy dedupe false positives (70% threshold) | Medium | Data loss | `analysis_stream.py:66-74` - Jaccard similarity |
| NER-006 | Card Extraction | No owner/due date extraction from context | Medium | Missing metadata | `analysis_stream.py:127-133` - only keyword match |
| NER-007 | Analysis Loop | 10s timeout on entity extraction | Medium | Log warning | `ws_live_listener.py:943-946` - asyncio.wait_for |
| NER-008 | Analysis Loop | 15s timeout on card extraction | Medium | Log warning | `ws_live_listener.py:958-961` - asyncio.wait_for |
| NER-009 | Analysis Loop | Fixed 12s/28s timers waste CPU on silence | Low | No detection | `ws_live_listener.py:938,953` - sleep-based, no activity check |
| RAG-001 | RAG Store | JSON file corruption on crash | High | Startup failure | `rag_store.py:212-225` - temp file pattern but no checksum |
| RAG-002 | RAG Store | BM25 docFreq calculation O(n*m) per query | Medium | Slow queries | `rag_store.py:303-305` - nested loop over all chunks |
| RAG-003 | RAG Store | No pagination on large result sets | Low | Memory pressure | `rag_store.py:123-132` - returns all results |
| RAG-004 | RAG Store | Hybrid search double-queries (2× overhead) | Medium | Performance | `rag_store.py:171-172` - calls both query methods |
| RAG-005 | RAG Store | Document update is delete+create (no versioning) | Low | History loss | `rag_store.py:54-95` - no update-in-place |
| EMB-001 | Embeddings | Model load failure on first request | High | Request failure | `embeddings.py:64-80` - lazy loading, no preload |
| EMB-002 | Embeddings | Cache unbounded growth | Medium | Disk space | `embeddings.py:82-101` - no eviction policy |
| EMB-003 | Embeddings | No batch size limit for embed_texts | Medium | OOM risk | `embeddings.py:132-154` - processes all texts at once |
| EMB-004 | Embeddings | CPU fallback silent (no GPU warning) | Low | Performance | `embeddings.py:55-62` - falls back without log |
| DIA-001 | Diarization | HF token missing = silent skip | Medium | Missing speakers | `diarization.py:44-49` - returns false, no error |
| DIA-002 | Diarization | pyannote.audio OOM on long sessions | High | Crash | `diarization.py:164-209` - no chunking strategy |
| DIA-003 | Diarization | Session-end only (no real-time) | Medium | Delayed feedback | `ws_live_listener.py:1351-1352` - only on stop message |
| DIA-004 | Diarization | MPS/CUDA device selection may fail | Medium | CPU fallback | `diarization.py:98-105` - exception catch all |
| DIA-005 | Diarization | Speaker merge threshold hardcoded (0.5s) | Low | Over-merging | `diarization.py:113-143` - gap_threshold fixed |
| API-001 | Documents API | No rate limiting on index endpoint | Medium | DoS risk | `documents.py:76-89` - no throttle decorator |
| API-002 | Documents API | Query auth bypass if token env unset | High | Security | `documents.py:59-65` - returns early if no env var |
| ORC-001 | Missing | No OCR for screen capture | High | Feature gap | N/A - component does not exist |
| ORC-002 | Missing | No image analysis for slides | High | Feature gap | N/A - component does not exist |

---

## Root Causes (Ranked by Impact)

### Critical (P0)

**RC-001: Rule-Based NLP Limitations**
- **Impact:** Poor extraction quality on nuanced language
- **Location:** `analysis_stream.py:101-493`
- **Evidence:** Keywords like "we will" match "we will not" as action; no negation detection
- **Root Cause:** Keyword matching lacks semantic understanding

**RC-002: Session-End Diarization Only**
- **Impact:** No real-time speaker labels during meeting
- **Location:** `ws_live_listener.py:1351-1363`
- **Evidence:** `_run_diarization_per_source()` only called on stop message
- **Root Cause:** Diarization is batch-only, not streaming

### High (P1)

**RC-003: Analysis Timer Inefficiency**
- **Impact:** Wasted CPU cycles, delayed insights
- **Location:** `ws_live_listener.py:935-975`
- **Evidence:** Fixed `asyncio.sleep(12)` regardless of transcript activity
- **Root Cause:** No event-driven or adaptive scheduling

**RC-004: Embedding Cache Unbounded Growth**
- **Impact:** Disk space exhaustion over time
- **Location:** `embeddings.py:82-101`
- **Evidence:** `self._cache` dict grows forever, no LRU/max size
- **Root Cause:** Missing cache eviction policy

**RC-005: No OCR Pipeline**
- **Impact:** Missed slide content, document references
- **Location:** N/A - missing component
- **Evidence:** No references to image processing, vision models, or screen content OCR
- **Root Cause:** Architecture focused on audio-only

### Medium (P2)

**RC-006: Fuzzy Matching False Positives**
- **Impact:** Duplicate cards incorrectly deduplicated
- **Location:** `analysis_stream.py:66-74`
- **Evidence:** 70% Jaccard threshold catches "schedule meeting" and "schedule review"
- **Root Cause:** Bag-of-words similarity lacks semantic discrimination

**RC-007: BM25 Performance on Large Corpora**
- **Impact:** Query latency degrades with document count
- **Location:** `rag_store.py:281-348`
- **Evidence:** O(n*m) nested loops for doc frequency calculation
- **Root Cause:** No inverted index, brute-force scoring

**RC-008: Embedding Model Cold Start**
- **Impact:** First request latency spike
- **Location:** `embeddings.py:64-80`
- **Evidence:** `_load_model()` on first `embed_text()` call
- **Root Cause:** Lazy loading without warmup

---

## Concrete Fixes (Ranked by Impact/Effort/Risk)

### Quick Wins (Low Effort, High Impact)

| ID | Fix | Effort | Risk | Files |
|----|-----|--------|------|-------|
| F-001 | Add activity-gated analysis (skip if no new transcript) | 2h | Low | `ws_live_listener.py` |
| F-002 | Add embedding cache size limit (LRU eviction) | 3h | Low | `embeddings.py` |
| F-003 | Extend title patterns (Prof., Rev., etc.) | 1h | Low | `analysis_stream.py` |
| F-004 | Add negation detection for card extraction | 4h | Medium | `analysis_stream.py` |
| F-005 | Preload embedding model at startup | 2h | Low | `main.py` |

### Medium Effort (Strategic Improvements)

| ID | Fix | Effort | Risk | Files |
|----|-----|--------|------|-------|
| F-006 | Implement streaming diarization (chunk-based) | 2d | High | New module + `ws_live_listener.py` |
| F-007 | Add inverted index for BM25 | 1d | Medium | `rag_store.py` |
| F-008 | Integrate lightweight NER model (spaCy) | 1d | Medium | `analysis_stream.py` |
| F-009 | Add cross-encoder re-ranking for RAG | 1d | Low | `rag_store.py` |
| F-010 | Implement OCR for screen capture frames | 2d | Medium | New module |

### Architectural (High Effort, Transformative)

| ID | Fix | Effort | Risk | Files |
|----|-----|--------|------|-------|
| F-011 | Replace keyword cards with LLM-based extraction | 3d | High | `analysis_stream.py` |
| F-012 | Add vector database (Chroma/FAISS) for embeddings | 2d | Medium | `rag_store.py`, `embeddings.py` |
| F-013 | Real-time vision analysis for slide detection | 3d | High | New pipeline |
| F-014 | Event-driven analysis (asyncio events vs timers) | 2d | Medium | `ws_live_listener.py` |

---

## Test Plan

### Unit Tests

```python
# tests/test_analysis_stream.py
def test_extract_entities_handles_negation():
    """Ensure "we will not" doesn't create action card."""
    transcript = [{"t0": 0, "t1": 2, "text": "We will not schedule the meeting"}]
    cards = extract_cards(transcript)
    assert len(cards["actions"]) == 0

def test_entity_deduplication_preserves_distinct():
    """Ensure 'schedule meeting' and 'schedule review' are distinct."""
    # Implementation test for fuzzy threshold

def test_incremental_analysis_progresses_t1():
    """Ensure last_t1 advances correctly in incremental mode."""
```

### Integration Tests

```python
# tests/test_rag_integration.py
def test_rag_hybrid_search_ranks_correctly():
    """Hybrid search should combine lexical and semantic signals."""

def test_document_persistence_survives_restart():
    """JSON store should reload correctly after crash."""
```

### Manual Tests

| Test | Steps | Expected |
|------|-------|----------|
| Entity timeout handling | Add 10s delay in extract_entities | Warning log, continued operation |
| Embedding cache eviction | Index 1000 documents, check cache size | Oldest evicted, size bounded |
| Diarization memory limit | 2-hour session, monitor PCM buffer | Buffer capped at 30 min |
| RAG query performance | 100 documents, measure query time | <100ms per query |

---

## Instrumentation Plan

### Metrics to Add

| Metric | Type | Labels | Location |
|--------|------|--------|----------|
| `ner_entities_extracted` | Counter | `entity_type` | `analysis_stream.py:490` |
| `ner_extraction_duration_ms` | Histogram | - | `ws_live_listener.py:943` |
| `rag_query_duration_ms` | Histogram | `search_type` | `rag_store.py:123,134,170` |
| `rag_documents_indexed` | Gauge | - | `rag_store.py:86` |
| `embedding_cache_hit_ratio` | Gauge | - | `embeddings.py:209` |
| `embedding_generation_duration_ms` | Histogram | - | `embeddings.py:127` |
| `diarization_duration_ms` | Histogram | `source` | `ws_live_listener.py:1352` |
| `diarization_speakers_found` | Counter | - | `diarization.py:203` |
| `analysis_loop_lag_ms` | Gauge | - | `ws_live_listener.py:938` |

### Logs to Add

```python
# analysis_stream.py - extract_entities_incremental
logger.debug(f"Entity extraction: {len(new_segments)} new segments, "
             f"{len(entity_map)} entities tracked")

# rag_store.py - query
logger.info(f"RAG query: '{query}' returned {len(results)} results "
            f"in {(time.time()-start)*1000:.1f}ms")

# embeddings.py - embed_text
logger.warning(f"Embedding cache miss for key {cache_key}, "
               f"generating new embedding")
```

---

## Queue/Backpressure Analysis

### Current State

| Component | Queue Type | Max Size | Strategy | Backpressure |
|-----------|-----------|----------|----------|--------------|
| ASR Audio | `asyncio.Queue` | 500 frames / 2s bytes | Drop oldest | Yes (client notified) |
| Analysis | None (timer-based) | N/A | Skip iteration | Partial (timeout) |
| Diarization | In-memory PCM buffer | 30 min audio | Drop oldest | No (accumulates) |
| RAG Query | None (synchronous) | N/A | Block | No |
| Embeddings | None (synchronous) | N/A | Block | No |

### Analysis Bottlenecks

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOTTLENECK ANALYSIS                          │
├─────────────────────────────────────────────────────────────────┤
│  1. ANALYSIS LOOP                                               │
│     - Runs in asyncio.to_thread (thread pool)                   │
│     - Fixed intervals regardless of work completion             │
│     - No queue between transcript and analysis                  │
│     - Risk: Piles up if extraction is slow                      │
│                                                                 │
│  2. DIARIZATION                                                 │
│     - Runs at session end on full PCM buffer                    │
│     - Synchronous, blocking WebSocket close                     │
│     - Risk: 10s+ delay on long sessions                         │
│                                                                 │
│  3. EMBEDDING GENERATION                                        │
│     - Synchronous in index_document                             │
│     - No batching for multiple chunks                           │
│     - Risk: Blocks API response                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Improvements

1. **Add analysis queue** with backpressure (skip if queue full)
2. **Stream diarization** in chunks during session (not just at end)
3. **Background embedding generation** (don't block index API)
4. **Add circuit breaker** for embedding service failures

---

## Evidence Citations

### Critical Paths

**Entity Extraction (Full Window)**
- Entry: `analysis_stream.py:280-288`
- Processing: `analysis_stream.py:290-493`
- Exit: Returns dict with people, orgs, dates, projects, topics

**Incremental Entity Extraction**
- Entry: `analysis_stream.py:495-524`
- New segment detection: `analysis_stream.py:505`
- State management: `analysis_stream.py:512,518`

**Card Extraction**
- Keywords: `analysis_stream.py:113-118`
- Deduplication: `analysis_stream.py:77-98`
- Limits: `analysis_stream.py:154-156` (max 7 per type)

**RAG Query (Lexical)**
- Entry: `rag_store.py:123-132`
- Tokenization: `rag_store.py:389-390`
- BM25 scoring: `rag_store.py:281-348`
- Snippet generation: `rag_store.py:360-382`

**RAG Query (Semantic)**
- Embedding fallback: `rag_store.py:134-136`
- Similarity search: `embeddings.py:262-281`
- Result merging: `rag_store.py:146-168`

**Diarization Pipeline**
- Entry: `ws_live_listener.py:231-260`
- Pipeline load: `diarization.py:80-110`
- Processing: `diarization.py:164-209`
- Merge with transcript: `diarization.py:212-243`

**Analysis Loop**
- Entity cycle: `ws_live_listener.py:942-951`
- Card cycle: `ws_live_listener.py:953-973`
- Timeouts: 10s entities, 15s cards

---

## Appendix: Data Models

### Entity Schema
```python
{
  "name": str,
  "type": "person" | "org" | "date" | "project" | "topic",
  "count": int,
  "last_seen": float,  # timestamp
  "confidence": float,
  "grounding": List[str]  # up to 2 quotes
}
```

### Card Schema
```python
{
  "text": str,
  "confidence": float,
  "evidence": [{"t0": float, "t1": float, "quote": str}],
  "owner": Optional[str],  # actions only
  "due": Optional[str]     # actions only
}
```

### Document Schema
```python
{
  "document_id": str,
  "title": str,
  "source": str,
  "indexed_at": ISO8601,
  "preview": str,  # first 180 chars
  "chunk_count": int,
  "chunks": [{"chunk_index": int, "text": str, "tokens": List[str]}]
}
```

---

## State Machine Diagram: Analysis Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ANALYSIS LIFECYCLE                               │
│                                                                         │
│   SESSION START                                                         │
│       │                                                                 │
│       ▼                                                                 │
│   ┌─────────────┐     new segment     ┌─────────────┐                  │
│   │  ACCUMULATE │────────────────────▶│   BUFFER    │                  │
│   │ TRANSCRIPT  │◀────────────────────│   CHECK     │                  │
│   └─────────────┘    buffer < 10min   └─────────────┘                  │
│       │                                    │                            │
│       │ buffer >= 10min                    │ buffer full                │
│       ▼                                    ▼                            │
│   ┌─────────────┐                    ┌─────────────┐                   │
│   │   SLIDE     │                    │   TRIGGER   │                   │
│   │   WINDOW    │                    │  ANALYSIS   │                   │
│   └─────────────┘                    └─────────────┘                   │
│       │                                    │                            │
│       └────────────────┬───────────────────┘                            │
│                        ▼                                                │
│               ┌─────────────────┐                                       │
│               │  ANALYSIS RUN   │                                       │
│               │  ├─ NER         │                                       │
│               │  ├─ Cards       │                                       │
│               │  └─ Summary     │                                       │
│               └─────────────────┘                                       │
│                        │                                                │
│           ┌────────────┼────────────┐                                   │
│           ▼            ▼            ▼                                   │
│      ┌────────┐  ┌────────┐  ┌─────────┐                               │
│      │ENTITIES│  │ CARDS  │  │ SUMMARY │                               │
│      └────────┘  └────────┘  └─────────┘                               │
│           │            │            │                                   │
│           └────────────┼────────────┘                                   │
│                        ▼                                                │
│               ┌─────────────────┐                                       │
│               │  EMIT UPDATE    │────▶ WebSocket                         │
│               └─────────────────┘                                       │
│                        │                                                │
│       ┌────────────────┴────────────────┐                               │
│       ▼                                 ▼                               │
│   CONTINUE                          SESSION END                         │
│   (loop back)                            │                              │
│                                          ▼                              │
│                              ┌─────────────────┐                        │
│                              │  FINAL ANALYSIS │                        │
│                              │  ├─ Full NER    │                        │
│                              │  ├─ Full Cards  │                        │
│                              │  ├─ Diarization │                        │
│                              │  └─ Export      │                        │
│                              └─────────────────┘                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

*Audit prepared per AGENTS.md audit requirements. All citations include file paths and line ranges for verification.*
