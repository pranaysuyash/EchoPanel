# Server Stub (local)

This is a minimal FastAPI WebSocket server that implements the v0.1 contract in `docs/WS_CONTRACT.md`.

## Setup
```sh
uv venv .venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

### Optional: local ASR with faster-whisper
```sh
uv pip install -e ".[asr]"
export ECHOPANEL_WHISPER_MODEL=base
export ECHOPANEL_WHISPER_DEVICE=metal
export ECHOPANEL_WHISPER_COMPUTE=int8_float16
```

## Run
```sh
python -m server.main
```

Default URL: `ws://127.0.0.1:8000/ws/live-listener`

## Simulated client
```sh
python -m server.tools.sim_client --url ws://127.0.0.1:8000/ws/live-listener
```
