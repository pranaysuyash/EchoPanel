"""SQLite storage adapter for Brain Dump."""

import json
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import List, Optional
from uuid import UUID

import aiosqlite

from ..storage_adapter import StorageAdapter, StorageError, StorageQueryError
from ..models import (
    Session,
    TranscriptSegment,
    AudioSource,
    SyncStatus,
    SearchFilters,
    SearchResult,
    StorageConfig
)


class SQLiteAdapter(StorageAdapter):
    """SQLite storage adapter with FTS5 full-text search.
    
    This is the default storage backend. It requires zero configuration
    and stores data in a local SQLite database file.
    """
    
    def __init__(self, config: StorageConfig):
        super().__init__(config)
        self.db_path = Path(config.sqlite_path).expanduser()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._connection: Optional[aiosqlite.Connection] = None
    
    async def initialize(self) -> None:
        """Initialize the database (create tables, indexes, FTS)."""
        async with self._get_connection() as conn:
            # Enable foreign keys
            await conn.execute("PRAGMA foreign_keys = ON")
            
            # Create sessions table
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    started_at TIMESTAMP NOT NULL,
                    ended_at TIMESTAMP,
                    title TEXT,
                    source_app TEXT,
                    tags TEXT,
                    is_pinned INTEGER DEFAULT 0,
                    audio_path TEXT,
                    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    sync_status TEXT DEFAULT 'local',
                    metadata TEXT
                )
            """)
            
            # Create transcript_segments table
            await conn.execute("""
                CREATE TABLE IF NOT EXISTS transcript_segments (
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
                    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
                )
            """)
            
            # Create FTS5 virtual table for full-text search
            await conn.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS transcript_fts USING fts5(
                    text,
                    content='transcript_segments',
                    content_rowid='rowid'
                )
            """)
            
            # Create indexes
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_segments_session 
                ON transcript_segments(session_id)
            """)
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_segments_timestamp 
                ON transcript_segments(timestamp)
            """)
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_sessions_started 
                ON sessions(started_at)
            """)
            await conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_sessions_pinned 
                ON sessions(is_pinned, started_at)
            """)
            
            # Create triggers to keep FTS index in sync
            await conn.execute("""
                CREATE TRIGGER IF NOT EXISTS segments_fts_insert 
                AFTER INSERT ON transcript_segments
                BEGIN
                    INSERT INTO transcript_fts(rowid, text)
                    VALUES (new.rowid, new.text);
                END
            """)
            
            await conn.execute("""
                CREATE TRIGGER IF NOT EXISTS segments_fts_delete
                AFTER DELETE ON transcript_segments
                BEGIN
                    INSERT INTO transcript_fts(transcript_fts, rowid, text)
                    VALUES ('delete', old.rowid, old.text);
                END
            """)
            
            await conn.execute("""
                CREATE TRIGGER IF NOT EXISTS segments_fts_update
                AFTER UPDATE ON transcript_segments
                BEGIN
                    INSERT INTO transcript_fts(transcript_fts, rowid, text)
                    VALUES ('delete', old.rowid, old.text);
                    INSERT INTO transcript_fts(rowid, text)
                    VALUES (new.rowid, new.text);
                END
            """)
            
            await conn.commit()
    
    async def close(self) -> None:
        """Close database connection."""
        if self._connection:
            await self._connection.close()
            self._connection = None
    
    def _get_connection(self) -> aiosqlite.Connection:
        """Get or create database connection."""
        if self._connection is None:
            self._connection = aiosqlite.connect(str(self.db_path))
        return self._connection
    
    # Session operations
    
    async def create_session(self, session: Session) -> Session:
        """Create a new recording session."""
        async with self._get_connection() as conn:
            await conn.execute(
                """
                INSERT INTO sessions 
                (id, started_at, ended_at, title, source_app, tags, is_pinned, 
                 audio_path, last_modified, sync_status, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(session.id),
                    session.started_at.isoformat(),
                    session.ended_at.isoformat() if session.ended_at else None,
                    session.title,
                    session.source_app,
                    json.dumps(session.tags),
                    1 if session.is_pinned else 0,
                    session.audio_file_path,
                    session.last_modified.isoformat(),
                    session.sync_status.value,
                    json.dumps(session.metadata)
                )
            )
            await conn.commit()
            return session
    
    async def get_session(self, session_id: UUID) -> Optional[Session]:
        """Get a session by ID."""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "SELECT * FROM sessions WHERE id = ?",
                (str(session_id),)
            )
            row = await cursor.fetchone()
            if row:
                return self._row_to_session(row)
            return None
    
    async def update_session(self, session: Session) -> Session:
        """Update an existing session."""
        session.last_modified = datetime.utcnow()
        
        async with self._get_connection() as conn:
            await conn.execute(
                """
                UPDATE sessions SET
                    ended_at = ?,
                    title = ?,
                    source_app = ?,
                    tags = ?,
                    is_pinned = ?,
                    audio_path = ?,
                    last_modified = ?,
                    sync_status = ?,
                    metadata = ?
                WHERE id = ?
                """,
                (
                    session.ended_at.isoformat() if session.ended_at else None,
                    session.title,
                    session.source_app,
                    json.dumps(session.tags),
                    1 if session.is_pinned else 0,
                    session.audio_file_path,
                    session.last_modified.isoformat(),
                    session.sync_status.value,
                    json.dumps(session.metadata),
                    str(session.id)
                )
            )
            await conn.commit()
            return session
    
    async def end_session(self, session_id: UUID) -> Optional[Session]:
        """Mark a session as ended."""
        session = await self.get_session(session_id)
        if session:
            session.ended_at = datetime.utcnow()
            await self.update_session(session)
        return session
    
    async def list_sessions(
        self,
        limit: int = 100,
        offset: int = 0,
        pinned_only: bool = False
    ) -> List[Session]:
        """List sessions, most recent first."""
        async with self._get_connection() as conn:
            if pinned_only:
                cursor = await conn.execute(
                    """
                    SELECT * FROM sessions 
                    WHERE is_pinned = 1
                    ORDER BY started_at DESC 
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset)
                )
            else:
                cursor = await conn.execute(
                    """
                    SELECT * FROM sessions 
                    ORDER BY started_at DESC 
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset)
                )
            
            rows = await cursor.fetchall()
            return [self._row_to_session(row) for row in rows]
    
    async def delete_session(self, session_id: UUID) -> bool:
        """Delete a session and all its segments."""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "DELETE FROM sessions WHERE id = ?",
                (str(session_id),)
            )
            await conn.commit()
            return cursor.rowcount > 0
    
    # Segment operations
    
    async def save_segment(self, segment: TranscriptSegment) -> TranscriptSegment:
        """Save a transcript segment."""
        async with self._get_connection() as conn:
            await conn.execute(
                """
                INSERT INTO transcript_segments 
                (id, session_id, timestamp, relative_time, source, speaker_id, 
                 text, confidence, prev_segment_id, next_segment_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(segment.id),
                    str(segment.session_id),
                    segment.timestamp.isoformat(),
                    segment.relative_time,
                    segment.source.value,
                    segment.speaker_id,
                    segment.text,
                    segment.confidence,
                    str(segment.prev_segment_id) if segment.prev_segment_id else None,
                    str(segment.next_segment_id) if segment.next_segment_id else None
                )
            )
            await conn.commit()
            return segment
    
    async def save_segments(self, segments: List[TranscriptSegment]) -> List[TranscriptSegment]:
        """Save multiple segments (batch insert)."""
        async with self._get_connection() as conn:
            data = [
                (
                    str(s.id),
                    str(s.session_id),
                    s.timestamp.isoformat(),
                    s.relative_time,
                    s.source.value,
                    s.speaker_id,
                    s.text,
                    s.confidence,
                    str(s.prev_segment_id) if s.prev_segment_id else None,
                    str(s.next_segment_id) if s.next_segment_id else None
                )
                for s in segments
            ]
            await conn.executemany(
                """
                INSERT INTO transcript_segments 
                (id, session_id, timestamp, relative_time, source, speaker_id, 
                 text, confidence, prev_segment_id, next_segment_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                data
            )
            await conn.commit()
            return segments
    
    async def get_segment(self, segment_id: UUID) -> Optional[TranscriptSegment]:
        """Get a segment by ID."""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "SELECT * FROM transcript_segments WHERE id = ?",
                (str(segment_id),)
            )
            row = await cursor.fetchone()
            if row:
                return self._row_to_segment(row)
            return None
    
    async def get_segments_by_session(
        self,
        session_id: UUID,
        limit: int = 1000,
        offset: int = 0
    ) -> List[TranscriptSegment]:
        """Get all segments for a session, ordered by timestamp."""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                """
                SELECT * FROM transcript_segments 
                WHERE session_id = ?
                ORDER BY timestamp ASC
                LIMIT ? OFFSET ?
                """,
                (str(session_id), limit, offset)
            )
            rows = await cursor.fetchall()
            return [self._row_to_segment(row) for row in rows]
    
    async def get_segment_context(
        self,
        segment_id: UUID,
        context_size: int = 3
    ) -> tuple[List[TranscriptSegment], TranscriptSegment, List[TranscriptSegment]]:
        """Get a segment with surrounding context."""
        segment = await self.get_segment(segment_id)
        if not segment:
            return [], None, []
        
        # Get context by temporal proximity
        async with self._get_connection() as conn:
            # Before
            cursor = await conn.execute(
                """
                SELECT * FROM transcript_segments 
                WHERE session_id = ? AND timestamp < ?
                ORDER BY timestamp DESC
                LIMIT ?
                """,
                (str(segment.session_id), segment.timestamp.isoformat(), context_size)
            )
            before_rows = await cursor.fetchall()
            before = [self._row_to_segment(row) for row in reversed(before_rows)]
            
            # After
            cursor = await conn.execute(
                """
                SELECT * FROM transcript_segments 
                WHERE session_id = ? AND timestamp > ?
                ORDER BY timestamp ASC
                LIMIT ?
                """,
                (str(segment.session_id), segment.timestamp.isoformat(), context_size)
            )
            after_rows = await cursor.fetchall()
            after = [self._row_to_segment(row) for row in after_rows]
            
            return before, segment, after
    
    # Search operations
    
    async def search(
        self,
        query: str,
        filters: Optional[SearchFilters] = None,
        limit: int = 20,
        offset: int = 0
    ) -> List[SearchResult]:
        """Full-text search with filters using FTS5."""
        filters = filters or SearchFilters()
        
        async with self._get_connection() as conn:
            # Build query with FTS5 and filters
            sql = """
                SELECT ts.*, s.*, rank
                FROM transcript_fts fts
                JOIN transcript_segments ts ON fts.rowid = ts.rowid
                JOIN sessions s ON ts.session_id = s.id
                WHERE transcript_fts MATCH ?
            """
            params = [query]
            
            # Add filters
            if filters.time_range_start:
                sql += " AND ts.timestamp >= ?"
                params.append(filters.time_range_start.isoformat())
            if filters.time_range_end:
                sql += " AND ts.timestamp <= ?"
                params.append(filters.time_range_end.isoformat())
            if filters.source_filter:
                sources = [s.value for s in filters.source_filter]
                sql += f" AND ts.source IN ({','.join('?' * len(sources))})"
                params.extend(sources)
            if filters.speaker_filter:
                sql += f" AND ts.speaker_id IN ({','.join('?' * len(filters.speaker_filter))})"
                params.extend(filters.speaker_filter)
            if filters.session_ids:
                sql += f" AND ts.session_id IN ({','.join('?' * len(filters.session_ids))})"
                params.extend([str(sid) for sid in filters.session_ids])
            if filters.min_confidence > 0:
                sql += " AND ts.confidence >= ?"
                params.append(filters.min_confidence)
            
            sql += " ORDER BY rank LIMIT ? OFFSET ?"
            params.extend([limit, offset])
            
            cursor = await conn.execute(sql, params)
            rows = await cursor.fetchall()
            
            results = []
            for row in rows:
                segment = self._row_to_segment(row)
                session = self._row_to_session(row, prefix="s.")
                
                # Get context
                before, _, after = await self.get_segment_context(segment.id, context_size=2)
                
                results.append(SearchResult(
                    segment=segment,
                    session=session,
                    relevance_score=1.0 / (row["rank"] + 1),  # Simple scoring
                    context_before=before,
                    context_after=after
                ))
            
            return results
    
    async def semantic_search(
        self,
        query_embedding: List[float],
        filters: Optional[SearchFilters] = None,
        limit: int = 20
    ) -> List[SearchResult]:
        """Vector similarity search (not implemented in SQLite without extension)."""
        # SQLite doesn't support vector search natively
        # This would require an extension or fallback to keyword search
        raise NotImplementedError(
            "Semantic search requires PostgreSQL with pgvector or a vector database. "
            "Use keyword search with SQLite."
        )
    
    # Statistics and maintenance
    
    async def get_stats(self) -> dict:
        """Get storage statistics."""
        async with self._get_connection() as conn:
            # Session count
            cursor = await conn.execute("SELECT COUNT(*) FROM sessions")
            session_count = (await cursor.fetchone())[0]
            
            # Segment count
            cursor = await conn.execute("SELECT COUNT(*) FROM transcript_segments")
            segment_count = (await cursor.fetchone())[0]
            
            # Database file size
            db_size = self.db_path.stat().st_size if self.db_path.exists() else 0
            
            # Time range
            cursor = await conn.execute(
                "SELECT MIN(started_at), MAX(started_at) FROM sessions"
            )
            row = await cursor.fetchone()
            
            return {
                "backend": "sqlite",
                "db_path": str(self.db_path),
                "db_size_bytes": db_size,
                "session_count": session_count,
                "segment_count": segment_count,
                "oldest_session": row[0],
                "newest_session": row[1]
            }
    
    async def compact(self) -> None:
        """Compact/optimize the database."""
        async with self._get_connection() as conn:
            await conn.execute("VACUUM")
            await conn.execute("ANALYZE")
            await conn.commit()
    
    async def delete_old_sessions(self, days: int = 90) -> int:
        """Delete sessions older than N days (except pinned)."""
        cutoff = datetime.utcnow().timestamp() - (days * 24 * 60 * 60)
        cutoff_iso = datetime.fromtimestamp(cutoff).isoformat()
        
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                """
                DELETE FROM sessions 
                WHERE started_at < ? AND is_pinned = 0
                """,
                (cutoff_iso,)
            )
            await conn.commit()
            return cursor.rowcount
    
    async def health_check(self) -> bool:
        """Check if storage is healthy."""
        try:
            async with self._get_connection() as conn:
                await conn.execute("SELECT 1")
                return True
        except Exception:
            return False
    
    # Helper methods
    
    def _row_to_session(self, row: sqlite3.Row, prefix: str = "") -> Session:
        """Convert a database row to a Session object."""
        def get(col: str):
            return row[f"{prefix}{col}"] if prefix else row[col]
        
        return Session(
            id=UUID(get("id")),
            started_at=datetime.fromisoformat(get("started_at")),
            ended_at=datetime.fromisoformat(get("ended_at")) if get("ended_at") else None,
            title=get("title"),
            source_app=get("source_app"),
            tags=json.loads(get("tags")) if get("tags") else [],
            is_pinned=bool(get("is_pinned")),
            audio_file_path=get("audio_path"),
            last_modified=datetime.fromisoformat(get("last_modified")),
            sync_status=SyncStatus(get("sync_status")),
            metadata=json.loads(get("metadata")) if get("metadata") else {}
        )
    
    def _row_to_segment(self, row: sqlite3.Row) -> TranscriptSegment:
        """Convert a database row to a TranscriptSegment object."""
        return TranscriptSegment(
            id=UUID(row["id"]),
            session_id=UUID(row["session_id"]),
            timestamp=datetime.fromisoformat(row["timestamp"]),
            relative_time=row["relative_time"] or 0.0,
            source=AudioSource(row["source"]) if row["source"] else AudioSource.SYSTEM,
            speaker_id=row["speaker_id"],
            text=row["text"],
            confidence=row["confidence"] or 1.0,
            prev_segment_id=UUID(row["prev_segment_id"]) if row["prev_segment_id"] else None,
            next_segment_id=UUID(row["next_segment_id"]) if row["next_segment_id"] else None
        )
