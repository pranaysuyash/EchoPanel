> **⚠️ OBSOLETE (2026-02-15):** All findings in this audit have been addressed. Moved to archive.
> See implementation references below. Original audit preserved for historical context.
>
> **Implementation refs:** Server default config uses `base.en` as recommended. HF token propagation implemented in `server/main.py` (`_sync_huggingface_token_env()`). Server health: READY with model=base.en, provider=faster_whisper.

# ASR Streaming Model Matrix (Local) — 2026-02-13

Goal: pick a default end-user meeting configuration that does not drop system audio under realtime streaming on this machine.

Audio used:
- `/Users/pranay/Projects/EchoPanel/llm_recording_pranay.wav`
- Streaming window: 30s
- Send cadence: 40ms frames (`chunk-seconds=0.04`) at realtime pace
- ASR chunking (server-side): `ECHOPANEL_ASR_CHUNK_SECONDS=2`
- Provider: `faster_whisper` (CPU, int8) for all runs

Results directory:
- `output/asr_matrix/20260213-224744/results.json`

## Matrix Summary (Observed)

### Model: `base.en`
- Health warmup: ~658ms, RSS ~460MB
- Metrics (30 samples):
  - avg realtime_factor: ~0.73 (good, <1)
  - max queue_fill_ratio: 0.50
  - dropped_recent: 0
- ASR finals received: 15
- Statuses included: `buffering` once ("Reduced quality for stability") but **no backpressure/drops**

### Model: `small.en`
- Health warmup: ~737ms, RSS ~930MB
- Metrics (30 samples):
  - avg realtime_factor: ~1.29 (bad, >1)
  - max queue_fill_ratio: 1.0
  - max dropped_recent: 22
- ASR finals received: 10
- Statuses: repeated `backpressure` + `overloaded` indicating real-time cannot be maintained.

### Model: `large-v3-turbo`
- Server did not become ready within the matrix harness readiness window (health returned 503).
- This is likely due to model availability/download/load time in the current environment.

## Recommendation (Default End-User Meeting Config)

Use `faster_whisper` with `base.en` for live meetings on this machine:

```bash
export ECHOPANEL_ASR_PROVIDER=faster_whisper
export ECHOPANEL_WHISPER_MODEL=base.en
export ECHOPANEL_WHISPER_DEVICE=cpu
export ECHOPANEL_WHISPER_COMPUTE=int8
export ECHOPANEL_ASR_CHUNK_SECONDS=2
export ECHOPANEL_ASR_VAD=1
export ECHOPANEL_WHISPER_LANGUAGE=en
```

Rationale: `base.en` maintained realtime (RTF < 1) and did not trigger backpressure drops for system audio under the end-user aligned streaming test. `small.en` did not.

## HF Pro / Token Note

To make model downloads faster and avoid unauthenticated rate limits, set:

```bash
export ECHOPANEL_HF_TOKEN=hf_...
```

Server startup now propagates this into Hugging Face standard env vars (`HF_TOKEN`, `HUGGINGFACE_HUB_TOKEN`), so faster-whisper downloads benefit automatically.

## Reproduce

Run the matrix script:

```bash
PYTHONPATH=. .venv/bin/python scripts/run_streaming_model_matrix.py \
  --audio /Users/pranay/Projects/EchoPanel/llm_recording_pranay.wav \
  --models base.en small.en large-v3-turbo \
  --seconds 30 \
  --chunk-seconds 0.04 \
  --asr-chunk-seconds 2 \
  --vad 1 \
  --out-dir output/asr_matrix
```

