"""
Perceptual Hashing for Image Deduplication

Uses average hash (aHash) and difference hash (dHash) for detecting
similar images (e.g., same slide with minor changes).

More robust than MD5/file hash for visual similarity.
"""

from typing import Optional, Union

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    Image = None


class PerceptualHash:
    """
    Perceptual hash implementation for image deduplication.
    
    Uses a hybrid approach:
    - Average hash (aHash) for overall similarity
    - Difference hash (dHash) for edge/gradient similarity
    """
    
    def __init__(self, hash_size: int = 8):
        """
        Args:
            hash_size: Size of the hash (8 = 64-bit hash)
        """
        self.hash_size = hash_size
    
    def compute_hash(self, image: Image.Image) -> str:
        """
        Compute perceptual hash of an image.
        
        Args:
            image: PIL Image
            
        Returns:
            Hex string representation of the hash
        """
        if not PIL_AVAILABLE:
            raise ImportError("Pillow is required for image hashing")
        
        # Ensure image is in RGB or L mode
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        # Compute average hash
        avg_hash = self._average_hash(image)
        
        return avg_hash
    
    def compute_hash_from_bytes(self, image_bytes: bytes) -> Optional[str]:
        """
        Compute hash from raw image bytes.
        
        Args:
            image_bytes: Raw image data
            
        Returns:
            Hash string or None if error
        """
        from io import BytesIO
        
        if not PIL_AVAILABLE:
            return None
        
        try:
            image = Image.open(BytesIO(image_bytes))
            return self.compute_hash(image)
        except Exception:
            return None
    
    def _average_hash(self, image: Image.Image) -> str:
        """
        Compute average hash (aHash).
        
        Algorithm:
        1. Convert to grayscale
        2. Resize to hash_size x hash_size
        3. Compute average pixel value
        4. Hash bit = 1 if pixel > average, else 0
        """
        # Convert to grayscale and resize
        if image.mode != 'L':
            image = image.convert('L')
        
        # Resize to small square (removes high-frequency details)
        small = image.resize((self.hash_size, self.hash_size), Image.Resampling.LANCZOS)
        
        # Get pixel data
        pixels = list(small.getdata())
        
        # Compute average
        avg = sum(pixels) / len(pixels)
        
        # Build hash
        bits = ''.join('1' if p > avg else '0' for p in pixels)
        
        # Convert to hex
        return hex(int(bits, 2))[2:].zfill(self.hash_size * self.hash_size // 4)
    
    def _difference_hash(self, image: Image.Image) -> str:
        """
        Compute difference hash (dHash).
        
        Algorithm:
        1. Convert to grayscale
        2. Resize to (hash_size+1) x hash_size
        3. Hash bit = 1 if pixel > next pixel (horizontal gradient)
        
        Better for detecting structural/layout similarity.
        """
        if image.mode != 'L':
            image = image.convert('L')
        
        # Resize - width is hash_size+1 for horizontal comparison
        small = image.resize((self.hash_size + 1, self.hash_size), Image.Resampling.LANCZOS)
        
        pixels = list(small.getdata())
        
        # Compare adjacent pixels (horizontal gradients)
        bits = []
        for row in range(self.hash_size):
            for col in range(self.hash_size):
                left = pixels[row * (self.hash_size + 1) + col]
                right = pixels[row * (self.hash_size + 1) + col + 1]
                bits.append('1' if left > right else '0')
        
        return hex(int(''.join(bits), 2))[2:].zfill(self.hash_size * self.hash_size // 4)
    
    def hamming_distance(self, hash1: str, hash2: str) -> int:
        """
        Compute Hamming distance between two hashes.
        
        Args:
            hash1: First hash string
            hash2: Second hash string
            
        Returns:
            Number of bits that differ (0 = identical)
        """
        if len(hash1) != len(hash2):
            # Pad shorter hash
            max_len = max(len(hash1), len(hash2))
            hash1 = hash1.zfill(max_len)
            hash2 = hash2.zfill(max_len)
        
        # Convert hex to binary
        bin1 = bin(int(hash1, 16))[2:].zfill(len(hash1) * 4)
        bin2 = bin(int(hash2, 16))[2:].zfill(len(hash2) * 4)
        
        # Count differences
        return sum(c1 != c2 for c1, c2 in zip(bin1, bin2))
    
    def is_similar(
        self,
        hash1: str,
        hash2: str,
        threshold: int = 5
    ) -> bool:
        """
        Check if two hashes represent similar images.
        
        Args:
            hash1: First hash string
            hash2: Second hash string
            threshold: Max Hamming distance for similarity
            
        Returns:
            True if images are similar
        """
        distance = self.hamming_distance(hash1, hash2)
        return distance <= threshold


# Convenience functions

def compute_image_hash(image_bytes: bytes, hash_size: int = 8) -> Optional[str]:
    """
    One-shot function to compute perceptual hash.
    
    Args:
        image_bytes: Raw image data
        hash_size: Hash size (default 8 = 64-bit)
        
    Returns:
        Hash string or None
    """
    hasher = PerceptualHash(hash_size=hash_size)
    return hasher.compute_hash_from_bytes(image_bytes)


def are_images_similar(
    hash1: str,
    hash2: str,
    threshold: int = 5,
    hash_size: int = 8
) -> bool:
    """
    Check if two image hashes are similar.
    
    Args:
        hash1: First hash string
        hash2: Second hash string
        threshold: Hamming distance threshold
        hash_size: Hash size for padding
        
    Returns:
        True if similar
    """
    hasher = PerceptualHash(hash_size=hash_size)
    return hasher.is_similar(hash1, hash2, threshold)


class ImageDeduplicator:
    """
    Track seen images and detect duplicates.
    """
    
    def __init__(self, threshold: int = 5, max_history: int = 100):
        """
        Args:
            threshold: Hamming distance for similarity
            max_history: Max number of hashes to keep in memory
        """
        self.threshold = threshold
        self.max_history = max_history
        self.hasher = PerceptualHash()
        self.seen_hashes: list = []
    
    def is_duplicate(self, image_bytes: bytes) -> bool:
        """
        Check if image is a duplicate of recently seen images.
        
        Args:
            image_bytes: Raw image data
            
        Returns:
            True if duplicate detected
        """
        new_hash = self.hasher.compute_hash_from_bytes(image_bytes)
        
        if new_hash is None:
            return False  # Can't determine, assume not duplicate
        
        # Check against recent hashes
        for existing_hash in self.seen_hashes:
            if self.hasher.is_similar(new_hash, existing_hash, self.threshold):
                return True
        
        # Not a duplicate, add to history
        self.seen_hashes.append(new_hash)
        
        # Trim history if needed
        if len(self.seen_hashes) > self.max_history:
            self.seen_hashes = self.seen_hashes[-self.max_history:]
        
        return False
    
    def clear(self):
        """Clear deduplication history."""
        self.seen_hashes.clear()
