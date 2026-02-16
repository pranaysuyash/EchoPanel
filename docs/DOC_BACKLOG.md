# Docs-Derived Backlog

**Last Updated:** 2026-02-14

Backlog items extracted from documentation and embedded workflow artifacts. Each item links to evidence in source docs.

## Backlog Table

| ID | Source | Type | Description | Evidence Snippet | Owner Area | Risk / Blast Radius | Effort | Dependencies | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DOC-001 | `docs/STATUS_AND_ROADMAP.md` → “Known Limitations” | governance | Code signing and notarization remain blocked; distribution cannot proceed. | “Code signing… requires Apple Developer Program… Notarization… blocked by code signing.” | infra | High / distribution | S | Apple Developer Program | blocked |
| DOC-002 | `docs/STATUS_AND_ROADMAP.md` → “Pre-Launch Checklist” | qa | Validate graceful behavior when offline. | “Test with no internet (graceful degradation)” | qa | Med / runtime behavior | S | None | new |
| DOC-003 | `docs/STATUS_AND_ROADMAP.md` → “Pre-Launch Checklist” | qa | Validate behavior when permissions are denied. | “Test with denied permissions” | qa | Med / permissions UX | S | None | new |
| DOC-004 | `docs/STATUS_AND_ROADMAP.md` → “Pre-Launch Checklist” | design | App icon design not completed. | “App icon design” | ui | Low / brand | M | Design assets | new |
| DOC-005 | `docs/STATUS_AND_ROADMAP.md` → “Pre-Launch Checklist” | product | App Store metadata not prepared. | “App Store metadata” | product | Med / launch | M | Marketing copy | new |
| DOC-006 | `docs/STATUS_AND_ROADMAP.md` → “Pre-Launch Checklist” | doc-only | Privacy policy for audio capture not prepared. | “Privacy policy for audio capture” | docs | Med / compliance | S | Legal copy | new |
| DOC-007 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | improvement | Add lightweight UI snapshot / visual regression checks. | “Add lightweight UI snapshot or visual regression checks.” | ui | Low / QA | S | None | doc-stale |
| DOC-008 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | improvement | Add integration tests for WebSocket streaming and exports. | “Add integration tests for WebSocket streaming and exports.” | tests | Med / regressions | M | Test harness | needs-verify |
| DOC-009 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | improvement | Surface diarization results in UI (currently final JSON only). | “Surface diarization results in UI (currently only in final JSON).” | ui | Med / UX | M | API/UX design | needs-verify |
| DOC-010 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | improvement | Replace local ASR stub with production streaming ASR and validate latency targets. | “Replace local ASR stub with production streaming ASR and validate latency targets.” | backend | High / core pipeline | L | ASR infra | needs-verify |
| DOC-011 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | doc-only | Draft v0.2 spec and run audit prompt in `docs/V0_2_AUDIT_PROMPT.md`. | “Draft v0.2 spec and run the audit prompt…” | docs | Low / planning | M | Spec scope | needs-verify |
| DOC-012 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | product | Decide waitlist policy and update landing copy. | “Decide waitlist policy… update landing copy.” | product | Med / GTM | M | Product decision | blocked |
| DOC-013 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | feature | Add landing page roadmap tab backed by a sheet. | “Add \"Roadmap\" tab with Sheet-backed features list on landing page.” | landing | Low / marketing | M | Product decision | needs-verify |
| DOC-014 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | feature | Add “Request a feature” form and publish “Most requested” summary. | “Add \"Request a feature\" form…” | landing | Low / marketing | M | Product decision | needs-verify |
| DOC-015 | `docs/PROJECT_MANAGEMENT.md` → “Open TODOs” | product | Define pricing tiers for local vs cloud models and document in `docs/PRICING.md`. | “Define pricing tiers for local vs cloud models…” | product | Med / monetization | M | Pricing decision | blocked |

