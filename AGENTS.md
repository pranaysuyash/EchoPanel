# EchoPanel — Agent Coordination Guide

<!-- PROJECTS_MEMORY_AGENT_ALIGNMENT_BEGIN -->

## Projects-Level Agent Alignment (Workspace Memory)

**Purpose:** ensure any agent/LLM (Codex, Copilot, Claude Code, Qwen, GLM, etc.) starts aligned with the same workspace memory + project context.

### Step 0 (first time in this folder)
Generate the per-project context pack:
```bash
/Users/pranay/Projects/agent-start
```

### Step 1 (per shell)
Load the shared defaults for this project session:
```bash
source .agent/STEP1_ENV.sh
# Or (no file read) print exports and eval:
/Users/pranay/Projects/agent-start --print-step1 --skip-index
```

### Step 2 (generate aligned context pack)
```bash
/Users/pranay/Projects/agent-start
```

Outputs:
- `.agent/SESSION_CONTEXT.md`
- `.agent/AGENT_KICKOFF_PROMPT.txt`
- `.agent/STEP1_ENV.sh`

### How agents should use this
- Provide `.agent/AGENT_KICKOFF_PROMPT.txt` and `.agent/SESSION_CONTEXT.md` as the first context for the agent.
- If sources conflict, the agent must cite concrete file paths and ask before proceeding.

<!-- PROJECTS_MEMORY_AGENT_ALIGNMENT_END -->

**🆕 NEW AGENTS:** Start with **[AGENT_START_HERE.md](./AGENT_START_HERE.md)** for current project status.

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

## Staging policy
- Default to staging all useful, non-breaking project changes with `git add -A`.
- Only skip full staging when the user explicitly asks not to.

## Audit documentation requirements

When conducting an audit (type: `AUDIT`), you MUST:

1. **Create a ticket** in `docs/WORKLOG_TICKETS.md` following the template
2. **Create/update an audit document** in `docs/audit/` with naming convention:
   - `docs/audit/<surface>-<area>-<YYYYMMDD>.md` for scoped audits
   - `docs/audit/<theme>-<YYYYMMDD>.md` for cross-cutting audits
3. **Include all required sections**:
   - Files inspected (with paths)
   - Executive summary (5-10 bullets)
   - Failure modes table (minimum 10 entries)
   - Root causes (ranked by impact)
   - Concrete fixes (ranked by impact/effort/risk)
   - Test plan (unit + integration + manual)
   - Instrumentation plan (metrics, logs)
   - State machine diagrams (text form acceptable)
   - Queue/backpressure analysis
   - Evidence citations (file path + line range)

4. **Answer all key questions** specified in the audit prompt
5. **Run all required personas** and include their findings
6. **Update the ticket** with evidence log and mark DONE when complete

Audits are documentation-only but MUST be comprehensive and cite specific code locations. Do not fabricate performance numbers—label assumptions clearly.
