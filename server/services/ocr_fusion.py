"""
Fusion Engine for Hybrid OCR

Intelligently merges results from PaddleOCR (fast) and SmolVLM (smart).
"""

import difflib
import logging
from dataclasses import dataclass, field
from typing import List, Optional

from .ocr_layout_classifier import LayoutType
from .ocr_paddle import PaddleOCRResult
from .ocr_smolvlm import Entity, SmolVLMResult

logger = logging.getLogger(__name__)


@dataclass
class HybridOCRResult:
    """Enriched result from hybrid OCR pipeline."""
    primary_text: str = ""
    raw_ocr_text: str = ""
    semantic_summary: Optional[str] = None
    confidence: float = 0.0
    ocr_confidence: float = 0.0
    vlm_confidence: float = 0.0
    source: str = "unknown"
    engines_used: List[str] = field(default_factory=list)
    layout_type: LayoutType = LayoutType.UNKNOWN
    layout_confidence: float = 0.0
    key_insights: List[str] = field(default_factory=list)
    entities: List[Entity] = field(default_factory=list)
    processing_time_ms: float = 0.0
    paddle_time_ms: float = 0.0
    vlm_time_ms: float = 0.0
    error: Optional[str] = None
    
    @property
    def success(self) -> bool:
        return self.error is None and len(self.primary_text) > 0
    
    @property
    def word_count(self) -> int:
        return len(self.primary_text.split()) if self.primary_text else 0
    
    @property
    def is_enriched(self) -> bool:
        return "smolvlm" in self.engines_used
    
    def to_searchable_text(self) -> str:
        parts = [self.primary_text]
        if self.semantic_summary:
            parts.append(f"Summary: {self.semantic_summary}")
        if self.key_insights:
            parts.append("Key points: " + "; ".join(self.key_insights))
        if self.entities:
            entity_str = ", ".join([f"{e.text} ({e.type})" for e in self.entities])
            parts.append(f"Mentions: {entity_str}")
        return "\n".join(parts)
    
    def to_dict(self) -> dict:
        return {
            "primary_text": self.primary_text,
            "raw_ocr_text": self.raw_ocr_text,
            "semantic_summary": self.semantic_summary,
            "confidence": self.confidence,
            "ocr_confidence": self.ocr_confidence,
            "vlm_confidence": self.vlm_confidence,
            "source": self.source,
            "engines_used": self.engines_used,
            "layout_type": self.layout_type.value,
            "layout_confidence": self.layout_confidence,
            "key_insights": self.key_insights,
            "entities": [{"text": e.text, "type": e.type, "confidence": e.confidence} for e in self.entities],
            "processing_time_ms": self.processing_time_ms,
            "word_count": self.word_count,
            "is_enriched": self.is_enriched,
        }


class FusionEngine:
    """Fuses PaddleOCR and SmolVLM results."""
    
    def __init__(self, text_similarity_threshold=0.6, confidence_boost=0.1):
        self.text_similarity_threshold = text_similarity_threshold
        self.confidence_boost = confidence_boost
        self._stats = {
            "frames_fused": 0,
            "frames_paddle_only": 0,
            "frames_vlm_only": 0,
            "corrections_applied": 0,
            "disagreements": 0,
        }
    
    def fuse(self, paddle_result=None, vlm_result=None, force_vlm_text=False):
        if paddle_result is None and vlm_result is None:
            return HybridOCRResult(error="Both engines failed")
        
        if paddle_result is None:
            self._stats["frames_vlm_only"] += 1
            return self._vlm_only_result(vlm_result)
        
        if vlm_result is None:
            self._stats["frames_paddle_only"] += 1
            return self._paddle_only_result(paddle_result)
        
        self._stats["frames_fused"] += 1
        return self._full_fusion(paddle_result, vlm_result, force_vlm_text)
    
    def _paddle_only_result(self, paddle):
        return HybridOCRResult(
            primary_text=paddle.text,
            raw_ocr_text=paddle.text,
            confidence=paddle.confidence,
            ocr_confidence=paddle.confidence,
            source="paddle_only",
            engines_used=["paddleocr"],
            layout_type=getattr(paddle, 'detected_layout', LayoutType.UNKNOWN),
            layout_confidence=getattr(paddle, 'layout_confidence', 0.0),
            processing_time_ms=paddle.processing_time_ms,
            paddle_time_ms=paddle.processing_time_ms,
            error=paddle.error
        )
    
    def _vlm_only_result(self, vlm):
        return HybridOCRResult(
            primary_text=vlm.text,
            raw_ocr_text="",
            semantic_summary=vlm.semantic_summary,
            confidence=vlm.confidence,
            vlm_confidence=vlm.confidence,
            source="vlm_only",
            engines_used=["smolvlm"],
            key_insights=vlm.key_insights,
            entities=vlm.entities,
            processing_time_ms=vlm.processing_time_ms,
            vlm_time_ms=vlm.processing_time_ms,
            error=vlm.error
        )
    
    def _full_fusion(self, paddle, vlm, force_vlm_text):
        primary_text, text_source = self._select_best_text(
            paddle.text, vlm.text, paddle.confidence, vlm.confidence, force_vlm_text
        )
        
        if text_source == "vlm_corrected":
            self._stats["corrections_applied"] += 1
        
        combined_confidence = self._calculate_combined_confidence(
            paddle.confidence, vlm.confidence, text_source
        )
        
        total_time = paddle.processing_time_ms + vlm.processing_time_ms
        
        return HybridOCRResult(
            primary_text=primary_text,
            raw_ocr_text=paddle.text,
            semantic_summary=vlm.semantic_summary,
            confidence=combined_confidence,
            ocr_confidence=paddle.confidence,
            vlm_confidence=vlm.confidence,
            source="fused",
            engines_used=["paddleocr", "smolvlm"],
            layout_type=getattr(paddle, 'detected_layout', LayoutType.UNKNOWN),
            layout_confidence=getattr(paddle, 'layout_confidence', 0.0),
            key_insights=vlm.key_insights,
            entities=vlm.entities,
            processing_time_ms=total_time,
            paddle_time_ms=paddle.processing_time_ms,
            vlm_time_ms=vlm.processing_time_ms
        )
    
    def _select_best_text(self, ocr_text, vlm_text, ocr_conf, vlm_conf, force_vlm):
        if force_vlm:
            return vlm_text, "vlm_corrected"
        
        if not ocr_text or ocr_conf < 30:
            return vlm_text, "vlm_fallback"
        
        similarity = difflib.SequenceMatcher(None, ocr_text.lower(), vlm_text.lower()).ratio()
        
        if similarity > 0.8:
            return vlm_text, "vlm_corrected"
        
        if similarity > self.text_similarity_threshold:
            if vlm_conf > ocr_conf:
                return vlm_text, "vlm_corrected"
            else:
                return ocr_text, "ocr"
        
        self._stats["disagreements"] += 1
        if vlm_conf > ocr_conf + 20:
            return vlm_text, "vlm_corrected"
        else:
            return ocr_text, "ocr"
    
    def _calculate_combined_confidence(self, ocr_conf, vlm_conf, text_source):
        base_conf = max(ocr_conf, vlm_conf)
        if text_source == "vlm_corrected":
            base_conf = min(95, base_conf + self.confidence_boost * 100)
        return base_conf
    
    def get_stats(self):
        return self._stats.copy()
    
    def reset_stats(self):
        self._stats = {
            "frames_fused": 0,
            "frames_paddle_only": 0,
            "frames_vlm_only": 0,
            "corrections_applied": 0,
            "disagreements": 0,
        }
