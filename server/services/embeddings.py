"""Embedding service for semantic search.

This module provides text embedding generation using sentence-transformers
or other embedding models. It's designed to work with the Brain Dump
storage system for semantic search capabilities.
"""

import logging
import os
from typing import List, Optional

logger = logging.getLogger(__name__)


class EmbeddingService:
    """Service for generating text embeddings.
    
    Uses sentence-transformers by default, but can be extended to use
    other embedding providers (OpenAI, local MLX models, etc.)
    
    Usage:
        service = EmbeddingService()
        if service.is_available():
            embeddings = service.encode(["text to embed"])
    """
    
    def __init__(self, model_name: Optional[str] = None):
        """Initialize embedding service.
        
        Args:
            model_name: Name of the sentence-transformers model to use.
                       Defaults to "all-MiniLM-L6-v2" (384 dims, fast).
        """
        self.model_name = model_name or os.getenv(
            "ECHOPANEL_EMBEDDING_MODEL", 
            "all-MiniLM-L6-v2"
        )
        self._model = None
        self._dimension: Optional[int] = None
    
    def is_available(self) -> bool:
        """Check if embedding service is available.
        
        Returns:
            True if sentence-transformers is installed and working
        """
        try:
            import sentence_transformers
            return True
        except ImportError:
            return False
    
    def _load_model(self):
        """Lazy load the embedding model."""
        if self._model is None:
            if not self.is_available():
                raise RuntimeError(
                    "sentence-transformers not installed. "
                    "Install with: pip install sentence-transformers"
                )
            
            from sentence_transformers import SentenceTransformer
            logger.info(f"Loading embedding model: {self.model_name}")
            self._model = SentenceTransformer(self.model_name)
            self._dimension = self._model.get_sentence_embedding_dimension()
            logger.info(f"Embedding model loaded: {self._dimension} dimensions")
        
        return self._model
    
    def warmup(self) -> None:
        """Warm up the model by loading it.
        
        Call this at startup to avoid first-request latency.
        """
        try:
            self._load_model()
            # Run a dummy embedding to fully initialize
            self.encode(["warmup"])
            logger.info("Embedding model warmed up")
        except Exception as e:
            logger.warning(f"Embedding model warmup failed: {e}")
    
    def encode(
        self, 
        texts: List[str], 
        batch_size: int = 32,
        show_progress: bool = False
    ) -> List[List[float]]:
        """Generate embeddings for texts.
        
        Args:
            texts: List of text strings to embed
            batch_size: Batch size for processing
            show_progress: Whether to show progress bar
            
        Returns:
            List of embedding vectors (each is a list of floats)
            
        Raises:
            RuntimeError: If sentence-transformers is not available
        """
        model = self._load_model()
        
        # Filter out empty strings
        valid_texts = [t if t.strip() else " " for t in texts]
        
        embeddings = model.encode(
            valid_texts,
            batch_size=batch_size,
            show_progress_bar=show_progress,
            convert_to_numpy=True
        )
        
        # Convert to list of lists
        return embeddings.tolist()
    
    def encode_single(self, text: str) -> List[float]:
        """Generate embedding for a single text.
        
        Args:
            text: Text to embed
            
        Returns:
            Embedding vector
        """
        embeddings = self.encode([text])
        return embeddings[0]
    
    @property
    def dimension(self) -> int:
        """Get embedding dimension.
        
        Returns:
            Size of embedding vectors
        """
        if self._dimension is None:
            self._load_model()
        return self._dimension


# Global singleton instance
_embedding_service: Optional[EmbeddingService] = None


def get_embedding_service() -> EmbeddingService:
    """Get the global embedding service instance.
    
    Returns:
        EmbeddingService singleton
    """
    global _embedding_service
    if _embedding_service is None:
        _embedding_service = EmbeddingService()
    return _embedding_service


def reset_embedding_service() -> None:
    """Reset the global embedding service (mainly for testing)."""
    global _embedding_service
    _embedding_service = None
