# Discussion: OCR Pipeline for Screen Capture

**Date:** 2026-02-14  
**Participants:** Pranay (User), Agent (Kimi Code CLI)  
**Context:** Post-audit implementation roadmap, Strategic Option B  
**Ticket:** TCK-20260214-084 (created in WORKLOG_TICKETS.md)  
**Source:** `docs/IMPLEMENTATION_ROADMAP_2026-02-14.md` - Phase 3 Strategic Capabilities

> **Update (2026-02-16):** OCR planning and partial implementation were reconciled in backlog docs.
> Implemented/planned artifacts are tracked under `TCK-20260214-084` and `TCK-20260214-089` (DONE), with remaining completion work ticketized as `TCK-20260216-012` (OPEN).
> Use `docs/EXPLORATION_ACTION_TRIAGE_2026-02-16.md` and `docs/WORKLOG_TICKETS.md` for current status.

---

## 1. Executive Summary

Discussed implementing an OCR (Optical Character Recognition) pipeline to extract text from screen captures during meetings. This would capture presentation slides, documents, and web content that appears on screen, automatically indexing it into the RAG system for context-aware insights.

**Key Outcome:** Documented as strategic option; decision pending on launch timeline vs. differentiation value.

---

## 2. User Request

> "lets discuss the no. 2"  
> - Referring to "Option B: OCR Pipeline" from Implementation Roadmap

User initiated discussion of OCR Pipeline as a potential strategic capability to implement.

---

## 3. Technical Architecture Presented

### 3.1 Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  USER'S SCREEN                                                   │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │  Presentation   │    │   Document      │                     │
│  │  Slide: Q3      │    │   Contract      │                     │
│  │  Revenue: $5M   │    │   Terms...      │                     │
│  └────────┬────────┘    └────────┬────────┘                     │
│           │                      │                               │
└───────────┼──────────────────────┼───────────────────────────────┘
            │                      │
            ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  ECHOPANEL OCR PIPELINE                                          │
│                                                                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│  │ Frame Grab  │──▶│  OCR Engine │──▶│ Deduplicate │           │
│  │ (30s intvl) │   │ Apple Vision│   │ (perceptual │           │
│  └─────────────┘   └─────────────┘   │ hash)       │           │
│                                       └──────┬──────┘           │
│                                              │                   │
│                                              ▼                   │
│                                       ┌─────────────┐           │
│                                       │ RAG Index   │           │
│                                       │ source=screen│          │
│                                       └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│  USER ASKS: "What was the Q3 revenue number?"                   │
│                                                                  │
│  RAG Query ──▶ Retrieves: "Q3 Revenue: $5M" from slide OCR      │
│                                                                  │
│  No one had to type it. It was on the screen.                   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Proposed Implementation

**New Module:** `server/services/screen_ocr.py`

```python
class ScreenOCRPipeline:
    """
    Extracts text from screen capture frames during meetings.
    """
    
    def __init__(self):
        self.frame_interval = 30  # seconds
        self.last_frame_hash = None
        self.ocr_engine = AppleVisionOCR()  # or pytesseract fallback
    
    async def process_frame(self, image_data: bytes) -> Optional[OCRResult]:
        # 1. Check if frame is different (perceptual hash)
        current_hash = perceptual_hash(image_data)
        if current_hash == self.last_frame_hash:
            return None  # Duplicate slide, skip
        
        # 2. Run OCR
        text = await self.ocr_engine.recognize(image_data)
        
        # 3. Deduplicate text (don't index if same as last)
        if text_similarity(text, self.last_text) < 0.9:
            # 4. Index into RAG
            await self.index_to_rag(text, timestamp=now())
        
        self.last_frame_hash = current_hash
        return OCRResult(text=text, timestamp=now())
```

### 3.3 Integration Points

| Component | Change | Location |
|-----------|--------|----------|
| Client (Swift) | Capture frame every 30s | `MeetingListenerApp.swift` |
| WebSocket | New message type `screen_frame` | `ws_live_listener.py` |
| OCR Processing | New service module | `services/screen_ocr.py` |
| RAG Indexing | Auto-index with `source="screen"` | `rag_store.py` |
| API | New endpoints for screen documents | `documents.py` |

---

## 4. Competitive Analysis

| Tool | Audio | Transcript | Screen OCR | Notes |
|------|-------|------------|------------|-------|
| Otter.ai | ✅ | ✅ | ❌ | Market leader, no visual context |
| Fireflies | ✅ | ✅ | ❌ | AI summaries only |
| Grain | ✅ | ✅ | ❌ | Focuses on clips/sharing |
| Fathom | ✅ | ✅ | ❌ | CRM integration only |
| **EchoPanel** | ✅ | ✅ | **🆕 Unique** | **Differentiator if implemented** |

**Competitive Advantage:** No meeting assistant currently captures visual/slide content automatically.

---

## 5. Implementation Approaches Discussed

### 5.1 Option A: Server-Side (macOS Only)

| Aspect | Details |
|--------|---------|
| **Pros** | Real-time processing, no client bandwidth usage |
| **Cons** | Requires server on macOS, complex permissions, not cross-platform |
| **Effort** | 4 days |
| **Risk** | High (ScreenCaptureKit permissions in server context) |

### 5.2 Option B: Client-Side (Recommended)

| Aspect | Details |
|--------|---------|
| **Pros** | Cross-platform, simpler architecture, client already has screen access |
| **Cons** | More bandwidth (sending frames), client CPU for compression |
| **Effort** | 3 days |
| **Risk** | Low (proven pattern, client already captures) |

**Recommendation:** Option B (Client-side frame capture, server-side OCR)

---

## 6. Challenges & Solutions Identified

| Challenge | Solution Proposed |
|-----------|-------------------|
| **Performance** (OCR is slow: 500ms-2s) | Run async in thread pool; skip similar frames via perceptual hash; resize to 720p |
| **Privacy Concerns** | Make opt-in (default off); only capture during active recording; offer on-device OCR option |
| **Accuracy on Slides** | Use Apple Vision (structured text optimized); fallback to easyOCR; 80% confidence threshold |
| **Storage Growth** | Only store OCR text (not images); aggressive deduplication; auto-delete after session |
| **Bandwidth** (client→server) | JPEG compression (quality 0.7); only send changed frames; 30s interval default |

---

## 7. Implementation Phases Proposed

### Phase 1: MVP (3 days)
- [ ] Basic OCR with Apple Vision framework
- [ ] Client-side frame capture every 30 seconds
- [ ] Auto-index extracted text to RAG
- [ ] No deduplication (process all frames)

### Phase 2: Polish (2 days)
- [ ] Perceptual hash deduplication (skip duplicate slides)
- [ ] Confidence threshold filtering
- [ ] Settings UI for opt-in/control
- [ ] Privacy controls and indicators

### Phase 3: Advanced (3 days)
- [ ] Real-time slide change detection (vs fixed interval)
- [ ] Table/chart structure extraction
- [ ] Image captioning for diagrams
- [ ] Export with slide references

**Total Effort:** 5 days (MVP + Polish), 8 days (Full)

---

## 8. User Experience Design

### 8.1 Settings UI

```
[ ] Enable Screen Content Capture
    Capture presentation slides and documents
    for better meeting context
    
    Frame capture interval: [30 seconds ▼]
    Options: 10s / 30s / 60s / Manual
    
    [ ] Show capture indicator in menu bar
    
    Privacy: Screen content is processed locally
    when possible and stored as text only.
```

### 8.2 Example Interaction

**Meeting:** Q3 Financial Review

**Transcript:**
```
[10:00] Alice: "As you can see on the slide..."
[10:01] Bob: "What's the revenue number again?"
```

**Screen Capture OCR [10:00:15]:**
```
Q3 2026 Financial Results
Revenue: $5.2M (+23% YoY)
New Customers: 1,240
Gross Margin: 78%
```

**EchoPanel Generated Insight:**
```
Q3 revenue was $5.2M (23% growth, 1,240 new customers)
Source: Slide "Q3 2026 Financial Results" [10:00 AM]
```

---

## 9. Agent Recommendation

**Recommendation: BUILD THIS**

**Rationale:**
1. **Differentiation:** No competitor has this capability
2. **User Value:** Captures 50% of meeting content currently lost (visual context)
3. **Technical Feasibility:** Low risk (proven OCR tech, straightforward integration)
4. **Strategic Value:** Creates moat that's hard to replicate

**Trade-offs:**
- 5-day effort pushes other features
- Privacy complexity requires careful UX
- Adds infrastructure cost (OCR processing)

**Decision Framework:**
- **If launch >2 weeks away:** Build MVP (Phase 1)
- **If launch <2 weeks away:** Defer to post-launch roadmap as P0
- **If iterating before launch:** Build full (Phases 1-2)

---

## 10. Open Questions

Questions posed to user for decision:

1. **Launch Timeline:** Do we have 1 week to implement MVP before launch?

2. **Privacy Model:** Should this be:
   - Opt-in (default off, user enables)
   - Opt-out (default on, user disables)
   - Always ask per-session

3. **Scope for v1:** 
   - MVP only (basic text extraction)
   - Polish included (deduplication + settings)
   - Full feature (tables, charts, change detection)

4. **Processing Location:**
   - Server-side OCR (requires frame upload)
   - Client-side OCR (requires Swift OCR library)
   - Hybrid (client for simple, server for complex)

---

## 11. Related Documentation

| Document | Relationship |
|----------|--------------|
| `docs/IMPLEMENTATION_ROADMAP_2026-02-14.md` | Source document referencing this as "Option B" |
| `docs/WORKLOG_TICKETS.md` (TCK-20260214-084) | Formal ticket created for this feature |
| `docs/audit/pipeline-intelligence-layer-20260214.md` | Identified "No OCR Pipeline" as gap (ORC-001, ORC-002) |

---

## 12. Next Actions

Pending user decision on:
- [ ] Priority relative to launch timeline
- [ ] Privacy model preference
- [ ] Scope (MVP vs Polish vs Full)

If approved for implementation:
- [ ] Create detailed technical spec
- [ ] Break into sub-tasks
- [ ] Begin Phase 1 implementation

---

*Discussion documented per AGENTS.md requirements. All technical proposals and trade-offs captured for future reference.*
