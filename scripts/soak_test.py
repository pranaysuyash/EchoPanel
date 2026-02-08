#!/usr/bin/env python3
"""
Soak Test for EchoPanel Streaming Pipeline.

Simulates a real-time audio stream at 16kHz mono PCM16, runs for a configurable
duration, and asserts bounded latency throughout.

Usage:
    python scripts/soak_test.py --duration 1800 --check-interval 60
    
Requirements:
    - Server running at ws://127.0.0.1:8000/ws/live-listener
    - uv pip install websockets

Metrics tracked:
    - Frames sent
    - ASR events received
    - Average latency (time from audio timestamp to event receipt)
    - Queue high-water marks (from backpressure events)
"""

import argparse
import asyncio
import base64
import json
import struct
import sys
import time
from dataclasses import dataclass, field
from typing import List

try:
    import websockets
except ImportError:
    print("Please install websockets: uv pip install websockets")
    sys.exit(1)


@dataclass
class SoakMetrics:
    """Metrics collected during soak test."""
    frames_sent: int = 0
    bytes_sent: int = 0
    asr_events: int = 0
    latencies: List[float] = field(default_factory=list)
    backpressure_warnings: int = 0
    errors: List[str] = field(default_factory=list)
    start_time: float = 0.0


async def soak_test(
    duration_seconds: int = 1800,
    check_interval: int = 60,
    max_latency_threshold: float = 5.0,
    uri: str = "ws://127.0.0.1:8000/ws/live-listener",
) -> bool:
    """
    Run soak test for specified duration.
    
    Returns True if all checks pass, False otherwise.
    """
    metrics = SoakMetrics(start_time=time.time())
    stop_event = asyncio.Event()
    
    print(f"🧪 Starting soak test")
    print(f"   Duration: {duration_seconds}s")
    print(f"   Check interval: {check_interval}s")
    print(f"   Max latency threshold: {max_latency_threshold}s")
    print(f"   URI: {uri}")
    print()
    
    try:
        async with websockets.connect(uri, max_size=2**24) as ws:
            # Send start message
            session_id = f"soak-{int(time.time())}"
            await ws.send(json.dumps({
                "type": "start",
                "session_id": session_id,
                "sample_rate": 16000,
                "format": "pcm_s16le",
                "channels": 1,
            }))
            print(f"✅ Connected, session: {session_id}")
            
            async def send_audio():
                """Send audio frames at real-time rate."""
                frame_duration = 0.02  # 20ms per frame
                samples_per_frame = 320  # 320 samples = 20ms at 16kHz
                
                while not stop_event.is_set():
                    # Generate 20ms of low-level noise (more realistic than silence)
                    # This helps test VAD behavior
                    samples = [int(100 * (i % 3 - 1)) for i in range(samples_per_frame)]
                    frame = struct.pack(f"<{samples_per_frame}h", *samples)
                    
                    # Send as JSON with base64
                    await ws.send(json.dumps({
                        "type": "audio",
                        "source": "system",
                        "data": base64.b64encode(frame).decode(),
                    }))
                    
                    metrics.frames_sent += 1
                    metrics.bytes_sent += len(frame)
                    
                    await asyncio.sleep(frame_duration)
            
            async def receive_events():
                """Receive and process server events."""
                while not stop_event.is_set():
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=1.0)
                        event = json.loads(msg)
                        event_type = event.get("type", "")
                        
                        if event_type == "asr_final":
                            metrics.asr_events += 1
                            # Calculate latency: current time - event timestamp
                            t1 = event.get("t1", 0.0)
                            elapsed = time.time() - metrics.start_time
                            latency = elapsed - t1
                            metrics.latencies.append(latency)
                            
                        elif event_type == "status":
                            state = event.get("state", "")
                            if state == "backpressure":
                                metrics.backpressure_warnings += 1
                                print(f"⚠️  Backpressure warning: {event.get('message', '')}")
                            elif state == "error":
                                metrics.errors.append(event.get("message", "Unknown error"))
                                print(f"❌ Error: {event.get('message', '')}")
                                
                    except asyncio.TimeoutError:
                        pass
            
            async def check_stats():
                """Periodically check metrics and assert thresholds."""
                last_check = time.time()
                
                while not stop_event.is_set():
                    await asyncio.sleep(1)
                    
                    elapsed = time.time() - metrics.start_time
                    if time.time() - last_check >= check_interval:
                        last_check = time.time()
                        
                        # Calculate stats for last N events
                        recent_latencies = metrics.latencies[-100:] if metrics.latencies else []
                        avg_latency = sum(recent_latencies) / max(1, len(recent_latencies))
                        max_latency = max(recent_latencies) if recent_latencies else 0
                        
                        print(f"📊 [{int(elapsed)}s] Frames: {metrics.frames_sent:,} | "
                              f"ASR events: {metrics.asr_events} | "
                              f"Avg latency: {avg_latency:.2f}s | "
                              f"Max latency: {max_latency:.2f}s | "
                              f"Backpressure: {metrics.backpressure_warnings}")
                        
                        # Assert latency threshold
                        if avg_latency > max_latency_threshold:
                            print(f"❌ FAIL: Average latency {avg_latency:.2f}s exceeds threshold {max_latency_threshold}s")
                            return False
            
            async def timer():
                """Stop test after duration."""
                await asyncio.sleep(duration_seconds)
                stop_event.set()
            
            # Run all tasks concurrently
            tasks = [
                asyncio.create_task(send_audio()),
                asyncio.create_task(receive_events()),
                asyncio.create_task(check_stats()),
                asyncio.create_task(timer()),
            ]
            
            await asyncio.gather(*tasks, return_exceptions=True)
            
            # Send stop and wait briefly for final summary
            await ws.send(json.dumps({"type": "stop", "session_id": session_id}))
            
            try:
                final_msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
                final = json.loads(final_msg)
                if final.get("type") == "final_summary":
                    print(f"✅ Received final summary")
            except asyncio.TimeoutError:
                print(f"⚠️  No final summary received (timeout)")
                
    except ConnectionRefusedError:
        print(f"❌ Connection refused. Is the server running at {uri}?")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    # Final report
    print()
    print("=" * 60)
    print("SOAK TEST COMPLETE")
    print("=" * 60)
    print(f"Duration: {duration_seconds}s")
    print(f"Frames sent: {metrics.frames_sent:,}")
    print(f"Bytes sent: {metrics.bytes_sent:,}")
    print(f"ASR events received: {metrics.asr_events}")
    print(f"Backpressure warnings: {metrics.backpressure_warnings}")
    print(f"Errors: {len(metrics.errors)}")
    
    if metrics.latencies:
        avg_latency = sum(metrics.latencies) / len(metrics.latencies)
        max_latency = max(metrics.latencies)
        min_latency = min(metrics.latencies)
        print(f"Latency (avg/min/max): {avg_latency:.2f}s / {min_latency:.2f}s / {max_latency:.2f}s")
    else:
        print("Latency: No ASR events received")
    
    # Determine pass/fail
    passed = True
    if metrics.errors:
        print(f"\n❌ FAIL: {len(metrics.errors)} errors encountered")
        for err in metrics.errors[:5]:
            print(f"   - {err}")
        passed = False
    
    if metrics.latencies:
        avg_latency = sum(metrics.latencies) / len(metrics.latencies)
        if avg_latency > max_latency_threshold:
            print(f"\n❌ FAIL: Average latency {avg_latency:.2f}s exceeds threshold {max_latency_threshold}s")
            passed = False
    
    if passed:
        print("\n✅ PASS: All checks passed")
    
    return passed


def main():
    parser = argparse.ArgumentParser(description="EchoPanel Soak Test")
    parser.add_argument("--duration", type=int, default=60,
                        help="Test duration in seconds (default: 60)")
    parser.add_argument("--check-interval", type=int, default=10,
                        help="Metrics check interval in seconds (default: 10)")
    parser.add_argument("--max-latency", type=float, default=5.0,
                        help="Maximum allowed average latency in seconds (default: 5.0)")
    parser.add_argument("--uri", type=str, default="ws://127.0.0.1:8000/ws/live-listener",
                        help="WebSocket URI (default: ws://127.0.0.1:8000/ws/live-listener)")
    
    args = parser.parse_args()
    
    success = asyncio.run(soak_test(
        duration_seconds=args.duration,
        check_interval=args.check_interval,
        max_latency_threshold=args.max_latency,
        uri=args.uri,
    ))
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
