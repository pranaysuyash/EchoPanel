"""
Voxtral Realtime ASR Provider (v0.2) — Local Open-Source, Streaming Mode

Implements the ASRProvider interface using antirez/voxtral.c for local inference.
Uses --stdin streaming mode to keep the model resident (fixes subprocess-per-chunk bug).

No API key needed. Requires voxtral.c binary and downloaded model (~8.9GB).

Config:
    ECHOPANEL_VOXTRAL_BIN        — path to voxtral binary (default: ../voxtral.c/voxtral)
    ECHOPANEL_VOXTRAL_MODEL      — path to model dir (default: ../voxtral.c/voxtral-model)
    ECHOPANEL_VOXTRAL_STREAMING_DELAY — streaming delay in seconds (default: 0.5)
    ECHOPANEL_ASR_PROVIDER=voxtral_realtime

Changes in v0.2:
    - Rewritten to use --stdin streaming mode (model stays resident)
    - Added session lifecycle management (start/stop streaming process)
    - Added per-chunk latency tracking and health metrics
    - Removed subprocess-per-chunk architecture (was causing ~11s load per chunk)
"""

from __future__ import annotations

import asyncio
import logging
import os
import re
import time
from pathlib import Path
from typing import AsyncIterator, Optional, Tuple
from dataclasses import dataclass

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource, ProviderCapabilities

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


def _streaming_delay() -> float:
    """Streaming delay in seconds (lower = lower latency, higher = better accuracy)."""
    return float(os.getenv("ECHOPANEL_VOXTRAL_STREAMING_DELAY", "0.5"))


@dataclass
class StreamingSession:
    """Manages a resident voxtral.c process for streaming transcription."""
    process: asyncio.subprocess.Process
    started_at: float
    chunk_seconds: float
    chunks_processed: int = 0
    total_infer_ms: float = 0.0
    
    @property
    def avg_infer_ms(self) -> float:
        if self.chunks_processed == 0:
            return 0.0
        return self.total_infer_ms / self.chunks_processed
    
    @property
    def realtime_factor(self) -> float:
        """RTF based on average inference time per configured chunk size."""
        if self.chunks_processed == 0:
            return 0.0
        avg_infer_s = self.avg_infer_ms / 1000.0
        return avg_infer_s / max(self.chunk_seconds, 0.001)


class VoxtralRealtimeProvider(ASRProvider):
    """ASR provider using voxtral.c in streaming mode (local, open-source, MPS/BLAS).
    
    v0.2 rewrite: Uses --stdin streaming mode to keep model resident.
    Previous versions spawned a new subprocess per chunk (~11s penalty each).
    """

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        self._bin = _default_bin()
        self._model = _default_model()
        self._streaming_delay = _streaming_delay()
        self._session: Optional[StreamingSession] = None
        self._session_lock = asyncio.Lock()

    @property
    def name(self) -> str:
        return "voxtral_realtime"

    @property
    def is_available(self) -> bool:
        return self._bin.is_file() and (self._model / "consolidated.safetensors").is_file()
    
    @property
    def capabilities(self) -> ProviderCapabilities:
        """Report provider capabilities.
        
        Voxtral supports Metal on macOS for GPU acceleration.
        """
        return ProviderCapabilities(
            supports_streaming=True,  # True streaming with --stdin mode
            supports_batch=True,
            supports_gpu=True,
            supports_metal=True,  # ✅ Metal support on Apple Silicon
            supports_cuda=False,
            supports_vad=False,
            supports_diarization=False,
            supports_multilanguage=True,
            min_ram_gb=4.0,
            recommended_ram_gb=8.0,
        )

    async def _start_session(self) -> StreamingSession:
        """Start voxtral.c in streaming mode with --stdin.
        
        The process stays resident and reads PCM audio from stdin.
        Output format: Each transcription result is printed to stdout as text.
        """
        if not self.is_available:
            raise RuntimeError(f"Voxtral unavailable: bin={self._bin.exists()}, model={self._model.exists()}")
        
        # Build command: voxtral -d model --stdin -I <delay>
        # --stdin: read PCM audio from stdin
        # -I: streaming delay in seconds (e.g., 0.5 = 500ms)
        cmd = [
            str(self._bin),
            "-d", str(self._model),
            "--stdin",
            "-I", str(self._streaming_delay),
            "--silent",  # Suppress progress output, only emit transcriptions
        ]
        
        self.log(f"Starting voxtral.c streaming session: delay={self._streaming_delay}s")
        t0 = time.perf_counter()
        
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except Exception as e:
            raise RuntimeError(f"Failed to start voxtral.c: {e}")
        
        # Wait for model to load (parse stderr for "Metal GPU" or similar ready signal)
        # This is typically the slow part (~10-60s for large models like 4B/8B on first load)
        ready = await self._wait_for_ready(process, timeout=120.0)
        load_time = time.perf_counter() - t0
        
        if not ready:
            process.kill()
            await process.wait()
            raise RuntimeError(f"voxtral.c failed to become ready after {load_time:.1f}s")
        
        self.log(f"Voxtral streaming session ready in {load_time:.2f}s")
        
        return StreamingSession(
            process=process,
            started_at=time.perf_counter(),
            chunk_seconds=float(self.config.chunk_seconds),
        )

    async def _wait_for_ready(self, process: asyncio.subprocess.Process, timeout: float) -> bool:
        """Wait for voxtral.c to finish loading and signal readiness.
        
        Looks for indicators in stdout/stderr like "Metal:" or "Model loaded" that indicate
        the model is loaded and ready for inference.
        """
        ready_patterns = [
            b"Model loaded.",  # Definitive ready signal (appears after all layers loaded)
            b"Metal:",         # MPS/Metal backend ready (voxtral outputs "Metal: GPU...")
            b"BLAS",           # CPU BLAS backend ready
            b"Ready",          # Generic ready signal
        ]
        
        start_time = time.perf_counter()
        stdout_buffer = b""
        stderr_buffer = b""
        
        while time.perf_counter() - start_time < timeout:
            # Try reading from stdout first (voxtral outputs to stdout)
            if process.stdout:
                try:
                    chunk = await asyncio.wait_for(
                        process.stdout.read(1024),
                        timeout=0.5
                    )
                    if chunk:
                        stdout_buffer += chunk
                        # Check for ready signals
                        for pattern in ready_patterns:
                            if pattern in stdout_buffer:
                                self.log(f"Voxtral ready signal detected: {pattern.decode()}")
                                return True
                except asyncio.TimeoutError:
                    pass
            
            # Also check stderr
            if process.stderr:
                try:
                    chunk = await asyncio.wait_for(
                        process.stderr.read(1024),
                        timeout=0.5
                    )
                    if chunk:
                        stderr_buffer += chunk
                        for pattern in ready_patterns:
                            if pattern in stderr_buffer:
                                self.log(f"Voxtral ready signal detected: {pattern.decode()}")
                                return True
                except asyncio.TimeoutError:
                    pass
            
            # Check if process is still alive
            if process.returncode is not None:
                return False
        
        return False  # Timeout

    async def _stop_session(self) -> None:
        """Clean up the streaming session."""
        async with self._session_lock:
            if self._session is None:
                return
            
            session = self._session
            self._session = None
            
            self.log(f"Stopping voxtral.c session: {session.chunks_processed} chunks, "
                    f"avg infer={session.avg_infer_ms:.1f}ms, "
                    f"RTF={session.realtime_factor:.3f}x")
            
            if session.process.returncode is None:
                # Graceful shutdown: close stdin, wait for process to exit
                try:
                    if session.process.stdin:
                        session.process.stdin.close()
                    await asyncio.wait_for(session.process.wait(), timeout=5.0)
                except asyncio.TimeoutError:
                    self.log("Voxtral process did not exit gracefully, killing...")
                    session.process.kill()
                    await session.process.wait()

    async def _ensure_session(self) -> StreamingSession:
        """Get existing session or start a new one."""
        async with self._session_lock:
            if self._session is None or self._session.process.returncode is not None:
                self._session = await self._start_session()
            return self._session

    async def _write_chunk(self, session: StreamingSession, pcm_bytes: bytes, sample_rate: int) -> None:
        """Write a PCM chunk to voxtral.c stdin.
        
        voxtral.c expects raw PCM16 mono data at 16kHz.
        """
        if session.process.stdin is None or session.process.returncode is not None:
            raise RuntimeError("Voxtral process not ready")
        
        # voxtral.c expects continuous PCM stream
        # No framing needed - just raw bytes
        try:
            session.process.stdin.write(pcm_bytes)
            await session.process.stdin.drain()
        except (BrokenPipeError, ConnectionResetError) as e:
            raise RuntimeError(f"Voxtral process pipe broken: {e}")

    async def _read_transcription(self, session: StreamingSession, timeout: float = 10.0) -> Optional[str]:
        """Read a transcription result from voxtral.c stdout.
        
        Returns the transcribed text, or None if timeout/no output.
        Output format from voxtral.c: plain text lines (one per utterance).
        """
        if session.process.stdout is None:
            return None
        
        try:
            # Read line from stdout (voxtral.c prints transcriptions as lines)
            line = await asyncio.wait_for(
                session.process.stdout.readline(),
                timeout=timeout
            )
            if not line:
                return None
            
            text = line.decode("utf-8", errors="replace").strip()
            
            # Parse timing info from stderr if available (for metrics)
            # This is done asynchronously - we don't block on it
            return text if text else None
            
        except asyncio.TimeoutError:
            return None

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """Transcribe audio stream using voxtral.c in streaming mode.
        
        Keeps the model resident throughout the session for real-time performance.
        """
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
        
        session: Optional[StreamingSession] = None
        
        try:
            # Ensure session is started
            session = await self._ensure_session()
            self.log(f"Started streaming via voxtral.c (streaming mode), chunk={chunk_seconds}s")
            
            # Task to read transcriptions from stdout
            pending_transcriptions: asyncio.Queue[Tuple[int, int, str]] = asyncio.Queue()
            read_task: Optional[asyncio.Task] = None
            
            async def read_loop():
                """Background task to read transcriptions from stdout."""
                while session and session.process.returncode is None:
                    try:
                        text = await self._read_transcription(session, timeout=0.5)
                        if text:
                            # Store with current sample position
                            await pending_transcriptions.put((
                                processed_samples,
                                text
                            ))
                    except Exception as e:
                        self.log(f"Read loop error: {e}")
                        break
            
            # Start background reader
            read_task = asyncio.create_task(read_loop())
            
            async for chunk in pcm_stream:
                buffer.extend(chunk)
                
                # Send complete chunks to voxtral.c
                while len(buffer) >= chunk_bytes:
                    audio_bytes = bytes(buffer[:chunk_bytes])
                    del buffer[:chunk_bytes]
                    
                    t0 = processed_samples / sample_rate
                    chunk_samples = len(audio_bytes) // bytes_per_sample
                    t1 = (processed_samples + chunk_samples) / sample_rate
                    
                    # Write chunk to streaming process
                    infer_start = time.perf_counter()
                    try:
                        await self._write_chunk(session, audio_bytes, sample_rate)
                        session.chunks_processed += 1
                    except RuntimeError as e:
                        self.log(f"Write error, restarting session: {e}")
                        # Try to recover by restarting session
                        await self._stop_session()
                        session = await self._ensure_session()
                        await self._write_chunk(session, audio_bytes, sample_rate)
                        session.chunks_processed += 1
                    
                    infer_ms = (time.perf_counter() - infer_start) * 1000
                    session.total_infer_ms += infer_ms
                    
                    processed_samples += chunk_samples
                    
                    # Check for any completed transcriptions
                    while not pending_transcriptions.empty():
                        try:
                            _, text = pending_transcriptions.get_nowait()
                            yield ASRSegment(
                                text=text,
                                t0=t0,
                                t1=t1,
                                confidence=0.9,
                                is_final=True,
                                source=source,
                            )
                        except asyncio.QueueEmpty:
                            break
            
            # Flush remaining buffer
            if buffer:
                audio_bytes = bytes(buffer)
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                
                try:
                    await self._write_chunk(session, audio_bytes, sample_rate)
                    session.chunks_processed += 1
                except RuntimeError as e:
                    self.log(f"Write error on final chunk: {e}")
                
                processed_samples += chunk_samples
            
            # Allow time for final transcriptions
            await asyncio.sleep(self._streaming_delay + 0.5)
            
            # Drain remaining transcriptions
            if read_task:
                read_task.cancel()
                try:
                    await read_task
                except asyncio.CancelledError:
                    pass
            
            while not pending_transcriptions.empty():
                try:
                    _, text = pending_transcriptions.get_nowait()
                    yield ASRSegment(
                        text=text,
                        t0=0,  # Timing lost for buffered transcriptions
                        t1=0,
                        confidence=0.9,
                        is_final=True,
                        source=source,
                    )
                except asyncio.QueueEmpty:
                    break
            
            # Log session stats
            if session:
                self.log(f"Session complete: {session.chunks_processed} chunks, "
                        f"RTF={session.realtime_factor:.3f}x, "
                        f"avg_infer={session.avg_infer_ms:.1f}ms")
                
        except Exception as e:
            self.log(f"Streaming error: {e}")
            raise
        finally:
            # Clean up session
            await self._stop_session()

    async def health(self) -> dict:
        """Return health metrics for the provider."""
        async with self._session_lock:
            if self._session is None:
                return {
                    "status": "idle",
                    "realtime_factor": 0.0,
                    "chunks_processed": 0,
                }
            
            session = self._session
            return {
                "status": "active" if session.process.returncode is None else "error",
                "realtime_factor": session.realtime_factor,
                "chunks_processed": session.chunks_processed,
                "avg_infer_ms": session.avg_infer_ms,
                "session_duration_s": time.perf_counter() - session.started_at,
            }

    async def unload(self) -> None:
        """Stop any active streaming session and clear residency markers."""
        await self._stop_session()
        await super().unload()


ASRProviderRegistry.register("voxtral_realtime", VoxtralRealtimeProvider)
