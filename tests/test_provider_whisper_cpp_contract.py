import asyncio
from dataclasses import dataclass

import pytest


@dataclass
class _FakeSeg:
    text: str
    t0: float
    t1: float
    confidence: float = 0.9


class _FakeModel:
    def __init__(self, model_path, params=None):
        self.model_path = model_path
        self.params = params or {}

    def transcribe(self, audio_float32):
        # Return a single segment relative to the chunk start.
        return [_FakeSeg(text="hello", t0=0.0, t1=0.5, confidence=0.9)]


async def _one_chunk_pcm_stream(chunk_bytes: bytes):
    yield chunk_bytes


@pytest.mark.asyncio
async def test_whisper_cpp_provider_contract(monkeypatch, tmp_path):
    """
    Provider should be importable without pywhispercpp, and when patched "available",
    it should yield ASRSegment objects with is_final=True and AudioSource source.
    """
    from server.services import provider_whisper_cpp
    from server.services.asr_providers import ASRConfig, AudioSource

    # Patch dependencies to simulate availability without requiring pywhispercpp at test time.
    model_file = tmp_path / "ggml-base.bin"
    model_file.write_bytes(b"x")
    monkeypatch.setattr(provider_whisper_cpp, "PYWHISPERCPP_AVAILABLE", True)
    monkeypatch.setattr(provider_whisper_cpp, "Model", _FakeModel, raising=False)
    monkeypatch.setattr(provider_whisper_cpp.WhisperCppProvider, "_get_model_path", lambda self: str(model_file))

    cfg = ASRConfig(model_name="base", device="metal", compute_type="fp16", chunk_seconds=1, vad_enabled=False)
    provider = provider_whisper_cpp.WhisperCppProvider(cfg)
    assert provider.name == "whisper_cpp"
    assert provider.is_available is True

    pcm_bytes = b"\x00\x00" * 16000  # 1s @ 16kHz pcm_s16le mono
    segments = []
    async for seg in provider.transcribe_stream(_one_chunk_pcm_stream(pcm_bytes), sample_rate=16000, source=AudioSource.SYSTEM):
        segments.append(seg)

    assert segments, "Expected at least one segment"
    assert all(s.is_final for s in segments)
    assert all(s.source == AudioSource.SYSTEM for s in segments)
