"""
Hybrid OCR Pipeline for EchoPanel

Combines PaddleOCR (fast) + SmolVLM (smart) for optimal slide processing.
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
from .ocr_paddle import PaddleOCRPipeline
from .ocr_smolvlm import SmolVLMPipeline

logger = logging.getLogger(__name__)

OCR_MODE = os.getenv("ECHOPANEL_OCR_MODE", "hybrid")
OCR_VLM_TRIGGER = os.getenv("ECHOPANEL_OCR_VLM_TRIGGER", "adaptive")
OCR_CONFIDENCE_THRESHOLD = float(os.getenv("ECHOPANEL_OCR_CONFIDENCE_THRESHOLD", "85"))
OCR_PERIODIC_VLM_INTERVAL = int(os.getenv("ECHOPANEL_OCR_PERIODIC_VLM_INTERVAL", "10"))
OCR_ENABLE_DEDUP = os.getenv("ECHOPANEL_OCR_ENABLE_DEDUP", "true").lower() == "true"
OCR_MAX_DIMENSION = int(os.getenv("ECHOPANEL_OCR_MAX_DIMENSION", "1280"))


class OCRMode(str, Enum):
    HYBRID = "hybrid"
    PADDLE_ONLY = "paddle_only"
    VLM_ONLY = "vlm_only"


class VLMTriggerMode(str, Enum):
    ADAPTIVE = "adaptive"
    ALWAYS = "always"
    CONFIDENCE_ONLY = "confidence"
    NEVER = "never"


@dataclass
class ProcessingContext:
    frame_number: int = 0
    session_id: str = ""
    is_new_slide: bool = False
    user_query_pending: bool = False
    previous_layout: Optional[LayoutType] = None
    last_vlm_frame: int = -100


class HybridOCRPipeline:
    """Hybrid OCR pipeline combining PaddleOCR and SmolVLM."""
    
    def __init__(self, mode=None, vlm_trigger=None, confidence_threshold=None):
        self.mode = OCRMode(mode or OCR_MODE)
        self.vlm_trigger = VLMTriggerMode(vlm_trigger or OCR_VLM_TRIGGER)
        self.confidence_threshold = confidence_threshold or OCR_CONFIDENCE_THRESHOLD
        
        self.preprocessor = ImagePreprocessor(max_dimension=OCR_MAX_DIMENSION)
        self.deduplicator = ImageDeduplicator()
        self.perceptual_hash = PerceptualHash()
        
        self.paddle = PaddleOCRPipeline()
        self.vlm = SmolVLMPipeline()
        self.fusion = FusionEngine()
        
        self._context = ProcessingContext()
        self._last_hash = None
        self._vlm_semaphore = asyncio.Semaphore(1)
        
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
        
        logger.info(f"HybridOCR: mode={self.mode.value}, trigger={self.vlm_trigger.value}")
    
    def is_available(self) -> bool:
        if self.mode == OCRMode.PADDLE_ONLY:
            return self.paddle.is_available()
        elif self.mode == OCRMode.VLM_ONLY:
            return self.vlm.is_available()
        else:
            return self.paddle.is_available() or self.vlm.is_available()
    
    async def process_frame(self, image_bytes: bytes, session_id: str = "", mode: Optional[str] = None, skip_duplicates: bool = True) -> HybridOCRResult:
        start_time = time.time()
        self._context.frame_number += 1
        self._context.session_id = session_id
        
        processing_mode = mode or "background"
        
        try:
            image = Image.open(__import__('io').BytesIO(image_bytes))
            
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
            
            if self.mode == OCRMode.PADDLE_ONLY:
                result = await self._process_paddle_only(image)
            elif self.mode == OCRMode.VLM_ONLY:
                result = await self._process_vlm_only(image)
            else:
                result = await self._process_hybrid(image, processing_mode)
            
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
            logger.error(f"Hybrid OCR error: {e}")
            self._stats["frames_failed"] += 1
            return HybridOCRResult(
                primary_text="",
                raw_ocr_text="",
                error=str(e),
                processing_time_ms=(time.time() - start_time) * 1000
            )
    
    async def _process_paddle_only(self, image: Image.Image) -> HybridOCRResult:
        paddle_result = await self.paddle.process(image, detect_layout=True)
        return self.fusion.fuse(paddle_result, None)
    
    async def _process_vlm_only(self, image: Image.Image) -> HybridOCRResult:
        vlm_result = await self.vlm.process(image)
        return self.fusion.fuse(None, vlm_result)
    
    async def _process_hybrid(self, image: Image.Image, mode: str) -> HybridOCRResult:
        paddle_result = await self.paddle.process(image, detect_layout=True)
        
        if not paddle_result.success:
            logger.warning("PaddleOCR failed, falling back to VLM")
            async with self._vlm_semaphore:
                vlm_result = await self.vlm.process(image)
            return self.fusion.fuse(None, vlm_result)
        
        should_run_vlm, trigger_reason = self._should_run_vlm(paddle_result, mode)
        
        if not should_run_vlm or self.vlm_trigger == VLMTriggerMode.NEVER:
            return self.fusion.fuse(paddle_result, None)
        
        logger.debug(f"Running VLM enrichment (trigger: {trigger_reason})")
        
        async with self._vlm_semaphore:
            vlm_result = await self.vlm.process(image, paddle_context=paddle_result)
        
        force_vlm_text = (mode == "query")
        return self.fusion.fuse(paddle_result, vlm_result, force_vlm_text)
    
    def _should_run_vlm(self, paddle_result, mode: str):
        if mode == "query":
            self._stats["vlm_triggers"]["user_query"] += 1
            return True, "user_query"
        
        if mode == "quality":
            self._stats["vlm_triggers"]["forced"] += 1
            return True, "quality_mode"
        
        if self.vlm_trigger == VLMTriggerMode.ALWAYS:
            self._stats["vlm_triggers"]["forced"] += 1
            return True, "always"
        
        if self.vlm_trigger == VLMTriggerMode.NEVER:
            return False, "never"
        
        if paddle_result.confidence < self.confidence_threshold:
            self._stats["vlm_triggers"]["low_confidence"] += 1
            return True, f"low_confidence ({paddle_result.confidence:.1f})"
        
        if self.vlm_trigger == VLMTriggerMode.ADAPTIVE:
            if paddle_result.is_complex_layout:
                self._stats["vlm_triggers"]["complex_layout"] += 1
                return True, f"complex_layout ({paddle_result.detected_layout.value})"
            
            if self._context.is_new_slide:
                self._stats["vlm_triggers"]["new_slide"] += 1
                return True, "new_slide"
            
            if paddle_result.contains_metrics():
                self._stats["vlm_triggers"]["key_metrics"] += 1
                return True, "key_metrics"
            
            frames_since_vlm = self._context.frame_number - self._context.last_vlm_frame
            if frames_since_vlm >= OCR_PERIODIC_VLM_INTERVAL:
                self._context.last_vlm_frame = self._context.frame_number
                self._stats["vlm_triggers"]["periodic"] += 1
                return True, "periodic_refresh"
        
        return False, "none"
    
    async def answer_query(self, image_bytes: bytes, query: str, session_id: str = "") -> str:
        try:
            image = Image.open(__import__('io').BytesIO(image_bytes))
            paddle_result = await self.paddle.process(image, detect_layout=False)
            
            async with self._vlm_semaphore:
                answer = await self.vlm.answer_query(
                    image, query,
                    paddle_context=paddle_result if paddle_result.success else None
                )
            return answer
        except Exception as e:
            logger.error(f"Query error: {e}")
            return f"Error: {e}"
    
    def get_status(self) -> dict:
        return {
            "available": self.is_available(),
            "mode": self.mode.value,
            "vlm_trigger": self.vlm_trigger.value,
            "confidence_threshold": self.confidence_threshold,
            "engines": {
                "paddleocr": {"available": self.paddle.is_available(), "stats": self.paddle.get_stats()},
                "smolvlm": {"available": self.vlm.is_available(), "stats": self.vlm.get_stats()},
            },
            "fusion_stats": self.fusion.get_stats(),
            "pipeline_stats": self._get_pipeline_stats()
        }
    
    def _get_pipeline_stats(self) -> dict:
        stats = self._stats.copy()
        if stats["frames_processed"] > 0:
            stats["avg_processing_time_ms"] = stats["total_processing_time_ms"] / stats["frames_processed"]
            stats["vlm_usage_rate"] = stats["frames_with_vlm"] / stats["frames_processed"]
        else:
            stats["avg_processing_time_ms"] = 0
            stats["vlm_usage_rate"] = 0
        
        paddle_avg = stats["total_paddle_time_ms"] / max(stats["frames_processed"], 1)
        vlm_avg = stats["total_vlm_time_ms"] / max(stats["frames_with_vlm"], 1)
        vlm_rate = stats["vlm_usage_rate"]
        
        stats["estimated_avg_latency_ms"] = paddle_avg + (vlm_avg * vlm_rate)
        return stats
    
    def reset_stats(self):
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
