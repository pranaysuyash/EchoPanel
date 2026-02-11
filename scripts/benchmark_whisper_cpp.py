#!/usr/bin/env python3
"""
Benchmark: whisper.cpp vs faster-whisper

Compares performance (RTF, latency, memory) between providers.
Run on Apple Silicon to see Metal acceleration benefits.
"""

import asyncio
import time
import sys
import os
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

import numpy as np


def generate_test_audio(duration_seconds: float = 10.0, sample_rate: int = 16000) -> bytes:
    """Generate synthetic test audio (sine wave)."""
    t = np.linspace(0, duration_seconds, int(sample_rate * duration_seconds))
    # Mix of frequencies to simulate speech-like content
    audio = (
        0.3 * np.sin(2 * np.pi * 200 * t) +  # 200 Hz
        0.3 * np.sin(2 * np.pi * 400 * t) +  # 400 Hz
        0.2 * np.sin(2 * np.pi * 800 * t)    # 800 Hz
    )
    # Convert to int16
    audio_int16 = (audio * 32767).astype(np.int16)
    return audio_int16.tobytes()


async def benchmark_provider(provider_name: str, duration_seconds: float = 10.0):
    """Benchmark a single provider."""
    from server.services.asr_providers import ASRProviderRegistry, ASRConfig
    
    print(f"\n{'='*60}")
    print(f"Benchmarking: {provider_name}")
    print(f"{'='*60}")
    
    # Get provider
    config = ASRConfig(
        model_name="base" if provider_name == "whisper_cpp" else "base.en",
        device="auto",
        chunk_seconds=2,
    )
    
    provider = ASRProviderRegistry.get_provider(name=provider_name, config=config)
    if not provider:
        print(f"❌ Provider '{provider_name}' not available")
        return None
    
    # Generate test audio
    print(f"Generating {duration_seconds}s test audio...")
    audio_bytes = generate_test_audio(duration_seconds)
    
    # Create async iterator
    async def audio_stream():
        chunk_size = 32000  # 1s of 16kHz 16-bit audio
        for i in range(0, len(audio_bytes), chunk_size):
            yield audio_bytes[i:i+chunk_size]
    
    # Warmup (first inference is slower)
    print("Warming up...")
    try:
        async for _ in provider.transcribe_stream(audio_stream(), source="system"):
            break  # Just process one chunk
    except Exception as e:
        print(f"Warmup error: {e}")
    
    # Benchmark
    print(f"Running benchmark ({duration_seconds}s audio)...")
    start_time = time.time()
    
    segment_count = 0
    total_text = ""
    
    try:
        async for segment in provider.transcribe_stream(audio_stream(), source="system"):
            segment_count += 1
            total_text += segment.text + " "
            
    except Exception as e:
        print(f"❌ Error during benchmark: {e}")
        return None
    
    elapsed = time.time() - start_time
    rtf = elapsed / duration_seconds
    
    results = {
        "provider": provider_name,
        "audio_duration": duration_seconds,
        "processing_time": round(elapsed, 2),
        "realtime_factor": round(rtf, 2),
        "segments": segment_count,
        "text_preview": total_text[:100] + "..." if len(total_text) > 100 else total_text,
    }
    
    print(f"\n✅ Results:")
    print(f"  Processing time: {results['processing_time']}s")
    print(f"  Real-time factor: {results['realtime_factor']}x")
    print(f"  Segments: {results['segments']}")
    print(f"  Text preview: {results['text_preview']}")
    
    if rtf < 1.0:
        print(f"  ⚠️  WARNING: RTF < 1.0 - too slow for real-time!")
    elif rtf < 2.0:
        print(f"  ✅ OK: RTF acceptable for real-time")
    else:
        print(f"  ✅ EXCELLENT: Fast enough for real-time streaming")
    
    return results


async def main():
    """Run benchmarks for all available providers."""
    print("="*60)
    print("EchoPanel ASR Provider Benchmark")
    print("="*60)
    
    # Import after setting up path
    from server.services import asr_providers  # noqa: F401 - registers providers
    
    results = []
    
    # Benchmark faster-whisper (baseline)
    result = await benchmark_provider("faster_whisper", duration_seconds=10.0)
    if result:
        results.append(result)
    
    # Benchmark whisper.cpp (if available)
    result = await benchmark_provider("whisper_cpp", duration_seconds=10.0)
    if result:
        results.append(result)
    
    # Summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    
    if len(results) < 2:
        print("Need both providers for comparison")
        return
    
    baseline_rtf = results[0]["realtime_factor"]
    whisper_rtf = results[1]["realtime_factor"]
    
    speedup = whisper_rtf / baseline_rtf if baseline_rtf > 0 else 0
    
    print(f"\n{results[0]['provider']}: RTF = {baseline_rtf}x")
    print(f"{results[1]['provider']}: RTF = {whisper_rtf}x")
    print(f"\nSpeedup: {speedup:.1f}x")
    
    if speedup > 2.0:
        print("🎉 whisper.cpp is significantly faster!")
    elif speedup > 1.0:
        print("✅ whisper.cpp is faster")
    else:
        print("⚠️  whisper.cpp is not faster on this system")


if __name__ == "__main__":
    asyncio.run(main())
