"""
Video Understanding Integration for EchoPanel

Integrates VLM-based video understanding with session recording pipeline.
Analyzes screen capture frames to provide visual context for meetings.

Key features:
- Async frame collection from OCR pipeline
- VideoUnderstandingPipeline for analysis
- Session-level visual context storage
- REST API for video narration
"""

import asyncio
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from .ocr_smolvlm import (
    VideoUnderstandingPipeline,
    VideoAnalysisResult,
    VLM_FRAME_INTERVAL,
    VLM_MAX_FRAMES,
    VLM_FRAME_SAMPLING,
)

logger = logging.getLogger(__name__)

VLM_VIDEO_ENABLED = os.getenv("ECHOPANEL_VLM_VIDEO_ENABLED", "false").lower() == "true"
VLM_VIDEO_ASYNC = os.getenv("ECHOPANEL_VLM_VIDEO_ASYNC", "true").lower() == "true"


@dataclass
class SessionVisualContext:
    """Visual context for a recording session."""
    session_id: str
    frame_summaries: List[str] = field(default_factory=list)
    overall_summary: str = ""
    key_scenes: List[str] = field(default_factory=list)
    narrative: str = ""
    analyzed_frames: int = 0
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)


class VideoUnderstandingIntegration:
    """Integrates video understanding with session recording pipeline."""
    
    def __init__(self):
        self.pipeline = VideoUnderstandingPipeline()
        self._session_contexts: Dict[str, SessionVisualContext] = {}
        self._pending_frames: Dict[str, List] = {}
        self._lock = asyncio.Lock()
        self._initialized = False
    
    def is_available(self) -> bool:
        return VLM_VIDEO_ENABLED and self.pipeline.is_available()
    
    async def initialize(self):
        """Initialize the integration."""
        if self._initialized:
            return
        
        if not self.is_available():
            logger.warning("Video understanding not enabled or VLM not available")
            return
        
        self._initialized = True
        logger.info("VideoUnderstandingIntegration initialized")
    
    async def start_session(self, session_id: str):
        """Start tracking visual context for a session."""
        async with self._lock:
            self._pending_frames[session_id] = []
            self._session_contexts[session_id] = SessionVisualContext(session_id=session_id)
            logger.debug(f"Started video context tracking for session {session_id}")
    
    async def add_frame(self, session_id: str, frame_data: bytes, timestamp_ms: int):
        """Add a frame for later analysis (non-blocking)."""
        if not self.is_available():
            return
        
        async with self._lock:
            if session_id not in self._pending_frames:
                self._pending_frames[session_id] = []
            
            self._pending_frames[session_id].append({
                "data": frame_data,
                "timestamp_ms": timestamp_ms,
            })
            
            logger.debug(f"Added frame to session {session_id}, total pending: {len(self._pending_frames[session_id])}")
    
    async def analyze_session(self, session_id: str) -> Optional[SessionVisualContext]:
        """Analyze all pending frames for a session."""
        if not self.is_available():
            return None
        
        async with self._lock:
            frames = self._pending_frames.get(session_id, [])
            if not frames:
                logger.debug(f"No frames to analyze for session {session_id}")
                return None
            
            context = self._session_contexts.get(session_id)
            if not context:
                context = SessionVisualContext(session_id=session_id)
        
        if not frames:
            return None
        
        try:
            from PIL import Image
            import io
            
            async def frame_extractor(timestamp_ms: int) -> Image.Image:
                for frame in frames:
                    if frame["timestamp_ms"] == timestamp_ms:
                        return Image.open(io.BytesIO(frame["data"]))
                return Image.open(io.BytesIO(frames[0]["data"]))
            
            duration_ms = frames[-1]["timestamp_ms"] - frames[0]["timestamp_ms"]
            duration_seconds = duration_ms / 1000.0
            
            result = await self.pipeline.analyze_video(duration_seconds, frame_extractor)
            
            if result.success:
                async with self._lock:
                    context.frame_summaries = result.frame_summaries
                    context.overall_summary = result.overall_summary
                    context.key_scenes = result.key_scenes
                    context.narrative = result.to_narrative()
                    context.analyzed_frames = result.frames_analyzed
                    context.updated_at = datetime.utcnow()
                    
                    self._session_contexts[session_id] = context
                
                logger.info(f"Analyzed {result.frames_analyzed} frames for session {session_id}")
                return context
            
        except Exception as e:
            logger.error(f"Failed to analyze session {session_id}: {e}")
        
        return None
    
    async def get_session_context(self, session_id: str) -> Optional[SessionVisualContext]:
        """Get visual context for a session."""
        async with self._lock:
            return self._session_contexts.get(session_id)
    
    async def end_session(self, session_id: str, analyze: bool = True) -> Optional[SessionVisualContext]:
        """End session and optionally analyze pending frames."""
        if analyze:
            return await self.analyze_session(session_id)
        
        async with self._lock:
            self._pending_frames.pop(session_id, None)
            return self._session_contexts.get(session_id)
    
    def get_stats(self) -> dict:
        """Get pipeline statistics."""
        stats = {
            "vlm_available": self.is_available(),
            "active_sessions": len(self._session_contexts),
            "pending_frames": sum(len(f) for f in self._pending_frames.values()),
        }
        if self.is_available():
            stats.update(self.pipeline.get_stats())
        return stats


_integration: Optional[VideoUnderstandingIntegration] = None


def get_video_understanding_integration() -> VideoUnderstandingIntegration:
    """Get the singleton video understanding integration."""
    global _integration
    if _integration is None:
        _integration = VideoUnderstandingIntegration()
    return _integration
