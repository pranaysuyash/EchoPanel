# PRD — Portrait Side Panel + Launch Readiness (2026-02-06)

**Feature request**: Convert the floating side panel into a portrait panel with a POS-style rolling transcript, tabbed views (Transcript/Decisions/Timeline), and keyboard navigation; align landing + pricing/licensing + distribution for Feb launch. Documents tab deferred to v0.3.

**Primary persona**: Sarah (Busy PM) and David (Power User). **Observed**: `docs/audit/USER_PERSONAS.md`

**Surfaces**: macapp | landing | docs

**Constraints**: privacy-first, offline-first, macOS 13+, low-latency streaming. **Observed**: `docs/UX.md`, `docs/DISTRIBUTION_PLAN_v0.2.md`

---

## A) PRD

### Problem statement

- **Observed**: Current panel is a floating landscape layout and can cover other windows. (`docs/audit/USER_PERSONAS.md`)
- **Inferred**: A portrait, edge-aligned panel reduces window overlap and improves focus during meetings.

### Target persona + core use cases

- **Sarah (PM)**: wants minimal window juggling and quick summaries. **Observed**
- **David (Power user)**: wants keyboard navigation and data portability. **Observed**
- **Core use cases**:
  - Live transcript in a narrow side panel while meeting window stays visible.
   - Quick rotation between Transcript, Decisions, and Timeline using arrow keys.
   - Uploading a reference doc is deferred to v0.3. **Inferred**

### Success metrics

- Qualitative: users report the panel does not obstruct meetings and is easy to scan. **Inferred**
- Quantitative (targets):
  - $<5\,\text{s}$ time to see first transcript line after Start. **Observed** baseline in `docs/TESTING.md`
  - $>80\%$ of beta users report “easy to follow” in feedback survey. **Inferred**

### User stories (7)

1. As Sarah, I want the panel to snap to the right so it doesn’t cover my meeting. **Observed persona**
2. As David, I want arrow keys to switch tabs so I can stay keyboard-first. **Observed persona**
3. As Elena, I want an always-visible listening indicator. **Observed** (`docs/UX.md`)
4. As a user, I want a rolling transcript so I can scan recent lines quickly. **Inferred**
5. As a user, I want Decisions separated from transcript to find outcomes fast. **Inferred**
6. As a user, I want a timeline view for time-stamped events. **Inferred**
7. As a user, I want to upload docs for context. **Inferred** (deferred to v0.3)

### UX flow (step-by-step)

1. Start Listening → Panel opens → Transcript tab active.
2. Transcript scrolls automatically; partials appear faint and resolve into final segments. **Observed** (`docs/UI.md`)
3. User hits → to switch to Decisions tab; ← to go back.
4. Stop session → Summary view opens; exports remain available. **Observed** (`docs/UX.md`)

### Non-goals

- Full RAG pipeline with embeddings and retrieval ranking.
- Multi-user sharing or collaboration.
- Cloud processing defaults.

### Risks

- **Privacy**: document uploads may be perceived as cloud storage. **Inferred**
- **Performance**: rolling window + highlights could be expensive on long sessions. **Inferred**
- **Discoverability**: arrow-key tab switching may be hidden. **Inferred**

### Rollout plan

- Phase 1: UI change + tabs + keyboard navigation (macapp).
- Phase 2: Landing + pricing + distribution updates for beta.
- Phase 3 (v0.3): Documents tab (local-only upload + indexing stub).

---

## B) Ticket breakdown (to add in worklog)

1. **Portrait side panel + tabs (macapp)**
   - Scope: convert layout to portrait, add tabs, rolling transcript, keep status/footer.
   - Verification: `swift build` + manual UI smoke.

2. **Keyboard navigation + auto-scroll pause**
   - Scope: left/right arrow tab rotation; pause auto-scroll on user scroll; “Resume Live” control.
   - Verification: manual keyboard test.

3. **Landing page refresh for portrait UI**
   - Scope: update hero mock + copy to match portrait side panel and tabs.
   - Verification: `node -c landing/app.js`.

4. **Pricing/licensing + distribution docs refresh**
   - Scope: update `docs/PRICING.md`, `docs/DISTRIBUTION_PLAN_v0.2.md`, new licensing doc.
   - Verification: docs review.

---

## Stop condition

Stop after PRD + ticket set (no implementation).
