"""
Tests for whisper.cpp ASR provider.
"""

import pytest
import asyncio
import platform
from unittest.mock import Mock, patch, MagicMock, AsyncMock
from pathlib import Path

from server.services.provider_whisper_cpp import WhisperCppProvider, ASRConfig


class TestWhisperCppProvider:
    """Test suite for WhisperCppProvider."""
    
    def test_is_available_detects_binary(self):
        """Test availability check when binary and model exist."""
        with patch("subprocess.run") as mock_run:
            mock_run.return_value.returncode = 0
            with patch.object(Path, "exists", return_value=True):
                config = ASRConfig()
                provider = WhisperCppProvider(config)
                assert provider.is_available is True
    
    def test_is_available_detects_missing_binary(self):
        """Test availability check when binary is missing."""
        with patch("subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError()
            config = ASRConfig()
            provider = WhisperCppProvider(config)
            assert provider.is_available is False
    
    def test_is_available_detects_missing_model(self):
        """Test availability check when model is missing."""
        config = ASRConfig()
        provider = WhisperCppProvider(config)
        # Model file doesn't exist by default
        assert provider.is_available is False
    
    def test_default_config(self):
        """Test default configuration."""
        config = ASRConfig(
            model_name="base",
            device="cpu",
            chunk_seconds=2,
        )
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        assert provider.config.model_name == "base"
        assert provider.config.chunk_seconds == 2
        assert provider.name == "whisper_cpp"
    
    def test_get_model_path(self):
        """Test model path resolution."""
        config = ASRConfig(model_name="base")
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        path = provider._get_model_path()
        assert "ggml-base.bin" in str(path)
    
    def test_is_apple_silicon(self):
        """Test Apple Silicon detection."""
        config = ASRConfig()
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        result = provider._is_apple_silicon()
        # Result depends on actual platform
        assert isinstance(result, bool)
        if platform.system() == "Darwin" and platform.machine() == "arm64":
            assert result is True
    
    def test_get_optimal_threads(self):
        """Test thread count calculation."""
        config = ASRConfig()
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        threads = provider._get_optimal_threads()
        assert 1 <= threads <= 8
    
    def test_performance_stats_empty(self):
        """Test performance tracking with no data."""
        config = ASRConfig()
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        stats = provider.get_performance_stats()
        
        assert "avg_inference_ms" in stats
        assert "realtime_factor" in stats
        assert isinstance(stats["avg_inference_ms"], float)
        assert stats["chunks_processed"] == 0
    
    def test_performance_stats_with_data(self):
        """Test performance tracking with data."""
        config = ASRConfig(chunk_seconds=2)
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        # Simulate some inference times
        provider._infer_times = [0.5, 0.6, 0.4]
        provider._chunks_processed = 3
        
        stats = provider.get_performance_stats()
        
        assert stats["avg_inference_ms"] == 500.0  # (0.5+0.6+0.4)/3 * 1000
        assert stats["chunks_processed"] == 3
        assert stats["realtime_factor"] > 0
    
    @pytest.mark.asyncio
    async def test_health(self):
        """Test health check."""
        config = ASRConfig()
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        health = await provider.health()
        
        assert "status" in health
        assert "realtime_factor" in health
        assert "chunks_processed" in health
    
    @pytest.mark.asyncio
    async def test_transcribe_stream_unavailable(self):
        """Test streaming when provider unavailable."""
        config = ASRConfig()
        
        # Create provider with mocked model path
        with patch.object(WhisperCppProvider, '_get_model_path', return_value=Path("/fake/model.bin")):
            provider = WhisperCppProvider(config)
            # Override is_available to return False
            type(provider).is_available = property(lambda self: False)
        
        async def empty_stream():
            if False:
                yield b""
        
        segments = []
        async for segment in provider.transcribe_stream(empty_stream()):
            segments.append(segment)
        
        assert len(segments) == 1
        assert "unavailable" in segments[0].text.lower()


class TestModelSelection:
    """Test model selection logic."""
    
    def test_model_mapping(self):
        """Test model name to filename mapping."""
        # Check known models exist in MODELS dict
        assert "tiny" in WhisperCppProvider.MODELS
        assert "base" in WhisperCppProvider.MODELS
        assert "small" in WhisperCppProvider.MODELS
        
        # Check model info structure
        base_info = WhisperCppProvider.MODELS["base"]
        assert "file" in base_info
        assert "memory_mb" in base_info
        assert base_info["file"] == "ggml-base.bin"
    
    def test_model_path_resolution(self):
        """Test that all MODELS entries can resolve paths."""
        config = ASRConfig(model_name="base")
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        for model_name, model_info in WhisperCppProvider.MODELS.items():
            provider.config.model_name = model_name
            path = provider._get_model_path()
            assert model_info["file"] in str(path)


class TestProviderContract:
    """Test ASRProvider contract compliance."""
    
    def test_provider_registration(self):
        """Test that provider is registered."""
        from server.services.asr_providers import ASRProviderRegistry
        
        # Provider is registered in module
        assert "whisper_cpp" in ASRProviderRegistry._providers
        
        # available_providers() only returns providers that are_available
        # which requires whisper-cli to be installed, so we just check registration
    
    def test_provider_capabilities(self):
        """Test provider capabilities."""
        config = ASRConfig()
        
        with patch.object(WhisperCppProvider, 'is_available', return_value=True):
            provider = WhisperCppProvider(config)
        
        caps = provider.capabilities
        assert caps.supports_metal is True  # Should report Metal support on Apple
        assert caps.supports_streaming is True
        assert caps.supports_batch is True


@pytest.mark.skip(reason="Requires whisper-cli to be installed with models")
class TestIntegration:
    """Integration tests - only run if whisper.cpp is installed."""
    
    @pytest.mark.asyncio
    async def test_provider_initialization(self):
        """Test full provider initialization."""
        config = ASRConfig(model_name="base")
        provider = WhisperCppProvider(config)
        
        # Check that we can read properties
        assert provider.name == "whisper_cpp"
        assert provider.model_path is not None
        assert provider.bin_path == "whisper-cli"
    
    def test_health_with_real_provider(self):
        """Test health check with real provider."""
        config = ASRConfig()
        provider = WhisperCppProvider(config)
        
        health = asyncio.run(provider.health())
        assert "status" in health
        assert "model_exists" in health
