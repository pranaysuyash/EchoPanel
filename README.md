# EchoPanel

EchoPanel is a macOS menu-bar app for capturing **System Audio**, **Microphone**, or **Both**, streaming PCM to a local backend, and generating live transcript + cards + entities.

## Setup

### Prerequisites

- macOS
- Python 3.11+
- [uv](https://github.com/astral-sh/uv) package manager (much faster than pip)

### Environment Setup

```bash
# Create virtual environment
uv venv .venv

# Activate environment
source .venv/bin/activate

# Install dependencies (base + dev)
uv pip install -e ".[dev]"

# Optional: Add ASR support
uv pip install -e ".[asr]"

# Optional: Add diarization support
uv pip install -e ".[diarization]"
```

**Note**: We use `uv` for fast, reliable package management. If you prefer pip, use `pip install -e ".[dev]"` etc., but uv is recommended.

## Dev runbook (macOS) — copy/paste friendly

### Terminal 0 — hard reset (quit app + free port 8000)

```bash
cd /Users/pranay/Projects/EchoPanel

# Quit any running instances (binary or .app)
pkill -f MeetingListenerApp || true

# Free the backend port (avoid “ghost server ready” states)
lsof -nP -iTCP:8000 -sTCP:LISTEN || true
# If something is listening, kill it (replace <PID>)
# kill <PID>

# Re-check port is free
lsof -nP -iTCP:8000 -sTCP:LISTEN || true
```

### Terminal 1 — build + launch a stable Dev .app bundle (recommended for permissions)

```bash
cd /Users/pranay/Projects/EchoPanel
./scripts/run-dev-app.sh
```

Why this matters: macOS ties Screen Recording permission to the app identity. Running `swift run MeetingListenerApp` creates a different identity than the `.app` bundle, so permissions can appear to “reset”.

### One-time macOS permissions

1. System Settings → Privacy & Security → **Screen Recording** → enable **MeetingListenerApp Dev**
2. System Settings → Privacy & Security → **Microphone** → enable **MeetingListenerApp Dev**
3. Quit the app fully (Cmd+Q) and re-run Terminal 1

### Option A (recommended): app-managed backend

The app starts and manages the backend automatically and writes logs to a temp file.

#### Terminal 2 — tail backend log (spawned by the app)

```bash
tail -f /var/folders/fc/xwynjqm94t39_jvz88fhcpfc0000gn/T/echopanel_server.log
```

#### Terminal 3 — stream macOS app logs (only useful signals)

```bash
log stream --style compact --predicate '(process == "MeetingListenerApp") && (eventMessage CONTAINS "onPCMFrame" OR eventMessage CONTAINS "AudioCaptureManager" OR eventMessage CONTAINS "MicrophoneCaptureManager" OR eventMessage CONTAINS "WebSocketStreamer" OR eventMessage CONTAINS "BackendManager" OR eventMessage CONTAINS "SidePanelController")'
```

#### Terminal 4 — backend health check

```bash
curl -i http://127.0.0.1:8000/health
```

Expected:

- HTTP 200 when ASR is ready
- HTTP 503 while ASR is not available / warming up

### Option B: manual backend (only when you want full control)

Important: only one process can bind `127.0.0.1:8000`.

#### Terminal 1B — start backend with venv

```bash
cd /Users/pranay/Projects/EchoPanel
source .venv/bin/activate
python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --log-level debug
```

#### Terminal 2B — launch app (don’t let the app also start a server)

```bash
cd /Users/pranay/Projects/EchoPanel
./scripts/run-dev-app.sh
```

If the app says “Port 8000 is already in use”, that’s expected when you’re running the backend manually; just ensure `curl /health` succeeds.

## Documentation

**Comprehensive documentation (50+ files, 45,000+ lines):**

| Quick Links | |
|-------------|---|
| 📖 **Getting Started** | [docs/LIVE_LISTENER_SPEC.md](./docs/LIVE_LISTENER_SPEC.md) |
| 🔧 **Troubleshooting** | [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) |
| 📊 **All Docs** | [docs/README.md](./docs/README.md) |
| 🔍 **Audits** | [docs/audit/README.md](./docs/audit/README.md) (30+ technical audits) |
| 📋 **Work Status** | [docs/WORKLOG_TICKETS.md](./docs/WORKLOG_TICKETS.md) |

**Latest Audits:**
- [Phase 0A: System Contracts](./docs/audit/PHASE_0A_SYSTEM_CONTRACTS_AUDIT.md) - State machines, protocol truth
- [Streaming Reliability](./docs/audit/streaming-reliability-dual-pipeline-20260210.md) - End-to-end streaming analysis
- [UI/UX Audit](./docs/UI_UX_AUDIT_2026-02-10.md) - Interface design review

See [docs/DOCUMENTATION_STATUS.md](./docs/DOCUMENTATION_STATUS.md) for complete index.

## Local quality gate

```bash
./scripts/install-git-hooks.sh
```

This enables a pre-commit hook that runs `./scripts/verify.sh` (`swift build` + `swift test`, including SidePanel visual snapshot tests).
