# Repo Operating Manual

**Last Updated:** 2026-02-14

This manual summarizes repo-specific operating rules and workflows, derived from governance sources listed in `docs/GOVERNANCE_INDEX.md`.

## Source of Truth
- **Tickets & execution log:** `docs/WORKLOG_TICKETS.md`
- **Prompt library:** `prompts/README.md`
- **Decisions:** `docs/DECISIONS.md`

## Repository Structure
- `macapp/` — macOS menu bar app (Swift)
- `server/` — FastAPI backend and services (Python)
- `landing/` — static landing page
- `docs/` — documentation, audits, decisions
- `prompts/` — repo-native prompts/workflows
- `scripts/` — build, dev, and verification scripts
- `tests/` — Python tests

## Environment & Setup
- **OS:** macOS (required for app build)
- **Python:** 3.11+ (per `pyproject.toml`)
- **Package manager:** `uv` recommended (see `README.md`)

### Python Setup (recommended)
```bash
uv venv .venv
source .venv/bin/activate
uv pip install -e ".[dev]"
```

## Build & Run
- **Dev app bundle (stable permissions):** `scripts/run-dev-app.sh`
- **Manual backend:** `python -m uvicorn server.main:app --host 127.0.0.1 --port 8000 --log-level debug`
- **Release bundle:** `python scripts/build_app_bundle.py --release`

See `docs/BUILD.md` for full build details.

## Testing & Verification
- **Swift:** `cd macapp/MeetingListenerApp && swift build && swift test`
- **Python:** `.venv/bin/pytest -q tests/`
- **Manual QA:** `docs/QA_CHECKLIST.md`
- **Detailed testing guidance:** `docs/TESTING.md`

## Quality Gates (Executable Truth)
- `scripts/verify.sh` runs `swift build` + `swift test`.
- Pre-commit hook runs `scripts/verify.sh`.

### Install Git Hooks
```bash
./scripts/install-git-hooks.sh
```

## Definition of Done (v0.1)
From `docs/PROJECT_MANAGEMENT.md`:
- Meets acceptance checklist in `docs/TESTING.md`.
- No silent capture behavior.
- Clear user-facing status in error and reconnect states.

## Commit Conventions
- No repo-wide convention documented. For PM loop work, prefer:
  - `DOC-00X: <short verb phrase>`

## Release & Distribution Notes
- Code signing and notarization are currently blocked (Apple Developer Program required).
- For dev permissions stability, use the app bundle installed at:
  - `~/Applications/MeetingListenerApp-Dev.app`

## Governance References
- `docs/GOVERNANCE_INDEX.md` (full source list and precedence)
