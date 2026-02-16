"""
Fusion Engine for Hybrid OCR

Intelligently merges results from PaddleOCR (fast) and SmolVLM (smart).

Strategies:
1. Text correction: Use SmolVLM to fix PaddleOCR errors
2. Confidence weighting: Combine confidence scores
3. Semantic enrichment: Add VLM insights to OCR text
4. Cross-validation: Detect disagreements
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
    """
    Enriched result from hybrid OCR pipeline.
    
    Combines the best of both engines:
    - Fast, accurate text from PaddleOCR
    - Semantic understanding from SmolVLM
    """
    # Core text
    primary_text: str                           # Best text (corrected)
    raw_ocr_text: str                           # Original PaddleOCR output
    semantic_summary: Optional[str] = None      # SmolVLM summary
    
    # Metadata
    confidence: float = 0.0
    ocr_confidence: float = 0.0
    vlm_confidence: float = 0.0
    
    # Source tracking
    source: str = "unknown"                     # paddle_only, vlm_only, fused
    engines_used: List[str] = field(default_factory=list)
    
    # Layout
    layout_type: LayoutType = LayoutType.UNKNOWN
    layout_confidence: float = 0.0
    
    # Enrichment
    key_insights: List[str] = field(default_factory=list)
    entities: List[Entity] = field(default_factory=list)
    
    # Processing
    processing_time_ms: float = 0.0
    paddle_time_ms: float = 0.0
    vlm_time_ms: float = 0.0
    
    # Status
    error: Optional[str] = None
    
    @property
    def success(self) -> bool:
        """Check if processing succeeded."""
        return self.error is None and len(self.primary_text) > 0
    
    @property
    def word_count(self) -> int:
        """Count words in primary text."""
        return len(self.primary_text.split()) if self.primary_text else 0
    
    @property
    def is_enriched(self) -> bool:
        """Check if result has VLM enrichment."""
        return "smolvlm" in self.engines_used
    
    def to_searchable_text(self) -> str:
        """
        Combine all text for RAG indexing.
        
        Includes: raw text + summary + insights + entities
        """
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
        """Convert to dictionary for serialization."""
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
            "entities": [
                {"text": e.text, "type": e.type, "confidence": e.confidence}
                for e in self.entities
            ],
            "processing_time_ms": self.processing_time_ms,
            "word_count": self.word_count,
            "is_enriched": self.is_enriched,
        }


class FusionEngine:
    """
    Fuses PaddleOCR and SmolVLM results.
    
    Key capabilities:
    1. Smart text selection/correction
    2. Confidence fusion
    3. Semantic enrichment integration
    4. Quality validation
    """
    
    def __init__(
        self,
        text_similarity_threshold: float = 0.6,
        confidence_boost_for_correction: float = 0.1
    ):
        """
        Initialize fusion engine.
        
        Args:
            text_similarity_threshold: Min similarity to consider texts related
            confidence_boost_for_correction: Boost when VLM corrects OCR
        """
        self.text_similarity_threshold = text_similarity_threshold
        self.confidence_boost = confidence_boost_for_correction
        
        # Statistics
        self._stats = {
            "frames_fused": 0,
            "frames_paddle_only": 0,
            "frames_vlm_only": 0,
            "corrections_applied": 0,
            "disagreements": 0,
        }
    
    def fuse(
        self,
        paddle_result: Optional[PaddleOCRResult],
        vlm_result: Optional[SmolVLMResult],
        force_vlm_text: bool = False
    ) -> HybridOCRResult:
        """
        Fuse results from both engines.
        
        Args:
            paddle_result: PaddleOCR result (may be None)
            vlm_result: SmolVLM result (may be None)
            force_vlm_text: Always use VLM text even if different
            
        Returns:
            HybridOCRResult with merged information
        """
        # Handle None cases
        if paddle_result is None and vlm_result is None:
            return HybridOCRResult(
                primary_text="",
                raw_ocr_text="",
                error="Both engines failed"
            )
        
        if paddle_result is None:
            # VLM only
            self._stats["frames_vlm_only"] += 1
            return self._vlm_only_result(vlm_result)
        
        if vlm_result is None:
            # PaddleOCR only
            self._stats["frames_paddle_only"] += 1
            return self._paddle_only_result(paddle_result)
        
        # Both available - full fusion
        self._stats["frames_fused"] += 1
        return self._full_fusion(paddle_result, vlm_result, force_vlm_text)
    
    def _paddle_only_result(
        self,
        paddle: PaddleOCRResult
    ) -> HybridOCRResult:
        """Create result from PaddleOCR only."""
        return HybridOCRResult(
            primary_text=paddle.text,
            raw_ocr_text=paddle.text,
            confidence=paddle.confidence,
            ocr_confidence=paddle.confidence,
            vlm_confidence=0.0,
            source="paddle_only",
            engines_used=["paddleocr"],
            layout_type=paddle.detected_layout,
            layout_confidence=paddle.layout_confidence,
            processing_time_ms=paddle.processing_time_ms,
            paddle_time_ms=paddle.processing_time_ms,
            error=paddle.error
        )
    
    def _vlm_only_result(
        self,
        vlm: SmolVLMResult
    ) -> HybridOCRResult:
        """Create result from SmolVLM only."""
        return HybridOCRResult(
            primary_text=vlm.text,
            raw_ocr_text="",
            semantic_summary=vlm.semantic_summary,
            confidence=vlm.confidence,
            ocr_confidence=0.0,
            vlm_confidence=vlm.confidence,
            source="vlm_only",
            engines_used=["smolvlm"],
            key_insights=vlm.key_insights,
            entities=vlm.entities,
            processing_time_ms=vlm.processing_time_ms,
            vlm_time_ms=vlm.processing_time_ms,
            error=vlm.error
        )
    
    def _full_fusion(
        self,
        paddle: PaddleOCRResult,
        vlm: SmolVLMResult,
        force_vlm_text: bool
    ) -> HybridOCRResult:
        """
        Full fusion of both results.
        
        Strategy:
        1. Select best text (OCR vs VLM-corrected)
        2. Combine confidences
        3. Integrate VLM enrichment
        """
        # Select primary text
        primary_text, text_source = self._select_best_text(
            paddle.text,
            vlm.text,
            paddle.confidence,
            vlm.confidence,
            force_vlm_text
        )
        
        if text_source == "vlm_corrected":
            self._stats["corrections_applied"] += 1
        
        # Calculate combined confidence
        combined_confidence = self._calculate_combined_confidence(
            paddle.confidence,
            vlm.confidence,
            text_source
        )
        
        # Total processing time
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
            layout_type=paddle.detected_layout,
            layout_confidence=paddle.layout_confidence,
            key_insights=vlm.key_insights,
            entities=vlm.entities,
            processing_time_ms=total_time,
            paddle_time_ms=paddle.processing_time_ms,
            vlm_time_ms=vlm.processing_time_ms
        )
    
    def _select_best_text(
        self,
        ocr_text: str,
        vlm_text: str,
        ocr_conf: float,
        vlm_conf: float,
        force_vlm: bool
    ) -> tuple[str, str]:
        """
        Select best text between OCR and VLM.
        
        Returns: (selected_text, source)
        source is one of: "ocr", "vlm_corrected", "vlm_fallback"
        """
        # If forced, use VLM
        if force_vlm:
            return vlm_text, "vlm_corrected"
        
        # If OCR failed or is empty, use VLM
        if not ocr_text or ocr_conf < 30:
            return vlm_text, "vlm_fallback"
        
        # Calculate similarity
        similarity = difflib.SequenceMatcher(
            None,
            ocr_text.lower(),
            vlm_text.lower()
        ).ratio()
        
        # If very similar, use VLM (assumed corrected)
        if similarity > 0.8:
            return vlm_text, "vlm_corrected"
        
        # If somewhat similar, decide based on confidence
        if similarity > self.text_similarity_threshold:
            if vlm_conf > ocr_conf:
                return vlm_text, "vlm_corrected"
            else:
                return ocr_text, "ocr"
        
        # Texts are quite different - possible VLM hallucination or OCR miss
        self._stats["disagreements"] += 1
        
        # Prefer OCR for raw text extraction unless VLM is much more confident
        if vlm_conf > ocr_conf + 20:  # VLM significantly more confident
            return vlm_text, "vlm_corrected"
        else:
            # Use OCR but log disagreement
            logger.debug(f"Text disagreement (sim={similarity:.2f}): OCR={ocr_text[:50]}... VLM={vlm_text[:50]}...")
            return ocr_text, "ocr"
    
    def _calculate_combined_confidence(
        self,
        ocr_conf: float,
        vlm_conf: float,
        text_source: str
    ) -> float:
        """
        Calculate combined confidence score.
        
        Strategy:
        - Boost when both engines agree
        - Use VLM confidence for semantic elements
        """
        base_conf = max(ocr_conf, vlm_conf)
        
        # Boost if VLM corrected (indicates it understood context)
        if text_source == "vlm_corrected":
            base_conf = min(95, base_conf + self.confidence_boost * 100)
        
        return base_conf
    
    def validate_fusion(
        self,
        result: HybridOCRResult
    ) -> tuple[bool, Optional[str]]:
        """
        Validate fused result for quality.
        
        Returns: (is_valid, warning_message)
        """
        warnings = []
        
        # Check for empty text
        if not result.primary_text:
            return False, "Empty text output"
        
        # Check confidence
        if result.confidence < 50:
            warnings.append(f"Low confidence ({result.confidence:.1f}%)")
        
        # Check for word count mismatch (possible truncation)
        if result.raw_ocr_text:
            ocr_words = len(result.raw_ocr_text.split())
            primary_words = len(result.primary_text.split())
            
            if primary_words < ocr_words * 0.5:
                warnings.append(f"Possible truncation: {ocr_words} -> {primary_words} words")
        
        # Check for VLM hallucination indicators
        if result.is_enriched:
            hallucination_indicators = [
                "i cannot see",
                "no image",
                "not visible",
                "unclear"
            ]
            text_lower = result.primary_text.lower()
            if any(ind in text_lower for ind in hallucination_indicators):
                warnings.append("Possible VLM hallucination detected")
        
        if warnings:
            return True, "; ".join(warnings)
        
        return True, None
    
    def get_stats(self) -> dict:
        """Get fusion statistics."""
        return self._stats.copy()
    
    def reset_stats(self):
        """Reset statistics."""
        self._stats = {
            "frames_fused": 0,
            "frames_paddle_only": 0,
            "frames_vlm_only": 0,
            "corrections_applied": 0,
            "disagreements": 0,
        }
