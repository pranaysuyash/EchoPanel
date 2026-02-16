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

1. ✅ Create models (dataclasses)
2. ✅ Create storage adapter base class
3. ✅ Implement SQLite adapter
4. ⬜ Implement PostgreSQL adapter
5. ⬜ Create background indexer service
6. ⬜ Integrate with WebSocket pipeline
7. ⬜ Create search API endpoints
8. ⬜ Add configuration UI (macOS)
9. ⬜ Implement Google Drive sync
10. ⬜ Write tests

---

## Progress Tracker

| Task | Status | File |
|------|--------|------|
| Storage adapter base | ✅ Done | `server/db/storage_adapter.py` |
| Models | ✅ Done | `server/db/models.py` |
| SQLite adapter | 🔄 In Progress | `server/db/adapters/sqlite_adapter.py` |
| Config | ⬜ Todo | `server/db/config.py` |
| Indexer service | ⬜ Todo | `server/services/brain_dump_indexer.py` |
| Search API | ⬜ Todo | `server/api/brain_dump_query.py` |
| Integration | ⬜ Todo | `server/api/ws_live_listener.py` |
