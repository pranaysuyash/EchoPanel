"""
Tests for Screen OCR Pipeline

Covers:
- Image preprocessing
- Perceptual hashing
- OCR with confidence
- Deduplication
- End-to-end pipeline
"""

import base64
import io
import sys
import time
from unittest.mock import Mock, patch

import pytest

# Ensure server is in path
sys.path.insert(0, '/Users/pranay/Projects/EchoPanel')


class TestImagePreprocessor:
    """Tests for image preprocessing module."""
    
    def test_preprocess_from_bytes_valid_image(self):
        """Test preprocessing a valid image."""
        from PIL import Image
        from server.services.image_preprocess import ImagePreprocessor
        
        # Create a test image
        img = Image.new('RGB', (1920, 1080), color='white')
        # Add some text-like patterns
        from PIL import ImageDraw
        draw = ImageDraw.Draw(img)
        draw.text((100, 100), "Test text for OCR", fill='black')
        
        # Save to bytes
        buf = io.BytesIO()
        img.save(buf, format='JPEG')
        image_bytes = buf.getvalue()
        
        # Preprocess
        preprocessor = ImagePreprocessor(max_dimension=1280)
        result = preprocessor.preprocess_from_bytes(image_bytes)
        
        assert result is not None
        assert result.mode == 'L'  # Grayscale
        assert max(result.size) <= 1280  # Resized
    
    def test_preprocess_invalid_bytes(self):
        """Test handling invalid image bytes."""
        from server.services.image_preprocess import ImagePreprocessor
        
        preprocessor = ImagePreprocessor()
        result = preprocessor.preprocess_from_bytes(b"not an image")
        
        assert result is None
    
    def test_resize_large_image(self):
        """Test that large images are resized."""
        from PIL import Image
        from server.services.image_preprocess import ImagePreprocessor
        
        # Create large image
        img = Image.new('RGB', (4000, 3000), color='white')
        
        preprocessor = ImagePreprocessor(max_dimension=1280)
        result = preprocessor._resize_if_needed(img)
        
        assert max(result.size) <= 1280
        # Aspect ratio preserved
        assert abs(result.width / result.height - 4/3) < 0.01
    
    def test_no_resize_small_image(self):
        """Test that small images are not resized."""
        from PIL import Image
        from server.services.image_preprocess import ImagePreprocessor
        
        img = Image.new('RGB', (800, 600), color='white')
        
        preprocessor = ImagePreprocessor(max_dimension=1280)
        result = preprocessor._resize_if_needed(img)
        
        assert result.size == (800, 600)


class TestPerceptualHash:
    """Tests for perceptual hashing module."""
    
    def test_compute_hash_consistency(self):
        """Test that same image produces same hash."""
        from PIL import Image
        from server.services.image_hash import PerceptualHash
        
        img = Image.new('RGB', (400, 300), color='red')
        
        hasher = PerceptualHash()
        hash1 = hasher.compute_hash(img)
        hash2 = hasher.compute_hash(img)
        
        assert hash1 == hash2
        assert len(hash1) > 0
    
    def test_similar_images_have_close_hashes(self):
        """Test that visually similar images have similar hashes."""
        from PIL import Image
        from server.services.image_hash import PerceptualHash
        
        # Two similar images (same color, slightly different size)
        img1 = Image.new('RGB', (400, 300), color='blue')
        img2 = Image.new('RGB', (395, 295), color='blue')
        
        hasher = PerceptualHash()
        hash1 = hasher.compute_hash(img1)
        hash2 = hasher.compute_hash(img2)
        
        distance = hasher.hamming_distance(hash1, hash2)
        
        # Similar images should have small hamming distance
        assert distance < 10
    
    def test_different_images_have_different_hashes(self):
        """Test that different images have different hashes."""
        from PIL import Image
        from server.services.image_hash import PerceptualHash
        
        # Two very different images
        img1 = Image.new('RGB', (400, 300), color='white')
        img2 = Image.new('RGB', (400, 300), color='black')
        
        hasher = PerceptualHash()
        hash1 = hasher.compute_hash(img1)
        hash2 = hasher.compute_hash(img2)
        
        distance = hasher.hamming_distance(hash1, hash2)
        
        # Very different images should have large hamming distance
        assert distance > 10
    
    def test_is_similar_threshold(self):
        """Test similarity detection with threshold."""
        from PIL import Image
        from server.services.image_hash import PerceptualHash
        
        img1 = Image.new('RGB', (400, 300), color='green')
        img2 = Image.new('RGB', (400, 300), color='green')  # Same
        
        hasher = PerceptualHash()
        hash1 = hasher.compute_hash(img1)
        hash2 = hasher.compute_hash(img2)
        
        # Same image should be similar
        assert hasher.is_similar(hash1, hash2, threshold=5)


class TestImageDeduplicator:
    """Tests for image deduplication."""
    
    def test_duplicate_detection(self):
        """Test that duplicate images are detected."""
        from PIL import Image
        import io
        from server.services.image_hash import ImageDeduplicator
        
        dedup = ImageDeduplicator(threshold=5)
        
        # Create image
        img = Image.new('RGB', (400, 300), color='yellow')
        buf = io.BytesIO()
        img.save(buf, format='JPEG')
        image_bytes = buf.getvalue()
        
        # First image is not duplicate
        assert not dedup.is_duplicate(image_bytes)
        
        # Same image is duplicate
        assert dedup.is_duplicate(image_bytes)
    
    def test_similar_images_not_duplicate(self):
        """Test that similar but different images are not marked duplicates."""
        from PIL import Image
        import io
        from server.services.image_hash import ImageDeduplicator
        
        dedup = ImageDeduplicator(threshold=5)
        
        # Two different images
        img1 = Image.new('RGB', (400, 300), color='purple')
        img2 = Image.new('RGB', (400, 300), color='orange')
        
        buf1 = io.BytesIO()
        img1.save(buf1, format='JPEG')
        
        buf2 = io.BytesIO()
        img2.save(buf2, format='JPEG')
        
        assert not dedup.is_duplicate(buf1.getvalue())
        assert not dedup.is_duplicate(buf2.getvalue())  # Different image
    
    def test_max_history_limit(self):
        """Test that history is limited to max_history."""
        from PIL import Image
        import io
        from server.services.image_hash import ImageDeduplicator
        
        dedup = ImageDeduplicator(threshold=5, max_history=3)
        
        # Add 3 different images
        for i, color in enumerate(['red', 'green', 'blue']):
            img = Image.new('RGB', (400, 300), color=color)
            buf = io.BytesIO()
            img.save(buf, format='JPEG')
            dedup.is_duplicate(buf.getvalue())
        
        # History should be trimmed to 3
        assert len(dedup.seen_hashes) == 3


class TestScreenOCRPipeline:
    """Tests for main OCR pipeline."""
    
    @pytest.mark.asyncio
    async def test_pipeline_not_available(self):
        """Test behavior when OCR is not available."""
        from server.services.screen_ocr import ScreenOCRPipeline
        
        with patch('server.services.screen_ocr.TESSERACT_AVAILABLE', False):
            pipeline = ScreenOCRPipeline()
            assert not pipeline.is_available()
            
            result = await pipeline.process_frame(b"fake image")
            assert not result.success
            assert "not available" in result.error.lower()
    
    @pytest.mark.asyncio
    async def test_process_valid_image(self):
        """Test processing a valid image with text."""
        from PIL import Image, ImageDraw, ImageFont
        import io
        from server.services.screen_ocr import ScreenOCRPipeline
        
        # Skip if tesseract not available
        try:
            import pytesseract
            pytesseract.get_tesseract_version()
        except:
            pytest.skip("Tesseract not installed")
        
        # Create image with text
        img = Image.new('RGB', (400, 100), color='white')
        draw = ImageDraw.Draw(img)
        
        # Use default font
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
        except:
            font = ImageFont.load_default()
        
        draw.text((10, 30), "OCR Test 123", fill='black', font=font)
        
        buf = io.BytesIO()
        img.save(buf, format='PNG')  # PNG for better quality
        image_bytes = buf.getvalue()
        
        # Process
        pipeline = ScreenOCRPipeline(confidence_threshold=30)
        result = await pipeline.process_frame(image_bytes)
        
        # Should succeed (even if text not perfect)
        assert result is not None
        # Processing should complete
        assert result.processing_time_ms > 0
    
    @pytest.mark.asyncio
    async def test_duplicate_skipping(self):
        """Test that duplicates are skipped."""
        from PIL import Image
        import io
        from server.services.screen_ocr import ScreenOCRPipeline
        
        # Create image
        img = Image.new('RGB', (400, 300), color='cyan')
        buf = io.BytesIO()
        img.save(buf, format='JPEG')
        image_bytes = buf.getvalue()
        
        pipeline = ScreenOCRPipeline()
        
        # Mock OCR to avoid tesseract dependency
        with patch.object(pipeline, '_ocr_with_confidence', return_value=("test", 90.0)):
            # First frame - not duplicate
            result1 = await pipeline.process_frame(image_bytes, skip_duplicates=True)
            assert not result1.is_duplicate
            
            # Second frame - duplicate
            result2 = await pipeline.process_frame(image_bytes, skip_duplicates=True)
            assert result2.is_duplicate
    
    def test_ocresult_properties(self):
        """Test OCResult helper properties."""
        from server.services.screen_ocr import OCResult
        
        # Successful result
        result = OCResult(
            text="Hello world",
            confidence=90.0,
            word_count=2,
            processing_time_ms=100.0
        )
        assert result.success
        assert result.should_index
        
        # Low confidence result
        result_low = OCResult(
            text="Hello",
            confidence=50.0,
            word_count=1,
            processing_time_ms=100.0
        )
        assert result_low.success
        assert not result_low.should_index  # Below threshold
        
        # Failed result
        result_fail = OCResult(
            text="",
            confidence=0.0,
            word_count=0,
            processing_time_ms=0.0,
            error="Processing failed"
        )
        assert not result_fail.success
        assert not result_fail.should_index
    
    def test_stats_tracking(self):
        """Test that statistics are tracked correctly."""
        from server.services.screen_ocr import ScreenOCRPipeline
        
        pipeline = ScreenOCRPipeline()
        
        # Simulate some stats
        pipeline._stats["frames_processed"] = 10
        pipeline._stats["frames_duplicate"] = 2
        pipeline._stats["frames_indexed"] = 6
        pipeline._stats["total_processing_time_ms"] = 5000
        
        stats = pipeline.get_stats()
        
        assert stats["frames_processed"] == 10
        assert stats["frames_duplicate"] == 2
        assert stats["frames_indexed"] == 6
        assert stats["avg_processing_time_ms"] == 500.0
    
    def test_reset_stats(self):
        """Test stats reset functionality."""
        from server.services.screen_ocr import ScreenOCRPipeline
        
        pipeline = ScreenOCRPipeline()
        pipeline._stats["frames_processed"] = 100
        
        pipeline.reset_stats()
        
        assert pipeline._stats["frames_processed"] == 0


class TestOCRFrameHandler:
    """Tests for OCR frame handler."""
    
    @pytest.mark.asyncio
    async def test_handle_frame_disabled(self):
        """Test handler when OCR is disabled."""
        from server.services.screen_ocr import OCRFrameHandler
        
        handler = OCRFrameHandler()
        handler._enabled = False
        
        result = await handler.handle_frame(
            image_base64="fake_base64",
            session_id="test_session",
            timestamp=time.time()
        )
        
        assert not result.success
        assert "disabled" in result.error.lower()
    
    @pytest.mark.asyncio
    async def test_handle_frame_invalid_base64(self):
        """Test handling invalid base64."""
        from server.services.screen_ocr import OCRFrameHandler
        
        handler = OCRFrameHandler()
        handler._enabled = True
        
        result = await handler.handle_frame(
            image_base64="!!!invalid_base64!!!",
            session_id="test_session",
            timestamp=time.time()
        )
        
        assert not result.success
        assert "decode" in result.error.lower() or "decode" in str(result.error).lower()
    
    @pytest.mark.asyncio
    async def test_handle_frame_valid(self):
        """Test handling valid frame."""
        from PIL import Image
        import io
        import base64
        from server.services.screen_ocr import OCRFrameHandler
        
        handler = OCRFrameHandler()
        handler._enabled = True
        
        # Create valid base64 image
        img = Image.new('RGB', (100, 100), color='white')
        buf = io.BytesIO()
        img.save(buf, format='JPEG')
        image_base64 = base64.b64encode(buf.getvalue()).decode()
        
        # Mock the pipeline
        with patch.object(handler.pipeline, 'process_frame') as mock_process:
            from server.services.screen_ocr import OCResult
            mock_process.return_value = OCResult(
                text="Test text",
                confidence=90.0,
                word_count=2,
                processing_time_ms=100.0
            )
            
            result = await handler.handle_frame(
                image_base64=image_base64,
                session_id="test_session",
                timestamp=time.time(),
                index_to_rag=False  # Skip RAG indexing for test
            )
            
            assert result.success
            assert result.text == "Test text"
    
    def test_get_status(self):
        """Test status reporting."""
        from server.services.screen_ocr import OCRFrameHandler
        
        handler = OCRFrameHandler()
        status = handler.get_status()
        
        assert "enabled" in status
        assert "available" in status
        assert "config" in status
        assert "stats" in status


class TestOCRIntegration:
    """Integration tests for full OCR flow."""
    
    @pytest.mark.asyncio
    async def test_end_to_end_with_mock(self):
        """Test full flow with mocked dependencies."""
        from server.services.screen_ocr import (
            ScreenOCRPipeline,
            OCRFrameHandler,
            get_ocr_handler,
            reset_ocr_handler
        )
        
        # Reset singleton
        reset_ocr_handler()
        
        # Get fresh handler
        handler = get_ocr_handler()
        
        # Mock OCR to avoid tesseract dependency
        with patch.object(handler.pipeline, '_ocr_with_confidence', return_value=("Meeting notes: Q3 revenue $5M", 95.0)):
            with patch.object(handler.pipeline, 'is_available', return_value=True):
                handler._enabled = True
                
                from PIL import Image
                import io
                import base64
                
                # Create test image
                img = Image.new('RGB', (400, 300), color='white')
                buf = io.BytesIO()
                img.save(buf, format='JPEG')
                image_base64 = base64.b64encode(buf.getvalue()).decode()
                
                # Process frame
                result = await handler.handle_frame(
                    image_base64=image_base64,
                    session_id="test_session",
                    timestamp=time.time(),
                    index_to_rag=False
                )
                
                assert result.success
                assert result.confidence == 95.0
                assert "revenue" in result.text.lower()


# Run tests if executed directly
if __name__ == "__main__":
    pytest.main([__file__, "-v"])
