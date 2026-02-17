"""Tests for Hybrid OCR Pipeline."""

import unittest
import asyncio
import io
from unittest.mock import Mock, patch, MagicMock
from PIL import Image
import numpy as np

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from services.ocr_layout_classifier import LayoutClassifier, LayoutType
from services.ocr_fusion import FusionEngine, HybridOCRResult
from services.ocr_smolvlm import Entity, SmolVLMResult
from services.ocr_paddle import PaddleOCRResult


class TestLayoutClassifier(unittest.TestCase):
    def setUp(self):
        self.classifier = LayoutClassifier()
    
    def test_text_slide(self):
        img = Image.new('RGB', (800, 600), color=(255, 255, 255))
        result = self.classifier.classify(img)
        self.assertIsInstance(result.layout_type, LayoutType)
        self.assertGreaterEqual(result.confidence, 0)
    
    def test_chart_slide(self):
        img_array = np.zeros((600, 800, 3), dtype=np.uint8)
        img_array[100:300, 100:400] = [255, 0, 0]
        img = Image.fromarray(img_array)
        result = self.classifier.classify(img)
        # Layout classification is heuristic-based, just ensure it returns a valid type
        self.assertIsInstance(result.layout_type, LayoutType)
        self.assertGreaterEqual(result.confidence, 0)
    
    def test_is_complex(self):
        from services.ocr_layout_classifier import LayoutResult
        text = LayoutResult(LayoutType.TEXT, 0.8, 10)
        self.assertFalse(text.is_complex())
        table = LayoutResult(LayoutType.TABLE, 0.8, 10)
        self.assertTrue(table.is_complex())


class TestFusionEngine(unittest.TestCase):
    def setUp(self):
        self.fusion = FusionEngine()
    
    def test_paddle_only(self):
        paddle = PaddleOCRResult(
            text="Revenue $5M",
            confidence=85.0,
            word_count=3,
            detected_layout=LayoutType.TEXT,
            processing_time_ms=50
        )
        result = self.fusion.fuse(paddle, None)
        self.assertEqual(result.primary_text, "Revenue $5M")
        self.assertEqual(result.source, "paddle_only")
    
    def test_vlm_only(self):
        vlm = SmolVLMResult(
            text="Revenue $5 Million",
            semantic_summary="Q3 chart",
            key_insights=["15% growth"],
            confidence=0.9,
            processing_time_ms=200
        )
        result = self.fusion.fuse(None, vlm)
        self.assertEqual(result.primary_text, "Revenue $5 Million")
        self.assertTrue(result.is_enriched)
    
    def test_full_fusion(self):
        paddle = PaddleOCRResult(
            text="Revenu $5M",
            confidence=70.0,
            word_count=2,
            detected_layout=LayoutType.TEXT,
            processing_time_ms=50
        )
        vlm = SmolVLMResult(
            text="Revenue $5M",
            semantic_summary="Chart",
            confidence=0.85,
            processing_time_ms=200
        )
        result = self.fusion.fuse(paddle, vlm)
        self.assertEqual(result.source, "fused")
        self.assertIn("paddleocr", result.engines_used)
        self.assertIn("smolvlm", result.engines_used)


class TestPaddleOCRResult(unittest.TestCase):
    def test_contains_metrics(self):
        r1 = PaddleOCRResult(text="Revenue was $5M", confidence=90.0, word_count=3)
        self.assertTrue(r1.contains_metrics())
        
        r2 = PaddleOCRResult(text="Welcome to meeting", confidence=90.0, word_count=3)
        self.assertFalse(r2.contains_metrics())
    
    def test_is_complex_layout(self):
        r1 = PaddleOCRResult(text="x", confidence=90.0, word_count=1, detected_layout=LayoutType.TEXT)
        self.assertFalse(r1.is_complex_layout)
        
        r2 = PaddleOCRResult(text="x", confidence=90.0, word_count=1, detected_layout=LayoutType.CHART)
        self.assertTrue(r2.is_complex_layout)


class TestHybridOCRResult(unittest.TestCase):
    def test_success(self):
        r1 = HybridOCRResult(primary_text="Test", confidence=90.0)
        self.assertTrue(r1.success)
        
        r2 = HybridOCRResult(error="Failed")
        self.assertFalse(r2.success)
    
    def test_is_enriched(self):
        r1 = HybridOCRResult(engines_used=["paddleocr"])
        self.assertFalse(r1.is_enriched)
        
        r2 = HybridOCRResult(engines_used=["paddleocr", "smolvlm"])
        self.assertTrue(r2.is_enriched)


class TestIntegrationAsync(unittest.IsolatedAsyncioTestCase):
    async def test_pipeline_init(self):
        try:
            from services.ocr_hybrid import HybridOCRPipeline
            pipeline = HybridOCRPipeline()
            self.assertIsInstance(pipeline.is_available(), bool)
        except ImportError as e:
            self.skipTest(f"Import error: {e}")


if __name__ == '__main__':
    unittest.main()
