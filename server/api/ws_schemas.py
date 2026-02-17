"""Pydantic schemas for WebSocket message validation."""

from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict, Any, Literal


class StartMessage(BaseModel):
    """Schema for 'start' message from client."""
    type: Literal["start"] = "start"
    session_id: str = Field(..., min_length=1, max_length=256)
    sample_rate: int = Field(default=16000, ge=8000, le=48000)
    format: str = Field(default="pcm_s16le", pattern="^(pcm_s16le|pcm_s8|pcm_f32le)$")
    channels: int = Field(default=1, ge=1, le=2)
    attempt_id: Optional[str] = Field(default=None, max_length=256)
    connection_id: Optional[str] = Field(default=None, max_length=256)
    client_features: Optional[Dict[str, Any]] = None

    @field_validator("session_id")
    @classmethod
    def validate_session_id(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("session_id cannot be empty or whitespace")
        return v.strip()


class StopMessage(BaseModel):
    """Schema for 'stop' message from client."""
    type: Literal["stop"] = "stop"
    session_id: str = Field(..., min_length=1, max_length=256)

    @field_validator("session_id")
    @classmethod
    def validate_session_id(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("session_id cannot be empty or whitespace")
        return v.strip()


class AudioMessage(BaseModel):
    """Schema for 'audio' message from client (base64 encoded)."""
    type: Literal["audio"] = "audio"
    source: str = Field(default="system", pattern="^(system|mic|microphone)$")
    data: str = Field(..., min_length=1)
    timestamp: Optional[float] = Field(default=None, ge=0)

    @field_validator("data")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        import base64
        try:
            # Validate it's valid base64
            base64.b64decode(v, validate=True)
            return v
        except Exception:
            raise ValueError("data must be valid base64 encoded audio")


class VoiceNoteStartMessage(BaseModel):
    """Schema for 'voice_note_start' message."""
    type: Literal["voice_note_start"] = "voice_note_start"
    session_id: str = Field(..., min_length=1, max_length=256)
    sample_rate: int = Field(default=16000, ge=8000, le=48000)
    format: str = Field(default="pcm_s16le", pattern="^(pcm_s16le|pcm_s8|pcm_f32le)$")
    channels: int = Field(default=1, ge=1, le=2)


class VoiceNoteAudioMessage(BaseModel):
    """Schema for 'voice_note_audio' message."""
    type: Literal["voice_note_audio"] = "voice_note_audio"
    data: str = Field(..., min_length=1)

    @field_validator("data")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        import base64
        try:
            base64.b64decode(v, validate=True)
            return v
        except Exception:
            raise ValueError("data must be valid base64 encoded audio")


class VoiceNoteStopMessage(BaseModel):
    """Schema for 'voice_note_stop' message."""
    type: Literal["voice_note_stop"] = "voice_note_stop"
    session_id: Optional[str] = Field(default=None, max_length=256)


class OCRTextMessage(BaseModel):
    """Schema for 'ocr_text' message."""
    type: Literal["ocr_text"] = "ocr_text"
    text: str = Field(..., min_length=1, max_length=10000)
    timestamp: Optional[float] = Field(default=None, ge=0)

    @field_validator("text")
    @classmethod
    def validate_text(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("text cannot be empty or whitespace")
        return v.strip()


# Union type for all incoming messages
IncomingMessage = (
    StartMessage
    | StopMessage
    | AudioMessage
    | VoiceNoteStartMessage
    | VoiceNoteAudioMessage
    | VoiceNoteStopMessage
    | OCRTextMessage
)


def parse_websocket_message(data: Dict[str, Any]) -> IncomingMessage:
    """Parse and validate a WebSocket message.
    
    Args:
        data: Raw JSON dict from WebSocket message
        
    Returns:
        Validated pydantic model for the message type
        
    Raises:
        ValueError: If message type is unknown or validation fails
    """
    msg_type = data.get("type", "")
    
    validators = {
        "start": StartMessage,
        "stop": StopMessage,
        "audio": AudioMessage,
        "voice_note_start": VoiceNoteStartMessage,
        "voice_note_audio": VoiceNoteAudioMessage,
        "voice_note_stop": VoiceNoteStopMessage,
        "ocr_text": OCRTextMessage,
    }
    
    if msg_type not in validators:
        raise ValueError(f"Unknown message type: {msg_type}")
    
    return validators[msg_type].model_validate(data)
