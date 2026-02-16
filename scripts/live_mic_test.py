#!/usr/bin/env python3
"""
Live microphone transcription test
- Captures your voice
- Uses large model 
- Tracks timing at each step
"""
import time
import wave
import threading
import numpy as np

print("=" * 60)
print("LIVE MICROPHONE TRANSCRIPTION TEST")
print("=" * 60)

# Settings
MODEL_SIZE = "large-v3"  # Use large model
CHUNK_SECONDS = 2  # Process every 2 seconds

# Standard text for testing - READ THIS ALOUD
TEST_TEXT = """Hello, this is a test of the EchoPanel transcription system. 
A large language model, or LLM, is a language model trained with self-supervised machine learning.
The largest and most capable LLMs are generative pre-trained transformers, also known as GPTs.
These models acquire predictive power regarding syntax, semantics, and ontologies.
LLMs represent a significant new technology in their ability to generalize across tasks.
This innovation enabled models like GPT and BERT which demonstrated emergent behaviors at scale."""

# Step 1: Load model
print(f"\n1. Loading model: {MODEL_SIZE}")
from faster_whisper import WhisperModel

load_start = time.time()
model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
load_time = time.time() - load_start
print(f"   ✅ Model loaded in {load_time:.1f}s")

# Step 2: Setup microphone capture
print(f"\n2. Setting up microphone...")
import pyaudio

audio = pyaudio.PyAudio()
chunk_size = 1024
format = pyaudio.paInt16
channels = 1
rate = 16000

stream = audio.open(format=format, channels=channels, rate=rate, 
                    input=True, frames_per_buffer=chunk_size)

print(f"   ✅ Mic ready (16kHz, mono)")

# Step 3: Start recording
print(f"\n3. Recording...")
print("=" * 60)
print(">>> READ THIS TEXT ALOUD: <<<")
print("=" * 60)
print(TEST_TEXT)
print("=" * 60)
print(">>> START READING NOW! <<<")
print("=" * 60)
frames = []
start_time = time.time()
recording_duration = 10  # seconds

# Record with progress - tell user when to speak
for i in range(int(rate / chunk_size * recording_duration)):
    data = stream.read(chunk_size)
    frames.append(data)
    if i % (rate // chunk_size) == 0:
        elapsed = i * chunk_size / rate
        print(f"Recording... {elapsed:.0f}s - KEEP SPEAKING!")

record_time = time.time() - start_time
print(f"   ✅ Recorded {record_time:.1f}s of audio")

# Step 4: Save to buffer
audio_data = b''.join(frames)
audio_np = np.frombuffer(audio_data, dtype=np.int16).astype(np.float32) / 32768.0
print(f"\n4. Audio buffer: {len(audio_np)} samples ({len(audio_np)/rate:.1f}s)")

# Step 5: Transcribe with timing
print(f"\n5. Transcribing with {MODEL_SIZE}...")
transcribe_start = time.time()

segments, info = model.transcribe(audio_np, language="en")

transcribe_time = time.time() - transcribe_start
total_time = time.time() - start_time

print(f"   - Transcription took: {transcribe_time:.2f}s")
print(f"   - Total time: {total_time:.2f}s")
print(f"   - Language: {info.language} ({info.language_probability:.2f})")

# Step 6: Show results
print(f"\n6. TRANSCRIPTION RESULTS:")
print("-" * 40)

segment_count = 0
for seg in segments:
    segment_count += 1
    duration = seg.end - seg.start
    print(f"[{seg.start:.1f}s - {seg.end:.1f}s] ({duration:.1f}s) {seg.text}")

print("-" * 40)
print(f"Total segments: {segment_count}")

if segment_count == 0:
    print("\n⚠️ PROBLEM: No speech detected!")
else:
    print(f"\n✅ SUCCESS! {segment_count} segments from {recording_duration}s of speech")

print(f"\n📊 TIMING SUMMARY:")
print(f"   Model load: {load_time:.1f}s")
print(f"   Recording: {record_time:.1f}s") 
print(f"   Transcribe: {transcribe_time:.1f}s")
print(f"   Total:     {total_time:.1f}s")

# Cleanup
stream.stop_stream()
stream.close()
audio.terminate()

print("\n" + "=" * 60)
