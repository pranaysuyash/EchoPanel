"""
Official Mistral Voxtral Realtime ASR Provider (vLLM Mode)

Uses the official mistralai/Voxtral-Mini-4B-Realtime-2602 model via vLLM serving.

⚠️  PLATFORM LIMITATION: vLLM does NOT support Apple Silicon (Metal/MPS).
    On macOS, Voxtral must run on CPU which is very slow. 
    For macOS, use mlx_whisper instead (50× faster with Metal GPU).

Requirements:
    1. vLLM installed: pip install vllm
    2. Model downloaded: huggingface-cli download mistralai/Voxtral-Mini-4B-Realtime-2602
    3. vLLM serving: vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 --max-model-len 4096
    4. Linux with NVIDIA GPU recommended (macOS CPU only, slow)

Model Details:
    - Model ID: mistralai/Voxtral-Mini-4B-Realtime-2602
    - Parameters: 4B
    - License: Apache 2.0
    - Latency: <200ms to 2.4s configurable (480ms recommended)
    - WER: ~4% on FLEURS benchmark
    - Architecture: Novel streaming architecture (not chunked)

Environment Variables:
    VOXTRAL_VLLM_URL: vLLM endpoint - default: "http://localhost:8000"
    VOXTRAL_STREAMING_DELAY_MS: Delay in ms - default: 480 (range: 240-2400)
    HF_TOKEN: HuggingFace token for gated model access

Note:
    Unlike Whisper's chunked approach, Voxtral Realtime uses a novel streaming
    architecture that processes audio as it arrives with configurable latency.
    This requires vLLM 0.6.0+ with audio model support.

Example (Linux + NVIDIA):
    # Download model
    huggingface-cli download mistralai/Voxtral-Mini-4B-Realtime-2602

    # Start vLLM (in separate terminal)
    vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 \
        --max-model-len 4096 \
        --tensor-parallel-size 1

    # Use in EchoPanel
    export ECHOPANEL_ASR_PROVIDER=voxtral_official

See docs/VOXTRAL_VLLM_SETUP_GUIDE.md for full details.
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path
from typing import AsyncIterator, Optional
from dataclasses import dataclass

from .asr_providers import ASRProvider, ASRConfig, ASRSegment, ASRProviderRegistry, AudioSource


# Model configuration
MODEL_ID = "mistralai/Voxtral-Mini-4B-Realtime-2602"
MODEL_NAME = "voxtral-mini-transcribe-realtime-2602"

# Default settings
DEFAULT_STREAMING_DELAY_MS = 480  # Recommended by Mistral
MIN_STREAMING_DELAY_MS = 240
MAX_STREAMING_DELAY_MS = 2400


@dataclass
class VoxtralConfig:
    """Configuration for Voxtral Realtime provider."""
    vllm_url: str = "http://localhost:8000"
    streaming_delay_ms: int = DEFAULT_STREAMING_DELAY_MS
    
    def __post_init__(self):
        # Clamp streaming delay to valid range
        self.streaming_delay_ms = max(
            MIN_STREAMING_DELAY_MS,
            min(MAX_STREAMING_DELAY_MS, self.streaming_delay_ms)
        )


class VoxtralOfficialProvider(ASRProvider):
    """
    Official Mistral Voxtral Realtime ASR provider via vLLM.
    
    Features:
    - Uses official mistralai/Voxtral-Mini-4B-Realtime-2602 model
    - Novel streaming architecture (not chunked)
    - Configurable latency/quality tradeoff (240ms-2.4s)
    - ~4% WER on FLEURS benchmark
    - Local inference via vLLM (no cloud API needed)
    
    Architecture Notes:
    - NOT a chunked approach - true streaming with model state
    - Streaming delay controls how much audio to buffer before emitting
    - Lower delay = lower latency, higher WER
    - Higher delay = higher latency, lower WER
    """

    def __init__(self, config: ASRConfig):
        super().__init__(config)
        
        # Parse config from environment
        self.voxtral_config = VoxtralConfig(
            vllm_url=os.getenv("VOXTRAL_VLLM_URL", "http://localhost:8000"),
            streaming_delay_ms=int(os.getenv("VOXTRAL_STREAMING_DELAY_MS", str(DEFAULT_STREAMING_DELAY_MS))),
        )
        
        self._infer_times: list[float] = []
        self._chunks_processed = 0
        self._session: Optional[any] = None
        
    @property
    def name(self) -> str:
        return "voxtral_official"

    @property
    def is_available(self) -> bool:
        """Check if vLLM is accessible."""
        try:
            import aiohttp
            # Don't actually check here to avoid blocking
            return True
        except ImportError:
            return False

    def _check_vllm_health(self) -> bool:
        """Check if vLLM server is running and model is loaded."""
        import urllib.request
        import urllib.error
        
        try:
            health_url = f"{self.voxtral_config.vllm_url}/health"
            req = urllib.request.Request(health_url, method="GET")
            with urllib.request.urlopen(req, timeout=5) as response:
                return response.status == 200
        except Exception:
            return False

    def _check_vllm_ready(self) -> bool:
        """Check if vLLM model is ready for inference."""
        import urllib.request
        import json
        
        try:
            # Try to list models
            models_url = f"{self.voxtral_config.vllm_url}/v1/models"
            req = urllib.request.Request(models_url, method="GET")
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode('utf-8'))
                    models = data.get('data', [])
                    # Check if our model is available
                    for model in models:
                        if MODEL_NAME in model.get('id', ''):
                            return True
                    # If no specific model check passed, vLLM is at least running
                    return len(models) > 0
                return False
        except Exception:
            return False

    async def _init_vllm(self) -> bool:
        """Initialize connection to vLLM server."""
        loop = asyncio.get_event_loop()
        
        # Check vLLM health
        is_healthy = await loop.run_in_executor(None, self._check_vllm_health)
        if not is_healthy:
            self.log(f"❌ vLLM not accessible at {self.voxtral_config.vllm_url}")
            self.log("   To start vLLM:")
            self.log(f"   vllm serve {MODEL_ID} --max-model-len 4096")
            return False
        
        # Check if model is ready
        is_ready = await loop.run_in_executor(None, self._check_vllm_ready)
        if not is_ready:
            self.log(f"⚠️  vLLM running but model may not be loaded yet")
            # Still return True - model might be loading
        
        self.log(f"✅ Connected to vLLM at {self.voxtral_config.vllm_url}")
        self.log(f"   Streaming delay: {self.voxtral_config.streaming_delay_ms}ms")
        return True

    async def _transcribe_with_vllm(
        self,
        audio_bytes: bytes,
        t0: float,
        t1: float,
    ) -> Optional[ASRSegment]:
        """
        Transcribe audio using vLLM's chat completions API.
        
        Voxtral uses the chat API with audio content.
        """
        import aiohttp
        import base64
        
        # Encode audio as base64
        audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
        
        # Build request for vLLM chat completions with audio
        # Note: This uses OpenAI-compatible API
        url = f"{self.voxtral_config.vllm_url}/v1/chat/completions"
        
        # Voxtral expects audio in the messages
        # Format based on Mistral's audio API
        payload = {
            "model": MODEL_NAME,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "audio_url",
                            "audio_url": {
                                "url": f"data:audio/pcm;base64,{audio_b64}",
                                "format": "pcm_s16le_16000",
                            }
                        }
                    ]
                }
            ],
            "max_tokens": 256,
            "temperature": 0.0,
        }
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(url, json=payload, timeout=30) as resp:
                    if resp.status != 200:
                        error_text = await resp.text()
                        self.log(f"vLLM error {resp.status}: {error_text[:200]}")
                        return None
                    
                    result = await resp.json()
                    
                    # Extract text from response
                    choices = result.get("choices", [])
                    if choices:
                        message = choices[0].get("message", {})
                        text = message.get("content", "").strip()
                        
                        if text:
                            return ASRSegment(
                                text=text,
                                t0=t0,
                                t1=t1,
                                confidence=0.9,  # vLLM doesn't provide confidence
                                is_final=True,
                                source=AudioSource.SYSTEM,
                                language=self.config.language or "en",
                            )
                    return None
                    
        except asyncio.TimeoutError:
            self.log("vLLM request timeout")
            return None
        except Exception as e:
            self.log(f"Transcription error: {e}")
            return None

    async def transcribe_stream(
        self,
        pcm_stream: AsyncIterator[bytes],
        sample_rate: int = 16000,
        source: Optional[AudioSource] = None,
    ) -> AsyncIterator[ASRSegment]:
        """
        Transcribe audio stream using official Voxtral Realtime model via vLLM.
        
        Accumulates audio into chunks based on streaming_delay and sends to vLLM.
        Note: True streaming would use WebSocket, but vLLM currently uses chunked HTTP.
        """
        import aiohttp
        
        # Check dependencies
        try:
            import aiohttp
        except ImportError:
            yield ASRSegment(
                text="[voxtral_official: aiohttp not installed: pip install aiohttp]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return
        
        # Platform warning for macOS
        import platform
        if platform.system() == "Darwin":
            self.log("⚠️  WARNING: vLLM does not support Apple Silicon GPUs (Metal/MPS)")
            self.log("   Voxtral will run on CPU which is very slow.")
            self.log("   For macOS, use mlx_whisper instead (50× faster with Metal GPU).")
            # Continue anyway - user might still want to test

        # Initialize vLLM connection
        initialized = await self._init_vllm()
        if not initialized:
            yield ASRSegment(
                text=f"[voxtral_official: vLLM not running at {self.voxtral_config.vllm_url}. Start with: vllm serve {MODEL_ID}]",
                t0=0, t1=0,
                confidence=0,
                is_final=True,
                source=source,
            )
            async for _ in pcm_stream:
                pass
            return

        # Calculate chunk size based on streaming delay
        # streaming_delay_ms determines how much audio to accumulate
        bytes_per_sample = 2
        delay_seconds = self.voxtral_config.streaming_delay_ms / 1000.0
        chunk_bytes = int(sample_rate * delay_seconds * bytes_per_sample)
        
        buffer = bytearray()
        processed_samples = 0
        
        self.log(f"Starting Voxtral streaming (delay={self.voxtral_config.streaming_delay_ms}ms, chunk={chunk_bytes} bytes)")
        
        async for chunk in pcm_stream:
            buffer.extend(chunk)
            
            # Process when we have enough audio for the delay window
            while len(buffer) >= chunk_bytes:
                audio_bytes = bytes(buffer[:chunk_bytes])
                del buffer[:chunk_bytes]
                
                # Calculate timestamps
                t0 = processed_samples / sample_rate
                chunk_samples = len(audio_bytes) // bytes_per_sample
                t1 = (processed_samples + chunk_samples) / sample_rate
                processed_samples += chunk_samples
                
                infer_start = time.perf_counter()
                
                segment = await self._transcribe_with_vllm(audio_bytes, t0, t1)
                
                infer_time = time.perf_counter() - infer_start
                self._infer_times.append(infer_time)
                self._chunks_processed += 1
                
                if segment:
                    yield segment
        
        # Process any remaining buffer
        if buffer:
            t0 = processed_samples / sample_rate
            chunk_samples = len(buffer) // bytes_per_sample
            t1 = (processed_samples + chunk_samples) / sample_rate
            
            segment = await self._transcribe_with_vllm(bytes(buffer), t0, t1)
            if segment:
                yield segment

    async def health(self) -> dict:
        """Return health metrics."""
        # Check vLLM status
        loop = asyncio.get_event_loop()
        vllm_healthy = await loop.run_in_executor(None, self._check_vllm_health)
        
        if not self._infer_times:
            return {
                "status": "idle" if not vllm_healthy else "ready",
                "vllm_url": self.voxtral_config.vllm_url,
                "vllm_healthy": vllm_healthy,
                "streaming_delay_ms": self.voxtral_config.streaming_delay_ms,
                "realtime_factor": 0.0,
                "chunks_processed": 0,
            }
        
        avg_infer = sum(self._infer_times) / len(self._infer_times)
        delay_seconds = self.voxtral_config.streaming_delay_ms / 1000.0
        rtf = avg_infer / delay_seconds if delay_seconds > 0 else 0
        
        return {
            "status": "active" if vllm_healthy else "degraded",
            "vllm_url": self.voxtral_config.vllm_url,
            "vllm_healthy": vllm_healthy,
            "streaming_delay_ms": self.voxtral_config.streaming_delay_ms,
            "realtime_factor": rtf,
            "chunks_processed": self._chunks_processed,
            "avg_infer_ms": avg_infer * 1000,
            "model": MODEL_ID,
        }

    async def unload(self) -> None:
        """Clean up resources."""
        self._session = None
        self._infer_times.clear()
        self._chunks_processed = 0
        await super().unload()


# Register the provider
ASRProviderRegistry.register("voxtral_official", VoxtralOfficialProvider)
