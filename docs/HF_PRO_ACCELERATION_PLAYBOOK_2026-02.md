# HF Pro Acceleration Playbook (Before 2026-03-01)

## Goal
Use Hugging Face Pro while active to front-load model downloads and quickly evaluate staged model candidates for INT-008/INT-009.

## Inputs
- `ECHOPANEL_HF_TOKEN` set in shell environment
- Project venv: `.venv`
- Pinned model manifest: `server/config/hf_model_manifest.json`

## Commands
1. Prefetch all pinned models:
```bash
.venv/bin/python scripts/prefetch_hf_models.py
```

2. Prefetch only diarization model:
```bash
.venv/bin/python scripts/prefetch_hf_models.py --group diarization
```

3. Hosted latency probe for staged INT candidates:
```bash
.venv/bin/python scripts/eval_hf_models.py --group int-008 --group int-009 --requests 3
```

## Outputs
- Prefetch receipt: `docs/audit/artifacts/hf-prefetch-receipt-*.json`
- Eval receipt: `docs/audit/artifacts/hf-eval-receipt-*.json`

## Notes
- Gated models (for example `pyannote/speaker-diarization-3.1`) require token + accepted model terms.
- Hosted eval requests (`scripts/eval_hf_models.py`) require token auth in this environment.
- Server now starts a background diarization prewarm task by default (`ECHOPANEL_PREWARM_DIARIZATION=1`).
- To disable Apple-Silicon whisper.cpp preference in auto-selection:
  - `ECHOPANEL_PREFER_WHISPER_CPP=0`
