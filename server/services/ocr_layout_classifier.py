"""
Layout Classifier for OCR Pipeline

Lightweight CNN-based classifier to detect slide content type.
Used by hybrid OCR to decide when to run VLM enrichment.

Layout types:
- text: Text-heavy slides (bullet points, paragraphs)
- table: Tables with structured data
- chart: Charts and graphs (bar, line, pie)
- diagram: Diagrams, flowcharts, architecture
- mixed: Combination of above
"""

import logging
import os
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)


class LayoutType(str, Enum):
    """Types of slide layouts."""
    TEXT = "text"
    TABLE = "table"
    CHART = "chart"
    DIAGRAM = "diagram"
    MIXED = "mixed"
    UNKNOWN = "unknown"


@dataclass
class LayoutResult:
    """Result from layout classification."""
    layout_type: LayoutType
    confidence: float
    processing_time_ms: float
    
    def is_complex(self) -> bool:
        """Check if layout needs VLM enrichment."""
        return self.layout_type in [LayoutType.TABLE, LayoutType.CHART, LayoutType.DIAGRAM]


class LayoutClassifier:
    """
    Lightweight layout classifier for slide content.
    
    Uses heuristics + simple CV analysis (no heavy ML model).
    Fast (<10ms) and sufficient for trigger decisions.
    
    Future: Could use MobileNet CNN (~5MB) for better accuracy.
    """
    
    def __init__(self):
        self.stats = {
            "frames_processed": 0,
            "total_time_ms": 0,
        }
    
    def classify(self, image: Image.Image) -> LayoutResult:
        """
        Classify slide layout type.
        
        Args:
            image: PIL Image
            
        Returns:
            LayoutResult with type and confidence
        """
        import time
        start = time.time()
        
        try:
            # Convert to numpy for analysis
            img_array = np.array(image)
            
            # Run heuristics
            features = self._extract_features(img_array)
            layout_type, confidence = self._classify_from_features(features)
            
            processing_time = (time.time() - start) * 1000
            
            self.stats["frames_processed"] += 1
            self.stats["total_time_ms"] += processing_time
            
            return LayoutResult(
                layout_type=layout_type,
                confidence=confidence,
                processing_time_ms=processing_time
            )
            
        except Exception as e:
            logger.warning(f"Layout classification failed: {e}")
            return LayoutResult(
                layout_type=LayoutType.UNKNOWN,
                confidence=0.0,
                processing_time_ms=(time.time() - start) * 1000
            )
    
    def _extract_features(self, img_array: np.ndarray) -> dict:
        """
        Extract visual features for classification.
        
        Features:
        - Line density (tables have many horizontal/vertical lines)
        - Color variance (charts have distinct colors)
        - Text density (text slides have uniform texture)
        - Shape complexity (diagrams have complex shapes)
        """
        from scipy import ndimage
        from skimage import feature, measure
        
        # Convert to grayscale if needed
        if len(img_array.shape) == 3:
            gray = np.mean(img_array, axis=2).astype(np.uint8)
        else:
            gray = img_array
        
        # Resize for faster processing
        h, w = gray.shape
        if max(h, w) > 512:
            scale = 512 / max(h, w)
            new_h, new_w = int(h * scale), int(w * scale)
            gray = ndimage.zoom(gray, (new_h/h, new_w/w), order=1)
        
        features = {}
        
        # 1. Edge density (Canny)
        edges = feature.canny(gray / 255.0, sigma=1.0)
        features["edge_density"] = np.sum(edges) / edges.size
        
        # 2. Line detection (Hough transform simplified)
        # Count strong horizontal and vertical lines
        h_lines, v_lines = self._detect_lines(gray)
        features["horizontal_lines"] = h_lines
        features["vertical_lines"] = v_lines
        features["line_ratio"] = (h_lines + v_lines) / max(h_lines, v_lines, 1)
        
        # 3. Color analysis (if color image)
        if len(img_array.shape) == 3:
            # Count distinct colors
            reshaped = img_array.reshape(-1, 3)
            unique_colors = len(np.unique(reshaped, axis=0))
            features["color_diversity"] = unique_colors / reshaped.shape[0]
            
            # Saturation variance (charts often have saturated colors)
            hsv = self._rgb_to_hsv(img_array)
            features["saturation_std"] = np.std(hsv[:, :, 1])
        else:
            features["color_diversity"] = 0
            features["saturation_std"] = 0
        
        # 4. Texture analysis (text has regular patterns)
        features["texture_regularity"] = self._analyze_texture(gray)
        
        # 5. Aspect ratio zones
        features["has_header"] = self._detect_header_zone(gray)
        features["has_footer"] = self._detect_footer_zone(gray)
        
        return features
    
    def _detect_lines(self, gray: np.ndarray) -> Tuple[int, int]:
        """Detect horizontal and vertical lines."""
        from scipy import ndimage
        
        # Horizontal lines - look for rows with high variance
        row_diff = np.abs(np.diff(gray.astype(float), axis=1))
        h_edges = np.mean(row_diff, axis=1)
        h_lines = np.sum(h_edges > np.percentile(h_edges, 95))
        
        # Vertical lines
        col_diff = np.abs(np.diff(gray.astype(float), axis=0))
        v_edges = np.mean(col_diff, axis=0)
        v_lines = np.sum(v_edges > np.percentile(v_edges, 95))
        
        return int(h_lines), int(v_lines)
    
    def _rgb_to_hsv(self, rgb: np.ndarray) -> np.ndarray:
        """Convert RGB to HSV color space."""
        rgb_norm = rgb / 255.0
        maxc = np.max(rgb_norm, axis=2)
        minc = np.min(rgb_norm, axis=2)
        delta = maxc - minc
        
        # Hue
        h = np.zeros_like(maxc)
        mask = delta != 0
        
        r, g, b = rgb_norm[:, :, 0], rgb_norm[:, :, 1], rgb_norm[:, :, 2]
        h[mask & (maxc == r)] = ((g - b) / delta)[mask & (maxc == r)] % 6
        h[mask & (maxc == g)] = ((b - r) / delta + 2)[mask & (maxc == g)]
        h[mask & (maxc == b)] = ((r - g) / delta + 4)[mask & (maxc == b)]
        h = h / 6.0
        
        # Saturation
        s = np.zeros_like(maxc)
        s[maxc != 0] = delta[maxc != 0] / maxc[maxc != 0]
        
        # Value
        v = maxc
        
        return np.stack([h, s, v], axis=2)
    
    def _analyze_texture(self, gray: np.ndarray) -> float:
        """Analyze texture regularity (text has regular patterns)."""
        from scipy import ndimage
        
        # Local binary pattern approximation
        kernel = np.array([[-1, -1, -1],
                          [-1,  8, -1],
                          [-1, -1, -1]])
        laplacian = ndimage.convolve(gray.astype(float), kernel)
        
        # Measure uniformity
        hist, _ = np.histogram(laplacian, bins=50)
        # Uniform texture has peaked histogram
        uniformity = np.max(hist) / np.sum(hist)
        return uniformity
    
    def _detect_header_zone(self, gray: np.ndarray) -> bool:
        """Detect if there's a distinct header zone (title area)."""
        h, w = gray.shape
        top_zone = gray[:int(h*0.2), :]
        rest = gray[int(h*0.2):, :]
        
        # Header typically has higher contrast
        top_contrast = np.std(top_zone)
        rest_contrast = np.std(rest)
        return top_contrast > rest_contrast * 1.5
    
    def _detect_footer_zone(self, gray: np.ndarray) -> bool:
        """Detect if there's a distinct footer zone."""
        h, w = gray.shape
        bottom_zone = gray[int(h*0.8):, :]
        rest = gray[:int(h*0.8), :]
        
        bottom_contrast = np.std(bottom_zone)
        rest_contrast = np.std(rest)
        return bottom_contrast > rest_contrast * 1.2
    
    def _classify_from_features(self, features: dict) -> Tuple[LayoutType, float]:
        """
        Classify layout from extracted features.
        
        Heuristics:
        - Many lines + regular pattern → TABLE
        - High color diversity + no regular text pattern → CHART
        - Complex shapes + low text regularity → DIAGRAM
        - Regular texture + text-like pattern → TEXT
        - Mixed signals → MIXED
        """
        h_lines = features["horizontal_lines"]
        v_lines = features["vertical_lines"]
        edge_density = features["edge_density"]
        color_div = features["color_diversity"]
        texture_reg = features["texture_regularity"]
        sat_std = features["saturation_std"]
        
        scores = {}
        
        # TABLE: Many horizontal and vertical lines
        if h_lines > 5 and v_lines > 3:
            scores[LayoutType.TABLE] = 0.8 + min(0.15, (h_lines + v_lines) / 50)
        elif h_lines > 10 or v_lines > 8:
            scores[LayoutType.TABLE] = 0.7
        else:
            scores[LayoutType.TABLE] = 0.2
        
        # CHART: High color diversity, distinct regions
        if color_div > 0.1 and sat_std > 0.3:
            scores[LayoutType.CHART] = 0.75 + min(0.2, color_div)
        elif sat_std > 0.2:
            scores[LayoutType.CHART] = 0.6
        else:
            scores[LayoutType.CHART] = 0.15
        
        # DIAGRAM: Complex edges, not table-like
        if edge_density > 0.05 and scores[LayoutType.TABLE] < 0.5:
            scores[LayoutType.DIAGRAM] = 0.7 + min(0.2, edge_density * 5)
        else:
            scores[LayoutType.DIAGRAM] = 0.2
        
        # TEXT: Regular texture, low color diversity
        if texture_reg > 0.15 and color_div < 0.05:
            scores[LayoutType.TEXT] = 0.8 + min(0.15, texture_reg)
        elif texture_reg > 0.1:
            scores[LayoutType.TEXT] = 0.65
        else:
            scores[LayoutType.TEXT] = 0.3
        
        # MIXED: Multiple high scores or no clear winner
        high_scores = [s for s in scores.values() if s > 0.6]
        if len(high_scores) >= 2:
            scores[LayoutType.MIXED] = 0.75
        else:
            scores[LayoutType.MIXED] = 0.3
        
        # Select winner
        best_type = max(scores, key=scores.get)
        best_score = scores[best_type]
        
        return best_type, best_score
    
    def get_stats(self) -> dict:
        """Get classifier statistics."""
        stats = self.stats.copy()
        if stats["frames_processed"] > 0:
            stats["avg_time_ms"] = stats["total_time_ms"] / stats["frames_processed"]
        else:
            stats["avg_time_ms"] = 0
        return stats
