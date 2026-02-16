# RAG Pipeline Architecture

## Implementation Status

| Feature | Status | Version | Notes |
|---------|--------|---------|-------|
| Lexical Search (BM25) | ✅ **Implemented** | v0.2 | Current production implementation |
| Vector Storage (LanceDB) | 🚧 **Planned** | v0.3 | Specification complete, pending implementation |
| Embedding Generation | 🚧 **Planned** | v0.3 | EmbeddingGemma/BGE-M3 planned |
| Semantic Search | 🚧 **Planned** | v0.3 | Hybrid vector+lexical planned |
| Hybrid Reranking | 🚧 **Planned** | v0.3 | bge-reranker-v2-m3 planned |
| Visual Memory RAG | 🚧 **Planned** | v0.4 | Frame transcript retrieval |

> **Current Implementation (v0.2):** The RAG pipeline currently uses **lexical BM25 search only** via SQLite FTS5. Semantic search and embeddings are planned for v0.3.

## Overview
EchoPanel's RAG system focuses on **Evidence Retrieval** as the primary UX. It transitions from simple lexical search to a high-density "Semantic + Lexical" hybrid pipeline using legally safe, local-first models, with the Gemma ecosystem available for high-performance on-device needs.

## The Local "SOTA Edge" Stack

### 1. Vector Storage: LanceDB (Embedded)
- **Why**: Serverless, file-based, and in-process. Native support for hybrid search (Vector + Full-Text) and RRF (Reciprocal Rank Fusion).
- **Optimization**: All data remains in the user's local application support directory.

### 2. Embedding & Retrieval
- **Default (Gemma Stack)**: **EmbeddingGemma (300M)**.
  - **Why**: [Gemma License] Optimized for on-device RAG, sub-200MB RAM, sub-2K context.
- **Alternative (Apache Stack)**: **BGE-M3** via FastEmbed (ONNX).
  - **Why**: [Apache-2.0] Supports dense + sparse (multi-vector) retrieval up to 8192 tokens.
- **Fast Mode**: **Nomic Embed Text v1.5** [Apache-2.0].
- **Reranker (Optional Toggle)**: **bge-reranker-v2-m3**.

### 3. Synthesis & Reasoning: Model Tiers
| Tier | Category | Local LLM Target | License | Hardware |
| :--- | :--- | :--- | :--- | :--- |
| **Edge** | Fast/Light | **Llama-3.2-1B** | Llama 3.2 | 8GB RAM |
| **Standard**| Balanced | **Ministral 3 3B Instruct** | Apache-2.0 | 8GB - 16GB |
| **Multimodal**| Vision | **Gemma 3** / **Qwen3-VL** | Mixed | 16GB+ RAM |
| **Pro / Logic**| High Precision | **Qwen 2.5 7B Instruct** | Apache-2.0 | 16GB+ RAM |

---

## The "Evidence Ladder" (Capability Scenarios)

The RAG system applies different routing logic based on the available metadata:

1. **Transcript Only**: Hybrid Search (Vector + FTS) → Evidence Spans → Grounded Synthesis.
2. **+ Diarization**: Faceted filters on `speaker_id`.
3. **+ NER**: Entity-first narrowing (Entity index hit → narrowed candidate slice → search).
4. **+ Structured Events**: Direct lookup path for decisions/actions; fallback to RAG.
5. **+ Visual Memory**: Concurrent retrieval from transcript and frame indices (by time-window).

---

## Synthesis Protocol: "Grounded or Silent"
1. **Pointers are Required**: Every claim must map to (meeting_id, speaker_id, t0/t1, segment_ids).
2. **"Not Found" Gating**: If evidence is missing, output "Not found in memory."
3. **Deterministic First**: Synthesis is a renderer over evidence pointers, not an improviser.

---

## Verification: The Offline Eval Harness
Before model selection is finalized, the system must pass an offline eval:
- **Corpus**: 30-50 canonical queries over real meetings.
- **Metrics**: Recall@K, MRR, and Faithfulness (supported by cited evidence).

---
> [!TIP]
> **Privacy Lock**: By default, no data leaves the device. The **Cloud Gemini File Search** is a restricted, opt-in feature for massive document sets only.
