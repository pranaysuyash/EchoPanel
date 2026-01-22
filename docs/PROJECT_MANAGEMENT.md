# Project Management

## Milestones
- M0: UI shell
- M1: Audio capture
- M2: Streaming
- M3: Live transcript
- M4: Live analysis
- M5: Finalization + export

## PR guidelines
- Keep PRs small and reviewable.
- Each PR must include:
  - goal statement
  - verification commands
  - acceptance criteria
  - docs updates if contracts or UX flows change

## Definition of done (v0.1)
- Meets acceptance checklist in `docs/TESTING.md`.
- No silent capture behavior.
- Clear user-facing status in error and reconnect states.

## Open TODOs
- Replace local ASR stub with production streaming ASR and validate latency targets.
- Implement backend reconnect and buffering behavior aligned with spec.
- Surface diarization results in UI (currently only in final JSON).
- Align macOS UI visuals with landing page and spec UI polish.
- Add integration tests for WebSocket streaming and exports.
- Add lightweight UI snapshot or visual regression checks.
- Draft v0.2 spec and run the audit prompt in `docs/V0_2_AUDIT_PROMPT.md`.
- Decide waitlist policy (cap, pricing, invite cadence) and update landing copy.
- Add "Roadmap" tab with Sheet-backed features list on landing page.
- Add "Request a feature" form and publish "Most requested" summary on landing page.
- Define pricing tiers for local vs cloud models and document in `docs/PRICING.md`.
