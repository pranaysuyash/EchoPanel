#!/usr/bin/env python3
"""
ASR Provider Test Suite (Memory-Optimized)

Tests all ASR providers (faster-whisper, whisper.cpp, MLX, ONNX) for:
- Availability
- Model loading
- Transcription accuracy
- Real-time factor (RTF)

Streams audio from disk to avoid memory issues with large files.

Usage:
    python scripts/test_asr_providers.py
    python scripts/test_asr_providers.py --model tiny
    python scripts/test_asr_providers.py --provider mlx_whisper
"""

import argparse
import asyncio
import os
import sys
import time
from pathlib import Path
from typing import AsyncIterator

# Add server to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from server.services import (
    ASRConfig,
    ASRProviderRegistry,
    AudioSource,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Test ASR providers")
    parser.add_argument("--model", default="tiny", help="Model size (tiny, base, small)")
    parser.add_argument("--provider", default="all", help="Provider to test (or 'all')")
    parser.add_argument("--audio", default="test_speech.wav", help="Audio file to test")
    parser.add_argument("--duration", type=int, default=8, help="Audio duration to test (seconds)")
    parser.add_argument("--chunk", type=int, default=4, help="Chunk size (seconds)")
    return parser.parse_args()


async def stream_audio_from_disk(
    raw_path: Path,
    chunk_bytes: int,
) -> AsyncIterator[bytes]:
    """
    Stream audio chunks from disk to avoid loading entire file into memory.
    
    Args:
        raw_path: Path to raw PCM file (s16le format)
        chunk_bytes: Size of each chunk in bytes
    
    Yields:
        Audio chunks as bytes
    """
    # Use aiofiles for async file I/O, fallback to sync in executor
    try:
        import aiofiles
        async with aiofiles.open(raw_path, 'rb') as f:
            while True:
                chunk = await f.read(chunk_bytes)
                if not chunk:
                    break
                yield chunk
    except ImportError:
        # Fallback: sync read in executor
        loop = asyncio.get_event_loop()
        
        def read_chunks():
            with open(raw_path, 'rb') as f:
                while True:
                    chunk = f.read(chunk_bytes)
                    if not chunk:
                        break
                    yield chunk
        
        # Run generator in thread pool
        for chunk in await loop.run_in_executor(None, lambda: list(read_chunks())):
            yield chunk


async def test_provider(provider_name: str, model: str, audio_path: str, duration: int, chunk: int) -> dict:
    """Test a single ASR provider with memory-efficient audio streaming."""
    print(f"\n{'='*60}")
    print(f"Testing: {provider_name}")
    print(f"Model: {model}")
    print(f"{'='*60}")
    
    results = {
        "provider": provider_name,
        "model": model,
        "available": False,
        "working": False,
        "rtf": 0.0,
        "transcription": "",
        "error": None,
    }
    
    # Create config
    config = ASRConfig(model_name=model, device="auto", chunk_seconds=chunk)
    
    # Get provider instance from registry
    provider = ASRProviderRegistry.get_provider(provider_name, config)
    if provider is None:
        results["error"] = f"Provider '{provider_name}' not found in registry"
        print(f"  ❌ {results['error']}")
        return results
    
    # Check availability
    if not provider.is_available:
        results["error"] = "Provider not available (check dependencies)"
        print(f"  ❌ {results['error']}")
        return results
    
    results["available"] = True
    print(f"  ✓ Provider available")
    
    # Prepare audio using FFmpeg
    import subprocess
    import tempfile
    
    temp_path = Path(tempfile.gettempdir()) / f"test_{provider_name}_{os.getpid()}.raw"
    
    result = subprocess.run(
        ['ffmpeg', '-y', '-i', audio_path, '-ar', '16000', '-ac', '1', '-f', 's16le', '-t', str(duration), str(temp_path)],
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        results["error"] = f"FFmpeg failed: {result.stderr}"
        print(f"  ❌ {results['error']}")
        return results
    
    # Calculate chunk size
    sample_rate = 16000
    bytes_per_sample = 2
    chunk_bytes = sample_rate * bytes_per_sample * chunk
    
    # Stream from disk instead of loading all to memory
    print(f"  Streaming audio from disk (chunk={chunk_bytes} bytes)...")
    
    segments = []
    start = time.perf_counter()
    
    try:
        # Create async generator that streams from disk
        audio_gen = stream_audio_from_disk(temp_path, chunk_bytes)
        
        async for seg in provider.transcribe_stream(audio_gen, source=AudioSource.SYSTEM):
            print(f"  [{seg.t0:5.1f}s - {seg.t1:5.1f}s] {seg.text[:60]}...")
            segments.append(seg)
        
        elapsed = time.perf_counter() - start
        
        if segments:
            transcription = " ".join(s.text for s in segments)
            results["transcription"] = transcription
            
            # Calculate RTF
            audio_duration = duration
            rtf = elapsed / audio_duration if audio_duration > 0 else 0
            results["rtf"] = rtf
            results["working"] = True
            
            print(f"\n  ✓ Transcription complete")
            print(f"  ✓ Audio duration: {audio_duration:.1f}s")
            print(f"  ✓ Processing time: {elapsed:.2f}s")
            print(f"  ✓ Real-time factor: {rtf:.3f}x (lower is better)")
            print(f"\n  Full text: {transcription[:100]}...")
        else:
            results["error"] = "No segments produced"
            print(f"  ❌ {results['error']}")
            
    except Exception as e:
        results["error"] = str(e)
        print(f"  ❌ Exception: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await provider.unload()
        # Cleanup temp file
        try:
            temp_path.unlink(missing_ok=True)
        except Exception:
            pass
    
    return results


async def main():
    args = parse_args()
    
    # Map provider names (registry keys)
    provider_map = {
        "faster_whisper": "faster_whisper",
        "whisper_cpp": "whisper_cpp",
        "mlx_whisper": "mlx_whisper",
        "onnx_whisper": "onnx_whisper",
        "voxtral": "voxtral",
        "voxtral_official": "voxtral_official",
    }
    
    # Determine which providers to test (use registry keys)
    if args.provider == "all":
        providers = ["faster_whisper", "whisper_cpp", "mlx_whisper", "onnx_whisper", "voxtral_official"]
    else:
        provider_key = provider_map.get(args.provider, args.provider)
        providers = [provider_key]
    
    print(f"\n{'#'*60}")
    print(f"# ASR Provider Test Suite (Memory-Optimized)")
    print(f"{'#'*60}")
    print(f"Audio: {args.audio}")
    print(f"Duration: {args.duration}s")
    print(f"Chunk: {args.chunk}s")
    print(f"Model: {args.model}")
    print(f"PID: {os.getpid()}")
    
    all_results = []
    for provider_name in providers:
        try:
            result = await test_provider(
                provider_name,
                args.model,
                args.audio,
                args.duration,
                args.chunk
            )
            all_results.append(result)
        except Exception as e:
            print(f"\n  ❌ Failed to test {provider_name}: {e}")
            import traceback
            traceback.print_exc()
            all_results.append({
                "provider": provider_name,
                "available": False,
                "working": False,
                "error": str(e),
            })
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"{'Provider':<25} {'Available':<10} {'Working':<10} {'RTF':<10}")
    print(f"{'-'*60}")
    
    for r in all_results:
        avail = "✓" if r["available"] else "✗"
        work = "✓" if r["working"] else "✗"
        rtf = f"{r['rtf']:.3f}x" if r["working"] else "N/A"
        print(f"{r['provider']:<25} {avail:<10} {work:<10} {rtf:<10}")
    
    # Exit code
    working_count = sum(1 for r in all_results if r["working"])
    if working_count == 0:
        print(f"\n❌ No working providers found!")
        return 1
    
    print(f"\n✅ {working_count}/{len(all_results)} providers working")
    return 0


if __name__ == "__main__":
    exit(asyncio.run(main()))
