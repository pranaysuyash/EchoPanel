# Full Repo Review - 2026-02-26

## Scope and Method

- Audit type: `AUDIT`
- Surfaces reviewed: root docs, backend entrypoints, websocket streaming path, config/rate-limit APIs, persistence/search, test harness docs.
- Method: repository evidence only (`FACT`), explicit `INFERENCE` labels where needed, and `RISK` framing for possible failure modes.
- Implementation: none (documentation-only audit).

## Files Inspected

- `README.md`
- `docs/README.md`
- `docs/BUILD.md`
- `docs/TESTING.md`
- `docs/WS_CONTRACT.md`
- `docs/audit/README.md`
- `pyproject.toml`
- `scripts/verify.sh`
- `scripts/install-git-hooks.sh`
- `.githooks/pre-commit`
- `scripts/run-dev-app.sh`
- `scripts/run-dev-all.sh`
- `scripts/build_app_bundle.py`
- `server/main.py`
- `server/security.py`
- `server/api/ws_live_listener.py`
- `server/api/documents.py`
- `server/api/config.py`
- `server/api/rate_limiter.py`
- `server/services/rag_store.py`
- `server/services/asr_providers.py`
- `macapp/MeetingListenerApp/Package.swift`
- `macapp/MeetingListenerApp/Tests/SidePanelVisualSnapshotTests.swift`

## 1) Repo Map

### High-level purpose (FACT)

- Repo describes EchoPanel as a macOS menu-bar app with local backend streaming PCM for transcript/cards/entities generation (`README.md:1-4`).
- Runtime contract centers on WebSocket `/ws/live-listener` plus local document APIs (`docs/WS_CONTRACT.md:1-36`, `docs/WS_CONTRACT.md:222-257`).

### Top-level directory inventory (FACT)

- `macapp/`: primary Swift package app (`macapp/MeetingListenerApp/Package.swift:1-35`).
- `server/`: FastAPI backend with websocket and docs APIs (`server/main.py:287-290`).
- `landing/`: static landing page + Apps Script waitlist integration (`landing/README.md:1-41`).
- `scripts/`: build/dev/release/verification tooling (`scripts/verify.sh:1-13`, `scripts/run-dev-all.sh:1-83`, `scripts/build_app_bundle.py:1-320`).
- `docs/`: product, architecture, audits, runbooks (`docs/README.md:1-161`).
- `tests/`: Python integration/unit tests for backend paths.

### Runtime components (FACT)

- macOS executable target `MeetingListenerApp` with MLX dependencies (`macapp/MeetingListenerApp/Package.swift:6-24`).
- FastAPI app with routers for websocket, documents, brain-dump query (`server/main.py:287-290`).
- Background subsystems initialized in lifespan: model preloader, embeddings, brain-dump indexer, rate limiter, optional diarization prewarm (`server/main.py:180-259`).
- Static landing page has no build step and can be hosted directly (`landing/README.md:26-41`).

### Source-of-truth run/build/test commands (FACT)

- Python dependencies via `uv` and project extras in `pyproject.toml` (`pyproject.toml:1-51`).
- Local quality gate = Git pre-commit hook -> `scripts/verify.sh` (`scripts/install-git-hooks.sh:1-9`, `.githooks/pre-commit:1-12`, `scripts/verify.sh:1-13`).
- `verify.sh` currently runs only Swift build/test (`scripts/verify.sh:7-10`).
- Distribution build via `python scripts/build_app_bundle.py --release` (`README.md:118-125`, `scripts/build_app_bundle.py:290-320`).

## 2) Docs vs Reality Truth Table

| Claim (quote) | Where stated | Evidence in code/config | Status | Fix |
|---|---|---|---|---|
| "pre-commit ... runs `./scripts/verify.sh` (`swift build` + `swift test`, including SidePanel visual snapshot tests)." | `README.md:157` | Snapshot tests are explicitly opt-in (`RUN_VISUAL_SNAPSHOTS=1`) and skipped otherwise (`SidePanelVisualSnapshotTests.swift:16-18`). `verify.sh` does not set this env var (`scripts/verify.sh:7-10`). | `FALSE` | Docs change: say snapshots are opt-in and not part of default verify. |
| "Latest Audits: Phase 0A ... Streaming Reliability" links | `README.md:145-147` | Linked files are not present at those paths; active audit index lists different files (`docs/audit/README.md:5-12`). | `FALSE` | Docs change: update links or point to archive paths. |
| docs index "Most Recent & Critical" links to `./audit/UI_UX_AUDIT_2026-02-09.md` etc. | `docs/README.md:57-60` | `docs/audit/README.md` says only 2 active audits and many moved to archive (`docs/audit/README.md:5-15`). | `FALSE` | Docs change: align `docs/README.md` with `docs/audit/README.md`. |
| WS auth token input priority starts with query param first. | `docs/WS_CONTRACT.md:20-25` | Server extraction checks Authorization header first, then `x-echopanel-token`, then query (`server/security.py:51-64`). | `FALSE` | Docs change (or code change if query-first is intended). |
| `/health` expected statuses are only 200 or 503. | `README.md:90-94` | Health endpoint invokes `_require_http_auth(request)` first (`server/main.py:352`), so 401 is also possible when auth is enabled. | `PARTIAL` | Docs change: include auth-required behavior. |
| "Comprehensive docs (50+ files, 45,000+ lines)" | `README.md:132`, `docs/README.md:148-151` | Repo does contain very large docs set (`docs/` directory inventory); exact line count not re-counted in this audit. | `UNKNOWN` | Optional: automate docs stats generation to avoid staleness. |

## 3) Findings (Grouped by Severity)

### P0

#### F-001
- Severity: `P0`
- Type: `bug`
- Evidence:
  - `server/main.py:345` calls `_require_http_auth(request)`.
  - No `_require_http_auth` definition or import exists in file (`server/main.py:1-120`, search phrase: `def _require_http_auth` not found).
- FACT: HTTP handlers reference undefined symbol.
- INFERENCE: Requests to `/`, `/health`, `/capabilities`, `/model-status` can raise `NameError` before endpoint logic completes.
- RISK: Core HTTP endpoints fail at runtime (health checks/ops visibility break).
- Repro steps:
  1. `python -m server.main`
  2. `curl -i http://127.0.0.1:8000/health`
  3. Observe server-side `NameError` (if route path hits this code path).
- Fix options:
  - Option A: Import `require_http_auth` from `server.security` and call it directly.
  - Option B: Add local wrappers `_require_http_auth` and `_extract_token` delegating to `server.security`.
- Recommended fix: Replace undefined calls with imported `require_http_auth` and centralized token extractor.
- Suggested test: Add API tests for `/health` authenticated/unauthenticated code paths.

#### F-002
- Severity: `P0`
- Type: `bug`
- Evidence:
  - Middleware calls `_extract_token(request)` (`server/main.py:310`).
  - No `_extract_token` definition/import in file (`server/main.py:1-120`, search phrase: `def _extract_token` not found).
- FACT: Rate-limit middleware references undefined symbol.
- INFERENCE: Any non-skipped HTTP request can fail before reaching handlers.
- RISK: API reliability outage under normal traffic.
- Repro steps:
  1. Start backend.
  2. Hit any non-`/health` HTTP route (e.g., `/documents`).
  3. Observe `NameError` in middleware path.
- Fix options:
  - Option A: Use `extract_http_token` from `server.security`.
  - Option B: Remove token-based client-id branching and rate-limit by source IP only.
- Recommended fix: Import/use `extract_http_token` for per-token client IDs.
- Suggested test: Middleware unit test asserting request path does not raise and sets response headers.

### P1

#### F-003
- Severity: `P1`
- Type: `reliability`
- Evidence:
  - `RateLimitState` tokens initialize to `0.0` (`server/api/rate_limiter.py:24-25`).
  - `acquire()` rejects when tokens `< 1.0` (`server/api/rate_limiter.py:102-108`).
- FACT: New clients begin with no available tokens.
- INFERENCE: First request is denied until enough refill time passes.
- RISK: Fresh sessions receive unexpected 429 responses.
- Repro steps:
  1. Create `RateLimiter(RateLimitConfig(requests_per_minute=60, requests_per_hour=1000))`.
  2. Immediately call `await limiter.acquire("client-a")`.
  3. Observe `False`.
- Fix options:
  - Option A: Initialize state with full token buckets.
  - Option B: Special-case first-seen client to grant one request.
- Recommended fix: Seed minute/hour buckets at full limits when client state is created.
- Suggested test: First acquire for new client should return `True`.

#### F-004
- Severity: `P1`
- Type: `bug`
- Evidence:
  - Config router exists (`server/api/config.py:23`).
  - App includes only ws/documents/brain_dump routers (`server/main.py:287-290`).
  - No `include_router(config_router)` found (search phrase: `include_router(` with config import absent).
- FACT: Config endpoints are defined but not mounted.
- INFERENCE: `/config` API surface is unreachable in runtime app.
- RISK: Operational config workflows are silently broken.
- Repro steps: call `GET /config` and receive 404.
- Fix options:
  - Option A: Mount config router in `server/main.py`.
  - Option B: Delete/deprecate config API and remove docs if intentionally disabled.
- Recommended fix: Mount router and add startup smoke check for expected route set.
- Suggested test: route table test asserting `/config` endpoints exist.

#### F-005
- Severity: `P1`
- Type: `bug`
- Evidence:
  - In `update_configuration`, loop reads fields from `request`, not `body` (`server/api/config.py:101-104`).
  - In `test_storage_connection`, branch checks `request.backend` and uses `request.sqlite_path` (`server/api/config.py:139-143`).
- FACT: Handlers read request-object attributes that do not correspond to payload schema.
- INFERENCE: These endpoints fail or return invalid behavior even if router is mounted.
- RISK: Config update/testing endpoints are nonfunctional.
- Repro steps:
  1. Mount router and POST valid JSON body to `/config`.
  2. Observe exception path and 400 response.
- Fix options:
  - Option A: Replace `request` field access with `body` fields.
  - Option B: Use dependency model validation helpers and explicit DTO mapping.
- Recommended fix: Correct attribute source (`body`) and add regression tests for successful update/test paths.
- Suggested test: POST `/config` with one field update returns success and persisted key list.

#### F-006
- Severity: `P1`
- Type: `reliability`
- Evidence:
  - Stop path enqueues EOF via blocking `await q.put(None)` (`server/api/ws_live_listener.py:1690-1692`).
  - Disconnect cleanup repeats `await q.put(None)` (`server/api/ws_live_listener.py:1864-1865`).
  - Queues are bounded (`get_queue` uses `asyncio.Queue(maxsize=QUEUE_MAX)` at `server/api/ws_live_listener.py:738-742`).
- FACT: EOF signaling can block when queue is full.
- INFERENCE: Session stop/cleanup can hang under overload or stalled consumers.
- RISK: Hung websocket shutdown, leaked tasks/resources.
- Repro steps:
  1. Fill queue to `maxsize`.
  2. Trigger stop/disconnect while consumer stalled.
  3. Observe shutdown blocking on `q.put(None)`.
- Fix options:
  - Option A: Use `put_nowait(None)` with fallback drop-oldest semantics.
  - Option B: Drain one item first then enqueue sentinel with timeout.
- Recommended fix: Non-blocking sentinel insertion with guarded timeout to guarantee shutdown progress.
- Suggested test: stop path should complete within timeout with pre-filled queue.

#### F-007
- Severity: `P1`
- Type: `data integrity`
- Evidence:
  - Corrupt store read is swallowed and state reset (`server/services/rag_store.py:218-225`).
- FACT: Parse/load errors clear in-memory state to empty docs without backup/recovery path.
- INFERENCE: A single malformed write can cause silent apparent data loss.
- RISK: Loss of document index visibility and user trust.
- Repro steps:
  1. Write invalid JSON to `rag_store.json`.
  2. Restart service and call list documents.
  3. Observe empty set without recovery notice.
- Fix options:
  - Option A: Keep corrupted file as `.corrupt` backup and emit explicit health warning.
  - Option B: Fail fast at startup and require operator intervention.
- Recommended fix: Preserve corrupt artifact + expose degraded-state metric/log while refusing destructive reset.
- Suggested test: corrupted store should preserve file and emit detectable warning.

### P2

#### F-008
- Severity: `P2`
- Type: `perf`
- Evidence:
  - Provider cache `_instances` grows by config key (`server/services/asr_providers.py:313,330-347,350-370`).
  - No max size/TTL/eviction policy beyond explicit manual eviction (`server/services/asr_providers.py:408-420`).
- FACT: Cache has no automatic bound.
- INFERENCE: Frequent config churn can accumulate providers and memory.
- RISK: Memory pressure over long-lived processes.
- Repro steps: repeatedly request providers with unique config combinations.
- Fix options:
  - Option A: LRU cache with max entries.
  - Option B: Time-based eviction for idle providers.
- Recommended fix: Add bounded LRU + explicit unload hook on eviction.
- Suggested test: cache size never exceeds configured max under config churn.

#### F-009
- Severity: `P2`
- Type: `docs`
- Evidence:
  - Broken links in root README latest audits (`README.md:145-147`).
  - Audit index indicates only 2 active audits and archived set (`docs/audit/README.md:5-15`).
- FACT: Key docs links point to non-existent files.
- INFERENCE: New contributors lose trust in docs as source-of-truth.
- RISK: Onboarding friction and mis-prioritized work.
- Repro steps: click links in rendered README.
- Fix options:
  - Option A: Update link targets to current active/archive paths.
  - Option B: Generate links from audit index automatically.
- Recommended fix: Make root/docs readmes derive “latest audits” from `docs/audit/README.md`.
- Suggested test: CI link checker across Markdown files.

#### F-010
- Severity: `P2`
- Type: `docs`
- Evidence:
  - Claim that default verify includes visual snapshot tests (`README.md:157`).
  - Snapshot tests skip unless env set (`SidePanelVisualSnapshotTests.swift:16-18`).
- FACT: Claim and implementation diverge.
- INFERENCE: Teams may assume UI regression coverage that is not actually running.
- RISK: False confidence in release checks.
- Repro steps: run `./scripts/verify.sh` and observe snapshots skipped.
- Fix options:
  - Option A: Correct docs to say opt-in.
  - Option B: Add separate CI job with `RUN_VISUAL_SNAPSHOTS=1`.
- Recommended fix: Update docs immediately and add optional scheduled visual test gate.
- Suggested test: CI verifies docs mention opt-in behavior exactly.

#### F-011
- Severity: `P2`
- Type: `testing gap`
- Evidence:
  - No tests found for `server/main.py` middleware undefined-name paths or config API path (search over `tests/` for `rate_limit_middleware`, `_extract_token`, `/config`).
- FACT: Critical startup/router regressions were not caught by automated tests.
- INFERENCE: Test suite emphasizes lower-level streaming paths but misses API wiring invariants.
- RISK: High-severity regressions reach main branch.
- Repro steps: inspect test inventory and route-level coverage.
- Fix options:
  - Option A: Add fast API smoke tests for route map + middleware invocation.
  - Option B: Add import-time static checks (ruff/pyflakes) in pre-commit/CI.
- Recommended fix: Add route smoke tests plus static undefined-name lint gate.
- Suggested test: `pytest tests/test_main_routes_smoke.py` and linter job blocking undefined names.

### P3

#### F-012
- Severity: `P3`
- Type: `docs`
- Evidence:
  - WS contract states token priority query/header/bearer (`docs/WS_CONTRACT.md:20-25`).
  - Code uses bearer/header/query order (`server/security.py:51-64`).
- FACT: Contract ordering mismatch.
- INFERENCE: Integrators relying on precedence behavior can be surprised during migration.
- RISK: Low-probability auth debugging complexity.
- Repro steps: provide different tokens in query/header and observe selected token source.
- Fix options:
  - Option A: Update contract docs to match code.
  - Option B: Change code to query-first (not recommended from security posture).
- Recommended fix: Keep code order and update contract docs.
- Suggested test: unit test for extraction precedence.

## Failure Modes Table (Minimum 10)

| ID | Failure Mode | Trigger | Impact | Evidence |
|---|---|---|---|---|
| FM-01 | HTTP endpoint auth helper crash | Call `/health` or `/` | 5xx / health unusable | `server/main.py:345,352` |
| FM-02 | Middleware token extraction crash | Any non-skipped HTTP request | 5xx before handler | `server/main.py:310` |
| FM-03 | First request rate-limited | New client immediate request | unexpected 429 | `server/api/rate_limiter.py:24-25,102-108` |
| FM-04 | Config API unreachable | Router not mounted | 404 for config ops | `server/main.py:287-290`, `server/api/config.py:23` |
| FM-05 | Config update request rejected | Valid payload to `/config` | persistent config impossible | `server/api/config.py:101-104` |
| FM-06 | Storage test endpoint invalid behavior | Valid payload to `/config/storage/test` | false failures | `server/api/config.py:139-143` |
| FM-07 | Stop/disconnect hang | Queue full + stop signal | stuck session cleanup | `server/api/ws_live_listener.py:1690-1692,1864-1865,738-742` |
| FM-08 | Silent RAG data loss appearance | Corrupt JSON store file | indexed docs disappear | `server/services/rag_store.py:218-225` |
| FM-09 | Memory growth in provider cache | Many unique ASR configs | RSS growth, eventual pressure | `server/services/asr_providers.py:313,350-370` |
| FM-10 | Broken audit navigation | Follow docs links | audit history inaccessible | `README.md:145-147`, `docs/README.md:57-60` |
| FM-11 | False visual-regression confidence | Run default verify | UI regressions may slip | `README.md:157`, `SidePanelVisualSnapshotTests.swift:16-18` |
| FM-12 | Auth precedence confusion | mixed token sources | integration/debug friction | `docs/WS_CONTRACT.md:20-25`, `server/security.py:51-64` |

## Root Causes (Ranked by Impact)

1. Missing integration tests for app wiring (routes/middleware/auth) let undefined names ship.
2. Documentation governance drift: manual link curation without validity checks.
3. API handler implementation hygiene issues (request vs body variable misuse) not covered by tests.
4. Reliability paths assume happy-path queue behavior (blocking sentinel insertion).
5. Cache/lifecycle policies are mostly manual (provider and persistence recovery semantics).

## Concrete Fixes (Ranked by Impact/Effort/Risk)

| Rank | Fix | Impact | Effort | Risk | Notes |
|---|---|---|---|---|---|
| 1 | Wire correct auth helpers in `server/main.py` | High | S | Low | Unblocks all HTTP endpoints. |
| 2 | Initialize rate limiter buckets full | High | S | Low | Prevents first-request 429. |
| 3 | Mount config router and fix body usage | High | S | Low | Restores config API functionality. |
| 4 | Make queue EOF signaling non-blocking with timeout | High | M | Medium | Prevents stop/disconnect hangs. |
| 5 | Add API smoke tests (routes + middleware) | High | S | Low | Catches regressions early. |
| 6 | Add markdown link check to CI/pre-commit | Medium | S | Low | Stops doc rot. |
| 7 | Reconcile README/docs audit links and test claims | Medium | S | Low | Improves onboarding trust. |
| 8 | Add corruption-safe recovery for rag store | Medium | M | Medium | Preserves user data trust. |
| 9 | Add bounded cache/eviction in ASR provider registry | Medium | M | Medium | Controls memory growth. |
| 10 | Add auth precedence contract test + doc sync | Low | S | Low | Eliminates ambiguity. |

## Test Plan

### Unit

- `test_rate_limiter_first_request_allowed` for new client token initialization.
- `test_security_extract_http_token_precedence` and `test_security_extract_ws_token_precedence`.
- `test_config_update_uses_body_fields` for payload handling.
- `test_ws_stop_does_not_block_when_queue_full` (mock queue behavior).
- `test_rag_store_corrupt_file_backup_behavior` (after fix).

### Integration

- FastAPI route smoke test: verify `/`, `/health`, `/documents`, `/config` wiring and status codes.
- Auth integration tests with `ECHOPANEL_WS_AUTH_TOKEN` set/unset.
- Stop/disconnect under backpressure test for websocket stream.

### Manual

- Launch backend and call `/health` with/without auth token.
- Perform config read/update/storage-test via HTTP client.
- Run `./scripts/verify.sh` and validate snapshot expectations match docs.
- Click key docs links from README and docs index.

## Instrumentation Plan

- Add `http_auth_failures_total` and `http_middleware_exceptions_total` counters.
- Add websocket cleanup latency histogram (`ws_cleanup_ms`).
- Emit explicit structured log when rag-store load fails with path and recovery action.
- Expose ASR provider cache size gauge (`asr_provider_cache_entries`).
- Add docs link-check report artifact in CI.

## State Machines (Text)

### HTTP request path

- `Incoming Request` -> `rate_limit_middleware` -> `auth gate` -> `handler` -> `response`.
- Failure states currently observed:
  - `middleware NameError` (undefined `_extract_token`)
  - `handler NameError` (undefined `_require_http_auth`)

### WebSocket session stop path

- `connected` -> `start` -> `streaming` -> `stop requested` -> `enqueue EOF` -> `flush ASR` -> `cancel analysis` -> `final_summary` -> `closed`.
- Failure risk state:
  - `stop requested` -> `queue full` -> `await q.put(None)` blocks -> no progress.

## Queue / Backpressure Analysis

- Realtime ingest queue is bounded per source (`server/api/ws_live_listener.py:738-742`) with byte-based drop policy in `put_audio` (`server/api/ws_live_listener.py:755-845`).
- Backpressure telemetry exists (`server/api/ws_live_listener.py:1155-1236`).
- Main reliability gap is not queue growth but shutdown sentinel insertion via blocking `put` (`server/api/ws_live_listener.py:1690-1692,1864-1865`).

## 4) Backlog PR Plan (PR-Sliced)

### PR-1: Fix HTTP auth wiring and middleware token extraction
- Scope: Replace undefined helper calls in `server/main.py` using `server.security` imports.
- Non-scope: auth model redesign.
- Files: `server/main.py`, tests for middleware/health.
- Acceptance criteria: `/health` and `/` no longer crash; auth behavior matches policy.
- Tests: new API smoke tests + auth tests.
- Risk/Rollback: low; rollback via single-file revert.
- Effort: `S`
- Dependencies: none.

### PR-2: Rate limiter first-request correctness
- Scope: initialize token buckets so first request can pass.
- Non-scope: distributed/global rate limiting.
- Files: `server/api/rate_limiter.py`, new tests.
- Acceptance criteria: first acquire for new client is allowed.
- Tests: unit tests around acquire and refill.
- Risk/Rollback: low.
- Effort: `S`
- Dependencies: PR-1 recommended first for end-to-end API stability.

### PR-3: Restore Config API surface
- Scope: mount router and fix request/body attribute misuse.
- Non-scope: config schema redesign.
- Files: `server/main.py`, `server/api/config.py`, tests.
- Acceptance criteria: `/config` endpoints reachable and functional.
- Tests: integration tests for get/update/storage-test.
- Risk/Rollback: medium (operator-facing API changes).
- Effort: `S`
- Dependencies: PR-1.

### PR-4: WebSocket shutdown hardening under full queues
- Scope: non-blocking EOF signaling with timeout-safe cleanup.
- Non-scope: rewrite queue architecture.
- Files: `server/api/ws_live_listener.py`, streaming tests.
- Acceptance criteria: stop/disconnect completes under full queue stress.
- Tests: targeted stress regression.
- Risk/Rollback: medium.
- Effort: `M`
- Dependencies: none.

### PR-5: Data-integrity hardening for local RAG store load failures
- Scope: backup corrupt file, explicit degraded-state signals.
- Non-scope: migrate to new DB.
- Files: `server/services/rag_store.py`, tests/docs.
- Acceptance criteria: corruption does not silently erase user-visible state.
- Tests: corrupt-file scenarios.
- Risk/Rollback: medium.
- Effort: `M`
- Dependencies: none.

### PR-6: Bound ASR provider cache and expose metrics
- Scope: implement max-size/eviction and cache gauges.
- Non-scope: provider interface refactor.
- Files: `server/services/asr_providers.py`, metrics/tests/docs.
- Acceptance criteria: cache size bounded under churn.
- Tests: churn simulation.
- Risk/Rollback: medium.
- Effort: `M`
- Dependencies: none.

### PR-7: Docs integrity and claim reconciliation
- Scope: fix broken links and test-claim drift in readmes/ws contract.
- Non-scope: rewriting all long-form docs.
- Files: `README.md`, `docs/README.md`, `docs/WS_CONTRACT.md`.
- Acceptance criteria: no broken links in key docs; statements align to runtime behavior.
- Tests: markdown link checker.
- Risk/Rollback: low.
- Effort: `S`
- Dependencies: none.

## 5) Top 10 Most Leveraged Fixes

1. Fix undefined auth helper references in `server/main.py` (`F-001`, `F-002`).
2. Correct rate limiter initial token state (`F-003`).
3. Mount config router + fix body usage (`F-004`, `F-005`).
4. Harden websocket stop/disconnect against full queues (`F-006`).
5. Add route/middleware smoke tests to catch undefined names early (`F-011`).
6. Add markdown link checker and refresh audit links (`F-009`).
7. Correct snapshot-coverage claim in README (`F-010`).
8. Add corruption-safe rag-store recovery + alerts (`F-007`).
9. Add bounded ASR provider instance cache (`F-008`).
10. Align WS auth precedence docs with code (`F-012`).

## 6) Unknowns and How to Resolve

- UNKNOWN: Exact current docs line-count and whether "45,000+" still true.
  - Resolve: run a deterministic docs line-count script in CI and publish badge/table.
- UNKNOWN: Whether any external consumers currently depend on `/config` API behavior.
  - Resolve: inspect usage in client code and release notes; add deprecation notice if behavior changes.
- UNKNOWN: Operational frequency of rag-store corruption events in real usage.
  - Resolve: add structured log and telemetry around load failures before selecting strict fail-fast vs recovery defaults.
