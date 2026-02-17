# Brain Dump Implementation Plan

**Date**: 2026-02-15  
**Status**: IN_PROGRESS  
**Phase**: 1 (Foundation)

---

## Phase 1: Foundation (v0.4) - Implementation Tasks

### Task 1: Storage Abstraction Layer ✅ IN PROGRESS
**Files to create:**
- `server/db/__init__.py`
- `server/db/storage_adapter.py` (abstract base)
- `server/db/models.py` (dataclasses)
- `server/db/config.py` (storage configuration)

### Task 2: SQLite Adapter
**Files to create:**
- `server/db/adapters/__init__.py`
- `server/db/adapters/sqlite_adapter.py`

**Features:**
- Auto-create database on first run
- FTS5 full-text search
- Migrations support

### Task 3: PostgreSQL Adapter (Optional)
**Files to create:**
- `server/db/adapters/postgres_adapter.py`

**Features:**
- Connection pooling
- pgvector for embeddings (future)

### Task 4: Background Indexing Service
**Files to create:**
- `server/services/brain_dump_indexer.py`

**Features:**
- Subscribe to transcript stream
- Store segments to database
- Generate embeddings (placeholder)
- Extract topics (placeholder)

### Task 5: Search API
**Files to create:**
- `server/api/brain_dump_query.py`

**Features:**
- POST /brain-dump/search (keyword)
- GET /brain-dump/sessions
- GET /brain-dump/session/{id}

### Task 6: Google Drive Sync (Experimental)
**Files to create:**
- `server/db/adapters/google_drive_adapter.py`
- `server/services/google_drive_sync.py`

### Task 7: Integration
**Files to modify:**
- `server/api/ws_live_listener.py` - Hook into transcript stream
- `server/main.py` - Initialize storage on startup

### Task 8: Configuration
**Files to create:**
- `server/config/storage.yaml` (example)

---

## Directory Structure

```
server/
├── db/
│   ├── __init__.py
│   ├── storage_adapter.py      # Abstract base
│   ├── models.py               # Data classes
│   ├── config.py               # Storage config
│   └── adapters/
│       ├── __init__.py
│       ├── sqlite_adapter.py   # Default
│       ├── postgres_adapter.py # Optional
│       └── google_drive_adapter.py # Experimental
├── services/
│   ├── brain_dump_indexer.py   # Background service
│   └── google_drive_sync.py    # Sync service
└── api/
    └── brain_dump_query.py     # REST API
```

---

## Dependencies

```toml
# Add to pyproject.toml
[project.dependencies]
# Existing...
sqlalchemy = "^2.0.0"           # ORM for SQLite/PostgreSQL
aiosqlite = "^0.20.0"           # Async SQLite
asyncpg = { version = "^0.29.0", optional = true }  # PostgreSQL
pgvector = { version = "^0.2.5", optional = true }  # Vector search

[project.optional-dependencies]
postgres = ["asyncpg", "pgvector"]
gdrive = ["google-api-python-client", "google-auth-httplib2"]
```

---

## Database Schema

### SQLite (Default)
```sql
-- sessions table
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP NOT NULL,
    ended_at TIMESTAMP,
    title TEXT,
    source_app TEXT,
    tags TEXT, -- JSON array
    is_pinned BOOLEAN DEFAULT 0,
    audio_path TEXT,
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sync_status TEXT DEFAULT 'local'
);

-- transcript_segments table
CREATE TABLE transcript_segments (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    relative_time REAL,
    source TEXT CHECK(source IN ('system', 'microphone', 'voice_note')),
    speaker_id TEXT,
    text TEXT NOT NULL,
    confidence REAL,
    prev_segment_id TEXT,
    next_segment_id TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- FTS5 virtual table for full-text search
CREATE VIRTUAL TABLE transcript_fts USING fts5(
    text,
    content='transcript_segments',
    content_rowid='rowid'
);

-- Indexes
CREATE INDEX idx_segments_session ON transcript_segments(session_id);
CREATE INDEX idx_segments_timestamp ON transcript_segments(timestamp);
CREATE INDEX idx_sessions_started ON sessions(started_at);
```

---

## Implementation Order

### Phase 1: Foundation ✅ COMPLETE
1. ✅ Create models (dataclasses) - `server/db/models.py`
2. ✅ Create storage adapter base class - `server/db/storage_adapter.py`
3. ✅ Implement SQLite adapter - `server/db/adapters/sqlite_adapter.py`
4. ✅ Create background indexer service - `server/services/brain_dump_indexer.py`
5. ✅ Create search API endpoints - `server/api/brain_dump_query.py`
6. ✅ Integrate with WebSocket pipeline - `server/services/brain_dump_integration.py`
7. ✅ Integrate with main app - `server/main.py`, `server/api/ws_live_listener.py`
8. ✅ Write tests - `tests/test_brain_dump_*.py`

### Phase 2: Semantic Search ✅ COMPLETE
9. ✅ Embedding service - `server/services/embeddings.py`
10. ✅ Vector store (ChromaDB) - `server/db/vector_store.py`
11. ✅ Tests for embedding/vector functionality

### Phase 3.1: Hybrid Search ✅ COMPLETE
12. ✅ Hybrid search engine (RRF) - `server/services/hybrid_search.py`
13. ✅ Integrate embeddings with indexer
14. ✅ Hybrid search API endpoint
15. ✅ Tests for hybrid search - `tests/test_brain_dump_hybrid.py`

### Phase 3: UI & Advanced Features ⬜ PENDING
14. ⬜ macOS Settings UI for configuration
15. ⬜ PostgreSQL adapter
16. ⬜ Google Drive sync

---

## Progress Tracker

| Task | Status | File | Tests |
|------|--------|------|-------|
| Storage adapter base | ✅ Done | `server/db/storage_adapter.py` | ✅ |
| Models | ✅ Done | `server/db/models.py` | ✅ |
| SQLite adapter | ✅ Done | `server/db/adapters/sqlite_adapter.py` | ✅ 6 tests |
| Indexer service | ✅ Done | `server/services/brain_dump_indexer.py` | ✅ |
| Integration layer | ✅ Done | `server/services/brain_dump_integration.py` | ✅ 7 tests |
| Search API | ✅ Done | `server/api/brain_dump_query.py` | ✅ |
| Main app integration | ✅ Done | `server/main.py` | ✅ |
| WebSocket integration | ✅ Done | `server/api/ws_live_listener.py` | ✅ |
| **TOTAL** | **✅ 100%** | | **✅ 13 tests pass** |

### Remaining (Future Phases)

| Task | Phase | Status |
|------|-------|--------|
| PostgreSQL adapter | Phase 1 ext | ⬜ |
| Google Drive sync | Phase 1 ext | ⬜ |
| macOS Settings UI | Phase 2 | ⬜ |
| Semantic search | Phase 2 | ⬜ |
