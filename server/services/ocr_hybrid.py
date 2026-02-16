"""
Hybrid OCR Pipeline for EchoPanel

Combines PaddleOCR (fast) + SmolVLM (smart) for optimal slide processing.

Architecture:
    Screen Frame
        │
        ├─► [Fast Path] PaddleOCR v5 ───────┐
        │        (50ms, 2MB)                │
        │        Raw text + layout detect     │
        │                                     ▼
        ├─► [Smart Path] SmolVLM-256M ────► [Fusion Engine]
        │        (200ms, <1GB)              (Smart Merge)
        │        Semantic understanding       │
        │        Contextual prompting         ▼
        │                              [RAG Index]
        │                              (Enriched content)

Modes:
- background: Default capture mode (adaptive triggering)
- query: User asked question (always use VLM)
- quality: Max quality for export (always use both)

Configuration via environment:
- ECHOPANEL_OCR_MODE: hybrid, paddle_only, vlm_only
- ECHOPANEL_OCR_VLM_TRIGGER: adaptive, always, confidence_only, never
- ECHOPANEL_OCR_CONFIDENCE_THRESHOLD: Min confidence (default: 85)
"""

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from PIL import Image

from .image_hash import ImageDeduplicator, PerceptualHash
from .image_preprocess import ImagePreprocessor
from .ocr_fusion import FusionEngine, HybridOCRResult
from .ocr_layout_classifier import LayoutType
from .ocr_paddle import PaddleOCRPipeline, PaddleOCRResult
from .ocr_smolvlm import SmolVLMPipeline

logger = logging.getLogger(__name__)

# Configuration
OCR_MODE = os.getenv("ECHOPANEL_OCR_MODE", "hybrid")  # hybrid, paddle_only, vlm_only
OCR_VLM_TRIGGER = os.getenv("ECHOPANEL_OCR_VLM_TRIGGER", "adaptive")  # adaptive, always, confidence_only, never
OCR_CONFIDENCE_THRESHOLD = float(os.getenv("ECHOPANEL_OCR_CONFIDENCE_THRESHOLD", "85"))
OCR_PERIODIC_VLM_INTERVAL = int(os.getenv("ECHOPANEL_OCR_PERIODIC_VLM_INTERVAL", "10"))
OCR_ENABLE_DEDUP = os.getenv("ECHOPANEL_OCR_ENABLE_DEDUP", "true").lower() == "true"
OCR_MAX_DIMENSION = int(os.getenv("ECHOPANEL_OCR_MAX_DIMENSION", "1280"))


class OCRMode(str, Enum):
    """OCR processing modes."""
    HYBRID = "hybrid"
    PADDLE_ONLY = "paddle_only"
    VLM_ONLY = "vlm_only"


class VLMTriggerMode(str, Enum):
    """When to trigger VLM processing."""
    ADAPTIVE = "adaptive"           # Smart triggering based on content
    ALWAYS = "always"               # Every frame
    CONFIDENCE_ONLY = "confidence"  # Only when OCR confidence low
    NEVER = "never"                 # Never use VLM


@dataclass
class ProcessingContext:
    """Context for frame processing decisions."""
    frame_number: int = 0
    session_id: str = ""
    is_new_slide: bool = False
    user_query_pending: bool = False
    previous_layout: Optional[LayoutType] = None
    last_vlm_frame: int = -100  # Force VLM on first frame


class HybridOCRPipeline:
    """
    Hybrid OCR pipeline combining PaddleOCR and SmolVLM.
    
    Features:
    - Tiered processing: Fast path + optional enrichment
    - Adaptive triggers: Run VLM only when needed
    - Contextual prompting: Use OCR to guide VLM
    - Smart fusion: Merge results intelligently
    - Resource management: Control VLM concurrency
    
    Usage:
        pipeline = HybridOCRPipeline()
        
        # Background capture (default)
        result = await pipeline.process_frame(image_bytes)
        
        # User query mode
        result = await pipeline.process_frame(image_bytes, mode="query")
        
        # Get status
        status = pipeline.get_status()
    """
    
    def __init__(
        self,
        mode: Optional[OCRMode] = None,
        vlm_trigger: Optional[VLMTriggerMode] = None,
        confidence_threshold: Optional[float] = None
    ):
        """
        Initialize hybrid OCR pipeline.
        
        Args:
            mode: Processing mode (hybrid, paddle_only, vlm_only)
            vlm_trigger: When to trigger VLM (adaptive, always, confidence_only, never)
            confidence_threshold: Min confidence for OCR acceptance
        """
        self.mode = OCRMode(mode or OCR_MODE)
        self.vlm_trigger = VLMTriggerMode(vlm_trigger or OCR_VLM_TRIGGER)
        self.confidence_threshold = confidence_threshold or OCR_CONFIDENCE_THRESHOLD
        
        # Initialize components
        self.preprocessor = ImagePreprocessor(max_dimension=OCR_MAX_DIMENSION)
        self.deduplicator = ImageDeduplicator()
        self.perceptual_hash = PerceptualHash()
        
        self.paddle = PaddleOCRPipeline()
        self.vlm = SmolVLMPipeline()
        self.fusion = FusionEngine()
        
        # Processing context
        self._context = ProcessingContext()
        self._last_hash: Optional[str] = None
        
        # Concurrency control for VLM
        self._vlm_semaphore = asyncio.Semaphore(1)  # Only 1 VLM at a time
        
        # Statistics
        self._stats = {
            "frames_processed": 0,
            "frames_duplicate": 0,
            "frames_paddle_only": 0,
            "frames_with_vlm": 0,
            "frames_failed": 0,
            "vlm_triggers": {
                "low_confidence": 0,
                "complex_layout": 0,
                "new_slide": 0,
                "key_metrics": 0,
                "periodic": 0,
                "user_query": 0,
                "forced": 0,
            },
            "total_processing_time_ms": 0,
            "total_paddle_time_ms": 0,
            "total_vlm_time_ms": 0,
        }
        
        logger.info(f"HybridOCR initialized: mode={self.mode.value}, trigger={self.vlm_trigger.value}")
    
    def is_available(self) -> bool:
        """Check if any OCR engine is available."""
        if self.mode == OCRMode.PADDLE_ONLY:
            return self.paddle.is_available()
        elif self.mode == OCRMode.VLM_ONLY:
            return self.vlm.is_available()
        else:  # hybrid
            return self.paddle.is_available() or self.vlm.is_available()
    
    async def process_frame(
        self,
        image_bytes: bytes,
        session_id: str = "",
        mode: Optional[str] = None,
        skip_duplicates: bool = True
    ) -> HybridOCRResult:
        """
        Process a screen capture frame with hybrid OCR.
        
        Args:
            image_bytes: Raw image data
            session_id: Session identifier
            mode: Override processing mode (background, query, quality)
            skip_duplicates: Skip if same as previous frame
            
        Returns:
            HybridOCRResult with enriched content
        """
        start_time = time.time()
        self._context.frame_number += 1
        self._context.session_id = session_id
        
        processing_mode = mode or "background"
        
        try:
            # Decode image
            image = Image.open(BytesIO(image_bytes))
            
            # Check for duplicates
            if skip_duplicates and OCR_ENABLE_DEDUP:
                current_hash = self.perceptual_hash.compute(image_bytes)
                if self._last_hash and self.perceptual_hash.similar(current_hash, self._last_hash):
                    self._stats["frames_duplicate"] += 1
                    return HybridOCRResult(
                        primary_text="",
                        raw_ocr_text="",
                        source="duplicate",
                        processing_time_ms=(time.time() - start_time) * 1000
                    )
                self._last_hash = current_hash
                self._context.is_new_slide = True
            else:
                self._context.is_new_slide = False
            
            # Route to appropriate processor
            if self.mode == OCRMode.PADDLE_ONLY:
                result = await self._process_paddle_only(image)
            elif self.mode == OCRMode.VLM_ONLY:
                result = await self._process_vlm_only(image)
            else:
                result = await self._process_hybrid(image, processing_mode)
            
            # Update stats
            processing_time = (time.time() - start_time) * 1000
            self._stats["frames_processed"] += 1
            self._stats["total_processing_time_ms"] += processing_time
            
            if result.source == "paddle_only":
                self._stats["frames_paddle_only"] += 1
                self._stats["total_paddle_time_ms"] += result.paddle_time_ms
            elif result.source in ["fused", "vlm_only"]:
                self._stats["frames_with_vlm"] += 1
                self._stats["total_paddle_time_ms"] += result.paddle_time_ms
                self._stats["total_vlm_time_ms"] += result.vlm_time_ms
            
            return result
            
        except Exception as e:
            logger.error(f"Hybrid OCR processing error: {e}")
            self._stats["frames_failed"] += 1
            return HybridOCRResult(
                primary_text="",
                raw_ocr_text="",
                error=str(e),
                processing_time_ms=(time.time() - start_time) * 1000
            )
    
    async def _process_paddle_only(self, image: Image.Image) -> HybridOCRResult:
        """Process with PaddleOCR only."""
        paddle_result = await self.paddle.process(image, detect_layout=True)
        return self.fusion.fuse(paddle_result, None)
    
    async def _process_vlm_only(self, image: Image.Image) -> HybridOCRResult:
        """Process with SmolVLM only."""
        vlm_result = await self.vlm.process(image)
        return self.fusion.fuse(None, vlm_result)
    
    async def _process_hybrid(
        self,
        image: Image.Image,
        mode: str
    ) -> HybridOCRResult:
        """
        Process with hybrid pipeline.
        
        Strategy:
        1. Always run PaddleOCR (fast)
        2. Decide if VLM needed (adaptive trigger)
        3. Run VLM with OCR context if needed
        4. Fuse results
        """
        # Step 1: Fast PaddleOCR
        paddle_result = await self.paddle.process(image, detect_layout=True)
        
        if not paddle_result.success:
            # PaddleOCR failed, try VLM fallback
            logger.warning("PaddleOCR failed, falling back to VLM")
            async with self._vlm_semaphore:
                vlm_result = await self.vlm.process(image)
            return self.fusion.fuse(None, vlm_result)
        
        # Step 2: Decide if we need VLM
        should_run_vlm, trigger_reason = self._should_run_vlm(paddle_result, mode)
        
        if not should_run_vlm or self.vlm_trigger == VLMTriggerMode.NEVER:
            # PaddleOCR only
            return self.fusion.fuse(paddle_result, None)
        
        # Step 3: Run VLM with OCR context
        logger.debug(f"Running VLM enrichment (trigger: {trigger_reason})")
        
        async with self._vlm_semaphore:
            vlm_result = await self.vlm.process(image, paddle_context=paddle_result)
        
        # Step 4: Fuse results
        force_vlm_text = (mode == "query")  # Use VLM text for user queries
        hybrid_result = self.fusion.fuse(paddle_result, vlm_result, force_vlm_text)
        
        return hybrid_result
    
    def _should_run_vlm(
        self,
        paddle_result: PaddleOCRResult,
        mode: str
    ) -> tuple[bool, str]:
        """
        Decide if VLM enrichment is needed.
        
        Returns: (should_run, reason)
        """
        # Mode-based overrides
        if mode == "query":
            self._stats["vlm_triggers"]["user_query"] += 1
            return True, "user_query"
        
        if mode == "quality":
            self._stats["vlm_triggers"]["forced"] += 1
            return True, "quality_mode"
        
        # Trigger mode checks
        if self.vlm_trigger == VLMTriggerMode.ALWAYS:
            self._stats["vlm_triggers"]["forced"] += 1
            return True, "always"
        
        if self.vlm_trigger == VLMTriggerMode.NEVER:
            return False, "never"
        
        # Confidence-based trigger
        if paddle_result.confidence < self.confidence_threshold:
            self._stats["vlm_triggers"]["low_confidence"] += 1
            return True, f"low_confidence ({paddle_result.confidence:.1f})"
        
        # Adaptive triggers (only if mode is adaptive)
        if self.vlm_trigger == VLMTriggerMode.ADAPTIVE:
            # Complex layout
            if paddle_result.is_complex_layout:
                self._stats["vlm_triggers"]["complex_layout"] += 1
                return True, f"complex_layout ({paddle_result.detected_layout.value})"
            
            # New slide detection
            if self._context.is_new_slide:
                self._stats["vlm_triggers"]["new_slide"] += 1
                return True, "new_slide"
            
            # Key metrics detected
            if paddle_result.contains_metrics():
                self._stats["vlm_triggers"]["key_metrics"] += 1
                return True, "key_metrics"
            
            # Periodic refresh
            frames_since_vlm = self._context.frame_number - self._context.last_vlm_frame
            if frames_since_vlm >= OCR_PERIODIC_VLM_INTERVAL:
                self._context.last_vlm_frame = self._context.frame_number
                self._stats["vlm_triggers"]["periodic"] += 1
                return True, "periodic_refresh"
        
        return False, "none"
    
    async def answer_query(
        self,
        image_bytes: bytes,
        query: str,
        session_id: str = ""
    ) -> str:
        """
        Answer a specific question about a slide.
        
        Args:
            image_bytes: Slide image
            query: User question
            session_id: Session identifier
            
        Returns:
            Answer string
        """
        try:
            image = Image.open(BytesIO(image_bytes))
            
            # Get OCR context first
            paddle_result = await self.paddle.process(image, detect_layout=False)
            
            # Query with context
            async with self._vlm_semaphore:
                answer = await self.vlm.answer_query(
                    image,
                    query,
                    paddle_context=paddle_result if paddle_result.success else None
                )
            
            return answer
            
        except Exception as e:
            logger.error(f"Query answering error: {e}")
            return f"Error processing query: {e}"
    
    def get_status(self) -> dict:
        """Get pipeline status and statistics."""
        return {
            "available": self.is_available(),
            "mode": self.mode.value,
            "vlm_trigger": self.vlm_trigger.value,
            "confidence_threshold": self.confidence_threshold,
            "engines": {
                "paddleocr": {
                    "available": self.paddle.is_available(),
                    "stats": self.paddle.get_stats()
                },
                "smolvlm": {
                    "available": self.vlm.is_available(),
                    "stats": self.vlm.get_stats()
                }
            },
            "fusion_stats": self.fusion.get_stats(),
            "pipeline_stats": self._get_pipeline_stats()
        }
    
    def _get_pipeline_stats(self) -> dict:
        """Calculate derived pipeline statistics."""
        stats = self._stats.copy()
        
        if stats["frames_processed"] > 0:
            stats["avg_processing_time_ms"] = (
                stats["total_processing_time_ms"] / stats["frames_processed"]
            )
            stats["vlm_usage_rate"] = (
                stats["frames_with_vlm"] / stats["frames_processed"]
            )
        else:
            stats["avg_processing_time_ms"] = 0
            stats["vlm_usage_rate"] = 0
        
        # Estimate effective latency
        paddle_avg = (stats["total_paddle_time_ms"] / max(stats["frames_processed"], 1))
        vlm_avg = (stats["total_vlm_time_ms"] / max(stats["frames_with_vlm"], 1))
        vlm_rate = stats["vlm_usage_rate"]
        
        stats["estimated_avg_latency_ms"] = paddle_avg + (vlm_avg * vlm_rate)
        
        return stats
    
    def reset_stats(self):
        """Reset all statistics."""
        self._stats = {
            "frames_processed": 0,
            "frames_duplicate": 0,
            "frames_paddle_only": 0,
            "frames_with_vlm": 0,
            "frames_failed": 0,
            "vlm_triggers": {
                "low_confidence": 0,
                "complex_layout": 0,
                "new_slide": 0,
                "key_metrics": 0,
                "periodic": 0,
                "user_query": 0,
                "forced": 0,
            },
            "total_processing_time_ms": 0,
            "total_paddle_time_ms": 0,
            "total_vlm_time_ms": 0,
        }
        self.paddle.reset_stats()
        self.vlm.reset_stats()
        self.fusion.reset_stats()


# Backward compatibility imports
from io import BytesIO  # noqa: F401, E402
