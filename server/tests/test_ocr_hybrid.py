"""
Comprehensive tests for Hybrid OCR Pipeline.

Tests cover:
- Layout classification
- PaddleOCR integration
- SmolVLM integration
- Fusion engine
- Hybrid orchestrator
- Adaptive triggers
- End-to-end processing
"""

import asyncio
import base64
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

import numpy as np
from PIL import Image

# Add server to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from services.ocr_fusion import FusionEngine, HybridOCRResult
from services.ocr_layout_classifier import LayoutClassifier, LayoutType
from services.ocr_paddle import PaddleOCRResult
from services.ocr_smolvlm import Entity, SmolVLMResult


class TestLayoutClassifier(unittest.TestCase):
    """Tests for layout classification."""
    
    def setUp(self):
        self.classifier = LayoutClassifier()
    
    def test_text_slide_classification(self):
        """Test classification of text-heavy slide."""
        # Create a simulated text slide (uniform texture)
        img = Image.new('RGB', (800, 600), color=(255, 255, 255))
        result = self.classifier.classify(img)
        
        self.assertIsInstance(result.layout_type, LayoutType)
        self.assertGreaterEqual(result.confidence, 0)
        self.assertLessEqual(result.confidence, 1)
        self.assertGreater(result.processing_time_ms, 0)
    
    def test_chart_slide_classification(self):
        """Test classification of chart slide (colorful regions)."""
        # Create image with distinct color regions (simulated chart)
        img_array = np.zeros((600, 800, 3), dtype=np.uint8)
        # Add colored regions
        img_array[100:300, 100:400] = [255, 0, 0]  # Red region
        img_array[350:500, 500:700] = [0, 255, 0]  # Green region
        img_array[50:150, 600:750] = [0, 0, 255]   # Blue region
        
        img = Image.fromarray(img_array)
        result = self.classifier.classify(img)
        
        # Should detect as chart or mixed due to color diversity
        self.assertIn(result.layout_type, 
                     [LayoutType.CHART, LayoutType.MIXED, LayoutType.UNKNOWN])
    
    def test_layout_is_complex(self):
        """Test is_complex method."""
        text_layout = LayoutType.TEXT
        table_layout = LayoutType.TABLE
        
        from services.ocr_layout_classifier import LayoutResult
        
        text_result = LayoutResult(
            layout_type=text_layout,
            confidence=0.8,
            processing_time_ms=10
        )
        self.assertFalse(text_result.is_complex())
        
        table_result = LayoutResult(
            layout_type=table_layout,
            confidence=0.8,
            processing_time_ms=10
        )
        self.assertTrue(table_result.is_complex())
    
    def test_classifier_stats(self):
        """Test statistics tracking."""
        img = Image.new('RGB', (400, 300), color=(128, 128, 128))
        
        # Process multiple frames
        for _ in range(5):
            self.classifier.classify(img)
        
        stats = self.classifier.get_stats()
        self.assertEqual(stats["frames_processed"], 5)
        self.assertGreater(stats["total_time_ms"], 0)


class TestFusionEngine(unittest.TestCase):
    """Tests for fusion engine."""
    
    def setUp(self):
        self.fusion = FusionEngine()
    
    def test_paddle_only_fusion(self):
        """Test fusion with PaddleOCR only."""
        paddle = PaddleOCRResult(
            text="Revenue $5M",
            confidence=85.0,
            word_count=3,
            detected_layout=LayoutType.TEXT,
            layout_confidence=0.8,
            processing_time_ms=50
        )
        
        result = self.fusion.fuse(paddle, None)
        
        self.assertEqual(result.primary_text, "Revenue $5M")
        self.assertEqual(result.source, "paddle_only")
        self.assertEqual(result.engines_used, ["paddleocr"])
        self.assertFalse(result.is_enriched)
    
    def test_vlm_only_fusion(self):
        """Test fusion with SmolVLM only."""
        vlm = SmolVLMResult(
            text="Revenue $5 Million",
            semantic_summary="Q3 revenue chart",
            key_insights=["15% growth", "Record quarter"],
            entities=[Entity("Q3", "date", 0.9)],
            confidence=0.9,
            processing_time_ms=200
        )
        
        result = self.fusion.fuse(None, vlm)
        
        self.assertEqual(result.primary_text, "Revenue $5 Million")
        self.assertEqual(result.source, "vlm_only")
        self.assertEqual(result.engines_used, ["smolvlm"])
        self.assertTrue(result.is_enriched)
        self.assertEqual(len(result.key_insights), 2)
    
    def test_full_fusion_vlm_correction(self):
        """Test fusion where VLM corrects OCR errors."""
        paddle = PaddleOCRResult(
            text="Revenu $5M, Grwoth 15%",  # Typos!
            confidence=70.0,
            word_count=4,
            detected_layout=LayoutType.TEXT,
            layout_confidence=0.7,
            processing_time_ms=50
        )
        
        vlm = SmolVLMResult(
            text="Revenue $5M, Growth 15%",  # Corrected
            semantic_summary="Revenue growth chart",
            key_insights=["$5M revenue", "15% growth"],
            entities=[],
            confidence=0.85,
            processing_time_ms=200
        )
        
        result = self.fusion.fuse(paddle, vlm)
        
        # Should use VLM-corrected text (high similarity)
        self.assertEqual(result.primary_text, "Revenue $5M, Growth 15%")
        self.assertEqual(result.source, "fused")
        self.assertEqual(result.engines_used, ["paddleocr", "smolvlm"])
        self.assertIn("smolvlm", result.engines_used)
    
    def test_fusion_disagreement_handling(self):
        """Test fusion when OCR and VLM disagree significantly."""
        paddle = PaddleOCRResult(
            text="The quick brown fox",
            confidence=90.0,
            word_count=4,
            detected_layout=LayoutType.TEXT,
            processing_time_ms=50
        )
        
        vlm = SmolVLMResult(
            text="Completely different content here",  # Very different
            semantic_summary="Different summary",
            confidence=0.8,
            processing_time_ms=200
        )
        
        result = self.fusion.fuse(paddle, vlm)
        
        # With high OCR confidence and low similarity, should prefer OCR
        self.assertEqual(result.source, "fused")
        stats = self.fusion.get_stats()
        self.assertEqual(stats["disagreements"], 1)
    
    def test_fusion_to_searchable_text(self):
        """Test conversion to searchable text."""
        result = HybridOCRResult(
            primary_text="Revenue $5M",
            raw_ocr_text="Revenu $5M",
            semantic_summary="Q3 results",
            key_insights=["15% growth"],
            entities=[Entity("Q3", "date", 0.9)],
            confidence=90.0
        )
        
        searchable = result.to_searchable_text()
        
        self.assertIn("Revenue $5M", searchable)
        self.assertIn("Q3 results", searchable)
        self.assertIn("15% growth", searchable)
        self.assertIn("Q3 (date)", searchable)
    
    def test_fusion_stats(self):
        """Test fusion statistics tracking."""
        paddle = PaddleOCRResult(
            text="Test",
            confidence=80.0,
            word_count=1,
            processing_time_ms=50
        )
        
        vlm = SmolVLMResult(
            text="Test corrected",
            semantic_summary="Summary",
            confidence=0.9,
            processing_time_ms=200
        )
        
        # Various fusions
        self.fusion.fuse(paddle, None)  # Paddle only
        self.fusion.fuse(None, vlm)      # VLM only
        self.fusion.fuse(paddle, vlm)    # Fused
        
        stats = self.fusion.get_stats()
        self.assertEqual(stats["frames_paddle_only"], 1)
        self.assertEqual(stats["frames_vlm_only"], 1)
        self.assertEqual(stats["frames_fused"], 1)


class TestPaddleOCRResult(unittest.TestCase):
    """Tests for PaddleOCR result utilities."""
    
    def test_contains_metrics(self):
        """Test detection of financial metrics."""
        # With dollar amount
        result = PaddleOCRResult(
            text="Revenue was $5,000,000 this quarter",
            confidence=90.0,
            word_count=5
        )
        self.assertTrue(result.contains_metrics())
        
        # With percentage
        result2 = PaddleOCRResult(
            text="Growth of 15% year over year",
            confidence=90.0,
            word_count=5
        )
        self.assertTrue(result2.contains_metrics())
        
        # With quarter
        result3 = PaddleOCRResult(
            text="Q3 2024 results are in",
            confidence=90.0,
            word_count=5
        )
        self.assertTrue(result3.contains_metrics())
        
        # Without metrics
        result4 = PaddleOCRResult(
            text="Welcome to the meeting today",
            confidence=90.0,
            word_count=5
        )
        self.assertFalse(result4.contains_metrics())
    
    def test_is_complex_layout(self):
        """Test layout complexity check."""
        # Text layout - not complex
        text_result = PaddleOCRResult(
            text="Some text",
            confidence=90.0,
            word_count=2,
            detected_layout=LayoutType.TEXT
        )
        self.assertFalse(text_result.is_complex_layout)
        
        # Chart layout - complex
        chart_result = PaddleOCRResult(
            text="Chart data",
            confidence=90.0,
            word_count=2,
            detected_layout=LayoutType.CHART
        )
        self.assertTrue(chart_result.is_complex_layout)


class TestHybridOCRResult(unittest.TestCase):
    """Tests for hybrid result."""
    
    def test_success_property(self):
        """Test success check."""
        # Success
        result = HybridOCRResult(
            primary_text="Extracted text",
            raw_ocr_text="Raw text",
            confidence=90.0
        )
        self.assertTrue(result.success)
        
        # Error
        result2 = HybridOCRResult(
            primary_text="",
            raw_ocr_text="",
            error="Processing failed"
        )
        self.assertFalse(result2.success)
        
        # Empty text
        result3 = HybridOCRResult(
            primary_text="",
            raw_ocr_text="",
            confidence=0.0
        )
        self.assertFalse(result3.success)
    
    def test_is_enriched_property(self):
        """Test enrichment check."""
        # Not enriched
        result = HybridOCRResult(
            primary_text="Text",
            raw_ocr_text="Text",
            engines_used=["paddleocr"]
        )
        self.assertFalse(result.is_enriched)
        
        # Enriched
        result2 = HybridOCRResult(
            primary_text="Text",
            raw_ocr_text="Text",
            engines_used=["paddleocr", "smolvlm"]
        )
        self.assertTrue(result2.is_enriched)
    
    def test_to_dict(self):
        """Test dictionary conversion."""
        result = HybridOCRResult(
            primary_text="Test",
            raw_ocr_text="Test raw",
            semantic_summary="Summary",
            confidence=85.0,
            key_insights=["Insight 1"],
            entities=[Entity("Name", "person", 0.9)]
        )
        
        d = result.to_dict()
        
        self.assertEqual(d["primary_text"], "Test")
        self.assertEqual(d["confidence"], 85.0)
        self.assertEqual(len(d["key_insights"]), 1)
        self.assertEqual(len(d["entities"]), 1)


class TestIntegrationAsync(unittest.IsolatedAsyncioTestCase):
    """Async integration tests."""
    
    async def test_pipeline_initialization(self):
        """Test that pipeline initializes correctly."""
        # Skip if dependencies not available
        try:
            from services.ocr_hybrid import HybridOCRPipeline
        except ImportError:
            self.skipTest("Hybrid OCR dependencies not available")
        
        pipeline = HybridOCRPipeline()
        
        # Should report availability
        self.assertIsInstance(pipeline.is_available(), bool)
        
        # Should have components
        self.assertIsNotNone(pipeline.paddle)
        self.assertIsNotNone(pipeline.vlm)
        self.assertIsNotNone(pipeline.fusion)
    
    async def test_simple_image_processing(self):
        """Test processing a simple test image."""
        try:
            from services.ocr_hybrid import HybridOCRPipeline
        except ImportError:
            self.skipTest("Hybrid OCR dependencies not available")
        
        # Create a simple test image with text
        img = Image.new('RGB', (400, 200), color=(255, 255, 255))
        
        # Convert to bytes
        buffer = io.BytesIO()
        img.save(buffer, format='PNG')
        image_bytes = buffer.getvalue()
        
        pipeline = HybridOCRPipeline()
        
        if not pipeline.is_available():
            self.skipTest("OCR engines not available")
        
        # Process frame
        result = await pipeline.process_frame(
            image_bytes,
            session_id="test_session",
            skip_duplicates=False
        )
        
        # Should return a result
        self.assertIsNotNone(result)
        self.assertIsNotNone(result.primary_text)
        self.assertGreaterEqual(result.confidence, 0)
        self.assertGreaterEqual(result.processing_time_ms, 0)
    
    async def test_duplicate_detection(self):
        """Test duplicate frame detection."""
        try:
            from services.ocr_hybrid import HybridOCRPipeline
        except ImportError:
            self.skipTest("Hybrid OCR dependencies not available")
        
        # Create test image
        img = Image.new('RGB', (400, 300), color=(200, 200, 200))
        buffer = io.BytesIO()
        img.save(buffer, format='PNG')
        image_bytes = buffer.getvalue()
        
        pipeline = HybridOCRPipeline()
        
        if not pipeline.is_available():
            self.skipTest("OCR engines not available")
        
        # Process same frame twice
        result1 = await pipeline.process_frame(image_bytes, skip_duplicates=True)
        result2 = await pipeline.process_frame(image_bytes, skip_duplicates=True)
        
        # Second should be marked as duplicate
        self.assertEqual(result2.source, "duplicate")
    
    async def test_vlm_trigger_modes(self):
        """Test different VLM trigger modes."""
        try:
            from services.ocr_hybrid import (
                HybridOCRPipeline, OCRMode, VLMTriggerMode
            )
        except ImportError:
            self.skipTest("Hybrid OCR dependencies not available")
        
        # Test different modes
        modes_to_test = [
            (OCRMode.HYBRID, VLMTriggerMode.ADAPTIVE),
            (OCRMode.PADDLE_ONLY, VLMTriggerMode.NEVER),
            (OCRMode.VLM_ONLY, VLMTriggerMode.ALWAYS),
        ]
        
        for mode, trigger in modes_to_test:
            with self.subTest(mode=mode, trigger=trigger):
                pipeline = HybridOCRPipeline(mode=mode, vlm_trigger=trigger)
                self.assertEqual(pipeline.mode, mode)
                self.assertEqual(pipeline.vlm_trigger, trigger)
    
    async def test_stats_tracking(self):
        """Test statistics tracking."""
        try:
            from services.ocr_hybrid import HybridOCRPipeline
        except ImportError:
            self.skipTest("Hybrid OCR dependencies not available")
        
        pipeline = HybridOCRPipeline()
        
        # Get initial stats
        initial_stats = pipeline.get_status()
        self.assertIn("pipeline_stats", initial_stats)
        
        # Reset and verify
        pipeline.reset_stats()
        reset_stats = pipeline.get_status()["pipeline_stats"]
        self.assertEqual(reset_stats["frames_processed"], 0)


class TestEnvironmentConfiguration(unittest.TestCase):
    """Tests for environment variable configuration."""
    
    @patch.dict('os.environ', {
        'ECHOPANEL_OCR_MODE': 'hybrid',
        'ECHOPANEL_OCR_CONFIDENCE_THRESHOLD': '90',
        'ECHOPANEL_OCR_VLM_TRIGGER': 'always'
    })
    def test_environment_config(self):
        """Test that environment variables are read correctly."""
        # Need to reimport to pick up new env vars
        import importlib
        from services import ocr_hybrid
        importlib.reload(ocr_hybrid)
        
        self.assertEqual(ocr_hybrid.OCR_MODE, 'hybrid')
        self.assertEqual(ocr_hybrid.OCR_CONFIDENCE_THRESHOLD, 90.0)
        self.assertEqual(ocr_hybrid.OCR_VLM_TRIGGER, 'always')


class TestRAGIntegration(unittest.TestCase):
    """Tests for RAG indexing integration."""
    
    def test_enriched_document_text(self):
        """Test that enriched text includes all components."""
        result = HybridOCRResult(
            primary_text="Revenue $5M",
            raw_ocr_text="Revenu $5M",
            semantic_summary="Q3 revenue chart showing growth",
            key_insights=["15% YoY growth", "Record quarter"],
            entities=[
                Entity("Q3 2024", "date", 0.9),
                Entity("Revenue", "metric", 0.8)
            ],
            layout_type=LayoutType.CHART
        )
        
        searchable = result.to_searchable_text()
        
        # Should include all components
        self.assertIn("Revenue $5M", searchable)
        self.assertIn("Q3 revenue chart", searchable)
        self.assertIn("15% YoY growth", searchable)
        self.assertIn("Q3 2024 (date)", searchable)


def run_tests():
    """Run all tests."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestLayoutClassifier))
    suite.addTests(loader.loadTestsFromTestCase(TestFusionEngine))
    suite.addTests(loader.loadTestsFromTestCase(TestPaddleOCRResult))
    suite.addTests(loader.loadTestsFromTestCase(TestHybridOCRResult))
    suite.addTests(loader.loadTestsFromTestCase(TestIntegrationAsync))
    suite.addTests(loader.loadTestsFromTestCase(TestEnvironmentConfiguration))
    suite.addTests(loader.loadTestsFromTestCase(TestRAGIntegration))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
