# Implementation Plan: Streaming Reliability & Dual-Pipeline

**Date**: 2026-02-10  
**Status**: Ready for Implementation  
**Priority**: P0 (Deployment Blocker)  
**Tickets**: TCK-20260210-004, TCK-20260210-005, TCK-20260210-006

---

## Executive Summary

Fix the "Listening but not streaming" bug through a 6-PR sequence:
1. UI handshake (stop the lie)
2. Server metrics (visibility)
3. VAD default (reduce load)
4. Backpressure (graceful degradation)
5. Parallel recording (offline pipeline)
6. Merge & reconciliation

---

## PR1: UI Handshake + Truthful States

**Goal**: Never show "Listening" without backend ACK

**Files to Modify**:
- `macapp/MeetingListenerApp/Sources/Models.swift` — Add `.starting` state
- `macapp/MeetingListenerApp/Sources/AppState.swift` — Handshake logic, timeout
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelStateLogic.swift` — Status strings

**Changes**:

```swift
// Models.swift
enum SessionState {
    case idle
    case starting          // NEW: Waiting for backend ACK
    case listening
    case finalizing
    case error
}
```

```swift
// AppState.swift
private var startAttemptId: UUID?
private var startTimeoutTask: Task<Void, Never>?

func startSession() {
    sessionState = .starting          // Was: .listening
    startAttemptId = UUID()
    let attempt = startAttemptId
    
    // ... start capture ...
    streamer.connect(sessionID: id)
    
    // 5 second timeout
    startTimeoutTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard let self, self.startAttemptId == attempt else { return }
        
        if self.streamStatus != .streaming {
            self.stopSession()
            self.sessionState = .error
            self.runtimeErrorState = .streaming(detail: "Backend did not start streaming within 5 seconds")
        }
    }
}

// On WebSocket status message
func handleStreamStatus(_ status: StreamStatus, message: String) {
    if status == .streaming && sessionState == .starting {
        startTimeoutTask?.cancel()
        sessionState = .listening
    }
}
```

**UI States**:
| State | Status Pill | Color | User Sees |
|-------|-------------|-------|-----------|
| `.starting` | "Starting..." | Blue | Spinner, "Connecting to backend" |
| `.listening` | "Listening" | Green | Timer running, transcript appears |
| Timeout | "Setup needed" | Red | Error banner with retry button |

**Acceptance Criteria**:
- [ ] Clicking Start shows "Starting..." for up to 5s
- [ ] Only shows "Listening" when backend sends `status: "streaming"`
- [ ] Timeout after 5s shows clear error with retry
- [ ] Late messages from previous attempt ignored (via `startAttemptId`)

**Estimate**: 4-6 hours

---

## PR2: Server Metrics + Deterministic ACK

**Goal**: Backend provides explicit handshake and continuous health visibility

**Files to Modify**:
- `server/api/ws_live_listener.py` — ACK on start, metrics emission
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift` — Parse metrics
- `macapp/MeetingListenerApp/Sources/AppState.swift` — Store metrics

**Changes**:

```python
# ws_live_listener.py

# On session start, emit explicit ACK
await ws_send(state, websocket, {
    "type": "status",
    "state": "streaming",  # This is the ACK client waits for
    "message": "Ready"
})

# Metrics emission task (1Hz)
async def metrics_loop():
    while state.started and not state.closed:
        await asyncio.sleep(1)
        
        for source, q in state.queues.items():
            metrics = {
                "type": "metrics",
                "source": source,
                "queue_depth": q.qsize(),
                "queue_max": QUEUE_MAX,
                "dropped_total": state.dropped_frames,
                "dropped_last_10s": get_dropped_recent(state, seconds=10),
                "realtime_factor": compute_realtime_factor(state),
                "provider": "faster_whisper"
            }
            await ws_send(state, websocket, metrics)
```

```swift
// WebSocketStreamer.swift
var onMetrics: ((SourceMetrics) -> Void)?

struct SourceMetrics {
    let source: String
    let queueDepth: Int
    let queueMax: Int
    let droppedTotal: Int
    let droppedRecent: Int
    let realtimeFactor: Double
}

// Parse metrics messages
if type == "metrics" {
    let metrics = SourceMetrics(
        source: object["source"] as? String ?? "",
        queueDepth: object["queue_depth"] as? Int ?? 0,
        queueMax: object["queue_max"] as? Int ?? 1,
        droppedTotal: object["dropped_total"] as? Int ?? 0,
        droppedRecent: object["dropped_last_10s"] as? Int ?? 0,
        realtimeFactor: object["realtime_factor"] as? Double ?? 0.0
    )
    onMetrics?(metrics)
}
```

**Metrics Display** (debug/diagnostics panel):
- Queue fill bar (green/yellow/red)
- Dropped frames counter
- Realtime factor graph

**Acceptance Criteria**:
- [ ] Client receives `status: "streaming"` within 2s of session start
- [ ] Metrics received every 1s while session active
- [ ] `realtime_factor` computed correctly (processing_time / audio_time)
- [ ] Dropped frames tracked per source

**Estimate**: 6-8 hours

---

## PR3: VAD Default On + Load Reduction

**Goal**: Reduce ASR load by skipping silence (~40% reduction in typical meetings)

**Files to Modify**:
- `server/services/asr_stream.py` — Enable VAD by default
- `server/services/provider_faster_whisper.py` — Apply VAD pre-filter

**Changes**:

```python
# asr_stream.py

def _get_default_config() -> ASRConfig:
    return ASRConfig(
        model_name=os.getenv("ECHOPANEL_WHISPER_MODEL", "base.en"),
        device=os.getenv("ECHOPANEL_WHISPER_DEVICE", "auto"),
        compute_type=os.getenv("ECHOPANEL_WHISPER_COMPUTE", "int8"),
        chunk_seconds=int(os.getenv("ECHOPANEL_ASR_CHUNK_SECONDS", "2")),  # Reduced from 4
        vad_enabled=os.getenv("ECHOPANEL_ASR_VAD", "1") == "1",  # CHANGED: default ON
    )
```

```python
# provider_faster_whisper.py

# Add Silero VAD filtering before transcribe
import torch
from silero_vad import load_silero_vad, read_audio

vad_model = load_silero_vad()

def filter_speech_segments(audio_bytes: bytes, sample_rate: int = 16000) -> List[bytes]:
    """Return only speech segments using Silero VAD."""
    # Convert bytes to tensor
    audio_tensor = torch.frombuffer(audio_bytes, dtype=torch.int16).float() / 32768.0
    
    # Get speech timestamps
    speech_timestamps = get_speech_timestamps(
        audio_tensor, 
        vad_model,
        sampling_rate=sample_rate,
        threshold=0.5,
        min_speech_duration_ms=250,
        min_silence_duration_ms=100
    )
    
    # Extract speech segments
    segments = []
    for ts in speech_timestamps:
        start = ts['start'] * 2  # bytes (16-bit)
        end = ts['end'] * 2
        segments.append(audio_bytes[start:end])
    
    return segments if segments else [audio_bytes]  # Fallback to full if no speech detected
```

**Dependencies**:
```bash
pip install silero-vad torch
```

**Acceptance Criteria**:
- [ ] VAD enabled by default
- [ ] Silence not sent to ASR (check logs)
- [ ] Speech still transcribed correctly (test with sample audio)
- [ ] Chunk size reduced to 2s (faster turnaround)

**Estimate**: 4-6 hours

---

## PR4: Backpressure Policy + Graceful Degradation

**Goal**: When overloaded, degrade gracefully instead of silently dropping

**Files to Modify**:
- `server/api/ws_live_listener.py` — Queue monitoring, backpressure signals
- `macapp/MeetingListenerApp/Sources/AppState.swift` — React to backpressure
- `macapp/MeetingListenerApp/Sources/SidePanel/Shared/SidePanelChromeViews.swift` — UI states

**Changes**:

```python
# ws_live_listener.py

async def monitor_backpressure(state: SessionState, websocket: WebSocket):
    """Emit backpressure warnings and apply degradation ladder."""
    while state.started:
        await asyncio.sleep(1)
        
        for source, q in state.queues.items():
            fill_ratio = q.qsize() / QUEUE_MAX
            
            if fill_ratio > 0.95:
                # Level 3: Critical - pause or drop
                await ws_send(state, websocket, {
                    "type": "status",
                    "state": "overloaded",
                    "message": f"Audio backlog critical for {source}",
                    "source": source
                })
                state.backpressure_level = 3
                
            elif fill_ratio > 0.85:
                # Level 2: Warning
                await ws_send(state, websocket, {
                    "type": "status", 
                    "state": "buffering",
                    "message": f"Processing backlog for {source}",
                    "source": source
                })
                state.backpressure_level = 2
```

```swift
// AppState.swift

enum BackpressureLevel {
    case normal      // green
    case buffering   // yellow  
    case overloaded  // red
}

@Published var backpressureLevel: BackpressureLevel = .normal

// On metrics update
func updateBackpressure(_ metrics: SourceMetrics) {
    let fillRatio = Double(metrics.queueDepth) / Double(metrics.queueMax)
    
    if metrics.droppedRecent > 0 || fillRatio > 0.95 {
        backpressureLevel = .overloaded
    } else if fillRatio > 0.85 || metrics.realtimeFactor > 1.0 {
        backpressureLevel = .buffering
    } else {
        backpressureLevel = .normal
    }
}
```

**UI States**:
```swift
// SidePanelChromeViews.swift

var statusPill: some View {
    HStack {
        Circle()
            .fill(statusColor)
        Text(statusText)
    }
    .background(statusColor.opacity(0.15))
}

var statusColor: Color {
    switch (sessionState, backpressureLevel) {
    case (.listening, .overloaded): return .red
    case (.listening, .buffering): return .orange
    case (.listening, .normal): return .green
    default: return .gray
    }
}

var statusText: String {
    switch (sessionState, backpressureLevel) {
    case (.listening, .overloaded): return "Overloaded"
    case (.listening, .buffering): return "Buffering"
    case (.listening, .normal): return "Listening"
    default: return "Starting"
    }
}
```

**Drop Policy** (server-side, already exists but make visible):
```python
# In put_audio(), when queue full:
# Policy: Drop oldest, keep newest (user cares about now, not 2min ago)
try:
    q.put_nowait(chunk)
except asyncio.QueueFull:
    # Drop oldest
    dropped = q.get_nowait()
    state.dropped_frames += 1
    q.put_nowait(chunk)
    
    # Log and notify
    logger.warning(f"Dropped oldest chunk, total={state.dropped_frames}")
```

**Acceptance Criteria**:
- [ ] Queue fill > 85% shows "Buffering" (orange)
- [ ] Queue fill > 95% shows "Overloaded" (red)
- [ ] Dropped frames surfaced in UI (counter or banner)
- [ ] Drop policy is "drop oldest, keep newest"

**Estimate**: 6-8 hours

---

## PR5: Parallel Recording (Offline Pipeline Foundation)

**Goal**: Always record raw audio for post-processing

**Files to Modify**:
- `macapp/MeetingListenerApp/Sources/RawAudioRecorder.swift` — NEW
- `macapp/MeetingListenerApp/Sources/AppState.swift` — Integrate recording
- `macapp/MeetingListenerApp/Sources/SessionStore.swift` — Manage files

**New File: RawAudioRecorder.swift**:
```swift
import Foundation

actor RawAudioRecorder {
    private var fileHandles: [String: FileHandle] = [:]
    private var sessionDirectory: URL?
    
    func start(sessionID: String) throws {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionDir = baseDir.appendingPathComponent("echopanel_sessions/\(sessionID)")
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        self.sessionDirectory = sessionDir
        
        // Create files for each source
        for source in ["system", "mic"] {
            let fileURL = sessionDir.appendingPathComponent("\(source).raw")
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            fileHandles[source] = try FileHandle(forWritingTo: fileURL)
        }
    }
    
    func append(_ data: Data, source: String) {
        guard let handle = fileHandles[source] else { return }
        handle.write(data)
    }
    
    func stop() -> [String: URL] {
        // Close files
        for handle in fileHandles.values { handle.closeFile() }
        fileHandles.removeAll()
        
        // Return file URLs
        guard let dir = sessionDirectory else { return [:] }
        return [
            "system": dir.appendingPathComponent("system.raw"),
            "mic": dir.appendingPathComponent("mic.raw")
        ]
    }
    
    func cleanup(sessionID: String) {
        // Delete raw files (called after offline processing complete)
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionDir = baseDir.appendingPathComponent("echopanel_sessions/\(sessionID)")
        try? FileManager.default.removeItem(at: sessionDir)
    }
}
```

**Integration in AppState**:
```swift
private let rawRecorder = RawAudioRecorder()

func onPCMFrame(_ data: Data, source: String) {
    // Existing: Send to WebSocket
    streamer.sendPCMFrame(data, source: source)
    
    // New: Write to file
    Task {
        await rawRecorder.append(data, source: source)
    }
}

func stopSession() {
    // ... existing stop logic ...
    
    // Get recorded files
    Task {
        let files = await rawRecorder.stop()
        sessionStore.saveRawAudioFiles(sessionId: id, files: files)
        
        // Schedule cleanup after 7 days
        scheduleCleanup(sessionId: id, delay: .days(7))
    }
}
```

**Storage Management**:
```swift
// SessionStore.swift

func scheduleCleanup(sessionId: String, delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.cleanupRawAudio(sessionId: sessionId)
    }
}

func cleanupRawAudio(sessionId: String) {
    // Delete raw PCM files, keep transcripts
    // Only delete if offline processing completed successfully
}
```

**Acceptance Criteria**:
- [ ] Raw PCM files created on session start
- [ ] Files contain all audio from both sources
- [ ] Files survive app restart/crash
- [ ] Auto-cleanup after 7 days (configurable)
- [ ] Files available for offline processing after session end

**Estimate**: 8-10 hours

---

## PR6: Offline Pipeline + Merge

**Goal**: Process raw audio post-session, merge with realtime

**Files to Modify**:
- `server/services/post_process_asr.py` — NEW
- `server/api/post_process_endpoint.py` — NEW
- `macapp/MeetingListenerApp/Sources/SessionStore.swift` — Trigger processing
- `macapp/MeetingListenerApp/Sources/SummaryView.swift` — Show progress

**New File: post_process_asr.py**:
```python
"""Offline ASR processing with larger model."""

import asyncio
from pathlib import Path
from faster_whisper import WhisperModel

class OfflineASRProcessor:
    def __init__(self):
        # Load larger model for offline processing
        self.model = WhisperModel(
            "large-v3",  # or large-v3-turbo
            device="auto",
            compute_type="int8"
        )
    
    async def process_session(
        self,
        system_audio: Path,
        mic_audio: Path,
        realtime_transcript: List[dict]
    ) -> dict:
        """Process raw audio and produce canonical transcript."""
        
        results = {
            "system_segments": [],
            "mic_segments": [],
            "merged_transcript": [],
            "metadata": {}
        }
        
        # Process each source
        for source, audio_path in [("system", system_audio), ("mic", mic_audio)]:
            if not audio_path.exists():
                continue
                
            segments, info = self.model.transcribe(
                str(audio_path),
                beam_size=5,
                best_of=5,
                condition_on_previous_text=True
            )
            
            source_segments = []
            for segment in segments:
                source_segments.append({
                    "text": segment.text,
                    "t0": segment.start,
                    "t1": segment.end,
                    "confidence": segment.avg_logprob,
                    "source": source
                })
            
            results[f"{source}_segments"] = source_segments
        
        # Merge by timestamp
        results["merged_transcript"] = self._merge_by_timestamp(
            results["system_segments"],
            results["mic_segments"]
        )
        
        return results
    
    def _merge_by_timestamp(self, system: List[dict], mic: List[dict]) -> List[dict]:
        """Interleave segments by timestamp."""
        all_segments = system + mic
        return sorted(all_segments, key=lambda s: s["t0"])
```

**Progress UI**:
```swift
// SummaryView.swift

struct OfflineProcessingView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack {
            if appState.offlineProcessingStatus == .processing {
                ProgressView("Processing final transcript...")
                Text("\(appState.offlineProgress)% complete")
            } else if appState.offlineProcessingStatus == .complete {
                Text("Final transcript ready")
                    .foregroundColor(.green)
            }
        }
    }
}
```

**Merge Strategies**:
```swift
enum MergeStrategy {
    case replace       // Use offline only
    case smartMerge    // Default: offline text + preserve realtime pins
    case hybrid        // Realtime for actions, offline for final
}

func mergeTranscripts(
    realtime: [TranscriptSegment],
    offline: [TranscriptSegment],
    strategy: MergeStrategy
) -> [TranscriptSegment] {
    switch strategy {
    case .replace:
        return offline
        
    case .smartMerge:
        var merged = offline
        for rtSegment in realtime {
            if rtSegment.hasUserPins {
                // Find nearest offline segment
                if let nearest = findNearestSegment(rtSegment.t0, in: offline) {
                    nearest.pins = rtSegment.pins
                }
            }
        }
        return merged
        
    case .hybrid:
        // TODO: More complex merge
        return offline
    }
}
```

**Acceptance Criteria**:
- [ ] Offline processing triggered on session end
- [ ] Progress shown to user
- [ ] Final transcript produced even if realtime failed
- [ ] Merge strategies work (test with sample data)
- [ ] Raw files cleaned up after successful processing

**Estimate**: 10-12 hours

---

## Implementation Order

| PR | Feature | Hours | Depends On | Can Parallelize |
|----|---------|-------|------------|-----------------|
| 1 | UI Handshake | 4-6 | None | No |
| 2 | Server Metrics | 6-8 | None | With PR1 |
| 3 | VAD Default | 4-6 | None | Yes |
| 4 | Backpressure | 6-8 | PR2 | With PR3 |
| 5 | Parallel Recording | 8-10 | None | Yes |
| 6 | Offline Pipeline | 10-12 | PR5 | After PR5 |

**Total**: 38-50 hours (1-2 weeks focused work)

**Minimum Viable Fix** (stop the bleeding):
- PR1 + PR2 + PR3 = 14-20 hours
- Fixes "UI lies" and reduces load ~40%

---

## Testing Checklist

### Unit Tests
- [ ] Handshake timeout triggers error
- [ ] Late messages from old attempt ignored
- [ ] Metrics parsing correct
- [ ] VAD filters silence
- [ ] Backpressure levels trigger correctly

### Integration Tests
- [ ] Full session: Start → Streaming → Stop → Offline complete
- [ ] Overload scenario: Queue fills → Buffering → Overloaded → Recovers
- [ ] Crash recovery: Recording survives app kill
- [ ] Merge: Realtime + offline combine correctly

### Manual Tests
- [ ] 30min meeting, both sources, continuous speech
- [ ] Verify realtime_factor < 1.0
- [ ] Verify zero dropped frames
- [ ] Verify final transcript quality vs realtime

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| VAD too aggressive | Tune thresholds, make user-configurable |
| Large model too slow for offline | Fallback to smaller model, or queue for later |
| Storage fills up | 7-day retention, user-configurable |
| Merge algorithm wrong | Keep both versions, let user choose |
| Timestamp drift | Use monotonic clock, validate in tests |

---

## Success Metrics

| Metric | Before | After PR1-4 | After PR6 |
|--------|--------|-------------|-----------|
| UI accuracy | ~60% | 100% | 100% |
| Dropped frames | 3,800+ | <100 | 0 (offline) |
| Realtime factor | ~1.5x | <1.0 | N/A |
| Final WER | ~10% | ~10% | ~3% |
| User satisfaction | Low | Medium | High |

---

*Ready for implementation*
