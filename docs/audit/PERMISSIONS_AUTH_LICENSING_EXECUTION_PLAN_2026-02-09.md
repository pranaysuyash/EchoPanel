# Permissions, Auth, and Licensing Execution Plan (2026-02-09)

**Update (2026-02-13):**
- WebSocket and HTTP requests now support header-based auth tokens from Keychain (no app-side query-token usage): `macapp/MeetingListenerApp/Sources/BackendConfig.swift`
- Backend endpoints can be token-gated consistently when `ECHOPANEL_WS_AUTH_TOKEN` is set: see `docs/WORKLOG_TICKETS.md` (`TCK-20260213-031`)
- Signing/notarization helper script exists (dry-run by default): see `docs/WORKLOG_TICKETS.md` (`TCK-20260213-032`)
- Local backend now auto-generates a random auth token if missing (secure-by-default local mode): see `docs/WORKLOG_TICKETS.md` (`TCK-20260213-037`)
- App now refuses to start a session against a non-local backend without a token configured: see `docs/WORKLOG_TICKETS.md` (`TCK-20260213-039`)

## Scope
Define a launch-grade implementation path for:
- macOS permissions and permission recovery UX
- backend/client auth hardening
- commercial licensing and entitlement enforcement

## Current State (Observed)
1. Permissions flow exists and gates capture start.
- `macapp/MeetingListenerApp/Sources/AppState.swift:432`
- `macapp/MeetingListenerApp/Sources/AppState.swift:955`
- `macapp/MeetingListenerApp/Sources/OnboardingView.swift:116`

2. Auth exists as optional shared token for WS + documents API.
- `server/api/ws_live_listener.py:137`
- `server/api/documents.py:59`
- `tests/test_ws_integration.py:107`
- `tests/test_documents_api.py:52`

3. WS token is still sent in URL query from app config path.
- `macapp/MeetingListenerApp/Sources/BackendConfig.swift:26`

4. Licensing is documented as soft-gated and not enforced.
- `docs/LICENSING.md:13`
- `docs/PRICING.md:25`

5. Distribution still has app bundle/signing/notarization blockers.
- `docs/DISTRIBUTION_PLAN_v0.2.md:11`
- `macapp/MeetingListenerApp/Package.swift:10`

## Target End State
1. Permissions:
- First-run setup is deterministic on a clean machine.
- Every denied/partial permission has direct remediation and explicit relaunch guidance.
- Permission status is continuously accurate (foreground refresh + explicit re-check) and covered by QA scenarios.

2. Auth:
- Local mode: backend always protected by an app-generated secret, never sent in URL, localhost-only binding.
- Remote mode: mandatory auth, TLS-only (`https/wss`), no unauthenticated WS/documents endpoints.
- Token rotation path and clear operator UX.

3. Licensing:
- Entitlement state machine in app (`trial`, `active`, `grace`, `expired`, `revoked`).
- Signed entitlement validation offline with periodic refresh.
- Device activation limits and recovery (deactivate/reactivate) defined and tested.

## Implementation Plan

### Phase 1 (P0): Auth transport hardening (1-2 days)
1. Remove token-in-query for WS client path.
- Use `URLRequest` headers (`Authorization` and/or `x-echopanel-token`) for WebSocket handshake.
- Keep query-token support server-side temporarily for backward compatibility; mark deprecated.

2. Enforce secure defaults by mode.
- Local mode: always generate/use random backend token if none configured.
- Remote mode: reject startup/config if token missing or scheme is not `https/wss`.

3. Protect all sensitive endpoints consistently.
- Keep `/documents*` and `/ws/live-listener` protected.
- For `/health`, expose only non-sensitive status in remote mode, or require token if desired operationally.

Acceptance:
- New tests for header-based WS auth success.
- Regression tests still pass (`pytest`, `swift test`).
- No token appears in logs, URLs, or diagnostics exports.

### Phase 2 (P0): Distribution + permission reliability (2-4 days)
1. Move from SPM executable distribution to signed app bundle pipeline.
- Add `.app` packaging, hardened runtime, notarization, DMG output.

2. Permission UX and remediation completeness.
- Keep existing onboarding rows, but add explicit blocked-state guidance matrix:
  - Screen Recording denied
  - Screen Recording granted but relaunch required
  - Microphone denied (only when source includes mic)
- Add a short “post-settings checklist” step before starting first session.

3. Clean-machine acceptance protocol.
- New machine script/checklist for first-run path.
- Capture screenshots and logs for each permission branch.

Acceptance:
- Signed + notarized artifact tested on clean macOS.
- First-run success path under 3 minutes from install to first transcript event.

### Phase 3 (P0): Licensing foundation (3-5 days)
1. Decide commercial model now (required):
- Per-device subscription with annual option.
- Provider: Stripe + licensing service, Lemon Squeezy, or Paddle.

2. Implement entitlement model in app.
- Local signed entitlement blob in Keychain.
- Verify signature with embedded public key.
- Enforce plan limits in app state (session count/feature gates as product chooses).

3. Activation workflow.
- Enter license key -> exchange for signed entitlement.
- Device fingerprint (privacy-preserving hash) for seat limits.
- Grace window for temporary offline failures.

4. Recovery workflows.
- Reinstall/transfer device handling.
- Key revoke/refresh behavior.

Acceptance:
- End-to-end tests for `active`, `expired`, `grace`, invalid signature.
- User-visible settings page shows license status and last verification time.

### Phase 4 (P1): Operational hardening (1-2 days)
1. Token rotation and incident response.
- Rotate backend auth token from settings without app reinstall.
- Add audit-safe diagnostics exports (no secrets).

2. Policy/docs finalization.
- Finalize `docs/PRICING.md` and `docs/LICENSING.md` from draft to launch values.
- Publish data handling + retention promises aligned with implementation.

3. CI gates.
- Add release gate checks requiring:
  - tests pass
  - notarization artifact present
  - pricing/licensing docs not in draft state

## Recommended Build Order (Do this first)
1. Phase 1 auth transport hardening.
2. Phase 2 signed distribution + clean-machine permission proof.
3. Phase 3 licensing foundation.
4. Phase 4 ops/documentation closure.

## Risks and Controls
1. Risk: shipping auth token in URL leaks in logs/proxies.
- Control: header-only tokens + sanitized logging.

2. Risk: macOS permission edge cases break first-run conversion.
- Control: explicit relaunch-state handling + clean-machine test matrix.

3. Risk: licensing provider lock-in or outage blocks users.
- Control: signed offline entitlement cache with grace period.

## Definition of Done (Launch)
1. App install path is notarized and clean-machine validated.
2. Permission flow has deterministic remediation for all denial states.
3. Auth is mandatory in any non-local deployment and no URL token path is used by app.
4. Licensing is enforced with signed entitlements and tested recovery paths.
5. Pricing/licensing docs are finalized (no draft/open-question markers).
