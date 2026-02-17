"""
Whisper.cpp ASR Provider with Metal GPU Support

Uses whisper.cpp via subprocess with --stdin streaming mode.
Optimized for Apple Silicon (M1/M2/M3/M4) with Metal GPU acceleration.

Installation:
    brew install whisper-cpp
    # Download models:
    curl -L -o ~/.cache/whisper/ggml-base.en.bin \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

Environment:
    WHISPER_CPP_BIN: Path to whisper-cli (default: whisper-cli)
    WHISPER_CPP_MODEL_DIR: Model directory (default: ~/.cache/whisper)
"""

from __future__ import annotations

import asyncio
import os
import platform
import re
import subprocess
import time
from pathlib import Path
from typing import AsyncIterator, Optional

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource


class WhisperCppProvider(ASRProvider):
    """
    ASR provider using whisper.cpp with Metal GPU acceleration.
    
    Features:
    - Metal GPU support on Apple Silicon (M1/M2/M3/M4)
    - Streaming mode via --stdin
    - Smaller model sizes (GGML format)
    - C++ performance
    """

    # Model registry for UI/testing
    MODELS = {
        "tiny": {"file": "ggml-tiny.bin", "memory_mb": 75, "description": "Fastest, basic accuracy"},
        "tiny.en": {"file": "ggml-tiny.en.bin", "memory_mb": 75, "description": "Fastest, English only"},
        "base": {"file": "ggml-base.bin", "memory_mb": 142, "description": "Balanced speed & accuracy"},
        "base.en": {"file": "ggml-base.en.bin", "memory_mb": 142, "description": "Balanced, English only"},
        "small": {"file": "ggml-small.bin", "memory_mb": 466, "description": "Better accuracy"},
        "small.en": {"file": "ggml-small.en.bin", "memory_mb": 466, "description": "Better, English only"},
        "medium": {"file": "ggml-medium.bin", "memory_mb": 1500, "description": "High accuracy"},
        "medium.en": {"file": "ggml-medium.en.bin", "memory_mb": 1500, "description": "High, English only"},
        "large-v1": {"file": "ggml-large-v1.bin", "memory_mb": 3000, "description": "Best accuracy"},
        "large-v2": {"file": "ggml-large-v2.bin", "memory_mb": 3000, "description": "Best accuracy"},
        "large-v3": {"file": "ggml-large-v3.bin", "memory_mb": 3100, "description": "Best accuracy"},
        "large-v3-turbo": {"file": "ggml-large-v3-turbo.bin", "memory_mb": 1600, "description": "Best accuracy, faster"},
    }

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self.bin_path = os.getenv("WHISPER_CPP_BIN", "whisper-cli")
        self.model_dir = Path(os.getenv("WHISPER_CPP_MODEL_DIR", "~/.cache/whisper")).expanduser()
        self.model_path = self._get_model_path()
        self._process: Optional[asyncio.subprocess.Process] = None
        self._session_lock = asyncio.Lock()
        self._infer_times: list[float] = []
        self._chunks_processed = 0
        
    def _get_model_path(self) -> Path:
        """Get GGML model path from config."""
        model_name = self.config.model_name
        
        # Use MODELS registry if available
        if model_name in self.MODELS:
            ggml_file = self.MODELS[model_name]["file"]
        else:
            ggml_file = f"ggml-{model_name}.bin"
        
        return self.model_dir / ggml_file

    @property
    def name(self) -> str:
        return "whisper_cpp"

    @property
    def is_available(self) -> bool:
        """Check if whisper.cpp is installed and model exists."""
        # Check model first
        if not self.model_path.exists():
            return False
        
        # Check binary
        try:
            result = subprocess.run(
                [self.bin_path, "--help"],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except Exception:
            return False

    @property
    def capabilities(self):
        """Override capabilities for whisper.cpp."""
        from .asr_providers import ProviderCapabilities
        return ProviderCapabilities(
            supports_streaming=True,
            supports_batch=True,
            supports_gpu=self._is_apple_silicon(),
            supports_metal=self._is_apple_silicon(),
            supports_cuda=False,
            supports_vad=False,
            supports_diarization=False,
            supports_multilanguage=True,
            min_ram_gb=2.0,
            recommended_ram_gb=4.0,
        )

    def _is_apple_silicon(self) -> bool:
        """Check if running on Apple Silicon."""
        return platform.system() == "Darwin" and platform.machine() == "arm64"

    def _get_optimal_threads(self) -> int:
        """Get optimal thread count for the system."""
        cpu_count = os.cpu_count() or 4
        if self._is_apple_silicon():
            # Apple Silicon: use performance cores
            return min(cpu_count // 2, 8)
        return min(cpu_count, 8)

    def get_performance_stats(self) -> dict:
        """Get performance statistics."""
        if not self._infer_times:
            return {
                "avg_inference_ms": 0.0,
                "realtime_factor": 0.0,
                "chunks_processed": 0,
            }
        
        avg_infer = sum(self._infer_times) / len(self._infer_times)
        chunk_seconds = self.config.chunk_seconds
        rtf = avg_infer / chunk_seconds if chunk_seconds > 0 else 0
        
        return {
            "avg_inference_ms": avg_infer * 1000,
            "realtime_factor": rtf,
            "chunks_processed": self._chunks_processed,
        }
    
    async def _check_binary(self) -> bool:
        """Check if whisper-cli binary is available."""
        try:
            proc = await asyncio.create_subprocess_exec(
                self.bin_path, "--help",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            return proc.returncode == 0
        except Exception:
            return False

    async def _start_session(self) -> asyncio.subprocess.Process:
        """Start whisper.cpp in streaming mode."""
        if not self.model_path.exists():
            raise RuntimeError(f"Model not found: {self.model_path}")
        
        # Build command
        cmd = [
            self.bin_path,
            "-m", str(self.model_path),
            "--stdin",
            "-l", self.config.language or "en",
            "--no-timestamps",
            "--output-txt",  # Simple text output
        ]
        
        # Add GPU layers for Metal (default: use GPU)
        if platform.system() == "Darwin" and platform.machine() == "arm64":
            cmd.extend(["-ng", "99"])  # Use all GPU layers
        
        # Add threads for CPU
        if self.config.n_threads:
            cmd.extend(["-t", str(self.config.n_threads)])
        
        self.log(f"Starting whisper.cpp: {' '.join(cmd)}")
        t0 = time.perf_counter()
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        
        load_time = time.perf_counter() - t0
        self.log(f"whisper.cpp started in {load_time:.2f}s")
        
        return process

    async def _ensure_session(self) -> asyncio.subprocess.Process:
        """Get or create streaming session."""
        async with self._session_lock:
            if self._process is None or self._process.returncode is not None:
                self._process = await self._start_session()
            return self._process

    async def _stop_session(self) -> None:
        """Clean up streaming session."""
        async with self._session_lock:
            if self._process is None:
                return
            
            process = self._process
            self._process = None
            
            if process.returncode is None:
                try:
                    process.stdin.close()
                    await asyncio.wait_for(process.wait(), timeout=5.0)
                except (asyncio.TimeoutError, ProcessLookupError):
                    process.kill()
                    await process.wait()

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """
        Transcribe audio stream using whisper.cpp.
        
        Note: whisper.cpp processes full audio files, not true streaming chunks.
        We accumulate chunks and process when we have enough data.
        """
        if not self.is_available:
            yield ASRSegment(
                text="[whisper.cpp unavailable - check installation]",
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
        chunk_count = 0
        
        self.log(f"Starting streaming, chunk_bytes={chunk_bytes} ({chunk_seconds}s)")
        
        async for chunk in pcm_stream:
            buffer.extend(chunk)
            
            # Process when we have a full chunk
            while len(buffer) >= chunk_bytes:
                chunk_count += 1
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]
                
                # Calculate timestamps
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples
                
                # Write to temp WAV file (whisper.cpp needs WAV format)
                import tempfile
                import wave
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                    temp_path = f.name
                
                # Write as proper WAV file
                with wave.open(temp_path, 'wb') as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)  # 16-bit
                    wav.setframerate(sample_rate)
                    wav.writeframes(audio_bytes)
                
                try:
                    infer_start = time.perf_counter()
                    
                    # Run whisper.cpp on this chunk
                    proc = await asyncio.create_subprocess_exec(
                        self.bin_path,
                        "-m", str(self.model_path),
                        "-f", temp_path,
                        "-l", self.config.language or "en",
                        "--no-timestamps",
                        "--output-txt",
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE,
                    )
                    
                    stdout, stderr = await proc.communicate()
                    infer_time = time.perf_counter() - infer_start
                    
                    self._infer_times.append(infer_time)
                    self._chunks_processed += 1
                    
                    # Parse output
                    text = stdout.decode("utf-8", errors="replace").strip()
                    
                    # Remove timing info if present
                    text = re.sub(r'\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]\s*', '', text)
                    
                    if text:
                        yield ASRSegment(
                            text=text,
                            t0=t0,
                            t1=t1,
                            confidence=0.9,  # whisper.cpp doesn't provide confidence
                            is_final=True,
                            source=source,
                        )
                    
                finally:
                    os.unlink(temp_path)
        
        # Process any remaining buffer
        if buffer:
            t0 = processed_samples / sample_rate
            chunk_samples = len(buffer) // bytes_per_sample
            t1 = (processed_samples + chunk_samples) / sample_rate
            
            # Write as proper WAV file
            import tempfile
            import wave
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                temp_path = f.name
            
            with wave.open(temp_path, 'wb') as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(sample_rate)
                wav.writeframes(bytes(buffer))
            
            try:
                proc = await asyncio.create_subprocess_exec(
                    self.bin_path,
                    "-m", str(self.model_path),
                    "-f", temp_path,
                    "-l", self.config.language or "en",
                    "--no-timestamps",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                
                stdout, _ = await proc.communicate()
                text = stdout.decode("utf-8", errors="replace").strip()
                text = re.sub(r'\[\d{2}:\d{2}:\d{2}\.\d{3} --> \d{2}:\d{2}:\d{2}\.\d{3}\]\s*', '', text)
                
                if text:
                    yield ASRSegment(
                        text=text,
                        t0=t0,
                        t1=t1,
                        confidence=0.9,
                        is_final=True,
                        source=source,
                    )
            finally:
                os.unlink(temp_path)

    async def health(self) -> dict:
        """Return health metrics."""
        if self._chunks_processed == 0:
            return {
                "status": "idle",
                "realtime_factor": 0.0,
                "chunks_processed": 0,
            }
        
        avg_infer = sum(self._infer_times) / len(self._infer_times) if self._infer_times else 0
        chunk_seconds = self.config.chunk_seconds
        rtf = avg_infer / chunk_seconds if chunk_seconds > 0 else 0
        
        return {
            "status": "active" if self._process and self._process.returncode is None else "idle",
            "realtime_factor": rtf,
            "chunks_processed": self._chunks_processed,
            "avg_infer_ms": avg_infer * 1000,
            "model_path": str(self.model_path),
            "model_exists": self.model_path.exists(),
        }

    async def unload(self) -> None:
        """Stop session and clean up."""
        await self._stop_session()
        await super().unload()


# Register the provider
ASRProviderRegistry.register("whisper_cpp", WhisperCppProvider)
