#!/usr/bin/env python3
"""
Simple audio transcription test - to debug the pipeline issue
"""
import time
import wave
import sys

print("=" * 60)
print("ECHO PANEL AUDIO TEST")
print("=" * 60)

# Test 1: Load audio file and transcribe
AUDIO_FILE = "/Users/pranay/Projects/EchoPanel/llm_recording_pranay.wav"

print(f"\n1. Loading audio file: {AUDIO_FILE}")
with wave.open(AUDIO_FILE, 'rb') as f:
    frames = f.getnframes()
    rate = f.getframerate()
    channels = f.getnchannels()
    duration = frames / rate
    print(f"   - Frames: {frames}")
    print(f"   - Sample rate: {rate} Hz")
    print(f"   - Channels: {channels}")
    print(f"   - Duration: {duration:.1f} seconds")
    audio_data = f.readframes(frames)

print(f"\n2. Audio data size: {len(audio_data)} bytes")

# Test 2: Load model and transcribe
print(f"\n3. Loading faster-whisper model...")
from faster_whisper import WhisperModel

start = time.time()
model = WhisperModel("small.en", device="cpu", compute_type="int8")
load_time = time.time() - start
print(f"   - Model loaded in {load_time:.2f}s")

# Test 3: Transcribe
print(f"\n4. Starting transcription...")
import numpy as np

audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
print(f"   - Audio array shape: {audio_np.shape}")
print(f"   - Audio min/max: {audio_np.min():.4f} / {audio_np.max():.4f}")
print(f"   - Audio mean: {np.abs(audio_np).mean():.4f}")

transcribe_start = time.time()
segments, info = model.transcribe(audio_np, language="en")
transcribe_time = time.time() - transcribe_start

print(f"\n5. Transcription results:")
print(f"   - Time taken: {transcribe_time:.2f}s")
print(f"   - Language detected: {info.language}")
print(f"   - Language probability: {info.language_probability:.2f}")

print(f"\n6. Segments:")
segment_count = 0
for seg in segments:
    segment_count += 1
    print(f"   [{seg.start:.1f}s - {seg.end:.1f}s] {seg.text}")
    
print(f"\n   Total segments: {segment_count}")

if segment_count == 0:
    print("\n⚠️ WARNING: No segments returned! Audio might be silent or empty.")
else:
    print("\n✅ SUCCESS: Transcription worked!")

print("\n" + "=" * 60)
