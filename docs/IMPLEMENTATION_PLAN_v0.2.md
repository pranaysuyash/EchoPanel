SPEC: macOS Live Meeting Listener + Side Panel (v0.2)
Implementation Plan: Address v0.1 Audit + v0.2 Scope Decisions (Mic + Diarization + Onboarding + Auto-save + Multi-Model + Rolling Summary + NER/NLP)

Context
- v0.1 shipped quickly and meets the original v0.1 spec baseline.
- v0.2 explicitly expands requirements to include microphone capture and diarization (previously out-of-scope), plus productization items (onboarding, caching, autosave, multi-model).
- This plan is meant to be:
  (1) pasted to an implementation agent,
  (2) copied into docs as a tracking doc (recommend: docs/IMPLEMENTATION_PLAN_v0.2.md),
  (3) used to drive PR breakdown and acceptance tests.

Non-negotiable v0.2 Requirements (Explicit Spec Amendments)
R1. Audio capture must include BOTH:
  - System output audio (remote participants) via ScreenCaptureKit
  - Microphone audio (local participant) via AVAudioEngine
  - Must be capturable concurrently.
R2. UI must show:
  - Active capture sources (system/mic/both)
  - Live level meters per source
  - Recording/listening status with unambiguous consent indicators
R3. Permissions:
  - Screen Recording permission for system audio capture
  - Microphone permission for mic capture
  - Consent UX must be explicit and fail-safe (no silent background capture)
R4. Diarization is REQUIRED:
  - Speaker labels visible in transcript when available
  - Speaker segments included in JSON export
  - Fallback gracefully when diarization unavailable
  - Start with offline diarization at session end (not live)
R5. Storage:
  - Manual export remains (JSON + Markdown)
  - Auto-save periodically (default ON, configurable) + final save on session end
  - Storage owned by mac app (Application Support), with session folders and rolling snapshots
R6. ASR provider abstraction:
  - Multiple local Whisper variants
  - Optional cloud ASR behind same interface
  - Provider selectable per session and via global default
  - Cloud API key storage + cost disclaimer
R7. Confidence must be useful:
  - Low-confidence transcript segments marked “Needs review”
  - Cards (actions/decisions/risks) use thresholds: show as Draft below threshold or suppress
  - Confidence derived from real signals where possible (no constant 0.6 everywhere)
R8. Summaries must be useful:
  - Final output must include 3–8 bullet summary + actions + decisions + risks + entities(counts)
  - Rolling summary updates with new context during session (stable, non-chaotic UI)
R9. Entities must include counts + recency:
  - Track {name, type, count, first_seen, last_seen}
  - UI shows top entities by recency-weighted frequency
  - Entities clickable: filter transcript and cards (“grounding”)

Primary Goal
Upgrade v0.1 into a genuinely useful meeting tool without turning it into an untestable blob.

Architecture Decisions (to prevent future regret)
A1. Keep audio as separate tracks internally (tag each audio frame with source=system|mic).
A2. Do not mutate canonical transcript for “last 10 minutes” analysis. Use an analysis view/window.
A3. Store canonical transcript as append-only JSONL. Maintain derived state snapshots separately.
A4. Diarization starts as session-end batch; UI supports speaker labels but degrades cleanly.
A5. WS protocol changes are backward-compatible or versioned explicitly.

Deliverables
- Updated spec + WS contract docs (v0.2)
- mac app improvements: consent UX, onboarding, mic capture, autosave, updated UI
- backend improvements: WS accept source-tagged audio, ASR provider abstraction, analysis windowing, rolling summary, diarization events
- test coverage: unit + integration + manual checklists

--------------------------------------------------------------------------------
PR0: Docs-First Spec and Contract Update (Fast, Unblocks Everything)
Files:
- docs/live-listener-spec.md (bump to v0.2 or add v0.2 section)
- docs/WS_CONTRACT.md
- docs/IMPLEMENTATION_PLAN_v0.2.md (new; paste this plan)
Changes:
- Explicitly document:
  - audio sources: system/mic/both
  - permissions required and consent UX expectations
  - diarization requirements + UI behavior + export schema
  - storage requirements (periodic + final autosave) and retention defaults
  - ASR provider abstraction and config shape
  - confidence semantics and thresholds
  - rolling summary behavior
  - entity schema with counts/recency and click-to-filter behavior
Acceptance:
- Docs merged before feature work begins.
Notes:
- Prevent “failing spec on paper” by explicitly changing scope.

--------------------------------------------------------------------------------
PR1: macOS Safety and Consent (Stop-on-close + Permission UX)
Files:
- macapp/MeetingListenerApp/Sources/SidePanelController.swift
- macapp/MeetingListenerApp/Sources/AppState.swift
- macapp/MeetingListenerApp/Sources/SidePanelView.swift
Changes:
1) Stop-on-close (Privacy-critical)
- SidePanelController conforms to NSWindowDelegate
- panel.delegate = self
- windowWillClose triggers AppState.stopSession() / onEndSession callback
- stop must be idempotent (closing + clicking “End Session” should not double-stop or crash)

2) Permission UX clarity
- AppState exposes explicit permission states:
  - PermissionRequired(ScreenRecording)
  - PermissionRequired(Microphone)
  - Ready
  - Error(message)
- Replace confusing “Reconnecting” text for permission errors
- Add banner with “Open Settings” buttons:
  - Screen Recording: x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
  - Microphone: x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone

3) Consent indicators
- While capturing: visible “Listening” badge (already exists) + explicit sources active
Acceptance:
- Closing side panel stops capture and WS streaming within 1s.
- Permission denied states never start capture.
- UI shows correct CTA to enable permissions.

Manual Verification:
- Start session, close window via red X → session ends; server receives end; UI returns to idle.
- Deny screen recording → UI shows Screen Recording required + Open Settings.
- Deny mic → UI shows Microphone required + Open Settings.

--------------------------------------------------------------------------------
PR2: Audio Capture v0.2 (System + Microphone, Source-tagged)
Files:
- macapp/MeetingListenerApp/Sources/AudioCapture/ (new module)
- macapp/MeetingListenerApp/Sources/AppState.swift
- macapp/MeetingListenerApp/Sources/SidePanelView.swift
Changes:
1) Microphone capture
- Implement mic capture with AVAudioEngine
- Support mic-only / system-only / both

2) Source tagging
- Every outgoing audio frame includes source="system"|"mic"
- Keep tracks separate (no mixing yet)

3) UI source selector + level meters
- Selector: System | Mic | Both (default Both)
- Show two meters: System level + Mic level
- Add note/warning for potential echo when Both selected (rare but real)

Acceptance:
- With Both: remote speaker + local speaker both appear in transcript (assuming meeting audio is in system output and local voice in mic).
- With Mic only: local voice transcribes; remote participants may not.
- With System only: remote audio transcribes; local voice may not.
- UI clearly indicates active sources and shows meters moving.

Manual Verification:
- Play YouTube audio (system) and speak (mic), confirm both streams are captured when Both selected.

--------------------------------------------------------------------------------
PR3: Backend WS Contract Update + ASR Provider Abstraction (Local + Cloud Ready)
Files:
- server/api/ws_live_listener.py
- server/services/asr/ (new)
  - base.py (ASRProvider interface)
  - local_faster_whisper.py
  - cloud_stub.py (config-driven placeholder)
- server/services/analysis_stream.py (adjust for new transcript schema)
Changes:
1) WS input supports source-tagged audio frames
- Update protocol for audio frames to include source
- Maintain backward compatibility if old clients send raw audio without source (default to "system")

2) ASRProvider abstraction
- Remove hard-coded model name usage in server
- Session config includes:
  - asr.provider: "local_whisper" | "cloud_x"
  - asr.model: "base" | "small" | "medium" | "large-v3-turbo" etc
  - asr.language, asr.vad, etc
- Cloud provider path exists but may be disabled until keys provided

3) ASR output schema improvements
- Transcript segment includes:
  - id
  - t0, t1
  - text
  - confidence (real metric if possible)
  - source ("system"|"mic")
  - speaker (optional, later)
Acceptance:
- Local Whisper still works end-to-end.
- Source tags are preserved through to client.
- Provider config does not break existing flow.

Tests:
- Integration test: WS audio frame with source → transcript event includes same source.

--------------------------------------------------------------------------------
PR4: Analysis Quality + Rolling Summary + NER/NLP Statefulness (Useful, Stable)
Files:
- server/services/analysis_stream.py
- server/api/ws_live_listener.py
- macapp/MeetingListenerApp/Sources/AppState.swift
- macapp/MeetingListenerApp/Sources/SidePanelView.swift
- macapp/MeetingListenerApp/Sources/Models/ (new or existing)
Changes:
A) Analysis windowing (spec compliance)
- Compute analysis_view = transcript segments within last 10 minutes by timestamp
- Do NOT mutate full transcript state used for export

B) Entities with counts/recency
- Maintain entity map:
  - {name, type, count, first_seen, last_seen}
- Provide recency-weighted ranking (simple decay or “last 10 min” toggle)
- De-dup entities (case-normalize)

C) Cards improvements (actions/decisions/risks)
- De-dup similar cards
- Sort by recency before truncating to N
- Add owner + due parsing heuristics:
  - "I will..." → owner inferred from speaker when diarization exists, else Unknown/Self
  - "@name" or "Name will" → owner=Name
  - parse due: tomorrow/next Friday/EOD

D) Confidence semantics
- Transcript: compute confidence from ASR metrics where available; else heuristic based on segment length + stability
- Cards: confidence derived from multiple signals (keyword match + structure + presence of due/owner + repetition)
- UI behavior:
  - Transcript segments below threshold show “Needs review”
  - Cards below threshold shown as “Draft” or suppressed based on setting

E) Rolling summary updates
- Maintain rolling state:
  - memory_summary (max 8–12 bullets)
  - open_loops (questions/unresolved)
  - running_actions (dedup)
- Update cadence: every 30–60 seconds OR every N words
- UI must avoid flicker:
  - show last_updated timestamp
  - highlight changed bullets only (or “New” badge)

F) UI updates (minimal, high-impact)
- Transcript modes:
  - Live (partial)
  - Final (timed)
  - Speakers (when diarization available)
- Right column:
  1) Rolling Summary
  2) Cards (Actions/Decisions/Risks)
  3) Entities (clickable chips with counts, filter transcript/cards)

Acceptance:
- Latest cards are actually “latest” (recency sorted).
- Entities show counts and last_seen; clicking filters transcript and cards.
- Rolling summary updates periodically without rewriting everything each time.
- Low-confidence segments visibly marked.

Tests:
- Unit tests for:
  - 10-minute window selection by timestamp
  - entity count increments and last_seen updates
  - card dedup + recency truncation
- Integration test:
  - Feed transcript segments across time, ensure analysis_view uses last 10 minutes.

--------------------------------------------------------------------------------
PR5: Diarization (Required) + Speaker Labels in UI and Export
Files:
- server/services/diarization.py (existing) or server/services/diarization/ (refactor)
- server/api/ws_live_listener.py
- macapp/MeetingListenerApp/Sources/Models/TranscriptSegment.swift
- macapp/MeetingListenerApp/Sources/SidePanelView.swift
Changes:
1) Diarization pipeline first-class
- Config-driven enable (but v0.2 requires it available and working)
- Batch diarization at session end initially
- Emit diarization segments over WS:
  - {speaker, t0, t1, confidence(optional)}

2) Transcript speaker labeling
- On client:
  - merge diarization segments with transcript segments (time overlap)
  - label transcript with Speaker A/B
  - add “Speakers” mode view
- Fallback:
  - If diarization fails or disabled, transcript renders with no speaker labels

3) Export updates
- final.json includes diarization segments
- final.md includes speaker labels when available

Acceptance:
- When diarization enabled and token present: transcript displays speaker labels; export contains diarization data.
- When diarization unavailable: app continues; no crash; UI indicates “Speakers unavailable”.

Tests:
- Unit: diarization merge logic in client (time overlap assignment)
- Integration: WS final includes diarization field when enabled.

--------------------------------------------------------------------------------
PR6: Storage (Auto periodic + Final) Owned by macOS App + Recovery
Files:
- macapp/MeetingListenerApp/Sources/Storage/SessionStore.swift (new)
- macapp/MeetingListenerApp/Sources/AppState.swift
- macapp/MeetingListenerApp/Sources/SidePanelView.swift (Settings UI)
Changes:
1) Session folder structure
- ~/Library/Application Support/EchoPanel/Sessions/<sessionId>/
  - transcript.jsonl (append)
  - state.json (overwrite snapshot)
  - final.json (on end)
  - final.md (on end)

2) Auto-save
- Timer (default 30s, configurable)
- Toggle in settings:
  - “Auto-save session locally” (default ON) + explanation
- Retention policy:
  - keep last N sessions or N days (configurable)

3) Crash recovery
- On app launch: detect incomplete sessions, offer “Resume/Recover” view
- At minimum: allow user to export from last snapshot

Acceptance:
- Force quit app mid-session → reopen shows recoverable session state.
- Auto-save writes periodically; final writes on end.
- Manual export still works.

Tests:
- Unit: session store path creation and write operations
- Manual: crash recovery happy path.

--------------------------------------------------------------------------------
PR7: Onboarding + Model Preload/Cache + Self-test
Files:
- macapp/MeetingListenerApp/Sources/Onboarding/ (new)
- macapp/MeetingListenerApp/Sources/AppState.swift
- macapp/MeetingListenerApp/Sources/Settings/ (new or existing)
Changes:
1) Onboarding wizard (first run)
Steps:
- What is captured (system/mic), why, privacy stance
- Permission requests in order:
  1) Screen Recording
  2) Microphone (only if mic/both selected)
- Choose ASR provider (local default) + model size
- Model preload/download + warmup states:
  - Downloading, Verifying, Warming up, Ready
- Self-test:
  - System audio test (play a sample)
  - Mic test (detect input level)
  - Show “Ready”

2) Model cache
- Ensure model artifacts are cached before first real meeting
- Avoid first-run “surprise download” during live meeting

3) Cloud provider setup (optional)
- Allow entering API key if user selects cloud ASR
- Show cost disclaimer and when it will be used

Acceptance:
- First run walks user to a “Ready” state.
- No model download surprises on first actual session.
- Permission denials handled with clear remediation.

--------------------------------------------------------------------------------
Protocol Additions (WS Contract) Summary
Input:
- audio_frame: {session_id, source: "system"|"mic", pcm16_base64, sample_rate, channels, t_client(optional)}

Output:
- transcript_partial: {segment_id, t0, t1_est, text, confidence, source, speaker(optional)}
- transcript_final: {segment_id, t0, t1, text, confidence, source, speaker(optional)}
- analysis_update: {actions[], decisions[], risks[], entities[], topics(optional)}
- summary_update: {bullets[], open_loops[], last_updated_ts}
- diarization_final: {segments:[{speaker, t0, t1, confidence(optional)}]}
- final_summary: {markdown, json} (must not be placeholder)

--------------------------------------------------------------------------------
Testing Strategy (Incremental, High-leverage)
Unit Tests
- server/services/analysis_stream.py:
  - analysis_view windowing by timestamps
  - entity map counts/last_seen
  - card dedup + recency truncate
- client diarization merge:
  - assign speaker labels by overlap
- storage:
  - session folder creation + writes

Integration Tests
- WS end-to-end:
  - audio_frame(system) + audio_frame(mic) → transcript includes sources
  - analysis_update uses last 10 minutes only
  - final_summary includes non-placeholder markdown + final.json with entities(counts) and diarization segments

Manual Test Checklist (Must pass for each PR)
- Stop-on-close stops capture and streaming
- Permissions denied never start capture; correct CTA displayed
- System-only/mic-only/both capture works and meters reflect input
- Rolling summary updates without UI flicker
- Entities clickable filters transcript/cards
- Auto-save + crash recovery works
- Diarization on/off behaves correctly

--------------------------------------------------------------------------------
PR Ordering (Recommended)
1) PR0 Docs + WS contract
2) PR1 Stop-on-close + permissions UX (privacy-critical)
3) PR2 Mic capture + source tagging (product correctness)
4) PR3 ASR provider abstraction (multi-model foundation)
5) PR4 Windowing + entity counts + rolling summary + confidence behavior + UI updates (usefulness)
6) PR6 Storage autosave + recovery (reliability)
7) PR5 Diarization integration + speaker labels (required, isolated)
8) PR7 Onboarding + model preload (polish, reduces first-run pain)
