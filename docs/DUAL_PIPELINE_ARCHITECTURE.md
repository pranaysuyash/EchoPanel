# Dual-Pipeline Audio Architecture

**Date**: 2026-02-10  
**Status**: Architecture Proposal  
**Ticket**: TCK-20260210-005  
**Priority**: P1

---

## 1. Executive Summary

EchoPanel currently uses a single real-time streaming ASR pipeline that compromises accuracy for speed. This proposal introduces a **dual-pipeline architecture**:

- **Pipeline A (Real-time)**: Fast, chunked streaming for immediate UI feedback
- **Pipeline B (Post-process)**: High-quality full recording processed after session end

Users get both immediate responsiveness and premium transcript quality.

---

## 2. Problem Statement

### Current State (Single Pipeline)
```
Audio Capture → WebSocket → faster-whisper (base) → UI
                    ↓
            Backpressure when slow
            Frame dropping (3,800+ observed)
            UI shows "Listening" but not streaming
```

**Issues:**
- Real-time constraint forces small, fast models (lower accuracy)
- No time for diarization, advanced NER, or LLM analysis
- Backpressure causes silent failures
- Users see "Listening" but get no transcript

### Target State (Dual Pipeline)
```
                    ┌─→ Pipeline A: Real-time ─→ Live UI
Audio Capture ──────┤     (fast, draft quality)
                    │
                    └─→ Pipeline B: Recording ─→ Post-process ─→ Final Output
                          (full quality, diarization, LLM)
```

---

## 3. Architecture

### 3.1 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AUDIO CAPTURE LAYER                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │  System Audio   │  │   Microphone    │  │    Raw PCM Stream       │  │
│  │  (ScreenCapture)│  │   (AVAudioEngine)│  │    16kHz 16-bit mono   │  │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────────────┘  │
│           │                    │                    │                    │
│           └────────────────────┴────────────────────┘                    │
│                              │                                         │
│                              ▼                                         │
│              ┌───────────────────────────────┐                         │
│              │     DUAL OUTPUT SPLITTER      │                         │
│              │   (one input → two outputs)   │                         │
│              └───────────────┬───────────────┘                         │
│                              │                                         │
│              ┌───────────────┴───────────────┐                         │
│              ▼                               ▼                         │
│    ┌─────────────────────┐      ┌─────────────────────┐                │
│    │  PIPELINE A: FAST   │      │  PIPELINE B: BEST   │                │
│    │  (Real-time)        │      │  (Post-process)     │                │
│    ├─────────────────────┤      ├─────────────────────┤                │
│    │ • Chunked streaming │      │ • Full recording    │                │
│    │ • ~2-4s latency     │      │ • Process at end    │                │
│    │ • faster-whisper    │      │ • Whisper API or    │                │
│    │   base.en / small   │      │   large-v3-turbo    │                │
│    │ • Keyword NER       │      │ • GLiNER NER        │                │
│    │ • Immediate UI      │      │ • Native diarization│                │
│    └──────────┬──────────┘      └──────────┬──────────┘                │
│               │                            │                           │
│               ▼                            ▼                           │
│    ┌─────────────────────┐      ┌─────────────────────┐                │
│    │  Live Transcript    │      │  Final Transcript   │                │
│    │  (draft quality)    │      │  (premium quality)  │                │
│    │                     │      │                     │                │
│    │ During meeting:     │      │ After meeting:      │                │
│    │ • Quick reference   │      │ • Permanent record  │                │
│    │ • Action items      │      │ • Speaker labels    │                │
│    │ • Real-time alerts  │      │ • Better accuracy   │                │
│    └─────────────────────┘      └─────────────────────┘                │
│               │                            │                           │
│               └──────────────┬─────────────┘                           │
│                              ▼                                         │
│              ┌───────────────────────────────┐                         │
│              │     MERGE/COMBINE LAYER       │                         │
│              │   (User-selectable strategy)  │                         │
│              └───────────────────────────────┘                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Pipeline A: Real-Time (Fast)

**Purpose:** Immediate feedback during meeting  
**Constraints:** <2s latency, local execution  

| Model | Latency | WER | RAM | Use Case |
|-------|---------|-----|-----|----------|
| faster-whisper tiny.en | ~300ms | ~12% | ~100MB | 8GB machines |
| faster-whisper base.en | ~500ms | ~8% | ~200MB | Current default |
| Voxtral Realtime 4B | <200ms | ~4% | ~4GB | 16GB+ machines |
| whisper.cpp (Metal) | ~400ms | ~8% | ~200MB | Apple Silicon |

**Features:**
- 2-second chunks (reduced from 4s)
- Silero VAD pre-filter (skip silent audio)
- Basic keyword NER (actions, decisions)
- Immediate UI updates

### 3.3 Pipeline B: Post-Processing (Best)

**Purpose:** Permanent high-quality transcript  
**Trigger:** Session end (user clicks "Stop")  
**Duration:** 30s - 2min depending on length  

**Decision:** Local-first as per `docs/DECISIONS.md` — user's own API key is opt-in only.

| Provider | WER | Cost | Diarization | Best For | Status |
|----------|-----|------|-------------|----------|--------|
| **local large-v3-turbo** | ~3% | Free | Via pyannote | **Default** | ✅ Local |
| **local large-v3 + GLiNER** | ~2.5% | Free | GLiNER + pyannote | Best local | ✅ Local |
| OpenAI Whisper API | ~2.5% | $0.006/min | Via pyannote | User opt-in | ☁️ Cloud |
| Voxtral Mini Transcribe V2 | ~4% | $0.003/min | Native | User opt-in | ☁️ Cloud |

> **Note:** Cloud APIs are opt-in only. User must provide their own API key. Default stack is fully local.

**Features:**
- Full audio file (not chunked)
- Larger ASR model (better accuracy)
- Native diarization (speaker labels)
- GLiNER semantic NER
- LLM-powered summary (if API key configured)

---

## 4. Storage Architecture

```
Session: 2026-02-10_Meeting_with_Team
│
├── realtime/
│   ├── chunks/              # 2s audio chunks (temp)
│   ├── transcript.json      # Live transcript
│   └── entities.json        # Real-time entities
│
├── recording/
│   ├── session.raw.pcm      # Full raw audio
│   ├── session.wav          # Converted WAV
│   └── transcript.final.json # Post-processed
│
└── merged/
    ├── transcript.merged.json  # Combined output
    └── export.md               # User-facing export
```

**Storage Requirements:**
- 1 hour meeting = ~115 MB PCM (16kHz 16-bit mono)
- 10 meetings/week = ~1.1 GB/week
- Auto-cleanup: Raw audio 30 days, transcripts permanent

---

## 5. Merge Strategies

### 5.1 Strategy 1: Replace (Simple)
- Discard real-time transcript
- Use post-processed only
- **Pros:** Clean, single source
- **Cons:** Lose real-time user annotations

### 5.2 Strategy 2: Smart Merge (Recommended)
```python
for segment in post_process_segments:
    rt_match = find_by_timestamp(segment.t0, segment.t1)
    
    if rt_match and similarity(segment.text, rt_match.text) < 0.8:
        # Significant difference - trust post-process (more accurate)
        use_post_process(segment)
    elif rt_match.has_user_pins():
        # Keep real-time to preserve user context
        use_realtime(rt_match)
    else:
        # Similar - use post-process for consistency
        use_post_process(segment)
```

**Rules:**
- Post-process text takes precedence when different
- Preserve real-time segments with user pins/notes
- Maintain timeline continuity

### 5.3 Strategy 3: Hybrid (Advanced)
- Real-time: Action items, quick reference
- Post-process: Speaker labels, final transcript
- **Use case:** "I captured action items live, but need speaker diarization"

---

## 6. Implementation Phases

### Phase 1: Parallel Recording (Week 1)
**Goal:** Capture raw audio alongside streaming

**Files to modify:**
- `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
- New: `macapp/MeetingListenerApp/Sources/RawAudioRecorder.swift`

**Changes:**
```swift
// AudioCaptureManager
func startCapture() async throws {
    // Existing: Start streaming
    try await startStreaming()
    
    // New: Start raw recording
    rawAudioRecorder.start(sessionID: sessionID)
}

func onPCMFrame(_ frame: Data, source: String) {
    // Existing: Send to WebSocket
    streamer.sendPCMFrame(frame, source: source)
    
    // New: Write to file
    rawAudioRecorder.append(frame, source: source)
}
```

**Acceptance:**
- [ ] Raw PCM file created on session start
- [ ] File contains all audio from both sources
- [ ] File deleted after post-processing (configurable)

### Phase 2: Post-Processing Pipeline (Week 2-3)
**Goal:** Process full recording after session

**New files:**
- `server/services/post_process_asr.py`
- `server/services/post_process_pipeline.py`

**Providers to implement:**
1. OpenAI Whisper API
2. Voxtral Mini Transcribe V2
3. Local large-v3-turbo

**Flow:**
```python
async def post_process(session_id: str, audio_path: Path):
    # 1. Convert PCM to WAV
    wav_path = await convert_to_wav(audio_path)
    
    # 2. Run ASR
    transcript = await asr_provider.transcribe(wav_path)
    
    # 3. Diarization
    speakers = await diarizer.process(wav_path, transcript)
    
    # 4. NER
    entities = await gliner.extract(transcript)
    
    # 5. Save results
    save_final_transcript(session_id, transcript, speakers, entities)
```

**UI Changes:**
- Progress indicator during post-processing
- "Processing final transcript..." banner
- Cancel button (skip post-processing)

### Phase 3: Merge & Export (Week 4)
**Goal:** Combine pipelines, user choice

**Files to modify:**
- `macapp/MeetingListenerApp/Sources/SessionStore.swift`
- `macapp/MeetingListenerApp/Sources/SummaryView.swift`

**Settings:**
```swift
enum MergeStrategy: String, CaseIterable {
    case replace = "Use final transcript only"
    case smartMerge = "Smart merge (recommended)"
    case hybrid = "Hybrid: Real-time + diarization"
}

@AppStorage("postProcessProvider") var provider: PostProcessProvider = .localLargeV3
@AppStorage("mergeStrategy") var strategy: MergeStrategy = .smartMerge
```

**Export options:**
- Real-time only
- Final only  
- Merged (default)
- Both (side-by-side comparison)

### Phase 4: Advanced Features (Future)
- **Offline queue:** Post-process when connection available
- **Multi-model voting:** Combine 3+ ASR outputs
- **Custom vocabulary:** Fine-tune on user's domain terms

---

## 7. Configuration

### Environment Variables
```bash
# Pipeline selection
ECHOPANEL_ENABLE_DUAL_PIPELINE=1          # Enable parallel recording
ECHOPANEL_POST_PROCESS_PROVIDER=local     # local | openai | voxtral
ECHOPANEL_MERGE_STRATEGY=smart            # replace | smart | hybrid

# Post-processing options
# Optional: Cloud post-processing (opt-in only)
ECHOPANEL_OPENAI_API_KEY=sk-xxx           # User's own key for Whisper API
ECHOPANEL_MISTRAL_API_KEY=xxx             # User's own key for Voxtral V2
ECHOPANEL_KEEP_RAW_AUDIO_DAYS=7           # Retention policy

# Real-time options (existing)
ECHOPANEL_WHISPER_MODEL=base.en           # tiny | base | small
ECHOPANEL_ASR_CHUNK_SECONDS=2             # Reduced from 4
ECHOPANEL_ASR_VAD=1                       # Enable Silero VAD
```

### macOS Settings UI
```
┌────────────────────────────────────────┐
│ Audio Processing                       │
├────────────────────────────────────────┤
│ [✓] Enable dual-pipeline capture       │
│                                        │
│ Real-time ASR: [faster-whisper base.en]│
│ Post-process:  [local large-v3-turbo ▼] │
│                                        │
│ Merge strategy:                        │
│ ○ Use final transcript only            │
│ ● Smart merge (recommended)            │
│ ○ Hybrid: Live + diarization           │
│                                        │
│ Storage: Keep raw audio for [7] days   │
└────────────────────────────────────────┘
```

---

## 8. Cost Analysis

### Scenario: 10 hours/week of meetings

| Mode | Real-time | Post-process | Total/month | Privacy |
|------|-----------|--------------|-------------|---------|
| **Local-only (Default)** | faster-whisper (free) | large-v3-turbo (free) | **$0** | ✅ Audio never leaves Mac |
| **Hybrid opt-in** | faster-whisper (free) | Whisper API ($0.006/min) | **~$12** | ☁️ Audio sent to API |

**Default:** Local-only (fully offline)  
**Opt-in:** User adds their own OpenAI/Mistral API key for cloud post-processing

---

## 9. Trade-offs

| Aspect | Pros | Cons |
|--------|------|------|
| **Storage** | Re-processable, audit trail | ~115MB/hour disk usage |
| **Latency** | Real-time feedback | Two transcripts to manage |
| **Accuracy** | Best possible quality | Delayed final results |
| **Cost** | Free by default, paid opt-in | Cloud APIs add up |
| **Complexity** | Best of both worlds | More code paths |
| **Privacy** | ✅ Local by default | ☁️ Cloud only with user opt-in |

---

## 10. Open Questions

1. **Sync strategy:** How to align timestamps between pipelines if clocks drift?
2. **Partial post-process:** Allow post-processing first 5 minutes while meeting continues?
3. **Quality gates:** Auto-reject post-process if confidence too low?
4. **Storage encryption:** Encrypt raw audio at rest?
5. **Multi-device:** Merge transcripts from phone + laptop of same meeting?

---

## 11. Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Real-time WER | ~10% | ~8% | LibriSpeech test |
| Final WER | N/A | ~3% | Same test set |
| Post-process time | N/A | <2x meeting duration | 1h meeting <2min processing |
| Frame dropping | 3,800+ | 0 | Server logs |
| User satisfaction | Unknown | >4.0/5.0 | In-app survey |

---

## 12. Related Documents

- `docs/GAPS_ANALYSIS_2026-02.md` — Gap 2 (VAD), Gap 3 (streaming ASR)
- `docs/ASR_MODEL_RESEARCH_2026-02.md` — Model comparison matrix
- `docs/VOXTRAL_RESEARCH_2026-02.md` — Voxtral Realtime architecture
- `docs/PIPELINE_EVOLUTION_2026-02.md` — NER and RAG roadmap
- Ticket: TCK-20260210-005 — This architecture proposal

---

## 13. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-10 | Dual-pipeline architecture | Solves real-time vs accuracy trade-off |
| 2026-02-10 | Smart merge as default | Preserves user context + uses best ASR |
| 2026-02-10 | 7-day raw audio retention | Balance between re-processability and storage |
| 2026-02-10 | Phase 1-4 implementation | Incremental delivery, user feedback between phases |

---

*End of architecture document*
