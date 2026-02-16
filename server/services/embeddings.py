"""
Embedding Generation Service for EchoPanel.

Provides semantic embeddings for RAG documents using sentence-transformers.
Enables semantic search and improved document retrieval.
"""

import json
import logging
import math
import os
import threading
from collections import OrderedDict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

# QW-002: Embedding cache configuration
EMBEDDING_CACHE_MAX_SIZE_ENV = "ECHOPANEL_EMBEDDING_CACHE_MAX_SIZE"
DEFAULT_CACHE_MAX_SIZE = 10000  # Max number of embeddings in memory

EMBEDDING_MODEL_ENV = "ECHOPANEL_EMBEDDING_MODEL"
EMBEDDING_DIM_ENV = "ECHOPANEL_EMBEDDING_DIMENSION"
EMBEDDING_CACHE_PATH_ENV = "ECHOPANEL_EMBEDDING_CACHE_PATH"

DEFAULT_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
DEFAULT_DIMENSION = 384


class EmbeddingService:
    """
    Service for generating and storing document embeddings.
    
    Uses sentence-transformers/all-MiniLM-L6-v2 by default.
    Stores embeddings in a local JSON cache for persistence.
    
    QW-002: Implements LRU cache eviction to prevent unbounded growth.
    """
    
    def __init__(
        self,
        model_name: Optional[str] = None,
        cache_path: Optional[Path] = None,
        device: Optional[str] = None,
        max_cache_size: Optional[int] = None
    ):
        self.model_name = model_name or os.getenv(EMBEDDING_MODEL_ENV, DEFAULT_MODEL)
        self.embedding_dim = int(os.getenv(EMBEDDING_DIM_ENV, DEFAULT_DIMENSION))
        self.cache_path = cache_path or self._default_cache_path()
        self._lock = threading.RLock()
        self._model = None
        self._model_lock = threading.Lock()
        self._device = device or self._get_default_device()
        # QW-002: Use OrderedDict for LRU tracking
        self._max_cache_size = max_cache_size or int(os.getenv(EMBEDDING_CACHE_MAX_SIZE_ENV, str(DEFAULT_CACHE_MAX_SIZE)))
        self._cache: OrderedDict[str, List[float]] = OrderedDict()
        # QW-002: Cache statistics
        self._cache_hits = 0
        self._cache_misses = 0
        self._load_cache()
    
    def _default_cache_path(self) -> Path:
        override = os.getenv(EMBEDDING_CACHE_PATH_ENV, "").strip()
        if override:
            return Path(override).expanduser()
        return Path.home() / ".echopanel" / "embeddings_cache.json"
    
    def _get_default_device(self) -> str:
        try:
            import torch
            if torch.cuda.is_available():
                return "cuda"
        except ImportError:
            pass
        return "cpu"
    
    def _load_model(self):
        """Lazy load the embedding model."""
        if self._model is not None:
            return
        
        with self._model_lock:
            if self._model is not None:
                return
            
            try:
                from sentence_transformers import SentenceTransformer
                self._model = SentenceTransformer(self.model_name, device=self._device)
            except ImportError:
                raise ImportError(
                    f"sentence-transformers not installed. "
                    f"Install with: pip install sentence-transformers"
                )
    
    def _load_cache(self) -> None:
        """Load embeddings cache from disk."""
        if self.cache_path.exists():
            try:
                with open(self.cache_path, 'r', encoding='utf-8') as f:
                    loaded = json.load(f)
                    # QW-002: Convert to OrderedDict for LRU tracking
                    if isinstance(loaded, dict):
                        self._cache = OrderedDict(loaded)
                    else:
                        self._cache = OrderedDict()
            except Exception:
                self._cache = OrderedDict()
    
    def _save_cache(self) -> None:
        """Save embeddings cache to disk."""
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = self.cache_path.with_suffix(".tmp")
        try:
            with self._lock:
                # Convert OrderedDict to regular dict for JSON serialization
                with open(temp_path, 'w', encoding='utf-8') as f:
                    json.dump(dict(self._cache), f, indent=2)
            temp_path.replace(self.cache_path)
        except Exception:
            if temp_path.exists():
                temp_path.unlink()
    
    def _evict_if_needed(self) -> None:
        """QW-002: Evict oldest entries if cache exceeds max size."""
        with self._lock:
            while len(self._cache) > self._max_cache_size:
                # OrderedDict maintains insertion order; oldest is first
                oldest_key = next(iter(self._cache))
                del self._cache[oldest_key]
                logger.debug(f"LRU evicted embedding: {oldest_key}")
    
    def get_cache_stats(self) -> dict:
        """QW-002: Get cache statistics."""
        with self._lock:
            total = self._cache_hits + self._cache_misses
            hit_ratio = self._cache_hits / total if total > 0 else 0.0
            return {
                "size": len(self._cache),
                "max_size": self._max_cache_size,
                "hits": self._cache_hits,
                "misses": self._cache_misses,
                "hit_ratio": round(hit_ratio, 4),
            }
    
    def warmup(self) -> None:
        """Warm up the model for faster first inference."""
        self._load_model()
        if self._model is not None:
            self._model.warmup()
    
    def is_available(self) -> bool:
        """Check if embedding service is available."""
        try:
            self._load_model()
            return self._model is not None
        except ImportError:
            return False
    
    def embed_text(self, text: str) -> Optional[List[float]]:
        """Generate embedding for a single text."""
        if not text or not text.strip():
            return None
        
        self._load_model()
        if self._model is None:
            return None
        
        try:
            embedding = self._model.encode(text.strip(), normalize_embeddings=True)
            return embedding.tolist()
        except Exception:
            return None
    
    def embed_texts(self, texts: List[str]) -> Tuple[List[List[float]], List[str]]:
        """Generate embeddings for multiple texts."""
        valid_embeddings: List[List[float]] = []
        valid_indices: List[int] = []
        
        if not texts:
            return [], []
        
        self._load_model()
        if self._model is None:
            return [], []
        
        try:
            embeddings = self._model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
            
            for i, (text, embedding) in enumerate(zip(texts, embeddings)):
                if text and text.strip():
                    valid_embeddings.append(embedding.tolist())
                    valid_indices.append(i)
            
            return valid_embeddings, valid_indices
        except Exception:
            return [], []
    
    def generate_chunk_embedding(self, chunk_text: str, chunk_index: int, document_id: str) -> Optional[Dict]:
        """Generate embedding for a document chunk."""
        embedding = self.embed_text(chunk_text)
        
        if embedding is None:
            return None
        
        with self._lock:
            cache_key = f"{document_id}_{chunk_index}"
            # QW-002: Add to cache and evict if needed
            self._cache[cache_key] = embedding
            self._cache.move_to_end(cache_key)  # Mark as most recent
            self._evict_if_needed()
            self._save_cache()
        
        return {
            "chunk_index": chunk_index,
            "document_id": document_id,
            "embedding": embedding,
            "dimension": len(embedding),
        }
    
    def generate_document_embeddings(
        self,
        document_id: str,
        chunks: List[Dict]
    ) -> List[Dict]:
        """Generate embeddings for all chunks in a document."""
        if not chunks:
            return []
        
        texts = [chunk.get("text", "") for chunk in chunks]
        embeddings, valid_indices = self.embed_texts(texts)
        
        results = []
        for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
            if i in valid_indices:
                chunk_index = chunk.get("chunk_index", i)
                cache_key = f"{document_id}_{chunk_index}"
                
                with self._lock:
                    self._cache[cache_key] = embedding
                    self._cache.move_to_end(cache_key)  # QW-002: Mark as most recent
                
                results.append({
                    "chunk_index": chunk_index,
                    "document_id": document_id,
                    "embedding": embedding,
                    "dimension": len(embedding),
                })
        
        with self._lock:
            # QW-002: Evict if needed after batch insert
            self._evict_if_needed()
            self._save_cache()
        
        return results
    
    def get_embedding(self, document_id: str, chunk_index: int) -> Optional[List[float]]:
        """Get cached embedding for a document chunk."""
        with self._lock:
            cache_key = f"{document_id}_{chunk_index}"
            embedding = self._cache.get(cache_key)
            # QW-002: Track stats and mark as recently used
            if embedding is not None:
                self._cache_hits += 1
                self._cache.move_to_end(cache_key)
            else:
                self._cache_misses += 1
            return embedding
    
    def get_document_embeddings(self, document_id: str) -> Dict[int, List[float]]:
        """Get all cached embeddings for a document."""
        results: Dict[int, List[float]] = {}
        with self._lock:
            for key, embedding in self._cache.items():
                if key.startswith(f"{document_id}_"):
                    parts = key.split("_")
                    if len(parts) == 2:
                        try:
                            chunk_idx = int(parts[1])
                            results[chunk_idx] = embedding
                        except ValueError:
                            continue
        return results
    
    def delete_document_embeddings(self, document_id: str) -> int:
        """Delete all embeddings for a document. Returns count deleted."""
        keys_to_delete = []
        with self._lock:
            for key in self._cache:
                if key.startswith(f"{document_id}_"):
                    keys_to_delete.append(key)
            
            for key in keys_to_delete:
                del self._cache[key]
            
            if keys_to_delete:
                self._save_cache()
        
        return len(keys_to_delete)
    
    def cosine_similarity(self, embedding1: List[float], embedding2: List[float]) -> float:
        """Calculate cosine similarity between two embeddings."""
        if not embedding1 or not embedding2:
            return 0.0
        
        vec1 = np.array(embedding1)
        vec2 = np.array(embedding2)
        
        dot_product = np.dot(vec1, vec2)
        norm1 = np.linalg.norm(vec1)
        norm2 = np.linalg.norm(vec2)
        
        if norm1 == 0 or norm2 == 0:
            return 0.0
        
        return float(dot_product / (norm1 * norm2))
    
    def find_similar(
        self,
        query_embedding: List[float],
        document_id: str,
        top_k: int = 5
    ) -> List[Tuple[int, float]]:
        """Find most similar chunks in a document."""
        doc_embeddings = self.get_document_embeddings(document_id)
        
        if not doc_embeddings:
            return []
        
        similarities: List[Tuple[int, float]] = []
        for chunk_idx, embedding in doc_embeddings.items():
            sim = self.cosine_similarity(query_embedding, embedding)
            similarities.append((chunk_idx, sim))
        
        similarities.sort(key=lambda x: x[1], reverse=True)
        
        return similarities[:top_k]
    
    def clear_cache(self) -> int:
        """Clear all cached embeddings. Returns count cleared."""
        with self._lock:
            count = len(self._cache)
            self._cache = OrderedDict()
            self._cache_hits = 0
            self._cache_misses = 0
            self._save_cache()
        return count
    
    def cache_size(self) -> int:
        """Return number of cached embeddings."""
        with self._lock:
            return len(self._cache)


_service_lock = threading.Lock()
_service: Optional[EmbeddingService] = None


def get_embedding_service(
    model_name: Optional[str] = None,
    cache_path: Optional[Path] = None,
    device: Optional[str] = None
) -> EmbeddingService:
    """Get or create the global embedding service instance."""
    global _service
    
    if _service is not None:
        return _service
    
    with _service_lock:
        if _service is None:
            _service = EmbeddingService(model_name=model_name, cache_path=cache_path, device=device)
        return _service


def reset_embedding_service_for_tests(
    model_name: Optional[str] = None,
    cache_path: Optional[Path] = None
) -> EmbeddingService:
    """Reset the embedding service for testing."""
    global _service
    
    with _service_lock:
        _service = EmbeddingService(model_name=model_name, cache_path=cache_path)
        return _service
