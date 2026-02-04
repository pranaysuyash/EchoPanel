# Docs Index Enforcer (EchoPanel) — v1.0

**Goal**: Keep documentation navigable by ensuring docs folders have entrypoints and indexes are consistent.

---

## Required discovery (if repo access)
```bash
find docs -maxdepth 3 -type f -name '*.md' | sort
rg -n \"docs/\" -S docs prompts README.md || true
```

---

## Output (required)
- Missing indexes/entrypoints (e.g., `docs/README.md`, `docs/audit/README.md`)
- Broken references (paths that don’t exist)
- Proposed minimal fixes (which files to add/update)

---

## Stop condition
Stop after listing the exact edits required (do not implement unless explicitly asked).

