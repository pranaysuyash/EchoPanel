#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ONLINE_CHECK_URL="https://example.com"
HEALTH_URL="http://127.0.0.1:8000/health"
MODEL_STATUS_URL="http://127.0.0.1:8000/model-status"

print_header() {
  echo "[offline-verify] $1"
}

print_header "Checking that internet access is disabled..."
if curl -m 3 -fsSL "$ONLINE_CHECK_URL" >/dev/null 2>&1; then
  echo "[offline-verify] Online access detected. Disable Wi-Fi/network and re-run."
  echo "[offline-verify] Tip: System Settings → Network → Wi-Fi → Off"
  exit 2
fi

print_header "Confirming local backend health..."
if ! curl -m 3 -fsSL "$HEALTH_URL" >/dev/null 2>&1; then
  echo "[offline-verify] Backend not reachable at $HEALTH_URL"
  echo "[offline-verify] Start the app (recommended) or run:"
  echo "  python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --log-level debug"
  exit 3
fi

echo "[offline-verify] /health reachable."

print_header "Checking model status..."
if ! curl -m 3 -fsSL "$MODEL_STATUS_URL" >/dev/null 2>&1; then
  echo "[offline-verify] Model status not reachable at $MODEL_STATUS_URL"
  exit 4
fi

echo "[offline-verify] /model-status reachable."
print_header "Offline graceful behavior verification passed."
