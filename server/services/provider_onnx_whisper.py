"""
ONNX Whisper ASR Provider with CoreML Support

Uses ONNX Runtime with CoreMLExecutionProvider for Apple Neural Engine support.

Installation:
    uv pip install onnxruntime-silicon  # For Apple Silicon
    # OR
    uv pip install onnxruntime  # General

Model Conversion:
    Models must be converted from PyTorch to ONNX format.
    See: https://huggingface.co/docs/optimum/main/en/onnxruntime/usage_guides/models
"""

from __future__ import annotations

import asyncio
import os
import time
from pathlib import Path
from typing import AsyncIterator, Optional

import numpy as np

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource


class ONNXWhisperProvider(ASRProvider):
    """
    ASR provider using ONNX Runtime with CoreML support.
    
    Features:
    - CoreML execution provider on macOS (Apple Neural Engine)
    - CPU fallback
    - Optimized for edge inference
    
    Limitations:
    - Requires ONNX-converted models
    - Not true streaming (encoder-decoder architecture)
    """

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self._infer_times: list[float] = []
        self._chunks_processed = 0
        self._session = None
        self._model_dir = Path(os.getenv("WHISPER_ONNX_MODEL_DIR", "~/.cache/whisper-onnx")).expanduser()
        
    def _get_model_path(self) -> Optional[Path]:
        """Get path to ONNX model."""
        model_name = self.config.model_name
        
        # Try different naming conventions
        possible_paths = [
            self._model_dir / model_name / "model.onnx",
            self._model_dir / f"whisper-{model_name}" / "model.onnx",
            self._model_dir / f"{model_name}.onnx",
            Path(model_name),  # If full path provided
        ]
        
        for path in possible_paths:
            if path.exists() and path.suffix == ".onnx":
                return path
        
        return None

    def _load_model(self) -> bool:
        """Load ONNX model with appropriate execution provider."""
        try:
            import onnxruntime as ort
            
            model_path = self._get_model_path()
            if model_path is None:
                self.log(f"ONNX model not found for {self.config.model_name}")
                return False
            
            # Select execution providers
            providers = ['CoreMLExecutionProvider', 'CPUExecutionProvider']
            
            # Check available providers
            available = ort.get_available_providers()
            self.log(f"Available ONNX providers: {available}")
            
            # Filter to only available providers
            providers = [p for p in providers if p in available]
            if not providers:
                providers = ['CPUExecutionProvider']
            
            self.log(f"Using providers: {providers}")
            
            # Load session
            self._session = ort.InferenceSession(
                str(model_path),
                providers=providers
            )
            
            self.log(f"ONNX model loaded: {model_path}")
            return True
            
        except ImportError:
            self.log("onnxruntime not installed")
            return False
        except Exception as e:
            self.log(f"Error loading ONNX model: {e}")
            return False

    @property
    def name(self) -> str:
        return "onnx_whisper"

    @property
    def is_available(self) -> bool:
        """Check if ONNX Runtime is available."""
        try:
            import onnxruntime as ort
            # Check if we have a valid model
            return self._get_model_path() is not None
        except ImportError:
            return False

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """
        Transcribe audio stream using ONNX Runtime.
        
        Note: Whisper ONNX models are typically encoder-decoder and process
        full audio. We accumulate chunks and process in batches.
        """
        if not self.is_available:
            yield ASRSegment(
                text="[onnx-whisper unavailable - install: uv pip install onnxruntime-silicon]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return

        # Load model if not already loaded
        if self._session is None:
            loaded = await asyncio.to_thread(self._load_model)
            if not loaded:
                yield ASRSegment(
                    text="[onnx-whisper: failed to load model]",
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
                
                # Convert to numpy
                audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0
                
                try:
                    infer_start = time.perf_counter()
                    
                    # TODO: Implement ONNX inference
                    # This requires proper preprocessing (mel spectrogram)
                    # and postprocessing (token decoding)
                    
                    # Placeholder: Simulate inference
                    await asyncio.sleep(0.1)  # Simulated inference time
                    text = "[ONNX inference not yet implemented]"
                    
                    infer_time = time.perf_counter() - infer_start
                    self._infer_times.append(infer_time)
                    self._chunks_processed += 1
                    
                    if text:
                        yield ASRSegment(
                            text=text,
                            t0=t0,
                            t1=t1,
                            confidence=0.9,
                            is_final=True,
                            source=source,
                        )
                        
                except Exception as e:
                    self.log(f"Transcription error: {e}")
                    yield ASRSegment(
                        text=f"[transcription error: {e}]",
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
            
            yield ASRSegment(
                text="[Final chunk - ONNX not fully implemented]",
                t0=t0,
                t1=t1,
                confidence=0,
                is_final=True,
                source=source,
            )

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
            "status": "active" if self._session else "idle",
            "realtime_factor": rtf,
            "chunks_processed": self._chunks_processed,
            "avg_infer_ms": avg_infer * 1000,
            "model_loaded": self._session is not None,
        }

    async def unload(self) -> None:
        """Clean up."""
        self._session = None
        self._infer_times.clear()
        self._chunks_processed = 0
        await super().unload()


# Register the provider
ASRProviderRegistry.register("onnx_whisper", ONNXWhisperProvider)
