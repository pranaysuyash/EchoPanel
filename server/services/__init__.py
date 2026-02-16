"""
EchoPanel Server Services Package.

This package provides ASR (Automatic Speech Recognition) providers
and related services for real-time transcription.

Available ASR Providers:
- faster_whisper: CTranslate2-based Whisper (CPU on macOS)
- whisper_cpp: whisper.cpp with Metal GPU support
- mlx_whisper: MLX-native Whisper for Apple Silicon
- onnx_whisper: ONNX Runtime with CoreML (placeholder)
- voxtral_official: Official Mistral Voxtral (mistralai/Voxtral-Mini-4B-Realtime-2602)
- voxtral_realtime: ⚠️ Third-party C port (antirez/voxtral.c) - use with caution
"""

from .asr_providers import (
    ASRConfig,
    ASRProvider,
    ASRProviderRegistry,
    ASRSegment,
    AudioSource,
)

# Import provider implementations (these auto-register)
try:
    from .provider_faster_whisper import FasterWhisperProvider
except ImportError:
    FasterWhisperProvider = None

try:
    from .provider_whisper_cpp import WhisperCppProvider
except ImportError:
    WhisperCppProvider = None

try:
    from .provider_mlx_whisper import MLXWhisperProvider
except ImportError:
    MLXWhisperProvider = None

try:
    from .provider_onnx_whisper import ONNXWhisperProvider
except ImportError:
    ONNXWhisperProvider = None

try:
    from .provider_voxtral_realtime import VoxtralRealtimeProvider
except ImportError:
    VoxtralRealtimeProvider = None

try:
    from .provider_voxtral_official import VoxtralOfficialProvider
except ImportError:
    VoxtralOfficialProvider = None

__all__ = [
    "ASRConfig",
    "ASRProvider",
    "ASRProviderRegistry",
    "ASRSegment",
    "AudioSource",
    "FasterWhisperProvider",
    "MLXWhisperProvider",
    "ONNXWhisperProvider",
    "VoxtralOfficialProvider",
    "VoxtralRealtimeProvider",
    "WhisperCppProvider",
]
