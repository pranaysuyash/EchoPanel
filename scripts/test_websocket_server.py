#!/usr/bin/env python3
"""
Test WebSocket Server for EchoPanel.

This script tests if the backend WebSocket server is correctly receiving
and processing audio data. It sends fake audio (silence) to verify the
pipeline is working.

Usage:
    python scripts/test_websocket_server.py
"""

import asyncio
import struct
import sys

try:
    import websockets
except ImportError:
    print("Please install websockets: pip install websockets")
    sys.exit(1)


async def test_client():
    """Test the WebSocket server with fake audio data."""
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
            
            # Send fake audio (silence)
            # 4 seconds * 16000 samples/sec * 2 bytes/sample = 128000 bytes
            # We'll send 10 chunks of 640 bytes each (20ms frames)
            # to simulate real streaming
            
            print("📤 Sending audio chunks...")
            for i in range(200):  # 200 * 640 bytes = 128000 bytes = 4 seconds
                # Create 320 samples of silence (640 bytes per frame)
                frame = struct.pack('<' + 'h' * 320, *([0] * 320))
                await websocket.send(frame)
                if (i + 1) % 50 == 0:
                    print(f"   Sent {(i + 1) * 640} bytes ({(i + 1) * 20}ms of audio)")
                await asyncio.sleep(0.01)  # Small delay to simulate real-time
            
            print("✅ Finished sending audio")
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
    print("=" * 50)
    print("EchoPanel WebSocket Server Test")
    print("=" * 50)
    asyncio.run(test_client())
    print("=" * 50)
    print("Test complete!")
