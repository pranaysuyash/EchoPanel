# Server Models / Latency / Error Audit (2026-02-06)

## 1) Scope contract
- In-scope:
  - EchoPanel model configuration and runtime behavior for ASR/diarization.
  - Observed latency/error evidence from EchoPanel code/logs and model-lab artifacts.
  - Cross-check with model-lab docs/runs for benchmark context.
- Out-of-scope:
  - Implementing fixes.
  - Product strategy recommendations beyond ticket-ready findings.
- Behavior change allowed: NO

## 2) What exists today (Observed only)
- EchoPanel server ASR pipeline uses a provider abstraction with one registered provider (`faster_whisper`) and chunked streaming (`server/services/asr_stream.py:22`, `server/services/provider_faster_whisper.py:45`).
- EchoPanel runtime default model from env/config path is `base` (`server/services/asr_stream.py:25`).
- macOS Settings exposes model choices `base`, `small`, `medium`, `large-v3-turbo` (`macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift:344`).
- Diarization execution is currently commented out in session stop flow (`server/api/ws_live_listener.py:313`).
- Backpressure (dropped frame) is tracked/logged, but no built-in ASR latency/error-rate counters are emitted by EchoPanel session code (`server/api/ws_live_listener.py:137`, `server/api/ws_live_listener.py:403`).
- Model-lab benchmark doc includes ASR model comparison with WER/RTF/latency tables (`/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md:43`).
- Fresh model-lab streaming benchmark runs (executed during this audit) show ~0.36-0.39 RTF and first-event chunk latency roughly 0.8-1.4s on the 10s sample (`/Users/pranay/Projects/speech_experiments/model-lab/runs/streaming_bench/streaming_asr_20260206T113202Z.json:20`, `/Users/pranay/Projects/speech_experiments/model-lab/runs/streaming_bench/streaming_asr_20260206T113214Z.json:20`, `/Users/pranay/Projects/speech_experiments/model-lab/runs/streaming_bench/streaming_asr_20260206T113227Z.json:20`).

## 3) Findings (prioritized)

### F-001
- Severity: P1
- Claim type: Observed
- Evidence:
  - UI allows `large-v3-turbo` (`macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift:348`).
  - Sanitizer allow-list omits `large-v3-turbo`, so selection falls back to `base` (`macapp/MeetingListenerApp/Sources/BackendManager.swift:292`).
- User impact: Users selecting “Large v3 Turbo (Best)” do not actually run that model, causing silent quality/performance mismatch.
- Recommendation: Add `large-v3-turbo` to allow-list or align UI options to exactly what sanitizer accepts.
- Verification steps:
  - `rg -n "large-v3-turbo|sanitizeWhisperModel|allowed" macapp/MeetingListenerApp/Sources -S`
  - Select `large-v3-turbo` in settings, restart server, verify `/health` model field.

### F-002
- Severity: P1
- Claim type: Observed
- Evidence:
  - EchoPanel tracks dropped frames only (`server/api/ws_live_listener.py:137`, `server/api/ws_live_listener.py:403`).
  - No emitted `avg_asr_latency`, no per-session ASR error-rate counters in server responses/events.
- User impact: Latency/error regressions cannot be measured from product telemetry, making model decisions hard to validate.
- Recommendation: Add per-session counters (ASR events, ASR failures, avg/p95 ASR latency, dropped frame rate) and emit on session end.
- Verification steps:
  - `rg -n "dropped_frames|latency|error rate|metrics" server/api/ws_live_listener.py server/services -S`
  - Run a session and inspect server log and emitted WS status/final events.

### F-003
- Severity: P1
- Claim type: Observed
- Evidence:
  - Diarization call path is commented out (`server/api/ws_live_listener.py:315`).
  - Roadmap/status docs present diarization as completed capability (`docs/STATUS_AND_ROADMAP.md:13`).
- User impact: Speaker-label expectations can diverge from actual behavior (empty diarization segments in final summary).
- Recommendation: Either re-enable diarization or explicitly mark it as disabled/experimental in product docs and UI.
- Verification steps:
  - `rg -n "diarization" server/api/ws_live_listener.py docs/STATUS_AND_ROADMAP.md -S`
  - Complete session and inspect `final_summary.json.diarization` payload.

### F-004
- Severity: P2
- Claim type: Observed
- Evidence:
  - Settings default app storage model is `base` (`macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift:329`).
  - Hardware guide claims “Medium” is default (`docs/HARDWARE_AND_PERFORMANCE.md:31`).
- User impact: Incorrect operator/user expectations on latency and quality.
- Recommendation: Align docs with runtime default or change runtime default deliberately and document rationale.
- Verification steps:
  - `rg -n "@AppStorage\(\"whisperModel\"\)|Default setting" macapp docs/HARDWARE_AND_PERFORMANCE.md -S`

### F-005
- Severity: P2
- Claim type: Observed
- Evidence:
  - Model-lab session manifests: 132 total, 83 FAILED, 38 COMPLETED, 9 RUNNING, 2 CANCELLED.
  - Top failure codes: `FileNotFoundError` (34), `RuntimeError` (21), `TypeError` (6).
  - Command outputs captured during audit.
- User impact: Benchmark baselines used for model decisions may include unstable or incomplete run sets.
- Recommendation: Publish a curated “blessed benchmark set” (fixed datasets + successful terminal runs only) before using aggregate error/latency numbers for default-model decisions.
- Verification steps:
  - `ls runs/sessions/*/*/manifest.json | wc -l`
  - `jq -r '.status // "UNKNOWN"' runs/sessions/*/*/manifest.json | sort | uniq -c`
  - `jq -r 'select(.status=="FAILED") | (.error_code // "UNKNOWN")' runs/sessions/*/*/manifest.json | sort | uniq -c | sort -nr`

### F-006
- Severity: P3
- Claim type: Observed
- Evidence:
  - `PERFORMANCE_RESULTS.md` summary lines conflict with table values (e.g., “Fastest: Whisper (13.1s)” while table shows 9.6s; “Fastest: LFM-2.5-Audio (92.7s)” while table shows 62.4s) (`/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md:45`, `/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md:50`, `/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md:60`, `/Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md:63`).
- User impact: Reduces trust in benchmark summaries used for model selection.
- Recommendation: Regenerate the markdown summary directly from run artifacts to avoid hand-edited drift.
- Verification steps:
  - `sed -n '39,66p' /Users/pranay/Projects/speech_experiments/model-lab/PERFORMANCE_RESULTS.md`

## 4) Backlog conversion
- P0/P1 findings that should become tickets:
  - `Fix model selection mismatch: allow large-v3-turbo end-to-end`
    - Acceptance criteria:
      - Selecting `large-v3-turbo` in settings survives sanitization.
      - `/health` returns `model: large-v3-turbo` after restart.
      - Add regression test for sanitizer allow-list.
  - `Add server-side ASR latency/error telemetry`
    - Acceptance criteria:
      - Session-end log/event includes ASR event count, error count, avg/p95 latency, dropped frame count/rate.
      - Metrics documented in `docs/OBSERVABILITY.md`.
  - `Clarify diarization status (enabled vs disabled)`
    - Acceptance criteria:
      - Either diarization code path is enabled and tested, or docs/UI explicitly label it disabled/experimental.
      - Final summary payload semantics documented for both states.
- P2/P3 suggested tickets:
  - `Align model default documentation with runtime behavior`.
  - `Create model-lab blessed benchmark manifest and auto-generated report`.

## Evidence log (commands run)
- `git -C /Users/pranay/Projects/EchoPanel status --porcelain`
- `git -C /Users/pranay/Projects/EchoPanel rev-parse --abbrev-ref HEAD`
- `git -C /Users/pranay/Projects/EchoPanel rev-parse HEAD`
- `uv run python scripts/bench_streaming_asr.py --input data/audio/conversation_2ppl_10s.wav --chunk-seconds 4` (model-lab)
- `uv run python scripts/bench_streaming_asr.py --input data/audio/conversation_2ppl_10s.wav --chunk-seconds 2` (model-lab)
- `MODEL_LAB_WHISPER_MODEL=base uv run python scripts/bench_streaming_asr.py --input data/audio/conversation_2ppl_10s.wav --chunk-seconds 4` (model-lab)
- `jq -r '.status // "UNKNOWN"' runs/sessions/*/*/manifest.json | sort | uniq -c` (model-lab)
- `jq -r 'select(.status=="FAILED") | (.error_code // "UNKNOWN")' runs/sessions/*/*/manifest.json | sort | uniq -c | sort -nr` (model-lab)
