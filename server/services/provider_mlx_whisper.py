"""
MLX Whisper ASR Provider with Metal GPU Support (Optimized)

Uses Apple's MLX framework for native Apple Silicon acceleration.
Requires: uv pip install mlx mlx-whisper

Installation:
    brew install uv
    uv pip install mlx mlx-whisper

Model Sources:
    Uses mlx-community models from HuggingFace which are pre-converted
    for MLX compatibility.

Optimizations:
    - Blocking transcribe() calls wrapped in asyncio.to_thread()
    - Explicit GPU memory management via mx.clear_cache()
    - Model caching to avoid repeated loads
"""

from __future__ import annotations

import asyncio
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import AsyncIterator, Optional

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource


# Map standard model names to mlx-community model IDs
MLX_MODEL_MAP = {
    # Standard name -> mlx-community model ID
    "tiny": "mlx-community/whisper-tiny",
    "tiny.en": "mlx-community/whisper-tiny.en-mlx",
    "base": "mlx-community/whisper-base-mlx",
    "base.en": "mlx-community/whisper-base.en-mlx",
    "small": "mlx-community/whisper-small-mlx",
    "small.en": "mlx-community/whisper-small.en-mlx",
    "medium": "mlx-community/whisper-medium-mlx",
    "medium.en": "mlx-community/whisper-medium.en-mlx",
    "large": "mlx-community/whisper-large-mlx",
    "large-v1": "mlx-community/whisper-large-v1-mlx",
    "large-v2": "mlx-community/whisper-large-v2-mlx",
    "large-v3": "mlx-community/whisper-large-v3-mlx",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
    # Quantized variants (4-bit for memory efficiency)
    "tiny-q4": "mlx-community/whisper-tiny-mlx-4bit",
    "base-q4": "mlx-community/whisper-base-mlx-4bit",
    "small-q4": "mlx-community/whisper-small-mlx-4bit",
}


class MLXWhisperProvider(ASRProvider):
    """
    ASR provider using mlx-whisper with Metal GPU acceleration.
    
    Features:
    - Native Apple Silicon (MLX framework)
    - Metal GPU acceleration
    - Pre-converted models from mlx-community
    - Smaller memory footprint than PyTorch
    - Non-blocking inference via thread pool
    - Explicit GPU memory management
    
    Note:
    - Processes audio in chunks (not true streaming)
    - Requires mlx-community models (not compatible with HF models directly)
    """

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self._infer_times: list[float] = []
        self._chunks_processed = 0
        self._model_cache_dir = Path("~/.cache/whisper-mlx").expanduser()
        self._model_path: Optional[str] = None
        self._thread_pool: Optional[ThreadPoolExecutor] = None
        
    def _get_thread_pool(self) -> ThreadPoolExecutor:
        """Get or create thread pool for blocking operations."""
        if self._thread_pool is None:
            self._thread_pool = ThreadPoolExecutor(
                max_workers=1,
                thread_name_prefix="mlx_whisper_"
            )
        return self._thread_pool
        
    def _get_model_id(self) -> str:
        """Get mlx-community model ID for the configured model."""
        model_name = self.config.model_name
        if model_name in MLX_MODEL_MAP:
            return MLX_MODEL_MAP[model_name]
        
        # Try to construct mlx-community model ID
        if not model_name.startswith("mlx-community/"):
            return f"mlx-community/whisper-{model_name}"
        return model_name

    def _ensure_model(self) -> Optional[str]:
        """Download and cache model from mlx-community."""
        if self._model_path is not None:
            return self._model_path
        
        model_id = self._get_model_id()
        
        try:
            from huggingface_hub import snapshot_download
            
            self.log(f"Downloading {model_id}...")
            t0 = time.perf_counter()
            
            model_path = snapshot_download(
                repo_id=model_id,
                cache_dir=str(self._model_cache_dir),
            )
            
            download_time = time.perf_counter() - t0
            self.log(f"Model ready in {download_time:.1f}s: {model_path}")
            
            self._model_path = model_path
            return model_path
                
        except Exception as e:
            self.log(f"Error downloading model: {e}")
            return None

    @property
    def name(self) -> str:
        return "mlx_whisper"

    @property
    def is_available(self) -> bool:
        """Check if mlx-whisper and Metal are available."""
        try:
            import mlx_whisper
            import mlx.core as mx
            return mx.metal.is_available()
        except ImportError:
            return False

    def _transcribe_sync(
        self,
        audio_array,
        model_path: str,
    ) -> dict:
        """
        Synchronous transcription - runs in thread pool.
        
        This is the blocking call that must not run on the event loop.
        """
        import mlx_whisper
        
        return mlx_whisper.transcribe(
            audio_array,
            path_or_hf_repo=model_path,
            language=self.config.language or "en",
            task="transcribe",
        )

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """
        Transcribe audio stream using mlx-whisper.
        
        Accumulates PCM chunks and processes in batches.
        All blocking operations run in thread pool to avoid event loop blocking.
        """
        if not self.is_available:
            yield ASRSegment(
                text="[mlx-whisper unavailable - install: uv pip install mlx mlx-whisper]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return

        import numpy as np
        
        # Ensure model is ready (in thread pool since HF download can block)
        loop = asyncio.get_event_loop()
        model_path = await loop.run_in_executor(
            self._get_thread_pool(),
            self._ensure_model
        )
        
        if model_path is None:
            yield ASRSegment(
                text="[mlx-whisper: failed to load model]",
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
        
        self.log(f"Starting streaming, chunk_bytes={chunk_bytes} ({chunk_seconds}s)")
        
        async for chunk in pcm_stream:
            buffer.extend(chunk)
            
            # Process when we have a full chunk
            while len(buffer) >= chunk_bytes:
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]
                
                # Calculate timestamps
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples
                
                # Convert to numpy float32
                audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
                
                try:
                    infer_start = time.perf_counter()
                    
                    # Run blocking transcribe in thread pool
                    result = await loop.run_in_executor(
                        self._get_thread_pool(),
                        self._transcribe_sync,
                        audio_array,
                        model_path,
                    )
                    
                    infer_time = time.perf_counter() - infer_start
                    self._infer_times.append(infer_time)
                    self._chunks_processed += 1
                    
                    # Extract text
                    text = result.get("text", "").strip()
                    
                    if text:
                        yield ASRSegment(
                            text=text,
                            t0=t0,
                            t1=t1,
                            confidence=0.9,  # mlx-whisper doesn't provide per-segment confidence
                            is_final=True,
                            source=source,
                            language=result.get("language"),
                        )
                        
                except Exception as e:
                    self.log(f"Transcription error: {e}")
                    yield ASRSegment(
                        text=f"[transcription error]",
                        t0=t0,
                        t1=t1,
                        confidence=0,
                        is_final=True,
                        source=source,
                    )
        
        # Process any remaining buffer
        if buffer:
            t0 = processed_samples / sample_rate
            chunk_samples = len(buffer) // bytes_per_sample
            t1 = (processed_samples + chunk_samples) / sample_rate
            
            audio_array = np.frombuffer(buffer, dtype=np.int16).astype(np.float32) / 32768.0
            
            try:
                result = await loop.run_in_executor(
                    self._get_thread_pool(),
                    self._transcribe_sync,
                    audio_array,
                    model_path,
                )
                
                text = result.get("text", "").strip()
                if text:
                    yield ASRSegment(
                        text=text,
                        t0=t0,
                        t1=t1,
                        confidence=0.9,
                        is_final=True,
                        source=source,
                        language=result.get("language"),
                    )
            except Exception as e:
                self.log(f"Final chunk error: {e}")

    async def health(self) -> dict:
        """Return health metrics."""
        if not self._infer_times:
            return {
                "status": "idle",
                "realtime_factor": 0.0,
                "chunks_processed": 0,
            }
        
        avg_infer = sum(self._infer_times) / len(self._infer_times)
        chunk_seconds = self.config.chunk_seconds
        rtf = avg_infer / chunk_seconds if chunk_seconds > 0 else 0
        
        return {
            "status": "active",
            "realtime_factor": rtf,
            "chunks_processed": self._chunks_processed,
            "avg_infer_ms": avg_infer * 1000,
            "model_cached": self._model_path is not None,
        }

    async def unload(self) -> None:
        """
        Clean up resources.
        
        Explicitly clears MLX GPU cache to free memory.
        """
        try:
            import mlx.core as mx
            # Clear MLX cache to free GPU memory
            if mx.metal.is_available():
                mx.clear_cache()
                self.log("MLX cache cleared")
        except ImportError:
            pass
        
        # Shutdown thread pool
        if self._thread_pool is not None:
            self._thread_pool.shutdown(wait=True)
            self._thread_pool = None
        
        self._model_path = None
        self._infer_times.clear()
        self._chunks_processed = 0
        await super().unload()


# Register the provider
ASRProviderRegistry.register("mlx_whisper", MLXWhisperProvider)
