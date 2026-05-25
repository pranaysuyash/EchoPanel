# EchoPanel — Agent Coordination Guide

<!-- PROJECTS_MEMORY_AGENT_ALIGNMENT_BEGIN -->

## Projects-Level Agent Alignment (Workspace Memory)

**Purpose:** ensure any agent/LLM (Codex, Copilot, Claude Code, Qwen, GLM, etc.) starts aligned with the same workspace memory + project context.

## Instruction Stack

### Startup Order

When starting work in this repo, read sources in this order:

1. `/Users/pranay/AGENTS.md`
2. `/Users/pranay/Projects/AGENTS.md`
3. Repo-local `AGENTS.md` (this file)
4. Project-local context pack from `/Users/pranay/Projects/agent-start`

### Conflict Precedence

If instructions conflict, the most specific applicable source wins:

1. Repo-local `AGENTS.md`
2. `/Users/pranay/Projects/AGENTS.md`
3. `/Users/pranay/AGENTS.md`

Always cite concrete file paths when surfacing a conflict.

### Step 0 (first time in this folder)

Generate the per-project context pack:

```bash
/Users/pranay/Projects/agent-start
```

### Step 1 (per shell)

Load the shared defaults for this project session:

```bash
source Docs/context/agent-start/STEP1_ENV.sh
# Or (no file read) print exports and eval:
/Users/pranay/Projects/agent-start --print-step1 --skip-index
```

### Step 2 (generate aligned context pack)

```bash
/Users/pranay/Projects/agent-start
```

Outputs:

- Canonical project-local pack:
  - `Docs/context/agent-start/SESSION_CONTEXT.md`
  - `Docs/context/agent-start/AGENT_KICKOFF_PROMPT.txt`
  - `Docs/context/agent-start/STEP1_ENV.sh`
- Compatibility mirror:
  - `.agent/SESSION_CONTEXT.md`
  - `.agent/AGENT_KICKOFF_PROMPT.txt`
  - `.agent/STEP1_ENV.sh`

### Automation (already configured)

- Terminal auto-loads `Docs/context/agent-start/STEP1_ENV.sh` when you `cd` into a project under `/Users/pranay/Projects` (zsh hook).
- VS Code/Antigravity can run `agent-start --skip-index` on folder open via `.vscode/tasks.json`.

### How agents should use this

- Provide `Docs/context/agent-start/AGENT_KICKOFF_PROMPT.txt` and `Docs/context/agent-start/SESSION_CONTEXT.md` as the first context for the agent.
- If sources conflict, the agent must cite concrete file paths and ask before proceeding.
- If the canonical pack is missing or stale, run `/Users/pranay/Projects/agent-start --skip-index` before planning changes.
- Treat `.agent/` files as compatibility mirrors only.
- Do not start implementation until the canonical `Docs/context/agent-start/AGENT_KICKOFF_PROMPT.txt` and `Docs/context/agent-start/SESSION_CONTEXT.md` are loaded.

### Optional commit safety net

Install repo-local git pre-commit hooks that refresh and stage `Docs/context/agent-start/*` before commit:

```bash
python3 /Users/pranay/Projects/workspace_memory/scripts/install_git_precommit_agent_hook.py
```

### Shared Idea Pad Protocol (Required)

- Canonical file: `/Users/pranay/Projects/idea_pad/IDEA_PAD.md`
- Raw capture file: `/Users/pranay/Projects/idea_pad/IDEA_DUMP.md`
- Do not create per-model primary copies of the idea pad.
- Do not overwrite the whole file; use append/update workflow with validation.
- Capture rough ideas in `IDEA_DUMP.md`, then promote high-signal items into `IDEA_PAD.md`.
- Before edits:

```bash
python3 /Users/pranay/Projects/idea_pad/scripts/idea_pad_tool.py validate
```

- Add new ideas safely:

```bash
python3 /Users/pranay/Projects/idea_pad/scripts/idea_pad_tool.py add --title "<title>" --owner "<agent>" --type build
```

- After updates, refresh shared memory index:

```bash
cd /Users/pranay/Projects
./projects-memory index
```

<!-- PROJECTS_MEMORY_AGENT_ALIGNMENT_END -->

## ⚠️ Skills Discovery Protocol (CRITICAL)

**Agents: DO NOT default to using `.claude` skills or `gstack`.** We have an extensive skills ecosystem across multiple locations.

### Complete Skills Reference

For a complete catalog of ALL available skills across the workspace, see:
**`/Users/pranay/Projects/SKILLS_CATALOG.md`**

### Check ALL Skills Locations (in order)

1. `~/.claude/skills/*/` — ~72 skills (Claude Code)
2. `~/.agents/skills/*/` — ~98 skills (includes Azure/Marketing)
3. `~/Projects/skills/*/` — **47 skills (most curated, engineering focus, often missed!)**
4. `~/Projects/external-skills/*/` — 2,898+ community skills
5. `~/Projects/openai-skills/` — OpenAI Codex skills (official standard repo copy)
6. `$CODEX_HOME/skills/*/` — Codex runtime-installed skills (when CODEX_HOME is set)
7. `~/.codex/skills/*/` — Codex local saved skills (default path)
8. `~/.codex/skills/.system/*/` — Codex app bundled/system skills (read-only baseline)

**gstack is NOT your primary testing tool.** Use specialized alternatives instead:

- For browser testing: `browse` skill (faster)
- For QA: `qa` or `qa-only` skills (systematic)
- For E2E: `webapp-testing` or `e2e-testing` skills (comprehensive)
- For debugging: `systematic-debugging` skill (methodology)

See `/Users/pranay/Projects/SKILLS_CATALOG.md` for complete skills reference.

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
Do not delete documentation files or documentation directories without explicit user permission in the current conversation. If docs need restructuring, preserve them via moves, archives, or clear superseded markers instead of deletion by default.

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
