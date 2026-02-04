# Verification (EchoPanel) — v1.0

**Goal**: Verify completed work against acceptance criteria and catch regressions with evidence.

## Inputs
- Ticket ID(s)
- Changeset summary
- Surfaces touched (macapp/server/landing)

---

## Procedure (strict)
1) Restate acceptance criteria from ticket(s).
2) Run relevant checks (touched surfaces only):
   - macapp: `cd macapp/MeetingListenerApp && swift build`
   - server: `/.venv/bin/python -m pytest -q || python -m pytest -q || true`
   - landing: `node -c landing/app.js`
3) Manual smoke checklist (pick relevant):
   - Onboarding opens and can start listening
   - Side panel shows status + transcript updates
   - Stop opens Summary and allows export
   - History shows sessions and export works
4) Record results as Observed with command outputs summarized.

## Required outputs
- Ticket(s) updated with verification evidence.
- If verification fails, create a new ticket for the regression (do not silently expand scope).

---

## Stop condition
Stop after verification evidence is recorded and tickets are updated.
