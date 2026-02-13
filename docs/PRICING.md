# Pricing Strategy (v1.0 - Local-First Single-User App)

**Last Updated**: 2026-02-12
**Product Type**: Local-first macOS app (single-user)
**Distribution**: Direct download + Mac App Store

---

## Goals

- Clear, simple pricing with a fast path to purchase.
- Align with productivity tools for solo founders and small teams.
- Maximize revenue while respecting local-first architecture.
- **No free tier** - all features require purchase.
- No multi-user authentication required for MVP.

---

## Monetization Strategy (Decision: 2026-02-12)

### Primary: Mac App Store Subscriptions (Already Implemented via StoreKit 2)

| Tier | Price | Target |
|------|-------|--------|
| Monthly | $12/month | Low-commitment users |
| Annual | $99/year | Committed users (2 months free) |

**Why App Store**:
- Built-in trust and discoverability
- Easy payment and receipt validation
- Automatic subscription management
- Apple handles refunds and disputes

### Secondary: Direct Sales via LemonSqueezy/Paddle (Future)

| Tier | Price | Target |
|------|-------|--------|
| Lifetime | $199 | Power users who hate subscriptions |
| Annual | $79/year | Discounted vs App Store |

**Why Direct Sales**:
- Lower fees (3-5% vs Apples 15-30%)
- No App Store restrictions on local-first features
- Lifetime option appeals to power users
- Alternative for users who avoid subscriptions

### NOT Using: Gumroad

**Reason**: Removed from consideration (2026-02-12)
- Higher fees than LemonSqueezy/Paddle
- Less developer-friendly API
- Not optimized for software sales

---

## Tiers

### Pro (Paid)

**Status**: ✅ Implemented (TCK-20260212-004)

**Features** (all require purchase):
- Unlimited sessions.
- All ASR models.
- Advanced diarization enabled by default.
- All export formats (JSON, Markdown, Bundle).
- Unlimited session history.
- Unlimited RAG documents.
- Priority support.

**Technical Implementation**:
- Monthly and Annual subscription tiers. **Observed**: `SubscriptionManager.swift` - SubscriptionTier enum
- StoreKit 2 in-app purchases. **Observed**: `SubscriptionManager.swift` - StoreKit integration
- Receipt validation with Apple servers. **Observed**: `ReceiptValidator.swift` - Transaction.currentEntitlements
- Restore Purchases functionality. **Observed**: `SubscriptionManager.swift` - restorePurchases()
- Upgrade prompts in UI. **Observed**: `UpgradePromptView.swift` - UpgradePromptView struct

**Note**: No free tier - all users must purchase to access features.

### Free Beta (Removed)

**Status**: ❌ Removed from strategy (2026-02-12)

**Reason**: User preference - no free tier
- All features require purchase
- Invite code system removed
- Focus on paid conversions from launch

**Alternative**: Direct download with purchase wall

---

## Feature Gating Matrix

| Feature | Not Purchased | Pro |
|---------|---------------|-----|
| (No free tier) | - | - |
| Sessions/month | ❌ Blocked | ✅ Unlimited |
| ASR Models | ❌ Blocked | ✅ All models |
| Diarization | ❌ Blocked | ✅ Enabled |
| Export formats | ❌ Blocked | ✅ All formats |
| Session history | ❌ Blocked | ✅ Unlimited |
| RAG documents | ❌ Blocked | ✅ Unlimited |
| Priority support | ❌ Blocked | ✅ Yes |

**Note**: No free tier - all features blocked until purchase.

---

## Usage Limits (MON-004)

**Status**: ⏸️ Deferred (2026-02-12)

**Reason**: No free tier means no usage limits needed
- All users are paying customers
- No restrictions on usage
- Focus on feature value, not restrictions

**Reference**: User decision - no free tier

---

## Revenue Projections (Estimates)

| Scenario | Monthly Users | Conversion | ARPU | Monthly Revenue |
|---------|--------------|-----------|------|-----------------|
| Conservative | 1,000 | 5% | $12 | $6,000 |
| Moderate | 5,000 | 8% | $12 | $48,000 |
| Optimistic | 20,000 | 10% | $12 | $240,000 |

**Note**: These are estimates for planning purposes only.

---

## Whats NOT Implemented (And Why)

### License Key Validation (MON-003)

**Status**: Removed from Phase 1 (2026-02-12)

**Reason**: Gumroad removed from monetization strategy
- No direct sales via Gumroad planned
- App Store handles primary monetization
- Can be added later if direct sales resume

### User Authentication (AUTH-001 to AUTH-004)

**Status**: Deferred until multi-user/cloud sync validated

**Reason**: Single-user local-first app
- No account system required for MVP
- Focus on core product instead of authentication
- Add when/if multi-device sync or team features needed

### Sync for Transcripts

**Status**: Future consideration, not priority

**Reason**: Local-first architecture
- Core value: local processing, no cloud dependency
- Sync can be added later as premium feature
- Consider: iCloud sync (native, Apples ecosystem)

---

## Implementation Priority

| Priority | Ticket | Feature | Effort | Status |
|----------|--------|---------|--------|--------|
| P0 | TCK-20260212-004 | Pro Subscription | 4-6 weeks | ✅ DONE |
| P1 | TCK-20260212-00X | License Keys | 2-3 weeks | ⏸️ Deferred |
| P2 | Future | Direct Sales | 2-3 weeks | Future |
| P2 | Future | Sync (iCloud) | 4-6 weeks | Future |

**Note**: No free tier means Free Beta and Usage Limits tickets are removed.

---

## Distribution Strategy

### Phase 1: Private Beta (Current)
- Invite-only via email
- Trial access with purchase wall
- Gather feedback, validate product-market fit

### Phase 2: Public Beta
- Open download on website
- Purchase required for all features
- Conversion via App Store or direct

### Phase 3: Launch
- Mac App Store submission
- Direct website sales (LemonSqueezy/Paddle)
- Press outreach, product hunt launch

---

## Open Questions (Resolved)

| Question | Decision | Date |
|---------|----------|------|
| Multi-user authentication? | No - single-user only | 2026-02-12 |
| Gumroad for direct sales? | No - using App Store + direct | 2026-02-12 |
| License key validation? | Deferred - not needed | 2026-02-12 |
| Cloud sync MVP? | No - local-first priority | 2026-02-12 |
| AUTH flows in Phase 1? | Deferred | 2026-02-12 |

---

## References

- Implementation: `docs/IMPLEMENTATION_ROADMAP_v1.0.md`
- Feature list: `docs/FEATURES.md`
- Distribution: `docs/DISTRIBUTION_PLAN_v0.2.md`
- Launch planning: `docs/LAUNCH_PLANNING.md`
