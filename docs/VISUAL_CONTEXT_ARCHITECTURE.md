# Visual Context Architecture (v0.3 Specification)

## Overview
EchoPanel's Visual Context layer turns screen shares, slides, and shared documents into a timestamped **Visual Memory**. This allows users to search not just for what was *said*, but for what was *shown*.

## The Visual Path (Two-Stage Pipeline)

EchoPanel implements a "Dual-Speed" visual ingestion pipeline to maximize accuracy while minimizing battery and GPU drain.

### Stage 1: Capture & Change Detection (Always-On)
- **Engine**: Apple **ScreenCaptureKit** (Native macOS API).
- **Optimization**: We downscale copies for OCR (e.g., 1440p -> 960p) to stabilize latency.
- **Gating**: 
  - Capture screen snapshots at 1fps.
  - **Keyframe Trigger**: Compute **pHash** (Perceptual Hash) or **SSIM** between the current frame and the last indexed frame.
  - **Threshold**: If the change is below the threshold, skip Stage 2. If the change is significant (e.g., slide flip), promote to the **Extraction Tiers**.

---

### Stage 2: Extraction Tiers (Tiered Intelligence)

We apply tiered logic to promovted keyframes to respect hardware budgets:

| Tier | Engine | Role | Footprint | License |
| :--- | :--- | :--- | :--- | :--- |
| **Tier A (Fast)** | **Apple Vision** | Always-on native OCR. Extracts "Lexical Anchors" (keywords/numbers) for the RAG index. | <50MB RAM | Native |
| **Tier B (Structure)**| **LightOnOCR-2-1B** | On-demand document conversion (Markdown/Tables/Structure). Best for slides/docs. | ~1GB RAM | Apache-2.0 |
| **Tier C (Semantic)** | **SmolVLM2 (MLX)** | Generates a "Dense Visual Summary" (e.g., "A chart showing upward revenue trend"). | 500MB - 2GB RAM | Apache-2.0 |

---

## Visual Memory Schema
Every keyframe is stored as a "Visual Memory Object" in LanceDB with `media_type: "visual"`:

```json
{
  "meeting_id": "uuid",
  "t0": 450.2,
  "t1": 465.5,
  "ocr_text": "Q4 Results: Revenue $5M...",
  "semantic_summary": "Slide showing Q4 financial metrics and bar charts.",
  "doc_markdown": "# Q4 Projections\n- Revenue: $5.2M\n...",
  "metadata": {
    "app_name": "Keynote",
    "window_title": "Investor Deck",
    "has_tables": true,
    "source_hash": "phash_123"
  }
}
```

## Retrieval Strategy: Temporal Fusion
When a user queries the RAG system:
1. **Hybrid Retrieval**: Search over both transcript chunks and "Visual Memory" objects.
2. **Temporal Banding**: If a relevant transcript hit is found, the system automatically retrieves any visual keyframes in the `[T-30s, T+30s]` band.
3. **Evidence Fusion**: The LLM synthesizes the final answer using the transcript *and* the visual summary content.

## Licensing & Ethics
- **Redlines**: Avoid **Surya** (GPL-3.0) and **OmniParser** (AGPL) for default commercial redistribution.
- **Privacy Lock**: 100% on-device. No screen data leaves the Mac.
- **Safety**: App allowlist/denylist for capture to avoid sensitive data (e.g., password managers).
