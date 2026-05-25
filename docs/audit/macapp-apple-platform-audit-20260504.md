# EchoPanel Apple Platform Audit — 2026-05-04

## Scope

Audit the current macOS app for Apple-platform blockers, architecture choices that are not well optimized for a native Apple app, and implementation risks that should shape the next remediation phase.

## Files inspected

- `AGENT_START_HERE.md`
- `.agent/AGENT_KICKOFF_PROMPT.txt`
- `.agent/SESSION_CONTEXT.md`
- `macapp/MeetingListenerApp/Package.swift`
- `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift`
- `macapp/MeetingListenerApp/Sources/BackendManager.swift`
- `macapp/MeetingListenerApp/Sources/BackendConfig.swift`
- `macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift`
- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift`
- `macapp/MeetingListenerApp/Sources/ASR/PythonBackend.swift`
- `macapp/MeetingListenerApp/Tests/RedundantAudioCaptureTests.swift`
- `macapp/MeetingListenerApp/Tests/MANUAL_TESTING_GUIDE.md`
- `scripts/build_app_bundle.py`
- `server/main.py`
- `server/api/ws_live_listener.py`
- `server/services/rag_store.py`
- `server/tests/test_embeddings.py`
- `server/README.md`
- `macapp_v2/README.md`
- `macapp_v3/README.md`

## Executive summary

- `Observed:` The app still starts a Python backend subprocess at launch, so the runtime is not yet a native-first Apple app despite the presence of a Swift/MLX path.
- `Observed:` Distribution metadata is internally inconsistent. The Swift package declares `macOS 15`, while the bundle script advertises `LSMinimumSystemVersion = 13.0`.
- `Observed:` The packaging strategy depends on PyInstaller, unsigned-executable-memory entitlement, disabled library validation, local network server/client permissions, and no app sandbox. That is a poor fit for App-Store-grade or tightly-hardened Apple distribution.
- `Observed:` The native MLX path is present but still carries non-native inefficiencies, including model reloading for streaming and temp-file round-trips for transcription.
- `Observed:` A backend regression remains in the current runtime path: Python tests fail in `RAGStore` embedding availability semantics.
- `Observed:` Repo guidance is stale or incomplete in this checkout. `AGENT_START_HERE.md` points to core docs and audit files that are absent from `docs/`.
- `Observed:` The repo still contains parallel app stacks (`macapp_v2`, `macapp_v3`) and mixed prototype/runtime narratives, increasing drift risk.
- `Observed:` Swift tests pass cleanly overall, but there are concurrency/test-hygiene warnings and unhandled-resource warnings that indicate maintenance debt.
- `Inferred:` The main risk is no longer “can EchoPanel work on macOS?” but “can it converge on one production-quality Apple architecture without carrying prototype/server-era assumptions?”
- `Recommendation:` Implement in this order: canonicalize runtime boundary, fix packaging/distribution truth, repair current backend regression, then optimize native inference/data paths.

## Primary findings

### 1. Native app boundary is still subordinate to a Python server boundary

- `Observed:` The app launches `BackendManager.shared.startServer()` directly in app initialization (`macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift:20-25`).
- `Observed:` `BackendManager` starts a subprocess, probes local ports, sets HTTP/WebSocket auth env vars, and writes server logs to a temp file (`macapp/MeetingListenerApp/Sources/BackendManager.swift:50-224`).
- `Observed:` The app’s canonical WebSocket endpoint is still `ws://127.0.0.1:8000/ws/live-listener` through `BackendConfig` (`macapp/MeetingListenerApp/Sources/BackendConfig.swift:5-55`).
- `Impact:` Runtime correctness depends on process spawning, localhost networking, health polling, and server lifecycle recovery. That is materially more fragile than a native-first Apple app architecture.
- `Why this matters for Apple:` App quality on macOS is judged less by “does it run” and more by trust, startup smoothness, permission stability, and low operational surface area. A local server + port + subprocess model pushes in the opposite direction.

### 2. Distribution truth is inconsistent and could mislead launch readiness

- `Observed:` The Swift package targets `macOS(.v15)` (`macapp/MeetingListenerApp/Package.swift:4-8`).
- `Observed:` The bundle builder publishes `MIN_MACOS = "13.0"` and writes `LSMinimumSystemVersion` from that value into `Info.plist` (`scripts/build_app_bundle.py:23-28`, `scripts/build_app_bundle.py:140-174`).
- `Observed:` `AGENT_START_HERE.md` still claims distribution is largely complete and the `.app` / `.dmg` are built and tested (`AGENT_START_HERE.md:7-17`, `AGENT_START_HERE.md:32-36`).
- `Impact:` The bundle can advertise support for OS versions that the Swift target does not actually support. That is a real launch/distribution correctness issue, not just documentation sloppiness.

### 3. Current packaging choices are poor fits for a hardened Apple app

- `Observed:` The build script is explicitly a “bundled Python backend” flow (`scripts/build_app_bundle.py:2-12`).
- `Observed:` Entitlements request `allow-unsigned-executable-memory`, `disable-library-validation`, `network.client`, `network.server`, and explicitly set `com.apple.security.app-sandbox` to `false` (`scripts/build_app_bundle.py:176-209`).
- `Observed:` `BackendManager` assumes server subprocess logs and local server ownership as first-class runtime concepts (`macapp/MeetingListenerApp/Sources/BackendManager.swift:156-176`).
- `Impact:` This increases notarization, sandboxing, review, and trust complexity. Even outside the Mac App Store, this is not the long-term architecture to optimize.

### 4. The native MLX path exists, but it is not yet optimized as the canonical path

- `Observed:` `HybridASRManager` instantiates both `NativeMLXBackend()` and `PythonBackend()` and keeps Python as a first-class runtime backend (`macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift:513-527`, `macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift:532-545`).
- `Observed:` `NativeMLXBackend.initialize()` reloads `Qwen3ASRModel` after the fallback chain already initialized a tier, specifically to support the streaming session (`macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift:164-191`).
- `Observed:` `NativeMLXBackend.transcribe()` writes incoming audio to a temp `.wav` file and reads it back before inference (`macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift:214-237`).
- `Impact:` The native path is functionally promising but still pays avoidable model-load and disk-I/O costs. Those are exactly the kinds of issues that should be removed once native becomes the canonical architecture.

### 5. A backend regression still exists in the path the app currently depends on

- `Observed:` Python tests fail in `server/tests/test_embeddings.py::TestRAGStoreEmbeddingIntegration::test_rag_store_embedding_property` because `store.is_embedding_available()` returns `True` when the test expects `False` (`server/tests/test_embeddings.py:169-182`).
- `Observed:` `LocalRAGStore.is_embedding_available()` currently returns `self.embeddings_service is not None and self.embeddings_service.is_available()` (`server/services/rag_store.py:247-257`).
- `Impact:` This is not the biggest Apple-platform issue, but it proves the current server-side runtime still has live behavioral drift. As long as the app depends on the server architecture, these regressions matter directly to product trust.

### 6. Documentation and repo topology are out of sync with the current checkout

- `Observed:` `AGENT_START_HERE.md` points to `docs/STATUS_AND_ROADMAP.md`, `docs/WORKLOG_TICKETS.md`, `docs/BUILD.md`, and `docs/audit/LAUNCH_READINESS_AUDIT_2026-02-12.md` (`AGENT_START_HERE.md:21-27`).
- `Observed:` This checkout’s `docs/` folder only contains `docs/sessions/*`; those referenced files are absent.
- `Observed:` `server/README.md` still describes the backend as a “Server Stub (local)” and points to `docs/WS_CONTRACT.md`, which is also absent here (`server/README.md:1-3`).
- `Impact:` The project cannot currently rely on its own stated intake path. That slows implementation and increases the chance of fixing the wrong layer.

### 7. Parallel app stacks are preserved, but not clearly quarantined

- `Observed:` `macapp_v2` is described as a standalone UI prototype with no backend dependencies (`macapp_v2/README.md:1-7`).
- `Observed:` `macapp_v3` is described as a full redesign with its own platform assumptions (`macapp_v3/README.md:1-20`).
- `Impact:` Keeping historical prototypes is fine, but without a canonical “production app path” note, they increase architecture drift, confusion, and accidental duplication.

### 8. Test/build health is green overall, but maintenance debt is visible

- `Observed:` `swift test` passed with `165 tests`, `12 skipped`, `0 failures`.
- `Observed:` Swift emitted warnings for unhandled resources in tests, actor-isolation/test-lifecycle mismatches, and multiple low-value test patterns.
- `Observed:` `RedundantAudioCaptureTests` is annotated `@MainActor`, but `setUp`/`tearDown` still triggered actor-isolation warnings during test compilation (`macapp/MeetingListenerApp/Tests/RedundantAudioCaptureTests.swift:5-17`).
- `Observed:` `MANUAL_TESTING_GUIDE.md` is an unhandled test resource (`macapp/MeetingListenerApp/Tests/MANUAL_TESTING_GUIDE.md:1-5`).
- `Impact:` Not a release blocker by itself, but it lowers signal quality and obscures real warnings as the app evolves.

## Failure modes

| ID | Failure mode | Severity | Evidence | Notes |
|---|---|---:|---|---|
| FM-01 | App launches but backend subprocess fails or restarts repeatedly | High | `BackendManager.swift:50-224` | User experience depends on external process health |
| FM-02 | Port `8000` is occupied by another process | High | `BackendManager.swift:69-91` | App enters error state before capture even begins |
| FM-03 | Bundle advertises unsupported macOS versions | High | `Package.swift:4-8`, `build_app_bundle.py:23-28`, `build_app_bundle.py:162-163` | Distribution correctness issue |
| FM-04 | App review/notarization hardening friction from Python-era entitlements | High | `build_app_bundle.py:176-209` | Architectural rather than cosmetic blocker |
| FM-05 | Native backend incurs avoidable startup/memory hit by reloading model | Medium | `NativeMLXBackend.swift:182-189` | Native path not yet canonicalized |
| FM-06 | Batch transcription pays temp-file disk I/O overhead | Medium | `NativeMLXBackend.swift:221-237` | Especially poor for repeated local operations |
| FM-07 | Python hybrid backend points at `/ws/transcribe`, but canonical server route is `/ws/live-listener` | Medium | `PythonBackend.swift:59-63`, `ws_live_listener.py:1277-1278` | Suggests stale or parallel contract |
| FM-08 | Backend regression in embedding availability semantics | Medium | `test_embeddings.py:169-182`, `rag_store.py:247-257` | Concrete failing test in current runtime family |
| FM-09 | Engineers follow stale docs and miss real files or blockers | Medium | `AGENT_START_HERE.md:21-27`, checkout `docs/` shape | Process risk with technical consequences |
| FM-10 | Prototype stacks (`macapp_v2`, `macapp_v3`) influence current implementation accidentally | Medium | `macapp_v2/README.md:1-7`, `macapp_v3/README.md:1-20` | Drift/duplication risk |
| FM-11 | Warning noise masks meaningful Swift concurrency regressions | Low | `RedundantAudioCaptureTests.swift:5-17` | Hygiene issue, but grows over time |
| FM-12 | Test resources remain unhandled in package graph | Low | `Package.swift:23-45`, `MANUAL_TESTING_GUIDE.md:1-5` | Build cleanliness issue |

## Root causes ranked by impact

1. The project still carries a split identity between native macOS app and localhost server product.
2. Distribution and documentation truth have drifted from the current source tree.
3. Native MLX was added as a capability, but not yet made the single operational default path.
4. Historical prototypes and migration phases were preserved without a strong canonical-boundary document in the current checkout.
5. Build/test cleanliness has been treated as secondary to capability expansion.

## Concrete fixes ranked by impact, effort, and risk

| Rank | Fix | Impact | Effort | Risk |
|---|---|---|---|---|
| 1 | Define and implement one canonical runtime boundary: native-first app, Python fallback only behind explicit diagnostic or unsupported-mode gating | Very high | High | Medium |
| 2 | Align package target, bundle minimum OS, and support matrix in one source of truth | High | Low | Low |
| 3 | Replace PyInstaller-centric distribution as the default shipping story, or explicitly demote it to fallback/dev-only | High | Medium | Medium |
| 4 | Fix stale Python hybrid contract (`/ws/transcribe` vs canonical route) or remove dead/stale path | High | Medium | Medium |
| 5 | Fix `RAGStore` embedding availability regression and re-run backend suite | Medium | Low | Low |
| 6 | Optimize native MLX startup by removing double model load and designing a reusable streaming/session model holder | Medium | Medium | Medium |
| 7 | Remove temp-file audio round trips from native transcription path where library APIs allow | Medium | Medium | Medium |
| 8 | Restore repo-native docs/worklog/audit index so future work starts from current truth | Medium | Low | Low |
| 9 | Mark `macapp_v2` and `macapp_v3` as historical/prototype paths in a canonical index doc | Medium | Low | Low |
| 10 | Clean Swift warnings and package resource declarations | Low | Low | Low |

## Recommended implementation plan

### Phase 0 — Canonical truth reset

- Create or restore the current `docs/` index files promised by `AGENT_START_HERE.md`.
- Add one short architecture note declaring the production runtime boundary.
- Explicitly label `macapp_v2` and `macapp_v3` as historical/prototype paths.

### Phase 1 — Fix product/runtime contract

- Decide the primary shipping mode:
  - Option A: native Swift/MLX primary, local Python fallback only when native capability is unavailable.
  - Option B: hybrid remains, but with a formally supported boundary and corrected packaging/docs.
- Recommended option: `A`.
- Gate Python startup behind explicit fallback conditions instead of unconditional app init.
- Make launch UX reflect the chosen mode clearly.

### Phase 2 — Repair distribution correctness

- Unify minimum supported macOS version across `Package.swift`, bundle metadata, docs, and release language.
- Reassess entitlements against the chosen runtime boundary.
- Separate “development/dev-app install” from “shipping/distribution” build scripts.

### Phase 3 — Remove native-path inefficiencies

- Eliminate redundant model reload in `NativeMLXBackend.initialize()`.
- Replace temp-file based transcription handoff with in-memory conversion where possible.
- Validate memory footprint, warmup time, and first-token latency after the refactor.

### Phase 4 — Clean current server fallback path

- Fix failing backend tests first, starting with `RAGStore` embedding availability semantics.
- Resolve stale Python WebSocket contract mismatch or remove dead code if hybrid path is no longer canonical.
- Keep the server path healthy until it is either demoted or intentionally retired.

### Phase 5 — Hygiene and observability

- Reduce Swift warning noise.
- Make skipped visual tests explicit in CI/dev docs.
- Add runtime telemetry comparing native mode, fallback mode, and recovery events.

## Test plan

### Unit

- Re-run `swift test` after each phase touching the mac app.
- Re-run `.venv/bin/pytest -q tests server/tests` after each server/fallback change.
- Add explicit tests for runtime mode selection:
  - native available → app does not spawn Python by default
  - native unavailable → controlled fallback path engages
  - packaging metadata remains internally consistent

### Integration

- Launch app in native-first mode and verify:
  - no localhost dependency in the success path
  - permissions remain stable across relaunch
  - session start/stop works without backend-process orchestration
- Launch fallback mode intentionally and verify:
  - server process lifecycle is explicit
  - route/auth health remains correct

### Manual

- Verify first launch, onboarding, screen recording permission, and microphone permission on a clean account/session.
- Verify Activity Monitor resource profile for:
  - app idle
  - native model warmup
  - 30-minute live session
  - post-session summary/export
- Verify packaged app on the oldest supported macOS version after support-matrix alignment.

## Instrumentation plan

- Add a top-level `runtime_mode` dimension: `native_primary`, `python_fallback`, `external_backend`.
- Record:
  - app startup time
  - model warmup time
  - first transcript latency
  - fallback activation count
  - backend subprocess start failures
  - route/auth mismatch failures
  - memory high-water mark during session
- Persist last runtime mode and last failure reason in a privacy-safe diagnostics surface.

## State machine diagrams

### Runtime mode state machine

```text
App Launch
  -> Capability Detection
    -> Native Available
      -> Native Warmup
        -> Ready
    -> Native Unavailable
      -> Fallback Eligibility Check
        -> Python Fallback Allowed
          -> Start Local Backend
            -> Health Ready
        -> Fallback Not Allowed
          -> Blocked With User Guidance
```

### Session start state machine

```text
Idle
  -> Permission Check
    -> Runtime Ready Check
      -> Capture Start
        -> Streaming
          -> Stop Requested
            -> Finalize Session
              -> Persist / Export / Review
```

## Queue and backpressure analysis

- `Observed:` The server still uses bounded, real-time audio queueing with queue sizing derived from audio seconds (`server/api/ws_live_listener.py:29-38`).
- `Observed:` The V3 docs describe a dual-lane architecture where live processing may drop and recording remains lossless (`macapp_v3/README.md:65-80`).
- `Assessment:` This is a sound server-era design, but once native-first becomes canonical, the queue/backpressure policy should be owned by the app runtime rather than a localhost WebSocket service whenever possible.
- `Risk:` If the localhost server remains in the critical path, queue policy, dropped-frame behavior, and subprocess recovery remain user-visible quality risks.

## Evidence citations

- `AGENT_START_HERE.md:7-17` — launch-readiness claim snapshot
- `AGENT_START_HERE.md:21-27` — referenced docs/audit entrypoints
- `macapp/MeetingListenerApp/Package.swift:4-8` — macOS 15 platform target
- `macapp/MeetingListenerApp/Sources/MeetingListenerApp.swift:20-25` — unconditional backend startup
- `macapp/MeetingListenerApp/Sources/BackendManager.swift:50-224` — subprocess, localhost, env, health, restart model
- `macapp/MeetingListenerApp/Sources/BackendConfig.swift:5-55` — canonical localhost URL construction
- `macapp/MeetingListenerApp/Sources/ASR/HybridASRManager.swift:513-527` — native + python backend co-instantiation
- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift:164-191` — chain init plus Qwen reload
- `macapp/MeetingListenerApp/Sources/ASR/NativeMLXBackend.swift:214-237` — temp-file audio round-trip
- `macapp/MeetingListenerApp/Sources/ASR/PythonBackend.swift:12-15` — optimistic availability
- `macapp/MeetingListenerApp/Sources/ASR/PythonBackend.swift:59-63` — stale `/ws/transcribe` endpoint
- `scripts/build_app_bundle.py:23-28` — bundle min OS config
- `scripts/build_app_bundle.py:140-174` — generated `Info.plist`
- `scripts/build_app_bundle.py:176-209` — entitlements
- `server/api/ws_live_listener.py:1277-1278` — canonical websocket route
- `server/services/rag_store.py:247-257` — embedding service availability logic
- `server/tests/test_embeddings.py:169-182` — failing backend regression
- `server/README.md:1-3` — server stub narrative and missing contract reference
- `macapp_v2/README.md:1-7` — historical prototype identity
- `macapp_v3/README.md:1-20` — alternate redesign identity
- `macapp/MeetingListenerApp/Tests/RedundantAudioCaptureTests.swift:5-17` — test actor-isolation hygiene debt
- `macapp/MeetingListenerApp/Tests/MANUAL_TESTING_GUIDE.md:1-5` — unhandled test resource

## Verification log

- `2026-05-04`: `swift test` in `macapp/MeetingListenerApp` — passed (`165 tests`, `12 skipped`, `0 failed`)
- `2026-05-04`: `.venv/bin/pytest -q tests server/tests` — failed (`1 failed`, `197 passed`, `2 skipped`)
- `2026-05-04`: `agent-start` failed to refresh the memory index due to embedding-dimension mismatch (`768` existing collection vs `1024` current provider`)

## Recommended next implementation slice

Implement Phase 1 first:

1. Stop unconditional Python backend startup on app launch.
2. Introduce explicit runtime-mode selection and fallback gating.
3. Align supported macOS version metadata.
4. Fix the current `RAGStore` regression so the fallback path is healthy while we demote it.
