#!/usr/bin/env python3
"""
Test harness for EchoPanel UI testing with real audio file.
Plays llm_recording_pranay.wav through WebSocket and captures transcript output.
"""

import asyncio
import base64
import json
import sys
import time
import wave
from datetime import datetime
from pathlib import Path

import websockets

# Configuration
AUDIO_FILE = Path("/Users/pranay/Projects/EchoPanel/llm_recording_pranay.wav")
WS_URL = "ws://127.0.0.1:8000/ws/live-listener"
CHUNK_DURATION = 0.5  # seconds per chunk
SAMPLE_RATE = 16000

# Statistics
stats = {
    "start_time": None,
    "segments_received": 0,
    "partials_received": 0,
    "finals_received": 0,
    "errors": [],
    "duplicates": [],
    "confidence_issues": [],
    "transcript": []
}


async def stream_audio(websocket, audio_path):
    """Stream audio file to WebSocket in chunks."""
    with wave.open(str(audio_path), 'rb') as wav_file:
        n_channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        framerate = wav_file.getframerate()
        n_frames = wav_file.getnframes()
        
        print(f"Audio: {n_frames/framerate:.1f}s, {framerate}Hz, {n_channels}ch, {sample_width}bytes")
        
        chunk_frames = int(framerate * CHUNK_DURATION)
        frames_sent = 0
        
        while frames_sent < n_frames:
            frames_to_read = min(chunk_frames, n_frames - frames_sent)
            data = wav_file.readframes(frames_to_read)
            
            if not data:
                break
                
            # Send audio chunk
            b64_data = base64.b64encode(data).decode('utf-8')
            await websocket.send(json.dumps({
                "type": "audio",
                "data": b64_data,
                "source": "system"
            }))
            
            frames_sent += frames_to_read
            
            # Small delay to simulate real-time streaming
            await asyncio.sleep(CHUNK_DURATION * 0.8)
            
            if frames_sent % (framerate * 10) == 0:  # Every 10 seconds
                elapsed = time.time() - stats["start_time"]
                progress = frames_sent / n_frames * 100
                print(f"  Progress: {progress:.0f}% ({elapsed:.1f}s elapsed)")


async def receive_messages(websocket):
    """Receive and process messages from WebSocket."""
    seen_texts = set()
    
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type", "unknown")
                
                if msg_type == "asr_partial":
                    stats["partials_received"] += 1
                    stats["segments_received"] += 1
                    
                elif msg_type == "asr_final":
                    stats["finals_received"] += 1
                    stats["segments_received"] += 1
                    
                    text = data.get("text", "").strip()
                    t0 = data.get("t0", 0)
                    t1 = data.get("t1", 0)
                    confidence = data.get("confidence", 0)
                    
                    # Check for duplicates
                    text_key = f"{text}_{t0:.1f}"
                    if text_key in seen_texts:
                        stats["duplicates"].append({
                            "time": datetime.now().isoformat(),
                            "text": text,
                            "t0": t0
                        })
                        print(f"  ⚠️ DUPLICATE: '{text[:50]}...'")
                    else:
                        seen_texts.add(text_key)
                    
                    # Check confidence issues
                    if confidence < 0.3 and len(text.split()) < 3:
                        stats["confidence_issues"].append({
                            "time": datetime.now().isoformat(),
                            "text": text,
                            "confidence": confidence
                        })
                        print(f"  ⚠️ LOW CONFIDENCE: '{text[:50]}...' ({confidence:.2f})")
                    
                    stats["transcript"].append({
                        "time": datetime.now().isoformat(),
                        "t0": t0,
                        "t1": t1,
                        "text": text,
                        "confidence": confidence,
                        "source": data.get("source", "unknown")
                    })
                    
                    print(f"  [{t0:05.1f}-{t1:05.1f}] ({confidence:.0%}) {text[:60]}...")
                    
                elif msg_type == "status":
                    print(f"  Status: {data.get('state', 'unknown')} - {data.get('message', '')}")
                    
                elif msg_type == "error":
                    stats["errors"].append({
                        "time": datetime.now().isoformat(),
                        "message": data.get("message", "Unknown error")
                    })
                    print(f"  ❌ ERROR: {data.get('message', 'Unknown error')}")
                    
            except json.JSONDecodeError:
                print(f"  Raw message: {message[:100]}...")
                
    except websockets.exceptions.ConnectionClosed:
        print("  Connection closed")


async def run_test():
    """Run the full test."""
    print("=" * 60)
    print("EchoPanel UI Test with Audio File")
    print("=" * 60)
    print(f"Audio file: {AUDIO_FILE}")
    print(f"WebSocket: {WS_URL}")
    print()
    
    # Check if audio file exists
    if not AUDIO_FILE.exists():
        print(f"❌ Audio file not found: {AUDIO_FILE}")
        sys.exit(1)
    
    try:
        async with websockets.connect(WS_URL) as websocket:
            print("✅ Connected to WebSocket")
            
            # Send start message
            await websocket.send(json.dumps({
                "type": "start",
                "session_id": f"test_{int(time.time())}",
                "sample_rate": SAMPLE_RATE,
                "format": "pcm_s16le",
                "channels": 1
            }))
            print("✅ Sent start message")
            print()
            
            stats["start_time"] = time.time()
            
            # Start receiving and streaming concurrently
            receive_task = asyncio.create_task(receive_messages(websocket))
            
            # Wait a moment for server to initialize
            await asyncio.sleep(0.5)
            
            # Stream audio
            print("🎵 Streaming audio...")
            await stream_audio(websocket, AUDIO_FILE)
            print()
            
            # Send stop
            print("⏹️ Sending stop...")
            await websocket.send(json.dumps({"type": "stop"}))
            
            # Wait for final summary
            print("⏳ Waiting for final summary (10s max)...")
            await asyncio.sleep(10)
            
            receive_task.cancel()
            try:
                await receive_task
            except asyncio.CancelledError:
                pass
                
    except websockets.exceptions.ConnectionRefused:
        print(f"❌ Cannot connect to {WS_URL}")
        print("   Make sure the server is running: uv run uvicorn server.main:app --reload")
        sys.exit(1)
    
    # Print summary
    print()
    print("=" * 60)
    print("TEST SUMMARY")
    print("=" * 60)
    elapsed = time.time() - stats["start_time"]
    print(f"Duration: {elapsed:.1f}s")
    print(f"Segments received: {stats['segments_received']}")
    print(f"  - Partials: {stats['partials_received']}")
    print(f"  - Finals: {stats['finals_received']}")
    print(f"Duplicates detected: {len(stats['duplicates'])}")
    print(f"Confidence issues: {len(stats['confidence_issues'])}")
    print(f"Errors: {len(stats['errors'])}")
    
    # Save transcript
    output_file = Path("/Users/pranay/Projects/EchoPanel/output/test_transcript.json")
    output_file.parent.mkdir(exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(stats, f, indent=2)
    print(f"\n📝 Full transcript saved to: {output_file}")
    
    # Return success/failure
    if stats["errors"] or len(stats["duplicates"]) > 5:
        print("\n❌ TEST FAILED - Issues detected")
        return 1
    else:
        print("\n✅ TEST PASSED")
        return 0


if __name__ == "__main__":
    result = asyncio.run(run_test())
    sys.exit(result)
