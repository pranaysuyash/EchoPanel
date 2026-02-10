"""
Voxtral Realtime ASR Provider (v0.1) — Local Open-Source

Implements the ASRProvider interface using antirez/voxtral.c for local inference.
No API key needed. Requires voxtral.c binary and downloaded model (~8.9GB).

Config:
    ECHOPANEL_VOXTRAL_BIN     — path to voxtral binary (default: ../voxtral.c/voxtral)
    ECHOPANEL_VOXTRAL_MODEL   — path to model dir (default: ../voxtral.c/voxtral-model)
    ECHOPANEL_ASR_PROVIDER=voxtral_realtime
"""

from __future__ import annotations

import asyncio
import logging
import os
import struct
import tempfile
import time
from pathlib import Path
from typing import AsyncIterator, Optional

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource

logger = logging.getLogger(__name__)

_PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


def _default_bin() -> Path:
    return Path(os.getenv(
        "ECHOPANEL_VOXTRAL_BIN",
        str(_PROJECT_ROOT.parent / "voxtral.c" / "voxtral"),
    ))


def _default_model() -> Path:
    return Path(os.getenv(
        "ECHOPANEL_VOXTRAL_MODEL",
        str(_PROJECT_ROOT.parent / "voxtral.c" / "voxtral-model"),
    ))


class VoxtralRealtimeProvider(ASRProvider):
    """ASR provider using voxtral.c (local, open-source, MPS/BLAS)."""

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self._bin = _default_bin()
        self._model = _default_model()

    @property
    def name(self) -> str:
        return "voxtral_realtime"

    @property
    def is_available(self) -> bool:
        return self._bin.is_file() and (self._model / "consolidated.safetensors").is_file()

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """Transcribe audio stream using voxtral.c binary."""

        if not self.is_available:
            self.log(f"Voxtral unavailable: bin={self._bin.exists()}, model={self._model.exists()}")
            yield ASRSegment(
                text="[Voxtral ASR unavailable — check ECHOPANEL_VOXTRAL_BIN and ECHOPANEL_VOXTRAL_MODEL]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return

        bytes_per_sample = 2
        chunk_seconds = self.config.chunk_seconds
        chunk_bytes = int(sample_rate * chunk_seconds * bytes_per_sample)
        buffer = bytearray()
        processed_samples = 0

        self.log(f"Started streaming via voxtral.c, chunk={chunk_seconds}s")

        async for chunk in pcm_stream:
            buffer.extend(chunk)

            while len(buffer) >= chunk_bytes:
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]

                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples

                text = await self._transcribe_chunk(audio_bytes, sample_rate)
                if text:
                    yield ASRSegment(
                        text=text,
                        t0=t0,
                        t1=t1,
                        confidence=0.9,
                        is_final=True,
                        source=source,
                    )

        if buffer:
            audio_bytes = bytes(buffer)
            del buffer[:]
            t0 = processed_samples / sample_rate
            chunk_samples = len(audio_bytes) // bytes_per_sample
            t1 = (processed_samples + chunk_samples) / sample_rate

            text = await self._transcribe_chunk(audio_bytes, sample_rate)
            if text:
                yield ASRSegment(
                    text=text,
                    t0=t0,
                    t1=t1,
                    confidence=0.9,
                    is_final=True,
                    source=source,
                )

    async def _transcribe_chunk(self, pcm_bytes: bytes, sample_rate: int) -> Optional[str]:
        """Write PCM to a temp WAV, run voxtral.c, return text."""
        tmp = None
        try:
            tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            self._write_wav(tmp.name, pcm_bytes, sample_rate)
            tmp.close()

            proc = await asyncio.create_subprocess_exec(
                str(self._bin),
                "-d", str(self._model),
                "-i", tmp.name,
                "--silent",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await proc.communicate()
            text = stdout.decode("utf-8", errors="replace").strip()
            if proc.returncode != 0:
                self.log(f"voxtral.c error (rc={proc.returncode}): {stderr.decode()[:200]}")
                return None
            return text if text else None
        except Exception as e:
            self.log(f"voxtral.c exec error: {e}")
            return None
        finally:
            if tmp:
                try:
                    os.unlink(tmp.name)
                except OSError:
                    pass

    @staticmethod
    def _write_wav(path: str, pcm_bytes: bytes, sample_rate: int) -> None:
        """Write raw PCM16 mono bytes as a valid WAV file."""
        num_channels = 1
        bits_per_sample = 16
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        data_size = len(pcm_bytes)

        with open(path, "wb") as f:
            f.write(b"RIFF")
            f.write(struct.pack("<I", 36 + data_size))
            f.write(b"WAVE")
            f.write(b"fmt ")
            f.write(struct.pack("<I", 16))
            f.write(struct.pack("<HHIIHH", 1, num_channels, sample_rate, byte_rate, block_align, bits_per_sample))
            f.write(b"data")
            f.write(struct.pack("<I", data_size))
            f.write(pcm_bytes)


ASRProviderRegistry.register("voxtral_realtime", VoxtralRealtimeProvider)
