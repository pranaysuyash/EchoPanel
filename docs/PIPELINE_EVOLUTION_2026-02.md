# EchoPanel Pipeline Evolution: Research & Roadmap (Feb 2026)

Goal: move EchoPanel from lexical-only lookup to a local-first “evidence retrieval + grounded synthesis” system that works across multiple upstream artifact scenarios (transcript only, transcript + diarization, transcript + NER, transcript + structured events, plus optional visual memory).

Non-negotiables:
- **Local-first by default**: No data leaves device unless user explicitly opts in.
- **Evidence pointers are first-class**: (meeting_id, speaker_id, t0/t1, segment_ids).
- **Synthesis is “Grounded or Silent”**: If evidence is missing, answer is “Not found in memory”.

---

## 1. NER Evolution

### Current State (v0.2)
- Engine: regex + keyword matching
- Pros: near-zero latency, good for versions and simple patterns
- Cons: brittle, low recall, no contextual labeling, no span confidence

### Proposed (v0.3)
**Hybrid NER**:
1) **Deterministic extractors (regex)** for:
   - versions (vX.Y)
   - dates/times, money, emails/URLs
2) **GLiNER** for semantic labels (configurable label set per run):
   - ORG, PERSON, PRODUCT, TECH_TERM
   - DECISION, ACTION_ITEM, RISK, DEADLINE (as “events” with confidence)

Outputs:
- **entities**: (label, text, confidence, segment_id, char_start, char_end)
- **events**: (type, confidence, segment_id, evidence_span)

---

## 2. RAG and Reasoning

### Current State (v0.2)
- Local lexical search (BM25) in `LocalRAGStore`
- Pros: simple, instant
- Cons: poor semantic recall, weak for paraphrase and intent queries, no grounded synthesis

### Proposed (v0.3)
**Separation of concerns**:
1) **Retrieval Memory** (Fact layer): find evidence chunks with timestamps
2) **Synthesis** (Answer layer): summarize/reason using only retrieved evidence

**Local stack**:
- **Storage**: LanceDB embedded (Hybrid search + RRF)
- **Embeddings**:
  - **Default**: **EmbeddingGemma (300M)** [Gemma License] — SOTA on-device embedding.
  - **Alternative**: **BGE-M3** (hybrid dense + sparse) [Apache-2.0]
  - **Fast mode**: **Nomic embed text v1.5** [Apache-2.0]
- **Reranking** (optional): `bge-reranker-v2-m3` (top 20-50 results)
- **Visual Processing (OCR/VLM)**:
  - **Apple Vision Framework (Native)**:
    - **Pros**: Native macOS API, near-zero footprint, fast real-time OCR. Best for indexing text markers.
  - **LightOnOCR-2-1B (Doc-SOTA)**:
    - **Pros**: 1B params, Apache-2.0, high-precision document and table extraction. 
  - **SmolVLM2 (Visual Summary)**:
    - **Pros**: Apache-2.0, MLX-native, multiple sizes (500M-2.2B). SOTA for semantic captions.

### Recommendation: Two-Stage Visual Path
1. **Always-On**: **Apple Vision** (OCR) + **pHash** (Change Detection) via **ScreenCaptureKit**.
2. **Event-Driven**: **LightOnOCR-2-1B** (Structure) + **SmolVLM2** (Semantic) on keyframes.

- **Synthesis LLM**:
  - **Default**: **Ministral 3 3B Instruct** [Apache-2.0] — Clean commercial redistribution.
  - **Multimodal**: **Gemma 3** (text + image) — Great for vision path.
  - **Power tier**: **Qwen 2.5 7B Instruct** [Apache-2.0]

---

## 3. Visual Context (Optional “Visual Memory”)

Goal: capture screen shares/slides/whiteboards as timestamped “frame documents” so later queries can retrieve what was shown.

Ingestion path:
1) **Periodic frame capture** (configurable interval)
2) **Frame-to-text**: 
   - **Default**: Apple Vision Framework (Native, Fast, Private)
   - **Advanced**: **Gemma 3** or **Qwen3-VL** (Multimodal Summary)
3) **Indexing**: Store in LanceDB with `media_type = "visual"`, timestamp, and OCR/summary content.

---

## 4. Evidence Ladder (Capability Scenarios)

The RAG system applies different routing logic based on the available metadata:

1. **Transcript only**: Hybrid retrieval (dense+sparse) → evidence spans → grounded synthesis.
2. **+ Diarization**: Add `speaker_id` filtering and speaker-aware query routing ("What did Alex say?").
3. **+ NER**: Entity-first narrowing (Entity index hit → Filter chunks → Vector search).
4. **+ Structured Extraction**: Direct lookup path for decisions/action items; fallback to RAG.
5. **+ Visual Memory**: Retrieve transcript chunks + visual frames in the same time band.

---

## 5. Synthesis Protocol (“Grounded or Silent”)

Rules enforced by the system:
1) **Citation Requirement**: Every claim must map to evidence pointers (meeting_id, t0/t1, etc.).
2) **Gating**: If evidence is missing or confidence is low, output: "Not found in memory".
3) **No Weights-Only Logic**: The model cannot improvise facts not in the retrieved context.

---

## 6. Verification & Evaluation

We will build a tiny **offline evaluation harness** before model bake-offs:
- **Corpus**: 30-50 canonical queries over 5-10 real/sanitized meetings.
- **Ground Truth**: Store correct evidence spans (t0/t1) for each query.
- **Metrics**: Recall@K, MRR, and LLM-as-a-judge Faithfulness checks.

---

## 7. Implementation Roadmap (Local PR Units)

| Step | Component | Action |
|---|---|---|
| **PR-1** | **Memory Schema** | Define segments, chunks, entities, events, frames + invariants. |
| **PR-2** | **Ingestion & Eval** | Embedding pipeline + LanceDB + **Offline Eval Harness Skeleton**. |
| **PR-3** | **Retrieval API** | Hybrid search + RRF + metadata filters + initial Recall@K measurement. |
| **PR-4** | **Synthesis API** | Ollama/MLX adapter; "Grounded or Silent" citation enforcement. |
| **PR-5** | **Hybrid NER** | GLiNER/Regex integration; entity index + events table + routing logic. |
| **PR-6** | **Visual Path** | Frame capture → Apple Vision/Gemma-3 → store and retrieve. |

> [!IMPORTANT]
> All chosen models prioritize **Apache-2.0** or native frameworks where possible, with the Gemma ecosystem available as a high-performance alternative for users accepting its license.
