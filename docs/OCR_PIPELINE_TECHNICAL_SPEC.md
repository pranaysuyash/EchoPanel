# OCR Pipeline Technical Specification

**Version:** 1.0  
**Date:** 2026-02-14  
**Status:** Implementation Phase  
**Ticket:** TCK-20260214-084  
**Discussion:** `docs/discussions/DISCUSSION_OCR_PIPELINE_2026-02-14.md`

---

## 1. Overview

### 1.1 Purpose
Extract text from screen capture frames during meetings to capture presentation slides, documents, and visual content. Automatically index into RAG for context-aware insights.

### 1.2 Architecture Decision
**Client-Side Frame Capture + Server-Side OCR** (Option B from discussion)

Rationale:
- Client already has ScreenCaptureKit access and permissions
- Cross-platform compatible
- Simpler permission model
- Server can be headless

### 1.3 OCR Engine Selection

| Engine | Pros | Cons | Decision |
|--------|------|------|----------|
| Apple Vision | Best accuracy, native | Requires Swift bridge | Client-side only |
| **Tesseract (pytesseract)** | Pure Python, fast, good accuracy | Requires installation | **Selected** |
| easyOCR | PyTorch-based, multilingual | Heavy dependency, slower | Not selected |

**Selected:** pytesseract with Pillow preprocessing

---

## 2. System Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLIENT (macOS)                                │
│  ┌─────────────────┐      ┌─────────────┐      ┌──────────────────┐    │
│  │ ScreenCaptureKit│─────▶│ Frame Buffer│─────▶│ JPEG Compression │    │
│  │ (existing)      │      │ (30s timer) │      │ (quality 0.7)    │    │
│  └─────────────────┘      └─────────────┘      └────────┬─────────┘    │
│                                                         │               │
│                              ┌──────────────────────────┘               │
│                              ▼                                          │
│                         ┌─────────────┐                                 │
│                         │ WebSocket   │                                 │
│                         │ Send Frame  │                                 │
│                         └──────┬──────┘                                 │
└────────────────────────────────┼────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           SERVER (Python)                               │
│  ┌─────────────┐      ┌─────────────┐      ┌──────────────────────┐    │
│  │ Frame       │─────▶│ Perceptual  │─────▶│ pytesseract OCR      │    │
│  │ Receive     │      │ Hash Check  │      │ (with preprocessing) │    │
│  └─────────────┘      └─────────────┘      └──────────┬───────────┘    │
│                                                        │                │
│                              ┌─────────────────────────┘                │
│                              ▼                                          │
│  ┌─────────────────┐      ┌─────────────┐      ┌──────────────────┐    │
│  │ RAG Store       │◀─────│ Text        │◀─────│ Confidence       │    │
│  │ source="screen" │      │ Extraction  │      │ Threshold (>80%) │    │
│  └─────────────────┘      └─────────────┘      └──────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

1. **Client** captures frame every 30 seconds (configurable)
2. **Client** compresses to JPEG (quality 0.7), resizes to 720p
3. **Client** sends via WebSocket with message type `screen_frame`
4. **Server** receives and decodes base64 image
5. **Server** computes perceptual hash, skips if duplicate
6. **Server** preprocesses image (grayscale, contrast, denoise)
7. **Server** runs OCR with Tesseract
8. **Server** filters by confidence (>80%)
9. **Server** indexes to RAG with metadata (timestamp, session_id, source="screen")

---

## 3. Implementation Details

### 3.1 New Files

```
server/
├── services/
│   ├── screen_ocr.py          # Main OCR pipeline
│   ├── image_hash.py          # Perceptual hashing
│   └── image_preprocess.py    # Image preprocessing
├── api/
│   └── ws_live_listener.py    # Add screen_frame handler
└── tests/
    ├── test_screen_ocr.py     # OCR tests
    └── test_image_hash.py     # Hash tests

macapp/MeetingListenerApp/Sources/
├── ScreenCaptureManager.swift  # Frame capture
├── OCRFrameSender.swift        # WebSocket sender
└── Views/
    └── OCROptionsView.swift    # Settings UI
```

### 3.2 Dependencies

```
# requirements.txt additions
pytesseract==0.3.13
Pillow==10.4.0          # Already installed
imagehash==4.3.1        # Perceptual hashing
```

System dependency:
```bash
# macOS
brew install tesseract tesseract-lang

# Or download language data manually
```

### 3.3 Configuration

```python
# Environment variables
ECHOPANEL_OCR_ENABLED="true"                    # Master switch
ECHOPANEL_OCR_FRAME_INTERVAL="30"               # Seconds between captures
ECHOPANEL_OCR_JPEG_QUALITY="0.7"                # Compression quality
ECHOPANEL_OCR_MAX_DIMENSION="1280"              # Max width/height
ECHOPANEL_OCR_CONFIDENCE_THRESHOLD="80"         # Min confidence %
ECHOPANEL_OCR_DEDUP_THRESHOLD="5"               # Hash difference threshold
ECHOPANEL_OCR_LANG="eng"                        # Tesseract language
```

---

## 4. API Specification

### 4.1 WebSocket Messages

**Client → Server: Screen Frame**
```json
{
  "type": "screen_frame",
  "session_id": "uuid",
  "timestamp": 1707830400.0,
  "image_data": "base64_encoded_jpeg",
  "metadata": {
    "width": 1280,
    "height": 720,
    "source": "screen_capture"
  }
}
```

**Server → Client: OCR Result**
```json
{
  "type": "ocr_result",
  "timestamp": 1707830400.0,
  "success": true,
  "text_preview": "Q3 Revenue: $5.2M...",
  "word_count": 42,
  "indexed": true,
  "document_id": "uuid"
}
```

### 4.2 REST API Endpoints

**GET /ocr/status**
```json
{
  "enabled": true,
  "tesseract_available": true,
  "languages": ["eng"],
  "version": "5.3.4"
}
```

**POST /ocr/test** (for debugging)
```json
{
  "image_base64": "...",
  "confidence_threshold": 80
}

Response:
{
  "text": "extracted text",
  "confidence": 92.5,
  "processing_time_ms": 450
}
```

---

## 5. Core Algorithms

### 5.1 Perceptual Hash (pHash)

```python
def compute_phash(image: PIL.Image) -> str:
    """
    Compute perceptual hash for image deduplication.
    Uses average hash (aHash) - fast and good for slides.
    """
    return str(imagehash.average_hash(image))

def is_duplicate(hash1: str, hash2: str, threshold: int = 5) -> bool:
    """
    Check if two hashes represent similar images.
    Hamming distance <= threshold means similar.
    """
    return imagehash.hex_to_hash(hash1) - imagehash.hex_to_hash(hash2) <= threshold
```

### 5.2 Image Preprocessing Pipeline

```python
def preprocess_for_ocr(image: PIL.Image) -> PIL.Image:
    """
    Optimize image for OCR accuracy.
    """
    # 1. Convert to grayscale
    gray = image.convert('L')
    
    # 2. Increase contrast
    enhancer = ImageEnhance.Contrast(gray)
    high_contrast = enhancer.enhance(2.0)
    
    # 3. Resize if too large (maintain aspect ratio)
    max_dim = 1280
    if max(image.size) > max_dim:
        ratio = max_dim / max(image.size)
        new_size = (int(image.width * ratio), int(image.height * ratio))
        high_contrast = high_contrast.resize(new_size, Image.Resampling.LANCZOS)
    
    # 4. Denoise (optional, for low quality)
    # Apply mild Gaussian blur then sharpen
    denoised = high_contrast.filter(ImageFilter.GaussianBlur(radius=0.5))
    
    return denoised
```

### 5.3 OCR with Confidence

```python
def ocr_with_confidence(image: PIL.Image, lang: str = 'eng') -> Tuple[str, float]:
    """
    Run OCR and return text with average confidence.
    """
    # Get detailed data including confidence
    data = pytesseract.image_to_data(
        image, 
        lang=lang,
        output_type=pytesseract.Output.DICT
    )
    
    # Filter by confidence and extract text
    words = []
    confidences = []
    
    for i, conf in enumerate(data['conf']):
        if int(conf) > 0:  # Valid confidence
            word = data['text'][i].strip()
            if word:
                words.append(word)
                confidences.append(int(conf))
    
    text = ' '.join(words)
    avg_confidence = sum(confidences) / len(confidences) if confidences else 0
    
    return text, avg_confidence
```

---

## 6. Client-Side Implementation (Swift)

### 6.1 Frame Capture

```swift
class OCRFrameCapture {
    private let captureInterval: TimeInterval = 30.0
    private var timer: Timer?
    private var lastFrameHash: String?
    
    func startCapture() {
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { _ in
            self.captureFrame()
        }
    }
    
    private func captureFrame() {
        // 1. Capture from ScreenCaptureKit
        // 2. Resize to max 1280px dimension
        // 3. Compress to JPEG (quality 0.7)
        // 4. Send via WebSocket
    }
}
```

### 6.2 Settings UI

```swift
struct OCROptionsView: View {
    @AppStorage("ocrEnabled") private var enabled = false
    @AppStorage("ocrInterval") private var interval = 30
    
    var body: some View {
        Form {
            Toggle("Capture Screen Content", isOn: $enabled)
            
            if enabled {
                Picker("Capture Interval", selection: $interval) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("Manual").tag(0)
                }
                
                Text("Screen content helps EchoPanel understand presentations and documents shared during meetings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

```python
def test_perceptual_hash_similarity():
    """Test that similar images have close hashes."""
    img1 = create_test_slide("Q3 Revenue: $5M")
    img2 = create_test_slide("Q3 Revenue: $5M")  # Same content
    
    hash1 = compute_phash(img1)
    hash2 = compute_phash(img2)
    
    assert is_duplicate(hash1, hash2)

def test_ocr_extraction():
    """Test OCR extracts text from slide."""
    image = load_test_image("slide_q3_revenue.png")
    
    text, confidence = ocr_with_confidence(image)
    
    assert "Q3" in text or "Revenue" in text
    assert confidence > 70

def test_confidence_filtering():
    """Test low confidence text is rejected."""
    blurry_image = load_test_image("blurry_slide.png")
    
    text, confidence = ocr_with_confidence(blurry_image)
    
    if confidence < 80:
        assert not should_index(text, confidence)
```

### 7.2 Integration Tests

```python
async def test_end_to_end_ocr_pipeline():
    """Test full flow: frame -> OCR -> RAG index."""
    # 1. Send test frame
    frame_data = load_test_frame_base64()
    await websocket.send(json.dumps({
        "type": "screen_frame",
        "image_data": frame_data
    }))
    
    # 2. Wait for OCR result
    response = await websocket.recv()
    result = json.loads(response)
    
    assert result["type"] == "ocr_result"
    assert result["success"]
    assert result["indexed"]
    
    # 3. Verify RAG index
    docs = rag_store.query("Q3 revenue")
    assert len(docs) > 0
```

### 7.3 Manual Tests

| Test | Steps | Expected |
|------|-------|----------|
| Slide capture | Share PowerPoint, wait 30s | OCR result appears in RAG |
| Deduplication | Keep same slide visible | Only one document indexed |
| Privacy | Disable OCR in settings | No frames captured |
| Quality | Share blurry image | Rejected (confidence <80%) |

---

## 8. Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Frame processing time | <1s | From receive to RAG index |
| OCR accuracy (slides) | >85% | Structured text |
| Duplicate detection | <5% false negative | Similar slides caught |
| Memory usage | <100MB | For OCR pipeline |
| Bandwidth per frame | <100KB | Compressed JPEG |
| CPU usage | <5% | Average during capture |

---

## 9. Error Handling

| Error | Handling | User Impact |
|-------|----------|-------------|
| Tesseract not installed | Graceful degradation, log warning | OCR unavailable notice |
| OCR timeout (>5s) | Cancel, skip frame | None (silent) |
| Low confidence (<80%) | Skip indexing | None |
| Duplicate frame | Skip processing | None |
| WebSocket disconnect | Buffer frames, retry | None |
| Memory pressure | Reduce quality, skip non-essential | Slower OCR |

---

## 10. Privacy & Security

- **Opt-in by default:** OCR disabled, user must enable
- **Text only stored:** Original images discarded after OCR
- **Session-scoped:** Screen content deleted with session
- **No cloud:** All processing local (Tesseract local)
- **Indicator:** Menu bar icon shows when capturing

---

## 11. Documentation Plan

| Document | Purpose |
|----------|---------|
| This spec | Technical implementation guide |
| `docs/OCR_USER_GUIDE.md` | End-user documentation |
| `docs/OCR_TROUBLESHOOTING.md` | Common issues and fixes |
| Code comments | Inline documentation |

---

*Specification version 1.0 - Ready for implementation*
