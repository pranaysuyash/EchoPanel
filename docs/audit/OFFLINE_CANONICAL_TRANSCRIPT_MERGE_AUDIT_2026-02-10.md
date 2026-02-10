# EchoPanel Offline Canonical Transcript + Merge/Reconciliation Audit

**Date:** 2026-02-10  
**Type:** AUDIT  
**Scope:** Offline transcript pipeline, merge/reconciliation, notes/pins preservation, job orchestration  
**Owner:** Agent (Offline Canonical Transcript Architect)

---

## Executive Summary

1. **No offline canonical transcript pipeline exists today.** The system relies entirely on real-time streaming ASR with session-end diarization applied to the realtime transcript (`server/api/ws_live_listener.py:436-448`).

2. **Parallel recording is partially implemented.** Mic and system audio are captured separately in the macOS app (`AppState.swift:184-255`), streamed via separate WebSocket queues (`ws_live_listener.py:42, 223-227`), but there is no persistent raw audio storage for offline reprocessing.

3. **No stable segment IDs exist.** Transcript segments use ephemeral array indices and UUIDs assigned client-side (`Models.swift:25: let id = UUID()`), with no content-addressable or deterministic ID scheme.

4. **Pins/notes/bookmarks exist only in HTML prototypes.** The native macOS app does not yet implement user-created pins or notes that would need preservation across realtime→offline transitions.

5. **Diarization runs at session-end only,** on buffered PCM data (`ws_live_listener.py:78-107`), using pyannote.audio with 30-minute max retention (`diarization_max_bytes` at line 329).

6. **No job queue or orchestration exists.** Offline processing is entirely absent; all processing is synchronous during the WebSocket session.

7. **Exports use realtime draft data.** JSON/Markdown exports from `AppState.swift:687-718` use the current transcript state, with no concept of a "canonical" post-processed version.

8. **Session storage is append-only JSONL.** Transcript events are persisted to `transcript.jsonl` (`SessionStore.swift:72-74, 111-121`) but this is the realtime stream, not a canonical offline result.

9. **No timestamp drift compensation exists.** Realtime timestamps are derived from processed_samples in the ASR provider (`provider_faster_whisper.py:94-126`) with no anchor to wall-clock or NTP.

10. **Recovery mechanism exists for crashes.** `SessionStore.swift:159-206` implements crash recovery markers, but this is for resuming realtime capture, not for offline processing.

---

## Files Inspected

**Server (Python/FastAPI):**
- `server/main.py` (lines 1-94)
- `server/api/ws_live_listener.py` (lines 1-519)
- `server/api/documents.py` (lines 1-107)
- `server/services/asr_providers.py` (lines 1-150)
- `server/services/asr_stream.py` (lines 1-91)
- `server/services/provider_faster_whisper.py` (lines 1-239)
- `server/services/diarization.py` (lines 1-214)
- `server/services/analysis_stream.py` (lines 1-416)
- `server/services/rag_store.py` (lines 1-279)

**macOS App (Swift):**
- `macapp/MeetingListenerApp/Sources/AppState.swift` (lines 1-1370)
- `macapp/MeetingListenerApp/Sources/SessionStore.swift` (lines 1-327)
- `macapp/MeetingListenerApp/Sources/Models.swift` (lines 1-84)
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` (lines 1-320)
- `macapp/MeetingListenerApp/Sources/SidePanelController.swift` (lines 1-125)

**Tests:**
- `tests/test_ws_live_listener.py` (lines 1-74)

**Documentation:**
- `docs/STORAGE_AND_EXPORTS.md` (lines 1-61)
- `docs/WORKLOG_TICKETS.md`
- `docs/DUAL_PIPELINE_ARCHITECTURE.md`
- `docs/WS_CONTRACT.md`

**HTML Prototypes (Data Model Reference):**
- `echopanel.html` (pins UI references, lines 1115-1893)
- `echopanel_roll.html` (pins state tracking, line 760)
- `echopanel_sidepanel.html` (pins surface, lines 804-856)

---

## Current Pipeline Inventory

### Recording Subsystem (Observed)

**Location:** `macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`, `MicrophoneCaptureManager.swift`

| Component | Status | Location |
|-----------|--------|----------|
| System audio capture | ✅ Implemented | `AudioCaptureManager.swift` |
| Microphone capture | ✅ Implemented | `MicrophoneCaptureManager.swift` |
| Parallel dual-source | ✅ Implemented | `AppState.swift:499-520` |
| Raw audio persistence | ❌ Missing | Only debug dump exists (`ws_live_listener.py:177-220`) |
| Shared monotonic clock | ❌ Missing | Each source uses independent timestamps |
| Source tagging | ✅ Implemented | `WebSocketStreamer.swift:84-96` |

### Realtime Streaming Pipeline (Observed)

**Location:** `server/api/ws_live_listener.py`

```
WebSocket Message Flow:
1. Client sends "start" with session_id
2. Client sends "audio" frames with source tag ("system" | "mic")
3. Server queues audio per-source (lines 223-227)
4. ASR tasks process per-source (lines 273-286)
5. Final segments appended to state.transcript (line 283)
6. On "stop": 
   - ASR flush with timeout (lines 411-424)
   - Diarization per-source (lines 437-438)
   - Merge speakers with transcript (lines 446-448)
   - Return final_summary (lines 457-473)
```

### Session Storage (Observed)

**Location:** `macapp/MeetingListenerApp/Sources/SessionStore.swift`

| File | Purpose | Format |
|------|---------|--------|
| `metadata.json` | Session start, audio source, app version | JSON |
| `transcript.jsonl` | Append-only transcript events | JSONL |
| `snapshot.json` | Periodic autosave (30s interval) | JSON |
| `final_snapshot.json` | Final state at session end | JSON |
| `recovery.json` | Crash recovery marker | JSON |

### Export System (Observed)

**Location:** `macapp/MeetingListenerApp/Sources/AppState.swift:687-718`

| Format | Data Source | Canonical? |
|--------|-------------|------------|
| Markdown | `renderLiveMarkdown()` or `finalSummaryMarkdown` | ❌ Realtime only |
| JSON | `exportPayload()` - current transcript state | ❌ Realtime only |
| Debug Bundle | Session + server logs | ❌ Diagnostic only |

### Analysis/Cards Extraction (Observed)

**Location:** `server/services/analysis_stream.py`

- 10-minute sliding window (`ANALYSIS_WINDOW_SECONDS = 600.0`, line 23)
- Keyword-based extraction for actions/decisions/risks (lines 113-151)
- Entity extraction with deduplication (lines 178-365)
- **No stable IDs** for cards/entities across reprocessing

---

## Canonical Transcript Spec (Proposed)

### JSON Schema

```json
{
  "schema_version": "2.0",
  "canonical_transcript": {
    "session_id": "uuid-v4-string",
    "created_at": "2026-02-10T23:38:22.901461+05:30",
    "sources": ["mic", "system"],
    
    "provenance": {
      "pipeline_version": "2.0.0",
      "asr_provider": "faster_whisper",
      "asr_model": "large-v3-turbo",
      "diarization_model": "pyannote/speaker-diarization-3.1",
      "vad_used": true,
      "processed_at": "2026-02-10T23:45:00Z"
    },
    
    "segments": [
      {
        "segment_id": "sha256:content-hash-based",
        "source": "mic",
        "t0": 0.0,
        "t1": 4.32,
        "speaker": "Speaker 1",
        "text": "This is the transcribed text",
        "confidence": 0.94,
        "tokens": [
          {"text": "This", "t0": 0.0, "t1": 0.18, "confidence": 0.98},
          {"text": "is", "t0": 0.18, "t1": 0.24, "confidence": 0.96}
        ],
        "word_count": 5,
        "char_count": 28
      }
    ],
    
    "speaker_map": {
      "SPEAKER_00": "Speaker 1",
      "SPEAKER_01": "Speaker 2"
    },
    
    "mappings": {
      "realtime_to_canonical": {
        "description": "Maps ephemeral realtime segment indices to canonical segment_ids",
        "mapping": [
          {"realtime_idx": 0, "canonical_id": "sha256:abc...", "match_confidence": 0.98}
        ]
      }
    },
    
    "artifacts": {
      "raw_audio_paths": {
        "mic": "/path/to/mic.raw",
        "system": "/path/to/system.raw"
      },
      "intermediate_asr_path": "/path/to/asr_result.json",
      "diarization_path": "/path/to/diarization.json"
    }
  }
}
```

### Invariants

| Invariant | Enforcement | Rationale |
|-----------|-------------|-----------|
| **segment_id stability** | Content-addressable SHA256 of (source, t0, t1, normalized_text) | Allows reprocessing detection of unchanged segments |
| **timestamp monotonicity** | Validation: `t1 > t0` for all segments; `t0(n+1) >= t1(n)` per source | Prevents temporal paradoxes |
| **canonical derivation** | Must only use raw_audio + provenance chain | Ensures no circular dependencies |
| **source isolation** | Each segment has exactly one source | Simplifies diarization mapping |
| **text immutability** | Once written, segment text never changes | Enables stable pin/note references |

### Segment ID Generation

```python
def generate_segment_id(source: str, t0: float, t1: float, text: str) -> str:
    """Content-addressable segment ID for stability across reprocessing."""
    normalized_text = text.lower().strip().replace("  ", " ")
    content = f"{source}|{t0:.3f}|{t1:.3f}|{normalized_text}"
    hash_bytes = hashlib.sha256(content.encode("utf-8")).digest()
    return f"seg_{hash_bytes[:16].hex()}"
```

---

## Merge/Reconciliation Strategies

### Strategy 1: Replace (Default Safe)

**When to use:** User wants maximum accuracy; accepts that realtime draft may have been wrong.

**Algorithm:**
```
1. Generate canonical transcript from raw audio (full offline ASR + diarization)
2. Discard all realtime transcript segments
3. Map user artifacts (pins/notes) by timestamp proximity:
   - For each pin at time T, find canonical segment with t0 <= T <= t1
   - If no exact match, use nearest segment within ±5 seconds
   - Record mapping in canonical_transcript.mappings.pins
4. Return canonical as sole truth
```

**Pros:** Simple, deterministic, highest accuracy  
**Cons:** User may see "jumps" in transcript if realtime was wrong

### Strategy 2: Anchor-Merge (Recommended)

**When to use:** Balance between accuracy and UI continuity.

**Algorithm:**
```
1. Generate canonical transcript from raw audio
2. For each canonical segment:
   a. Find overlapping realtime segment(s) by time window
   b. If text similarity > 0.85 (Levenshtein-based), mark as "confirmed"
   c. If similarity < 0.85, mark as "corrected" with link to realtime
3. Preserve canonical text always (never use realtime text)
4. Map pins/notes:
   a. Primary: time-based anchor (as Strategy 1)
   b. Secondary: text hash fallback for drift compensation
5. Expose "view corrections" UI showing where realtime differed
```

**Pros:** User can see what changed, builds trust  
**Cons:** More complex mapping logic

### Strategy 3: Hybrid View

**When to use:** Power users want both perspectives.

**Algorithm:**
```
1. Store both realtime and canonical transcripts
2. Default view: canonical with "show draft" toggle
3. Exports default to canonical
4. Pin mapping uses canonical as primary, realtime as fallback
5. Provide "diff view" highlighting changes
```

**Pros:** Maximum transparency  
**Cons:** Double storage, complex UI

### Decision Rules Matrix

| Condition | Strategy |
|-----------|----------|
| Realtime confidence > 0.9 AND canonical matches | Silent merge (Strategy 2) |
| Realtime confidence < 0.7 AND canonical differs | Highlight correction (Strategy 2) |
| User explicitly chose "accuracy first" | Replace (Strategy 1) |
| Export requested | Always canonical |
| Pin at timestamp with no canonical segment | Orphan pin with warning |

---

## Notes/Pins Preservation Strategy

### Current State (Observed)

Pins exist **only in HTML prototypes** (`echopanel.html`, `echopanel_roll.html`, `echopanel_sidepanel.html`) with these properties:
- Created via "P" key on focused line
- Stored in `rightModel.pins` array
- Have text content but no stable ID scheme

**Native macOS app:** Pins/notes feature is **not implemented** (as of code inspection).

### Proposed Pin Data Model

```json
{
  "pin": {
    "pin_id": "uuid-v4",
    "session_id": "uuid-v4",
    "created_at": "2026-02-10T23:38:22Z",
    "created_during": "realtime",
    
    "anchor": {
      "type": "time|segment|text",
      "realtime_segment_idx": 12,
      "anchor_timestamp": 45.2,
      "anchor_text_snippet": "ship by Friday",
      "anchor_text_hash": "sha256:..."
    },
    
    "content": {
      "type": "pin|note|highlight|action_item",
      "text": "User's note about this moment",
      "tags": ["urgent", "follow-up"]
    },
    
    "resolved_mapping": {
      "canonical_segment_id": "seg_abc123",
      "canonical_timestamp": 45.1,
      "mapping_confidence": 0.94,
      "mapping_method": "time_overlap|text_similarity|manual"
    },
    
    "status": "resolved|orphan|ambiguous"
  }
}
```

### Resolution Algorithm

```python
def resolve_pin_to_canonical(pin: Pin, canonical: Transcript) -> Resolution:
    """
    Resolve a user pin to the canonical transcript.
    Never delete user data; always preserve with status.
    """
    
    # Strategy 1: Time-based (preferred)
    for seg in canonical.segments:
        if seg.t0 <= pin.anchor.timestamp <= seg.t1:
            return Resolution(
                segment_id=seg.segment_id,
                confidence=1.0,
                method="time_overlap"
            )
    
    # Strategy 2: Text similarity within time window
    candidates = [
        seg for seg in canonical.segments
        if abs(seg.t0 - pin.anchor.timestamp) < 10.0
    ]
    
    if candidates:
        best = max(candidates, 
                   key=lambda s: text_similarity(s.text, pin.anchor.text_snippet))
        if text_similarity(best.text, pin.anchor.text_snippet) > 0.7:
            return Resolution(
                segment_id=best.segment_id,
                confidence=0.8,
                method="text_similarity"
            )
    
    # Strategy 3: Mark as orphan (preserve user data!)
    return Resolution(
        segment_id=None,
        confidence=0.0,
        method="unresolved",
        status="orphan",
        warning="Pin could not be mapped to canonical transcript."
    )
```

### Orphan Pin Handling

Orphan pins must **never** be deleted. UI should:
1. Show orphan pins in a separate "Unmapped Pins" section
2. Allow manual re-attachment to transcript segments
3. Preserve original timestamp and text snippet
4. Include in exports with "unmapped" flag

---

## Failure Modes + Recovery (12+)

| # | Failure Mode | Trigger | User Impact | Detection Signal | Current Behavior | Proposed Behavior | Recovery/Rollback |
|---|--------------|---------|-------------|------------------|------------------|-------------------|-------------------|
| 1 | **ASR timeout during flush** | Slow model, long audio | Missing transcript tail | Log: "ASR flush timed out" | Warning sent, partial transcript | Same + mark for offline reprocess | Auto-queue for offline ASR |
| 2 | **Diarization failure** | Missing HF token, OOM | No speaker labels | Empty diarization_segments | Silent fallback to no speakers | Same + log warning | Retry with smaller chunk |
| 3 | **Realtime timestamp drift** | Clock skew, buffer bloat | Misaligned multi-source | Segment gaps/overlap | None (accepted) | Drift detection alert | Use wall-clock anchors |
| 4 | **WebSocket disconnect mid-session** | Network error | Lost final segments | Connection closed | Attempt reconnect | Queue for offline if reconnect fails | Resume from last ACKed |
| 5 | **Crash during session** | App termination | Lost unsaved data | recovery.json exists | Recovery prompt on restart | Same + incremental snapshot every 10s | Restore from snapshot |
| 6 | **Raw audio corruption** | Disk full, I/O error | Cannot offline process | File read error | N/A (no raw audio storage) | Mark unprocessable, keep realtime | Alert user, preserve realtime |
| 7 | **Offline ASR job crash** | OOM, model error | No canonical transcript | Job failure in queue | N/A | Fallback to realtime as canonical | Manual requeue from UI |
| 8 | **Pin mapping ambiguity** | Text changed significantly | Pin attached to wrong segment | Low similarity score | N/A | Mark ambiguous, prompt user | Manual reattachment |
| 9 | **Concurrent session modification** | Multiple devices | Data loss/conflict | File lock contention | Not supported | Detect and warn | Last-write-wins with log |
| 10 | **Export during processing** | User clicks export early | Incomplete export | Job status != complete | Exports current state | Block or warn "processing" | Retry after completion |
| 11 | **Storage quota exceeded** | Long sessions | Cannot save new sessions | Write error | Error logged | Graceful degradation | Cleanup old sessions |
| 12 | **Diarization model version mismatch** | Model updated | Inconsistent speaker IDs | Model version differs | Not tracked | Include version in canonical | Re-run with consistent model |

---

## Job Orchestration Plan

### Architecture

```
Session End → Job Queue → Worker Pool
                  ↓
    ┌─────────────┼─────────────┐
    ▼             ▼             ▼
 Stage 1      Stage 2      Stage 3
Audio Export  Offline ASR  Diarization
    │             │             │
    └─────────────┴─────────────┘
                  ▼
           Stage 4: Merge + Canonicalize
                  ▼
           Stage 5: Pin Mapping
```

### Job Schema

```python
@dataclass
class PostProcessJob:
    job_id: str  # UUID
    session_id: str
    status: JobStatus  # queued|running|completed|failed|retrying
    stages: Dict[str, StageInfo]
    retry_count: int
    max_retries: int = 3
    created_at: datetime
    updated_at: datetime
    checkpoint: Dict  # Last successful stage state
```

### Idempotency Rules

1. **Audio Export:** Idempotent - same input paths, same output paths
2. **Offline ASR:** Idempotent with segment_id dedup
3. **Diarization:** Idempotent - same input, same output
4. **Merge:** Idempotent - content-addressable segment_ids
5. **Pin Mapping:** NOT idempotent - version pins, map only new

### Progress UI

```swift
@Published var offlineProcessingStatus: OfflineStatus = .notStarted

enum OfflineStatus {
    case notStarted
    case inProgress(stage: String, progress: Double)
    case completed(canonicalTranscript: CanonicalTranscript)
    case failed(stage: String, error: String, retryable: Bool)
}
```

---

## Storage/Retention Plan

### Directory Structure

```
~/Library/Application Support/com.echopanel/
├── sessions/
│   ├── <session_id>/
│   │   ├── metadata.json
│   │   ├── realtime/
│   │   │   ├── transcript.jsonl      # Ephemeral: 30 days
│   │   │   └── snapshot.json
│   │   ├── raw/                       # Retention: 7 days default
│   │   │   ├── mic.raw
│   │   │   └── system.raw
│   │   ├── canonical/                 # Permanent
│   │   │   ├── transcript.json
│   │   │   └── provenance.json
│   │   └── pins/                      # Permanent
│   └── recovery.json
└── cache/
    └── asr_models/
```

### Retention Policies

| Data Type | Default Retention | Configurable |
|-----------|------------------|--------------|
| Raw audio | 7 days | Yes (`ECHOPANEL_RAW_AUDIO_RETENTION_DAYS`) |
| Realtime transcript | 30 days | Yes |
| Canonical transcript | Permanent | No |
| User pins/notes | Permanent | No |
| Debug dumps | 3 days | Yes |

### Size Estimates

| Audio Source | Bitrate | 1 Hour Size |
|--------------|---------|-------------|
| Single (mic OR system) | 256 kbps | ~115 MB |
| Dual (mic + system) | 512 kbps | ~230 MB |
| With 2x redundancy | - | ~460 MB |

---

## Test Plan

### Unit Tests

```python
def test_segment_id_stability():
    """Segment ID must be identical for identical content."""
    seg1 = create_segment(source="mic", t0=1.0, t1=3.0, text="Hello")
    seg2 = create_segment(source="mic", t0=1.0, t1=3.0, text="Hello")
    assert seg1.segment_id == seg2.segment_id

def test_pin_mapping_time_overlap():
    """Pin at T=10s should map to segment covering that time."""
    canonical = load_fixture("clean_speech_canonical.json")
    pin = create_pin(timestamp=10.0, text="test")
    resolution = resolve_pin(pin, canonical)
    assert resolution.method == "time_overlap"

def test_orphan_pin_preservation():
    """Pins that can't be mapped must be preserved."""
    canonical = load_fixture("short_session.json")
    pin = create_pin(timestamp=999.0, text="after end")
    resolution = resolve_pin(pin, canonical)
    assert resolution.status == "orphan"
    assert pin_exists_in_storage(pin.pin_id)
```

### Golden Fixture Tests

| Fixture | Description | Pass Criteria |
|---------|-------------|---------------|
| `clean_speech.wav` | Single speaker, clear audio | WER < 5% vs reference |
| `overlapped_speech.wav` | Two speakers overlapping | Both speakers detected |
| `long_silence.wav` | 30s speech, 60s silence | No hallucinations |
| `drift_simulation.wav` | Intentional clock skew | Drift detected and corrected |
| `mic_system_stereo.wav` | Dual source test | Sources correctly attributed |

---

## Migration Plan

### Phase 1: Backward-Compatible Addition (v0.3)
1. Add `canonical/` subdirectory to session storage
2. Run offline processing in background
3. Use canonical for exports if available, fallback to realtime
4. No breaking changes

### Phase 2: User-Facing Features (v0.4)
1. Add "View corrections" UI
2. Enable pin/notes feature with canonical mapping
3. Migrate existing sessions on first open

### Phase 3: Cleanup (v0.5)
1. Remove legacy realtime-only export paths
2. Enforce canonical for all exports
3. Implement raw audio retention policy

---

## Evidence Log

| Timestamp | Evidence | Interpretation |
|-----------|----------|----------------|
| 2026-02-10 | Inspected `server/api/ws_live_listener.py:310-519` | Observed - realtime-only pipeline, no offline queue |
| 2026-02-10 | Inspected `macapp/MeetingListenerApp/Sources/SessionStore.swift:9-48` | Observed - session storage structure, no raw audio |
| 2026-02-10 | Inspected `server/services/diarization.py:78-107` | Observed - session-end diarization only |
| 2026-02-10 | Searched for "pin" in native app sources | Observed - pins only exist in HTML prototypes |
| 2026-02-10 | Inspected `echopanel.html`, `echopanel_roll.html` | Observed - pins UI defined in prototypes only |

---

## Recommendations

### P0 (Critical Path)
1. Implement raw audio storage for dual-source capture
2. Design canonical transcript schema with stable segment IDs
3. Build job orchestration queue for offline processing

### P1 (High Value)
4. Implement pin/note data model with mapping resolution
5. Build merge/reconciliation UI (Strategy 2: Anchor-Merge)
6. Add timestamp drift detection and compensation

### P2 (Polish)
7. Implement retention policy enforcement
8. Build "view corrections" diff UI
9. Add comprehensive golden fixture tests

---

## Linked Tickets

- Create: `TCK-20260210-002` :: Implement raw audio dual-source storage
- Create: `TCK-20260210-003` :: Design canonical transcript schema v2.0
- Create: `TCK-20260210-004` :: Build offline processing job queue
- Create: `TCK-20260210-005` :: Implement pins/notes preservation system
