"""
Tests for Video Understanding Pipeline
"""

import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock
from PIL import Image
import io

from server.services.ocr_smolvlm import (
    VideoFrameSampler,
    VideoFrame,
    FrameSamplingStrategy,
    VideoAnalysisResult,
    VideoUnderstandingPipeline,
)


class TestVideoFrameSampler:
    """Test frame sampling strategies."""
    
    def test_uniform_sampling(self):
        """Test uniform frame sampling."""
        sampler = VideoFrameSampler(
            strategy=FrameSamplingStrategy.UNIFORM,
            max_frames=5,
            interval_seconds=10
        )
        
        def mock_frame_fn(ts):
            img = Image.new('RGB', (100, 100), color='red')
            return img
        
        frames = sampler.sample(60.0, mock_frame_fn)
        
        assert len(frames) <= 5
        assert all(isinstance(f, VideoFrame) for f in frames)
    
    def test_center_sampling(self):
        """Test center frame sampling."""
        sampler = VideoFrameSampler(
            strategy=FrameSamplingStrategy.CENTER,
            max_frames=1,
            interval_seconds=10
        )
        
        def mock_frame_fn(ts):
            img = Image.new('RGB', (100, 100), color='blue')
            return img
        
        frames = sampler.sample(60.0, mock_frame_fn)
        
        assert len(frames) == 1
        assert frames[0].timestamp_ms == 30000
    
    def test_zero_duration(self):
        """Test with zero duration video."""
        sampler = VideoFrameSampler()
        
        def mock_frame_fn(ts):
            return Image.new('RGB', (100, 100))
        
        frames = sampler.sample(0.0, mock_frame_fn)
        assert len(frames) == 0


class TestVideoAnalysisResult:
    """Test video analysis result."""
    
    def test_to_narrative_with_summary(self):
        """Test narrative generation with summary."""
        result = VideoAnalysisResult(
            frame_summaries=["Slide 1 shows Q4 results", "Slide 2 shows roadmap"],
            overall_summary="Quarterly review meeting",
            key_scenes=["Q4 metrics", "Product roadmap"],
            detected_text=["Revenue: $1M", "Launch: Q2"],
            confidence=0.8
        )
        
        narrative = result.to_narrative()
        
        assert "Quarterly review meeting" in narrative
        assert "Q4 metrics" in narrative
        assert "Revenue" in narrative
    
    def test_to_narrative_empty(self):
        """Test narrative with no content."""
        result = VideoAnalysisResult()
        
        narrative = result.to_narrative()
        
        assert "No visual content analyzed" in narrative
    
    def test_success_property(self):
        """Test success property."""
        result_success = VideoAnalysisResult()
        assert result_success.success is True
        
        result_error = VideoAnalysisResult(error="Test error")
        assert result_error.success is False


class TestVideoUnderstandingPipeline:
    """Test video understanding pipeline."""
    
    @pytest.mark.asyncio
    async def test_pipeline_not_available_without_vlm(self):
        """Test pipeline reports unavailable when VLM not available."""
        with patch('server.services.ocr_smolvlm.SmolVLMPipeline.is_available', return_value=False):
            pipeline = VideoUnderstandingPipeline()
            assert pipeline.is_available() is False
    
    @pytest.mark.asyncio
    async def test_analyze_video_no_frames(self):
        """Test analyze with no frames."""
        with patch('server.services.ocr_smolvlm.SmolVLMPipeline.is_available', return_value=False):
            pipeline = VideoUnderstandingPipeline()
            
            def mock_frame_fn(ts):
                return Image.new('RGB', (100, 100))
            
            result = await pipeline.analyze_video(10.0, mock_frame_fn)
            
            assert result.error is not None
    
    def test_get_stats(self):
        """Test stats retrieval."""
        pipeline = VideoUnderstandingPipeline()
        stats = pipeline.get_stats()
        
        assert "videos_processed" in stats
        assert "videos_failed" in stats


class TestIntegration:
    """Test integration with existing OCR pipeline."""
    
    def test_smolvlm2_model_default(self):
        """Test that SmolVLM2 is the default model."""
        from server.services.ocr_smolvlm import SMOLVLM_MODEL
        
        assert "SmolVLM2" in SMOLVLM_MODEL
        assert "500M" in SMOLVLM_MODEL
    
    def test_video_config_defaults(self):
        """Test default video config."""
        from server.services.ocr_smolvlm import VLM_FRAME_INTERVAL, VLM_MAX_FRAMES, VLM_FRAME_SAMPLING
        
        assert VLM_FRAME_INTERVAL == 10
        assert VLM_MAX_FRAMES == 20
        assert VLM_FRAME_SAMPLING == "uniform"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
