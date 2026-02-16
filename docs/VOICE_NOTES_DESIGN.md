# Voice Notes Feature — Design Document

**Created:** 2026-02-14  
**Type:** FEATURE  
**Status:** DESIGN  
**Priority:** P1

## Overview

Allow users to record personal voice notes (annotations, reminders, clarifications) while system audio is being transcribed. Voice notes are transcribed separately from the main transcript and displayed in a dedicated section.

## User Stories

1. **As a user**, I want to press a hotkey or button to record a quick voice note during a meeting
2. **As a user**, I want my voice notes to be transcribed and displayed separately from the main meeting transcript
3. **As a user**, I want to see my voice notes in the summary alongside action items and decisions
4. **As a user**, I want my voice notes to be included when I export the session (JSON, Markdown)

## Current State Analysis

### Existing Infrastructure
- **MicrophoneCaptureManager.swift**: Captures microphone audio via AVAudioEngine
- **AudioSource enum**: Supports `system`, `microphone`, `both`
- **TranscriptSegment model**: Has `source` field ("system" or "mic")
- **WebSocket streaming**: Backend already transcribes mic audio when source="both"

### Current Behavior
When `audioSource = .both`:
- System audio is transcribed with `source="system"`
- Mic audio is transcribed with `source="mic"`
- Both appear in the main transcript stream interleaved

### Problem with Current Approach
The "both" mode transcribes all microphone audio continuously, not just intentional notes. Users want:
- **Selective voice notes**: Press button → speak → release → transcribe
- **Separate display**: Voice notes not mixed into main transcript
- **Clear distinction**: Visual separation between meeting content and personal notes

## Proposed Solution

### 1. Data Model

```swift
// New model in Models.swift
struct VoiceNote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let createdAt: Date
    let confidence: Double
    var isPinned: Bool = false
}
```

### 2. Audio Capture Architecture

#### Option A: Dedicated Voice Note Capture Manager (Recommended)
- Create `VoiceNoteCaptureManager.swift`
- Reuses AVAudioEngine logic from MicrophoneCaptureManager
- Only active when voice note recording is in progress
- Sends audio to separate WebSocket endpoint or with special marker

#### Option B: Extend MicrophoneCaptureManager
- Add voice note mode to existing manager
- Switch between continuous capture and voice note capture
- More complex state management

**Recommendation: Option A** - Cleaner separation, easier to reason about

### 3. Backend Changes

#### WebSocket Message Format
```
{
  "type": "voice_note_audio",
  "audio": "<base64 PCM data>",
  "session_id": "<uuid>",
  "note_id": "<uuid>"
}
```

#### Response Format
```
{
  "type": "voice_note_transcript",
  "text": "Remember to follow up with Sarah",
  "confidence": 0.92,
  "note_id": "<uuid>",
  "timestamps": {"start": 123.45, "end": 128.3}
}
```

#### New Backend Endpoint
`server/api/ws_live_listener.py`:
- Add `voice_note_audio` message type handler
- Route to ASR provider (same as system audio)
- Return transcript with voice note metadata

### 4. UI/UX Design

#### Recording Trigger
- **Hotkey**: `⌘N` (Command + N) or `⌥V` (Option + V)
- **Button**: In SidePanel chrome (near record/pause controls)
- **Visual feedback**: Recording indicator (pulsing red circle)

#### Recording State
```
┌─────────────────────────────────┐
│  ● Recording voice note...     │
│  Press ⌘N or button to stop    │
│  [00:02]                        │
└─────────────────────────────────┘
```

#### Voice Notes Surface (New tab in Full mode)
- **Tab label**: "Notes" (next to Summary, Actions, Pins)
- **List items**: Each voice note with timestamp
- **Pin support**: Pin important notes to summary
- **Edit**: Text area to edit transcripted text

#### Voice Note Card
```
┌─────────────────────────────────────┐
│ 📝 Remember to ask about budget    │
│ 🕐 12:34 PM                         │
│ 📌 [Pin]  [Delete]                 │
└─────────────────────────────────────┘
```

#### Compact/Roll Mode
- Voice notes appear as special markers in transcript
- Different icon/color from regular segments
- Click to expand and see full text

### 5. State Management (AppState.swift)

```swift
@Published var voiceNotes: [VoiceNote] = []
@Published var isRecordingVoiceNote: Bool = false
@Published var voiceNoteStartTime: Date?

// Computed
var voiceNotesCount: Int { voiceNotes.count }
var voiceNoteDuration: String { ... }
```

### 6. Export Integration

#### JSON Export
```json
{
  "transcript_segments": [...],
  "voice_notes": [
    {
      "id": "uuid",
      "text": "Remember to follow up",
      "start_time": 123.45,
      "end_time": 128.3,
      "created_at": "2026-02-14T12:34:56Z",
      "confidence": 0.92,
      "is_pinned": false
    }
  ],
  ...
}
```

#### Markdown Export
```markdown
# Meeting Notes

## Transcript
...

## Voice Notes
- **12:34 PM**: Remember to follow up with Sarah
- **12:40 PM**: Check the Q3 numbers
```

### 7. Session Bundle

Add `voice_notes.json` to session bundle:
```json
{
  "notes": [...]
}
```

## Implementation Plan

### Phase 1: Core Recording (P1)
1. Create `VoiceNoteCaptureManager.swift`
2. Add voice note state to `AppState`
3. Implement hotkey/button trigger
4. Add recording indicator UI
5. Backend WebSocket handler for voice note audio

### Phase 2: Transcription & Display (P1)
1. Transcribe voice notes via backend
2. Create `VoiceNote` model
3. Add Voice Notes surface to Full mode
4. Display notes in compact/roll mode as markers
5. Pin voice notes to summary

### Phase 3: Export & Persistence (P2)
1. Include voice notes in JSON export
2. Include voice notes in Markdown export
3. Save to session bundle
4. Load voice notes from history

### Phase 4: Polish & Enhancements (P2)
1. Edit voice note transcripts
2. Delete voice notes
3. Voice note search/filter
4. Audio playback of original voice note
5. Voice note tags/categories

## Technical Considerations

### Thread Safety
- Voice note audio capture must be thread-safe (use NSLock like other managers)
- Voice notes array updates must be @Published and MainActor

### Memory Management
- Don't keep raw audio for voice notes (transcription only)
- Consider max voice note duration (e.g., 30 seconds)

### Error Handling
- Handle microphone permission denial gracefully
- Show error if voice note transcription fails
- Allow re-recording if transcription fails

### Accessibility
- VoiceOver announcements for recording state changes
- Keyboard-only operation (hotkey + focus management)
- Clear visual indicators

### Privacy
- Voice notes are local-only (like transcripts)
- Clear user consent before recording
- Easy to delete individual notes

## Open Questions

1. **Maximum note duration**: Should we cap voice notes at 30s, 60s, or unlimited?
2. **Audio storage**: Should we keep the original audio or just transcription?
3. **Note categories**: Should notes be simple text or support tags/types?
4. **Voice activation**: Should we support VAD-based auto-stop, or only manual stop?
5. **Multiple concurrent notes**: Can user overlap multiple voice notes?

## Alternatives Considered

### Alternative 1: Use "both" mode with filtering
- Keep both system and mic audio in main transcript
- Add UI filter to show/hide mic segments
- **Rejected**: Doesn't provide the "quick note" mental model

### Alternative 2: Text-only notes
- Quick text input for notes (not voice)
- **Rejected**: Doesn't leverage ASR capability, user already has text editors

### Alternative 3: Always-on mic with marker
- Keep mic recording always on
- Press button to mark current moment as a note
- **Rejected**: More complex, less privacy-friendly

## Success Criteria

- [ ] User can start/stop voice note recording with hotkey or button
- [ ] Voice notes are transcribed and displayed separately
- [ ] Voice notes appear in Full mode Notes tab
- [ ] Voice notes appear in export (JSON + Markdown)
- [ ] Voice notes are saved to session bundle
- [ ] Recording state is visually clear
- [ ] Voice notes can be pinned to summary
- [ ] Error handling is graceful

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mic permission denied | High | Show clear permission prompt, fall back to text notes |
| Transcription fails | Medium | Show error, offer re-record or manual edit |
| Too many notes clutter UI | Low | Collapsible list, pagination, or limit to recent 10 |
| Audio quality poor | Medium | Show audio level indicator, warn if too quiet |
| User forgets to stop recording | Medium | Auto-stop after max duration (60s) with confirmation |

## Related Work

- TCK-20260213-001: Flow findings remediation (includes VOD-014: Voice note capture)
- TCK-20260212-004: StoreKit subscriptions (voice notes could be premium feature)
- TCK-20260212-014: Audio capture hardening (reusable patterns)

## Next Steps

1. **Review this design** with stakeholders
2. **Create tickets** for each phase
3. **Priority**: Start with Phase 1 (core recording)
4. **User testing**: Validate hotkey choice and UI placement
