"""Integration layer between WebSocket pipeline and Brain Dump storage.

This module provides hooks to store transcripts from the WebSocket
handler into the Brain Dump database.
"""

import asyncio
import logging
from datetime import datetime
from typing import Optional
from uuid import UUID

from server.services.brain_dump_indexer import get_indexer, BrainDumpIndexer
from server.db import AudioSource

logger = logging.getLogger(__name__)


class BrainDumpWebSocketIntegration:
    """Integrates Brain Dump indexing with WebSocket sessions.
    
    Usage:
        # In WebSocket handler when session starts:
        integration = BrainDumpWebSocketIntegration()
        session_id = await integration.start_session(
            title="Meeting with Sarah",
            source_app="zoom"
        )
        
        # When transcript segments arrive:
        await integration.on_transcript(
            session_id=session_id,
            text="Let's discuss the roadmap",
            source=AudioSource.SYSTEM,
            speaker_id="speaker_1",
            t0=10.0,  # Seconds from start
            t1=15.0
        )
        
        # When session ends:
        await integration.end_session(session_id)
    """
    
    def __init__(self, indexer: Optional[BrainDumpIndexer] = None):
        """Initialize integration.
        
        Args:
            indexer: BrainDumpIndexer instance (uses global if not provided)
        """
        self.indexer = indexer or get_indexer()
        self._session_ids: dict[str, UUID] = {}  # connection_id -> session_id
    
    async def start_session(
        self,
        connection_id: str,
        title: Optional[str] = None,
        source_app: Optional[str] = None,
        audio_path: Optional[str] = None
    ) -> Optional[UUID]:
        """Start a new brain dump session for a WebSocket connection.
        
        Args:
            connection_id: WebSocket connection identifier
            title: Session title
            source_app: Source app (zoom, chrome, etc.)
            audio_path: Path to recorded audio file
            
        Returns:
            Session ID if indexer is available, None otherwise
        """
        if not self.indexer:
            logger.debug("Brain dump indexer not available, skipping session start")
            return None
        
        try:
            session_id = await self.indexer.start_session(
                title=title,
                source_app=source_app,
                audio_path=audio_path
            )
            self._session_ids[connection_id] = session_id
            logger.info(f"Started brain dump session {session_id} for connection {connection_id}")
            return session_id
        except Exception as e:
            logger.error(f"Failed to start brain dump session: {e}")
            return None
    
    async def on_transcript(
        self,
        connection_id: str,
        text: str,
        source: str = "system",
        speaker_id: Optional[str] = None,
        t0: float = 0.0,
        t1: float = 0.0,
        confidence: float = 1.0
    ) -> None:
        """Process a transcript segment from WebSocket.
        
        Args:
            connection_id: WebSocket connection identifier
            text: Transcribed text
            source: Audio source ("system", "microphone", "voice_note")
            speaker_id: Speaker identifier
            t0: Start time in seconds from session start
            t1: End time in seconds from session start
            confidence: ASR confidence score
        """
        if not self.indexer:
            return
        
        session_id = self._session_ids.get(connection_id)
        if not session_id:
            logger.debug(f"No brain dump session for connection {connection_id}")
            return
        
        try:
            # Map source string to AudioSource enum
            source_enum = AudioSource.SYSTEM
            if source == "microphone":
                source_enum = AudioSource.MICROPHONE
            elif source == "voice_note":
                source_enum = AudioSource.VOICE_NOTE
            
            await self.indexer.on_transcript(
                session_id=session_id,
                text=text,
                source=source_enum,
                speaker_id=speaker_id,
                relative_time=t0,
                confidence=confidence
            )
        except Exception as e:
            logger.error(f"Failed to index transcript: {e}")
    
    async def end_session(self, connection_id: str) -> None:
        """End a brain dump session.
        
        Args:
            connection_id: WebSocket connection identifier
        """
        if not self.indexer:
            return
        
        session_id = self._session_ids.pop(connection_id, None)
        if not session_id:
            return
        
        try:
            await self.indexer.end_session(session_id)
            logger.info(f"Ended brain dump session {session_id} for connection {connection_id}")
        except Exception as e:
            logger.error(f"Failed to end brain dump session: {e}")
    
    async def update_session_title(
        self,
        connection_id: str,
        title: str
    ) -> None:
        """Update the title of a session.
        
        Args:
            connection_id: WebSocket connection identifier
            title: New title
        """
        if not self.indexer:
            return
        
        session_id = self._session_ids.get(connection_id)
        if not session_id:
            return
        
        try:
            await self.indexer.update_session_title(session_id, title)
        except Exception as e:
            logger.error(f"Failed to update session title: {e}")
    
    async def pin_session(self, connection_id: str) -> None:
        """Pin a session to prevent auto-deletion.
        
        Args:
            connection_id: WebSocket connection identifier
        """
        if not self.indexer:
            return
        
        session_id = self._session_ids.get(connection_id)
        if not session_id:
            return
        
        try:
            await self.indexer.pin_session(session_id)
        except Exception as e:
            logger.error(f"Failed to pin session: {e}")
    
    def get_session_id(self, connection_id: str) -> Optional[UUID]:
        """Get the brain dump session ID for a connection.
        
        Args:
            connection_id: WebSocket connection identifier
            
        Returns:
            Session ID if exists, None otherwise
        """
        return self._session_ids.get(connection_id)


# Global integration instance
_integration_instance: Optional[BrainDumpWebSocketIntegration] = None


def get_integration() -> Optional[BrainDumpWebSocketIntegration]:
    """Get the global integration instance."""
    return _integration_instance


def initialize_integration(indexer: Optional[BrainDumpIndexer] = None) -> BrainDumpWebSocketIntegration:
    """Initialize the global integration instance.
    
    Args:
        indexer: BrainDumpIndexer instance (uses global if not provided)
        
    Returns:
        BrainDumpWebSocketIntegration instance
    """
    global _integration_instance
    _integration_instance = BrainDumpWebSocketIntegration(indexer)
    return _integration_instance


async def shutdown_integration() -> None:
    """Shutdown the global integration instance and indexer."""
    from server.services.brain_dump_indexer import shutdown_indexer
    
    global _integration_instance
    
    # Shutdown indexer first (stops background flush task)
    await shutdown_indexer()
    
    # Then clear integration instance
    _integration_instance = None


# Convenience function for WebSocket handler

async def index_transcript_event(
    connection_id: str,
    event: dict,
    source: str = "system"
) -> None:
    """Convenience function to index a transcript event from WebSocket.
    
    Args:
        connection_id: WebSocket connection identifier
        event: Transcript event dict with 'text', 't0', 't1', etc.
        source: Audio source
    """
    integration = get_integration()
    if not integration:
        return
    
    if event.get("type") != "asr_final":
        return
    
    await integration.on_transcript(
        connection_id=connection_id,
        text=event.get("text", ""),
        source=source,
        speaker_id=event.get("speaker"),
        t0=event.get("t0", 0.0),
        t1=event.get("t1", 0.0),
        confidence=event.get("confidence", 1.0)
    )
