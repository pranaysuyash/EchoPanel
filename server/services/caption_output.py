"""
Real-time caption output service for broadcast integration.

Converts ASR segments to standard subtitle formats (SRT, WebVTT) and streams
to multiple destinations: WebSocket, file, or UDP.

Usage:
    caption_output = CaptionOutputService()
    caption_output.add_websocket_handler(ws_connection)
    caption_output.add_file_output("/path/to/captions.srt")
    caption_output.add_udp_output("192.168.1.100", 5004)
    
    async for segment in asr_segments:
        await caption_output.on_asr_segment(segment)
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum, auto
from pathlib import Path
from typing import Callable, Dict, List, Optional, Protocol, Set
import struct

logger = logging.getLogger(__name__)


class CaptionFormat(Enum):
    """Supported caption output formats."""
    SRT = "srt"
    WEBVTT = "vtt"


@dataclass
class TranscriptSegment:
    """ASR transcript segment."""
    text: str
    t0: float  # Start time in seconds from session start
    t1: float  # End time in seconds from session start
    confidence: float = 1.0
    is_final: bool = True
    speaker: Optional[str] = None


@dataclass
class CaptionCue:
    """A single caption cue/entry."""
    index: int
    start_time: timedelta
    end_time: timedelta
    text: str
    
    def to_srt(self) -> str:
        """Format as SRT entry."""
        return f"{self.index}\n{self._format_srt_time(self.start_time)} --> {self._format_srt_time(self.end_time)}\n{self.text}\n\n"
    
    def to_webvtt(self) -> str:
        """Format as WebVTT cue."""
        return f"{self._format_vtt_time(self.start_time)} --> {self._format_vtt_time(self.end_time)}\n{self.text}\n\n"
    
    @staticmethod
    def _format_srt_time(td: timedelta) -> str:
        """Format timedelta as SRT time (HH:MM:SS,mmm)."""
        hours, remainder = divmod(int(td.total_seconds()), 3600)
        minutes, seconds = divmod(remainder, 60)
        milliseconds = int((td.total_seconds() - int(td.total_seconds())) * 1000)
        return f"{hours:02d}:{minutes:02d}:{seconds:02d},{milliseconds:03d}"
    
    @staticmethod
    def _format_vtt_time(td: timedelta) -> str:
        """Format timedelta as WebVTT time (HH:MM:SS.mmm)."""
        hours, remainder = divmod(int(td.total_seconds()), 3600)
        minutes, seconds = divmod(remainder, 60)
        milliseconds = int((td.total_seconds() - int(td.total_seconds())) * 1000)
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{milliseconds:03d}"


class WebSocketHandler(Protocol):
    """Protocol for WebSocket connection handlers."""
    
    async def send_text(self, message: str) -> None:
        ...


@dataclass
class CaptionOutputConfig:
    """Configuration for caption output service."""
    format: CaptionFormat = CaptionFormat.SRT
    encoding: str = "utf-8"
    add_bom: bool = False  # Add UTF-8 BOM for Windows compatibility
    min_segment_duration: float = 1.0  # Minimum segment duration in seconds
    max_segment_duration: float = 7.0  # Maximum segment duration (broadcast standard)
    max_chars_per_line: int = 32  # Maximum characters per line (broadcast safe)
    max_lines: int = 2  # Maximum lines per caption
    

class CaptionOutputService:
    """
    Real-time caption output service for broadcast integration.
    
    Supports multiple simultaneous outputs:
    - WebSocket: For browser-based CGs and streaming platforms
    - File: For recording/archiving
    - UDP: For hardware encoder integration
    """
    
    def __init__(self, config: Optional[CaptionOutputConfig] = None):
        self.config = config or CaptionOutputConfig()
        self._cue_index = 0
        self._websocket_handlers: Set[WebSocketHandler] = set()
        self._file_outputs: Dict[Path, asyncio.TextIOWrapper] = {}
        self._udp_outputs: List[tuple] = []  # [(host, port, transport)]
        self._session_start_time: Optional[datetime] = None
        self._buffer: List[CaptionCue] = []
        self._lock = asyncio.Lock()
        
    async def start_session(self, reference_time: Optional[datetime] = None) -> None:
        """Start a new caption session."""
        self._session_start_time = reference_time or datetime.utcnow()
        self._cue_index = 0
        self._buffer.clear()
        
        # Write WebVTT header if needed
        if self.config.format == CaptionFormat.WEBVTT:
            header = "WEBVTT - EchoPanel Live Captions\n\n"
            await self._broadcast_to_all(header)
        
        logger.info(f"Caption session started at {self._session_start_time}")
    
    async def end_session(self) -> None:
        """End caption session and flush remaining cues."""
        await self._flush_buffer()
        
        # Close file outputs
        for path, f in self._file_outputs.items():
            try:
                f.close()
                logger.info(f"Closed caption file: {path}")
            except Exception as e:
                logger.error(f"Error closing caption file {path}: {e}")
        self._file_outputs.clear()
        
        # Close UDP outputs
        for host, port, transport in self._udp_outputs:
            try:
                transport.close()
                logger.info(f"Closed UDP caption output: {host}:{port}")
            except Exception as e:
                logger.error(f"Error closing UDP output: {e}")
        self._udp_outputs.clear()
        
        self._websocket_handlers.clear()
        logger.info("Caption session ended")
    
    async def on_asr_segment(self, segment: TranscriptSegment) -> None:
        """Process an ASR segment and emit caption cue."""
        if not self._session_start_time:
            logger.warning("ASR segment received but session not started")
            return
        
        # Skip very short segments
        duration = segment.t1 - segment.t0
        if duration < self.config.min_segment_duration:
            logger.debug(f"Skipping short segment: {duration:.2f}s")
            return
        
        # Cap maximum duration
        if duration > self.config.max_segment_duration:
            segment.t1 = segment.t0 + self.config.max_segment_duration
        
        # Format text for broadcast (line breaking)
        text = self._format_text(segment.text)
        if not text:
            return
        
        async with self._lock:
            self._cue_index += 1
            cue = CaptionCue(
                index=self._cue_index,
                start_time=timedelta(seconds=segment.t0),
                end_time=timedelta(seconds=segment.t1),
                text=text
            )
            
            self._buffer.append(cue)
            
            # Emit immediately for low latency
            await self._emit_cue(cue)
    
    def add_websocket_handler(self, handler: WebSocketHandler) -> None:
        """Add a WebSocket connection for caption streaming."""
        self._websocket_handlers.add(handler)
        logger.debug(f"Added WebSocket handler, total: {len(self._websocket_handlers)}")
    
    def remove_websocket_handler(self, handler: WebSocketHandler) -> None:
        """Remove a WebSocket connection."""
        self._websocket_handlers.discard(handler)
        logger.debug(f"Removed WebSocket handler, total: {len(self._websocket_handlers)}")
    
    async def add_file_output(self, path: Path) -> None:
        """Add file output for caption recording."""
        try:
            # Ensure parent directory exists
            path.parent.mkdir(parents=True, exist_ok=True)
            
            # Open in append mode (create new if doesn't exist)
            mode = "a" if path.exists() else "w"
            f = open(path, mode, encoding=self.config.encoding)
            
            # Write BOM if configured and new file
            if self.config.add_bom and mode == "w":
                f.write("\ufeff")
            
            # Write WebVTT header if new file
            if self.config.format == CaptionFormat.WEBVTT and mode == "w":
                f.write("WEBVTT - EchoPanel Live Captions\n\n")
            
            self._file_outputs[path] = f
            logger.info(f"Added file output: {path}")
        except Exception as e:
            logger.error(f"Failed to add file output {path}: {e}")
            raise
    
    async def add_udp_output(self, host: str, port: int) -> None:
        """Add UDP output for hardware encoder integration."""
        try:
            loop = asyncio.get_event_loop()
            transport, _ = await loop.create_datagram_endpoint(
                lambda: CaptionUDPProtocol(),
                remote_addr=(host, port)
            )
            self._udp_outputs.append((host, port, transport))
            logger.info(f"Added UDP output: {host}:{port}")
        except Exception as e:
            logger.error(f"Failed to add UDP output {host}:{port}: {e}")
            raise
    
    def _format_text(self, text: str) -> str:
        """Format text for broadcast caption standards."""
        # Basic cleanup
        text = text.strip()
        if not text:
            return ""
        
        # Break into lines if too long
        words = text.split()
        lines: List[str] = []
        current_line = ""
        
        for word in words:
            if len(current_line) + len(word) + 1 <= self.config.max_chars_per_line:
                current_line = f"{current_line} {word}".strip()
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
                
                # Limit number of lines
                if len(lines) >= self.config.max_lines:
                    break
        
        if current_line and len(lines) < self.config.max_lines:
            lines.append(current_line)
        
        return "\n".join(lines)
    
    async def _emit_cue(self, cue: CaptionCue) -> None:
        """Emit a single caption cue to all outputs."""
        if self.config.format == CaptionFormat.SRT:
            output = cue.to_srt()
        else:
            output = cue.to_webvtt()
        
        await self._broadcast_to_all(output)
    
    async def _broadcast_to_all(self, data: str) -> None:
        """Broadcast caption data to all connected outputs."""
        # WebSocket handlers
        dead_handlers: Set[WebSocketHandler] = set()
        for handler in self._websocket_handlers:
            try:
                await handler.send_text(data)
            except Exception as e:
                logger.debug(f"WebSocket send failed: {e}")
                dead_handlers.add(handler)
        
        # Clean up dead handlers
        self._websocket_handlers -= dead_handlers
        
        # File outputs
        for path, f in list(self._file_outputs.items()):
            try:
                f.write(data)
                f.flush()
            except Exception as e:
                logger.error(f"File write failed for {path}: {e}")
        
        # UDP outputs
        for host, port, transport in self._udp_outputs:
            try:
                # Send as UTF-8 encoded bytes, truncate to safe UDP size
                bytes_data = data.encode(self.config.encoding)[:1400]
                transport.sendto(bytes_data)
            except Exception as e:
                logger.error(f"UDP send failed to {host}:{port}: {e}")
    
    async def _flush_buffer(self) -> None:
        """Flush any buffered cues."""
        async with self._lock:
            for cue in self._buffer:
                await self._emit_cue(cue)
            self._buffer.clear()
    
    def get_stats(self) -> Dict[str, int]:
        """Get caption output statistics."""
        return {
            "cues_emitted": self._cue_index,
            "websocket_handlers": len(self._websocket_handlers),
            "file_outputs": len(self._file_outputs),
            "udp_outputs": len(self._udp_outputs),
            "buffered_cues": len(self._buffer),
        }


class CaptionUDPProtocol(asyncio.DatagramProtocol):
    """UDP protocol handler for caption output."""
    
    def __init__(self):
        self.transport: Optional[asyncio.DatagramTransport] = None
    
    def connection_made(self, transport: asyncio.DatagramTransport) -> None:
        self.transport = transport
    
    def error_received(self, exc: Exception) -> None:
        logger.error(f"UDP error: {exc}")
    
    def connection_lost(self, exc: Optional[Exception]) -> None:
        logger.debug("UDP connection closed")


# Convenience functions for quick setup

async def create_srt_stream(path: Path) -> CaptionOutputService:
    """Create an SRT file output stream."""
    service = CaptionOutputService(CaptionOutputConfig(format=CaptionFormat.SRT))
    await service.add_file_output(path)
    return service


async def create_vtt_stream(path: Path) -> CaptionOutputService:
    """Create a WebVTT file output stream."""
    service = CaptionOutputService(CaptionOutputConfig(format=CaptionFormat.WEBVTT))
    await service.add_file_output(path)
    return service


# WebSocket message format helpers

def create_caption_ws_message(cue: CaptionCue, format: CaptionFormat) -> dict:
    """Create a WebSocket message dict for caption streaming."""
    return {
        "type": "caption",
        "format": format.value,
        "index": cue.index,
        "start": CaptionCue._format_vtt_time(cue.start_time),
        "end": CaptionCue._format_vtt_time(cue.end_time),
        "text": cue.text,
    }
