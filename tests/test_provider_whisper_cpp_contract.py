"""
Contract tests for whisper.cpp ASR provider.

Verifies that the provider adheres to the ASRProvider contract:
- Importable without optional dependencies
- Yields ASRSegment objects with required fields
- Respects AudioSource
- Handles is_final correctly
"""

import asyncio
from pathlib import Path

import pytest


async def _one_chunk_pcm_stream(chunk_bytes: bytes):
    """Yield a single PCM chunk."""
    yield chunk_bytes


@pytest.mark.asyncio
async def test_whisper_cpp_provider_contract(monkeypatch, tmp_path):
    """
    Provider should be importable and when configured properly,
    it should yield ASRSegment objects with is_final=True and AudioSource source.
    """
    from server.services import provider_whisper_cpp
    from server.services.asr_providers import ASRConfig, AudioSource

    cfg = ASRConfig(
        model_name="base", 
        device="metal", 
        compute_type="fp16", 
        chunk_seconds=1, 
        vad_enabled=False
    )
    provider = provider_whisper_cpp.WhisperCppProvider(cfg)
    
    assert provider.name == "whisper_cpp"
    # is_available is a property - returns bool
    assert isinstance(provider.is_available, bool)

    # Test with unavailable provider (model doesn't exist)
    # This is the default state since we don't have whisper-cli installed
    pcm_bytes = b"\x00\x00" * 16000  # 1s @ 16kHz pcm_s16le mono
    
    segments = []
    async for seg in provider.transcribe_stream(
        _one_chunk_pcm_stream(pcm_bytes), 
        sample_rate=16000, 
        source=AudioSource.SYSTEM
    ):
        segments.append(seg)

    # Should get at least one segment (error message when unavailable)
    assert segments, "Expected at least one segment"
    assert all(s.is_final for s in segments)
    assert all(s.source == AudioSource.SYSTEM for s in segments)
    # When unavailable, should indicate that in the text
    assert "unavailable" in segments[0].text.lower()


@pytest.mark.asyncio
async def test_whisper_cpp_provider_interface():
    """
    Verify provider interface matches ASRProvider contract.
    """
    from server.services.provider_whisper_cpp import WhisperCppProvider
    from server.services.asr_providers import ASRProvider, ASRConfig
    
    # Verify inheritance
    assert issubclass(WhisperCppProvider, ASRProvider)
    
    # Verify required methods exist
    assert hasattr(WhisperCppProvider, 'name')
    assert hasattr(WhisperCppProvider, 'is_available')
    assert hasattr(WhisperCppProvider, 'transcribe_stream')
    assert hasattr(WhisperCppProvider, 'health')
    
    # Verify MODELS registry exists
    assert hasattr(WhisperCppProvider, 'MODELS')
    assert "base" in WhisperCppProvider.MODELS
    assert "tiny" in WhisperCppProvider.MODELS


@pytest.mark.asyncio
async def test_whisper_cpp_capabilities():
    """
    Verify provider reports correct capabilities.
    """
    from server.services.provider_whisper_cpp import WhisperCppProvider
    from server.services.asr_providers import ASRConfig
    
    cfg = ASRConfig()
    provider = WhisperCppProvider(cfg)
    
    caps = provider.capabilities
    
    # Whisper.cpp supports streaming (via chunking) and batch
    assert caps.supports_streaming is True
    assert caps.supports_batch is True
    
    # Should report Metal support on Apple Silicon
    import platform
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        assert caps.supports_metal is True
