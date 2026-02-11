"""
Caption output extension for WebSocket live listener.

Integrates real-time caption streaming into the WebSocket handler.
Supports SRT and WebVTT formats for broadcast integration.

Usage:
    from server.api.ws_caption_extension import CaptionWebSocketExtension
    
    # In ws_live_listener:
    caption_ext = CaptionWebSocketExtension(websocket, state)
    await caption_ext.start_session()
    
    # On ASR segment:
    await caption_ext.on_asr_segment(segment)
    
    # Cleanup:
    await caption_ext.end_session()
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Optional, Set

from fastapi import WebSocket

from server.services.caption_output import (
    CaptionFormat,
    CaptionOutputConfig,
    CaptionOutputService,
    TranscriptSegment,
    create_caption_ws_message,
)

logger = logging.getLogger(__name__)


class WebSocketCaptionHandler:
    """Adapter to make WebSocket act like a caption output handler."""
    
    def __init__(self, websocket: WebSocket, format: CaptionFormat = CaptionFormat.SRT):
        self.websocket = websocket
        self.format = format
        self._closed = False
    
    async def send_text(self, message: str) -> None:
        """Send caption data as WebSocket message."""
        if self._closed:
            return
        
        try:
            # Wrap in caption message envelope
            envelope = {
                "type": "caption",
                "format": self.format.value,
                "data": message,
            }
            await self.websocket.send_text(json.dumps(envelope))
        except Exception as e:
            logger.debug(f"Failed to send caption via WebSocket: {e}")
            self._closed = True
    
    def close(self) -> None:
        """Mark handler as closed."""
        self._closed = True


class CaptionWebSocketExtension:
    """
    Extension to add caption output capabilities to WebSocket sessions.
    
    Features:
    - SRT/WebVTT streaming via WebSocket
    - File output for compliance logging
    - UDP output for hardware encoders
    - Per-session configuration
    """
    
    def __init__(
        self,
        websocket: WebSocket,
        state: "SessionState",  # Forward reference to avoid circular import
        config: Optional[CaptionOutputConfig] = None,
    ):
        self.websocket = websocket
        self.state = state
        self.config = config or CaptionOutputConfig()
        self.service = CaptionOutputService(self.config)
        self._handlers: Set[WebSocketCaptionHandler] = set()
        self._file_outputs: Set[Path] = set()
        self._started = False
    
    async def start_session(self) -> None:
        """Start caption output session."""
        if self._started:
            return
        
        await self.service.start_session()
        
        # Add WebSocket handler for real-time streaming
        ws_handler = WebSocketCaptionHandler(self.websocket, self.config.format)
        self.service.add_websocket_handler(ws_handler)
        self._handlers.add(ws_handler)
        
        self._started = True
        logger.info(f"Caption session started (format={self.config.format.value})")
    
    async def end_session(self) -> None:
        """End caption output session."""
        if not self._started:
            return
        
        await self.service.end_session()
        
        # Mark all handlers as closed
        for handler in self._handlers:
            handler.close()
        self._handlers.clear()
        
        self._started = False
        
        # Log stats
        stats = self.service.get_stats()
        logger.info(f"Caption session ended: {stats['cues_emitted']} cues emitted")
    
    async def on_asr_segment(self, event: dict) -> None:
        """
        Process ASR segment event and emit caption.
        
        Args:
            event: ASR event dict with 'type', 'text', 't0', 't1', 'confidence', etc.
        """
        if not self._started:
            return
        
        # Only process final segments (not partial)
        if event.get("type") != "asr_final":
            return
        
        text = event.get("text", "").strip()
        if not text:
            return
        
        # Create transcript segment
        segment = TranscriptSegment(
            text=text,
            t0=event.get("t0", 0.0),
            t1=event.get("t1", 0.0),
            confidence=event.get("confidence", 1.0),
            is_final=True,
            speaker=event.get("speaker"),
        )
        
        # Emit caption
        try:
            await self.service.on_asr_segment(segment)
        except Exception as e:
            logger.error(f"Failed to emit caption: {e}")
    
    async def add_file_output(self, path: Path) -> None:
        """Add file output for compliance logging."""
        await self.service.add_file_output(path)
        self._file_outputs.add(path)
        logger.info(f"Added caption file output: {path}")
    
    async def add_udp_output(self, host: str, port: int) -> None:
        """Add UDP output for hardware encoder."""
        await self.service.add_udp_output(host, port)
        logger.info(f"Added caption UDP output: {host}:{port}")
    
    def set_format(self, format: CaptionFormat) -> None:
        """Change caption format (only effective before session starts)."""
        if not self._started:
            self.config.format = format
    
    def get_stats(self) -> dict:
        """Get caption output statistics."""
        return self.service.get_stats()


# Convenience factory functions

async def create_caption_extension(
    websocket: WebSocket,
    state: "SessionState",
    format: str = "srt",
    file_output: Optional[Path] = None,
    udp_host: Optional[str] = None,
    udp_port: Optional[int] = None,
) -> CaptionWebSocketExtension:
    """
    Create and configure a caption extension.
    
    Args:
        websocket: FastAPI WebSocket connection
        state: Session state object
        format: Caption format ("srt" or "vtt")
        file_output: Optional file path for compliance logging
        udp_host: Optional UDP destination host for hardware encoder
        udp_port: Optional UDP destination port
    
    Returns:
        Configured CaptionWebSocketExtension
    """
    caption_format = CaptionFormat.SRT if format.lower() == "srt" else CaptionFormat.WEBVTT
    config = CaptionOutputConfig(format=caption_format)
    
    ext = CaptionWebSocketExtension(websocket, state, config)
    
    if file_output:
        await ext.add_file_output(file_output)
    
    if udp_host and udp_port:
        await ext.add_udp_output(udp_host, udp_port)
    
    return ext


# Message handlers for client caption configuration

async def handle_caption_config_message(
    websocket: WebSocket,
    state: "SessionState",
    message: dict,
    caption_ext: Optional[CaptionWebSocketExtension] = None,
) -> Optional[CaptionWebSocketExtension]:
    """
    Handle client caption configuration messages.
    
    Client messages:
    - {"type": "caption_config", "enable": true, "format": "srt"}
    - {"type": "caption_config", "enable": true, "format": "vtt", "file_output": "/path/to/captions.srt"}
    - {"type": "caption_config", "udp_host": "192.168.1.100", "udp_port": 5004}
    
    Returns:
        CaptionWebSocketExtension if created/updated, None otherwise
    """
    msg_type = message.get("type")
    
    if msg_type != "caption_config":
        return caption_ext
    
    enabled = message.get("enable", True)
    
    if not enabled:
        # Disable captions
        if caption_ext:
            await caption_ext.end_session()
        return None
    
    # Create or update extension
    format_str = message.get("format", "srt")
    file_path = message.get("file_output")
    udp_host = message.get("udp_host")
    udp_port = message.get("udp_port")
    
    if caption_ext is None:
        caption_ext = await create_caption_extension(
            websocket,
            state,
            format=format_str,
            file_output=Path(file_path) if file_path else None,
            udp_host=udp_host,
            udp_port=udp_port,
        )
        await caption_ext.start_session()
    else:
        # Add additional outputs
        if file_path:
            await caption_ext.add_file_output(Path(file_path))
        if udp_host and udp_port:
            await caption_ext.add_udp_output(udp_host, udp_port)
    
    # Send confirmation
    await websocket.send_text(json.dumps({
        "type": "caption_status",
        "enabled": True,
        "format": format_str,
    }))
    
    return caption_ext
