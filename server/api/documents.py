import hmac
import os
from typing import List

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from server.services.rag_store import get_rag_store

router = APIRouter()
AUTH_TOKEN_ENV = "ECHOPANEL_WS_AUTH_TOKEN"


class DocumentIndexRequest(BaseModel):
    title: str = Field(default="Untitled")
    text: str = Field(min_length=1)
    source: str = Field(default="local")
    document_id: str | None = None


class DocumentQueryRequest(BaseModel):
    query: str = Field(min_length=1)
    top_k: int = Field(default=5, ge=1, le=20)


class DocumentSummary(BaseModel):
    document_id: str
    title: str
    source: str
    indexed_at: str
    preview: str
    chunk_count: int


class DocumentQueryResult(BaseModel):
    document_id: str
    title: str
    source: str
    chunk_index: int
    snippet: str
    score: float


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


@router.get("/documents")
async def list_documents(request: Request) -> dict:
    _require_http_auth(request)
    store = get_rag_store()
    documents = [DocumentSummary(**doc).model_dump() for doc in store.list_documents()]
    return {"documents": documents, "count": len(documents)}


@router.post("/documents/index")
async def index_document(request: Request, body: DocumentIndexRequest) -> dict:
    _require_http_auth(request)
    store = get_rag_store()
    try:
        indexed = store.index_document(
            title=body.title,
            text=body.text,
            source=body.source,
            document_id=body.document_id,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"document": DocumentSummary(**indexed).model_dump()}


@router.post("/documents/query")
async def query_documents(request: Request, body: DocumentQueryRequest) -> dict:
    _require_http_auth(request)
    store = get_rag_store()
    results = [DocumentQueryResult(**row).model_dump() for row in store.query(body.query, top_k=body.top_k)]
    return {"query": body.query, "results": results, "count": len(results)}


@router.delete("/documents/{document_id}")
async def delete_document(request: Request, document_id: str) -> dict:
    _require_http_auth(request)
    store = get_rag_store()
    deleted = store.delete_document(document_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Document not found")
    return {"deleted": True}
