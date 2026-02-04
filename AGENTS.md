# EchoPanel — Agent Coordination Guide

This repo contains a macOS menu bar app (`macapp/`), a local FastAPI backend (`server/`), and a static landing page (`landing/`).

## Principles

### Evidence-first
- **Observed**: verified by running code/reading files
- **Inferred**: reasonable conclusion, not directly verified
- **Unknown**: cannot determine from available evidence

Never present `Inferred` as `Observed`.

### Single source of truth
- **Worklog / tickets**: `docs/WORKLOG_TICKETS.md`
- **Prompt library**: `prompts/`
- **Audits**: `docs/audit/`
- **Decisions**: `docs/DECISIONS.md`
- **Specs / contracts**: `docs/` (notably `docs/WS_CONTRACT.md`)

### Scope discipline
- One work unit should have one “scope contract” and clear acceptance criteria.
- Prefer small, reviewable patches that keep behavior stable unless explicitly changing UX.

## Workflow (required)

### 1) Intake
1. Identify the work type: `AUDIT`, `BUG`, `FEATURE`, `IMPROVEMENT`, `HARDENING`, `DOCS`.
2. Create or update a ticket in `docs/WORKLOG_TICKETS.md`.
3. Choose the right prompt from `prompts/README.md` and follow it.

### 2) Execution
- Keep edits focused on the ticket scope.
- Add/adjust docs when behavior or UX changes.
- Validate with the most specific checks available (`swift build`, `pytest`, etc.).

### 3) Closeout
- Update ticket status and add an “evidence log” (commands run + outcomes).
- If you created/updated prompts, update `prompts/README.md`.

## Ticket status
- **OPEN** 🔵
- **IN_PROGRESS** 🟡
- **BLOCKED** 🔴
- **DONE** ✅

## No destructive cleanup by default
Do not delete files or remove “unused” code unless explicitly requested or clearly required by the scoped ticket.

