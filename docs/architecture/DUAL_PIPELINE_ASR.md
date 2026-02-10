# Dual-Pipeline ASR Architecture

**Date**: 2026-02-10  
**Status**: Architecture Specification  
**Ticket**: TCK-20260210-005, TCK-20260210-006  
**Priority**: P1

---

## 1. Goals and Non-Goals

### Goals
- **Realtime pipeline**: Low-latency transcription for immediate UI feedback; allowed to degrade under load
- **Offline pipeline**: High-accuracy canonical transcript produced after session; must complete reliably
- **Honest UI**: Never claim "streaming" without explicit backend acknowledgment

### Non-Goals
- Realtime pipeline is NOT required to be lossless (frame dropping acceptable with visibility)
- Offline pipeline does NOT need to be fast (minutes acceptable)
- Single merged audio stream is NOT required (parallel capture preferred)

---

## 2. Pipeline Contracts

### 2.1 Realtime Pipeline Contract

**Input**: Chunked PCM audio (16kHz, 16-bit, mono)  
**Output**: Partial transcript segments with {timestamp, confidence, is_final}

**Required Behaviors**:
1. **ACK on ready**: Emit `status: "streaming"` ONLY when ASR is initialized and ready to ingest audio
2. **Periodic metrics**: Emit metrics payload at 1Hz containing:
   - `queue_depth` / `queue_max`
   - `dropped_chunks_total` / `dropped_chunks_last_10s`
   - `avg_infer_ms_per_chunk`
   - `realtime_factor` (processing_time / audio_time)
   - `sources_active`: ["mic", "system"]
   - `provider`: "faster_whisper" | "voxtral" | ...
3. **Degrade gracefully**: When overloaded, follow Backpressure Policy (Section 5)

**State Machine** (client perspective):
```
idle → starting → streaming → [buffering | overloaded] → stopping → complete
  ↑                    ↓
  └──────────────── error
```

### 2.2 Offline Pipeline Contract

**Input**: Full session recording per source (raw PCM or WAV)  
**Output**: Final canonical transcript with:
- Stable segment IDs
- Precise timestamps
- Speaker labels (if diarization enabled)
- Confidence scores

**Required Behaviors**:
1. **Must complete**: Even if realtime pipeline dropped frames or failed
2. **Canonical**: This transcript is source of truth for exports and search
3. **Deterministic**: Same input must produce same output (stable model, no temperature)

---

## 3. Capture Topology

### 3.1 Always Parallel Capture

Always record mic and system audio into **separate files**.

```
┌─────────────┐     ┌─────────────┐
│ System Audio│     │   Mic Audio │
│  (PCM 16k)  │     │  (PCM 16k)  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ system.raw   │    │  mic.raw     │
│ (for offline)│    │ (for offline)│
└──────────────┘    └──────────────┘
```

**Rationale**:
- Clean separation for speaker attribution
- Enables per-source processing
- Simpler than mixed-source diarization

### 3.2 Conditional Parallel ASR

Realtime ASR can be:

| Mode | Streams | When to Use |
|------|---------|-------------|
| **Single** (default) | System only | Conservative, works on all hardware |
| **Adaptive** | System + Mic (if metrics allow) | Best UX, degrades gracefully |
| **Dual** | System + Mic (always) | Only if compute verified sufficient |

**Adaptive Policy**:
1. Start with both system + mic ASR
2. If `realtime_factor > 1.0` or `queue_fill > 0.85`:
   - Pause ASR for secondary stream (mic)
   - Continue recording mic for offline processing
   - Surface "Listening (System only)" in UI
3. Resume dual ASR when metrics recover

---

## 4. Timestamp Clock Invariants

**Critical for merge correctness**: All timestamps must use the **same monotonic clock**.

### Requirements

1. **Single clock source**: Use `CACurrentMediaTime()` (mach_absolute_time) on macOS
2. **Session anchor**: Record `session_start_time` at moment of user "Start"
3. **Relative timestamps**: All audio chunks and transcript segments use delta from session_start
4. **Source synchronization**: Both mic and system streams use same clock domain

### Merge Alignment

When combining realtime + offline transcripts:
```
for offline_segment in offline_transcript:
    # Find matching realtime window
    window_start = offline_segment.t0 - 0.5s
    window_end = offline_segment.t1 + 0.5s
    
    rt_candidates = realtime_segments.where(t0 >= window_start, t1 <= window_end)
    
    if text_similarity(offline_segment.text, rt_candidates.text) > 0.8:
        # Timestamps align, preserve offline (more accurate)
        use_offline_segment()
    else:
        # Significant difference or no match
        # Use offline text but note discrepancy in logs
        use_offline_segment_with_note()
```

---

## 5. Backpressure Policy

Deterministic degradation ladder to prevent "UI lies and silent drops".

### Ladder (in order of application)

| Level | Trigger | Action | UI State |
|-------|---------|--------|----------|
| 0 | Normal | VAD enabled (default) | Listening (green) |
| 1 | `queue_fill > 0.70` | Show metrics | Listening (green) |
| 2 | `queue_fill > 0.85` OR `realtime_factor > 1.0` | Emit backpressure warning | Buffering (yellow) |
| 3 | `queue_fill > 0.95` | Pause capture OR drop-oldest chunks | Overloaded (red) |
| 4 | Sustained overload > 5s | Disable secondary source (mic) | Overloaded (System only) |
| 5 | Still overloaded | Stop realtime ASR | "Live paused; offline transcript will be generated" |

### Drop Policy (when dropping required)

- **Policy**: Drop oldest chunks, keep newest
- **Rationale**: User cares about "what's being said now", not 2-minute backlog
- **Tracking**: Count drops per source, surface in UI

### Pause vs Drop Decision

| Scenario | Action |
|----------|--------|
| Can control capture rate | Pause capture, resume when recovered |
| Cannot control (external source) | Drop-oldest with visibility |

---

## 6. Merge Strategies (Post-Session)

Three explicit modes for combining realtime + offline:

### 6.1 Replace (Simple)
- Discard realtime transcript entirely
- Use offline as canonical
- **Use when**: User doesn't need live annotations

### 6.2 Smart Merge (Default)
- Offline is source of truth for text accuracy
- Preserve realtime segments that have user pins/notes
- Align by timestamp windows

**Algorithm**:
```
for offline_seg in offline_segments:
    rt_match = find_realtime_by_timestamp(offline_seg.t0, window=0.5s)
    
    if rt_match and rt_match.has_user_pins():
        # Preserve user context from realtime
        merged_seg = offline_seg.copy()
        merged_seg.pins = rt_match.pins
        merged_seg.source = "merged"
    else:
        # Use offline (more accurate)
        merged_seg = offline_seg
```

### 6.3 Hybrid (Advanced)
- Realtime: Action items, quick notes during meeting
- Offline: Final transcript, speaker labels, diarization
- **Use when**: User took notes on realtime but wants offline accuracy for record

---

## 7. Benchmark Protocol

Before claiming any performance numbers, run this protocol.

### 7.1 Test Setup

**Hardware**: Target deployment machine (e.g., M1 MacBook Air 8GB)  
**Audio**: 10-minute test file with:
- 60% speech, 40% silence (natural meeting)
- Both system + mic sources active
- Various speakers, overlapping speech

### 7.2 Metrics to Collect

| Metric | How | Target |
|--------|-----|--------|
| `realtime_factor` | avg(processing_time / audio_duration) | < 1.0 |
| `max_latency` | max(chunk_emit_time - chunk_capture_time) | < 3s |
| `dropped_chunks` | server count | 0 |
| `ui_state_accuracy` | % time UI matches backend state | 100% |
| `offline_completion` | % sessions producing final transcript | 100% |

### 7.3 Load Testing

1. **Normal**: 10min meeting, single source
2. **Heavy**: 10min meeting, both sources, continuous speech
3. **Stress**: 30min meeting, both sources, rapid speaker changes

### 7.4 Current Claims Status

| Claim | Source | Status | Action |
|-------|--------|--------|--------|
| Voxtral <200ms latency | Mistral announcement | Vendor claim | Must benchmark locally |
| Whisper large-v3 2.5% WER | OpenAI benchmarks | Vendor claim | Must benchmark locally |
| faster-whisper base 8% WER | Community reports | Unverified | Must benchmark locally |
| Silero VAD 0.5ms inference | Silero docs | Vendor claim | Acceptable (fast enough) |

**Policy**: All latency/accuracy numbers in documentation must be labeled as:
- "[Vendor: X]" for unbenchmarked claims
- "[Measured: Y]" for locally verified

---

## 8. Provider Options

### 8.1 Realtime Providers

| Provider | Type | When to Use | Status |
|----------|------|-------------|--------|
| faster-whisper base | Local CPU | Default, works everywhere | Implemented |
| faster-whisper small | Local CPU | Better accuracy, more RAM | Available |
| Voxtral Realtime 4B | Local GPU/Apple Silicon | If benchmark shows <1.0 realtime_factor | TBD (requires validation) |
| whisper.cpp Metal | Local Apple Silicon | If faster than faster-whisper | TBD |

### 8.2 Offline Providers

| Provider | Type | When to Use | Status |
|----------|------|-------------|--------|
| faster-whisper large-v3 | Local | Default offline, privacy-first | Available |
| OpenAI Whisper API | Cloud (opt-in) | If user provides API key | Not implemented |
| Voxtral Mini Transcribe V2 | Cloud (opt-in) | If user provides API key | Not implemented |

---

## 9. Implementation Phases

### PR1: Truthful UI + Handshake
- Add `.starting` state
- Wait for `status: "streaming"` ACK before showing Listening
- 5s timeout to error if no ACK
- Track `startAttemptId` to ignore late messages

### PR2: Server Metrics
- Emit `status: "streaming"` on session start ready
- Emit metrics payload at 1Hz
- Include queue depth, drops, realtime_factor

### PR3: Backpressure Policy
- Implement degradation ladder
- Add UI states: Buffering, Overloaded
- Surface drop counts to user

### PR4: Parallel Recording
- Write raw PCM to disk alongside streaming
- Per-source files
- Retention policy (default 7 days)

### PR5: Offline Pipeline
- Post-session ASR with larger model
- Produce canonical transcript
- Store alongside realtime

### PR6: Merge & Export
- Implement merge strategies
- Settings UI for provider selection
- Export options (realtime only, offline only, merged)

---

## 10. Retention and Privacy

### Storage Math
- 1 hour meeting = ~115 MB PCM (16kHz, 16-bit, mono, per source)
- 10 meetings/week = ~1.1 GB/week
- Typical user: ~5 GB/month

### Retention Policy
- Raw PCM: 7 days default (configurable)
- Realtime transcripts: 30 days
- Offline transcripts: Permanent
- Final merged exports: Permanent

### Privacy
- **Default**: All processing local (no audio leaves device)
- **Opt-in cloud**: User provides own API key (OpenAI, Mistral)
- **No phone-home**: Metrics are local-only unless user explicitly enables telemetry

---

## 11. Related Documents

- `docs/DECISIONS.md` — LLM and commercialization decisions
- `docs/GAPS_ANALYSIS_2026-02.md` — Identified system gaps
- `docs/ASR_MODEL_RESEARCH_2026-02.md` — Model comparison (vendor claims noted)
- `docs/VOXTRAL_RESEARCH_2026-02.md` — Voxtral-specific research
- `docs/WORKLOG_TICKETS.md` — TCK-20260210-005, TCK-20260210-006

---

## 12. Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-02-10 | Dual-pipeline architecture | Realtime vs accuracy trade-off unavoidable |
| 2026-02-10 | Parallel capture always | Clean separation, enables per-source processing |
| 2026-02-10 | Adaptive realtime ASR | Single-stream default, dual when metrics allow |
| 2026-02-10 | Offline is canonical | Realtime is advisory only |
| 2026-02-10 | Smart merge default | Preserves user context + uses best accuracy |
| 2026-02-10 | Drop-oldest backpressure | User cares about now, not backlog |

---

*End of architecture specification*
