#!/usr/bin/env python3
import asyncio
import wave
import json
import sys
import os
import websockets

async def stream_audio_file(file_path):
    uri = "ws://127.0.0.1:8000/ws/live-listener"
    
    if not os.path.exists(file_path):
        print(f"File {file_path} not found")
        return

    print(f"Connecting to {uri}...")
    async with websockets.connect(uri) as websocket:
        print("Connected!")
        
        # Open wave file
        wf = wave.open(file_path, 'rb')
        params = wf.getparams()
        print(f"Audio params: {params}")
        
        # Send start message
        start_msg = {
            "type": "start",
            "session_id": "test_streaming_file",
            "sample_rate": params.framerate,
            "format": "pcm_s16le",
            "channels": params.nchannels
        }
        await websocket.send(json.dumps(start_msg))
        print("Sent start message")

        # Stream audio in chunks
        chunk_size = 1024
        data = wf.readframes(chunk_size)
        while len(data) > 0:
            await websocket.send(data)
            await asyncio.sleep(0.1) # Simulate real-time
            data = wf.readframes(chunk_size)
        
        print("Finished streaming audio")
        
        # Wait for responses
        print("Waiting for responses...")
        try:
            while True:
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                resp_json = json.loads(response)
                print(f"Received {resp_json.get('type')}: {json.dumps(resp_json, indent=2)}")
        except asyncio.TimeoutError:
            print("Timeout waiting for more responses")
        
        # Send stop
        await websocket.send(json.dumps({"type": "stop", "session_id": "test_streaming_file"}))
        print("Sent stop message")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python stream_test.py <path_to_wav>")
        sys.exit(1)
    
    asyncio.run(stream_audio_file(sys.argv[1]))
