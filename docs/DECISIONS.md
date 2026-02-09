# Decisions

This is a lightweight decision log. Prefer short entries that explain why.

## v0.1
- Capture: Use ScreenCaptureKit (macOS 13+) to capture system audio output without virtual drivers.
- Streaming: Use WebSocket; stream PCM16 16 kHz mono frames.
- UI: Three lanes only in the side panel (Transcript, Cards, Entities).
- No diarization in v0.1.

## v0.2
- Multi-source audio: JSON-tagged frames with `source: "system" | "mic"` instead of raw binary.
- Diarization: batch-only at session end via pyannote; requires user-provided HuggingFace token; disabled by default.
- Session storage: auto-save every 30s with crash recovery.
- Embedded backend: macOS app starts/stops the Python server automatically.

## v0.3 (planned)

### LLM-Powered Analysis Strategy (decided 2026-02-06)

**Decision**: Hybrid approach — keyword extraction as default, LLM as opt-in upgrade via user's own API key (Option D+B).

**Why**: Preserves "works offline out of the box" while enabling production-quality analysis for users who want it.

**Options evaluated**:

| Option | Description | Rejected because |
|--------|-------------|-----------------|
| A: Ollama (local LLM) | Bundle or require Ollama + 2-4GB model | Requires 6-8GB RAM total (Whisper + LLM); 8GB M1 Air can't handle both; adds install friction |
| B: User's own cloud API key | User enters OpenAI/Anthropic key in Settings | **Selected** — no infrastructure on our side, ~$0.01-0.05/meeting, audio never leaves Mac |
| C: Our hosted API | We run the LLM, user connects to our backend | Requires servers, user accounts, auth, billing, Stripe, GDPR, on-call — too heavy for solo dev |
| D: Hybrid default | Keyword extraction default + optional LLM | **Selected** — combined with B as the LLM path |

**Key architectural constraints**:
- The LLM never touches audio. It only processes transcript text that ASR already produced locally.
- Audio capture (ScreenCaptureKit) and ASR (faster-whisper) always run locally — this never changes.
- Privacy story: "Audio never leaves your Mac. Transcript text can optionally be sent to your own LLM provider for enhanced analysis."
- No user accounts, no auth, no billing infrastructure needed. User pays their LLM provider directly.
- Keyword extraction remains the always-available fallback (offline, zero cost, zero setup).

**Implementation scope**:
- Add `ECHOPANEL_LLM_PROVIDER` env var / Settings UI (values: `none`, `openai`, `ollama`)
- Add `ECHOPANEL_OPENAI_API_KEY` setting (stored in macOS Keychain, not env var)
- `analysis_stream.py`: add LLM path alongside keyword path for `extract_cards()`, `extract_entities()`, `generate_rolling_summary()`
- No changes to ASR pipeline, WebSocket protocol, or audio capture

**What would change this decision**:
- If Ollama adds a lightweight 1B model with good extraction quality that runs in <1GB RAM → reconsider Option A
- If user demand for "fully offline LLM" is strong in beta feedback → add Ollama as second LLM provider
- If we raise funding or find a co-founder → reconsider Option C (hosted API)

### Commercialization Strategy (decided 2026-02-06)

**Decision**: Hybrid (A+B) — monetize the packaged macOS app; open-source the backend/protocol.

**Why**: Privacy/local-only wedge is real and defensible. Open-sourcing the backend builds trust ("look, no exfiltration") without commoditizing the hard part (macOS capture + permissions + UX).

**Details**: See `docs/audit/COMMERCIALIZATION_STRATEGY_AUDIT_2026-02.md`

### Gap Priorities (decided 2026-02-06)

**Decision**: Address gaps in this order: (1) NLP quality via LLM, (2) Silero VAD, (3) Distribution blockers.

**Why**: NLP quality is the #1 difference between "toy" and "product." VAD prevents hallucinations. Distribution unblocks external users.

**Details**: See `docs/audit/GAPS_ANALYSIS_2026-02.md`

### ASR Provider Strategy — Voxtral Transcribe 2 (researched 2026-02-08)

**Decision**: Try Voxtral Realtime (4B, open-source) locally as alternative ASR provider. Keep pyannote for diarization. Voxtral Mini Transcribe V2 (paid API) is optional/future — only pursue if paid plan is justified.

**Why**: Voxtral Realtime is Apache 2.0 open weights — can self-host for free with no API key. 4B params is feasible on Apple Silicon. Better accuracy than Whisper large-v3 at sub-200ms latency. Diarization stays with pyannote since V2 (the only Voxtral model with native diarization) is API-only and paid.

**What we're doing**:

| Component | Now | Future (if paid justified) |
|-----------|-----|---------------------------|
| Live transcription | Faster-Whisper (default) + Voxtral Realtime local (try out) | Voxtral Realtime API ($0.006/min) |
| Diarization | pyannote (keep as-is) | Voxtral Mini Transcribe V2 API ($0.003/min) |

**Key facts**:
- Voxtral Realtime: 4B params, Apache 2.0, open weights on HuggingFace — free to self-host
- Voxtral Mini Transcribe V2: API-only (not open-source), $0.003/min, native diarization — skip for now
- Mistral API has free "Experiment" tier for testing if we want to try V2 later
- Same PCM16/16kHz input format EchoPanel already uses — no capture changes needed
- pyannote stays for diarization — already works, no reason to replace with a paid API

**What would change this decision**:
- If Voxtral Realtime runs well locally on M1 8GB → could become default over Faster-Whisper
- If Mistral open-sources V2 with diarization → could replace pyannote for free
- If paid V2 diarization quality is significantly better than pyannote → justify the API cost

**Details**: See `docs/VOXTRAL_RESEARCH_2026-02.md`

