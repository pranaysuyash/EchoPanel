"""
Screen OCR Pipeline for EchoPanel

Extracts text from screen capture frames during meetings.
Integrates with RAG for automatic indexing of visual content.

Now with Hybrid OCR: PaddleOCR v5 (fast) + SmolVLM (smart)

Key features:
- Hybrid processing: Fast OCR + optional VLM enrichment
- Perceptual hash deduplication (skip duplicate slides)
- Image preprocessing for OCR accuracy
- Adaptive VLM triggering (only when needed)
- Contextual prompting (OCR guides VLM)
- Smart fusion of results
- Async processing
- Auto-indexing to RAG
"""

import asyncio
import base64
import logging
import os
import time
from dataclasses import dataclass
from typing import Optional

from .image_hash import ImageDeduplicator, PerceptualHash
from .image_preprocess import ImagePreprocessor

logger = logging.getLogger(__name__)

# Configuration from environment
OCR_ENABLED = os.getenv("ECHOPANEL_OCR_ENABLED", "false").lower() == "true"
OCR_MODE = os.getenv("ECHOPANEL_OCR_MODE", "hybrid")  # hybrid, paddle_only, vlm_only, tesseract
OCR_CONFIDENCE_THRESHOLD = float(os.getenv("ECHOPANEL_OCR_CONFIDENCE_THRESHOLD", "85"))
OCR_DEDUP_THRESHOLD = int(os.getenv("ECHOPANEL_OCR_DEDUP_THRESHOLD", "5"))
OCR_MAX_DIMENSION = int(os.getenv("ECHOPANEL_OCR_MAX_DIMENSION", "1280"))

# Legacy Tesseract support (for backward compatibility)
try:
    import pytesseract
    from PIL import Image
    TESSERACT_AVAILABLE = True
except ImportError:
    TESSERACT_AVAILABLE = False
    pytesseract = None
    Image = None


@dataclass
class OCResult:
    """
    Result from OCR processing.
    
    This is the legacy result format for backward compatibility.
    New code should use HybridOCRResult from ocr_fusion.
    """
    text: str
    confidence: float
    word_count: int
    processing_time_ms: float
    is_duplicate: bool = False
    error: Optional[str] = None
    
    # New hybrid fields (optional)
    semantic_summary: Optional[str] = None
    is_enriched: bool = False
    layout_type: str = "unknown"
    
    @property
    def success(self) -> bool:
        """Check if OCR was successful."""
        return self.error is None and len(self.text) > 0
    
    @property
    def should_index(self) -> bool:
        """Check if result should be indexed to RAG."""
        if not self.success or self.is_duplicate:
            return False
        return self.confidence >= OCR_CONFIDENCE_THRESHOLD and self.word_count >= 3


class ScreenOCRPipeline:
    """
    Main OCR pipeline - now uses Hybrid OCR internally.
    
    This class maintains backward compatibility while using the new
    hybrid architecture (PaddleOCR + SmolVLM).
    
    For new code, prefer using HybridOCRPipeline directly from ocr_hybrid.
    
    Usage:
        pipeline = ScreenOCRPipeline()
        if pipeline.is_available():
            result = await pipeline.process_frame(image_bytes)
            if result.should_index:
                # Index to RAG
                pass
    """
    
    def __init__(
        self,
        confidence_threshold: Optional[float] = None,
        dedup_threshold: Optional[int] = None,
        max_dimension: Optional[int] = None,
        lang: Optional[str] = None
    ):
        """
        Initialize OCR pipeline.
        
        Args:
            confidence_threshold: Min confidence % (default from env)
            dedup_threshold: Hash threshold for dedup (default from env)
            max_dimension: Max image dimension (default from env)
            lang: Language code (legacy, not used with PaddleOCR)
        """
        self.confidence_threshold = confidence_threshold or OCR_CONFIDENCE_THRESHOLD
        self.dedup_threshold = dedup_threshold or OCR_DEDUP_THRESHOLD
        self.max_dimension = max_dimension or OCR_MAX_DIMENSION
        
        # Initialize new hybrid pipeline
        self._hybrid = None
        self._mode = OCR_MODE
        
        if OCR_MODE in ["hybrid", "paddle_only", "vlm_only"]:
            try:
                from .ocr_hybrid import HybridOCRPipeline, OCRMode
                self._hybrid = HybridOCRPipeline(
                    mode=OCRMode(OCR_MODE),
                    confidence_threshold=self.confidence_threshold
                )
                logger.info(f"Using Hybrid OCR pipeline (mode={OCR_MODE})")
            except Exception as e:
                logger.warning(f"Failed to initialize Hybrid OCR: {e}. Falling back to Tesseract.")
                self._hybrid = None
                self._mode = "tesseract"
        
        # Legacy Tesseract components (fallback only)
        if self._hybrid is None:
            self.preprocessor = ImagePreprocessor(max_dimension=self.max_dimension)
            self.deduplicator = ImageDeduplicator(threshold=self.dedup_threshold)
            self.hasher = PerceptualHash()
        
        # Statistics
        self._stats = {
            "frames_processed": 0,
            "frames_duplicate": 0,
            "frames_low_confidence": 0,
            "frames_indexed": 0,
            "total_processing_time_ms": 0,
        }
    
    def is_available(self) -> bool:
        """Check if OCR is available."""
        if self._hybrid:
            return self._hybrid.is_available()
        return TESSERACT_AVAILABLE
    
    async def process_frame(
        self,
        image_bytes: bytes,
        skip_duplicates: bool = True
    ) -> OCResult:
        """
        Process a screen capture frame.
        
        Uses hybrid pipeline if available, falls back to Tesseract.
        
        Args:
            image_bytes: Raw image data (JPEG, PNG, etc.)
            skip_duplicates: Whether to skip duplicate frames
            
        Returns:
            OCResult with extracted text and metadata
        """
        # Use hybrid pipeline if available
        if self._hybrid:
            return await self._process_hybrid(image_bytes, skip_duplicates)
        else:
            return await self._process_tesseract(image_bytes, skip_duplicates)
    
    async def _process_hybrid(
        self,
        image_bytes: bytes,
        skip_duplicates: bool
    ) -> OCResult:
        """Process using hybrid pipeline."""
        start_time = time.time()
        
        try:
            # Use hybrid pipeline
            hybrid_result = await self._hybrid.process_frame(
                image_bytes,
                skip_duplicates=skip_duplicates
            )
            
            # Convert to legacy OCResult format
            result = OCResult(
                text=hybrid_result.primary_text,
                confidence=hybrid_result.confidence,
                word_count=hybrid_result.word_count,
                processing_time_ms=hybrid_result.processing_time_ms,
                is_duplicate=(hybrid_result.source == "duplicate"),
                error=hybrid_result.error,
                semantic_summary=hybrid_result.semantic_summary,
                is_enriched=hybrid_result.is_enriched,
                layout_type=hybrid_result.layout_type.value
            )
            
            # Update stats
            self._stats["frames_processed"] += 1
            self._stats["total_processing_time_ms"] += result.processing_time_ms
            
            if result.is_duplicate:
                self._stats["frames_duplicate"] += 1
            elif result.confidence < self.confidence_threshold:
                self._stats["frames_low_confidence"] += 1
            else:
                self._stats["frames_indexed"] += 1
            
            return result
            
        except Exception as e:
            logger.error(f"Hybrid OCR error: {e}")
            return OCResult(
                text="",
                confidence=0.0,
                word_count=0,
                processing_time_ms=(time.time() - start_time) * 1000,
                error=str(e)
            )
    
    async def _process_tesseract(
        self,
        image_bytes: bytes,
        skip_duplicates: bool
    ) -> OCResult:
        """Legacy Tesseract processing (fallback)."""
        start_time = time.time()
        
        if not TESSERACT_AVAILABLE:
            return OCResult(
                text="",
                confidence=0.0,
                word_count=0,
                processing_time_ms=0.0,
                error="OCR not available"
            )
        
        try:
            # Check for duplicates
            if skip_duplicates:
                is_dup = self.deduplicator.is_duplicate(image_bytes)
                if is_dup:
                    self._stats["frames_duplicate"] += 1
                    return OCResult(
                        text="",
                        confidence=0.0,
                        word_count=0,
                        processing_time_ms=(time.time() - start_time) * 1000,
                        is_duplicate=True
                    )
            
            # Preprocess image
            preprocessed = await asyncio.to_thread(
                self.preprocessor.preprocess_from_bytes,
                image_bytes
            )
            
            if preprocessed is None:
                return OCResult(
                    text="",
                    confidence=0.0,
                    word_count=0,
                    processing_time_ms=(time.time() - start_time) * 1000,
                    error="Image preprocessing failed"
                )
            
            # Run OCR
            text, confidence = await asyncio.to_thread(
                self._ocr_with_confidence,
                preprocessed
            )
            
            word_count = len(text.split()) if text else 0
            processing_time = (time.time() - start_time) * 1000
            
            # Update stats
            self._stats["frames_processed"] += 1
            self._stats["total_processing_time_ms"] += processing_time
            
            if confidence < self.confidence_threshold:
                self._stats["frames_low_confidence"] += 1
            else:
                self._stats["frames_indexed"] += 1
            
            return OCResult(
                text=text,
                confidence=confidence,
                word_count=word_count,
                processing_time_ms=processing_time
            )
            
        except Exception as e:
            logger.error(f"Tesseract OCR error: {e}")
            return OCResult(
                text="",
                confidence=0.0,
                word_count=0,
                processing_time_ms=(time.time() - start_time) * 1000,
                error=str(e)
            )
    
    def _ocr_with_confidence(self, image: Image.Image) -> tuple[str, float]:
        """Legacy Tesseract OCR with confidence."""
        data = pytesseract.image_to_data(
            image,
            output_type=pytesseract.Output.DICT
        )
        
        words = []
        confidences = []
        
        for i, conf in enumerate(data['conf']):
            conf_int = int(conf)
            if conf_int > 0:
                word = data['text'][i].strip()
                if word:
                    words.append(word)
                    confidences.append(conf_int)
        
        text = ' '.join(words)
        avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0
        
        return text, avg_confidence
    
    def get_stats(self) -> dict:
        """Get OCR processing statistics."""
        stats = self._stats.copy()
        if stats["frames_processed"] > 0:
            stats["avg_processing_time_ms"] = (
                stats["total_processing_time_ms"] / stats["frames_processed"]
            )
        else:
            stats["avg_processing_time_ms"] = 0
        
        # Add hybrid stats if available
        if self._hybrid:
            stats["hybrid"] = self._hybrid.get_status()
        
        return stats
    
    def reset_stats(self):
        """Reset statistics."""
        self._stats = {
            "frames_processed": 0,
            "frames_duplicate": 0,
            "frames_low_confidence": 0,
            "frames_indexed": 0,
            "total_processing_time_ms": 0,
        }
        if self._hybrid:
            self._hybrid.reset_stats()
    
    def clear_deduplication_cache(self):
        """Clear deduplication history."""
        if self._hybrid:
            self._hybrid.deduplicator.clear()
        else:
            self.deduplicator.clear()


class OCRFrameHandler:
    """
    Handles OCR frame processing and RAG integration.
    
    This is the high-level interface used by the WebSocket handler.
    Now uses hybrid OCR for enriched slide understanding.
    """
    
    def __init__(self):
        self.pipeline = ScreenOCRPipeline()
        self._enabled = OCR_ENABLED and self.pipeline.is_available()
        
        # Try to get hybrid pipeline for enriched indexing
        self._hybrid = None
        if hasattr(self.pipeline, '_hybrid') and self.pipeline._hybrid:
            self._hybrid = self.pipeline._hybrid
    
    @property
    def enabled(self) -> bool:
        """Check if OCR is enabled and available."""
        return self._enabled
    
    async def handle_frame(
        self,
        image_base64: str,
        session_id: str,
        timestamp: float,
        index_to_rag: bool = True
    ) -> OCResult:
        """
        Handle an incoming screen frame.
        
        Args:
            image_base64: Base64-encoded image
            session_id: Session identifier
            timestamp: Frame timestamp
            index_to_rag: Whether to auto-index to RAG
            
        Returns:
            OCResult
        """
        if not self.enabled:
            return OCResult(
                text="",
                confidence=0.0,
                word_count=0,
                processing_time_ms=0.0,
                error="OCR disabled or not available"
            )
        
        # Decode image
        try:
            image_bytes = base64.b64decode(image_base64)
        except Exception as e:
            logger.error(f"Failed to decode base64 image: {e}")
            return OCResult(
                text="",
                confidence=0.0,
                word_count=0,
                processing_time_ms=0.0,
                error=f"Image decode failed: {e}"
            )
        
        # Process frame
        result = await self.pipeline.process_frame(image_bytes)
        
        # Index to RAG if appropriate
        if index_to_rag and result.should_index:
            await self._index_to_rag_enhanced(result, session_id, timestamp)
        
        return result
    
    async def _index_to_rag_enhanced(
        self,
        result: OCResult,
        session_id: str,
        timestamp: float
    ):
        """Index OCR result to RAG with enrichment."""
        try:
            from .rag_store import get_rag_store
            
            rag = get_rag_store()
            
            # Build enriched document text
            doc_title = f"Screen capture {time.strftime('%H:%M:%S', time.localtime(timestamp))}"
            
            # Use semantic summary if available (hybrid mode)
            if result.is_enriched and result.semantic_summary:
                doc_text = f"""{result.text}

Context: {result.semantic_summary}
Layout: {result.layout_type}"""
            else:
                doc_text = result.text
            
            # Index with metadata
            rag.index_document(
                title=doc_title,
                text=doc_text,
                source="screen",
                document_id=f"screen_{session_id}_{int(timestamp)}",
                generate_embeddings=True
            )
            
            logger.debug(f"Indexed screen content to RAG: {result.word_count} words (enriched={result.is_enriched})")
            
        except Exception as e:
            logger.error(f"Failed to index to RAG: {e}")
    
    async def query_slide(
        self,
        image_base64: str,
        query: str,
        session_id: str
    ) -> str:
        """
        Answer a question about a specific slide.
        
        Args:
            image_base64: Base64-encoded slide image
            query: User question
            session_id: Session identifier
            
        Returns:
            Answer string
        """
        if not self._hybrid:
            return "Slide querying requires hybrid OCR mode"
        
        try:
            image_bytes = base64.b64decode(image_base64)
            answer = await self._hybrid.answer_query(image_bytes, query, session_id)
            return answer
        except Exception as e:
            logger.error(f"Slide query error: {e}")
            return f"Error: {e}"
    
    def get_status(self) -> dict:
        """Get OCR handler status."""
        return {
            "enabled": self.enabled,
            "available": self.pipeline.is_available(),
            "mode": OCR_MODE,
            "tesseract_available": TESSERACT_AVAILABLE,
            "config": {
                "confidence_threshold": OCR_CONFIDENCE_THRESHOLD,
                "dedup_threshold": OCR_DEDUP_THRESHOLD,
                "max_dimension": OCR_MAX_DIMENSION,
            },
            "stats": self.pipeline.get_stats(),
        }


# Singleton instance
_ocr_handler: Optional[OCRFrameHandler] = None


def get_ocr_handler() -> OCRFrameHandler:
    """Get or create OCR frame handler singleton."""
    global _ocr_handler
    if _ocr_handler is None:
        _ocr_handler = OCRFrameHandler()
    return _ocr_handler


def reset_ocr_handler():
    """Reset OCR handler (for testing)."""
    global _ocr_handler
    _ocr_handler = None


# New exports for hybrid pipeline
__all__ = [
    'OCResult',
    'ScreenOCRPipeline',
    'OCRFrameHandler',
    'get_ocr_handler',
    'reset_ocr_handler',
]
