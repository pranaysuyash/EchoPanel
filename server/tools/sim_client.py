import argparse
import asyncio
import json
import os

import websockets

async def run_client(url: str, frames: int) -> None:
    async with websockets.connect(url) as websocket:
        await websocket.send(
            json.dumps(
                {
                    "type": "start",
                    "session_id": "simulated-session",
                    "sample_rate": 16000,
                    "format": "pcm_s16le",
                    "channels": 1,
                }
            )
        )
        for _ in range(frames):
            await websocket.send(os.urandom(640))
            await asyncio.sleep(0.02)
        await websocket.send(json.dumps({"type": "stop", "session_id": "simulated-session"}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--frames", type=int, default=50)
    args = parser.parse_args()

    asyncio.run(run_client(args.url, args.frames))
