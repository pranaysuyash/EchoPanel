# Brain Dump Phase 3.2 & 3.3 Specification

**Date**: 2026-02-16  
**Status**: PLANNING  
**Scope**: Configuration System + PostgreSQL Adapter

---

## User Stories

### US1: Configure Storage Backend
**As a** power user  
**I want** to choose between SQLite and PostgreSQL  
**So that** I can scale to larger datasets

**Acceptance Criteria**:
- Configuration file at `~/.echopanel/config.yaml`
- Environment variable override support
- Hot-reload of configuration (where possible)
- Migration path from SQLite to PostgreSQL

### US2: Environment-Based Configuration
**As a** DevOps engineer  
**I want** to configure via environment variables  
**So that** I can deploy with Docker/CI/CD

**Acceptance Criteria**:
- All config options have env var equivalents
- `ECHOPANEL_` prefix for all env vars
- Type conversion (strings → bools/ints)
- Secrets handling (db passwords, API keys)

### US3: Configuration API
**As a** macOS app developer  
**I want** to read/write configuration via API  
**So that** I can build a settings UI

**Acceptance Criteria**:
- `GET /config` - Read current configuration
- `POST /config` - Update configuration
- `POST /config/storage/test` - Test storage connection
- Validation before applying changes

### US4: PostgreSQL Support
**As a** power user with existing infrastructure  
**I want** to use PostgreSQL instead of SQLite  
**So that** I can handle larger datasets and concurrent access

**Acceptance Criteria**:
- PostgreSQL adapter implements same interface as SQLite
- Connection pooling with asyncpg
- pgvector extension for vector storage (instead of ChromaDB)
- Migration tool to move data SQLite → PostgreSQL

---

## Configuration Schema

```yaml
# ~/.echopanel/config.yaml
version: "1.0"

storage:
  backend: "sqlite"  # "sqlite" | "postgresql"
  
  sqlite:
    path: "~/.echopanel/brain_dump.db"
  
  postgresql:
    host: "localhost"
    port: 5432
    database: "echopanel"
    user: "echopanel"
    password: ""  # Loaded from env var or secrets file
    pool_size: 10
    max_overflow: 20

search:
  default_type: "hybrid"  # "keyword" | "semantic" | "hybrid"
  semantic_weight: 0.5
  max_results: 20

embeddings:
  enabled: true
  model: "all-MiniLM-L6-v2"
  batch_size: 32
  device: "cpu"  # "cpu" | "cuda" | "mps"

sync:
  google_drive:
    enabled: false
    mode: "backup"  # "backup" | "sync"
    encrypt: true
    sync_interval_minutes: 60

retention:
  max_days: 90  # 0 = keep forever
  pinned_forever: true
  audio_retention_days: 7

logging:
  level: "info"  # "debug" | "info" | "warning" | "error"
  file: "~/.echopanel/logs/echopanel.log"
  max_size_mb: 100
  backup_count: 5
```

---

## Environment Variables

```bash
# Storage
ECHOPANEL_STORAGE_BACKEND=postgresql
ECHOPANEL_SQLITE_PATH=/custom/path/db.sqlite

ECHOPANEL_POSTGRES_HOST=localhost
ECHOPANEL_POSTGRES_PORT=5432
ECHOPANEL_POSTGRES_DATABASE=echopanel
ECHOPANEL_POSTGRES_USER=echopanel
ECHOPANEL_POSTGRES_PASSWORD=secret
ECHOPANEL_POSTGRES_POOL_SIZE=10

# Search
ECHOPANEL_SEARCH_DEFAULT_TYPE=hybrid
ECHOPANEL_SEARCH_SEMANTIC_WEIGHT=0.5

# Embeddings
ECHOPANEL_EMBEDDINGS_ENABLED=true
ECHOPANEL_EMBEDDINGS_MODEL=all-MiniLM-L6-v2
ECHOPANEL_EMBEDDINGS_DEVICE=mps

# Retention
ECHOPANEL_RETENTION_MAX_DAYS=90
ECHOPANEL_RETENTION_PINNED_FOREVER=true

# Logging
ECHOPANEL_LOG_LEVEL=info
```

---

## API Endpoints

### Configuration
```
GET /config
Returns current configuration (with secrets masked)

POST /config
Updates configuration (validates first)

POST /config/storage/test
Tests storage connection with provided config

POST /config/reset
Resets to defaults
```

### Migration
```
POST /admin/migrate
{
  "from": "sqlite",
  "to": "postgresql",
  "options": {
    "drop_existing": false,
    "batch_size": 1000
  }
}
```

---

## PostgreSQL Schema

```sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Sessions table
CREATE TABLE sessions (
    id UUID PRIMARY KEY,
    started_at TIMESTAMP NOT NULL,
    ended_at TIMESTAMP,
    title TEXT,
    source_app TEXT,
    tags TEXT[],  -- PostgreSQL array type
    is_pinned BOOLEAN DEFAULT FALSE,
    audio_path TEXT,
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sync_status TEXT DEFAULT 'local',
    metadata JSONB  -- PostgreSQL JSON type
);

-- Transcript segments table
CREATE TABLE transcript_segments (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL,
    relative_time REAL,
    source TEXT CHECK(source IN ('system', 'microphone', 'voice_note')),
    speaker_id TEXT,
    text TEXT NOT NULL,
    confidence REAL,
    prev_segment_id UUID,
    next_segment_id UUID
);

-- Full-text search with pg_trgm (trigram similarity)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_segments_text_trgm ON transcript_segments USING gin(text gin_trgm_ops);

-- Vector embeddings using pgvector
CREATE TABLE segment_embeddings (
    segment_id UUID PRIMARY KEY REFERENCES transcript_segments(id) ON DELETE CASCADE,
    embedding vector(384),  -- all-MiniLM-L6-v2 dimension
    model TEXT
);

-- Vector similarity index
CREATE INDEX idx_embeddings_vector ON segment_embeddings USING ivfflat (embedding vector_cosine_ops);

-- Regular indexes
CREATE INDEX idx_segments_session ON transcript_segments(session_id);
CREATE INDEX idx_segments_timestamp ON transcript_segments(timestamp);
CREATE INDEX idx_sessions_started ON sessions(started_at);
```

---

## Implementation Plan

### Phase 3.2: Configuration System
1. Create `server/config/manager.py` - Configuration manager
2. Create `server/config/schema.py` - Pydantic models for config
3. Create `server/config/loader.py` - YAML + env var loading
4. Add config API endpoints to `server/api/config.py`
5. Tests for configuration system

### Phase 3.3: PostgreSQL Adapter
1. Create `server/db/adapters/postgres_adapter.py`
2. Implement all StorageAdapter methods with asyncpg
3. Add pgvector support for semantic search
4. Create migration tool
5. Tests for PostgreSQL adapter

---

## Success Criteria

- [ ] Configuration loads from YAML file
- [ ] Environment variables override YAML
- [ ] Configuration API works
- [ ] PostgreSQL adapter passes all storage tests
- [ ] Migration tool works SQLite → PostgreSQL
- [ ] All 30 existing tests still pass
- [ ] New tests for config and PostgreSQL pass

---

## Dependencies

```toml
# New dependencies
pyyaml = "^6.0.1"
pydantic-settings = "^2.0.0"
asyncpg = { version = "^0.29.0", optional = true }
pgvector = { version = "^0.2.5", optional = true }

[project.optional-dependencies]
postgres = ["asyncpg", "pgvector"]
```

---

Ready to implement.
