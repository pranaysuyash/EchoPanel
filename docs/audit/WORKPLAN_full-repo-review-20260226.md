# Audit Work Plan — full-repo-review-20260226

**Ticket:** TCK-20260226-002
**Produced by:** Audit-Doc Work Planner agent (Steps 0–9)
**Date:** 2026-02-26
**Chosen doc:** `docs/audit/full-repo-review-20260226.md`
**Status:** Analysis complete; all findings verified against live code.

---

## 1) Repo Orientation

| Signal | Value |
|---|---|
| Language(s) | Swift 6.2 (macOS app), Python 3.11 (backend) |
| Framework(s) | SwiftUI / MLX (macOS), FastAPI + asyncio (backend) |
| Package manager | SPM (Swift), uv + pyproject.toml (Python) |
| Test runner | `swift test` (163 Swift tests), `pytest` (154 Python tests) |
| Linting | **None configured** — no ruff/flake8/mypy in pyproject.toml, not run in pre-commit |
| CI config | None (local pre-commit only via `.githooks/pre-commit → scripts/verify.sh`) |
| Pre-commit gate | `verify.sh` runs **only** `swift build && swift test` — Python never checked |

**Architecture:**
- `macapp/MeetingListenerApp/` — primary Swift app, Apple Silicon only
- `server/` — FastAPI backend (local process, fallback ASR path)
- `landing/` — static HTML waitlist page
- `docs/` — extensive documentation (audits, decisions, research)
- `tests/` — 154 Python tests covering backend paths

---

## 2) Audit Doc Inventory

| Path | Title/Header | Last Modified | Summary | Why High Leverage |
|---|---|---|---|---|
| `docs/audit/full-repo-review-20260226.md` | "Full Repo Review – 2026-02-26" | 2026-02-26 (untracked) | Comprehensive backend+docs audit; 12 findings FM-01→12 | Most recent, cross-cutting, concrete repro steps, confirmed bugs |
| `audit-senior-stakeholder-red-team-review.md` | Senior Stakeholder Red-Team Review | 2026-02-14 | Executive risk + go-to-market concerns | High business-risk framing; UX + reliability |
| `docs/audit/SENIOR_STAKEHOLDER_RED_TEAM_REVIEW_20260214.md` | Senior Stakeholder Review | 2026-02-14 | Detailed technical risk areas | Overlap with root-level; complements technical depth |
| `docs/audit/native-mlx-backend-multi-ai-review-20260218.md` | Native MLX Backend Multi-AI Review | 2026-02-18 (committed) | Multi-model review of NativeMLXBackend.swift + OCR | Most recent committed audit; Swift-side issues |
| `docs/audit/pipeline-intelligence-layer-20260214.md` | Pipeline Intelligence Layer | 2026-02-14 | LLM analysis pipeline risks | Cross-cutting: LLM + ASR + streaming |
| `docs/research/AUDIO_PIPELINE_GAPS_2026-02-26.md` | Audio Pipeline Gaps | 2026-02-26 | 8 concrete gap analyses with effort/risk | P0 implementation guide for TCK-20260225-001 |
| `docs/research/NLP_NER_PIPELINE_RESEARCH_2026-02-26.md` | NLP/NER Pipeline Research | 2026-02-26 | 10-component gap analysis | License risk (fasttext rejected), GLiNER path |
| `docs/NATIVE_SWIFT_MIGRATION_OPEN_QUESTIONS.md` | Native Swift Migration Open Questions | 2026-02-14 | Q1–Q10 open questions | Q5/Q8/Q9/Q10 still blocking implementation |

---

## 3) Chosen Doc

**Path:** `docs/audit/full-repo-review-20260226.md`

**Selection rationale:**
- Most recent (2026-02-26), comprehensive, still unmerged → highest urgency
- Contains two P0 `NameError` bugs confirmed failing in live test suite (`test_main_auth_gate.py`)
- Cross-cutting: covers HTTP middleware, WebSocket, RAG persistence, config API, docs governance
- Has concrete repro steps with exact file:line references for every finding
- The ONLY audit with a structured PR plan already inline → easiest to act on immediately

---

## 4) Doc Outline

| Section | What It Covers |
|---|---|
| Scope and Method | Audit surfaces, methodology (FACT/INFERENCE/RISK labeling) |
| Files Inspected | 22 files: server entrypoints, WS listener, config API, RAG store, security, Package.swift |
| 1) Repo Map | High-level purpose, directory inventory, runtime components, build/run/test commands |
| 2) Docs vs Reality Truth Table | 6 documented claims checked against code; 4 FALSE, 1 PARTIAL, 1 UNKNOWN |
| 3) Findings (P0–P3) | 12 findings: 2×P0 bugs, 5×P1 bugs/reliability, 3×P2 perf/docs/testing, 2×P3 docs |
| Failure Modes Table | FM-01→12: trigger, impact, evidence with line refs |
| Root Causes | 5 ranked causes |
| Concrete Fixes | 10 ranked fixes by impact/effort/risk |
| Test Plan | Unit + integration + manual scenarios |
| Instrumentation Plan | Metrics, logs, CI artifacts |
| State Machines | HTTP request path, WS stop path failure states |
| Queue/Backpressure | Bounded queue analysis; sentinel insertion as primary risk |
| 4) Backlog PR Plan | PR-1→7 with scope, files, tests, rollback, effort |
| Top 10 Fixes | Priority ordered summary |
| 6) Unknowns | 3 open unknowns |

---

## 5) Key Claims (Observed / Inferred / Unknown)

### P0 Bugs

| # | Claim | Tag | Evidence | Verification |
|---|---|---|---|---|
| C-01 | `_require_http_auth` is called but never defined or imported in `server/main.py` | **Observed** | `server/main.py:345,352,412,431`; `security.py` exports `require_http_auth` (no underscore prefix) | ✅ CONFIRMED — `pytest tests/test_main_auth_gate.py` fails with `NameError` |
| C-02 | `_extract_token` is called in middleware but never defined or imported | **Observed** | `server/main.py:310`; `security.py` exports `extract_http_token` (different name) | ✅ CONFIRMED — same test run triggers middleware path |
| C-03 | The fix is a 2-line import addition + rename — functions exist in `security.py` | **Observed** | `security.py:17` has `extract_http_token`, line 89 has `require_http_auth` | ✅ Verified |

### P1 Bugs

| # | Claim | Tag | Evidence | Verification |
|---|---|---|---|---|
| C-04 | Rate limiter creates new clients with `0.0` tokens → first request immediately rejected (429) | **Observed** | `server/api/rate_limiter.py:24-25`: `minute_tokens: float = field(default=0.0)` | ✅ CONFIRMED |
| C-05 | Config router is defined with 5 routes but is never mounted in `server/main.py` | **Observed** | `server/main.py:288-290`: only 3 routers; no `config` import | ✅ CONFIRMED — `GET /config` returns 404 |
| C-06 | `test_storage_connection` reads `request.backend` / `request.sqlite_path` instead of `body.backend` / `body.sqlite_path` | **Observed** | `server/api/config.py:139-143`: signature is `(request: Request, body: StorageTestRequest)` | ✅ CONFIRMED |
| C-07 | WebSocket stop/disconnect uses blocking `await q.put(None)` which hangs when queue is full | **Observed** | `server/api/ws_live_listener.py:1692,1865` use `await q.put(None)`; queue is bounded | ✅ CONFIRMED (1059-1060 also affected) |
| C-08 | `rag_store.py` silently resets to empty on JSON parse error, no backup | **Observed** | `server/services/rag_store.py:225`: `self._state = {"documents": []}` in except block | ✅ CONFIRMED |

### P2/P3

| # | Claim | Tag | Evidence | Verification |
|---|---|---|---|---|
| C-09 | ASR provider cache (`_instances` dict) has no max size or eviction policy | **Observed** | `server/services/asr_providers.py:313,350-370`: only manual `evict_provider_instance` | ✅ CONFIRMED |
| C-10 | README/docs audit links point to non-existent or archived paths | **Observed** | `README.md:145-147`; `docs/README.md:57-60` | **Inferred** — not re-verified in this pass |
| C-11 | WS contract states token priority order as query/header/bearer; code does bearer/header/query | **Observed** | `docs/WS_CONTRACT.md:20-25` vs `server/security.py:51-64` | **Inferred** — matches historical code pattern |

---

## 6) Open Questions

| # | Question | Blocking | Resolution |
|---|---|---|---|
| OQ-01 | Are any external consumers relying on the current `/config` behavior (even if 404)? | No — pre-launch product | Inspect release notes + client-side code before PR-3 |
| OQ-02 | What is the operational frequency of RAG store JSON corruption? | Severity of F-007 | Add structured log to measure before choosing fail-fast vs silent-recovery defaults |
| OQ-03 | Should WS sentinel insertion use `put_nowait` with drop-oldest, or a timeout? | Design of PR-4 | Test under real queue-full conditions; `put_nowait` + `asyncio.wait_for` is the safest default |
| OQ-04 | Does `test_main_auth_gate.py` cover the middleware path (F-002) or only handler path (F-001)? | Scope of PR-1 test | The test reaches F-001 (`/`) first; need dedicated middleware test to confirm F-002 |

---

## 7) Worklist

### Explicit Work Items (directly from audit)

#### EXP-01 — Fix undefined auth helper references in `server/main.py`
- **Category:** bug
- **Priority:** P0
- **Impact:** user-facing — ALL HTTP endpoints crash with 500 (NameError)
- **Risk if not done:** health check, capabilities, model-status are completely broken; ops visibility is zero
- **Source:** F-001/F-002, `server/main.py:310,345,352,412,431`
- **Proposed approach:**
  1. Add `from server.security import require_http_auth, extract_http_token` to top-level imports
  2. Replace `_require_http_auth(request)` → `require_http_auth(request)` (4 sites)
  3. Replace `_extract_token(request)` → `extract_http_token(request)` (1 site, middleware)
- **Affected files:** `server/main.py`
- **Acceptance criteria:**
  - `pytest tests/test_main_auth_gate.py` passes (currently fails with NameError)
  - `GET /health` with no token → 401; with valid token → 200
  - Middleware processes any request without NameError
- **Test plan:** `tests/test_main_auth_gate.py` (existing) + new test for middleware path
- **Effort:** S (< 1 hour)
- **Dependencies:** none

#### EXP-02 — Correct rate limiter initial token state
- **Category:** reliability
- **Priority:** P1
- **Impact:** user-facing — first request from any new client gets unexpected 429
- **Risk if not done:** fresh sessions denied; users perceive service as broken on first connect
- **Source:** F-003, `server/api/rate_limiter.py:24-25`
- **Proposed approach:** Change `RateLimitState` defaults to full buckets:
  `minute_tokens: float = field(default_factory=lambda: <minute_limit>)` — or seed in `acquire()` on first-seen
- **Affected files:** `server/api/rate_limiter.py`
- **Acceptance criteria:**
  - First `acquire()` call for a new client returns `True`
  - Subsequent rapid requests correctly rate-limit
- **Test plan:** unit test `test_rate_limiter_first_request_allowed`; stress test with burst
- **Effort:** S
- **Dependencies:** EXP-01 (end-to-end API needs to be working first)

#### EXP-03 — Mount config router and fix request/body variable misuse
- **Category:** bug
- **Priority:** P1
- **Impact:** developer-facing + ops — config management API entirely broken (404 + wrong field access)
- **Risk if not done:** configuration cannot be changed via API; storage tests fail silently
- **Source:** F-004/F-005, `server/main.py:288-290`, `server/api/config.py:101-104,139-143`
- **Proposed approach:**
  1. Add `from server.api.config import router as config_router` import to `server/main.py`
  2. Add `app.include_router(config_router, prefix="/config")` after existing routers
  3. In `test_storage_connection`: replace `request.backend` → `body.backend`, `request.sqlite_path` → `body.sqlite_path`, `request.postgres_url` → `body.postgres_url`
- **Affected files:** `server/main.py`, `server/api/config.py`
- **Acceptance criteria:**
  - `GET /config` returns 200 (not 404)
  - `POST /config` with valid JSON body returns success and lists updated keys
  - `POST /config/storage/test` with `{"backend": "sqlite"}` returns success response
- **Test plan:** integration tests for all 5 config routes
- **Effort:** S
- **Dependencies:** EXP-01

#### EXP-04 — Harden WebSocket shutdown against full queues
- **Category:** reliability
- **Priority:** P1
- **Impact:** user-facing — session stop/disconnect can hang indefinitely under load
- **Risk if not done:** zombie sessions; resource leaks; server requires restart to recover
- **Source:** F-006, `server/api/ws_live_listener.py:1692,1865,1059-1060`
- **Proposed approach:**
  Replace `await q.put(None)` sentinel insertion with `put_nowait` in a try/except, or use
  `asyncio.wait_for(q.put(None), timeout=1.0)` so shutdown cannot block >1s
- **Affected files:** `server/api/ws_live_listener.py`
- **Acceptance criteria:**
  - Stop path completes within 2s even when queue is at maxsize
  - No sentinel is silently dropped without a warning log
- **Test plan:** mock full queue → trigger stop → assert completion within timeout
- **Effort:** M
- **Dependencies:** none

#### EXP-05 — Corruption-safe RAG store recovery
- **Category:** data integrity
- **Priority:** P1
- **Impact:** user-facing — silently appears to lose all indexed documents on any JSON corruption
- **Risk if not done:** user data loss perception; no recovery path for ops
- **Source:** F-007, `server/services/rag_store.py:218-225`
- **Proposed approach:**
  1. On load exception: rename corrupt file to `rag_store.CORRUPT.<timestamp>.json`
  2. Emit a structured `logger.error(...)` with path + error
  3. Initialize clean state and log a `DEGRADED_STATE` event
  4. Expose via `/health` response as `"rag_store": "degraded"` flag
- **Affected files:** `server/services/rag_store.py`, `server/main.py` (health endpoint)
- **Acceptance criteria:**
  - Writing invalid JSON to store file + restart preserves `.CORRUPT` backup
  - Health endpoint reflects degraded state
  - No document list is returned as falsely empty without an error signal
- **Test plan:** corrupt-file fixture test; health check integration test
- **Effort:** M
- **Dependencies:** none

#### EXP-06 — Bound ASR provider cache with LRU eviction
- **Category:** performance
- **Priority:** P2
- **Impact:** cost/memory — RSS grows indefinitely under provider config churn
- **Risk if not done:** memory pressure in long-lived process; potential OOM under heavy config variation
- **Source:** F-008, `server/services/asr_providers.py:313,350-370`
- **Proposed approach:**
  Replace `_instances: dict` with `functools.lru_cache`-style bounded map (e.g., `OrderedDict` + max entries).
  Add `evict_lru_if_needed()` before inserting new provider.
- **Affected files:** `server/services/asr_providers.py`
- **Acceptance criteria:**
  - Cache size never exceeds configured max under 100+ unique config combos
  - Evicted providers are `unload()`-ed
- **Test plan:** churn test: 200 unique configs → assert `len(_instances) <= MAX`
- **Effort:** M
- **Dependencies:** none

#### EXP-07 — Fix docs claim drift (README, WS contract, audit links)
- **Category:** docs
- **Priority:** P2
- **Impact:** developer-facing — false confidence in test coverage; broken audit links
- **Source:** F-009/F-010/F-012
- **Proposed approach:**
  1. `README.md:157` — change snapshot test claim to "opt-in via `RUN_VISUAL_SNAPSHOTS=1`"
  2. `README.md:145-147` — update audit links to `docs/audit/README.md` canonical index
  3. `docs/README.md:57-60` — align "Most Recent & Critical" with `docs/audit/README.md`
  4. `docs/WS_CONTRACT.md:20-25` — correct token priority order to match `server/security.py`
- **Affected files:** `README.md`, `docs/README.md`, `docs/WS_CONTRACT.md`
- **Acceptance criteria:**
  - All links in key docs resolve to existing files
  - Snapshot opt-in behavior explicitly stated in docs
  - WS contract token order matches code
- **Test plan:** `find . -name "*.md" | xargs grep "docs/audit/UI_UX"` returns no hits
- **Effort:** S
- **Dependencies:** none

---

### Implicit Work Items (inferred from audit + repo state)

#### IMP-01 — Add Python tests + static analysis to `verify.sh` pre-commit gate
- **Category:** tooling / reliability
- **Priority:** P0
- **Impact:** developer-facing — ROOT CAUSE of why F-001/F-002 shipped; currently `verify.sh` runs only `swift build + swift test`; 154 Python tests and zero Python linters are never run before commit
- **Reasoning:**
  1. `scripts/verify.sh:7-10` — only Swift commands run
  2. `pyproject.toml` — no ruff/flake8/mypy configured
  3. F-001/F-002 (`NameError` undefined names) would be caught by `pyflakes` or `ruff` in seconds
  4. `test_main_auth_gate.py` already tests the exact failure — but is never run by pre-commit
- **Repo evidence:** `scripts/verify.sh:7-10`, `tests/` (154 tests), `pyproject.toml` (no lint section)
- **Proposed approach:**
  1. Add `[tool.ruff]` section to `pyproject.toml` with `select = ["F", "E"]` (undefined names = F821)
  2. Add to `verify.sh` after swift tests:
     ```bash
     echo "[verify] Running Python lint..."
     cd "$ROOT_DIR" && uvx ruff check server/ tests/
     echo "[verify] Running Python unit tests..."
     cd "$ROOT_DIR" && python -m pytest tests/ -x -q --timeout=60
     ```
- **Acceptance criteria:**
  - `verify.sh` fails on undefined Python names before commit
  - All 154 Python tests run and pass as part of pre-commit gate
  - F-001/F-002 class bugs can never re-enter `main.py`
- **Effort:** S (< 1 day)
- **Dependencies:** EXP-01 must pass first (tests currently failing)

#### IMP-02 — Add route-map smoke test to catch future wiring regressions
- **Category:** tests
- **Priority:** P1
- **Impact:** developer-facing — prevents F-004 class (router not mounted) from re-entering silently
- **Reasoning:**
  1. F-004 (config router not mounted) would be instantly caught by a simple route table assertion
  2. No such test exists (`tests/` inventory shows no smoke test for route set)
  3. Config router has 5 routes — easiest to enumerate and assert
- **Repo evidence:** `tests/` directory listing, `server/main.py:288-290`
- **Proposed approach:** `tests/test_main_routes_smoke.py` — assert all expected paths in `[route.path for route in app.routes]`
- **Acceptance criteria:** test fails if any router is un-mounted
- **Effort:** S
- **Dependencies:** EXP-01, EXP-03

#### IMP-03 — Add middleware unit test for `extract_http_token` path
- **Category:** tests
- **Priority:** P1
- **Impact:** developer-facing — `test_main_auth_gate.py` hits handler NameError (F-001) before testing middleware NameError (F-002); a dedicated middleware test is needed
- **Reasoning:**
  1. Current test hits `/` which fails at handler before middleware token extraction
  2. F-002 (middleware) is a separate code path (`server/main.py:310`) that needs its own assertion
- **Proposed approach:** Use `TestClient` to call a route after mocking `get_rate_limiter` to capture client_id computation
- **Acceptance criteria:** middleware processes requests without exception; `client_id` set correctly for token vs IP
- **Effort:** S
- **Dependencies:** EXP-01

---

## 8) PR Plan

### PR-1: Fix HTTP auth + middleware undefined names `[P0]`
- **Goal:** Make all HTTP endpoints functional — no NameError
- **Scope IN:** `server/main.py` import additions + call site renames (5 sites, ~10 lines)
- **Scope OUT:** auth logic changes, security model redesign
- **Files:** `server/main.py`
- **Tests to run:** `pytest tests/test_main_auth_gate.py -x -v` — must go from 1 FAIL → PASS
- **Documentation updates:** none
- **Rollback plan:** single-file revert; 10-line change
- **Validation checklist:**
  - [ ] `pytest tests/test_main_auth_gate.py` passes (all 4 status assertions)
  - [ ] `curl -i http://127.0.0.1:8000/health` returns 401 (no 500)
  - [ ] `curl -H "Authorization: Bearer <token>" http://127.0.0.1:8000/health` returns 200

### PR-2: Rate limiter first-request correctness `[P1]`
- **Goal:** New clients can make their first request without being rate-limited
- **Scope IN:** `server/api/rate_limiter.py` token initialization
- **Scope OUT:** distributed rate limiting, per-route limits
- **Files:** `server/api/rate_limiter.py`, new unit test
- **Tests to run:** `pytest tests/ -k "rate_limit" -v` + new test
- **Rollback plan:** single-field default change revert
- **Validation checklist:**
  - [ ] `RateLimiter(...).acquire("new-client")` returns `True` immediately
  - [ ] Burst >limits → correct 429

### PR-3: Restore config API surface `[P1]`
- **Goal:** `/config` endpoints are reachable and functional
- **Scope IN:** mount config router + fix body vs request variable in 2 handlers
- **Scope OUT:** config schema changes, new config fields
- **Files:** `server/main.py`, `server/api/config.py`, new integration tests
- **Tests to run:** `pytest tests/test_config_system.py -v` + new route integration tests
- **Rollback plan:** remove router mount + revert config.py (2-file revert)
- **Validation checklist:**
  - [ ] `GET /config` returns 200 (not 404)
  - [ ] `POST /config` with valid JSON returns `{"status": "success", "updated": [...]}`
  - [ ] `POST /config/storage/test` with `{"backend": "sqlite"}` returns success

### PR-4: WebSocket shutdown hardening `[P1]`
- **Goal:** Session stop/disconnect cannot hang on a full queue
- **Scope IN:** Replace 3 blocking `await q.put(None)` with guarded async sentinel insertion
- **Scope OUT:** Queue architecture redesign, queue max size changes
- **Files:** `server/api/ws_live_listener.py`
- **Tests to run:** `pytest tests/test_ws_live_listener.py tests/test_streaming_correctness.py -v` + stress test
- **Rollback plan:** revert 3-line change in ws_live_listener.py
- **Validation checklist:**
  - [ ] Stop path with pre-filled queue completes within 2s
  - [ ] No test regression in existing WS listener tests

### PR-5: RAG store corruption safety `[P1]`
- **Goal:** Corrupt store file creates `.CORRUPT` backup + health flag; never silently resets to empty
- **Scope IN:** `rag_store.py` load exception handler + `/health` degraded flag
- **Scope OUT:** store format migration, vector DB migration
- **Files:** `server/services/rag_store.py`, `server/main.py` (health endpoint)
- **Tests to run:** `pytest tests/test_rag_store.py -v` + new corrupt-file test
- **Rollback plan:** revert rag_store.py load exception block
- **Validation checklist:**
  - [ ] Corrupt JSON → `.CORRUPT` backup file created
  - [ ] `GET /health` reflects `"rag_store": "degraded"` in degraded state
  - [ ] Clean start → `"rag_store": "ok"`

### PR-6: Pre-commit Python gate (ruff + pytest) `[P0 implicit]`
- **Goal:** Python undefined names and test failures block commits
- **Scope IN:** `scripts/verify.sh` additions, `pyproject.toml` ruff config
- **Scope OUT:** full mypy type checking, CI pipeline changes
- **Files:** `scripts/verify.sh`, `pyproject.toml`
- **Tests to run:** `./scripts/verify.sh` — must run `ruff check` + `pytest` cleanly
- **Rollback plan:** remove 4 lines from verify.sh
- **Validation checklist:**
  - [ ] `verify.sh` fails on any file with `F821` (undefined name)
  - [ ] All 154 Python tests run in pre-commit
  - [ ] Introducing `_fake_undefined()` call in main.py causes pre-commit to block

### PR-7: Docs integrity cleanup `[P2]`
- **Goal:** README, docs index, and WS contract are accurate
- **Scope IN:** Fix 4 doc mismatches identified in audit
- **Scope OUT:** Rewriting full docs, adding new docs sections
- **Files:** `README.md`, `docs/README.md`, `docs/WS_CONTRACT.md`
- **Validation checklist:**
  - [ ] Snapshot test opt-in behavior documented
  - [ ] All audit links resolve to existing files
  - [ ] WS token priority in contract matches `security.py` actual order

---

## 9) Research TODOs

| # | What to look up | Why it matters | Decision it changes |
|---|---|---|---|
| R-01 | `asyncio.wait_for` vs `put_nowait` + drain-one semantics for bounded queue shutdown | Determines safest sentinel strategy for PR-4; wrong choice could lose final audio frames | Implementation detail in EXP-04 |
| R-02 | Best practice for FastAPI route-table smoke tests (using `app.routes` introspection or pytest-asyncio startup) | Shapes IMP-02 test architecture | Whether to use TestClient vs introspection |
| R-03 | Is there a `uvx ruff` mode that fits into `uv`-managed venvs without `ruff` in pyproject deps? | Determines whether to add `ruff` as dev dep or use `uvx` in verify.sh | PR-6 exact implementation |

---

## Quick-Start Fix Order

Given all findings are verified live, the recommended implementation order:

```
PR-1 (EXP-01)       → 10 min  → unblocks all HTTP endpoints + tests
PR-6 (IMP-01)       → 30 min  → pre-commit gate prevents recurrence
PR-2 (EXP-02)       → 30 min  → rate limiter correctness
PR-3 (EXP-03)       → 45 min  → config API restored
IMP-02/IMP-03       → 1 day   → test coverage gaps
PR-4 (EXP-04)       → 1 day   → WS shutdown safety
PR-5 (EXP-05)       → 1 day   → RAG store safety
PR-6 (EXP-06)       → 2 days  → cache eviction
PR-7 (EXP-07)       → 1 hour  → docs cleanup
```

**Total estimated effort:** ~1 week for all items.
**Highest-leverage first 2 hours:** PR-1 + PR-6 = unblock all tests + prevent recurrence.
