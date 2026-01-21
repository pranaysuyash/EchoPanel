# SPEC: macOS Live Meeting Listener + Side Panel (v0.1)

## 0) One-line definition
A macOS menu bar app that captures system audio live, streams it to a backend for streaming ASR, and renders a floating side panel with live transcript plus continuously updating Actions, Decisions, Risks, and Entities.

## 1) Problem and wedge
People do not reliably record meetings. Integrations with Meet or Zoom are optional and heavy. The wedge is: capture audio locally on the Mac with one click, then produce usable meeting artifacts in real time.

## 2) Target user and scenarios
Primary user:
- Founder, PM, recruiter, agency owner who runs meetings daily and wants decisions and action items without doing admin work.

Primary scenarios:
- Joining any meeting and wanting live notes.
- Reviewing the meeting summary immediately after the call ends.
- Copying action items into a doc or task tool.

## 3) Hard constraints
- No integrations with Zoom or Meet calendar or APIs in v0.1.
- Must work for any audio playing on the Mac.
- User consent is mandatory for Screen Recording permission.
- v0.1 prioritizes shipping and trust over feature depth.

## 4) Non-goals
- Joining meetings as a bot.
- Multi-user collaboration, sharing workspaces, team accounts.
- Full search across historical meetings.
- Per-speaker diarization as a core feature.
- Video capture or screen capture as a requirement.
- Perfect clip generation or highlight reels.
- Model switching UI, agent frameworks in-app, prompt editing UI.

## 5) Product requirements
### 5.1 Minimal flow
- Menu bar icon with Start or Stop.
- On Start:
  - Request or verify required permissions.
  - Begin system audio capture.
  - Open floating side panel.
  - Start streaming to backend.
- During capture:
  - Show live transcript.
  - Refresh analysis cards periodically.
  - Update entity list periodically.
- On Stop:
  - Stop capture.
  - Request final consolidation summary.
  - Provide export actions.

### 5.2 UX requirements
Menu bar:
- State: Idle, Listening, Error.
- Start or Stop is a single obvious toggle.
- Show current session timer.

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
  - Actions: text, owner, due, confidence.
  - Decisions: text, confidence.
  - Risks: text, confidence.
- Entities:
  - name, type, last_seen time, confidence.
- Controls:
  - Copy Markdown
  - Export JSON
  - End session
  - Audio quality indicator
- Minimal theming.
- Keyboard shortcuts: Cmd+Shift+L, Cmd+C.

### 5.3 Trust and observability
- Display audio quality: Good, OK, Poor.
- Display a small status line.
- All outputs show confidence numbers.

## 6) Technical architecture
### 6.1 High-level components
- macOS app in Swift and SwiftUI:
  - Capture system audio via ScreenCaptureKit.
  - Convert audio sample buffers to streamable frames.
  - Maintain WebSocket connection to backend.
  - Render UI and handle session state.
- Backend:
  - WebSocket endpoint for ingesting audio frames.
  - Streaming ASR.
  - Periodic analysis jobs.
  - Final consolidation on session end.
  - Optional session storage.

### 6.2 Capture method
- Use ScreenCaptureKit to capture system audio output.
- No virtual audio drivers required in v0.1.
- If ScreenCaptureKit is unavailable, show unsupported and exit.

### 6.3 Streaming strategy
- Use PCM16 16 kHz mono frames over WebSocket.

Client audio pipeline:
- Capture audio at native sample rate.
- Downmix to mono.
- Downsample to 16 kHz.
- Convert float to Int16 PCM.
- Send in fixed frame sizes.

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
- ASR partials as available.
- Entities update every 10 to 20 seconds.
- Cards update every 30 to 60 seconds.
- Final consolidation on stop.

### 6.6 Storage
- Store session transcript and final outputs locally as JSON.
- Optional backend storage.

## 7) Permissions and compliance
- Screen Recording permission required.
- User must initiate capture with explicit action.
- Provide clear onboarding.
- Add a visible listening indicator.

## 8) Distribution and packaging
- Distribute from website as DMG or ZIP.
- Must code-sign with Developer ID and notarize.
- Apple Developer Program membership required.

## 9) Milestones and acceptance criteria
### Milestone M0: UI shell
- Menu bar app launches.
- Start or Stop toggles.
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
- Transcript updates within 2 to 5 seconds of speech.
- Final segments do not duplicate excessively.

### Milestone M4: Live analysis
- Entities and cards update on cadence.
Acceptance:
- Entities list refreshes.
- Actions, Decisions, Risks update at least every 60 seconds.

### Milestone M5: Finalization and export
- Stop produces final summary and exports.
Acceptance:
- Copy Markdown works.
- Export JSON writes a file.
- Session saved locally.

## 10) Edge cases
- No audio playing: show no audio detected after N seconds.
- Very low volume: show poor audio warning.
- Backend unavailable: show offline state and optionally buffer limited audio locally.
- Long sessions: cap memory, flush transcript to disk periodically.

## 11) Open decisions
- Backend ASR engine choice: use existing antigravity pipeline.
- Buffering strategy when backend disconnects: default none.
- Diarization off in v0.1.
- PII handling: display and export only.
