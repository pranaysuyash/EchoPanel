# Prompt Library Curation — v1.0

**Goal**: Keep prompts repo-native, versioned, and high-quality (actionable, evidence-first, consistent artifacts).

---

## Rules
- Add prompts under `prompts/<category>/...-vX.Y.md`.
- Update `prompts/README.md` when adding/removing prompts.
- Prompts must reference EchoPanel’s canonical artifacts:
  - `docs/WORKLOG_TICKETS.md`
  - `docs/audit/`
  - `docs/WS_CONTRACT.md`, `docs/ARCHITECTURE.md`, etc.
- Avoid referencing external URLs as “source of truth” unless unavoidable.

---

## Prompt quality gate (required)
Every prompt must include:
1) Clear role and non-goals
2) Explicit inputs
3) Required discovery commands (if repo access)
4) Strict output format
5) Clear stop condition
6) Evidence labels: Observed / Inferred / Unknown
7) EchoPanel surfaces: `macapp`, `server`, `landing`

Use: `prompts/workflow/prompt-quality-gate-v1.0.md` to audit prompt quality.

---

## Output (required)
- A short change log: what prompts were added/updated and why
- `prompts/README.md` updated to include new prompts
- (Optional) a new ticket in `docs/WORKLOG_TICKETS.md` if prompt changes are tied to a broader process initiative
