"""Background indexing service for Brain Dump.

This service subscribes to transcript events and stores them in the
configured storage backend (SQLite by default).
"""

import asyncio
import logging
from datetime import datetime
from typing import Callable, Optional
from uuid import UUID, uuid4

from server.db import (
    get_storage_adapter,
    StorageAdapter,
    StorageConfig,
    Session,
    TranscriptSegment,
    AudioSource
)
from server.db.vector_store import VectorStore
from server.services.embeddings import EmbeddingService

logger = logging.getLogger(__name__)


class BrainDumpIndexer:
    """Background service that indexes transcripts to storage.
    
    Usage:
        indexer = BrainDumpIndexer(storage_config)
        await indexer.start()
        
        # From WebSocket handler
        await indexer.on_transcript(session_id, text, source, timestamp)
        
        await indexer.stop()
    """
    
    def __init__(
        self,
        storage_config: Optional[StorageConfig] = None,
        buffer_size: int = 10,
        flush_interval: float = 5.0,
        enable_embeddings: bool = True
    ):
        """Initialize the indexer.
        
        Args:
            storage_config: Storage configuration (defaults to SQLite)
            buffer_size: Number of segments to buffer before flushing
            flush_interval: Seconds between automatic flushes
            enable_embeddings: Whether to generate embeddings for semantic search
        """
        self.config = storage_config or StorageConfig(backend="sqlite")
        self.adapter: Optional[StorageAdapter] = None
        self.buffer_size = buffer_size
        self.flush_interval = flush_interval
        self.enable_embeddings = enable_embeddings
        
        # Vector store for semantic search
        self.vector_store: Optional[VectorStore] = None
        self.embedding_service: Optional[EmbeddingService] = None
        
        # Buffer for batching writes
        self._buffer: list[TranscriptSegment] = []
        self._buffer_lock = asyncio.Lock()
        
        # Buffer for embeddings
        self._embedding_buffer: list[tuple[TranscriptSegment, list[float]]] = []
        
        # Track active sessions
        self._active_sessions: dict[UUID, Session] = {}
        
        # Background tasks
        self._flush_task: Optional[asyncio.Task] = None
        self._running = False
    
    async def start(self) -> None:
        """Initialize storage and start background tasks."""
        logger.info("Starting Brain Dump indexer...")
        
        # Initialize storage adapter
        self.adapter = get_storage_adapter(self.config)
        await self.adapter.initialize()
        
        # Initialize vector store for semantic search
        if self.enable_embeddings:
            try:
                self.vector_store = VectorStore()
                await self.vector_store.initialize()
                
                self.embedding_service = EmbeddingService()
                if self.embedding_service.is_available():
                    logger.info("Embedding service initialized")
                else:
                    logger.warning("sentence-transformers not installed, embeddings disabled")
                    self.embedding_service = None
            except Exception as e:
                logger.warning(f"Failed to initialize vector store: {e}")
                self.vector_store = None
                self.embedding_service = None
        
        # Start background flush task
        self._running = True
        self._flush_task = asyncio.create_task(self._flush_loop())
        
        logger.info("Brain Dump indexer started")
    
    async def stop(self) -> None:
        """Stop background tasks and flush remaining buffer."""
        logger.info("Stopping Brain Dump indexer...")
        
        self._running = False
        
        # Cancel flush task
        if self._flush_task:
            self._flush_task.cancel()
            try:
                await self._flush_task
            except asyncio.CancelledError:
                pass
        
        # Final flush
        await self._flush_buffer()
        
        # Close storage
        if self.adapter:
            await self.adapter.close()
        
        # Close vector store
        if self.vector_store:
            await self.vector_store.close()
        
        logger.info("Brain Dump indexer stopped")
    
    async def start_session(
        self,
        session_id: Optional[UUID] = None,
        title: Optional[str] = None,
        source_app: Optional[str] = None,
        audio_path: Optional[str] = None
    ) -> UUID:
        """Start a new recording session.
        
        Args:
            session_id: Optional session ID (generated if not provided)
            title: Session title
            source_app: Source application (e.g., "zoom", "chrome")
            audio_path: Path to audio recording file
            
        Returns:
            Session ID
        """
        if not self.adapter:
            raise RuntimeError("Indexer not started. Call start() first.")
        
        session_id = session_id or uuid4()
        
        session = Session(
            id=session_id,
            title=title,
            source_app=source_app,
            audio_file_path=audio_path,
            started_at=datetime.utcnow()
        )
        
        await self.adapter.create_session(session)
        self._active_sessions[session_id] = session
        
        logger.info(f"Started session {session_id}: {title or 'Untitled'}")
        return session_id
    
    async def end_session(self, session_id: UUID) -> None:
        """End a recording session.
        
        Args:
            session_id: Session ID to end
        """
        if not self.adapter:
            raise RuntimeError("Indexer not started.")
        
        # Flush any remaining segments for this session
        await self._flush_buffer(session_id=session_id)
        
        # End session in storage
        session = await self.adapter.end_session(session_id)
        if session:
            self._active_sessions.pop(session_id, None)
            logger.info(f"Ended session {session_id}")
        else:
            logger.warning(f"Session {session_id} not found")
    
    async def on_transcript(
        self,
        session_id: UUID,
        text: str,
        source: AudioSource = AudioSource.SYSTEM,
        timestamp: Optional[datetime] = None,
        speaker_id: Optional[str] = None,
        confidence: float = 1.0,
        relative_time: float = 0.0
    ) -> None:
        """Process a transcript segment.
        
        Args:
            session_id: Session ID
            text: Transcribed text
            source: Audio source type
            timestamp: Absolute timestamp (defaults to now)
            speaker_id: Speaker identifier
            confidence: ASR confidence score
            relative_time: Seconds from session start
        """
        if not self.adapter:
            raise RuntimeError("Indexer not started.")
        
        segment = TranscriptSegment(
            id=uuid4(),
            session_id=session_id,
            timestamp=timestamp or datetime.utcnow(),
            relative_time=relative_time,
            source=source,
            speaker_id=speaker_id,
            text=text,
            confidence=confidence
        )
        
        async with self._buffer_lock:
            self._buffer.append(segment)
            
            # Flush if buffer is full
            if len(self._buffer) >= self.buffer_size:
                asyncio.create_task(self._flush_buffer())
    
    async def on_voice_note(
        self,
        text: str,
        title: Optional[str] = None
    ) -> UUID:
        """Process a voice note as a separate session.
        
        Args:
            text: Transcribed voice note text
            title: Optional title for the note
            
        Returns:
            Session ID of the created voice note session
        """
        # Create a new session for the voice note
        session_id = await self.start_session(
            title=title or "Voice Note",
            source_app="voice_note"
        )
        
        # Add the transcript as a segment
        await self.on_transcript(
            session_id=session_id,
            text=text,
            source=AudioSource.VOICE_NOTE
        )
        
        # End the session immediately
        await self.end_session(session_id)
        
        return session_id
    
    async def update_session_title(self, session_id: UUID, title: str) -> None:
        """Update the title of a session.
        
        Args:
            session_id: Session ID
            title: New title
        """
        if not self.adapter:
            raise RuntimeError("Indexer not started.")
        
        session = await self.adapter.get_session(session_id)
        if session:
            session.title = title
            await self.adapter.update_session(session)
            logger.info(f"Updated session {session_id} title: {title}")
        else:
            logger.warning(f"Session {session_id} not found for title update")
    
    async def pin_session(self, session_id: UUID, pinned: bool = True) -> None:
        """Pin or unpin a session.
        
        Args:
            session_id: Session ID
            pinned: True to pin, False to unpin
        """
        if not self.adapter:
            raise RuntimeError("Indexer not started.")
        
        session = await self.adapter.get_session(session_id)
        if session:
            session.is_pinned = pinned
            await self.adapter.update_session(session)
            logger.info(f"{'Pinned' if pinned else 'Unpinned'} session {session_id}")
        else:
            logger.warning(f"Session {session_id} not found")
    
    async def _flush_loop(self) -> None:
        """Background task to periodically flush the buffer."""
        while self._running:
            try:
                await asyncio.sleep(self.flush_interval)
                await self._flush_buffer()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in flush loop: {e}")
    
    async def _flush_buffer(self, session_id: Optional[UUID] = None) -> None:
        """Flush buffered segments to storage.
        
        Args:
            session_id: If provided, only flush segments for this session
        """
        if not self.adapter:
            return
        
        async with self._buffer_lock:
            if not self._buffer:
                return
            
            # Filter by session if specified
            if session_id:
                segments = [s for s in self._buffer if s.session_id == session_id]
                self._buffer = [s for s in self._buffer if s.session_id != session_id]
            else:
                segments = self._buffer
                self._buffer = []
        
        if not segments:
            return
        
        try:
            # Save to SQLite
            await self.adapter.save_segments(segments)
            logger.debug(f"Flushed {len(segments)} segments to storage")
            
            # Generate and save embeddings if enabled
            if self.vector_store and self.embedding_service:
                try:
                    texts = [s.text for s in segments]
                    embeddings = self.embedding_service.encode(texts)
                    await self.vector_store.add_segments(segments, embeddings)
                    logger.debug(f"Generated embeddings for {len(segments)} segments")
                except Exception as e:
                    logger.warning(f"Failed to generate embeddings: {e}")
                    
        except Exception as e:
            logger.error(f"Failed to flush segments: {e}")
            # Put segments back in buffer for retry
            async with self._buffer_lock:
                self._buffer.extend(segments)
    
    async def get_stats(self) -> dict:
        """Get indexing statistics."""
        if not self.adapter:
            return {"status": "not_started"}
        
        stats = await self.adapter.get_stats()
        stats["buffer_size"] = len(self._buffer)
        stats["active_sessions"] = len(self._active_sessions)
        return stats


# Singleton instance for global access
_indexer_instance: Optional[BrainDumpIndexer] = None


def get_indexer() -> Optional[BrainDumpIndexer]:
    """Get the global indexer instance."""
    return _indexer_instance


async def initialize_indexer(config: Optional[StorageConfig] = None) -> BrainDumpIndexer:
    """Initialize the global indexer instance.
    
    Args:
        config: Storage configuration (defaults to SQLite)
        
    Returns:
        BrainDumpIndexer instance
    """
    global _indexer_instance
    _indexer_instance = BrainDumpIndexer(config)
    await _indexer_instance.start()
    return _indexer_instance


async def shutdown_indexer() -> None:
    """Shutdown the global indexer instance."""
    global _indexer_instance
    if _indexer_instance:
        await _indexer_instance.stop()
        _indexer_instance = None
