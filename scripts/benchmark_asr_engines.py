#!/usr/bin/env python3
"""
ASR Engine Benchmark for Apple Silicon

Tests and compares:
1. faster-whisper (CPU - current)
2. whisper.cpp (Metal via subprocess)
3. mlx-whisper (Metal - native Apple)
4. ONNX Runtime (CoreML)

Usage:
    python scripts/benchmark_asr_engines.py --audio test_speech.wav --duration 30
"""

import asyncio
import time
import os
import sys
import tempfile
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any, Callable
from dataclasses import dataclass
import json

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

@dataclass
class BenchmarkResult:
    engine: str
    model: str
    load_time_ms: float
    inference_time_ms: float
    audio_duration_s: float
    rtf: float  # Real-time factor (lower is better, <1 means faster than realtime)
    memory_mb: float
    device: str
    errors: list[str]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "engine": self.engine,
            "model": self.model,
            "load_time_ms": round(self.load_time_ms, 1),
            "inference_time_ms": round(self.inference_time_ms, 1),
            "audio_duration_s": round(self.audio_duration_s, 2),
            "rtf": round(self.rtf, 3),
            "memory_mb": round(self.memory_mb, 1),
            "device": self.device,
            "errors": self.errors,
        }


class ASRBenchmark:
    def __init__(self, audio_path: str, duration_s: float = 30.0):
        self.audio_path = audio_path
        self.duration_s = duration_s
        self.results: list[BenchmarkResult] = []
        
    def _get_memory_mb(self) -> float:
        """Get current process memory in MB."""
        try:
            import psutil
            process = psutil.Process()
            return process.memory_info().rss / 1024 / 1024
        except ImportError:
            return 0.0
    
    def _extract_audio_segment(self, output_path: str, duration: float) -> bool:
        """Extract a segment of audio for testing."""
        try:
            import subprocess
            cmd = [
                "ffmpeg", "-y", "-i", self.audio_path,
                "-ar", "16000", "-ac", "1", "-f", "s16le",
                "-t", str(duration),
                output_path
            ]
            subprocess.run(cmd, capture_output=True, check=True)
            return True
        except Exception as e:
            print(f"  Error extracting audio: {e}")
            return False
    
    async def benchmark_faster_whisper(self, model: str = "base.en") -> Optional[BenchmarkResult]:
        """Benchmark faster-whisper (CPU on macOS)."""
        print(f"\n🧪 Testing faster-whisper ({model})...")
        errors = []
        
        try:
            from faster_whisper import WhisperModel
            
            # Measure model load time
            mem_before = self._get_memory_mb()
            t0 = time.perf_counter()
            
            # Force CPU on macOS (simulating current behavior)
            model_obj = WhisperModel(model, device="cpu", compute_type="int8")
            
            load_time = (time.perf_counter() - t0) * 1000
            mem_after = self._get_memory_mb()
            
            # Extract test audio
            with tempfile.NamedTemporaryFile(suffix=".raw", delete=False) as f:
                test_audio = f.name
            
            if not self._extract_audio_segment(test_audio, self.duration_s):
                return None
            
            # Read audio
            import numpy as np
            audio_data = np.fromfile(test_audio, dtype=np.int16).astype(np.float32) / 32768.0
            
            # Measure inference time
            t0 = time.perf_counter()
            segments, info = model_obj.transcribe(audio_data, language="en")
            list(segments)  # Consume generator
            inference_time = (time.perf_counter() - t0) * 1000
            
            os.unlink(test_audio)
            
            return BenchmarkResult(
                engine="faster-whisper",
                model=model,
                load_time_ms=load_time,
                inference_time_ms=inference_time,
                audio_duration_s=self.duration_s,
                rtf=(inference_time / 1000) / self.duration_s,
                memory_mb=mem_after - mem_before,
                device="cpu",
                errors=errors
            )
            
        except Exception as e:
            errors.append(str(e))
            print(f"  ❌ Error: {e}")
            return None
    
    async def benchmark_mlx_whisper(self, model: str = "base") -> Optional[BenchmarkResult]:
        """Benchmark mlx-whisper (Metal GPU)."""
        print(f"\n🧪 Testing mlx-whisper ({model})...")
        errors = []
        
        try:
            import mlx.core as mx
            import mlx_whisper
            
            if not mx.metal.is_available():
                errors.append("Metal not available")
                return None
            
            # Measure model load time
            mem_before = self._get_memory_mb()
            t0 = time.perf_counter()
            
            # Load model (mlx-whisper loads on first transcribe)
            # Pre-load by calling with a tiny dummy array
            import numpy as np
            dummy = np.zeros(16000, dtype=np.float32)
            _ = mlx_whisper.transcribe(dummy, path_or_hf_repo=f"openai/whisper-{model}")
            
            load_time = (time.perf_counter() - t0) * 1000
            mem_after = self._get_memory_mb()
            
            # Extract test audio
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                test_audio = f.name
            
            # Extract as WAV for mlx-whisper
            try:
                subprocess.run([
                    "ffmpeg", "-y", "-i", self.audio_path,
                    "-ar", "16000", "-ac", "1",
                    "-t", str(self.duration_s),
                    test_audio
                ], capture_output=True, check=True)
            except Exception as e:
                errors.append(f"FFmpeg error: {e}")
                return None
            
            # Measure inference time
            t0 = time.perf_counter()
            result = mlx_whisper.transcribe(
                test_audio, 
                path_or_hf_repo=f"openai/whisper-{model}",
                language="en"
            )
            inference_time = (time.perf_counter() - t0) * 1000
            
            os.unlink(test_audio)
            
            return BenchmarkResult(
                engine="mlx-whisper",
                model=model,
                load_time_ms=load_time,
                inference_time_ms=inference_time,
                audio_duration_s=self.duration_s,
                rtf=(inference_time / 1000) / self.duration_s,
                memory_mb=mem_after - mem_before,
                device="metal",
                errors=errors
            )
            
        except Exception as e:
            errors.append(str(e))
            print(f"  ❌ Error: {e}")
            return None
    
    async def benchmark_whisper_cpp(self, model: str = "base.en") -> Optional[BenchmarkResult]:
        """Benchmark whisper.cpp (if available)."""
        print(f"\n🧪 Testing whisper.cpp ({model})...")
        errors = []
        
        # Check if whisper.cpp is installed
        whisper_cpp_path = None
        for path in ["whisper-cpp", "whisper.cpp", "./whisper.cpp/main"]:
            if subprocess.run(["which", path], capture_output=True).returncode == 0:
                whisper_cpp_path = path
                break
        
        if not whisper_cpp_path:
            errors.append("whisper.cpp not found in PATH")
            print("  ❌ whisper.cpp not installed")
            return None
        
        try:
            # Extract test audio as WAV
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                test_audio = f.name
            
            subprocess.run([
                "ffmpeg", "-y", "-i", self.audio_path,
                "-ar", "16000", "-ac", "1",
                "-t", str(self.duration_s),
                test_audio
            ], capture_output=True, check=True)
            
            # Map model name to GGML model file
            model_map = {
                "tiny.en": "ggml-tiny.en.bin",
                "base.en": "ggml-base.en.bin",
                "small.en": "ggml-small.en.bin",
            }
            ggml_model = model_map.get(model, "ggml-base.en.bin")
            
            # Check if model exists
            model_path = os.path.expanduser(f"~/.cache/whisper/{ggml_model}")
            if not os.path.exists(model_path):
                errors.append(f"Model not found: {model_path}")
                print(f"  ❌ Model not found: {model_path}")
                return None
            
            # Measure inference time
            mem_before = self._get_memory_mb()
            t0 = time.perf_counter()
            
            result = subprocess.run([
                whisper_cpp_path,
                "-m", model_path,
                "-f", test_audio,
                "-l", "en",
                "--no-timestamps"
            ], capture_output=True, text=True)
            
            inference_time = (time.perf_counter() - t0) * 1000
            mem_after = self._get_memory_mb()
            
            os.unlink(test_audio)
            
            if result.returncode != 0:
                errors.append(f"whisper.cpp error: {result.stderr}")
                return None
            
            return BenchmarkResult(
                engine="whisper.cpp",
                model=model,
                load_time_ms=0,  # whisper.cpp loads model per invocation
                inference_time_ms=inference_time,
                audio_duration_s=self.duration_s,
                rtf=(inference_time / 1000) / self.duration_s,
                memory_mb=mem_after - mem_before,
                device="metal",
                errors=errors
            )
            
        except Exception as e:
            errors.append(str(e))
            print(f"  ❌ Error: {e}")
            return None
    
    async def run_all(self) -> Dict[str, Any]:
        """Run all benchmarks."""
        print(f"\n{'='*60}")
        print(f"ASR Engine Benchmark")
        print(f"Audio: {self.audio_path}")
        print(f"Duration: {self.duration_s}s")
        print(f"{'='*60}")
        
        # Test faster-whisper (current)
        result = await self.benchmark_faster_whisper("base.en")
        if result:
            self.results.append(result)
        
        # Test mlx-whisper (Metal)
        result = await self.benchmark_mlx_whisper("base")
        if result:
            self.results.append(result)
        
        # Test whisper.cpp (if available)
        result = await self.benchmark_whisper_cpp("base.en")
        if result:
            self.results.append(result)
        
        return self._generate_report()
    
    def _generate_report(self) -> Dict[str, Any]:
        """Generate benchmark report."""
        print(f"\n{'='*60}")
        print("RESULTS SUMMARY")
        print(f"{'='*60}")
        
        if not self.results:
            print("No successful benchmarks!")
            return {"results": [], "recommendation": None}
        
        # Sort by RTF (lower is better)
        sorted_results = sorted(self.results, key=lambda r: r.rtf)
        
        print(f"\n{'Engine':<20} {'Model':<15} {'RTF':<10} {'Time':<10} {'Device':<10}")
        print("-" * 70)
        
        for r in sorted_results:
            rtf_str = f"{r.rtf:.3f}x"
            time_str = f"{r.inference_time_ms/1000:.1f}s"
            print(f"{r.engine:<20} {r.model:<15} {rtf_str:<10} {time_str:<10} {r.device:<10}")
        
        best = sorted_results[0]
        print(f"\n🏆 WINNER: {best.engine} ({best.model})")
        print(f"   RTF: {best.rtf:.3f}x (target: <0.5x for comfortable real-time)")
        print(f"   Device: {best.device}")
        
        return {
            "results": [r.to_dict() for r in self.results],
            "recommendation": {
                "engine": best.engine,
                "model": best.model,
                "rtf": best.rtf,
                "reason": f"Best RTF ({best.rtf:.3f}x) on {best.device}"
            }
        }


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Benchmark ASR engines on Apple Silicon")
    parser.add_argument("--audio", default="test_speech.wav", help="Audio file to test")
    parser.add_argument("--duration", type=float, default=30.0, help="Test duration in seconds")
    parser.add_argument("--output", help="Output JSON file for results")
    args = parser.parse_args()
    
    audio_path = Path(args.audio)
    if not audio_path.exists():
        # Try to find in project root
        audio_path = Path(__file__).parent.parent / args.audio
    
    if not audio_path.exists():
        print(f"Audio file not found: {args.audio}")
        print("Creating synthetic test audio...")
        
        # Create a silent test file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            test_path = f.name
        
        # Generate 30s of silence at 16kHz
        subprocess.run([
            "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono",
            "-t", str(args.duration), "-acodec", "pcm_s16le", test_path
        ], capture_output=True)
        audio_path = test_path
    
    benchmark = ASRBenchmark(str(audio_path), args.duration)
    results = asyncio.run(benchmark.run_all())
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"\nResults saved to: {args.output}")
    
    # Cleanup
    if 'test_path' in locals():
        os.unlink(test_path)
    
    return 0 if results["results"] else 1


if __name__ == "__main__":
    sys.exit(main())
