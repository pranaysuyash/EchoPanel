# Pricing (v0.2 draft)

## Goals

- Clear, simple pricing with a fast path to purchase.
- Align with productivity tools for solo founders and small teams.
- Keep beta access frictionless while validating demand.

## Proposed tiers

### Free Beta (Invite-only)

- Limited sessions per month (20 sessions/month). **Observed**: `macapp/MeetingListenerApp/Sources/BetaGatingManager.swift` - sessionLimit = 20
- Invite code validation required. **Observed**: `macapp/MeetingListenerApp/Sources/BetaGatingManager.swift` - validateInviteCode()
- Basic transcript + cards (Actions/Decisions/Risks/Entities). **Observed**: current features in `docs/FEATURES.md`
- Export Markdown + JSON. **Observed**: `docs/FEATURES.md`
- Local-only processing by default. **Observed**: distribution plan emphasizes local bundle (`docs/DISTRIBUTION_PLAN_v0.2.md`)
- Admin tool for invite code generation. **Observed**: `scripts/generate_invite_code.py` - generate, batch, use, list, export commands
- Audit logging for invite code usage. **Observed**: `scripts/generate_invite_code.py` - audit_log tracking generation and usage

### Pro (Paid)

- Unlimited sessions.
- Higher limits (longer sessions, more frequent updates). **Inferred**
- Priority support.
- Optional cloud summary/analysis add-on (if introduced). **Inferred**

## Pricing recommendation (needs confirmation)

- **Feb beta default**: Free beta only (invite-only). **Inferred**
- **Pro range (post-beta)**: $12–$20 per device / month. **Inferred** (benchmark vs productivity tools)
- **Alternate**: $99/year per device with early adopter discount. **Inferred**

## Licensing & access

- **Private beta**: invite-only access with email gating. **Observed**: `docs/LAUNCH_PLANNING.md`
- **Paid access**: Gumroad license keys and email fulfillment. **Observed**: `docs/DISTRIBUTION_PLAN_v0.2.md`

## Open questions

- Per-seat vs per-device licensing.
- Metering for longer sessions.
- Whether cloud features are included or sold as add-on.
