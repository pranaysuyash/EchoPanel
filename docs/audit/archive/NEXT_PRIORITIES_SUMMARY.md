> **📁 ARCHIVED (2026-02-15):** Reference/planning document. Moved to archive.
> Superseded by `docs/WORKLOG_TICKETS.md` and `SENIOR_STAKEHOLDER_RED_TEAM_REVIEW_20260214.md`.

# EchoPanel — Next Agent Review Priorities

**Date:** 2026-02-09  
**Context:** Post-SidePanel remediation, pre-v0.2 launch  
**Status:** SidePanel P0 remediation ✅ COMPLETE

**Update (2026-02-13):** This doc is a historical snapshot from 2026-02-09. The top priorities below were executed and are now tracked as DONE in `docs/WORKLOG_TICKETS.md`:
- Backend hardening follow-ups: `TCK-20260213-016`, `TCK-20260213-022`, `TCK-20260213-024`, `TCK-20260213-025` (see also `docs/audit/BACKEND_HARDENING_AUDIT_2026-02-09.md`, `docs/audit/BACKEND_HARDENING_VERIFICATION_2026-02-09.md`)
- Accessibility deep pass: `TCK-20260213-017` (see also `docs/audit/ACCESSIBILITY_DEEP_PASS_2026-02-09.md`)
- Performance quick win: `TCK-20260213-014` (LazyVStack transcript rows). A full profiling/baseline pass is still not captured as a dedicated ticket.
- Test stability: `TCK-20260213-028` (visual snapshot tests opt-in to keep `swift test` stable by default)

---

## Current State (Validated)

### Completed: SidePanel P0 Remediation (TCK-20260209-002) ✅

| Item | Before | After | Status |
|------|--------|-------|--------|
| SidePanelView.swift | 2,738 lines | 271 lines | ✅ 90% reduction |
| Test coverage | 7 tests | 11 tests | ✅ +4 dark mode snapshots |
| Build | — | Clean | ✅ 0 warnings |
| VoiceOver | None | Implemented | ✅ Entity highlights accessible |
| Color contrast | Unverified | Verified | ✅ "Needs review" badge compliant |

**Files created:** 8 new files in `SidePanel/{Roll,Compact,Full,Shared}/`

---

## Recommended Review Order

### Priority 1: Backend Hardening (P0/P1) ✅ DONE (2026-02-13)
**Ticket:** TCK-20260209-003 (historical) + follow-ups: `TCK-20260213-016`, `TCK-20260213-022`, `TCK-20260213-024`, `TCK-20260213-025`

**Why first:** Backend reliability is a launch blocker. Users will blame the app if transcription fails silently.

**Scope:**
- WebSocket retry/backoff logic
- Backend crash recovery
- Port conflict handling
- Log redaction (PII removal)
- Secret handling (Keychain assessment)
- Zombie process prevention

**Deliverable:** Hardening report + fixes

**Files to review:**
- `server/api/ws_live_listener.py`
- `macapp/MeetingListenerApp/Sources/BackendManager.swift`
- `macapp/MeetingListenerApp/Sources/WebSocketStreamer.swift`
- `macapp/MeetingListenerApp/Sources/SessionStore.swift`

---

### Priority 2: Performance Review (P1)
**Ticket:** (To be created from findings)

**Why second:** Long meeting sessions (1hr+) will expose performance issues.

**Scope:**
- `filteredSegments` recomputation (currently computed on every view access)
- `decisionBeadPositions` O(n²) search
- Transcript rendering with 500+ segments
- Memory usage during 2+ hour sessions

**Deliverable:** Measured baseline + optimization patch

**Files to review:**
- `SidePanel/Shared/SidePanelStateLogic.swift` (line 85-104)
- `SidePanel/Shared/SidePanelStateLogic.swift` (line 242-255)

---

### Priority 3: Accessibility Deep Pass (P1) ✅ DONE (2026-02-13)
**Ticket:** `TCK-20260213-017` (follow-up to `docs/audit/ACCESSIBILITY_DEEP_PASS_2026-02-09.md`)

**Why third:** Current a11y is "implemented" but not validated with real VoiceOver workflows.

**Scope:**
- Rotor navigation for transcript
- Focus order validation
- Keyboard-only flows (no mouse)
- Live update announcements
- Real VoiceOver testing (not just code review)

**Deliverable:** a11y bug list with VoiceOver repro steps

**Files to review:**
- `SidePanel/Shared/SidePanelSupportViews.swift` (accessibility implementations)
- `SidePanel/Shared/SidePanelTranscriptSurfaces.swift`

---

### Priority 4: Design Polish (P2)
**Ticket:** (To be created from findings)

**Why last:** Visual polish is important but not a launch blocker.

**Scope:**
- SidePanelSupportViews.swift organization (452 lines)
- SidePanelTranscriptSurfaces.swift clarity (427 lines)
- Full mode information density
- Session rail readability

**Deliverable:** Small UX polish patches (not redesign)

---

## Agent Handoff Notes

### What the Previous Agent Did Well
- SidePanelView decomposition followed recommended structure
- Added bonus dark mode snapshot tests
- Implemented VoiceOver accessibility for entity highlights
- Verified color contrast for confidence badges
- All tests pass (11/11), zero warnings

### Known Issues to Carry Forward
1. **Two view files slightly large:**
   - SidePanelSupportViews.swift: 452 lines (target: <400)
   - SidePanelTranscriptSurfaces.swift: 427 lines (target: <400)
   - *Note: Acceptable for now, revisit in Priority 4*

2. **Performance debt:**
   - `filteredSegments` recomputes on every access
   - `decisionBeadPositions` has O(n²) search
   - *Note: Address in Priority 2*

3. **Backend reliability unknowns (historical):**
   - This was addressed post-2026-02-09; see Priority 1 follow-up tickets in `docs/WORKLOG_TICKETS.md`.

---

## Quick Start for Next Agent

### If you're working on Priority 1 (Backend Hardening):
```bash
# Start here
cd /Users/pranay/Projects/EchoPanel

# Review server architecture
cat server/api/ws_live_listener.py | head -100

# Check backend manager
cat macapp/MeetingListenerApp/Sources/BackendManager.swift | head -100

# Run existing tests
cd macapp/MeetingListenerApp && swift test

# Check server tests
cd /Users/pranay/Projects/EchoPanel
source .venv/bin/activate && pytest tests/ -v
```

### Create evidence log entries:
```markdown
Evidence log:
- [YYYY-MM-DD HH:MM] Finding description | Evidence:
  - Command: `command run`
  - Output:
    ```
    raw output
    ```
  - Interpretation: Observed/Inferred/Unknown — one sentence
```

---

## Definition of Done (for each priority)

### Backend Hardening (P0/P1)
- [ ] All P0 issues fixed + tests added
- [ ] P1 issues documented with tickets
- [ ] Hardening report created
- [ ] `swift build && swift test` passes
- [ ] Security/privacy risks documented

### Performance Review (P1)
- [ ] Baseline measurements recorded
- [ ] Bottlenecks identified with profiling data
- [ ] Optimizations implemented
- [ ] Before/after timing comparison
- [ ] No regressions in existing tests

### Accessibility Deep Pass (P1)
- [ ] VoiceOver testing completed on real macOS
- [ ] All P1 a11y issues fixed
- [ ] Keyboard-only navigation validated
- [ ] No `accessibility` compiler warnings

### Design Polish (P2)
- [ ] UI changes limited to 2 files (SupportViews, TranscriptSurfaces)
- [ ] Visual changes approved (screenshots)
- [ ] No behavior changes
- [ ] Snapshot tests updated if intentional

---

## Questions?

- **Which priority should I start with?** → Priority 1 (Backend Hardening) unless you have specific expertise elsewhere
- **Updated guidance (2026-02-13):** Start with the currently **OPEN 🔵** tickets in `docs/WORKLOG_TICKETS.md` (this doc is historical).
- **Can I combine priorities?** → No. Each has distinct deliverables and validation criteria
- **What if I find issues outside scope?** → Create new ticket, don't expand scope
- **How do I mark a ticket done?** → Update status to ✅, fill evidence log, update worklog

---

*Generated 2026-02-09 from agent review session*
