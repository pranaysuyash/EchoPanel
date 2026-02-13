import json
import math
import os
import re
import threading
import uuid
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

try:
    from server.services.embeddings import get_embedding_service
    EMBEDDINGS_AVAILABLE = True
except ImportError:
    EMBEDDINGS_AVAILABLE = False
    get_embedding_service = None

STORE_PATH_ENV = "ECHOPANEL_DOC_STORE_PATH"
_TOKEN_PATTERN = re.compile(r"[a-z0-9']+")


@dataclass(frozen=True)
class ChunkResult:
    document_id: str
    title: str
    source: str
    chunk_index: int
    snippet: str
    score: float


class LocalRAGStore:
    """
    Lightweight local document store with lexical chunk retrieval.
    """

    def __init__(self, store_path: Optional[Path] = None, chunk_words: int = 120, overlap_words: int = 30):
        self.store_path = store_path or _default_store_path()
        self.chunk_words = max(40, chunk_words)
        self.overlap_words = max(0, min(overlap_words, self.chunk_words - 1))
        self._lock = threading.RLock()
        self._state: Dict[str, List[dict]] = {"documents": []}
        self._embeddings_service = None
        self._load()

    def list_documents(self) -> List[dict]:
        with self._lock:
            docs = [self._public_document(doc) for doc in self._state.get("documents", [])]
            docs.sort(key=lambda item: item["indexed_at"], reverse=True)
            return docs

    def index_document(
        self,
        title: str,
        text: str,
        source: str = "local",
        document_id: Optional[str] = None,
        generate_embeddings: bool = True
    ) -> dict:
        clean_text = (text or "").strip()
        if not clean_text:
            raise ValueError("Document text is empty")

        safe_title = (title or "Untitled").strip() or "Untitled"
        safe_source = (source or "local").strip() or "local"
        doc_id = document_id or str(uuid.uuid4())
        chunks = self._chunk_document(clean_text)
        now = datetime.now(timezone.utc).isoformat()
        preview = self._normalize_whitespace(clean_text)[:180]

        document = {
            "document_id": doc_id,
            "title": safe_title,
            "source": safe_source,
            "indexed_at": now,
            "preview": preview,
            "chunk_count": len(chunks),
            "chunks": chunks,
        }

        with self._lock:
            docs = [doc for doc in self._state.get("documents", []) if doc.get("document_id") != doc_id]
            docs.append(document)
            self._state["documents"] = docs
            self._persist()

            if generate_embeddings and self.is_embedding_available():
                try:
                    self._generate_embeddings_for_document(doc_id, chunks)
                except Exception:
                    pass

            return self._public_document(document)

    def _generate_embeddings_for_document(self, document_id: str, chunks: List[Dict]) -> None:
        if not self.embeddings_service:
            return
        try:
            self.embeddings_service.generate_document_embeddings(document_id, chunks)
        except Exception:
            pass

    def delete_document(self, document_id: str) -> bool:
        with self._lock:
            docs = self._state.get("documents", [])
            kept = [doc for doc in docs if doc.get("document_id") != document_id]
            if len(kept) == len(docs):
                return False

            self._state["documents"] = kept
            self._persist()

            if self.embeddings_service:
                try:
                    self.embeddings_service.delete_document_embeddings(document_id)
                except Exception:
                    pass

            return True

    def query(self, query: str, top_k: int = 5) -> List[dict]:
        query_tokens = self._tokenize(query)
        if not query_tokens:
            return []

        with self._lock:
            docs = self._state.get("documents", [])
            scored = self._score_chunks(docs, query_tokens)
            limit = max(1, min(int(top_k), 20))
            return [result.__dict__ for result in scored[:limit]]

    def query_semantic(self, query: str, top_k: int = 5) -> List[dict]:
        if not self.is_embedding_available():
            return self.query(query, top_k)

        query_embedding = self.embeddings_service.embed_text(query)
        if not query_embedding:
            return self.query(query, top_k)

        with self._lock:
            docs = self._state.get("documents", [])
            results: List[ChunkResult] = []

            for doc in docs:
                doc_id = doc.get("document_id", "")
                similar = self.embeddings_service.find_similar(query_embedding, doc_id, top_k=1)

                if similar:
                    chunk_idx, similarity = similar[0]
                    chunk = self._find_chunk(doc, chunk_idx)
                    if chunk:
                        snippet = self._snippet(chunk.get("text", ""), self._tokenize(query))
                        results.append(
                            ChunkResult(
                                document_id=doc_id,
                                title=doc.get("title", "Untitled"),
                                source=doc.get("source", "local"),
                                chunk_index=chunk_idx,
                                snippet=snippet,
                                score=round(similarity, 4),
                            )
                        )

            results.sort(key=lambda item: item.score, reverse=True)
            limit = max(1, min(int(top_k), 20))
            return [result.__dict__ for result in results[:limit]]

    def query_hybrid(self, query: str, top_k: int = 5, semantic_weight: float = 0.7) -> List[dict]:
        semantic_results = self.query_semantic(query, top_k=top_k * 2)
        lexical_results = self.query(query, top_k=top_k * 2)

        if not semantic_results:
            return lexical_results[:top_k]

        if not lexical_results:
            return semantic_results[:top_k]

        semantic_dict = {r["document_id"]: r for r in semantic_results}
        lexical_dict = {r["document_id"]: r for r in lexical_results}

        all_doc_ids = set(semantic_dict.keys()) | set(lexical_dict.keys())

        hybrid_results = []
        for doc_id in all_doc_ids:
            sem = semantic_dict.get(doc_id, {"score": 0})
            lex = lexical_dict.get(doc_id, {"score": 0})

            combined_score = (semantic_weight * sem.get("score", 0)) + ((1 - semantic_weight) * lex.get("score", 0))

            hybrid_results.append({
                "document_id": doc_id,
                "title": sem.get("title", lex.get("title", "Untitled")),
                "source": sem.get("source", lex.get("source", "local")),
                "chunk_index": sem.get("chunk_index", lex.get("chunk_index", 0)),
                "snippet": sem.get("snippet", lex.get("snippet", "")),
                "score": round(combined_score, 4),
                "semantic_score": sem.get("score", 0),
                "lexical_score": lex.get("score", 0),
            })

        hybrid_results.sort(key=lambda x: x["score"], reverse=True)
        return hybrid_results[:top_k]

    def _find_chunk(self, document: dict, chunk_index: int) -> Optional[Dict]:
        for chunk in document.get("chunks", []):
            if chunk.get("chunk_index") == chunk_index:
                return chunk
        return None

    def _load(self) -> None:
        with self._lock:
            if not self.store_path.exists():
                self.store_path.parent.mkdir(parents=True, exist_ok=True)
                return

            try:
                raw = json.loads(self.store_path.read_text(encoding="utf-8"))
                docs = raw.get("documents", [])
                if isinstance(docs, list):
                    self._state = {"documents": docs}
            except Exception:
                # Corrupt data should not crash app startup; start fresh.
                self._state = {"documents": []}

    @property
    def embeddings_service(self):
        if self._embeddings_service is None and EMBEDDINGS_AVAILABLE and get_embedding_service:
            try:
                self._embeddings_service = get_embedding_service()
            except Exception:
                self._embeddings_service = None
        return self._embeddings_service

    def is_embedding_available(self) -> bool:
        return self.embeddings_service is not None and self.embeddings_service.is_available()

    def warmup_embeddings(self) -> bool:
        if self.embeddings_service:
            try:
                self.embeddings_service.warmup()
                return True
            except Exception:
                return False
        return False

    def _persist(self) -> None:
        self.store_path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = self.store_path.with_suffix(".tmp")
        payload = json.dumps(self._state, ensure_ascii=True, indent=2)
        temp_path.write_text(payload, encoding="utf-8")
        temp_path.replace(self.store_path)

    def _chunk_document(self, text: str) -> List[dict]:
        words = text.split()
        if not words:
            return []

        step = max(1, self.chunk_words - self.overlap_words)
        chunks: List[dict] = []
        chunk_index = 0
        for start in range(0, len(words), step):
            end = min(start + self.chunk_words, len(words))
            chunk_words = words[start:end]
            if not chunk_words:
                continue
            chunk_text = " ".join(chunk_words)
            chunks.append(
                {
                    "chunk_index": chunk_index,
                    "text": chunk_text,
                    "tokens": self._tokenize(chunk_text),
                }
            )
            chunk_index += 1
            if end >= len(words):
                break
        return chunks

    def _score_chunks(self, documents: List[dict], query_tokens: List[str]) -> List[ChunkResult]:
        all_chunks: List[dict] = []
        for doc in documents:
            for chunk in doc.get("chunks", []):
                all_chunks.append(
                    {
                        "document_id": doc.get("document_id", ""),
                        "title": doc.get("title", "Untitled"),
                        "source": doc.get("source", "local"),
                        "chunk_index": int(chunk.get("chunk_index", 0)),
                        "text": chunk.get("text", ""),
                        "tokens": chunk.get("tokens", []),
                    }
                )

        if not all_chunks:
            return []

        n_chunks = len(all_chunks)
        chunk_lengths = [len(chunk.get("tokens", [])) for chunk in all_chunks]
        avg_len = max(1.0, sum(chunk_lengths) / float(n_chunks))

        doc_freq: Dict[str, int] = {}
        for token in set(query_tokens):
            doc_freq[token] = sum(1 for chunk in all_chunks if token in set(chunk.get("tokens", [])))

        k1 = 1.4
        b = 0.75
        query_phrase = " ".join(query_tokens)
        results: List[ChunkResult] = []

        for chunk in all_chunks:
            tokens = chunk.get("tokens", [])
            if not tokens:
                continue
            tf = Counter(tokens)
            chunk_len = max(1, len(tokens))
            score = 0.0
            for token in query_tokens:
                freq = tf.get(token, 0)
                if freq == 0:
                    continue
                df = max(1, doc_freq.get(token, 1))
                idf = math.log(1.0 + ((n_chunks - df + 0.5) / (df + 0.5)))
                denom = freq + k1 * (1.0 - b + b * (chunk_len / avg_len))
                score += idf * ((freq * (k1 + 1.0)) / denom)

            text_lower = chunk.get("text", "").lower()
            if query_phrase and query_phrase in text_lower:
                score += 0.35

            if score <= 0:
                continue

            snippet = self._snippet(chunk.get("text", ""), query_tokens)
            results.append(
                ChunkResult(
                    document_id=chunk.get("document_id", ""),
                    title=chunk.get("title", "Untitled"),
                    source=chunk.get("source", "local"),
                    chunk_index=int(chunk.get("chunk_index", 0)),
                    snippet=snippet,
                    score=round(score, 4),
                )
            )

        results.sort(key=lambda item: item.score, reverse=True)
        return results

    def _public_document(self, document: dict) -> dict:
        return {
            "document_id": document.get("document_id", ""),
            "title": document.get("title", "Untitled"),
            "source": document.get("source", "local"),
            "indexed_at": document.get("indexed_at", ""),
            "preview": document.get("preview", ""),
            "chunk_count": int(document.get("chunk_count", 0)),
        }

    def _snippet(self, text: str, query_tokens: List[str], max_len: int = 220) -> str:
        normalized = self._normalize_whitespace(text)
        if len(normalized) <= max_len:
            return normalized

        lower = normalized.lower()
        hit = -1
        for token in query_tokens:
            idx = lower.find(token)
            if idx >= 0:
                hit = idx
                break
        if hit < 0:
            return normalized[:max_len].rstrip() + "..."

        start = max(0, hit - (max_len // 3))
        end = min(len(normalized), start + max_len)
        snippet = normalized[start:end]
        if start > 0:
            snippet = "..." + snippet
        if end < len(normalized):
            snippet += "..."
        return snippet

    @staticmethod
    def _normalize_whitespace(text: str) -> str:
        return " ".join(text.split())

    @staticmethod
    def _tokenize(text: str) -> List[str]:
        return _TOKEN_PATTERN.findall((text or "").lower())


_store_lock = threading.Lock()
_store: Optional[LocalRAGStore] = None


def _default_store_path() -> Path:
    override = os.getenv(STORE_PATH_ENV, "").strip()
    if override:
        return Path(override).expanduser()
    return Path.home() / ".echopanel" / "rag_store.json"


def get_rag_store() -> LocalRAGStore:
    global _store
    with _store_lock:
        if _store is None:
            _store = LocalRAGStore()
        return _store


def reset_rag_store_for_tests(store_path: Optional[Path] = None) -> LocalRAGStore:
    global _store
    with _store_lock:
        _store = LocalRAGStore(store_path=store_path)
        return _store
