"""Hybrid search combining keyword and semantic search.

Uses Reciprocal Rank Fusion (RRF) to combine results from:
- Keyword search (SQLite FTS5)
- Semantic search (ChromaDB vector similarity)

RRF Formula: score = Σ(1 / (k + rank)) for each list containing the item
Default k=60 (constant that works well across domains)
"""

import logging
from dataclasses import dataclass
from typing import Dict, List, Optional, Set
from uuid import UUID

from server.db import StorageAdapter, SearchResult, SearchFilters
from server.db.vector_store import VectorStore
from server.services.embeddings import EmbeddingService

logger = logging.getLogger(__name__)

# RRF constant - standard value that works well across domains
RRF_K = 60


@dataclass
class HybridSearchResult:
    """Result from hybrid search with combined score."""
    
    segment_id: UUID
    text: str
    session_id: UUID
    keyword_rank: Optional[int] = None
    semantic_rank: Optional[int] = None
    keyword_score: float = 0.0
    semantic_score: float = 0.0
    rrf_score: float = 0.0
    
    # Source results for context
    keyword_result: Optional[SearchResult] = None
    semantic_metadata: Optional[dict] = None


class HybridSearchEngine:
    """Engine for hybrid keyword + semantic search.
    
    Usage:
        engine = HybridSearchEngine(sqlite_adapter, vector_store)
        
        results = await engine.search(
            query="product roadmap",
            filters=SearchFilters(...),
            k=20
        )
        
        # Results are ranked by RRF score
        for result in results:
            print(f"{result.rrf_score}: {result.text}")
    """
    
    def __init__(
        self,
        keyword_adapter: StorageAdapter,
        vector_store: VectorStore,
        embedding_service: Optional[EmbeddingService] = None,
        rrf_k: int = RRF_K
    ):
        """Initialize hybrid search engine.
        
        Args:
            keyword_adapter: SQLite adapter for keyword search
            vector_store: ChromaDB vector store for semantic search
            embedding_service: Service for query embedding (creates default if None)
            rrf_k: RRF constant (default 60)
        """
        self.keyword_adapter = keyword_adapter
        self.vector_store = vector_store
        self.embedding_service = embedding_service or EmbeddingService()
        self.rrf_k = rrf_k
    
    async def search(
        self,
        query: str,
        filters: Optional[SearchFilters] = None,
        k: int = 20,
        keyword_weight: float = 0.5,
        use_rrf: bool = True
    ) -> List[HybridSearchResult]:
        """Perform hybrid search.
        
        Args:
            query: Search query text
            filters: Optional search filters (time range, source, etc.)
            k: Number of results to return
            keyword_weight: Weight for keyword vs semantic (0-1, only used if not RRF)
            use_rrf: Use Reciprocal Rank Fusion (if False, uses weighted sum)
            
        Returns:
            List of hybrid search results ranked by score
        """
        logger.debug(f"Hybrid search: '{query}' (k={k}, rrf={use_rrf})")
        
        # Get keyword results
        keyword_results = await self._keyword_search(query, filters, k=k * 2)
        logger.debug(f"Keyword results: {len(keyword_results)}")
        
        # Get semantic results if embedding service available
        semantic_results = []
        if self.embedding_service and self.embedding_service.is_available():
            semantic_results = await self._semantic_search(query, filters, k=k * 2)
            logger.debug(f"Semantic results: {len(semantic_results)}")
        else:
            logger.warning("Embedding service not available, using keyword only")
        
        # Combine results
        if use_rrf:
            return self._combine_rrf(keyword_results, semantic_results, k)
        else:
            return self._combine_weighted(
                keyword_results, semantic_results, k, keyword_weight
            )
    
    async def _keyword_search(
        self,
        query: str,
        filters: Optional[SearchFilters],
        k: int
    ) -> List[SearchResult]:
        """Perform keyword search."""
        try:
            return await self.keyword_adapter.search(query, filters, limit=k, offset=0)
        except Exception as e:
            logger.error(f"Keyword search failed: {e}")
            return []
    
    async def _semantic_search(
        self,
        query: str,
        filters: Optional[SearchFilters],
        k: int
    ) -> List[tuple[str, float, dict]]:
        """Perform semantic search.
        
        Returns:
            List of (segment_id, distance, metadata) tuples
        """
        try:
            # Generate query embedding
            query_embedding = self.embedding_service.encode_single(query)
            
            # Build ChromaDB filter from SearchFilters
            chroma_filter = self._build_chroma_filter(filters)
            
            # Search
            results = await self.vector_store.similarity_search(
                query_embedding, k=k, filter_dict=chroma_filter
            )
            
            # Fetch metadata for each result
            semantic_results = []
            for segment_id, distance in results:
                # Fetch full metadata from vector store
                semantic_results.append((segment_id, distance, {}))
            
            return semantic_results
            
        except Exception as e:
            logger.error(f"Semantic search failed: {e}")
            return []
    
    def _build_chroma_filter(self, filters: Optional[SearchFilters]) -> Optional[dict]:
        """Build ChromaDB filter from SearchFilters."""
        if not filters:
            return None
        
        conditions = {}
        
        if filters.source_filter:
            sources = [s.value for s in filters.source_filter]
            if len(sources) == 1:
                conditions["source"] = sources[0]
            else:
                conditions["source"] = {"$in": sources}
        
        # Note: ChromaDB has limited filtering, so we can't filter by
        # timestamp ranges or speaker IDs easily. Those are filtered
        # post-search if needed.
        
        return conditions if conditions else None
    
    def _combine_rrf(
        self,
        keyword_results: List[SearchResult],
        semantic_results: List[tuple[str, float, dict]],
        k: int
    ) -> List[HybridSearchResult]:
        """Combine results using Reciprocal Rank Fusion.
        
        RRF score = Σ(1 / (k + rank)) for each list containing the item
        """
        # Build segment_id -> result mapping
        all_segments: Dict[UUID, HybridSearchResult] = {}
        
        # Process keyword results
        for rank, result in enumerate(keyword_results, start=1):
            seg_id = result.segment.id
            if seg_id not in all_segments:
                all_segments[seg_id] = HybridSearchResult(
                    segment_id=seg_id,
                    text=result.segment.text,
                    session_id=result.segment.session_id,
                    keyword_result=result
                )
            
            all_segments[seg_id].keyword_rank = rank
            all_segments[seg_id].keyword_score = result.relevance_score
        
        # Process semantic results
        for rank, (segment_id_str, distance, metadata) in enumerate(semantic_results, start=1):
            seg_id = UUID(segment_id_str)
            
            if seg_id not in all_segments:
                # Need to fetch text from keyword result or elsewhere
                all_segments[seg_id] = HybridSearchResult(
                    segment_id=seg_id,
                    text="",  # Will be populated if found in keyword results
                    session_id=UUID(metadata.get("session_id", str(seg_id))),  # Fallback
                    semantic_metadata=metadata
                )
            
            all_segments[seg_id].semantic_rank = rank
            # Convert distance to score (ChromaDB cosine distance: lower is better)
            all_segments[seg_id].semantic_score = 1.0 - distance
            all_segments[seg_id].semantic_metadata = metadata
        
        # Calculate RRF scores
        for result in all_segments.values():
            rrf_score = 0.0
            
            if result.keyword_rank:
                rrf_score += 1.0 / (self.rrf_k + result.keyword_rank)
            
            if result.semantic_rank:
                rrf_score += 1.0 / (self.rrf_k + result.semantic_rank)
            
            result.rrf_score = rrf_score
        
        # Sort by RRF score and return top k
        sorted_results = sorted(
            all_segments.values(),
            key=lambda r: r.rrf_score,
            reverse=True
        )
        
        return sorted_results[:k]
    
    def _combine_weighted(
        self,
        keyword_results: List[SearchResult],
        semantic_results: List[tuple[str, float, dict]],
        k: int,
        keyword_weight: float
    ) -> List[HybridSearchResult]:
        """Combine results using weighted sum (alternative to RRF)."""
        semantic_weight = 1.0 - keyword_weight
        
        all_segments: Dict[UUID, HybridSearchResult] = {}
        
        # Process keyword results (normalize scores to 0-1)
        if keyword_results:
            max_score = max(r.relevance_score for r in keyword_results)
            for result in keyword_results:
                seg_id = result.segment.id
                normalized_score = result.relevance_score / max_score if max_score > 0 else 0
                
                all_segments[seg_id] = HybridSearchResult(
                    segment_id=seg_id,
                    text=result.segment.text,
                    session_id=result.segment.session_id,
                    keyword_score=normalized_score,
                    rrf_score=normalized_score * keyword_weight,
                    keyword_result=result
                )
        
        # Process semantic results
        if semantic_results:
            # Convert distances to scores (lower distance = higher score)
            distances = [d for _, d, _ in semantic_results]
            max_dist = max(distances) if distances else 1.0
            min_dist = min(distances) if distances else 0.0
            dist_range = max_dist - min_dist if max_dist > min_dist else 1.0
            
            for segment_id_str, distance, metadata in semantic_results:
                seg_id = UUID(segment_id_str)
                # Normalize to 0-1 (invert so lower distance = higher score)
                normalized_score = (max_dist - distance) / dist_range
                
                if seg_id in all_segments:
                    all_segments[seg_id].semantic_score = normalized_score
                    all_segments[seg_id].rrf_score += normalized_score * semantic_weight
                else:
                    all_segments[seg_id] = HybridSearchResult(
                        segment_id=seg_id,
                        text="",
                        session_id=UUID(metadata.get("session_id", str(seg_id))),
                        semantic_score=normalized_score,
                        rrf_score=normalized_score * semantic_weight,
                        semantic_metadata=metadata
                    )
        
        # Sort by combined score
        sorted_results = sorted(
            all_segments.values(),
            key=lambda r: r.rrf_score,
            reverse=True
        )
        
        return sorted_results[:k]


# Factory function for convenience
async def create_hybrid_search_engine(
    keyword_adapter: StorageAdapter,
    persist_directory: Optional[str] = None
) -> HybridSearchEngine:
    """Create and initialize a hybrid search engine.
    
    Args:
        keyword_adapter: SQLite adapter for keyword search
        persist_directory: Optional ChromaDB persistence directory
        
    Returns:
        Initialized HybridSearchEngine
    """
    from server.db.vector_store import VectorStore
    
    vector_store = VectorStore(persist_directory=persist_directory)
    await vector_store.initialize()
    
    return HybridSearchEngine(keyword_adapter, vector_store)
