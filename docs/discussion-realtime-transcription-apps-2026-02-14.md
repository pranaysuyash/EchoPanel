# Discussion: Real-Time Transcription Apps

**Date:** 2026-02-14  
**Participants:** User, Kimi Code CLI

---

## Question 1: Are there no apps that do real time transcription? how do they process it?

### Answer

There are definitely apps that do real-time transcription! Here are some popular ones and how they generally work:

#### Popular Real-Time Transcription Apps

| App | Platform | Notes |
|-----|----------|-------|
| **Otter.ai** | Web, iOS, Android | Meeting-focused, speaker diarization |
| **Rev Live Caption** | iOS | Human + AI hybrid |
| **Google Live Transcribe** | Android | Free, on-device for some languages |
| **Apple Live Captions** | iOS/macOS | On-device, system-wide |
| **Whisper (OpenAI)** | Cross-platform | Can run locally or via API |
| **Descript** | Desktop | Editing + transcription combined |
| **Fireflies.ai** | Web | Meeting bot approach |

#### How Real-Time Transcription Works

The pipeline typically looks like this:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Audio      │───▶│  Voice      │───▶│  Speech     │───▶│  Text       │
│  Capture    │    │  Activity   │    │  Recognition│    │  Output     │
│  (Microphone│    │  Detection  │    │  (ASR Model)│    │  (Display/  │
│  or Stream) │    │  (VAD)      │    │             │    │  Buffer)    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                              │
                                              ▼
                                       ┌─────────────┐
                                       │  Post-      │
                                       │  Processing │
                                       │ (Punctuation│
                                       │  Formatting)│
                                       └─────────────┘
```

##### 1. Audio Streaming
- Capture audio in small chunks (typically 100ms–1s)
- Often use WebRTC, Core Audio (macOS), or AudioRecord (Android)

##### 2. Voice Activity Detection (VAD)
- Filters out silence to save processing
- Common: WebRTC VAD, Silero VAD, or energy-based thresholding
- Project has `convert_vad_model.py` — likely for this purpose

##### 3. Speech Recognition (ASR)

There are two main architectures:

| Approach | How It Works | Examples |
|----------|--------------|----------|
| **Streaming/Incremental** | Processes audio chunks as they arrive, emits partial results | Whisper streaming, Conformer, RNN-T |
| **Segment-based** | Buffers audio into utterances, transcribes each | Traditional pipeline |

##### 4. Latency Reduction Techniques
- **Chunked inference**: Process overlapping windows (e.g., 30s sliding window)
- **Conditioning on previous text**: Whisper can use past context
- **On-device models**: Run locally to avoid network round-trip

#### The "Trick" for True Real-Time

The main challenge: **ASR models are typically designed for complete utterances**, not partial audio. Solutions:

1. **Sliding window with overlap**: Keep last N seconds, transcribe repeatedly
2. **Endpointing**: Detect natural pauses to commit finalized text
3. **Two-pass**: Fast first pass for display, refined second pass for final
4. **Streaming architectures**: RNN-T, CTC models that output tokens incrementally

---

## Question 2: any discussion that happens has to be documented

### Clarification Questions

1. **Are you documenting *this* discussion?** Should I summarize our conversation and append it to `docs/DECISIONS.md` or `docs/WORKLOG_TICKETS.md`?

2. **Or are you stating EchoPanel's core value proposition?** That the app must ensure any spoken discussion gets automatically documented?

3. **Scope for the app:** Are you targeting:
   - Meeting documentation (auto-generate meeting notes)
   - Personal voice memos/notes
   - Accessibility (live captions)
   - All of the above?

#### Analysis of Project Structure

Looking at the project structure, there is:
- `server/` — likely the FastAPI backend for transcription
- `macapp/` — the macOS menu bar capture client
- `docs/audit/` and `docs/DECISIONS.md` — documentation patterns

#### Key Architectural Question

**When does "discussion" start/stop for documentation purposes?**

This typically requires:
- **VAD (Voice Activity Detection)** — to detect when someone starts/stops speaking
- **Session management** — to chunk continuous audio into logical "discussions"
- **Persistence** — where documented transcripts live (local files, cloud, etc.)

---

## Action: Documentation of This Discussion

The user requested: *"everything in a new file starting with my question till your answers"*

This file documents the conversation from the initial question about real-time transcription apps through the documentation requirement clarification.
