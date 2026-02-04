# Prompt Quality Gate (EchoPanel) — v1.0

**Goal**: Ensure every prompt in `prompts/` is safe, actionable, and produces consistent artifacts.

---

## Hard rules for a “good” prompt
1) Clear role and non-goals.
2) Explicit inputs.
3) Required discovery commands (if repo access).
4) Strict output format.
5) Clear stop condition.
6) EchoPanel-aware surfaces: `macapp`, `server`, `landing`.
7) Evidence discipline: Observed/Inferred/Unknown.

---

## Required discovery (if repo access)
```bash
find prompts -maxdepth 3 -type f -name '*.md' | sort
```

---

## Output (required)
- Prompt coverage map (what work types are supported)
- Prompts failing the gate (with exact reason)
- Suggested edits (smallest change that makes them pass)

---

## Stop condition
Stop after the gate report and suggested edits are produced.

