#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Missing venv at $VENV_DIR"
  echo "Run: uv venv .venv && source .venv/bin/activate && uv pip install -e \".[dev]\""
  exit 1
fi

source "$VENV_DIR/bin/activate"
python -m server.main
