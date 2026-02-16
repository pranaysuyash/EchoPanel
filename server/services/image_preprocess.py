"""
Image Preprocessing for OCR Pipeline

Optimizes images for Tesseract OCR accuracy through:
- Grayscale conversion
- Contrast enhancement
- Resizing (performance)
- Denoising
"""

from io import BytesIO
from typing import Optional, Tuple

try:
    from PIL import Image, ImageEnhance, ImageFilter
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    Image = None
    ImageEnhance = None
    ImageFilter = None


class ImagePreprocessor:
    """Preprocess images for optimal OCR accuracy."""
    
    def __init__(
        self,
        max_dimension: int = 1280,
        contrast_factor: float = 2.0,
        sharpen_factor: float = 1.5,
        denoise_radius: float = 0.5
    ):
        self.max_dimension = max_dimension
        self.contrast_factor = contrast_factor
        self.sharpen_factor = sharpen_factor
        self.denoise_radius = denoise_radius
    
    def preprocess(self, image: Image.Image) -> Image.Image:
        """
        Full preprocessing pipeline for OCR.
        
        Args:
            image: PIL Image (any mode)
            
        Returns:
            Preprocessed PIL Image (grayscale)
        """
        # 1. Convert to RGB if necessary
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        # 2. Resize if too large (maintain aspect ratio)
        image = self._resize_if_needed(image)
        
        # 3. Convert to grayscale
        image = image.convert('L')
        
        # 4. Enhance contrast
        image = self._enhance_contrast(image)
        
        # 5. Denoise (mild blur then sharpen)
        image = self._denoise(image)
        
        return image
    
    def preprocess_from_bytes(self, image_bytes: bytes) -> Optional[Image.Image]:
        """
        Preprocess image from raw bytes.
        
        Args:
            image_bytes: Raw image data (JPEG, PNG, etc.)
            
        Returns:
            Preprocessed PIL Image or None if invalid
        """
        if not PIL_AVAILABLE:
            raise ImportError("Pillow is required for image preprocessing")
        
        try:
            image = Image.open(BytesIO(image_bytes))
            return self.preprocess(image)
        except Exception as e:
            # Log error and return None
            return None
    
    def _resize_if_needed(self, image: Image.Image) -> Image.Image:
        """Resize image if it exceeds max dimension."""
        max_dim = max(image.width, image.height)
        
        if max_dim > self.max_dimension:
            ratio = self.max_dimension / max_dim
            new_size = (int(image.width * ratio), int(image.height * ratio))
            return image.resize(new_size, Image.Resampling.LANCZOS)
        
        return image
    
    def _enhance_contrast(self, image: Image.Image) -> Image.Image:
        """Increase contrast for better text detection."""
        enhancer = ImageEnhance.Contrast(image)
        return enhancer.enhance(self.contrast_factor)
    
    def _denoise(self, image: Image.Image) -> Image.Image:
        """Apply mild denoising while preserving text edges."""
        # Mild gaussian blur to reduce noise
        blurred = image.filter(ImageFilter.GaussianBlur(radius=self.denoise_radius))
        
        # Sharpen to restore text edges
        sharpened = blurred.filter(ImageFilter.SHARPEN)
        
        # Additional sharpening if configured
        if self.sharpen_factor > 1.0:
            enhancer = ImageEnhance.Sharpness(sharpened)
            sharpened = enhancer.enhance(self.sharpen_factor)
        
        return sharpened
    
    def get_image_info(self, image: Image.Image) -> dict:
        """Get information about the image."""
        return {
            "width": image.width,
            "height": image.height,
            "mode": image.mode,
            "format": getattr(image, 'format', 'Unknown'),
        }


def preprocess_for_ocr(
    image_bytes: bytes,
    max_dimension: int = 1280
) -> Optional[Image.Image]:
    """
    Convenience function for one-shot preprocessing.
    
    Args:
        image_bytes: Raw image data
        max_dimension: Maximum width or height
        
    Returns:
        Preprocessed PIL Image or None
    """
    if not PIL_AVAILABLE:
        raise ImportError("Pillow is required. Install with: pip install Pillow")
    
    preprocessor = ImagePreprocessor(max_dimension=max_dimension)
    return preprocessor.preprocess_from_bytes(image_bytes)


def decode_base64_image(base64_string: str) -> Optional[bytes]:
    """Decode base64 image string to bytes."""
    import base64
    try:
        return base64.b64decode(base64_string)
    except Exception:
        return None
