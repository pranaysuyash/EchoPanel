from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()


@router.websocket("/ws/asr")
async def ws_asr(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            message = await websocket.receive()
            if "bytes" in message:
                # TODO: Forward PCM frames to streaming ASR pipeline.
                continue
            if "text" in message:
                # TODO: Handle control messages and session lifecycle.
                continue
    except WebSocketDisconnect:
        # TODO: Handle disconnect cleanup.
        return
