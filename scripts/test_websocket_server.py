#!/usr/bin/env python3
"""
Test WebSocket Server for EchoPanel.

This script tests if the backend WebSocket server is correctly receiving
and processing audio data. It can send fake audio (silence) or capture live
audio from the microphone.

Usage:
    python scripts/test_websocket_server.py [--live]
"""

import asyncio
import struct
import sys
import argparse

try:
    import websockets
except ImportError:
    print("Please install websockets: uv pip install websockets")
    sys.exit(1)

try:
    import pyaudio
except ImportError:
    print("Please install pyaudio: uv pip install pyaudio")
    sys.exit(1)


async def send_fake_audio(websocket):
    """Send fake audio (silence) to the server."""
    print("📤 Sending fake audio (silence)...")
    for i in range(200):  # 200 * 640 bytes = 128000 bytes = 4 seconds
        # Create 320 samples of silence (640 bytes per frame)
        frame = struct.pack('<' + 'h' * 320, *([0] * 320))
        await websocket.send(frame)
        if (i + 1) % 50 == 0:
            print(f"   Sent {(i + 1) * 640} bytes ({(i + 1) * 20}ms of audio)")
        await asyncio.sleep(0.01)  # Small delay to simulate real-time
    print("✅ Finished sending fake audio")


async def send_live_audio(websocket):
    """Capture and send live audio from microphone."""
    print("🎤 Starting live audio capture...")
    
    # Audio parameters
    CHUNK = 320  # 320 samples = 20ms at 16kHz
    FORMAT = pyaudio.paInt16
    CHANNELS = 1
    RATE = 16000
    
    audio = pyaudio.PyAudio()
    stream = None
    
    try:
        stream = audio.open(format=FORMAT,
                            channels=CHANNELS,
                            rate=RATE,
                            input=True,
                            frames_per_buffer=CHUNK)
        
        print("🎙️  Speak into the microphone (recording for 4 seconds)...")
        
        for i in range(200):  # 200 chunks = 4 seconds
            data = stream.read(CHUNK, exception_on_overflow=False)
            await websocket.send(data)
            if (i + 1) % 50 == 0:
                print(f"   Sent {(i + 1) * 640} bytes ({(i + 1) * 20}ms of audio)")
            await asyncio.sleep(0.01)  # Small delay
        
        print("✅ Finished live audio capture")
        
    except Exception as e:
        print(f"❌ Audio capture error: {e}")
    finally:
        if stream is not None:
            stream.stop_stream()
            stream.close()
        audio.terminate()


async def test_client(use_live_audio=False):
    """Test the WebSocket server with fake or live audio data."""
    uri = "ws://127.0.0.1:8000/ws/live-listener"
    
    print(f"🔌 Connecting to {uri}...")
    
    try:
        async with websockets.connect(uri) as websocket:
            print("✅ Connected!")
            
            # Send start message
            import json
            start_msg = json.dumps({
                "type": "start",
                "session_id": "test123",
                "sample_rate": 16000,
                "format": "pcm_s16le",
                "channels": 1
            })
            await websocket.send(start_msg)
            print("📤 Sent start message")
            
            # Wait a moment for the server to process
            await asyncio.sleep(0.5)
            
            if use_live_audio:
                await send_live_audio(websocket)
            else:
                await send_fake_audio(websocket)
            
            print("👂 Waiting for server responses...")
            
            # Listen for responses with timeout
            try:
                for i in range(10):
                    response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                    print(f"📥 Received: {response[:200]}..." if len(response) > 200 else f"📥 Received: {response}")
            except asyncio.TimeoutError:
                print("⏱️  No more responses (timeout after 5s)")
            
            # Send stop message
            stop_msg = json.dumps({
                "type": "stop",
                "session_id": "test123"
            })
            await websocket.send(stop_msg)
            print("📤 Sent stop message")
            
    except ConnectionRefusedError:
        print("❌ Connection refused! Is the server running?")
        print("   Run: cd server && python -m uvicorn app:app --reload")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test EchoPanel WebSocket Server")
    parser.add_argument("--live", action="store_true", help="Use live microphone audio instead of fake silence")
    args = parser.parse_args()
    
    print("=" * 50)
    print("EchoPanel WebSocket Server Test")
    print(f"Mode: {'Live Audio' if args.live else 'Fake Audio (Silence)'}")
    print("=" * 50)
    asyncio.run(test_client(use_live_audio=args.live))
    print("=" * 50)
    print("Test complete!")
