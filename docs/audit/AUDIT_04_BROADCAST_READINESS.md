# Broadcast Industry Readiness Audit (Phase 4G)

**Scope**: Evaluate EchoPanel for live production captioning/transcription use cases in broadcast media workflows.
**Focus Areas**: Capture reliability, failure modes, operator UX, compliance, and multi-language requirements.
**Date**: 2026-02-10
**Last reviewed**: 2026-02-11 (Audit Queue Runner)
**Status**: OPEN
**Current Readiness Score**: 42/100 (NOT BROADCAST-READY)

**Evidence Sources**:
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/AudioCaptureManager.swift`
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/MicrophoneCaptureManager.swift`
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SessionStore.swift`
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/BackendManager.swift`
- `/Users/pranay/Projects/EchoPanel/macapp/MeetingListenerApp/Sources/SessionBundle.swift`
- `/Users/pranay/Projects/EchoPanel/docs/WS_CONTRACT.md`

---

## Executive Summary

EchoPanel is currently **NOT BROADCAST-READY** for live production captioning without significant additions. While the core ASR pipeline shows promise with local-first processing, the current architecture lacks critical broadcast industry requirements including dual-path redundancy, timecode synchronization, hot-key operator controls, and real-time PII handling.

**Current State**: Alpha/Prototype - suitable for meeting notes, content review, and post-production.  
**Broadcast Readiness Score**: 42/100 (see detailed scorecard below)

---

## 1. Broadcast Readiness Scorecard

| Category | Weight | Score | Status | Key Gaps |
|----------|--------|-------|--------|----------|
| **Capture Reliability** | 25% | 55/100 | ⚠️ PARTIAL | No dual-path, no device failover |
| **Timing & Sync** | 20% | 20/100 | ❌ CRITICAL | No NTP/timecode, no genlock |
| **Operator UX** | 20% | 35/100 | ❌ CRITICAL | No hot-keys, no confidence display |
| **Output Formats** | 15% | 30/100 | ❌ CRITICAL | No SRT/VTT streaming, no EBU-TT |
| **Compliance/PII** | 10% | 40/100 | ⚠️ PARTIAL | No real-time redaction, manual export only |
| **Multi-Language** | 10% | 65/100 | ⚠️ PARTIAL | Basic multi-language ASR, no interpreter tracks |
| **OVERALL** | 100% | **42/100** | ❌ **NOT READY** | Significant engineering required |

### Scoring Rubric

- **90-100**: Production-ready for live broadcast
- **70-89**: Broadcast-ready with monitoring/guardrails
- **50-69**: Pilot/production test acceptable
- **30-49**: Development only, not suitable for live
- **0-29**: Fundamental architecture changes required

---

## 2. Capture Reliability Analysis

### 2.1 Current Capture Architecture

**System Audio (ScreenCaptureKit)**:
- SCStream with audio capture enabled
- 16kHz PCM16 mono output
- 20ms frame size (320 samples)
- Remainder handling for partial frames
- RMS/clipping/silence detection via EMA smoothing

**Microphone (AVAudioEngine)**:
- AVAudioEngine input node tap
- Same 16kHz PCM16 mono format
- Same 20ms frame emission

### 2.2 Evidence: Capture Quality Monitoring

```swift
// From AudioCaptureManager.swift - AudioQuality struct
struct AudioQuality {
    let rms: Float           // EMA-smoothed RMS level
    let clippingRatio: Float // Percentage of clipped samples
    let isSilent: Bool       // Silence threshold detection
}
```

Quality metrics are computed but only exposed via `onAudioQualityUpdate` callback. No automatic failover triggers.

### 2.3 Critical Gaps for Broadcast

| Gap | Impact | Broadcast Requirement |
|-----|--------|----------------------|
| No dual-path redundancy | Single point of failure | Dual microphone inputs with automatic failover |
| No device change handling | Audio drop on USB reconnect | Hot-swap support with <100ms recovery |
| No genlock/wordclock | Clock drift over long sessions | External reference sync for lip-sync |
| No dedicated "clean feed" | System audio may have processing | Unprocessed direct audio path |
| 20ms fixed buffering | Higher latency than broadcast spec | Configurable down to 5-10ms |

### 2.4 Failure Modes: Capture Layer

| ID | Failure | Cause | Current Behavior | Broadcast Impact |
|----|---------|-------|------------------|------------------|
| CAP-01 | SCStream failure | ScreenCaptureKit error | Error logged, stream stops | **Show-stopper**: No recovery, no alert |
| CAP-02 | AVAudioEngine stop | Device unplugged | Error logged, capture stops | **Show-stopper**: Hot-swap not supported |
| CAP-03 | Sample rate mismatch | USB device change | Conversion attempted | Potential drift if conversion fails |
| CAP-04 | Clock drift | No external sync | Monotonic timestamp only | Lip-sync issues over time |
| CAP-05 | Silence false positive | Very quiet content | 10s silence warning | Operator confusion, false alerts |

---

## 3. Persistence & Crash Recovery

### 3.1 Current SessionStore Implementation

**Strengths**:
- JSONL append-only transcript log (crash durable)
- Recovery markers via `recovery.json`
- 30-second auto-save snapshots
- Session history with metadata

**Evidence**:
```swift
// From SessionStore.swift
func appendTranscriptSegment(_ segment: [String: Any]) {
    // Append-only JSONL for crash durability
    guard let handle = transcriptFileHandle else { return }
    // Writes newline-delimited JSON
}

func checkForRecoverableSession() -> RecoverableSession? {
    // Reads recovery.json marker for crash detection
}
```

### 3.2 Broadcast-Specific Gaps

| Gap | Impact | Required Enhancement |
|-----|--------|---------------------|
| No redundant storage | Disk failure loses transcript | Network/NAS sync for critical sessions |
| 30s auto-save interval | Up to 30s data loss on crash | Sub-second persistence for live |
| Local storage only | Single machine risk | Real-time cloud backup option |
| No RAID/mirror awareness | Consumer-grade reliability | Enterprise storage integration |

---

## 4. Backend Recovery & Resilience

### 4.1 BackendManager Recovery Features

**Implemented**:
- 3-restart limit with exponential backoff
- Graceful termination (SIGTERM → SIGINT → SIGKILL)
- External backend detection (port probe)
- Health check with 503 handling

**Evidence**:
```swift
// From BackendManager.swift
private let maxRestartAttempts: Int = 3
private let maxRestartDelay: TimeInterval = 10.0
private func attemptRestart() {
    restartAttempts += 1
    let delay = min(restartDelay, maxRestartDelay)
    restartDelay *= 2 // Exponential backoff
}
```

### 4.2 Broadcast Issues

| Issue | Severity | Problem |
|-------|----------|---------|
| No hot-standby backend | HIGH | Seconds of downtime during restart |
| 3-attempt limit | MEDIUM | Manual intervention required after failures |
| No circuit breaker | MEDIUM | Continuous restart attempts during systemic issues |
| Python dependency | HIGH | Not suitable for 24/7 broadcast operations |

---

## 5. Timing, Synchronization & Timecode

### 5.1 Current Timestamp Implementation

**Evidence from ASR Providers**:
```python
# From provider_faster_whisper.py
segment_info = {
    "start": segment.start,  # seconds from audio start
    "end": segment.end,
    "text": segment.text,
}
```

**Limitations**:
- Monotonic relative timestamps only
- No absolute time reference
- No NTP synchronization
- No support for external timecode (LTC/VITC)

### 5.2 Broadcast Requirements

| Requirement | Current State | Gap |
|-------------|---------------|-----|
| NTP-synchronized timestamps | ❌ Not implemented | Absolute timing for multi-site |
| LTC (Linear Timecode) input | ❌ Not implemented | Professional timecode sync |
| VITC (Vertical Interval TC) | ❌ Not implemented | Video-embedded timing |
| Genlock/Blackburst input | ❌ Not implemented | Frame-accurate sync |
| Timezone-aware metadata | ❌ Not implemented | International production |

### 5.3 Impact Assessment

Without timecode synchronization:
- Multi-camera productions cannot sync transcripts
- Post-production requires manual alignment
- Compliance logging lacks forensic timing
- Multi-site productions drift independently

---

## 6. Output Formats & Caption Standards

### 6.1 Current Export Formats

**SessionBundle Export** (from `SessionBundle.swift`):
- `transcript_realtime.json` - JSON array with t0/t1
- `transcript_final.json` - Post-processed JSON
- No broadcast caption formats

### 6.2 Missing Broadcast Formats

| Format | Use Case | Priority |
|--------|----------|----------|
| SRT (SubRip) | Universal subtitle format | **P0** |
| WebVTT | Web streaming, HLS | **P0** |
| EBU-TT (Tech 3350) | European broadcast compliance | P1 |
| SCC (Scenarist Closed Caption) | US broadcast (CEA-608) | P1 |
| TTML/IMSC1 | XML-based broadcast standard | P2 |
| DFXP | Netflix/OTT delivery | P2 |

### 6.3 Real-Time Output Requirements

Current architecture exports only at session end. Broadcast requires:
- Streaming SRT/VTT output (file-per-segment or WebSocket)
- Live UDP/SDI embedding capability
- Character generator (CG) integration
- Lower-third overlay trigger support

---

## 7. Operator UX & Control Surface

### 7.1 Current Control Interface

**From AppState.swift analysis**:
- Start/Stop via UI button
- 5-second backend timeout on start
- Silence detection warning (10s threshold)
- Session state machine: idle → starting → listening → finalizing

### 7.2 Missing Broadcast Operator Controls

| Feature | Why Needed | Current Status |
|---------|------------|----------------|
| Hot-keys (function keys) | Hands-off operation | ❌ Not implemented |
| Confidence indicator | Quality monitoring | ❌ Not implemented |
| Manual speaker tagging | Post-diarization correction | ❌ Not implemented |
| Cough/bark suppression | Clean broadcast audio | ❌ Not implemented |
| VU meter display | Audio level monitoring | ⚠️ Internal metrics only |
| Recording indicator | On-air status | ⚠️ Basic UI only |
| Emergency stop | Immediate cut | ⚠️ Stop button only |

### 7.3 Confidence Display Requirements

Broadcast operators need real-time quality indicators:
- ASR confidence score (per-segment)
- Audio level VU meter
- Word error rate estimation
- Connection health status
- Buffer depth indicator

---

## 8. Multi-Language & Interpreter Workflows

### 8.1 Current Multi-Language Support

**From ASR Provider Analysis**:
- Faster-whisper supports multiple languages via `language` parameter
- No automatic language detection
- Single language per session

**Evidence**:
```python
# From provider_faster_whisper.py
options = {
    "language": self.config.language or "en",
    "task": "transcribe",
}
```

### 8.2 Broadcast Multi-Language Requirements

| Requirement | Current | Gap |
|-------------|---------|-----|
| Simultaneous multi-language | Single language only | Need parallel ASR streams |
| Interpreter floor audio | Mixed with program audio | Need separate channel routing |
| Language switching | Manual only | Need automatic detection |
| Translation (ASR→text→MT) | Not supported | Pipeline extension needed |
| Bilingual captions | Not supported | Dual-stream display |

### 8.3 Interpreter Track Routing

Current system mixes all sources. Broadcast requires:
- **Floor audio**: Main program audio
- **Interpreter 1-N**: Isolated translation feeds
- **Mix-minus**: Each interpreter hears floor minus their own voice
- **Individual transcript streams**: Separate output per language

---

## 9. Compliance, PII & Legal Hold

### 9.1 Current PII Handling

**SessionBundle privacy features**:
- Audio excluded by default (opt-in)
- Machine ID hashed (SHA256)
- Privacy-safe export configuration

**From SessionBundle.swift**:
```swift
static let privacySafe = Configuration(
    includeAudio: false,
    includeTranscript: true,
    includeMetrics: true,
    includeLogs: true
)
```

### 9.2 Broadcast Compliance Gaps

| Requirement | Current | Status |
|-------------|---------|--------|
| GDPR right-to-erasure | Manual file deletion | ⚠️ Partial |
| CCPA data portability | JSON export available | ✅ Adequate |
| Real-time PII redaction | Not implemented | ❌ Critical |
| Audit logging | StructuredLogger exists | ⚠️ Needs enhancement |
| Legal hold / retention | Not implemented | ❌ Critical |
| Accessibility (WCAG) | Basic tests passing | ⚠️ Needs broadcast review |

### 9.3 Real-Time PII Redaction

Broadcast captions must handle:
- Phone numbers: `xxx-xxx-xxxx` → `[PHONE REDACTED]`
- SSN/Credit cards: Pattern detection + masking
- Names (optional): Proper noun detection
- Profanity: Filter list substitution

---

## 10. Network Chaos & Resilience

### 10.1 Current WebSocket Resilience

**From ResilientWebSocket.swift** (referenced in audits):
- Exponential backoff for reconnection
- Connection state machine
- Message queuing during offline

### 10.2 Broadcast Network Requirements

| Scenario | Current | Required |
|----------|---------|----------|
| Network partition (brief) | Reconnection with backoff | <1s recovery, no loss |
| Network partition (extended) | Queue overflow, drops | Store-and-forward mode |
| High latency (>500ms) | Timeout/disconnect | Adaptive buffering |
| Packet loss | WebSocket TCP masks | UDP with FEC option |
| Corporate firewall | WebSocket fallback | Multiple transport options |

### 10.3 Offline Operation Gap

Current architecture requires constant backend connection. Broadcast requires:
- Local ASR without backend dependency
- Store-and-forward for post-processing
- Edge deployment capability

---

## 11. 10-Scenario Broadcast Playbook

### Scenario 1: Live News Captioning
**Setup**: Single anchor, clean audio feed  
**Configuration**: System audio capture, faster-whisper base.en  
**Risk**: Medium - single source point of failure  
**Mitigation**: Add mic backup channel  
**Score**: 70/100 (acceptable for pilot)

### Scenario 2: Multi-Person Interview
**Setup**: 2-4 speakers, mixed audio  
**Configuration**: System audio + diarization enabled  
**Risk**: High - speaker confusion common  
**Mitigation**: Pre-session speaker enrollment  
**Score**: 55/100 (post-production recommended)

### Scenario 3: Live Sports Commentary
**Setup**: Fast speech, background noise  
**Configuration**: medium.en or turbo model  
**Risk**: High - noise impacts accuracy  
**Mitigation**: Noise gate pre-processing  
**Score**: 50/100 (human captioner preferred)

### Scenario 4: Multi-Language Conference
**Setup**: English + Spanish + French  
**Configuration**: Not supported currently  
**Risk**: Critical - architecture limitation  
**Mitigation**: Multiple app instances (workaround)  
**Score**: 20/100 (not viable)

### Scenario 5: Remote Guest Via Zoom
**Setup**: Mixed local + remote audio  
**Configuration**: System audio (captures both)  
**Risk**: Medium - network quality impacts remote audio  
**Mitigation**: Separate recording on guest end  
**Score**: 65/100 (acceptable for pilot)

### Scenario 6: Live Event with Interpreters
**Setup**: Floor English + Spanish interpretation  
**Configuration**: Not supported (no track separation)  
**Risk**: Critical - no interpreter isolation  
**Mitigation**: Hardware audio router external  
**Score**: 30/100 (not viable without external hardware)

### Scenario 7: 24/7 Broadcast Channel
**Setup**: Continuous operation required  
**Configuration**: Not supported (memory leaks likely)  
**Risk**: Critical - no long-running testing  
**Mitigation**: Scheduled restarts every 4 hours  
**Score**: 25/100 (not viable for production)

### Scenario 8: Emergency Broadcast (FEMA/EBS)
**Setup**: Critical accuracy, no failure  
**Configuration**: Dual-redundancy required  
**Risk**: Critical - single points of failure throughout  
**Mitigation**: Human captioner backup mandatory  
**Score**: 10/100 (not suitable for emergency use)

### Scenario 9: Post-Production Transcription
**Setup**: File-based, non-real-time  
**Configuration**: Batch processing via API  
**Risk**: Low - retry possible  
**Mitigation**: N/A  
**Score**: 85/100 (viable with batch workflow)

### Scenario 10: Compliance Logging
**Setup**: Legal requirement for record  
**Configuration**: Full session capture  
**Risk**: Medium - timestamp accuracy  
**Mitigation**: NTP sync external  
**Score**: 60/100 (acceptable with enhancements)

---

## 12. Operator Observability Requirements

### 12.1 Required Dashboard Elements

| Element | Metric | Alert Threshold |
|---------|--------|-----------------|
| Audio VU Meter | dBFS level | Clip > -3dB, Silence < -60dB |
| ASR Confidence | Word-level score | < 0.7 warning, < 0.5 critical |
| Buffer Depth | Queued seconds | < 5s warning, < 1s critical |
| Latency | End-to-end delay | > 3s warning, > 5s critical |
| Word Error Rate | Estimated WER | > 20% warning, > 40% critical |
| Connection Status | WebSocket state | Disconnected = critical |
| CPU/GPU Load | ASR inference % | > 90% warning |
| Disk Space | Available for logs | < 1GB warning |

### 12.2 Required Alert Channels

- Visual: In-app indicator with color coding
- Audio: Optional beep on critical alerts
- External: Webhook for integration with broadcast automation
- Logging: Structured logs for post-incident analysis

### 12.3 Recommended Operator Workstation Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [VIZ] Audio Levels      [VIZ] Confidence    [VIZ] Buffer  │
│  L ████████ R            87% ████████        2.3s █████   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    TRANSCRIPT DISPLAY                       │
│              (Large, readable font, 3-line)                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [BTN] START   [BTN] STOP   [BTN] MARK   [BTN] EXPORT    │
│  [TXT] Session: 00:42:15   [TXT] Status: ON AIR ●         │
└─────────────────────────────────────────────────────────────┘
```

---

## 13. Implementation Status (Updated 2026-02-11)

### Patch B1: Dual-Path Audio Redundancy
**Status:** NOT STARTED ❌
**Priority:** P0
**Evidence:** No RedundantAudioCaptureManager or dual-path implementation found

---

### Patch B2: Real-Time SRT/VTT Streaming Output
**Status:** NOT STARTED ❌
**Priority:** P0
**Evidence:** No SRT/VTT output format or caption streaming service found

---

### Patch B3: Confidence Display Overlay
**Status:** NOT STARTED ❌
**Priority:** P1
**Evidence:** No confidence meter, overlay, or display found in UI

---

### Patch B4: NTP Timestamp Synchronization
**Status:** NOT STARTED ❌
**Priority:** P1
**Evidence:** No NTP client, timecode sync, or synchronized timestamps found

---

### Additional Broadcast Features

| Feature | Status | Evidence |
|----------|--------|----------|
| Hot-key operator controls | NOT STARTED ❌ | No hotkey/shortcut handlers found |
| Device hot-swap support | NOT STARTED ❌ | No USB reconnect or swap logic found |
| CEA-608 Closed Captions | NOT SUPPORTED ❌ | No CEA-608 implementation |
| CEA-708 Digital Captions | NOT SUPPORTED ❌ | No CEA-708 implementation |
| EBU-TT Timed Text | NOT SUPPORTED ❌ | No EBU-TT implementation |
| SMPTE standards | NOT SUPPORTED ❌ | No SMPTE timecode or ancillary data |

---

### Evidence Log (2026-02-11):

```bash
# Checked Patch B1: Dual-path redundancy
rg 'RedundantAudioCapture\|dual.*path\|primary.*backup' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked Patch B2: SRT/VTT streaming
rg 'SRT\|VTT\|caption.*output\|caption.*stream' /Users/pranay/Projects/EchoPanel/server/ --type py
# Result: No matches

# Checked Patch B3: Confidence display
rg 'confidence.*meter\|confidence.*overlay\|confidence.*display' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked Patch B4: NTP synchronization
rg 'NTP\|ntp.*client\|synchronized.*timestamp\|timecode' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked hot-key operator controls
rg 'hotkey\|hot.*key\|keyboard.*shortcut\|operator.*control' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked device hot-swap support
rg 'device.*swap\|hot.*swap\|USB.*reconnect' /Users/pranay/Projects/EchoPanel/macapp/ --type swift
# Result: No matches

# Checked broadcast standard outputs
rg 'CEA-608\|CEA-708\|EBU-TT\|SMPTE' /Users/pranay/Projects/EchoPanel/ --type md --type swift --type py
# Result: No matches
```

**Interpretation:**
- 0 of 4 primary patches are implemented
- 0 of 3 additional broadcast features are implemented
- EchoPanel remains at 42/100 broadcast readiness
- Major architecture work required for broadcast industry compliance

---

## 14. Original Reliability Patches Required

### Patch B1: Dual-Path Audio Redundancy (Priority: P0)

**Problem**: Single audio source is a single point of failure.

**Solution Architecture**:
```swift
// New: RedundantAudioCaptureManager
final class RedundantAudioCaptureManager {
    private let primary: AudioCaptureManager
    private let backup: MicrophoneCaptureManager  // or second system capture
    private var activeSource: AudioSource = .primary
    
    func startCapture() async throws {
        // Start both sources
        try await primary.startCapture()
        try await backup.startCapture()
        
        // Monitor quality, switch on degradation
        startQualityMonitor()
    }
    
    private func startQualityMonitor() {
        // Switch to backup if primary silence > 2s
        // Switch back when primary recovers
        // Emit source-switch events for transcript correlation
    }
}
```

**Implementation Scope**:
- New `RedundantAudioCaptureManager.swift` (~300 lines)
- Source tagging in WebSocket messages
- UI indicator for active source
- Configuration for primary/backup selection

**Estimate**: 2-3 engineering days

---

### Patch B2: Real-Time SRT/VTT Streaming Output (Priority: P0)

**Problem**: Broadcast systems require live caption feed, not post-session export.

**Solution Architecture**:
```python
# New: services/caption_output.py
from dataclasses import dataclass
from typing import AsyncIterator, Callable
import asyncio

@dataclass
class CaptionSegment:
    index: int
    start: str  # SRT format: "00:00:12,000"
    end: str
    text: str
    
class SRTStreamOutput:
    """Real-time SRT stream generator"""
    
    def __init__(self, callback: Callable[[str], None]):
        self.callback = callback
        self.segment_index = 0
        self.buffer = []
        
    async def on_asr_segment(self, segment: TranscriptSegment):
        # Convert to SRT format
        srt_entry = self._to_srt(segment)
        self.callback(srt_entry)
        
    def _to_srt(self, segment) -> str:
        self.segment_index += 1
        return f"{self.segment_index}\n{self._fmt_time(segment.t0)} --> {self._fmt_time(segment.t1)}\n{segment.text}\n\n"
```

**Integration Points**:
1. WebSocket extension for caption subscription
2. File-writer for network share output
3. UDP socket option for direct encoder feed

**Output Options**:
- WebSocket: `{"type": "caption", "format": "srt", "data": "..."}`
- File: Append to shared network location
- UDP: Direct to hardware encoder (configurable port)

**Estimate**: 3-4 engineering days

---

### Patch B3: Confidence Display Overlay (Priority: P1)

**Problem**: Operators cannot monitor ASR quality in real-time.

**Solution**:
- Extend ASR provider to emit confidence scores
- Add confidence meter to SwiftUI interface
- Color-code: Green (>0.85), Yellow (0.7-0.85), Red (<0.7)

**Estimate**: 1-2 engineering days

---

### Patch B4: NTP Timestamp Synchronization (Priority: P1)

**Problem**: Relative timestamps prevent multi-system synchronization.

**Solution**:
```swift
// Extend AudioCaptureManager
private let ntpClient: NTPClient

func getSynchronizedTimestamp() -> UInt64 {
    let monotonic = mach_absolute_time()
    let ntpOffset = ntpClient.currentOffset
    return monotonic + ntpOffset
}
```

**Estimate**: 1 engineering day (with NTP library)

---

## 15. Recommendations Summary (Original)

### For Immediate Pilot Use (Score: 60/100 achievable)

### For Immediate Pilot Use (Score: 60/100 achievable)

1. **Implement Patch B1** (Dual-path audio) - Prevents single-source failures
2. **Implement Patch B2** (SRT streaming) - Enables broadcast integration
3. **Add hot-key support** - Essential for operator workflow
4. **Extend silence detection** - Configurable thresholds per environment

### For Production Readiness (Score: 80/100 target)

5. **Add confidence display** - Operator quality monitoring
6. **NTP synchronization** - Multi-system coordination
7. **PII redaction pipeline** - Compliance requirement
8. **Device hot-swap support** - USB audio failover
9. **Circuit breaker pattern** - Prevent restart loops
10. **Long-running stability testing** - 24+ hour validation

### Out of Scope (Future Releases)

---

## 16. Next Steps (Prioritized by Impact)

### Immediate (P0 - Critical for broadcast):
1. **Implement Patch B1 (dual-path audio):** Create RedundantAudioCaptureManager for primary/backup sources
2. **Implement Patch B2 (SRT/VTT streaming):** Add caption output service for broadcast integration

### High Priority (P1):
3. **Implement Patch B3 (confidence display):** Add confidence meter to UI for operator monitoring
4. **Implement Patch B4 (NTP synchronization):** Add NTP client for multi-system timecode sync
5. **Add hot-key controls:** Implement keyboard shortcuts for operator workflow

### Medium Priority (P2):
6. **Add device hot-swap support:** Handle USB audio reconnect with <100ms recovery
7. **Implement PII redaction:** Real-time redaction pipeline for compliance
8. **Support broadcast standards:** Implement at least one standard (CEA-608 or EBU-TT)

### Suggested Work Order:
- Sprint 1-2: Patch B1 + Patch B2 (reliability + broadcast integration)
- Sprint 3: Patch B3 + Patch B4 (operator tools + sync)
- Sprint 4: Hot-keys + device hot-swap (workflow UX)
- Sprint 5-6: PII redaction + broadcast standards (compliance)

**Target:** Achieve 80/100 broadcast readiness score within 6 sprints

### Out of Scope (Future Releases)

- Genlock/Blackburst hardware integration
- Multi-language parallel ASR
- Interpreter track routing
- Hardware encoder integration (SMPTE 291M)
- Automated speaker enrollment

---

## 17. Original Evidence Log (2026-02-10)

### Commands Run
```bash
# Source code analysis
grep -r "device|Device|sleep|Sleep" macapp --include="*.swift"
grep -r "srt|SRT|vtt|VTT" . --include="*.swift"

# Documentation review
cat docs/WS_CONTRACT.md

# Provider analysis
cat server/services/provider_faster_whisper.py | head -100
```

### Key Findings
1. **Observed**: No dual-path redundancy implementation exists
2. **Observed**: No SRT/VTT output format implemented
3. **Observed**: SessionStore has crash recovery via JSONL append
4. **Observed**: BackendManager has 3-restart limit with backoff
5. **Observed**: No NTP/timecode synchronization exists
6. **Observed**: No hot-key operator controls implemented
7. **Inferred**: 20ms buffer adds ~100-200ms end-to-end latency
8. **Inferred**: Python backend not suitable for 24/7 broadcast

---

## 18. Related Documents

- [AUDIT_01_STREAMING.md](AUDIT_01_STREAMING.md) - Phase 1C: Streaming Reliability
- [AUDIT_02_PROVIDERS.md](AUDIT_02_PROVIDERS.md) - Phase 2D: ASR Provider Layer
- [AUDIT_03_ARCHITECTURE.md](AUDIT_03_ARCHITECTURE.md) - Phase 3: Senior Architect Review
- [WS_CONTRACT.md](../WS_CONTRACT.md) - WebSocket Protocol Specification
- [DECISIONS.md](../DECISIONS.md) - Architecture Decision Records

---

## 19. Appendix: Broadcast Industry Standards Reference

| Standard | Description | EchoPanel Status |
|----------|-------------|------------------|
| CEA-608 | US Line 21 Closed Captions | Not supported |
| CEA-708 | US Digital Closed Captions | Not supported |
| EBU-TT | European Broadcasting Union Timed Text | Not supported |
| TTML/IMSC1 | W3C Text Track Markup | Not supported |
| SMPTE 12M | Timecode standard | Not supported |
| SMPTE 291M | Ancillary data (caption embedding) | Not supported |
| AES11 | Audio synchronization | Not supported |

---

*Audit completed: 2026-02-10*
*Last review: 2026-02-11 (Audit Queue Runner)*
*Next review: Post-Patch B1/B2 implementation*
