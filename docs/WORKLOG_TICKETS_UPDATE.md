### TCK-20260204-P2-9 :: Standardize log levels (replace print/DEBUG inconsistency with logger)

Type: IMPROVEMENT
Owner: GitHub Copilot (agent: codex)
Created: 2026-02-04 14:00
Status: **DONE** ✅
Priority: P2

Description:
Mixed logging patterns found: some code uses `logger.debug()`, others use `logger.info()`, and many use `print()` statements with `DEBUG` guard clauses. Standardized to consistent `logging` module usage with appropriate levels (debug, info, warning, error).

Scope contract:
- In-scope:
  - Replace all `print()` calls with `logger.debug()`, `logger.info()`, `logger.warning()`, or `logger.error()`
  - Remove conditional `DEBUG` checks guarding print statements
  - Add `import logging` and `logger = logging.getLogger(__name__)` to affected files
  - Verify no functional behavior changes
- Out-of-scope:
  - Structured (JSON) logging format
  - Log aggregation/monitoring setup
  - Client-side (Swift) logging standardization
- Behavior change allowed: NO

Targets:
- Surfaces: server
- Files:
  - `server/services/asr_stream.py`
  - `server/services/diarization.py`
  - `server/services/asr_providers.py`
- Branch/PR: main

Acceptance criteria:
- [x] All `print()` statements replaced with `logger` calls
- [x] DEBUG guard clauses removed
- [x] Logger imported and initialized in each modified file
- [x] All existing tests pass
- [x] No functional behavior changes

Evidence log:
- [2026-02-04 14:00] Analyzed logging patterns | Evidence:
  - Command: `grep -r "print\(|logger\." server/ --include="*.py" | head -20`
  - Output: 13 matches found across asr_stream.py, diarization.py, asr_providers.py
  - Interpretation: Observed — inconsistent logging confirmed
  
- [2026-02-04 14:05] Standardized asr_stream.py | Evidence:
  - Changes:
    - Replaced `DEBUG` flag with `import logging` + `logger = logging.getLogger(__name__)`
    - Changed 3 `print()` statements to `logger.warning()` and `logger.debug()`
  - Interpretation: Observed — consistent logging pattern applied
  
- [2026-02-04 14:10] Standardized diarization.py | Evidence:
  - Changes:
    - Replaced 9 `DEBUG`-guarded `print()` calls with appropriate logger levels
    - Changed exception handling to use `logger.error()`
  - Interpretation: Observed — all diarization logging now uses logger module
  
- [2026-02-04 14:12] Standardized asr_providers.py | Evidence:
  - Changes:
    - Removed `DEBUG` conditional in `log()` method
    - Replaced with direct `logger.debug()` call
  - Interpretation: Observed — provider logging simplified
  
- [2026-02-04 14:15] Ran full test suite | Evidence:
  - Command: `pytest tests/ -v`
  - Output: All 13 tests passed
  - Interpretation: Observed — no regressions, all tests pass

Status updates:
- [2026-02-04 14:00] **IN_PROGRESS** — starting audit task P2-9
- [2026-02-04 14:15] **DONE** ✅ — logging standardized and tested

Summary:
Successfully replaced inconsistent `print()` + `DEBUG` pattern with proper Python `logging` module across three critical service files. All tests pass with no functional changes. Code is now easier to debug and monitor with consistent log levels (debug for diagnostic info, warning for degraded conditions, error for failures).

---
