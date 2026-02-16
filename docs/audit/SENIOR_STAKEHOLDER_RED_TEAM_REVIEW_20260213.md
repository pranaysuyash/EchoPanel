# Senior Stakeholder Red‑Team Review — 2026-02-13

Author: GitHub Copilot (agent)
Role: Senior stakeholder (red‑team)

Executive verdict: NOT SHIPPABLE WITHOUT RESET — critical pipeline and runtime verification failures block any credible release. See Stop‑Ship list and 2‑week rescue plan.

---

## Update (2026-02-13)

Some of the Stop‑Ship items cited in this red‑team review have been remediated later on 2026-02-13, but not all have end-to-end runtime proof yet.

Resolved (observed on 2026-02-13):
- ✅ macOS app builds: `cd macapp/MeetingListenerApp && swift build` (PASS)
- ✅ Python tests can import `server` and run: `.venv/bin/python -m pytest -q tests/test_streaming_correctness.py tests/test_provider_whisper_cpp_contract.py` (PASS)

Still open / needs evidence:
- 🔵 Golden‑path smoke test + CI gate is still missing (no enforced end‑to‑end capture→transcript test in CI).
- 🟡 Model preload readiness needs runtime proof for the default config (`/model-status` ready=true) and for any “large model” options, even if unit tests exist.

## Summary (short)
- What works (observed): repository contains comprehensive audits and tickets; server has model preloader and rich flows; many unit tests exist. Evidence: `docs/WORKLOG_TICKETS.md`, `docs/audit/*`, `server/services/model_preloader.py`.
- What is broken (observed, reproducible): model preload fails due to invalid default model name; macOS UI currently fails to build; dev/test environment can't run core tests (`pytest` cannot import `server`); no enforced golden‑path smoke tests. Evidence: `server.log` (model init error), `build.log` (Swift compile errors), `pytest` output (ModuleNotFoundError).
- Decision: Do not ship. Execute the 2‑week Rescue Plan below and require sign‑off on the Stop‑Ship gate list.

---

## PHASE 0 — Ship criteria (how we define "shippable")
(8 concise, testable criteria — how to test each in <5 minutes)
1. Reliable capture → transcript: start, speak, stop → transcript with timestamps appears. Test: Start UI session, stop, check `transcriptSegments` non‑empty in UI or `/documents` API.
2. Deterministic storage: session bundle saved with audio + metadata. Test: Export session bundle and inspect `audio_manifest` in exported zip.
3. Model warmup offline: server preloads model without internet. Test: Start server offline, check `/model-status` ready=true.
4. Visible failure states: `/health` explains any missing dependency or error. Test: `curl /health` and confirm HTTP 200 or actionable 503 detail.
5. Search/retrieval works across time ranges. Test: Create two sessions (now, yesterday), run UI search and confirm matches and correct timestamps.
6. Export formats are correct (JSON/MD) and include timestamps. Test: Use UI export; validate JSON schema contains t0/t1.
7. No silent data loss on crash; recoverable session present. Test: Kill app during session, relaunch, check `Recover Last Session` enabled.
8. CI smoke + release gate: a golden‑path smoke test exists and passes. Test: CI job runs `smoke/golden_path` and returns success.

---

## PHASE 1 — Reality check (evidence-first)
A) Fresh install / first run
- Observed: local developer cannot run tests or the app reliably. `pytest` fails during collection (ModuleNotFoundError: No module named 'server'); `curl /health` refused. Evidence: test output and failed curl (see `pytest` output and terminal). Severity: Stop‑Ship. Fix: add reproducible dev bootstrap + ensure PYTHONPATH/venv documentation and CI.

B) Core capture & pipeline
- Observed: model preloader logs error "Invalid model size 'large-v3-turbo'" and warmup incomplete. Mac app shows compile errors in `MeetingListenerApp.swift`. Evidence: `server.log` lines showing model init failure; `build.log` with Swift compiler errors. Severity: Stop‑Ship. Fix: canonicalize model keys, add server‑side validation and UI filtering; fix Swift build errors.

C) Retrieval and trust
- Observed: cannot verify search/export because pipeline is blocked. Evidence: server unreachable, UI not buildable. Severity: High. Fix: restore golden path and add E2E tests.

D) Failure behavior
- Observed: some failures are visible in logs (`/model-status`), but others are silent because test and CI gates are missing. Evidence: mixed — `server.log` contains clear messages while UI and CI lack gates. Severity: High. Fix: surface errors in UI and block releases on `/health`.

Each of the above failure items includes the exact file/log references in the Evidence section below.

---

## PHASE 2 — Audit & backlog forensics (reality of closures)
- Audit docs exist and many tickets marked DONE in `docs/WORKLOG_TICKETS.md`. However, closure claims often lack runtime evidence (missing test or failing CI).
- Example discrepancy: `UI_UX_AUDIT_2026-02-10.md` lists fixes, but `macapp` currently fails to compile (see `build.log`). Verdict: documentation closed; runtime verification still open.

Audit Closure — sample (evidence-backed)
- Finding: Model warmup failure
  - Source: `docs/audit/STREAMING_ASR_AUDIT_2026-02.md` (Reliability section)
  - Claim status: audit noted warmup; reality: still failing (see `server.log`).
  - Verdict: Still open — REQUIRE evidence (test + `/model-status` ready)

- Finding: Circuit breaker consolidation
  - Source: `docs/WORKLOG_TICKETS.md` (CircuitBreaker consolidation)
  - Claim status: DONE + unit tests; Reality: unit tests present but no E2E smoke. Verdict: Closed for unit surface; still needs integration verification.

(Full Audit Closure Table must be compiled into `docs/audit/` as follow‑up — see Rescue Plan.)

---

## PHASE 3 — Pipeline Broken Map (quick)
First failing link: model preload (server cannot load configured model). Evidence: `server.log:13-15` "Model initialization failed: Invalid model size 'large-v3-turbo'".
Downstream symptoms: `/health` reports loading, UI disabled, no transcripts produced.
Why debugging is hard: missing golden‑path smoke tests, environment fragility, and configuration drift between UI and server.

---

## PHASE 4 — Top 3 root causes
1. Configuration / surface contract drift (UI shows unsupported model names). Evidence: `.env.example`, `SettingsView.swift` vs `provider_faster_whisper._get_model()`.
   - Policy: UI must query provider capability API before showing model options.
2. No enforced golden‑path smoke tests or CI gating. Evidence: failing runtime issues not prevented by CI.
   - Policy: add mandatory CI smoke checks for `/health` and a synthetic audio→transcript integration test.
3. Frontend stability not gated by integration tests (Swift compile errors slipped in). Evidence: `build.log` shows compile failures.
   - Policy: require `swift build` + smoke in PR checks.

---

## PHASE 5 — Stop‑Ship Gates (top items — must be fixed)
1. Model preload error (invalid model key). Reproduce: start server → `server.log` shows model init failure. Acceptance: `/model-status` shows ready=true for default config and UI no longer exposes invalid names.
2. No golden‑path smoke test. Acceptance: CI runs smoke test (synthetic audio → transcript) and passes.
3. macOS UI must build. Acceptance: `swift build` and `swift test` pass in CI and local dev.
4. Dev/test env reproducible. Acceptance: `pytest -q` runs locally in clean clone after following README dev setup.
5. `/health` must reflect ASR readiness and block release. Acceptance: `curl /health` returns 200 OK on RC builds.
(Complete Stop‑Ship list included in attached worklog ticket entry.)

**Status (2026-02-13):**
- Gate 1: **PARTIAL** (unit tests exist; runtime `/model-status` proof still required)
- Gate 2: **OPEN**
- Gate 3: **RESOLVED locally** (build passes; CI proof still required)
- Gate 4: **PARTIAL** (targeted pytest passes; full-suite + clean-clone instructions not re-verified here)
- Gate 5: **PARTIAL** (server implements readiness-aware `/health`; curl proof still required)

---

## 2‑Week Rescue Plan (execution-focused)
Week 1 — Stabilize (priority)
- Day 1: Patch config drift (map/remove `large-v3-turbo`); add validation + unit tests. Owner: Backend. Acceptance: `/model-status` shows model_ready or clear error with fix path.
- Day 1: Fix dev/test setup so `pytest` can run. Owner: Infra. Acceptance: `pytest -q` passes for core tests.
- Day 2: Add CI `/health` smoke gate and run server warmup in CI. Owner: CI. Acceptance: CI green only when `/health` OK.
- Day 3: Add headless golden-path integration test (synthetic audio → transcript). Owner: Backend + QA. Acceptance: test passes.
- Day 4: Fix Swift compile errors and unblock mac app build. Owner: Frontend. Acceptance: `swift build` passes.
- Day 5: Verify exports and search with integration tests.

Week 2 — Polish (UX & reliability)
- Day 6–7: Surface `/health` reasons in UI; improve onboarding messages. Owner: Frontend.
- Day 8: Add E2E export/search tests. Owner: Backend.
- Day 9: Stabilize model lifecycle (unload/evict tests). Owner: Backend.
- Day 10: Release candidate smoke, stakeholder demo, and sign‑off.

Kill list (pause until golden path stable): Broadcast beta features, non‑essential UI experiments, heavy RAG/embedding work.

---

## Acceptance / Sign‑off criteria (for release)
- All Stop‑Ship items fixed and evidenced by tests + logs.
- Golden‑path smoke test passes in CI and locally.
- Demo: live end‑to‑end capture → transcript → export completed by engineering lead.

---

## Evidence citations (selected)
- `server.log` lines 12–15: Model initialization failed: Invalid model size 'large-v3-turbo'.
- `build.log` (macapp): compiler errors in `MeetingListenerApp.swift` (missing symbols / syntax errors).
- `tests` run: `pytest` collection errors: ModuleNotFoundError: No module named 'server'.
- Code locations: `server/services/model_preloader.py`, `server/services/provider_faster_whisper.py`, `macapp/MeetingListenerApp/Sources/SettingsView.swift`, `docs/WORKLOG_TICKETS.md`.

---

## Next actions (immediate)
1. Create PR: canonicalize model key + server validation (blocker). Owner: backend. Time: 0.5 day.
2. Create PR: add golden‑path smoke test + CI gating. Owner: infra. Time: 1 day.
3. Fix Swift build failures. Owner: frontend. Time: 1 day.
4. Run stakeholder demo after Week‑1 tasks complete.

---

### Appendix — Quick reproduction commands (evidence)
- Check server health: `curl -v http://127.0.0.1:8000/health`
- Check model status: `curl -s http://127.0.0.1:8000/model-status | jq .`
- Run core tests: `pytest -q tests/test_model_preloader.py tests/test_ws_live_listener.py`
- Build mac app: `cd macapp/MeetingListenerApp && swift build`

---

End of report. Add this file to `docs/audit/` and create a worklog ticket referencing the Stop‑Ship items.
