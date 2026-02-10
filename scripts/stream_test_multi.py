#!/usr/bin/env python3
import asyncio
import wave
import json
import sys
import os
import websockets
import base64

async def stream_multi_source(file_path):
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
        
        # Send start message
        start_msg = {
            "type": "start",
            "session_id": "test_multi_source",
            "sample_rate": params.framerate,
            "format": "pcm_s16le",
            "channels": params.nchannels
        }
        await websocket.send(json.dumps(start_msg))
        print("Sent start message")

        # Stream audio in interleaved JSON chunks
        chunk_size = 8000 # ~500ms
        data = wf.readframes(chunk_size)
        while len(data) > 0:
            b64_data = base64.b64encode(data).decode('utf-8')
            
            # Send as system
            await websocket.send(json.dumps({
                "type": "audio",
                "source": "system",
                "data": b64_data
            }))
            
            # Send as mic (simulating both active)
            await websocket.send(json.dumps({
                "type": "audio",
                "source": "mic",
                "data": b64_data
            }))
            
            await asyncio.sleep(0.2)
            data = wf.readframes(chunk_size)
        
        print("Finished streaming audio")
        
        # Send stop
        await websocket.send(json.dumps({"type": "stop", "session_id": "test_multi_source"}))
        print("Sent stop message")

        # Wait for responses
        sources_seen = set()
        print("Waiting for responses...")
        try:
            while True:
                response = await asyncio.wait_for(websocket.recv(), timeout=15.0)
                resp_json = json.loads(response)
                msg_type = resp_json.get('type')
                
                if msg_type == 'asr_final':
                     source = resp_json.get('source')
                     sources_seen.add(source)
                     print(f"Received asr_final from {source}: {resp_json.get('text')[:30]}...")
                
                if msg_type == 'final_summary':
                    print("Final summary received!")
                    print(f"Sources captured: {sources_seen}")
                    break
        except asyncio.TimeoutError:
            print("Timeout waiting for more responses")
        except websockets.exceptions.ConnectionClosed:
            print("Connection closed")

if __name__ == "__main__":
    file_path = "test_speech.wav"
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    
    asyncio.run(stream_multi_source(file_path))
