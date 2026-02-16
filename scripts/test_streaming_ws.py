#!/usr/bin/env python3
"""
Test WebSocket streaming - simulates what the app does
"""
import asyncio
import base64
import json
import websockets

WS_URL = "ws://127.0.0.1:8000/ws/live-listener"

async def test_streaming():
    print("Connecting to WebSocket...")
    ws = await websockets.connect(WS_URL)
    
    # Send start
    await ws.send(json.dumps({
        "type": "start",
        "session_id": "test_stream",
        "sample_rate": 16000,
        "format": "pcm_s16le",
        "channels": 1
    }))
    print("Sent start")
    
    # Wait for ready
    for _ in range(5):
        msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
        print(f"Received: {msg[:100]}")
        if "streaming" in msg:
            break
    
    # Read audio file and send chunks
    import wave
    with wave.open("/Users/pranay/Projects/EchoPanel/llm_recording_pranay.wav", "rb") as f:
        frames = f.getnframes()
        rate = f.getframerate()
        audio = f.readframes(frames)
    
    # Send in 640-byte chunks (40ms at 16kHz)
    chunk_size = 640
    sent = 0
    for i in range(0, len(audio), chunk_size):
        chunk = audio[i:i+chunk_size]
        b64 = base64.b64encode(chunk).decode()
        await ws.send(json.dumps({
            "type": "audio",
            "data": b64,
            "source": "mic"
        }))
        sent += 1
        await asyncio.sleep(0.04)  # 40ms real-time
        if sent % 10 == 0:
            print(f"Sent {sent} chunks...")
    
    print(f"Total sent: {sent} chunks")
    
    # Wait for results
    print("\nWaiting for transcripts...")
    for _ in range(30):
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=1.0)
            if "transcript" in msg or "asr" in msg:
                print(f"Got: {msg[:200]}")
        except:
            break
    
    await ws.close()
    print("Done")

asyncio.run(test_streaming())
