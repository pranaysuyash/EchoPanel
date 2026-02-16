# PM Playbook (Reusable)

**Last Updated:** 2026-02-14

This playbook captures the reusable workflow used in this repo. If repo governance is missing, this serves as the default "Local PM Framework v1".

## 1) Governance Discovery Framework
- Scan docs and codebase artifacts:
  - Docs: `README.md`, `docs/README.md`, `docs/PROJECT_MANAGEMENT.md`, `docs/TESTING.md`, `docs/WORKLOG_TICKETS.md`, ADRs, audits.
  - Scripts/configs: `scripts/verify.sh`, `.githooks/pre-commit`, `pyproject.toml`.
  - Prompts/runbooks: `prompts/README.md`, `docs/*RUNBOOK*.md`, `docs/*PLAYBOOK*.md`.
- Build/update `docs/GOVERNANCE_INDEX.md` and summarize precedence.

## 2) Docs/Artifacts → Backlog Loop
- Extract issues/features/improvements from docs and workflow artifacts.
- Record in `docs/DOC_BACKLOG.md` with evidence snippets and status.
- Avoid duplicating existing tickets; reference them instead.

## 3) Single-Item Delivery Unit (“Local PR”)
- One focused change set.
- Local verification evidence.
- Documentation updated to prevent drift.
- One commit per item (default).

## 4) Decision Record Format (Claim vs. Truth)
- **Claim:** What docs/prompts state.
- **Truth:** What code/tests show.
- **Conclusion:** Gap or doc drift (A/B/C).
- **Falsifier:** What evidence would prove this wrong.

## 5) Acceptance Criteria Patterns
- Observable, testable, minimal.
- Include failure modes and rollback plan.

## 6) Testing Strategy Ladder
1. Existing tests (fastest)
2. Minimal new test
3. Verifier script in `scripts/`
4. Manual checklist (documented)

## 7) Change Control
- Keep scope tight to the selected item.
- Log follow-ups as new backlog entries.
- Avoid destructive cleanup unless required.

## 8) Quality Gates
- Pre-commit: `scripts/verify.sh` (`swift build` + `swift test`).
- Follow repo-specific test/runbook steps in `docs/TESTING.md`.

## 9) Documentation Update Standard
- Update source docs to prevent drift.
- Add evidence logs to `docs/WORKLOG_TICKETS.md`.
- Record backlogs in `docs/DOC_BACKLOG.md`.

## 10) Backlog Status Taxonomy
`new` / `needs-verify` / `in-progress` / `blocked` / `done` / `doc-stale` / `won’t-do`

## 11) Commit Protocol
- Stage all changes: `git add -A`
- Commit message format: `DOC-00X: <short verb phrase>`
- One commit per item (default)
