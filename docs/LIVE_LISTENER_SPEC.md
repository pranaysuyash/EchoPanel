# SPEC: macOS Live Meeting Listener + Side Panel (v0.1)

## 0) One-line definition
A macOS menu bar app that captures system audio live, streams it to a backend for streaming ASR, and renders a floating side panel with live transcript plus continuously updating Actions, Decisions, Risks, and Entities.

## 1) Problem and wedge
People do not reliably record meetings. Integrations with Meet/Zoom are optional and heavy. The wedge is: capture audio locally on the Mac with one click, then produce usable meeting artifacts in real time.

## 2) Target user and scenarios
Primary user:
- Founder/PM/recruiter/agency owner who runs meetings daily and wants decisions and action items without doing admin work.

Primary scenarios:
- Joining any meeting (Meet in browser, Zoom app, Teams, video playback, in-person audio) and wanting live notes.
- Reviewing the meeting summary immediately after the call ends.
- Copying action items into a doc or task tool.

## 3) Hard constraints
- No integrations with Zoom/Meet calendar or APIs in v0.1.
- Must work for any audio playing on the Mac (system audio output), not just browser tabs.
- User consent is mandatory (Screen Recording permission). App must not attempt silent capture.
- v0.1 prioritizes shipping and trust over feature depth.

## 4) Non-goals (explicitly out of scope for v0.1)
- Joining meetings as a bot.
- Multi-user collaboration, sharing workspaces, team accounts.
- Full search across historical meetings.
- Per-speaker diarization as a core feature (optional later).
- Video capture or screen capture as a requirement (audio only).
- Perfect clip generation or highlight reels.
- Model switching UI, agent frameworks in-app, prompt editing UI.

## 5) Product requirements
### 5.1 Minimal flow
- Menu bar icon with Start/Stop.
- On Start:
  - Request or verify required permissions.
  - Begin system audio capture.
  - Open floating side panel.
  - Start streaming to backend.
- During capture:
  - Show live transcript (partials and finals).
  - Refresh analysis cards periodically.
  - Update entity list periodically.
- On Stop:
  - Stop capture.
  - Request final consolidation summary.
  - Provide export actions (copy Markdown, download JSON).

### 5.2 UX requirements
Menu bar:
- State: Idle, Listening, Error.
- Start/Stop is a single obvious toggle.
- Show current session timer (mm:ss).

Floating side panel:
- Three lanes only:
  1) Transcript
  2) Cards: Actions, Decisions, Risks
  3) Entities: People, Orgs, Dates, Projects, Topics
- Transcript:
  - Append-only view.
  - Partial lines shown with lighter style.
  - Final lines replace partials cleanly.
  - Each final segment has a timestamp.
- Cards:
  - Actions: text, owner (optional), due (optional), confidence.
  - Decisions: text, confidence.
  - Risks: text, confidence.
- Entities:
  - name, type, last_seen time, confidence.
- Controls:
  - Copy Markdown
  - Export JSON
  - End session
  - Audio quality indicator (Good/OK/Poor)
- Minimal theming:
  - Clean, premium, readable.
  - Keyboard shortcuts: Cmd+Shift+L (toggle listen), Cmd+C (copy markdown from panel).

### 5.3 Trust and observability
- Display audio quality: Good/OK/Poor derived from simple signal heuristics (RMS level, clipping rate, silence ratio).
- Display a small status line: Streaming, Reconnecting, Backend unavailable.
- All outputs show confidence numbers. Low confidence should be visibly labeled.

## 6) Technical architecture
### 6.1 High-level components
- macOS app (Swift + SwiftUI):
  - Capture system audio via ScreenCaptureKit (macOS 13+).
  - Convert audio sample buffers to streamable frames.
  - Maintain WebSocket connection to backend.
  - Render UI and handle session state.
- Backend (existing antigravity stack preferred):
  - WebSocket endpoint for ingesting audio frames.
  - Streaming ASR (partial + final).
  - Periodic analysis jobs for actions/decisions/risks/entities.
  - Final consolidation on session end.
  - Optional session storage.

### 6.2 Capture method
- Use ScreenCaptureKit to capture system audio output.
- No virtual audio drivers required in v0.1.
- If ScreenCaptureKit is unavailable (macOS < 13), show Unsupported and exit gracefully.

### 6.3 Streaming strategy
Choose one for v0.1:
- Preferred: PCM16 16 kHz mono frames over WebSocket (lower latency, simpler for ASR ingest).
- Alternative: Opus chunks (lower bandwidth, requires decode pipeline).

v0.1 selection: PCM16 16 kHz mono.

Client audio pipeline:
- Capture audio at native sample rate (often 48 kHz).
- Downmix to mono.
- Downsample to 16 kHz.
- Convert float to Int16 PCM.
- Send in fixed frame sizes (for example 20 ms = 320 samples at 16 kHz).

### 6.4 WebSocket contract
Client to server:
- Binary messages: raw Int16 PCM frames, little-endian, mono, 16 kHz.
- JSON control messages:
  - {"type":"start","session_id":"uuid","sample_rate":16000,"format":"pcm_s16le","channels":1}
  - {"type":"stop","session_id":"uuid"}

Server to client:
- ASR events:
  - {"type":"asr_partial","t0":123.40,"t1":126.20,"text":"we should ship by friday","stable":false}
  - {"type":"asr_final","t0":123.40,"t1":126.20,"text":"We should ship by Friday.","stable":true}
- Analysis events:
  - {"type":"cards_update","actions":[...],"decisions":[...],"risks":[...],"window":{"t0":0,"t1":420}}
  - {"type":"entities_update","people":[...],"orgs":[...],"dates":[...],"projects":[...],"topics":[...]}
- Status events:
  - {"type":"status","state":"streaming|reconnecting|error","message":"..."}
- Final event:
  - {"type":"final_summary","markdown":"...","json":{...}}

Data shapes:
- Action: {"text":"...","owner":"...","due":"YYYY-MM-DD","confidence":0.0-1.0,"evidence":[{"t0":...,"t1":...,"quote":"..."}]}
- Decision: {"text":"...","confidence":...,"evidence":[...]}
- Risk: {"text":"...","confidence":...,"evidence":[...]}
- Entity: {"name":"...","last_seen":123.4,"confidence":...}

### 6.5 Analysis cadence
- ASR partials: as available (streaming).
- Entities update: every 10-20 seconds.
- Cards update: every 30-60 seconds with a sliding context window (last N minutes, N default 10).
- Final consolidation: on stop, run one last pass over full transcript.

### 6.6 Storage
v0.1 minimal:
- Store session transcript and final outputs locally (app sandbox) as JSON.

Optional backend storage:
- Server stores per-session logs for replay/debug.

## 7) Permissions and compliance
- Screen Recording permission required for ScreenCaptureKit capture.
- User must initiate capture with explicit action.
- Provide clear onboarding:
  - Why permission is needed.
  - How to enable it in System Settings.
- Add a visible Listening indicator in panel and menu bar.

## 8) Distribution and packaging
- Distribute from website as DMG or ZIP.
- Must code-sign with Developer ID and notarize to avoid Gatekeeper friction.
- Apple Developer Program membership required for Developer ID cert.

## 9) Milestones and acceptance criteria
### Milestone M0: UI shell
- Menu bar app launches.
- Start/Stop toggles.
- Side panel opens and closes.
Acceptance:
- App runs without crashes for 10 minutes idle.

### Milestone M1: Audio capture
- ScreenCaptureKit captures system audio.
- Audio quality meter updates.
Acceptance:
- Captured audio produces non-zero RMS when audio plays.
- Silence ratio increases when audio stops.

### Milestone M2: Streaming
- WebSocket connects and streams PCM frames.
- Reconnect logic works.
Acceptance:
- Backend receives continuous frames for 5 minutes without drift.
- On network disconnect, app recovers within 10 seconds.

### Milestone M3: Live transcript
- Partial and final transcript events render correctly.
- Timestamped segments appear.
Acceptance:
- Transcript updates within 2-5 seconds of speech.
- Final segments do not duplicate excessively.

### Milestone M4: Live analysis
- Entities and cards update on cadence.
Acceptance:
- Entities list refreshes.
- Actions/Decisions/Risks update at least every 60 seconds.

### Milestone M5: Finalization + export
- Stop produces final summary and exports.
Acceptance:
- Copy Markdown works.
- Export JSON writes a file.
- Session saved locally.

## 10) Edge cases
- No audio playing: show No audio detected after N seconds.
- Very low volume: show Poor audio warning.
- Backend unavailable: show offline state and optionally buffer limited audio locally (optional).
- Long sessions: cap memory, flush transcript to disk periodically.

## 11) Open decisions (pick defaults for v0.1)
- Backend ASR engine choice: use existing antigravity pipeline.
- Buffering strategy when backend disconnects: default none (show error), optional ring buffer later.
- Diarization: off in v0.1.
- PII handling: display and export only; redaction optional later.

