import asyncio
import struct
import uuid

import websockets


async def main() -> None:
    session_id = str(uuid.uuid4())
    uri = "ws://localhost:8000/ws/asr"
    async with websockets.connect(uri) as websocket:
        await websocket.send(
            f'{{"type":"start","session_id":"{session_id}","sample_rate":16000,"format":"pcm_s16le","channels":1}}'
        )
        for _ in range(50):
            samples = [0] * 320
            frame = struct.pack("<" + "h" * len(samples), *samples)
            await websocket.send(frame)
            await asyncio.sleep(0.02)
        await websocket.send(f'{{"type":"stop","session_id":"{session_id}"}}')


if __name__ == "__main__":
    asyncio.run(main())
