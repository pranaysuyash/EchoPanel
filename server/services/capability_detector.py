"""
Machine Capability Detector (v0.1)

Detects machine capabilities (RAM, CPU, GPU) and recommends optimal ASR provider/model.
Used for automatic provider selection and degrade ladder decisions.

Features:
    - Detects available RAM, CPU cores
    - Detects GPU availability (Metal on macOS, CUDA on Linux)
    - Recommends optimal provider based on hardware
    - Provides degrade ladder recommendations

Usage:
    from server.services.capability_detector import CapabilityDetector, ProviderRecommendation
    
    detector = CapabilityDetector()
    profile = detector.detect()
    recommendation = detector.recommend(profile)
    
    print(f"Recommended: {recommendation.provider} with {recommendation.model}")
"""

from __future__ import annotations

import logging
import os
import platform
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, List, Dict, Any

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

logger = logging.getLogger(__name__)


@dataclass
class MachineProfile:
    """Detected machine capabilities."""
    ram_gb: float
    cpu_cores: int
    cpu_percent: float  # Current CPU usage
    has_mps: bool  # Metal Performance Shaders (Apple Silicon)
    has_cuda: bool  # NVIDIA CUDA
    cuda_devices: int  # Number of CUDA devices
    os_name: str  # Darwin, Linux, Windows
    arch: str  # arm64, x86_64, etc.
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "ram_gb": round(self.ram_gb, 1),
            "cpu_cores": self.cpu_cores,
            "cpu_percent": round(self.cpu_percent, 1),
            "has_mps": self.has_mps,
            "has_cuda": self.has_cuda,
            "cuda_devices": self.cuda_devices,
            "os_name": self.os_name,
            "arch": self.arch,
        }


@dataclass
class ProviderRecommendation:
    """Recommended ASR configuration."""
    provider: str
    model: str
    chunk_seconds: int
    compute_type: str
    device: str
    vad_enabled: bool
    n_threads: Optional[int] = None  # For whisper.cpp
    streaming_delay: Optional[float] = None  # For voxtral
    
    # Recommendation metadata
    reason: str = ""  # Why this recommendation was made
    fallback: Optional["ProviderRecommendation"] = None  # Fallback if primary fails
    
    def to_dict(self) -> Dict[str, Any]:
        result = {
            "provider": self.provider,
            "model": self.model,
            "chunk_seconds": self.chunk_seconds,
            "compute_type": self.compute_type,
            "device": self.device,
            "vad_enabled": self.vad_enabled,
            "reason": self.reason,
        }
        if self.n_threads is not None:
            result["n_threads"] = self.n_threads
        if self.streaming_delay is not None:
            result["streaming_delay"] = self.streaming_delay
        if self.fallback:
            result["fallback"] = self.fallback.to_dict()
        return result


class CapabilityDetector:
    """Detects machine capabilities and recommends ASR configuration."""

    # RAM thresholds for different model sizes (GB)
    RAM_REQUIREMENTS = {
        "tiny": 1,
        "base": 2,
        "small": 4,
        "medium": 8,
        "large": 16,
        "voxtral_4b": 16,  # Voxtral Realtime 4B needs ~16GB minimum
    }
    
    # Model recommendations by capability tier
    TIER_CONFIGS = {
        "ultra_low": {  # < 4GB RAM
            "provider": "faster_whisper",
            "model": "tiny.en",
            "chunk_seconds": 4,
            "compute_type": "int8",
            "device": "cpu",
            "vad_enabled": False,
        },
        "low": {  # 4-8GB RAM
            "provider": "faster_whisper",
            "model": "base.en",
            # Live meetings: lower chunk for latency; base.en is fast enough on CPU.
            "chunk_seconds": 2,
            "compute_type": "int8",
            "device": "cpu",
            # Default OFF for compute stability; can be enabled explicitly or by future adaptive logic.
            "vad_enabled": False,
        },
        "medium": {  # 8-16GB RAM, no GPU
            "provider": "faster_whisper",
            # Reliability-first default: small.en is often slower-than-realtime on CPU in live mode.
            "model": "base.en",
            "chunk_seconds": 2,
            "compute_type": "int8",
            "device": "cpu",
            "vad_enabled": False,
        },
        "medium_gpu": {  # 8-16GB RAM, with Metal/CUDA
            "provider": "whisper_cpp",
            "model": "small.en",
            "chunk_seconds": 2,
            "compute_type": "q5_0",
            "device": "gpu",
            "vad_enabled": True,
            "n_threads": 4,
        },
        "high": {  # 16-32GB RAM
            "provider": "whisper_cpp",
            "model": "medium.en",
            "chunk_seconds": 2,
            "compute_type": "q5_0",
            "device": "gpu",
            "vad_enabled": True,
            "n_threads": 4,
        },
        "ultra": {  # 32GB+ RAM, Apple Silicon or CUDA
            "provider": "voxtral_realtime",
            "model": "Voxtral-Mini-4B-Realtime",
            "chunk_seconds": 2,
            "compute_type": "bf16",
            "device": "mps",
            "vad_enabled": True,
            "streaming_delay": 0.5,
        },
    }

    def detect(self) -> MachineProfile:
        """Detect machine capabilities.
        
        Returns:
            MachineProfile with detected hardware capabilities.
        """
        # RAM
        if HAS_PSUTIL:
            ram_gb = psutil.virtual_memory().total / (1024**3)
            cpu_cores = psutil.cpu_count(logical=True) or 4
            cpu_percent = psutil.cpu_percent(interval=0.1)
        else:
            # Fallback: try reading from /proc/meminfo on Linux
            ram_gb = self._detect_ram_fallback() or 8.0
            cpu_cores = self._detect_cores_fallback() or 4
            cpu_percent = 0.0
        
        # OS and architecture
        os_name = platform.system()
        arch = platform.machine()
        
        # GPU detection
        has_mps = self._detect_mps()
        has_cuda, cuda_devices = self._detect_cuda()
        
        return MachineProfile(
            ram_gb=ram_gb,
            cpu_cores=cpu_cores,
            cpu_percent=cpu_percent,
            has_mps=has_mps,
            has_cuda=has_cuda,
            cuda_devices=cuda_devices,
            os_name=os_name,
            arch=arch,
        )

    def _detect_ram_fallback(self) -> Optional[float]:
        """Fallback RAM detection without psutil."""
        try:
            if platform.system() == "Linux":
                with open("/proc/meminfo", "r") as f:
                    for line in f:
                        if line.startswith("MemTotal:"):
                            kb = int(line.split()[1])
                            return kb / (1024**2)  # Convert KB to GB
            elif platform.system() == "Darwin":
                # Use sysctl on macOS
                result = subprocess.run(
                    ["sysctl", "-n", "hw.memsize"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                bytes_ram = int(result.stdout.strip())
                return bytes_ram / (1024**3)
        except Exception as e:
            logger.debug(f"RAM detection fallback failed: {e}")
        return None

    def _detect_cores_fallback(self) -> Optional[int]:
        """Fallback CPU core detection without psutil."""
        try:
            return os.cpu_count()
        except Exception as e:
            logger.debug(f"CPU detection fallback failed: {e}")
        return None

    def _detect_mps(self) -> bool:
        """Detect Metal Performance Shaders (Apple Silicon GPU)."""
        if platform.system() != "Darwin":
            return False
        
        # Check architecture (Apple Silicon is arm64)
        if platform.machine() != "arm64":
            return False
        
        # Try torch MPS
        if HAS_TORCH:
            try:
                return torch.backends.mps.is_available()
            except Exception as e:
                logger.debug(f"torch MPS detection failed: {e}")
        
        # Fallback: check for Metal framework
        try:
            result = subprocess.run(
                ["system_profiler", "SPDisplaysDataType"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            return "Metal" in result.stdout or "Apple" in result.stdout
        except Exception as e:
            logger.debug(f"Metal detection fallback failed: {e}")
        
        # Assume MPS on Apple Silicon if all else fails
        return True

    def _detect_cuda(self) -> tuple[bool, int]:
        """Detect NVIDIA CUDA availability.
        
        Returns:
            Tuple of (has_cuda, num_devices)
        """
        if HAS_TORCH:
            try:
                has_cuda = torch.cuda.is_available()
                num_devices = torch.cuda.device_count() if has_cuda else 0
                return has_cuda, num_devices
            except Exception as e:
                logger.debug(f"torch CUDA detection failed: {e}")
        
        # Fallback: check for nvidia-smi
        try:
            result = subprocess.run(
                ["nvidia-smi", "-L"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                # Count GPUs from output
                num_devices = len([l for l in result.stdout.split("\n") if "GPU" in l])
                return True, max(1, num_devices)
        except Exception:
            pass
        
        return False, 0

    def recommend(self, profile: Optional[MachineProfile] = None) -> ProviderRecommendation:
        """Recommend optimal ASR configuration based on machine profile.
        
        Args:
            profile: MachineProfile from detect(). If None, calls detect().
        
        Returns:
            ProviderRecommendation with optimal configuration.
        """
        if profile is None:
            profile = self.detect()
        
        logger.info(f"Machine profile: {profile.to_dict()}")
        
        # Determine capability tier
        if profile.ram_gb < 4:
            tier = "ultra_low"
            reason = f"Low RAM ({profile.ram_gb:.1f}GB < 4GB)"
        elif profile.ram_gb < 8:
            tier = "low"
            reason = f"Limited RAM ({profile.ram_gb:.1f}GB < 8GB)"
        elif profile.ram_gb < 16:
            if profile.has_mps or profile.has_cuda:
                tier = "medium_gpu"
                reason = f"Moderate RAM ({profile.ram_gb:.1f}GB) with GPU acceleration"
            else:
                tier = "medium"
                reason = f"Moderate RAM ({profile.ram_gb:.1f}GB), no GPU"
        elif profile.ram_gb < 32:
            if profile.has_mps:
                tier = "high"
                reason = f"Good RAM ({profile.ram_gb:.1f}GB) with Metal GPU"
            elif profile.has_cuda:
                tier = "high"
                reason = f"Good RAM ({profile.ram_gb:.1f}GB) with CUDA"
            else:
                tier = "medium"
                reason = f"Good RAM ({profile.ram_gb:.1f}GB), no GPU"
        else:
            if profile.has_mps or profile.has_cuda:
                tier = "ultra"
                reason = f"High RAM ({profile.ram_gb:.1f}GB) with GPU, can run Voxtral"
            else:
                tier = "high"
                reason = f"High RAM ({profile.ram_gb:.1f}GB), no GPU"
        
        config = self.TIER_CONFIGS[tier].copy()
        config["reason"] = reason

        # Reliability guard: do not auto-select Voxtral by default.
        # Voxtral requires a large local model + binary and can delay startup significantly.
        if config.get("provider") == "voxtral_realtime":
            auto_voxtral = os.getenv("ECHOPANEL_AUTO_SELECT_VOXTRAL", "0").strip().lower()
            if auto_voxtral in {"0", "false", "no", "off", ""}:
                logger.info("Voxtral auto-select disabled (set ECHOPANEL_AUTO_SELECT_VOXTRAL=1 to enable)")
                config = self.TIER_CONFIGS["high"].copy()
                config["reason"] = f"{reason} (voxtral auto-select disabled)"
        
        # Adjust for specific hardware
        if config["provider"] == "whisper_cpp":
            # Check if whisper.cpp is actually available
            if not self._whisper_cpp_available():
                logger.warning("whisper_cpp recommended but not available, falling back to faster_whisper")
                config = self.TIER_CONFIGS["medium"].copy()
                config["reason"] = f"{reason} (whisper.cpp not available)"
        
        elif config["provider"] == "voxtral_realtime":
            # Check if voxtral is actually available
            if not self._voxtral_available():
                logger.warning("voxtral_realtime recommended but not available, falling back to whisper_cpp")
                config = self.TIER_CONFIGS["high"].copy()
                config["reason"] = f"{reason} (voxtral not available)"
        
        # Build recommendation
        recommendation = ProviderRecommendation(
            provider=config["provider"],
            model=config["model"],
            chunk_seconds=config["chunk_seconds"],
            compute_type=config["compute_type"],
            device=config["device"],
            vad_enabled=config["vad_enabled"],
            reason=config["reason"],
        )
        
        if "n_threads" in config:
            recommendation.n_threads = config["n_threads"]
        if "streaming_delay" in config:
            recommendation.streaming_delay = config["streaming_delay"]
        
        # Set fallback
        if tier in ("ultra", "high"):
            fallback_config = self.TIER_CONFIGS["medium"].copy()
            recommendation.fallback = ProviderRecommendation(
                provider=fallback_config["provider"],
                model=fallback_config["model"],
                chunk_seconds=fallback_config["chunk_seconds"],
                compute_type=fallback_config["compute_type"],
                device=fallback_config["device"],
                vad_enabled=fallback_config["vad_enabled"],
                reason="Fallback if primary provider fails",
            )
        
        logger.info(f"Recommendation: {recommendation.provider}/{recommendation.model} ({reason})")
        return recommendation

    def _whisper_cpp_available(self) -> bool:
        """Check if whisper.cpp is available."""
        try:
            from .asr_providers import ASRConfig
            from . import provider_whisper_cpp

            provider = provider_whisper_cpp.WhisperCppProvider(
                ASRConfig(model_name="base.en", device="auto", compute_type="int8")
            )
            return bool(provider.is_available)
        except Exception as e:  # pragma: no cover - best-effort probe
            logger.debug("whisper.cpp availability probe failed: %s", e)
            return False

    def _voxtral_available(self) -> bool:
        """Check if voxtral is available."""
        try:
            from .asr_providers import ASRConfig
            from . import provider_voxtral_realtime

            provider = provider_voxtral_realtime.VoxtralRealtimeProvider(
                ASRConfig(model_name="base", device="auto", compute_type="bf16")
            )
            return bool(provider.is_available)
        except Exception as e:  # pragma: no cover - best-effort probe
            logger.debug("voxtral availability probe failed: %s", e)
            return False

    def can_run_model(self, model: str, profile: Optional[MachineProfile] = None) -> tuple[bool, str]:
        """Check if a specific model can run on this machine.
        
        Args:
            model: Model name (e.g., "base.en", "small.en", "large-v3", "voxtral_4b")
            profile: MachineProfile from detect(). If None, calls detect().
        
        Returns:
            Tuple of (can_run, reason)
        """
        if profile is None:
            profile = self.detect()
        
        # Map model names to RAM requirements
        model_lower = model.lower()
        required_ram = None
        
        for key, ram_gb in self.RAM_REQUIREMENTS.items():
            if key in model_lower:
                required_ram = ram_gb
                break
        
        if required_ram is None:
            # Unknown model, assume it needs 8GB
            required_ram = 8
        
        available_ram = profile.ram_gb * 0.8  # Leave 20% for OS/other apps
        
        if available_ram < required_ram:
            return False, f"Insufficient RAM: {model} needs ~{required_ram}GB, available ~{available_ram:.1f}GB"
        
        return True, f"Can run {model} with {profile.ram_gb:.1f}GB RAM"


def get_optimal_config() -> Dict[str, Any]:
    """Convenience function to get optimal ASR configuration for this machine.
    
    Returns:
        Dict with provider, model, and configuration settings.
    """
    detector = CapabilityDetector()
    profile = detector.detect()
    recommendation = detector.recommend(profile)
    
    return {
        "profile": profile.to_dict(),
        "recommendation": recommendation.to_dict(),
        "env_vars": {
            "ECHOPANEL_ASR_PROVIDER": recommendation.provider,
            "ECHOPANEL_WHISPER_MODEL": recommendation.model,
            "ECHOPANEL_ASR_CHUNK_SECONDS": str(recommendation.chunk_seconds),
            "ECHOPANEL_WHISPER_COMPUTE": recommendation.compute_type,
            "ECHOPANEL_WHISPER_DEVICE": recommendation.device,
            "ECHOPANEL_ASR_VAD": "1" if recommendation.vad_enabled else "0",
        },
    }


if __name__ == "__main__":
    # Run standalone to check machine capabilities
    logging.basicConfig(level=logging.INFO)
    
    detector = CapabilityDetector()
    profile = detector.detect()
    
    print("=" * 60)
    print("EchoPanel Machine Capability Detection")
    print("=" * 60)
    print(f"\nHardware Profile:")
    for key, value in profile.to_dict().items():
        print(f"  {key}: {value}")
    
    print(f"\nASR Recommendations:")
    recommendation = detector.recommend(profile)
    rec_dict = recommendation.to_dict()
    for key, value in rec_dict.items():
        if key != "fallback":
            print(f"  {key}: {value}")
    
    if recommendation.fallback:
        print(f"\n  Fallback:")
        for key, value in recommendation.fallback.to_dict().items():
            print(f"    {key}: {value}")
    
    print(f"\nEnvironment Variables:")
    config = get_optimal_config()
    for key, value in config["env_vars"].items():
        print(f"  export {key}={value}")
    
    print("\n" + "=" * 60)
