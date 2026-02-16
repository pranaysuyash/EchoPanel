# Hybrid OCR Architecture Plan

**Date:** 2026-02-14  
**Purpose:** Combine PaddleOCR (speed) + SmolVLM (intelligence) for optimal screen slide processing  
**Strategy:** "Fast path + Smart enrichment" hybrid pipeline

---

## Executive Summary

Instead of choosing one engine, we run **both PaddleOCR and SmolVLM** in a coordinated pipeline:

```
Screen Frame
    │
    ├─► [Fast Path] PaddleOCR v5 ───────┐
    │        (50ms, 2MB)                │
    │        Raw text extraction          │
    │                                     ▼
    ├─► [Smart Path] SmolVLM-256M ────► [Fusion Engine]
    │        (200ms, <1GB)              (Deduplication + Merge)
    │        Semantic understanding       │
    │        Layout analysis              ▼
    │                              [RAG Index]
    │                              (Enriched content)
```

**Benefits:**
- ✅ Speed: PaddleOCR gives instant text (50ms)
- ✅ Intelligence: SmolVLM adds context ("This is a revenue chart...")
- ✅ Accuracy: Cross-validation between engines
- ✅ Fallback: If one fails, other continues
- ✅ Resource efficiency: SmolVLM only runs when needed

---

## 1. Hybrid Architecture Options

### Option A: Sequential (Layered)

```python
async def process_frame_hybrid(image_bytes):
    # Step 1: Fast extraction (always run)
    paddle_result = await paddle_ocr.process(image_bytes)
    
    # Step 2: Smart enrichment (conditional)
    if should_enrich(paddle_result):
        smol_result = await smol_vlm.process(image_bytes, 
                                             context=paddle_result.text)
        return merge_results(paddle_result, smol_result)
    
    return paddle_result
```

**When to enrich:**
- Low confidence from PaddleOCR (<80%)
- Complex layout detected (tables, charts)
- First frame of new slide (establish context)
- User asks question about content

**Pros:** Simple, resource-efficient
**Cons:** SmolVLM adds latency to some frames

---

### Option B: Parallel (Concurrent)

```python
async def process_frame_hybrid(image_bytes):
    # Run both simultaneously
    paddle_task = paddle_ocr.process(image_bytes)
    smol_task = smol_vlm.process(image_bytes)
    
    # Wait for both
    paddle_result, smol_result = await asyncio.gather(
        paddle_task, smol_task,
        return_exceptions=True
    )
    
    # Merge with confidence weighting
    return fusion_engine.merge(paddle_result, smol_result)
```

**Pros:** Maximum information, cross-validation
**Cons:** Higher resource usage per frame

---

### Option C: Tiered (Recommended) ⭐

```python
class HybridOCRPipeline:
    async def process_frame(self, image_bytes, context=None):
        # Tier 1: Always run fast OCR
        paddle_result = await self.paddle.process(image_bytes)
        
        # Tier 2: Decide if we need VLM
        needs_vlm = self._needs_vlm(paddle_result, context)
        
        if needs_vlm:
            # Run VLM with PaddleOCR context as prompt
            prompt = self._build_prompt(paddle_result)
            smol_result = await self.smol_vlm.process(image_bytes, prompt)
            
            # Tier 3: Fusion
            return self._fuse_results(paddle_result, smol_result)
        
        return EnrichedResult(
            text=paddle_result.text,
            semantic_context=None,  # No VLM run
            confidence=paddle_result.confidence
        )
    
    def _needs_vlm(self, paddle_result, context):
        """Decide if frame needs semantic enrichment."""
        return (
            paddle_result.confidence < 0.85 or
            paddle_result.detected_layout in ['chart', 'table', 'diagram'] or
            context.is_new_slide or
            context.user_query_pending
        )
```

**Why Tiered is Best:**
- 80% of frames: PaddleOCR only (50ms)
- 20% of frames: Both engines (250ms total)
- Average latency: ~90ms (weighted)
- All frames get semantic context when needed

---

## 2. Detailed Component Design

### 2.1 Fast Path: PaddleOCR v5

**Role:** Primary text extraction, layout detection

```python
@dataclass
class PaddleResult:
    text: str
    confidence: float
    word_count: int
    bounding_boxes: List[BBox]
    detected_layout: Literal['text', 'table', 'chart', 'diagram', 'mixed']
    processing_time_ms: int

class PaddleOCRPipeline:
    def __init__(self):
        self.ocr = PaddleOCR(
            use_angle_cls=True,
            lang='en',
            use_gpu=False,
            enable_mkldnn=True
        )
        self.layout_classifier = LayoutClassifier()  # Lightweight CNN
    
    async def process(self, image_bytes: bytes) -> PaddleResult:
        start = time.time()
        
        # OCR
        result = self.ocr.ocr(image_bytes, cls=True)
        text = self._extract_text(result)
        bboxes = self._extract_boxes(result)
        
        # Layout classification (separate lightweight model)
        layout = self.layout_classifier.predict(image_bytes)
        
        return PaddleResult(
            text=text,
            confidence=self._calculate_confidence(result),
            word_count=len(text.split()),
            bounding_boxes=bboxes,
            detected_layout=layout,
            processing_time_ms=int((time.time() - start) * 1000)
        )
```

**Layout Classifier:**
- Tiny CNN (MobileNet-based, ~5MB)
- Classifies: text-heavy, table, chart, diagram, mixed
- Runs in <10ms
- Used to decide if VLM enrichment needed

---

### 2.2 Smart Path: SmolVLM-256M

**Role:** Semantic understanding, context extraction, answer questions

```python
@dataclass
class SmolVLMResult:
    text: str                    # Extracted text
    semantic_summary: str        # "Q3 revenue chart showing 15% growth..."
    key_insights: List[str]      # Bullet points of important info
    entities: List[Entity]       # People, companies, metrics
    confidence: float
    processing_time_ms: int

class SmolVLMPipeline:
    def __init__(self):
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.model = AutoModelForVision2Seq.from_pretrained(
            "HuggingFaceTB/SmolVLM-256M-Instruct",
            torch_dtype=torch.bfloat16,
        ).to(self.device)
        self.processor = AutoProcessor.from_pretrained(
            "HuggingFaceTB/SmolVLM-256M-Instruct"
        )
    
    async def process(self, 
                      image_bytes: bytes, 
                      paddle_context: Optional[PaddleResult] = None) -> SmolVLMResult:
        """
        If paddle_context provided, use it to guide VLM focus.
        Example: "PaddleOCR found text: 'Revenue $5M'. 
                  Explain what this chart shows."
        """
        start = time.time()
        image = Image.open(BytesIO(image_bytes))
        
        # Build contextual prompt
        if paddle_context:
            prompt = self._build_contextual_prompt(paddle_context)
        else:
            prompt = "Extract all text and describe what this slide shows."
        
        messages = [{
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": prompt}
            ]
        }]
        
        # Run inference
        prompt_text = self.processor.apply_chat_template(messages, add_generation_prompt=True)
        inputs = self.processor(text=prompt_text, images=[image], return_tensors="pt")
        inputs = inputs.to(self.device)
        
        generated_ids = self.model.generate(**inputs, max_new_tokens=300)
        output = self.processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
        
        # Parse structured output
        return self._parse_output(output, time.time() - start)
    
    def _build_contextual_prompt(self, paddle: PaddleResult) -> str:
        """Use PaddleOCR results to guide SmolVLM."""
        base = f"""OCR detected the following text: \"{paddle.text[:500]}\"

This appears to be a {paddle.detected_layout} slide.

Your task:
1. Verify and correct the OCR text
2. Describe what this {paddle.detected_layout} shows
3. Extract key insights and metrics
4. Identify any people, companies, or important entities"""
        return base
```

---

### 2.3 Fusion Engine

**Role:** Merge results from both engines intelligently

```python
@dataclass
class HybridResult:
    # Text
    primary_text: str           # Best text extraction
    ocr_text: str               # Raw PaddleOCR output
    semantic_text: str          # SmolVLM understanding
    
    # Metadata
    confidence: float           # Combined confidence
    source: Literal['paddle_only', 'vlm_only', 'fused']
    
    # Enrichment
    layout_type: str
    key_insights: List[str]
    entities: List[Entity]
    summary: Optional[str]
    
    # Performance
    processing_time_ms: int
    engines_used: List[str]

class FusionEngine:
    def merge(self, 
              paddle: PaddleResult, 
              smol: Optional[SmolVLMResult] = None) -> HybridResult:
        
        if smol is None:
            # PaddleOCR only
            return HybridResult(
                primary_text=paddle.text,
                ocr_text=paddle.text,
                semantic_text="",
                confidence=paddle.confidence,
                source='paddle_only',
                layout_type=paddle.detected_layout,
                key_insights=[],
                entities=[],
                summary=None,
                processing_time_ms=paddle.processing_time_ms,
                engines_used=['paddleocr']
            )
        
        # Both engines available - smart fusion
        primary_text = self._select_best_text(paddle.text, smol.text)
        confidence = self._calculate_combined_confidence(
            paddle.confidence, smol.confidence
        )
        
        return HybridResult(
            primary_text=primary_text,
            ocr_text=paddle.text,
            semantic_text=smol.semantic_summary,
            confidence=confidence,
            source='fused',
            layout_type=paddle.detected_layout,
            key_insights=smol.key_insights,
            entities=smol.entities,
            summary=smol.semantic_summary,
            processing_time_ms=paddle.processing_time_ms + smol.processing_time_ms,
            engines_used=['paddleocr', 'smolvlm']
        )
    
    def _select_best_text(self, paddle_text: str, smol_text: str) -> str:
        """
        Use SmolVLM to correct PaddleOCR errors.
        SmolVLM is better at:
        - Handwriting
        - Low contrast text
        - Complex fonts
        - Context-aware corrections (e.g., "Revenu" → "Revenue")
        """
        # If texts are similar, use SmolVLM (more accurate)
        similarity = difflib.SequenceMatcher(None, paddle_text, smol_text).ratio()
        
        if similarity > 0.8:
            return smol_text  # SmolVLM corrected version
        elif len(smol_text) > len(paddle_text) * 0.7:
            return smol_text  # SmolVLM likely more complete
        else:
            return paddle_text  # Fallback to PaddleOCR
```

---

## 3. Usage Modes

### Mode 1: Background Capture (Default)

```python
# Continuous screen capture - optimize for speed
pipeline = HybridOCRPipeline(mode='background')

# Configuration
config = {
    'paddleocr': {
        'enabled': True,
        'confidence_threshold': 0.85
    },
    'smolvlm': {
        'enabled': True,
        'trigger': 'conditional',  # Only when needed
        'max_concurrent': 1
    },
    'fusion': {
        'strategy': 'tiered'
    }
}

# Processing:
# Frame 1 (new slide): Both engines (establish context)
# Frame 2-5 (same slide): PaddleOCR only (fast)
# Frame 6 (new slide): Both engines
```

**Result:** 80% frames use PaddleOCR only (~50ms), 20% use both (~250ms)

---

### Mode 2: Active Query (User asks question)

```python
# User asks: "What was the Q3 revenue number?"
pipeline = HybridOCRPipeline(mode='query')

# Force VLM for detailed understanding
result = await pipeline.process_frame(image_bytes, force_vlm=True)

# Use SmolVLM to answer specific question
answer = await pipeline.query("What was the Q3 revenue number?")
```

**Result:** Always use SmolVLM for rich semantic understanding

---

### Mode 3: Quality Priority (Archive/Export)

```python
# Exporting session - maximize quality
pipeline = HybridOCRPipeline(mode='quality')

# Configuration
config = {
    'smolvlm': {
        'enabled': True,
        'trigger': 'always',  # Every frame
        'model': 'SmolVLM-500M'  # Larger model
    }
}
```

**Result:** Every frame gets full enrichment

---

## 4. Adaptive Trigger Logic

```python
class AdaptiveTrigger:
    """Decide when to run SmolVLM based on content and context."""
    
    def __init__(self):
        self.frame_history = deque(maxlen=10)
        self.slide_context = None
    
    def should_run_vlm(self, 
                       paddle_result: PaddleResult,
                       frame_number: int) -> Tuple[bool, str]:
        """
        Returns: (should_run, reason)
        """
        reasons = []
        
        # 1. Confidence-based
        if paddle_result.confidence < 0.85:
            reasons.append(f"low_confidence ({paddle_result.confidence:.2f})")
        
        # 2. Layout-based (complex content)
        if paddle_result.detected_layout in ['chart', 'table', 'diagram']:
            reasons.append(f"complex_layout ({paddle_result.detected_layout})")
        
        # 3. New slide detection (perceptual hash change)
        if self._is_new_slide(paddle_result):
            reasons.append("new_slide")
        
        # 4. Text significance (numbers, metrics, names)
        if self._contains_key_metrics(paddle_result.text):
            reasons.append("key_metrics_detected")
        
        # 5. Periodic (every Nth frame for context refresh)
        if frame_number % 10 == 0:
            reasons.append("periodic_refresh")
        
        # 6. User query pending
        if self.user_query_pending:
            reasons.append("user_query")
        
        should_run = len(reasons) > 0
        return should_run, ", ".join(reasons)
    
    def _contains_key_metrics(self, text: str) -> bool:
        """Detect if text contains financial/metrics data."""
        patterns = [
            r'\$[\d,]+\.?\d*',      # Dollar amounts
            r'\d+\.?\d*%',          # Percentages
            r'Q[1-4]\s+\d{4}',      # Quarters
            r'\d{1,2}/\d{1,2}/\d{2,4}',  # Dates
            r'revenue|profit|growth|users',  # Keywords
        ]
        return any(re.search(p, text, re.I) for p in patterns)
```

---

## 5. Resource Management

### Memory Budget

| Component | Memory | Notes |
|-----------|--------|-------|
| PaddleOCR v5 | 20MB | Model + runtime |
| Layout Classifier | 5MB | MobileNet CNN |
| SmolVLM-256M | 600MB | BFloat16 on MPS |
| **Total (both)** | **~650MB** | Well within 8GB Mac limit |

### Concurrency Strategy

```python
class ResourceManager:
    """Manage GPU/MPS memory for both engines."""
    
    def __init__(self):
        self.paddle_pool = ThreadPoolExecutor(max_workers=2)
        self.vlm_semaphore = asyncio.Semaphore(1)  # Only 1 VLM at a time
        self.vlm_queue = asyncio.Queue()
    
    async def process_vlm(self, image_bytes, prompt):
        """VLM runs with semaphore to prevent OOM."""
        async with self.vlm_semaphore:
            return await self.smol_vlm.process(image_bytes, prompt)
    
    def process_paddle(self, image_bytes):
        """PaddleOCR runs in thread pool (CPU)."""
        return self.paddle_pool.submit(self.paddle_ocr.process, image_bytes)
```

---

## 6. RAG Integration

```python
async def index_to_rag(hybrid_result: HybridResult, session_id: str):
    """Store enriched OCR to RAG with multiple representations."""
    
    document = {
        # Original content
        'text': hybrid_result.primary_text,
        'source': 'screen_ocr',
        'timestamp': datetime.now().isoformat(),
        
        # Metadata
        'layout_type': hybrid_result.layout_type,
        'confidence': hybrid_result.confidence,
        'engines_used': hybrid_result.engines_used,
        
        # Semantic enrichment (SmolVLM output)
        'semantic_summary': hybrid_result.summary,
        'key_insights': hybrid_result.key_insights,
        'entities': hybrid_result.entities,
        
        # Searchable text combines both
        'searchable_text': f"""
        {hybrid_result.primary_text}
        
        Context: {hybrid_result.summary}
        Insights: {' '.join(hybrid_result.key_insights)}
        """
    }
    
    # Create embedding from enriched text
    embedding = await create_embedding(document['searchable_text'])
    
    # Store in RAG
    await rag_store.add_document(
        session_id=session_id,
        document=document,
        embedding=embedding
    )
```

**Benefit:** RAG searches across both raw OCR text AND semantic understanding

---

## 7. Implementation Roadmap

### Phase 1: Basic Hybrid (Week 1)

```python
# server/services/ocr_hybrid.py

class HybridOCRPipeline:
    def __init__(self):
        self.paddle = PaddleOCRPipeline()
        self.smol = SmolVLMPipeline()
        self.fusion = FusionEngine()
    
    async def process_frame(self, image_bytes, context=None):
        # Always run PaddleOCR
        paddle_result = await self.paddle.process(image_bytes)
        
        # Run SmolVLM if confidence low
        if paddle_result.confidence < 0.85:
            smol_result = await self.smol.process(image_bytes, paddle_result)
            return self.fusion.merge(paddle_result, smol_result)
        
        return self.fusion.merge(paddle_result, None)
```

**Deliverable:** Working hybrid with confidence-based trigger

---

### Phase 2: Smart Triggers (Week 2)

- Add layout classifier
- Implement adaptive trigger logic
- Add new slide detection
- Periodic VLM refresh

**Deliverable:** 80% PaddleOCR only, 20% both

---

### Phase 3: Full Fusion (Week 3)

- Contextual prompts (PaddleOCR → SmolVLM)
- Text correction fusion
- Semantic summary generation
- Entity extraction

**Deliverable:** Rich hybrid results with insights

---

### Phase 4: Optimization (Week 4)

- MLX Swift integration (native macOS)
- ONNX export for both engines
- INT8 quantization
- Concurrent processing optimization

**Deliverable:** Production-ready performance

---

## 8. Configuration

```yaml
# config/ocr.yaml
ocr:
  mode: hybrid  # paddle_only, vlm_only, hybrid
  
  paddleocr:
    enabled: true
    model_version: v5
    lang: en
    use_gpu: false
    confidence_threshold: 0.85
    
  smolvlm:
    enabled: true
    model: HuggingFaceTB/SmolVLM-256M-Instruct  # or 500M, 2.2B
    device: auto  # mps, cuda, cpu
    dtype: bfloat16
    
    # Trigger conditions
    trigger:
      mode: adaptive  # always, adaptive, confidence_only
      confidence_threshold: 0.85
      layout_types: [chart, table, diagram]
      periodic_frames: 10
      
  fusion:
    strategy: tiered  # tiered, parallel, sequential
    text_selection: smart  # paddle, vlm, smart
    
  performance:
    max_concurrent_vlm: 1
    vlm_timeout_ms: 5000
    paddle_timeout_ms: 500
```

---

## 9. Benchmarks (Target)

| Metric | PaddleOCR Only | SmolVLM Only | Hybrid (Tiered) |
|--------|----------------|--------------|-----------------|
| **Avg Latency** | 50ms | 250ms | **90ms** |
| **DocVQA Accuracy** | 75% | 68% | **80%** |
| **Semantic Understanding** | ❌ | ✅ | ✅ |
| **Memory (peak)** | 20MB | 600MB | **650MB** |
| **CPU Usage** | Low | Medium | Low-Medium |
| **Power Efficiency** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |

**Why Hybrid Wins:**
- 3.6x faster than VLM-only
- Better accuracy than PaddleOCR-only (corrections)
- Semantic richness of VLM at fraction of cost

---

## 10. Summary

### Best of Both Worlds

| Aspect | PaddleOCR | SmolVLM | Hybrid Result |
|--------|-----------|---------|---------------|
| **Speed** | 50ms ⚡ | 250ms | 90ms avg ⚡ |
| **Size** | 2MB | 600MB | 650MB total |
| **Raw OCR** | 75% | 68% | 80% (corrected) |
| **Understanding** | None | Excellent | Excellent |
| **Charts/Tables** | Poor | Good | Good |
| **Handwriting** | Poor | Good | Good |

### Key Innovation

**Contextual Prompting:** Use PaddleOCR output to prime SmolVLM:

```
PaddleOCR: "Revenu $5M, Grwoth 15%"
          ↓
SmolVLM: "I see the OCR detected 'Revenu' and 'Grwoth' which 
          are likely typos for 'Revenue' and 'Growth'. 
          This chart shows Q3 revenue of $5M with 15% growth."
          ↓
Fusion:  "Revenue: $5M, Growth: 15%"
```

### Recommendation

**Implement Tiered Hybrid immediately:**

1. **This week:** Basic hybrid (confidence trigger)
2. **Next week:** Smart triggers (layout, new slide)
3. **Week 3:** Full fusion with contextual prompts
4. **Week 4:** MLX Swift optimization

**Expected outcome:** 80% reduction in VLM compute while maintaining 95% of semantic value.

---

*Plan created 2026-02-14. Ready for implementation.*
