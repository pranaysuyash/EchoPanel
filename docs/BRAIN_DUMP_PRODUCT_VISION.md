# Brain Dump Product Vision — Personal Audio Memory System

**Date**: 2026-02-15  
**Status**: CONCEPT  
**Type**: PRODUCT_STRATEGY  
**Related**: VOICE_NOTES_DESIGN.md, FEATURE_EXPLORATION_PERSONAS.md

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [What We Already Have (Foundation)](#what-we-already-have-foundation)
3. [The Brain Dump Concept](#the-brain-dump-concept)
4. [Technical Architecture](#technical-architecture)
5. [User Experience](#user-experience)
6. [Privacy & Security Model](#privacy--security-model)
7. [Integration Ecosystem](#integration-ecosystem)
8. [Differentiation from Competitors](#differentiation-from-competitors)
9. [Implementation Phases](#implementation-phases)
10. **[Storage Architecture (Flexible Backend)](#storage-architecture-flexible-backend)** ⭐ NEW
11. [Open Questions](#open-questions)
12. [Success Metrics](#success-metrics)
13. [Related Documents](#related-documents)
14. [Conclusion](#conclusion)

---

## Executive Summary

EchoPanel already captures **all system audio + microphone audio** in real-time. The "Brain Dump" vision extends this from "meeting transcription tool" to **"personal audio memory system"** — a searchable, queryable archive of everything you hear and say.

**The Shift:**
- **Now**: Capture meeting → Get transcript → Export
- **Future**: Continuous capture → Automatic organization → Ask questions anytime

---

## What We Already Have (Foundation)

| Component | Current Implementation | Brain Dump Extension |
|-----------|------------------------|----------------------|
| **Audio Capture** | Dual lane: realtime + recording | Continuous background capture |
| **ASR** | whisper.cpp 35× real-time | Persistent transcription to DB |
| **Storage** | Files in `/tmp/echopanel_recordings/` | Searchable transcript database |
| **Voice Notes** | Intentional button-triggered notes | Always-on + marked moments |
| **WebSocket** | Live streaming to server | Background indexing service |

---

## The Brain Dump Concept

### Core Idea

> "Your life has a soundtrack. EchoPanel remembers it."

Imagine:
- **Morning standup**: "What did Sarah say about the API yesterday?" → Search → Find exact quote
- **Lecture**: "What was that concept about vector embeddings?" → Query → Get timestamp + context
- **Podcast**: "The guest mentioned a book..." → Search transcripts → Find recommendation
- **Your thoughts**: "I had an idea while walking..." → Voice note auto-tagged → Retrieve later

### Use Cases

| Scenario | Capture | Query Example |
|----------|---------|---------------|
| **Work meetings** | System audio (Zoom/Meet) | "What did we decide about the launch date?" |
| **Personal calls** | Mic + system (with consent) | "What address did mom give me?" |
| **Lectures/Presentations** | System audio (YouTube/Live) | "Explain the transformer architecture from CS224N" |
| **Podcasts/Audiobooks** | System audio | "What were the 3 habits from Atomic Habits?" |
| **Voice memos** | Mic (always listening) | "What ideas did I have on Tuesday?" |
| **YouTube tutorials** | System audio | "How do I fix that Docker error from the video?" |

---

## Technical Architecture

### Data Flow (Current vs Brain Dump)

```
CURRENT:
┌─────────────┐    ┌──────────┐    ┌────────────┐    ┌─────────┐
│ Audio Input │───▶│   ASR    │───▶│ Transcript │───▶│  Export │
│ (Stream)    │    │(Real-time)│    │  (Memory)  │    │ (File)  │
└─────────────┘    └──────────┘    └────────────┘    └─────────┘
                                        │
                                        ▼ (session ends)
                                   [Discarded]

BRAIN DUMP:
┌─────────────┐    ┌──────────┐    ┌────────────┐    ┌──────────────┐
│ Audio Input │───▶│   ASR    │───▶│ Transcript │───▶│   Database   │
│ (Continuous)│    │(Real-time)│    │  (Memory)  │    │(Persistent)  │
└─────────────┘    └──────────┘    └────────────┘    └──────────────┘
                                                           │
                    ┌──────────────┬──────────────┬────────┘
                    ▼              ▼              ▼
              ┌─────────┐   ┌──────────┐   ┌──────────┐
              │ Search  │   │  RAG LLM │   │  Export  │
              │ (Full-text│   │ (Q&A)    │   │(Obsidian)│
              │ + Vector)│   │          │   │          │
              └─────────┘   └──────────┘   └──────────┘
```

### New Components Needed

#### 1. Storage Abstraction Layer

```python
# server/db/storage_adapter.py
from abc import ABC, abstractmethod
from typing import List, Optional

class StorageAdapter(ABC):
    """Abstract base for transcript storage backends."""
    
    @abstractmethod
    async def save_segment(self, segment: TranscriptSegment) -> None:
        pass
    
    @abstractmethod
    async def search(self, query: str, filters: SearchFilters) -> List[SearchResult]:
        pass
    
    @abstractmethod
    async def get_session(self, session_id: UUID) -> Optional[Session]:
        pass
    
    @abstractmethod
    async def semantic_search(self, embedding: List[float], k: int = 10) -> List[SearchResult]:
        pass

class SQLiteAdapter(StorageAdapter):
    """Default local SQLite backend."""
    def __init__(self, db_path: str = "~/.echopanel/brain_dump.db"):
        self.db_path = Path(db_path).expanduser()
        self._init_db()
    
    def _init_db(self):
        # Create tables, enable FTS5
        pass

class PostgreSQLAdapter(StorageAdapter):
    """Optional PostgreSQL backend for power users."""
    def __init__(self, connection_string: str):
        self.conn = asyncpg.connect(connection_string)
    
    async def semantic_search(self, embedding, k=10):
        # Use pgvector for vector similarity
        return await self.conn.fetch(
            "SELECT * FROM segments ORDER BY embedding <-> $1 LIMIT $2",
            embedding, k
        )

class GoogleDriveAdapter(StorageAdapter):
    """Experimental: Use Google Drive as storage."""
    # Append-only NDJSON files
    # Read: Download and parse
    # Write: Append to daily file
    pass

# Factory
def get_storage_adapter(config: StorageConfig) -> StorageAdapter:
    if config.backend == "postgresql":
        return PostgreSQLAdapter(config.connection_string)
    elif config.backend == "google_drive":
        return GoogleDriveAdapter(config.drive_config)
    else:
        return SQLiteAdapter(config.sqlite_path)
```

### 2. Data Models

```python
# server/db/models.py
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, List
from uuid import UUID
import enum

class AudioSource(enum.Enum):
    SYSTEM = "system"           # System audio (Zoom, browser)
    MICROPHONE = "microphone"   # Raw mic input
    VOICE_NOTE = "voice_note"   # Intentional voice notes

@dataclass
class TranscriptSegment:
    id: UUID
    session_id: UUID
    timestamp: datetime        # UTC absolute time
    relative_time: float       # Seconds from session start
    source: AudioSource
    speaker_id: Optional[str]  # From diarization
    text: str
    confidence: float          # 0.0 - 1.0
    embedding: Optional[List[float]] = None  # For semantic search
    
    # Metadata for linking
    prev_segment_id: Optional[UUID] = None
    next_segment_id: Optional[UUID] = None

@dataclass
class Session:
    id: UUID
    started_at: datetime
    ended_at: Optional[datetime]
    title: Optional[str]       # Auto-generated or user-edited
    source_app: Optional[str]  # "zoom", "chrome", "voice_note"
    tags: List[str]            # Auto-extracted topics
    is_pinned: bool = False    # Keep forever, don't auto-delete
    audio_file_path: Optional[str] = None
    
    # Sync metadata
    last_modified: datetime
    sync_status: str = "local"  # "local", "synced", "pending"

@dataclass
class MemoryResult:
    """Search result from brain dump query."""
    segment: TranscriptSegment
    session: Session
    relevance_score: float
    context_before: List[TranscriptSegment]  # Surrounding context
    context_after: List[TranscriptSegment]
```

#### 2. Background Indexing Service

```python
# server/services/brain_dump_indexer.py
class BrainDumpIndexer:
    """Continuously processes transcripts and builds search index."""
    
    async def index_segment(self, segment: TranscriptSegment):
        # 1. Store in database
        await self.db.insert(segment)
        
        # 2. Generate embedding for semantic search
        embedding = await self.embedding_model.encode(segment.text)
        await self.vector_store.add(segment.id, embedding)
        
        # 3. Extract entities/topics
        topics = await self.topic_extractor.extract(segment.text)
        await self.db.update_tags(segment.session_id, topics)
        
        # 4. Link related segments (across sessions)
        related = await self.find_related(segment)
        await self.db.add_links(segment.id, related)
```

#### 3. Semantic Search API

```python
# server/api/brain_dump_query.py
@app.post("/brain-dump/search")
async def search_brain_dump(
    query: str,
    query_type: Literal["keyword", "semantic", "hybrid"],
    time_range: Optional[TimeRange] = None,
    source_filter: Optional[List[AudioSource]] = None,
    speaker_filter: Optional[List[str]] = None,
):
    """
    Search personal audio memory.
    
    Examples:
    - "What did Sarah say about the API?" → semantic + entity filter
    - "Docker error fix" → keyword search in tutorials
    - "Ideas from last week" → time range + voice_note filter
    """
    if query_type == "semantic":
        query_embedding = await embedding_model.encode(query)
        results = await vector_store.similarity_search(query_embedding, k=10)
    elif query_type == "hybrid":
        # Combine keyword + semantic + entity extraction
        results = await hybrid_search(query, filters)
    
    return {
        "results": results,
        "suggested_followups": generate_followups(query, results)
    }
```

#### 4. RAG Q&A Interface

```python
# Ask questions about your audio memory
@app.post("/brain-dump/ask")
async def ask_brain_dump(question: str):
    """
    RAG-based Q&A over personal audio history.
    
    Example questions:
    - "What were my action items from the standup on Tuesday?"
    - "Summarize the key points from the ML lecture I watched"
    - "What books were recommended in podcasts this month?"
    """
    # 1. Retrieve relevant segments
    context = await retrieve_context(question, top_k=20)
    
    # 2. Generate answer with LLM
    answer = await llm.generate(
        prompt=BRAIN_DUMP_QA_PROMPT,
        context=context,
        question=question
    )
    
    return {
        "answer": answer.text,
        "sources": answer.source_segments,  # Citations with timestamps
        "confidence": answer.confidence
    }
```

---

## User Experience

### Mode 1: Passive Capture (Always On)

```
Status bar: 🔴 Recording memory

User doesn't interact. System continuously captures and indexes.
Storage: Last 7 days kept by default, pinned sessions kept forever.
```

### Mode 2: Active Marking (Intentional)

```
Hotkey: ⌥⇧M (Option+Shift+M) - "Mark this moment"

User hears something important → presses hotkey → system:
1. Saves last 30 seconds + next 2 minutes at high quality
2. Tags as "⭐ Important"
3. Adds to "Marked Moments" collection
```

### Mode 3: Voice Note (Original Feature)

```
Hotkey: ⌘N (Command+N) - "Voice note"

User has a thought → holds hotkey → speaks → releases
Note is transcribed and tagged as "💭 Thought"
```

### Query Interface (macOS App)

```swift
// Brain Dump Search UI
struct BrainDumpSearchView: View {
    @State var query: String = ""
    @State var results: [MemoryResult] = []
    
    var body: some View {
        VStack {
            // Natural language search
            SearchBar("Search your audio memory...", text: $query)
            
            // Filter chips
            FilterRow([
                .all, .meetings, .calls, .lectures, 
                .voiceNotes, .markedMoments
            ])
            
            // Timeline view
            List(results) { result in
                MemoryCard(result)
                    .onTapGesture { playSegment(result) }
            }
        }
    }
}
```

### Query Examples

| Natural Language | System Interpretation |
|------------------|----------------------|
| "What did Sarah say about the API?" | Entity search (Sarah) + keyword (API) + semantic similarity |
| "My ideas from last Tuesday" | Time filter + voice_note source + topic clustering |
| "Docker error from that YouTube video" | Source=system + keyword (Docker) + content type (tutorial) |
| "Summarize my standups this week" | Time range + meeting template + aggregation |
| "Books recommended in podcasts" | Source filter + entity extraction (book titles) |

---

## Privacy & Security Model

### Local-First Architecture

| Component | Location | Reasoning |
|-----------|----------|-----------|
| Raw audio | Local encrypted disk | Privacy, bandwidth |
| Transcripts | Local database | Search speed, privacy |
| Embeddings | Local vector DB | Semantic search works offline |
| LLM inference | Local (MLX) | Q&A without cloud |
| Sync (optional) | iCloud/E2EE | Backup only, not required |

### Data Retention Policies

```
Default: Keep 7 days of continuous capture
Marked moments: Keep forever
Voice notes: Keep forever
Pinned sessions: Keep forever
Auto-delete: Compress old audio to transcripts-only
```

### Consent Model

- **Your mic**: Always ok (your data)
- **System audio**: User acknowledges (like screen recording)
- **Calls with others**: Optional per-call consent recording
- **Meeting participants**: Depends on jurisdiction (auto-transcription vs recording)

---

## Integration Ecosystem

### Export Destinations

| App | Export Format | Use Case |
|-----|---------------|----------|
| **Obsidian** | Markdown + audio links | Second brain building |
| **Notion** | Rich text + embeddings | Team knowledge base |
| **Readwise** | Highlights | Spaced repetition |
| **Roam Research** | Bidirectional links | Networked thought |
| **Apple Notes** | Native | Quick access |

### API for Automation

```bash
# Query brain dump via CLI
echopanel query "What did I learn about transformers?"

# Export last week to Obsidian
echopanel export --since "7 days ago" --format obsidian --vault ~/Notes

# Get daily digest
echopanel digest --today --format markdown
```

---

## Differentiation from Competitors

| Feature | Otter | Fireflies | EchoPanel Brain Dump |
|---------|-------|-----------|----------------------|
| **Scope** | Meetings only | Meetings only | **Everything** (meetings, calls, lectures, podcasts, thoughts) |
| **Storage** | Cloud | Cloud | **Local-first** |
| **Search** | Keyword | Keyword | **Semantic + RAG Q&A** |
| **Always-on** | ❌ | ❌ | **✅ Continuous capture** |
| **Voice notes** | ❌ | ❌ | **✅ Integrated** |
| **Price** | $10-20/mo | $10-19/mo | **One-time purchase** |
| **Privacy** | Cloud processed | Cloud processed | **On-device only** |

---

## Implementation Phases

### Phase 1: Foundation (v0.4)
- [ ] **Flexible storage backend** (SQLite default, PostgreSQL optional)
- [ ] Background indexing service
- [ ] Basic keyword search
- [ ] Continuous capture mode (opt-in)
- [ ] Google Drive sync (JSON export) - experimental

### Phase 2: Intelligence (v0.5)
- [ ] Sentence embeddings for semantic search
- [ ] Vector database (FAISS/Chroma)
- [ ] Entity extraction (people, topics, dates)
- [ ] Auto-tagging

### Phase 3: Q&A (v0.6)
- [ ] RAG pipeline with local LLM (MLX)
- [ ] Natural language queries
- [ ] Source citations with timestamps
- [ ] Daily/weekly digest generation

### Phase 4: Integrations (v0.7)
- [ ] Obsidian export plugin
- [ ] Notion integration
- [ ] Apple Shortcuts support
- [ ] API for automation

### Phase 5: Advanced (v0.8+)
- [ ] Speaker recognition ("what did Sarah say?")
- [ ] Topic clustering
- [ ] Cross-session linking
- [ ] Predictive suggestions ("you mentioned X in Y context")

---

## Storage Architecture (Flexible Backend)

### Strategy: Progressive Enhancement

| Backend | Use Case | Configuration | Default |
|---------|----------|---------------|---------|
| **SQLite** | Single-user, local-first | Zero setup | ✅ Yes |
| **PostgreSQL** | Power users, complex queries | Connection string | Optional |
| **Google Drive** | Cloud backup, sync | OAuth consent | Experimental |

### SQLite (Default)

```python
# config/storage.py
DEFAULT_SQLITE_PATH = "~/.echopanel/brain_dump.db"

# Auto-created on first run
# - Zero configuration
# - Single-user optimized
# - FTS5 for full-text search
# - ~1.7GB/year for heavy usage
```

**Schema:**
```sql
-- SQLite with FTS5 extension
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    title TEXT,
    source_app TEXT,
    is_pinned BOOLEAN DEFAULT 0,
    audio_path TEXT
);

CREATE TABLE transcript_segments (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    timestamp TIMESTAMP,
    relative_time REAL,
    source TEXT,  -- 'system' | 'microphone' | 'voice_note'
    speaker_id TEXT,
    text TEXT,
    confidence REAL
);

-- Full-text search virtual table
CREATE VIRTUAL TABLE transcript_fts USING fts5(
    text, 
    session_id,
    content='transcript_segments',
    content_rowid='id'
);
```

### PostgreSQL (Optional)

```python
# User provides connection string via UI or env
DATABASE_URL=postgresql://user:pass@localhost/echopanel

# Benefits:
# - Better concurrent access
# - Advanced querying (window functions, CTEs)
# - pgvector for vector similarity
# - Power users may already have Postgres running
```

**Migration:**
```bash
# Export from SQLite → Import to PostgreSQL
python -m echopanel.db.migrate --from sqlite --to postgresql
```

### Google Drive Sync (Experimental)

```python
# Sync strategy: Append-only JSON lines
# Format: One JSON object per line (NDJSON)

# File structure in Drive:
# /EchoPanel/
#   /2026/
#     /sessions/
#       session_abc123.json      # Session metadata
#       session_def456.json
#     /segments/
#       2026-02-15.ndjson        # Daily transcript segments
#       2026-02-16.ndjson
#     /embeddings/
#       2026-02-15_embeddings.jsonl
#     /index/
#       manifest.json            # Sync state
```

**Sync Modes:**
```python
class SyncMode(Enum):
    OFF = "off"                    # Local only
    BACKUP = "backup"              # One-way: Local → Drive
    BIDIRECTIONAL = "bidirectional" # Experimental: Merge conflicts

# Privacy: 
# - User's Google Drive (their account)
# - JSON format (readable, future-proof)
# - No audio files (transcripts only)
# - Optional encryption before upload
```

**Google Drive Export Format:**
```json
// session_2026-02-15_abc123.json
{
  "id": "abc123",
  "started_at": "2026-02-15T09:00:00Z",
  "ended_at": "2026-02-15T10:30:00Z",
  "title": "Product Planning Meeting",
  "source_app": "zoom",
  "tags": ["planning", "product", "q1"],
  "is_pinned": true,
  "segments_count": 152,
  "export_version": "1.0"
}

// 2026-02-15.ndjson (one line per segment)
{"id": "seg001", "session_id": "abc123", "timestamp": "2026-02-15T09:05:23Z", "text": "Let's discuss the roadmap", "speaker": "Alice", "confidence": 0.95}
{"id": "seg002", "session_id": "abc123", "timestamp": "2026-02-15T09:05:45Z", "text": "I think we should prioritize mobile", "speaker": "Bob", "confidence": 0.92}
```

**Why Google Drive (not custom cloud):**
- User already has account (no signup)
- 15GB free tier
- User controls their data
- No EchoPanel backend costs
- Future-proof: Standard JSON

### Storage Configuration UI

```swift
// macOS Preferences Panel
struct StorageSettingsView: View {
    @State var backend: StorageBackend = .sqlite
    
    var body: some View {
        Form {
            Section("Database") {
                Picker("Backend", selection: $backend) {
                    Text("SQLite (Default)").tag(.sqlite)
                    Text("PostgreSQL").tag(.postgresql)
                }
                
                if backend == .postgresql {
                    TextField("Connection String", text: $postgresUrl)
                    Button("Test Connection")
                }
            }
            
            Section("Cloud Backup") {
                Toggle("Sync to Google Drive", isOn: $enableDriveSync)
                
                if enableDriveSync {
                    Picker("Mode", selection: $syncMode) {
                        Text("Backup only (one-way)").tag(SyncMode.backup)
                        Text("Bidirectional (experimental)").tag(SyncMode.bidirectional)
                    }
                    
                    Toggle("Encrypt before upload", isOn: $encryptUploads)
                    
                    Text("Storage used: \(driveUsage)")
                    Button("Force Sync Now")
                    Button("Disconnect")
                }
            }
            
            Section("Data Management") {
                Text("Local storage: \(localSize)")
                Button("Export All (JSON)")
                Button("Compact Database")
                Button("Clear Old Data (> 90 days)")
            }
        }
    }
}
```

---

## Open Questions

1. **Storage growth**: 8 hours/day × 365 days = ~2920 hours/year. At 10KB/minute transcript = ~1.7GB/year. Manageable?

2. **Audio retention**: Keep full audio or transcripts only? Audio = 100x storage but enables re-transcription with better models later.

3. **Battery impact**: Continuous ASR at 35× real-time = ~3% CPU on M3. Acceptable for background?

4. **Legal**: Recording laws vary by jurisdiction. Need geo-aware consent flows?

5. **Selective capture**: Should users be able to exclude apps (Spotify, Netflix)?

6. **Multi-device**: How sync brain dump across Mac, iPhone, Vision Pro? (Answer: Google Drive JSON as common format?)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Daily active capture** | 50% of users | % users with capture enabled |
| **Search engagement** | 3 queries/week | API call volume |
| **Marked moments** | 5/week | User marking behavior |
| **Voice notes** | 10/week | Feature adoption |
| **Export usage** | 30% monthly | Obsidian/Notion exports |
| **Retention** | <5% churn | Users keeping capture on |

---

## Related Documents

- **VOICE_NOTES_DESIGN.md**: Voice note feature (subset of brain dump)
- **FEATURE_EXPLORATION_PERSONAS.md**: User personas that would use brain dump
- **MLX_AUDIO_COMPREHENSIVE_RESEARCH.md**: On-device ASR for privacy
- **RAG_PIPELINE_ARCHITECTURE.md**: Q&A infrastructure

---

## Conclusion

EchoPanel is uniquely positioned to be the **first local-first, privacy-preserving personal audio memory system**. We already have the hard parts:
- Real-time ASR ✓
- Audio capture ✓
- Local processing ✓

The brain dump vision extends this from "tool" to **"augmented memory"** — a genuinely new product category.

**Next step**: Technical spike for Phase 1 (local DB + continuous capture) to validate UX and performance.
