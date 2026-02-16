"""
EchoPanel Server Services Package.

This package provides ASR (Automatic Speech Recognition) providers,
OCR (Optical Character Recognition) services, and related utilities
for real-time transcription and screen content analysis.

Available ASR Providers:
- faster_whisper: CTranslate2-based Whisper (CPU on macOS)
- whisper_cpp: whisper.cpp with Metal GPU support
- mlx_whisper: MLX-native Whisper for Apple Silicon
- onnx_whisper: ONNX Runtime with CoreML (placeholder)
- voxtral_official: Official Mistral Voxtral
- voxtral_realtime: Third-party C port (use with caution)

Available OCR Services:
- Hybrid OCR: PaddleOCR v5 (fast) + SmolVLM (smart)
- Layout Classification: Detect slide content types
- Fusion Engine: Intelligent result merging
"""

# ASR Providers
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

# OCR Services
try:
    from .screen_ocr import (
        OCResult,
        OCRFrameHandler,
        ScreenOCRPipeline,
        get_ocr_handler,
        reset_ocr_handler,
    )
except ImportError:
    OCResult = None
    OCRFrameHandler = None
    ScreenOCRPipeline = None
    get_ocr_handler = None
    reset_ocr_handler = None

try:
    from .ocr_hybrid import HybridOCRPipeline, OCRMode, VLMTriggerMode
except ImportError:
    HybridOCRPipeline = None
    OCRMode = None
    VLMTriggerMode = None

try:
    from .ocr_fusion import FusionEngine, HybridOCRResult
except ImportError:
    FusionEngine = None
    HybridOCRResult = None

try:
    from .ocr_layout_classifier import LayoutClassifier, LayoutType
except ImportError:
    LayoutClassifier = None
    LayoutType = None

try:
    from .ocr_paddle import PaddleOCRPipeline, PaddleOCRResult
except ImportError:
    PaddleOCRPipeline = None
    PaddleOCRResult = None

try:
    from .ocr_smolvlm import Entity, SmolVLMPipeline, SmolVLMResult
except ImportError:
    Entity = None
    SmolVLMPipeline = None
    SmolVLMResult = None


__all__ = [
    # ASR
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
    # OCR Legacy
    "OCResult",
    "OCRFrameHandler",
    "ScreenOCRPipeline",
    "get_ocr_handler",
    "reset_ocr_handler",
    # OCR Hybrid (New)
    "HybridOCRPipeline",
    "HybridOCRResult",
    "OCRMode",
    "VLMTriggerMode",
    "FusionEngine",
    "LayoutClassifier",
    "LayoutType",
    "PaddleOCRPipeline",
    "PaddleOCRResult",
    "SmolVLMPipeline",
    "SmolVLMResult",
    "Entity",
]
