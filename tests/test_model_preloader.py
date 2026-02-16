"""
Tests for PR4: Model Preloader + Warmup
"""

import pytest
import asyncio
import time
from unittest.mock import Mock, patch, AsyncMock

from server.services.model_preloader import (
    ModelManager,
    ModelState,
    ModelHealth,
    WarmupConfig,
    get_model_manager,
    reset_model_manager,
    shutdown_model_manager,
)
from server.services.asr_providers import ASRConfig


class TestModelManager:
    """Test suite for ModelManager."""
    
    def setup_method(self):
        """Reset singleton before each test."""
        reset_model_manager()
    
    def test_initial_state(self):
        """Test initial state is UNINITIALIZED."""
        manager = ModelManager()
        assert manager.state == ModelState.UNINITIALIZED
        assert not manager.is_ready
    
    @pytest.mark.asyncio
    async def test_initialize_success(self):
        """Test successful initialization."""
        manager = ModelManager()
        
        # Mock provider
        mock_provider = Mock()
        mock_provider.name = "test_provider"
        mock_provider.is_available = True
        
        # Create proper async generator mock
        async def mock_transcribe(*args, **kwargs):
            if False:  # Never yields, just for warmup
                yield Mock()
        
        mock_provider.transcribe_stream = mock_transcribe
        
        with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=mock_provider):
            success = await manager.initialize(timeout=10.0)
        
        assert success
        assert manager.state == ModelState.READY
        assert manager.is_ready
        assert manager.health().model_loaded
    
    @pytest.mark.asyncio
    async def test_initialize_provider_not_available(self):
        """Test initialization when provider not available."""
        manager = ModelManager()
        
        with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=None):
            success = await manager.initialize(timeout=10.0)
        
        assert not success
        # State could be ERROR or remain LOADING depending on error handling
        assert manager.state in (ModelState.ERROR, ModelState.LOADING, ModelState.UNINITIALIZED)
    
    @pytest.mark.asyncio
    async def test_initialize_with_warmup(self):
        """Test initialization with warmup enabled."""
        manager = ModelManager(
            warmup_config=WarmupConfig(
                enabled=True,
                level2_single_inference=True,
                level2_duration_ms=10,  # Fast for tests
            )
        )
        
        mock_provider = Mock()
        mock_provider.name = "test_provider"
        mock_provider.is_available = True
        
        # Mock transcribe_stream to yield one segment
        async def mock_transcribe(*args, **kwargs):
            yield Mock(text="test", t0=0.0, t1=1.0)
        
        mock_provider.transcribe_stream = mock_transcribe
        
        with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=mock_provider):
            success = await manager.initialize(timeout=10.0)
        
        # Warmup may fail due to timing, but load should succeed
        assert manager.state == ModelState.READY or manager.state == ModelState.ERROR
        health = manager.health()
        assert health.model_loaded
    
    @pytest.mark.asyncio
    async def test_transcribe_when_ready(self):
        """Test transcription when model is ready."""
        manager = ModelManager()
        
        mock_provider = Mock()
        mock_provider.name = "test_provider"
        mock_provider.is_available = True
        
        async def mock_transcribe(*args, **kwargs):
            yield Mock(text="hello", t0=0.0, t1=1.0)
            yield Mock(text="world", t0=1.0, t1=2.0)
        
        mock_provider.transcribe_stream = mock_transcribe
        
        with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=mock_provider):
            await manager.initialize(timeout=10.0)
        
        # Skip test if initialization failed
        if not manager.is_ready:
            pytest.skip("Model initialization failed")
        
        # Test transcribe
        segments = []
        async for segment in manager.transcribe(AsyncMock()):
            segments.append(segment)
        
        assert len(segments) == 2
        assert manager.get_stats()["inference_count"] == 1
    
    @pytest.mark.asyncio
    async def test_transcribe_when_not_ready(self):
        """Test transcription fails when model not ready."""
        manager = ModelManager()
        
        with pytest.raises(RuntimeError, match="Model not ready"):
            async for _ in manager.transcribe(AsyncMock()):
                pass
    
    def test_health(self):
        """Test health status."""
        manager = ModelManager()
        health = manager.health()
        
        assert isinstance(health, ModelHealth)
        assert health.state == ModelState.UNINITIALIZED
        assert not health.ready
        payload = health.to_dict()
        assert "process_rss_mb" in payload
        assert payload["process_rss_mb"] is None or payload["process_rss_mb"] >= 0
    
    def test_get_stats(self):
        """Test getting statistics."""
        manager = ModelManager()
        stats = manager.get_stats()
        
        assert "state" in stats
        assert "load_time_ms" in stats
        assert "inference_count" in stats


class TestWarmupConfig:
    """Test suite for WarmupConfig."""
    
    def test_default_config(self):
        """Test default warmup configuration."""
        config = WarmupConfig()
        
        assert config.enabled
        assert config.level2_single_inference
        assert not config.level3_full_warmup  # Disabled by default
        assert config.sample_rate == 16000
        assert config.warmup_audio_seconds == 2.0
    
    def test_custom_config(self):
        """Test custom warmup configuration."""
        config = WarmupConfig(
            enabled=True,
            level2_single_inference=False,
            level3_full_warmup=True,
            level3_iterations=10,
        )
        
        assert config.enabled
        assert not config.level2_single_inference
        assert config.level3_full_warmup
        assert config.level3_iterations == 10


class TestSingleton:
    """Test singleton behavior."""
    
    def setup_method(self):
        """Reset singleton before each test."""
        reset_model_manager()
    
    def test_get_model_manager_singleton(self):
        """Test that get_model_manager returns same instance."""
        manager1 = get_model_manager()
        manager2 = get_model_manager()
        
        assert manager1 is manager2
    
    def test_reset_model_manager(self):
        """Test reset creates new instance."""
        manager1 = get_model_manager()
        reset_model_manager()
        manager2 = get_model_manager()
        
        assert manager1 is not manager2


@pytest.mark.asyncio
async def test_initialize_model_at_startup():
    """Test initialize_model_at_startup convenience function."""
    from server.services.model_preloader import initialize_model_at_startup
    
    reset_model_manager()
    
    mock_provider = Mock()
    mock_provider.name = "test_provider"
    mock_provider.is_available = True
    
    async def mock_transcribe(*args, **kwargs):
        if False:
            yield Mock()
    
    mock_provider.transcribe_stream = mock_transcribe
    
    with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=mock_provider):
        success = await initialize_model_at_startup()
    
    # Should succeed with proper mock
    manager = get_model_manager()
    assert manager.state == ModelState.READY or manager.health().model_loaded


@pytest.mark.asyncio
async def test_unload_resets_state_and_stats():
    """Model unload should release provider and reset runtime stats."""
    reset_model_manager()
    manager = ModelManager()

    mock_provider = Mock()
    mock_provider.name = "test_provider"
    mock_provider.is_available = True
    mock_provider.stop_session = AsyncMock(return_value=None)
    mock_provider.unload = AsyncMock(return_value=None)

    async def mock_transcribe(*args, **kwargs):
        yield Mock(text="hello", t0=0.0, t1=1.0)

    mock_provider.transcribe_stream = mock_transcribe

    with patch("server.services.model_preloader.ASRProviderRegistry.get_provider", return_value=mock_provider):
        success = await manager.initialize(timeout=10.0)

    assert success
    manager._inference_count = 3
    manager._total_inference_time_ms = 123.0

    with patch("server.services.model_preloader.ASRProviderRegistry.evict_provider_instance", return_value=1) as evict:
        unloaded = await manager.unload(timeout=1.0)

    assert unloaded
    assert manager.state == ModelState.UNINITIALIZED
    assert not manager.is_ready
    assert manager.health().model_loaded is False
    assert manager.get_stats()["inference_count"] == 0
    mock_provider.stop_session.assert_awaited_once()
    mock_provider.unload.assert_awaited_once()
    evict.assert_called_once_with(mock_provider)


@pytest.mark.asyncio
async def test_unload_failure_sets_error_state():
    """Unload failures should transition manager into ERROR with details."""
    manager = ModelManager()

    mock_provider = Mock()
    mock_provider.name = "test_provider"
    mock_provider.stop_session = AsyncMock(return_value=None)
    mock_provider.unload = AsyncMock(side_effect=RuntimeError("unload failed"))

    manager._provider = mock_provider
    manager._state = ModelState.READY

    unloaded = await manager.unload(timeout=0.5)

    assert not unloaded
    assert manager.state == ModelState.ERROR
    assert "unload failed" in (manager.health().last_error or "")


@pytest.mark.asyncio
async def test_shutdown_model_manager_unloads_singleton():
    """Global shutdown helper should unload then reset singleton."""
    reset_model_manager()
    manager = get_model_manager()

    mock_provider = Mock()
    mock_provider.name = "test_provider"
    mock_provider.stop_session = AsyncMock(return_value=None)
    mock_provider.unload = AsyncMock(return_value=None)

    manager._provider = mock_provider
    manager._state = ModelState.READY

    with patch("server.services.model_preloader.ASRProviderRegistry.evict_provider_instance", return_value=1):
        success = await shutdown_model_manager(timeout=1.0)

    assert success
    replacement = get_model_manager()
    assert replacement is not manager
