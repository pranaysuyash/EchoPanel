import argparse
import asyncio
import json
import os
import uuid

import websockets


async def main(url: str) -> None:
    session_id = str(uuid.uuid4())
    async with websockets.connect(url, max_size=2**24) as ws:
        await ws.send(
            json.dumps(
                {
                    "type": "start",
                    "session_id": session_id,
                    "sample_rate": 16000,
                    "format": "pcm_s16le",
                    "channels": 1,
                }
            )
        )

        frame = os.urandom(640)
        for _ in range(50):
            await ws.send(frame)
            await asyncio.sleep(0.02)

        await ws.send(json.dumps({"type": "stop", "session_id": session_id}))

        try:
            async for msg in ws:
                print(msg)
        except websockets.ConnectionClosed:
            return


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:8000/ws/live-listener")
    args = parser.parse_args()
    asyncio.run(main(args.url))

