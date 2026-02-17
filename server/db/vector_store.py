"""Vector storage using ChromaDB for semantic search.

This module provides a vector database interface using ChromaDB
for storing and querying transcript embeddings.
"""

import logging
from pathlib import Path
from typing import List, Optional
from uuid import UUID

import chromadb
from chromadb.config import Settings

from .models import TranscriptSegment, SearchResult, Session

logger = logging.getLogger(__name__)


class VectorStore:
    """Vector database for transcript embeddings.
    
    Uses ChromaDB for efficient similarity search.
    
    Usage:
        store = VectorStore(persist_directory="~/.echopanel/vector_db")
        await store.initialize()
        
        # Add embeddings
        await store.add_segments(segments, embeddings)
        
        # Search
        results = await store.similarity_search(query_embedding, k=10)
    """
    
    def __init__(
        self, 
        persist_directory: Optional[str] = None,
        collection_name: str = "transcript_segments"
    ):
        """Initialize vector store.
        
        Args:
            persist_directory: Where to store ChromaDB files.
                             Defaults to ~/.echopanel/vector_db
            collection_name: Name of the collection
        """
        if persist_directory is None:
            persist_directory = str(Path.home() / ".echopanel" / "vector_db")
        
        self.persist_directory = Path(persist_directory).expanduser()
        self.persist_directory.parent.mkdir(parents=True, exist_ok=True)
        self.collection_name = collection_name
        
        self._client: Optional[chromadb.Client] = None
        self._collection: Optional[chromadb.Collection] = None
    
    async def initialize(self) -> None:
        """Initialize ChromaDB client and collection."""
        logger.info(f"Initializing vector store at {self.persist_directory}")
        
        # Create ChromaDB client
        self._client = chromadb.PersistentClient(
            path=str(self.persist_directory),
            settings=Settings(
                anonymized_telemetry=False,
                allow_reset=True
            )
        )
        
        # Get or create collection
        self._collection = self._client.get_or_create_collection(
            name=self.collection_name,
            metadata={"hnsw:space": "cosine"}  # Use cosine similarity
        )
        
        logger.info(f"Vector store initialized with collection: {self.collection_name}")
    
    async def close(self) -> None:
        """Close vector store connection."""
        # ChromaDB persists automatically
        self._collection = None
        self._client = None
        logger.info("Vector store closed")
    
    async def add_segments(
        self, 
        segments: List[TranscriptSegment],
        embeddings: List[List[float]]
    ) -> None:
        """Add segments with embeddings to vector store.
        
        Args:
            segments: List of transcript segments
            embeddings: List of embedding vectors (same order as segments)
        """
        if not self._collection:
            raise RuntimeError("Vector store not initialized")
        
        if len(segments) != len(embeddings):
            raise ValueError("Segments and embeddings must have same length")
        
        if not segments:
            return
        
        # Prepare data for ChromaDB
        ids = [str(s.id) for s in segments]
        documents = [s.text for s in segments]
        metadatas = []
        for s in segments:
            meta = {
                "session_id": str(s.session_id),
                "timestamp": s.timestamp.isoformat(),
                "source": s.source.value,
            }
            # Only add non-None values to avoid ChromaDB issues
            if s.relative_time is not None:
                meta["relative_time"] = float(s.relative_time)
            if s.speaker_id is not None:
                meta["speaker_id"] = str(s.speaker_id)
            if s.confidence is not None:
                meta["confidence"] = float(s.confidence)
            metadatas.append(meta)
        
        # Add to collection
        self._collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=documents,
            metadatas=metadatas
        )
        
        logger.debug(f"Added {len(segments)} segments to vector store")
    
    async def similarity_search(
        self,
        query_embedding: List[float],
        k: int = 10,
        filter_dict: Optional[dict] = None
    ) -> List[tuple[str, float]]:
        """Search for similar segments.
        
        Args:
            query_embedding: Query vector
            k: Number of results to return
            filter_dict: Optional metadata filter
            
        Returns:
            List of (segment_id, distance) tuples, sorted by similarity
        """
        if not self._collection:
            raise RuntimeError("Vector store not initialized")
        
        results = self._collection.query(
            query_embeddings=[query_embedding],
            n_results=k,
            where=filter_dict
        )
        
        # Extract IDs and distances
        segment_ids = results["ids"][0] if results["ids"] else []
        distances = results["distances"][0] if results["distances"] else []
        
        return list(zip(segment_ids, distances))
    
    async def delete_session_segments(self, session_id: UUID) -> int:
        """Delete all segments for a session.
        
        Args:
            session_id: Session ID to delete
            
        Returns:
            Number of segments deleted
        """
        if not self._collection:
            raise RuntimeError("Vector store not initialized")
        
        # ChromaDB doesn't have a count in delete, so we query first
        results = self._collection.get(
            where={"session_id": str(session_id)}
        )
        
        if results and results["ids"]:
            self._collection.delete(
                ids=results["ids"]
            )
            return len(results["ids"])
        
        return 0
    
    async def get_stats(self) -> dict:
        """Get vector store statistics.
        
        Returns:
            Dict with count and other stats
        """
        if not self._collection:
            return {"count": 0, "initialized": False}
        
        count = self._collection.count()
        return {
            "count": count,
            "initialized": True,
            "collection": self.collection_name,
            "persist_directory": str(self.persist_directory)
        }
    
    async def health_check(self) -> bool:
        """Check if vector store is healthy.
        
        Returns:
            True if operational
        """
        try:
            if self._collection:
                self._collection.count()
                return True
            return False
        except Exception:
            return False


# Factory function
async def get_vector_store(
    persist_directory: Optional[str] = None
) -> VectorStore:
    """Create and initialize a vector store.
    
    Args:
        persist_directory: Optional custom persistence directory
        
    Returns:
        Initialized VectorStore
    """
    store = VectorStore(persist_directory)
    await store.initialize()
    return store
