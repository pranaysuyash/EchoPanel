"""Brain Dump Query API - REST endpoints for searching personal audio memory."""

import hmac
import logging
import os
from datetime import datetime, timedelta
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from server.db import (
    get_storage_adapter,
    StorageAdapter,
    StorageConfig,
    SearchFilters,
    SearchResult,
    AudioSource
)
from server.services.brain_dump_indexer import get_indexer
from server.services.hybrid_search import HybridSearchEngine, create_hybrid_search_engine
from server.services.embeddings import get_embedding_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/brain-dump", tags=["brain-dump"])

AUTH_TOKEN_ENV = "ECHOPANEL_WS_AUTH_TOKEN"


def _extract_token(request: Request) -> str:
    query_token = request.query_params.get("token", "").strip()
    if query_token:
        return query_token

    header_token = request.headers.get("x-echopanel-token", "").strip()
    if header_token:
        return header_token

    auth_header = request.headers.get("authorization", "").strip()
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()
    return ""


def _require_http_auth(request: Request) -> None:
    required_token = os.getenv(AUTH_TOKEN_ENV, "").strip()
    if not required_token:
        return
    provided_token = _extract_token(request)
    if not provided_token or not hmac.compare_digest(provided_token, required_token):
        raise HTTPException(status_code=401, detail="Unauthorized")


# Pydantic models for API

class SearchRequest(BaseModel):
    """Request body for search endpoint."""
    query: str = Field(..., description="Search query string")
    query_type: str = Field(default="keyword", description="Type: keyword, semantic, hybrid")
    time_range_start: Optional[datetime] = Field(None, description="Start of time range")
    time_range_end: Optional[datetime] = Field(None, description="End of time range")
    sources: Optional[List[str]] = Field(None, description="Filter by source: system, microphone, voice_note")
    speakers: Optional[List[str]] = Field(None, description="Filter by speaker IDs")
    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)


class SegmentResponse(BaseModel):
    """Transcript segment in response."""
    id: str
    session_id: str
    timestamp: datetime
    relative_time: float
    source: str
    speaker_id: Optional[str]
    text: str
    confidence: float


class SessionResponse(BaseModel):
    """Session in response."""
    id: str
    started_at: datetime
    ended_at: Optional[datetime]
    title: Optional[str]
    source_app: Optional[str]
    tags: List[str]
    is_pinned: bool


class SearchResultResponse(BaseModel):
    """Search result item."""
    segment: SegmentResponse
    session: Optional[SessionResponse]
    relevance_score: float
    context_before: List[SegmentResponse]
    context_after: List[SegmentResponse]


class SearchResponse(BaseModel):
    """Search response."""
    results: List[SearchResultResponse]
    total: int
    query: str
    has_more: bool


class AskRequest(BaseModel):
    """Request body for ask endpoint."""
    question: str = Field(..., description="Natural language question")
    time_range_start: Optional[datetime] = None
    time_range_end: Optional[datetime] = None
    max_context_segments: int = Field(default=20, ge=5, le=50)


class AskResponse(BaseModel):
    """Response from ask endpoint."""
    answer: str
    sources: List[SearchResultResponse]
    confidence: float


class SessionListResponse(BaseModel):
    """List of sessions."""
    sessions: List[SessionResponse]
    total: int
    has_more: bool


class StatsResponse(BaseModel):
    """Storage statistics."""
    backend: str
    db_path: Optional[str]
    db_size_bytes: int
    session_count: int
    segment_count: int
    oldest_session: Optional[datetime]
    newest_session: Optional[datetime]


# Dependency injection

async def get_storage() -> StorageAdapter:
    """Get storage adapter (SQLite by default)."""
    config = StorageConfig(backend="sqlite")
    adapter = get_storage_adapter(config)
    await adapter.initialize()
    try:
        yield adapter
    finally:
        await adapter.close()


# API Endpoints

@router.post("/search", response_model=SearchResponse)
async def search(
    http_request: Request,
    request: SearchRequest,
    adapter: StorageAdapter = Depends(get_storage)
) -> SearchResponse:
    """Search personal audio memory with keyword search.
    
    Examples:
    - "roadmap" - Find mentions of roadmap
    - "Sarah API" - Find where Sarah mentioned API
    - Use time_range to narrow down
    """
    _require_http_auth(http_request)
    try:
        # Build filters
        filters = SearchFilters(
            time_range_start=request.time_range_start,
            time_range_end=request.time_range_end,
            source_filter=[AudioSource(s) for s in request.sources] if request.sources else None,
            speaker_filter=request.speakers,
            min_confidence=0.0
        )
        
        # Perform search
        results = await adapter.search(
            query=request.query,
            filters=filters,
            limit=request.limit,
            offset=request.offset
        )
        
        # Convert to response model
        response_results = []
        for r in results:
            response_results.append(SearchResultResponse(
                segment=SegmentResponse(
                    id=str(r.segment.id),
                    session_id=str(r.segment.session_id),
                    timestamp=r.segment.timestamp,
                    relative_time=r.segment.relative_time,
                    source=r.segment.source.value,
                    speaker_id=r.segment.speaker_id,
                    text=r.segment.text,
                    confidence=r.segment.confidence
                ),
                session=SessionResponse(
                    id=str(r.session.id),
                    started_at=r.session.started_at,
                    ended_at=r.session.ended_at,
                    title=r.session.title,
                    source_app=r.session.source_app,
                    tags=r.session.tags,
                    is_pinned=r.session.is_pinned
                ) if r.session else None,
                relevance_score=r.relevance_score,
                context_before=[
                    SegmentResponse(
                        id=str(s.id),
                        session_id=str(s.session_id),
                        timestamp=s.timestamp,
                        relative_time=s.relative_time,
                        source=s.source.value,
                        speaker_id=s.speaker_id,
                        text=s.text,
                        confidence=s.confidence
                    )
                    for s in r.context_before
                ],
                context_after=[
                    SegmentResponse(
                        id=str(s.id),
                        session_id=str(s.session_id),
                        timestamp=s.timestamp,
                        relative_time=s.relative_time,
                        source=s.source.value,
                        speaker_id=s.speaker_id,
                        text=s.text,
                        confidence=s.confidence
                    )
                    for s in r.context_after
                ]
            ))
        
        return SearchResponse(
            results=response_results,
            total=len(response_results),  # TODO: Get actual total
            query=request.query,
            has_more=len(response_results) == request.limit
        )
        
    except Exception as e:
        logger.error(f"Search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/search", response_model=SearchResponse)
async def search_get(
    http_request: Request,
    q: str = Query(..., description="Search query"),
    source: Optional[str] = Query(None, description="Filter by source"),
    days: int = Query(7, ge=1, le=365, description="Search last N days"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    adapter: StorageAdapter = Depends(get_storage)
) -> SearchResponse:
    """GET version of search (convenient for browser/testing).
    
    Example: /brain-dump/search?q=roadmap&days=7
    """
    _require_http_auth(http_request)
    # Build time range from days
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=days)
    
    filters = SearchFilters(
        time_range_start=start_time,
        time_range_end=end_time,
        source_filter=[AudioSource(source)] if source else None
    )
    
    results = await adapter.search(q, filters, limit, offset)
    
    return SearchResponse(
        results=[
            SearchResultResponse(
                segment=SegmentResponse(
                    id=str(r.segment.id),
                    session_id=str(r.segment.session_id),
                    timestamp=r.segment.timestamp,
                    relative_time=r.segment.relative_time,
                    source=r.segment.source.value,
                    speaker_id=r.segment.speaker_id,
                    text=r.segment.text,
                    confidence=r.segment.confidence
                ),
                session=SessionResponse(
                    id=str(r.session.id),
                    started_at=r.session.started_at,
                    ended_at=r.session.ended_at,
                    title=r.session.title,
                    source_app=r.session.source_app,
                    tags=r.session.tags,
                    is_pinned=r.session.is_pinned
                ) if r.session else None,
                relevance_score=r.relevance_score,
                context_before=[],
                context_after=[]
            )
            for r in results
        ],
        total=len(results),
        query=q,
        has_more=len(results) == limit
    )


class HybridSearchResponse(BaseModel):
    """Response for hybrid search."""
    results: List[dict]  # Simplified for now
    query: str
    query_type: str
    total: int


@router.post("/search/hybrid", response_model=HybridSearchResponse)
async def search_hybrid(
    http_request: Request,
    request: SearchRequest,
    adapter: StorageAdapter = Depends(get_storage)
) -> HybridSearchResponse:
    """Hybrid search combining keyword and semantic search.
    
    Uses Reciprocal Rank Fusion (RRF) to combine results from
    keyword (SQLite FTS5) and semantic (ChromaDB) search.
    
    Example:
    ```
    POST /brain-dump/search/hybrid
    {
        "query": "product planning",
        "query_type": "hybrid",
        "limit": 20
    }
    ```
    """
    _require_http_auth(http_request)
    # Only support hybrid/semantic if embedding service available
    embedding_service = get_embedding_service()
    
    if request.query_type == "keyword" or not embedding_service.is_available():
        # Fall back to keyword search
        filters = SearchFilters(
            time_range_start=request.time_range_start,
            time_range_end=request.time_range_end,
            source_filter=[AudioSource(s) for s in request.sources] if request.sources else None,
        )
        results = await adapter.search(request.query, filters, request.limit, request.offset)
        
        return HybridSearchResponse(
            results=[{"text": r.segment.text, "score": r.relevance_score} for r in results],
            query=request.query,
            query_type="keyword",
            total=len(results)
        )
    
    # Create hybrid search engine
    try:
        engine = await create_hybrid_search_engine(adapter)
        
        filters = SearchFilters(
            time_range_start=request.time_range_start,
            time_range_end=request.time_range_end,
            source_filter=[AudioSource(s) for s in request.sources] if request.sources else None,
        )
        
        results = await engine.search(
            query=request.query,
            filters=filters,
            k=request.limit,
            use_rrf=True
        )
        
        return HybridSearchResponse(
            results=[{
                "text": r.text,
                "rrf_score": r.rrf_score,
                "keyword_score": r.keyword_score,
                "semantic_score": r.semantic_score,
                "segment_id": str(r.segment_id),
                "session_id": str(r.session_id)
            } for r in results],
            query=request.query,
            query_type="hybrid",
            total=len(results)
        )
        
    except Exception as e:
        logger.error(f"Hybrid search error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/ask", response_model=AskResponse)
async def ask(
    http_request: Request,
    request: AskRequest,
    adapter: StorageAdapter = Depends(get_storage)
) -> AskResponse:
    """Ask a natural language question about your audio memory.
    
    This performs RAG (Retrieval Augmented Generation) to answer
    questions based on your transcripts.
    
    Example questions:
    - "What did Sarah say about the API?"
    - "Summarize my standup meetings this week"
    - "What were my action items from the product meeting?"
    """
    _require_http_auth(http_request)
    # TODO: Implement RAG with local LLM
    # For now, return a placeholder
    
    # Retrieve relevant context
    filters = SearchFilters(
        time_range_start=request.time_range_start,
        time_range_end=request.time_range_end
    )
    
    # Simple keyword extraction (improve later)
    keywords = request.question.lower().split()
    query = " OR ".join([k for k in keywords if len(k) > 3])
    
    results = await adapter.search(query, filters, request.max_context_segments, 0)
    
    # Placeholder: Just concatenate relevant segments
    context_text = "\n".join([r.segment.text for r in results[:10]])
    
    # TODO: Use MLX LM for actual generation
    answer = f"Based on your transcripts, here's what I found:\n\n{context_text[:500]}..."
    
    return AskResponse(
        answer=answer,
        sources=[
            SearchResultResponse(
                segment=SegmentResponse(
                    id=str(r.segment.id),
                    session_id=str(r.segment.session_id),
                    timestamp=r.segment.timestamp,
                    relative_time=r.segment.relative_time,
                    source=r.segment.source.value,
                    speaker_id=r.segment.speaker_id,
                    text=r.segment.text,
                    confidence=r.segment.confidence
                ),
                session=SessionResponse(
                    id=str(r.session.id),
                    started_at=r.session.started_at,
                    ended_at=r.session.ended_at,
                    title=r.session.title,
                    source_app=r.session.source_app,
                    tags=r.session.tags,
                    is_pinned=r.session.is_pinned
                ) if r.session else None,
                relevance_score=r.relevance_score,
                context_before=[],
                context_after=[]
            )
            for r in results[:5]
        ],
        confidence=0.8 if results else 0.0
    )


@router.get("/sessions", response_model=SessionListResponse)
async def list_sessions(
    http_request: Request,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    pinned_only: bool = Query(False),
    adapter: StorageAdapter = Depends(get_storage)
) -> SessionListResponse:
    """List recording sessions."""
    _require_http_auth(http_request)
    sessions = await adapter.list_sessions(limit, offset, pinned_only)
    
    return SessionListResponse(
        sessions=[
            SessionResponse(
                id=str(s.id),
                started_at=s.started_at,
                ended_at=s.ended_at,
                title=s.title,
                source_app=s.source_app,
                tags=s.tags,
                is_pinned=s.is_pinned
            )
            for s in sessions
        ],
        total=len(sessions),  # TODO: Get actual total
        has_more=len(sessions) == limit
    )


@router.get("/sessions/{session_id}")
async def get_session(
    http_request: Request,
    session_id: UUID,
    adapter: StorageAdapter = Depends(get_storage)
) -> SessionResponse:
    """Get a specific session by ID."""
    _require_http_auth(http_request)
    session = await adapter.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    return SessionResponse(
        id=str(session.id),
        started_at=session.started_at,
        ended_at=session.ended_at,
        title=session.title,
        source_app=session.source_app,
        tags=session.tags,
        is_pinned=session.is_pinned
    )


@router.get("/sessions/{session_id}/segments")
async def get_session_segments(
    http_request: Request,
    session_id: UUID,
    limit: int = Query(1000, ge=1, le=5000),
    offset: int = Query(0, ge=0),
    adapter: StorageAdapter = Depends(get_storage)
) -> List[SegmentResponse]:
    """Get all transcript segments for a session."""
    _require_http_auth(http_request)
    segments = await adapter.get_segments_by_session(session_id, limit, offset)
    
    return [
        SegmentResponse(
            id=str(s.id),
            session_id=str(s.session_id),
            timestamp=s.timestamp,
            relative_time=s.relative_time,
            source=s.source.value,
            speaker_id=s.speaker_id,
            text=s.text,
            confidence=s.confidence
        )
        for s in segments
    ]


@router.post("/sessions/{session_id}/pin")
async def pin_session(
    http_request: Request,
    session_id: UUID,
    adapter: StorageAdapter = Depends(get_storage)
) -> dict:
    """Pin a session to prevent auto-deletion."""
    _require_http_auth(http_request)
    session = await adapter.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    session.is_pinned = True
    await adapter.update_session(session)
    return {"status": "pinned", "session_id": str(session_id)}


@router.delete("/sessions/{session_id}")
async def delete_session(
    http_request: Request,
    session_id: UUID,
    adapter: StorageAdapter = Depends(get_storage)
) -> dict:
    """Delete a session and all its segments."""
    _require_http_auth(http_request)
    deleted = await adapter.delete_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"status": "deleted", "session_id": str(session_id)}


@router.get("/stats", response_model=StatsResponse)
async def get_stats(
    http_request: Request,
    adapter: StorageAdapter = Depends(get_storage)
) -> StatsResponse:
    """Get storage statistics."""
    _require_http_auth(http_request)
    stats = await adapter.get_stats()
    
    return StatsResponse(
        backend=stats["backend"],
        db_path=stats.get("db_path"),
        db_size_bytes=stats["db_size_bytes"],
        session_count=stats["session_count"],
        segment_count=stats["segment_count"],
        oldest_session=datetime.fromisoformat(stats["oldest_session"]) if stats.get("oldest_session") else None,
        newest_session=datetime.fromisoformat(stats["newest_session"]) if stats.get("newest_session") else None
    )


@router.post("/maintenance/compact")
async def compact_database(
    http_request: Request,
    adapter: StorageAdapter = Depends(get_storage)
) -> dict:
    """Compact/optimize the database."""
    _require_http_auth(http_request)
    await adapter.compact()
    return {"status": "compacted"}


@router.post("/maintenance/cleanup")
async def cleanup_old_sessions(
    http_request: Request,
    days: int = Query(90, ge=7, le=365),
    adapter: StorageAdapter = Depends(get_storage)
) -> dict:
    """Delete sessions older than N days (except pinned)."""
    _require_http_auth(http_request)
    deleted = await adapter.delete_old_sessions(days)
    return {"status": "cleaned", "deleted_sessions": deleted}
