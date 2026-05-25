"""Embedding service for semantic search.

This module provides text embedding generation using sentence-transformers
or other embedding models. It's designed to work with the Brain Dump
storage system for semantic search capabilities.
"""

import logging
import math
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple

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
    
    def __init__(self, model_name: Optional[str] = None, cache_path: Optional[Path] = None):
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
        self.cache_path = Path(cache_path) if cache_path else None
        self._cache: Dict[str, List[float]] = {}
    
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

    def embed_text(self, text: str) -> Optional[List[float]]:
        """Backward-compatible single-text embed API used by older callers."""
        if text is None or not str(text).strip():
            return None

        if not self.is_available():
            return None

        try:
            return self.encode_single(text)
        except Exception:
            return None

    @staticmethod
    def _cache_key(document_id: str, chunk_index: int) -> str:
        return f"{document_id}_{int(chunk_index)}"

    def cache_size(self) -> int:
        return len(self._cache)

    def get_embedding(self, document_id: str, chunk_index: int) -> Optional[List[float]]:
        return self._cache.get(self._cache_key(document_id, chunk_index))

    def get_document_embeddings(self, document_id: str) -> Dict[int, List[float]]:
        prefix = f"{document_id}_"
        out: Dict[int, List[float]] = {}
        for key, value in self._cache.items():
            if key.startswith(prefix):
                try:
                    idx = int(key[len(prefix):])
                    out[idx] = value
                except ValueError:
                    continue
        return out

    def delete_document_embeddings(self, document_id: str) -> int:
        prefix = f"{document_id}_"
        keys = [k for k in self._cache.keys() if k.startswith(prefix)]
        for key in keys:
            self._cache.pop(key, None)
        return len(keys)

    def clear_cache(self) -> int:
        count = len(self._cache)
        self._cache.clear()
        return count

    @staticmethod
    def cosine_similarity(v1: List[float], v2: List[float]) -> float:
        if not v1 or not v2 or len(v1) != len(v2):
            return 0.0

        dot = sum(a * b for a, b in zip(v1, v2))
        n1 = math.sqrt(sum(a * a for a in v1))
        n2 = math.sqrt(sum(b * b for b in v2))
        if n1 == 0.0 or n2 == 0.0:
            return 0.0
        return dot / (n1 * n2)

    def find_similar(
        self,
        query_embedding: List[float],
        document_id: str,
        top_k: int = 5
    ) -> List[Tuple[int, float]]:
        candidates = self.get_document_embeddings(document_id)
        scored: List[Tuple[int, float]] = []
        for idx, emb in candidates.items():
            sim = self.cosine_similarity(query_embedding, emb)
            scored.append((idx, sim))
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[: max(1, int(top_k))]

    def generate_document_embeddings(self, document_id: str, chunks: List[dict]) -> int:
        """Generate and cache embeddings for chunk dictionaries.

        Expected chunk schema includes: chunk_index (int), text (str)
        """
        if not self.is_available():
            return 0

        texts: List[str] = []
        indices: List[int] = []
        for chunk in chunks:
            idx = int(chunk.get("chunk_index", 0))
            txt = str(chunk.get("text", "")).strip()
            if txt:
                indices.append(idx)
                texts.append(txt)

        if not texts:
            return 0

        try:
            embeddings = self.encode(texts)
        except Exception:
            return 0

        for idx, emb in zip(indices, embeddings):
            self._cache[self._cache_key(document_id, idx)] = emb

        return len(indices)
    
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
