#!/usr/bin/env python3
import asyncio
import wave
import json
import sys
import os
import websockets
import base64

async def receiver(websocket):
    print("Receiver started")
    try:
        while True:
            response = await websocket.recv()
            resp_json = json.loads(response)
            msg_type = resp_json.get('type')
            print(f">>> Received {msg_type}")
            if msg_type == 'asr_final':
                print(f"    Text: {resp_json.get('text')}")
            elif msg_type == 'entities_update':
                print(f"    Entities: {resp_json.get('people', [])[:2]} ...")
            elif msg_type == 'cards_update':
                print(f"    Actions: {len(resp_json.get('actions', []))}")
            elif msg_type == 'final_summary':
                print("    Final summary received!")
                break
    except websockets.exceptions.ConnectionClosed:
        print("Receiver: Connection closed")
    except Exception as e:
        print(f"Receiver Error: {e}")

async def stream_audio_file_json(file_path):
    uri = "ws://127.0.0.1:8000/ws/live-listener"
    
    if not os.path.exists(file_path):
        print(f"File {file_path} not found")
        return

    print(f"Connecting to {uri}...")
    async with websockets.connect(uri) as websocket:
        print("Connected!")
        
        # Start receiver task
        recv_task = asyncio.create_task(receiver(websocket))
        
        # Open wave file
        wf = wave.open(file_path, 'rb')
        params = wf.getparams()
        
        # Send start message
        start_msg = {
            "type": "start",
            "session_id": "test_periodic_updates",
            "sample_rate": params.framerate,
            "format": "pcm_s16le",
            "channels": params.nchannels
        }
        await websocket.send(json.dumps(start_msg))
        print("Sent start message")

        # Stream audio in JSON chunks
        chunk_size = 4000
        data = wf.readframes(chunk_size)
        while len(data) > 0:
            b64_data = base64.b64encode(data).decode('utf-8')
            audio_msg = {
                "type": "audio",
                "source": "mic",
                "data": b64_data
            }
            await websocket.send(json.dumps(audio_msg))
            await asyncio.sleep(0.1)
            data = wf.readframes(chunk_size)
        
        print("Finished streaming audio, waiting 45s for periodic analysis updates...")
        await asyncio.sleep(45.0)
        
        # Send stop
        await websocket.send(json.dumps({"type": "stop", "session_id": "test_periodic_updates"}))
        print("Sent stop message")
        
        # Wait for receiver to finish
        await recv_task

if __name__ == "__main__":
    file_path = "test_speech.wav"
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    
    asyncio.run(stream_audio_file_json(file_path))
