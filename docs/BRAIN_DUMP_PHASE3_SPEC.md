# Brain Dump Phase 3 Specification

**Date**: 2026-02-16  
**Status**: PLANNING  
**Goal**: Hybrid search, configuration UI, advanced storage options

---

## User Stories

### US1: Hybrid Search
**As a** user  
**I want** to search using both keywords and meaning  
**So that** I can find "roadmap discussion" even if the word "roadmap" wasn't used

**Acceptance Criteria**:
- Search combines keyword (SQLite FTS5) and semantic (ChromaDB) results
- Results ranked by combined relevance score
- Falls back to keyword if semantic unavailable
- API supports `query_type: "hybrid" | "keyword" | "semantic"`

### US2: Configure Storage Backend
**As a** power user  
**I want** to choose my storage backend  
**So that** I can use PostgreSQL for better performance or Google Drive for backup

**Acceptance Criteria**:
- macOS Settings UI shows storage options
- SQLite is default (zero config)
- PostgreSQL configurable with connection string
- Google Drive OAuth setup
- Backup mode (one-way) vs sync mode (bidirectional)

### US3: Automatic Embeddings
**As a** user  
**I want** embeddings generated automatically  
**So that** I don't have to manually trigger semantic indexing

**Acceptance Criteria**:
- Embeddings generated when transcripts are stored
- Batch processing for efficiency
- Queue for embedding generation (non-blocking)
- Backfill capability for existing transcripts

### US4: Export to Obsidian
**As a** knowledge worker  
**I want** to export sessions to Obsidian  
**So that** I can integrate with my second brain

**Acceptance Criteria**:
- Export single session or bulk export
- Markdown format with frontmatter
- Audio file links
- Tag synchronization

---

## Technical Requirements

### Hybrid Search Algorithm

```python
def hybrid_search(query: str, k: int = 20) -> List[Result]:
    # 1. Get keyword results
    keyword_results = sqlite_search(query, k=k)
    
    # 2. Get semantic results
    query_embedding = embed(query)
    semantic_results = chroma_search(query_embedding, k=k)
    
    # 3. Merge and deduplicate
    all_results = merge_results(keyword_results, semantic_results)
    
    # 4. Re-rank by combined score
    for result in all_results:
        result.score = (
            alpha * result.keyword_score + 
            (1 - alpha) * result.semantic_score
        )
    
    return sorted(all_results, key=lambda r: r.score, reverse=True)[:k]
```

**Parameters**:
- `alpha`: Weight for keyword vs semantic (default 0.5)
- Reciprocal Rank Fusion for combining scores

### Configuration Schema

```yaml
storage:
  backend: "sqlite" | "postgresql" | "google_drive"
  
  sqlite:
    path: "~/.echopanel/brain_dump.db"
  
  postgresql:
    url: "postgresql://user:pass@localhost/echopanel"
  
  google_drive:
    enabled: true
    mode: "backup" | "sync"
    encrypt: true

search:
  default_type: "hybrid"
  semantic_weight: 0.5
  max_results: 20

embeddings:
  enabled: true
  model: "all-MiniLM-L6-v2"
  batch_size: 32
  generate_on_store: true
```

---

## Architecture

### Phase 3 System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS App (Swift)                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Settings UI                                │   │
│  │  - Storage backend selection                            │   │
│  │  - Google Drive OAuth                                   │   │
│  │  - Search preferences                                   │   │
│  │  - Export options                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ API Calls
┌─────────────────────────────────────────────────────────────────┐
│                       Python Server                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Hybrid       │  │ PostgreSQL   │  │ Google Drive         │  │
│  │ Search       │  │ Adapter      │  │ Sync                 │  │
│  │ (SQLite +    │  │ (optional)   │  │ (optional)           │  │
│  │  ChromaDB)   │  │              │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Embedding    │  │ Config       │  │ Export               │  │
│  │ Queue        │  │ Manager      │  │ (Obsidian, etc)      │  │
│  │ (async)      │  │              │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 3.1: Hybrid Search
- Implement Reciprocal Rank Fusion
- Update search API to support hybrid mode
- Integrate embedding generation with indexer
- Tests for hybrid search

### Phase 3.2: Configuration System
- Create config manager
- Add configuration API endpoints
- Environment variable support
- Config file (YAML) support

### Phase 3.3: PostgreSQL Adapter
- Implement PostgreSQLAdapter
- Connection pooling
- Migration from SQLite
- Tests

### Phase 3.4: Google Drive Sync
- OAuth implementation
- File upload/download
- Sync conflict resolution
- Tests

### Phase 3.5: macOS Settings UI
- SwiftUI settings panel
- Backend selector
- Connection string input
- OAuth flow
- Export UI

---

## API Endpoints

### New Endpoints

```
POST /brain-dump/search
{
  "query": "product planning",
  "query_type": "hybrid",  // "keyword" | "semantic" | "hybrid"
  "alpha": 0.5,            // keyword weight (0-1)
  "limit": 20
}

GET /config
Returns current configuration

POST /config
Updates configuration

POST /config/storage/test
Tests storage connection

POST /export/obsidian
{
  "session_ids": [...],
  "vault_path": "~/Notes",
  "include_audio": true
}

POST /admin/backfill-embeddings
Generates embeddings for existing transcripts
```

---

## Success Criteria

- [ ] Hybrid search returns results from both keyword and semantic
- [ ] macOS UI allows backend configuration
- [ ] PostgreSQL adapter passes all storage tests
- [ ] Google Drive sync works (one-way at minimum)
- [ ] All 24 existing tests still pass
- [ ] New tests for hybrid search pass
- [ ] Configuration persists across restarts

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ChromaDB performance with 100k+ docs | High | Implement pagination, consider FAISS |
| PostgreSQL connection pool exhaustion | Medium | Use asyncpg with proper pooling |
| Google Drive rate limits | Medium | Implement exponential backoff |
| Embedding generation backlog | Medium | Queue with priority, batch processing |
| Config migration issues | Low | Version configs, provide defaults |

---

## Dependencies

```toml
# New dependencies
asyncpg = { version = "^0.29.0", optional = true }
google-auth-oauthlib = { version = "^1.2.0", optional = true }
google-api-python-client = { version = "^2.100.0", optional = true }
pyyaml = "^6.0.1"
```

---

## Timeline Estimate

| Task | Duration |
|------|----------|
| Hybrid search | 2-3 hours |
| Config system | 1-2 hours |
| PostgreSQL adapter | 2-3 hours |
| Google Drive sync | 3-4 hours |
| macOS UI | 4-6 hours |
| Testing & docs | 2-3 hours |
| **Total** | **14-21 hours** |

---

Ready to proceed with implementation.
