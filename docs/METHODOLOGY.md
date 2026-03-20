# EchoPanel — Project Methodology

> How we work on projects. The pattern that emerged from the 2026-03-19 session.

---

## The Core Loop

For every project we touch, we follow this sequence:

```
Explore → Assess → Fix/Build → Validate → Document → Review (HIG/Skills) → Document
```

**Never skip "document"** — every decision, every finding, every open question gets written down before moving on.

---

## 1. Explore Before Acting

**Rule:** Read the existing code, docs, and context before writing anything.

### What to Read First
- `README.md` — project overview
- `AGENTS.md` — project-specific agent rules
- `STATUS.md` or `*.md` in `docs/` — current state
- The main entry point — the app shell, the main file
- Recent commits or audit docs

### Why
You can't improve what you don't understand. Writing code on a codebase you haven't read is guessing. The 15 minutes spent reading prevents an hour of rewriting wrong things.

### Practice
```bash
# Always do this before touching a project:
ls -la                   # understand directory structure
cat README.md            # get oriented
cat docs/STATUS*.md      # current known state
git log --oneline -10   # recent changes
```

---

## 2. Assess Before Planning

**Rule:** Categorize the work before assigning effort.

### The Priority Matrix

| | Quick Win | Heavy Lift |
|---|---|---|
| **Clear** | P0 — Fix now | P1 — Schedule |
| **Unclear** | Investigate first | Backlog — research needed |

### Categories We Use

**🔴 P0 — Immediate (≤15 min)**
- Security issues
- Memory leaks / crashes
- Clear bugs with obvious fixes
- One-liner fixes

**🟡 P1 — Scheduled (≤2 hrs)**
- Features with clear scope
- Non-critical bug fixes
- Known-effort UI improvements

**🔵 P2 — Backlog**
- Exploratory work
- Large features without clear scope
- "Nice to have" items

**⚫ Investigate — Before Planning**
- Anything where you don't know the scope
- Fix it first in isolation before timing it

### What Makes Something P0 vs P1
- **P0:** You know exactly what's wrong and exactly how to fix it
- **P1:** The fix is clear but requires multiple files or testing

---

## 3. Skills First, Then Code

**Rule:** When a skill exists for the task, read it before doing the work.

### Skills We Have
- `macos-hig-designer` — macOS UI/UX audit against HIG
- `macos-app-design` — macOS-specific design decisions
- `macos-development` — Swift/SwiftUI patterns
- `coding-agent` — delegating to Codex/Claude Code
- `github` — GitHub operations
- `azure-*` — Azure cloud operations

### The Anti-Pattern to Avoid
> ❌ "I know macOS design, let me just build it"
> ✅ "Let me read the macos-hig-designer skill first"

The skills encode hard-won knowledge. Using them is faster than discovering what they teach.

### When Multiple Skills Apply
Pick the most specific one first. Read it, follow it.

---

## 4. The Sub-Agent Pattern

**Rule:** Use a focused sub-agent for multi-step work that takes >10 minutes.

### When to Spawn a Sub-Agent
- Work has 3+ distinct phases
- Work can run while we do something else
- Work requires sustained context (a fresh agent is better for long tasks)
- You want parallel progress on two things

### When NOT to Spawn
- The task is <15 minutes
- The task requires your active context (you need to make decisions mid-way)
- The task is a single file edit

### How to Brief a Sub-Agent Well

```markdown
## Context
[What the project is, where it lives, what state it's in]

## Your Mission
[Numbered phases, clear deliverables per phase]

## Constraints
[What NOT to touch, what must stay valid]

## Success Criteria
[How you'll know it's done]
```

### The Brief Must Include
1. **Working directory** — exactly where to run
2. **What exists** — so it doesn't waste time discovering
3. **What to produce** — exact file names and formats
4. **What NOT to change** — explicit exclusions
5. **Validation** — how to confirm it worked (`swift build`, `node --check`, etc.)

---

## 5. Immediate Fixes vs Sub-Agent Work

### Fix Immediately (do these now, in this session)
- Single-file bugs with obvious fixes
- P0 security/memory issues
- Clear documentation gaps
- Skill-guided quick wins

### Sub-Agent Work (spawn and let it run)
- Multi-file implementations
- Exploratory audits
- Learning docs / notebooks
- Comprehensive builds with mock data
- Anything that would take >10 minutes of uninterrupted work

### The Test
> Can I explain what needs to happen in 3 sentences? → Do it now.
> Does it require reading 10 files first? → Sub-agent.

---

## 6. Validation Before Finishing

**Rule:** Every code change gets validated before reporting done.

### Validation Checklist
- [ ] Syntax check: `python -m py_compile`, `swift build`, `node --check`
- [ ] No new errors introduced (compare output before/after)
- [ ] Logic: does it actually do what the ticket says?
- [ ] If changing a build: run the build
- [ ] If changing an agent: run the agent and check results

### Common Validation Commands
```bash
# Python
cd ~/Projects/project && .venv/bin/python -m py_compile server/file.py

# Swift
cd ~/Projects/project/macapp/MeetingListenerApp && swift build

# Node/JS
node --check file.js
sed -n '/<script>/,/<\/script>/p' file.html | sed '1d;$d' > /tmp/check.js && node --check /tmp/check.js

# Git
git add -A && git commit -m "fix: ..."
```

---

## 7. Documentation Standards

**Rule:** Document WHILE you work, not after.

### What to Document
- Decisions made and WHY (not just what)
- Open questions with owners
- External dependencies (APIs, services, infra)
- Anything that would help a future agent or human

### Where Documents Go
```
project/
  README.md          — what it is, how to run
  AGENTS.md          — project-specific rules for agents
  docs/
    STATUS.md       — current state, last updated
    WORKLOG.md      — changelog (what changed, when, who)
    WORKLOG_TICKETS.md — ticket tracker (TCK-YYYYMMDD-NNN)
    audit/
      YYYY-MM-DD-AUDIT.md — any audit findings
    algorithms/     — algorithm docs (for ML/AI projects)
    learning/       — learning resources
  notebooks/        — Jupyter notebooks
```

### Ticket Format (WORKLOG_TICKETS.md)
```
nn. **TCK-YYYYMMDD-NNN** — Description ✅/📋 🔴 (date)
```
- ✅ = Done
- 📋 = In progress
- 🔴 = Blocked
- Include date completed

---

## 8. The macOS HIG Audit Pattern

**Trigger:** Any UI work on a macOS app.

### Skills to Read First
1. `macos-hig-designer` — full HIG reference
2. `macos-app-design` — macOS-specific patterns
3. `macos-development` — Swift 6+ patterns

### Audit Structure
```
1. Window & Panel Design — minimum size, position, style
2. Menu Bar Extras — state, actions, recent items
3. Onboarding — skip/cancel, keyboard nav, accessibility
4. Navigation & Keyboard — tab order, shortcuts, focus
5. Visual Design — system colors, spacing, typography
6. Error Handling — recovery actions, specific messages
```

### Issue Format
```
**Issue N — Category**
- Location: file:line
- Problem: what HIG says vs what it does
- HIG ref: specific guideline
- Fix: estimate + approach
```

### Severity Guide
| Severity | Meaning | Action |
|---|---|---|
| **Medium** | Violates HIG, not critical | Schedule fix |
| **Low** | Minor deviation, cosmetic | Fix when convenient |
| **Critical** | Causes crashes, data loss | P0 immediate fix |

---

## 9. Session Logging

**Rule:** Every session gets logged at the end.

### What Goes in the Daily Log
```markdown
## Project — What Happened
**Context:** what Pranay asked for
**What happened:** step by step what we did
**Output:** what was created/changed
**Decisions:** what we chose and why
**Issues found:** bugs, gaps, blockers
**Next:** what needs to happen next
```

### What Goes in MEMORY.md
```markdown
## Project X
- Location: ~/Projects/x/
- Status: [brief one-liner]
- Current best: [if running experiments]
- Known issues: [what's broken or needs work]
- TODO: [prioritized next steps]
```

---

## 10. The "Stop and Document" Triggers

Stop the current task and write findings if:
1. You've spent >15 minutes exploring a project (write findings before building)
2. You found something unexpected (a bug, a gap, a better approach)
3. Pranay says "not right now" (document it so it survives the session)
4. You're about to hand off to a sub-agent (document context first)
5. A decision was made (document the why, not just the what)

---

## Anti-Patterns We Avoid

**❌ Build first, read later** — Resist the urge to start coding. Read first.

**❌ "I'll remember this"** — You won't. Write it down.

**❌ Skipping validation** — If it doesn't build, it doesn't ship.

**❌ Unbounded scope** — "While I'm at it" is how 1-hour tasks become 1-week tasks. Stay scoped.

**❌ Forgetting to update WORKLOG** — If it's not in the ticket log, it didn't happen.

**❌ Skipping the skill** — If a skill exists for the task and you don't read it, you're working harder than you need to.

---

## The Golden Rule

> **Every decision, every finding, every open question gets written down before moving on.**

The alternative is sessions where 50% of the time is spent re-discovering what was already known. Documentation is the multiplier that makes every subsequent session 10x more productive.
