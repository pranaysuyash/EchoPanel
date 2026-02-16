# Governance Index

**Last Updated:** 2026-02-14

This index lists governance sources (docs, scripts, configs, prompts) and how to comply. Precedence rules appear below.

## Precedence Rules
1. **Most specific scope wins** (subdir rules override repo-wide rules).
2. **Executable truth wins** for gates (verify/test scripts) unless explicitly deprecated.
3. **Newer wins** if timestamps are available.
4. If still ambiguous, choose the **stricter** rule and document the decision.

## Governance Sources

### Repo-wide Sources

- **`AGENTS.md`**
  - **Type:** Doc guideline (repo governance)
  - **Enforces:** Evidence-first discipline; single source of truth for worklog/tickets; scope discipline; staging policy; audit requirements.
  - **How to comply:** Follow intake/execution/closeout; update `docs/WORKLOG_TICKETS.md` for tickets; avoid destructive cleanup.
  - **Scope:** Whole repo
  - **Precedence:** High

- **`AGENT_START_HERE.md`**
  - **Type:** Doc guideline (entrypoint)
  - **Enforces:** Current status, open/blocked items, critical traps, build commands, standard app location.
  - **How to comply:** Read first; avoid duplicating open tickets; use standard dev app path for permissions.
  - **Scope:** Whole repo
  - **Precedence:** High

- **`docs/PROJECT_MANAGEMENT.md`**
  - **Type:** Doc guideline (PM workflow)
  - **Enforces:** Use `docs/WORKLOG_TICKETS.md` as source of truth; use prompt library; PR guidelines; Definition of Done.
  - **How to comply:** Track work in `docs/WORKLOG_TICKETS.md`; include goal, acceptance criteria, verification commands in each unit of work.
  - **Scope:** Whole repo
  - **Precedence:** High

- **`prompts/README.md`**
  - **Type:** Embedded prompt library
  - **Enforces:** Evidence-first labels; scope discipline; append-only tracking in worklog.
  - **How to comply:** Use prompts for audits/remediation; keep evidence labels and references.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`docs/TESTING.md`**
  - **Type:** Doc guideline (testing/verification)
  - **Enforces:** Manual acceptance checklist; recommended dev scripts; snapshot testing process; pre-commit verify behavior.
  - **How to comply:** Use listed commands for verification; respect snapshot workflow and pre-commit gate.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`docs/BUILD.md`**
  - **Type:** Doc guideline (build/run)
  - **Enforces:** Build steps, tooling prerequisites, and distribution artifact locations.
  - **How to comply:** Follow build commands and prerequisites when packaging.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`README.md`**
  - **Type:** Doc guideline (dev runbook)
  - **Enforces:** uv-based Python setup, dev runbook, backend management, log streaming.
  - **How to comply:** Prefer uv; follow runbook steps; use app-managed backend unless manual control needed.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`docs/WORKLOG_TICKETS.md`**
  - **Type:** Doc guideline (worklog + tickets)
  - **Enforces:** Single source of truth for tickets; evidence log for work.
  - **How to comply:** Create/update tickets here for each unit of work; append evidence logs.
  - **Scope:** Whole repo
  - **Precedence:** High

- **`docs/DECISIONS.md`**
  - **Type:** Decision log
  - **Enforces:** Documented product/architecture decisions; constraints for future work.
  - **How to comply:** Align work with decisions unless explicitly superseded.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`docs/QA_CHECKLIST.md`**
  - **Type:** Doc guideline (QA)
  - **Enforces:** Basic QA checklist for core flows, permissions, streaming, UI, exports.
  - **How to comply:** Use as manual verification reference.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`pyproject.toml`**
  - **Type:** Config (Python toolchain)
  - **Enforces:** pytest settings, dependency groups, optional extras.
  - **How to comply:** Use `pytest` with configured settings; respect Python version requirement (>=3.11).
  - **Scope:** Python backend/tests
  - **Precedence:** Medium

### Executable Gates / Scripts

- **`scripts/verify.sh`**
  - **Type:** Script gate (build/test)
  - **Enforces:** `swift build` + `swift test` for macapp.
  - **How to comply:** Run script or ensure pre-commit hook is installed.
  - **Scope:** macapp
  - **Precedence:** High (executable truth)

- **`.githooks/pre-commit`**
  - **Type:** Script gate (git hook)
  - **Enforces:** Runs `scripts/verify.sh` before commit.
  - **How to comply:** Install hooks via `scripts/install-git-hooks.sh`.
  - **Scope:** Whole repo
  - **Precedence:** High

- **`scripts/install-git-hooks.sh`**
  - **Type:** Script installer
  - **Enforces:** Sets git hooks path to `.githooks`.
  - **How to comply:** Run once per clone.
  - **Scope:** Whole repo
  - **Precedence:** Medium

- **`scripts/build-dev-app.sh` / `scripts/run-dev-app.sh`**
  - **Type:** Script runbook
  - **Enforces:** Standard dev app bundle build location and signing for permission stability.
  - **How to comply:** Use these scripts when testing Screen Recording permission flows.
  - **Scope:** macapp
  - **Precedence:** Medium

## Notes
- Where guidance overlaps, prefer the stricter or more specific rule. Any deviations should be documented in `docs/WORKLOG_TICKETS.md`.
