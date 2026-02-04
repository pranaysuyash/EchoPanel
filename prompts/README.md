# Prompt Library (EchoPanel)

This folder contains repo-native prompts for consistent planning, audits, and implementation.

## How to use
1. Pick a work type (audit, remediation, UX review, status update, etc.).
2. Use the corresponding prompt file below.
3. Ensure outputs are tracked in `docs/WORKLOG_TICKETS.md` and, when relevant, `docs/audit/`.

## Conventions (required)
- **Evidence-first**: label non-trivial claims as **Observed / Inferred / Unknown** and point to a file path, command output, screenshot, or reproduction step.
- **Scope discipline**: one prompt run should produce one concrete artifact (audit report, plan, ticket set, implementation PR slice).
- **Source of truth**: tracking is append-only in `docs/WORKLOG_TICKETS.md`.

## Index

### Workflow
- `prompts/workflow/agent-entrypoint-v1.1.md`
- `prompts/workflow/worklog-v1.1.md`
- `prompts/workflow/issue-to-ticket-intake-v1.0.md`
- `prompts/workflow/ticket-hygiene-v1.0.md`
- `prompts/workflow/worklog-to-issues-triage-v1.0.md`
- `prompts/workflow/handoff-v1.0.md`
- `prompts/workflow/completion-report-v1.0.md`
- `prompts/workflow/canonical-file-finder-v1.0.md`
- `prompts/workflow/docs-index-enforcer-v1.0.md`
- `prompts/workflow/prompt-quality-gate-v1.0.md`
- `prompts/workflow/pre-flight-check-v1.0.md`
- `prompts/workflow/prompt-library-curation-v1.0.md`

### Audit
- `prompts/audit/audit-v1.0.md` (legacy lightweight)
- `prompts/audit/file-audit-v1.0.md` (comprehensive single-file)

### Remediation
- `prompts/remediation/implementation-v1.1.md`

### UI/UX
- `prompts/ui/ui-ux-design-audit-v1.1.0.md`
- `prompts/ui/repo-ui-audit-v1.0.md`
- `prompts/ui/ui-change-spec-v1.0.md`

### Product
- `prompts/product/feature-prd-and-ticketing-v1.0.md`
- `prompts/product/backlog-grooming-v1.0.md`
- `prompts/product/next-focus-strategy-v1.0.md`
- `prompts/product/lightweight-market-scan-v1.0.md`

### QA
- `prompts/qa/test-plan-v1.0.md`
- `prompts/qa/test-execution-report-v1.0.md`
- `prompts/qa/regression-hunt-v1.0.md`
- `prompts/qa/randomized-exploratory-testing-pack-v1.0.md`

### Review
- `prompts/review/pr-review-v1.0.md`
- `prompts/review/completeness-check-v1.0.md`
- `prompts/review/generalized-code-review-audit-v1.0.md`

### Security
- `prompts/security/privacy-review-v1.0.md`
- `prompts/security/threat-model-v1.0.md`
- `prompts/security/dependency-audit-v1.0.md`

### Hardening
- `prompts/hardening/hardening-v1.0.md`

### Architecture
- `prompts/architecture/adr-draft-v1.0.md`

### Deployment
- `prompts/deployment/deploy-runbook-v1.0.md`
- `prompts/deployment/incident-response-v1.0.md`

### Merge
- `prompts/merge/merge-conflict-v1.0.md`
- `prompts/merge/post-merge-v1.0.md`

### Release
- `prompts/release/release-readiness-v1.0.md`
- `prompts/release/demo-launch-strategy-v1.0.md`
- `prompts/release/post-merge-validation-general-v1.0.md`

### Stakeholder
- `prompts/stakeholder/status-update-v1.0.md` (now v1.1 content)

### Verification
- `prompts/verification/verification-v1.0.md`

### Triage
- `prompts/triage/out-of-scope-v1.0.md`
