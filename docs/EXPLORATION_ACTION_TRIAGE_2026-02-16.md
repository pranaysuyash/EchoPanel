# Exploration Action Triage

**Date:** 2026-02-16  
**Type:** DOCS / BACKLOG TRIAGE  
**Purpose:** Convert exploration/discussion outputs into explicit ticket dispositions so future audit passes can skip already-resolved items.

## Sources Triaged

- `docs/FEATURE_EXPLORATION_PERSONAS.md`
- `docs/REMAINING_IMPROVEMENTS_2026-02-14.md`
- `docs/ui-design-v2/COMPLETE_FEATURE_ANALYSIS.md`
- `docs/discussion-asr-overload-analysis-2026-02-14.md`
- `docs/discussions/DISCUSSION_OCR_PIPELINE_2026-02-14.md`
- `docs/audit/pipeline-intelligence-layer-20260214.md`

## Can/Should Do Now

| Priority | Item | Ticket | Status | Notes |
|---|---|---|---|---|
| P1 | Denied-permissions verification (screen + mic) | `DOC-003` | OPEN | Manual QA checklist already created. |
| P1 | Data & Privacy: live stat refresh while settings open | `TCK-20260214-074` | OPEN | Core dashboard exists; real-time refresh remains. |
| P1 | Data retention controls in settings (30/60/90/180/365/Never) | `TCK-20260214-075` | OPEN | Cleanup engine exists; UI controls remain. |
| P1 | Minutes of Meeting generator (persona F2) | `TCK-20260216-001` | OPEN | Selected as immediate v0.4 candidate. |
| P1 | Share flow (Slack/Teams/Email) (persona F3) | `TCK-20260216-002` | OPEN | Selected as immediate v0.4 candidate. |
| P1 | Meeting templates (persona F6) | `TCK-20260216-003` | OPEN | Selected as immediate v0.4 candidate. |
| P1 | UI-v2 companion panel form factor (phase 1) | `TCK-20260216-005` | OPEN | Ticketized from UI V2 roadmap as core UX direction. |
| P1 | UI-v2 live panel source selector | `TCK-20260216-006` | OPEN | Move source control from settings-only to in-context live panel. |
| P1 | UI-v2 transcript state clarity (partial vs final text) | `TCK-20260216-007` | OPEN | Improve live-readability and confidence while streaming. |
| P2 | UI-v2 real-time speaker labels in live transcript | `TCK-20260216-008` | OPEN | Dependent on stable live diarization signal path. |
| P2 | UI-v2 panel width presets (Narrow/Medium/Wide) | `TCK-20260216-009` | OPEN | Improves alongside-meeting ergonomics. |
| P2 | Calendar integration + auto-join spike (persona F1) | `TCK-20260216-010` | OPEN | Near-term exploration item promoted to explicit backlog ticket. |
| P2 | Action-item sync to task managers spike (persona F5) | `TCK-20260216-011` | OPEN | Near-term workflow integration item promoted to ticket. |
| P2 | OCR pipeline completion (frame capture + privacy controls) | `TCK-20260216-012` | OPEN | Discussion follow-up beyond initial OCR scaffolding. |

## Resolved (Skip In Next Pass)

| Item | Ticket | Resolution Evidence |
|---|---|---|
| Settings plain-language labels | `TCK-20260214-073` | `SettingsView.swift` uses "Transcription Model", "Cloud API Token", plain-language audio source labels, and `.help(...)` text. |
| Audio EMA lock hardening | `TCK-20260214-077`, `TCK-20260214-083` | `AudioCaptureManager.swift` uses `qualityLock`; `MicrophoneCaptureManager.swift` uses `levelLock` for EMA reads/writes. |
| Keyboard shortcut cheatsheet | `TCK-20260214-078` | `KeyboardCheatsheetView.swift` exists with category grouping and search filter; wired in `MeetingListenerApp.swift`. |
| Menu bar server status visibility | `TCK-20260214-081` | Badge overlay + tooltip + menu status text in `MeetingListenerApp.swift`. |
| Pipeline quick wins (activity-gated analysis, embedding LRU, embedding preload) | `TCK-20260214-082` | `_analysis_loop` gating in `ws_live_listener.py`; LRU/metrics in `embeddings.py`; startup warmup in `main.py`. |
| RAG/NER docs drift correction | `TCK-20260214-076` | Implementation status + explicit gap-tracking references in `docs/RAG_PIPELINE_ARCHITECTURE.md` and `docs/NER_PIPELINE_ARCHITECTURE.md`. |
| OCR hybrid architecture planning | `TCK-20260214-089` | Acceptance criteria already complete in ticket and plan doc. |

## Deferred / Decision-Dependent

| Item | Ticket | Reason |
|---|---|---|
| Offline graceful-behavior verification | `DOC-002` | BLOCKED until local environment can run with network disabled. |
| Event-driven analysis rewrite | `TCK-20260214-085` | Deferred after QW optimization + LLM integration; revisit after perf baseline. |
| ML-based NER replacement | `TCK-20260214-086` | Deferred pending quality benchmark target and runtime budget decision. |
