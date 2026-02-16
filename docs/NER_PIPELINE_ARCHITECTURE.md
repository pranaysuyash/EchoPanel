# NER Pipeline Architecture

## Implementation Status

| Feature | Status | Version | Notes |
|---------|--------|---------|-------|
| Regex/Pattern Matching | ✅ **Implemented** | v0.2 | Current production implementation |
| Keyword-based Extraction | ✅ **Implemented** | v0.2 | Actions, Decisions, Risks via patterns |
| GLiNER Integration | 🚧 **Planned** | v0.3 | Specification complete, pending implementation |
| Transformer NER (spaCy) | 🚧 **Planned** | v0.3 | en_core_web_trf for post-call analysis |
| Evidence Pointer API | 🚧 **Planned** | v0.3 | Standardized pointer format |
| Dynamic Label Adjustment | 🚧 **Planned** | v0.3 | Runtime context-aware labels |

> **Current Implementation (v0.2):** The NER pipeline currently uses **regex-based pattern matching** for entity extraction (versions, money, dates, URLs, emails) and **keyword-based extraction** for actions, decisions, and risks. GLiNER integration is planned for v0.3.
>
> **Gap Tracking:** See `docs/gaps-report-v2-20260212.md` (DD-001 / DD-002) and ticket `TCK-20260214-076`.

## Overview
EchoPanel's NER pipeline provides the structured "Evidence Anchors" that drive precision query routing. It transitions from basic string matching to a hybrid system that treats entities as first-class citizens in the RAG index.

## The Hybrid Model
We explicitly separate deterministic facts from probabilistic semantic labels.

### 1. Deterministic Layer (Regex/EntityRuler)
- **Scope**: Versions (e.g., `v0.3`), Money, Dates/Times, URLs, Emails, and EchoPanel-specific identifiers.
- **Goal**: 100% precision for non-ambiguous patterns.

### 2. Semantic Layer (GLiNER)
- **Scope**: Person, Organization, Product, Project, Technical Term.
- **Dynamic Events**: Action Items, Decisions, Risks, Deadlines.
- **Why GLiNER?**: Unlike spaCy, it allows for open-palette labeling. We can adjust extraction labels at runtime based on meeting context.
- **Interface**: GLiNER is treated as a modular model service, abstracting the runtime (ONNX/MLX) from the analysis logic.

## Evidence Pointers as the API
Every extraction must emit a standard **Evidence Pointer** to ensure compatibility with the RAG synthesis layer:

```json
{
  "label": "DECISION",
  "text": "Approve the v0.3 spec",
  "confidence": 0.94,
  "pointer": {
    "meeting_id": "uuid",
    "speaker_id": "spk_1",
    "t0": 450.2,
    "t1": 458.5,
    "segment_ids": ["seg_12", "seg_13"]
  }
}
```

## Execution & Latency Realism
EchoPanel switches models based on the active workflow to maintain battery life and UI responsiveness:

| Workflow | Phase | Target Model | Resource Profile |
| :--- | :--- | :--- | :--- |
| **Live Call** | Streaming | `en_core_web_lg` (CNN) | <50ms CPU; Lightest footprint. |
| **Post-Call** | Archival | `en_core_web_trf` (Transf.) | Managed background Task; Max accuracy. |
| **Semantic** | Optional | `gliner-tiny` / `small` | Targeted semantic tagging on-demand. |

---
> [!IMPORTANT]
> **Data Provenance**: The raw transcript is never mutated. Entities exist as a metadata overlay, allowing for multiple overlapping interpretations (e.g., the same text span can be both a "PROJECT" and a "DECISION").
