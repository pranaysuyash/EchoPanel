"""
Tests for whisper.cpp ASR provider.
"""

import pytest
import asyncio
import numpy as np
from unittest.mock import Mock, patch, MagicMock


# Skip all tests if pywhispercpp not available
try:
    from pywhispercpp.model import Model
    PYWHISPERCPP_AVAILABLE = True
except ImportError:
    PYWHISPERCPP_AVAILABLE = False


pytestmark = pytest.mark.skipif(
    not PYWHISPERCPP_AVAILABLE,
    reason="pywhispercpp not installed"
)


@pytest.fixture
def mock_model():
    """Create a mock whisper.cpp model."""
    mock = MagicMock()
    
    # Mock segment returned by transcribe
    mock_segment = MagicMock()
    mock_segment.text = "Hello world"
    mock_segment.t0 = 0.0
    mock_segment.t1 = 2.0
    mock_segment.confidence = 0.95
    
    mock.transcribe.return_value = [mock_segment]
    return mock


@pytest.fixture
def provider(mock_model):
    """Create provider with mocked model."""
    from server.services.provider_whisper_cpp import WhisperCppProvider, ASRConfig
    
    with patch("server.services.provider_whisper_cpp.Model", return_value=mock_model):
        config = ASRConfig(
            model_name="base",
            device="cpu",  # Use CPU for tests
            chunk_seconds=2,
        )
        provider = WhisperCppProvider(config)
        yield provider


class TestWhisperCppProvider:
    """Test suite for WhisperCppProvider."""
    
    def test_is_available(self):
        """Test availability check."""
        from server.services.provider_whisper_cpp import WhisperCppProvider
        # Should return True since we have pywhispercpp
        assert WhisperCppProvider.is_available() == PYWHISPERCPP_AVAILABLE
    
    def test_default_config(self, provider):
        """Test default configuration."""
        assert provider.config.model_name == "base"
        assert provider.config.chunk_seconds == 2
    
    @pytest.mark.asyncio
    async def test_transcribe_stream(self, provider, mock_model):
        """Test streaming transcription."""
        # Create test audio (2s of silence)
        sample_rate = 16000
        duration = 2.0
        audio = np.zeros(int(sample_rate * duration), dtype=np.int16)
        
        async def audio_stream():
            chunk_size = 32000  # 1s
            audio_bytes = audio.tobytes()
            for i in range(0, len(audio_bytes), chunk_size):
                yield audio_bytes[i:i+chunk_size]
        
        segments = []
        async for segment in provider.transcribe_stream(audio_stream(), source="mic"):
            segments.append(segment)
        
        assert len(segments) > 0
        assert segments[0].text == "Hello world"
        assert segments[0].source == "mic"
    
    def test_get_model_path(self, provider):
        """Test model path resolution."""
        path = provider._get_model_path()
        assert "ggml-base.bin" in path
    
    def test_is_apple_silicon(self, provider):
        """Test Apple Silicon detection."""
        # Should return False on non-macOS systems
        result = provider._is_apple_silicon()
        assert isinstance(result, bool)
    
    def test_get_optimal_threads(self, provider):
        """Test thread count calculation."""
        threads = provider._get_optimal_threads()
        assert 1 <= threads <= 8
    
    def test_performance_stats(self, provider):
        """Test performance tracking."""
        stats = provider.get_performance_stats()
        
        assert "avg_inference_ms" in stats
        assert "realtime_factor" in stats
        assert isinstance(stats["avg_inference_ms"], float)
    
    def test_health(self, provider):
        """Test health check."""
        health = provider.health()
        
        assert "available" in health
        assert "model_loaded" in health


class TestModelSelection:
    """Test model selection logic."""
    
    def test_model_mapping(self):
        """Test model name to filename mapping."""
        from server.services.provider_whisper_cpp import WhisperCppProvider
        
        # Check known models
        assert "tiny" in WhisperCppProvider.MODELS
        assert "base" in WhisperCppProvider.MODELS
        assert "small" in WhisperCppProvider.MODELS
        
        # Check model info
        base_info = WhisperCppProvider.MODELS["base"]
        assert "file" in base_info
        assert "memory_mb" in base_info
