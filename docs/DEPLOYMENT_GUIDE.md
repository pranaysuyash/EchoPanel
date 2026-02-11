# EchoPanel Deployment Guide

**Version**: v0.3 (Safety + Performance Release)  
**Date**: 2026-02-11

---

## Quick Start

### 1. Install Dependencies

```bash
# Python backend
cd /Users/pranay/Projects/EchoPanel
python -m venv .venv
source .venv/bin/activate
pip install -e ".[asr,diarization]"

# Optional: whisper.cpp for Apple Silicon
pip install pywhispercpp
```

### 2. Download Models (if using whisper.cpp)

```bash
# Create models directory
mkdir -p models

# Download GGML models (choose based on your RAM)
cd models

# Tiny (75MB, ~15% WER) - for 4GB RAM
curl -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# Base (142MB, ~11% WER) - for 8GB RAM
curl -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# Small (466MB, ~8% WER) - for 16GB RAM
curl -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

### 3. Start Server

```bash
# Auto-detects optimal provider and preloads model
cd /Users/pranay/Projects/EchoPanel
source .venv/bin/activate
python -m server.main

# Or with uvicorn directly
uvicorn server.main:app --host 0.0.0.0 --port 8000
```

### 4. Verify Health

```bash
# Wait for "Model ready!" in logs, then:
curl http://localhost:8000/health

# Expected response:
{
  "status": "ok",
  "service": "echopanel",
  "provider": "whisper_cpp",
  "model": "base",
  "model_ready": true,
  "model_state": "READY",
  "load_time_ms": 2450.5,
  "warmup_time_ms": 523.2
}
```

### 5. Build macOS App

```bash
cd macapp/MeetingListenerApp
swift build
# Or open in Xcode and build
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ECHOPANEL_ASR_PROVIDER` | Auto-detect | `whisper_cpp` or `faster_whisper` |
| `ECHOPANEL_WHISPER_MODEL` | Auto-detect | Model name (base, small, etc.) |
| `ECHOPANEL_MODEL_PATH` | `./models` | Path to GGML models |
| `ECHOPANEL_ASR_CHUNK_SECONDS` | 2 | Audio chunk size |
| `ECHOPANEL_ASR_VAD` | 1 | Voice activity detection |
| `ECHOPANEL_MAX_SESSIONS` | 10 | Concurrent session limit |
| `ECHOPANEL_WS_AUTH_TOKEN` | None | WebSocket auth token |

### Provider Selection

**Automatic (Recommended)**:
```bash
# No env vars set - auto-detects based on hardware
python -m server.main
# Logs: "Auto-selected: whisper_cpp/base (Apple Silicon with sufficient RAM)"
```

**Manual Override**:
```bash
# Force faster-whisper
export ECHOPANEL_ASR_PROVIDER=faster_whisper
export ECHOPANEL_WHISPER_MODEL=base.en
python -m server.main
```

**whisper.cpp on Apple Silicon**:
```bash
export ECHOPANEL_ASR_PROVIDER=whisper_cpp
export ECHOPANEL_WHISPER_MODEL=base
export ECHOPANEL_WHISPER_DEVICE=metal
python -m server.main
```

---

## Monitoring

### Health Endpoints

```bash
# Basic health
curl http://localhost:8000/health

# Capabilities (hardware + recommendations)
curl http://localhost:8000/capabilities

# Model status (preloader stats)
curl http://localhost:8000/model-status
```

### Logs

Watch for these key events:

```
# Startup
INFO: Auto-selected: whisper_cpp/base (Apple Silicon with sufficient RAM)
INFO: Phase 1/3: Loading model...
INFO: Model loaded in 2450.5ms
INFO: Phase 2/3: Warming up...
INFO: Warmup complete in 523.2ms
INFO: Model ready! Total time: 2973.7ms

# Session
INFO: Session started: session_id=..., provider=whisper_cpp, model=base

# Degrade ladder (if overloaded)
WARNING: DEGRADE: WARNING -> DEGRADE: Switch to smaller model
INFO: RECOVER: DEGRADE -> WARNING

# Concurrency
WARNING: Server at capacity, please try again later
```

### Metrics

WebSocket clients receive 1Hz metrics:
```json
{
  "type": "metrics",
  "realtime_factor": 1.85,
  "queue_fill_ratio": 0.35,
  "degrade_level": "NORMAL",
  "dropped_total": 0,
  "provider": "whisper_cpp"
}
```

---

## Troubleshooting

### Model Not Loading

**Symptom**: Health returns 503, "Model LOADING"

**Solutions**:
1. Wait longer (large models take 10-30s)
2. Check model path: `ECHOPANEL_MODEL_PATH=/correct/path`
3. Check logs for download errors
4. Try smaller model: `ECHOPANEL_WHISPER_MODEL=tiny`

### whisper.cpp Not Available

**Symptom**: Falls back to faster-whisper

**Solutions**:
```bash
# Install pywhispercpp
pip install pywhispercpp

# Verify installation
python -c "from pywhispercpp.model import Model; print('OK')"

# Download models
curl -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

### High CPU Usage

**Symptom**: System slow, RTF < 1.0

**Solutions**:
1. Check degrade ladder status: `degrade_level` in metrics
2. Reduce concurrent sessions: `ECHOPANEL_MAX_SESSIONS=5`
3. Use smaller model: `ECHOPANEL_WHISPER_MODEL=base`
4. Disable VAD: `ECHOPANEL_ASR_VAD=0`

### WebSocket Reconnects

**Symptom**: Client keeps reconnecting

**Check**:
```bash
# Server health
curl http://localhost:8000/health

# Check circuit breaker in client logs
# Verify max reconnect attempts not exceeded
```

---

## Performance Tuning

### For 8GB RAM (MacBook Air)

```bash
export ECHOPANEL_ASR_PROVIDER=whisper_cpp
export ECHOPANEL_WHISPER_MODEL=base
export ECHOPANEL_ASR_CHUNK_SECONDS=2
export ECHOPANEL_MAX_SESSIONS=5
```

**Expected**: RTF ~2.0x, 300MB RAM

### For 16GB RAM (MacBook Pro)

```bash
export ECHOPANEL_ASR_PROVIDER=whisper_cpp
export ECHOPANEL_WHISPER_MODEL=small
export ECHOPANEL_ASR_CHUNK_SECONDS=2
export ECHOPANEL_MAX_SESSIONS=10
```

**Expected**: RTF ~1.5x, 466MB RAM

### For 32GB+ RAM (Mac Studio)

```bash
export ECHOPANEL_ASR_PROVIDER=whisper_cpp
export ECHOPANEL_WHISPER_MODEL=medium
export ECHOPANEL_ASR_CHUNK_SECONDS=2
export ECHOPANEL_MAX_SESSIONS=20
```

**Expected**: RTF ~1.2x, 1.5GB RAM

---

## Testing

### Run All Tests

```bash
cd /Users/pranay/Projects/EchoPanel
source .venv/bin/activate

# Python tests
pytest tests/ -v

# Swift tests
cd macapp/MeetingListenerApp
swift test
```

### Load Testing

```bash
# Start server
python -m server.main &

# Run multiple concurrent sessions
for i in {1..10}; do
  python scripts/stream_test.py &
done

# Monitor metrics in logs
```

---

## Production Checklist

- [ ] Models downloaded and verified
- [ ] Health endpoint returns 200
- [ ] `/capabilities` shows correct hardware detection
- [ ] WebSocket connections stable
- [ ] Metrics showing RTF > 1.0
- [ ] Client reconnection handling tested
- [ ] Log rotation configured
- [ ] Monitoring alerts set up

---

## Support

**Documentation**:
- `docs/IMPLEMENTATION_COMPLETE_SUMMARY.md` - Feature overview
- `docs/IMPLEMENTATION_TICKETS_ROADMAP.md` - Ticket tracking
- `docs/RESEARCH_SYNTHESIS_PR4-PR6_AND_ASR.md` - Technical research

**Logs**: Check server logs for detailed error messages

**Health**: Use `/health`, `/capabilities`, `/model-status` endpoints
