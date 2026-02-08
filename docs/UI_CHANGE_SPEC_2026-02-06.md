# UI Change Spec — Portrait Side Panel + Rolling Window (2026-02-06)

**Goal**: Specify a non-trivial UI change with enough detail to implement without scope drift.

---

## Inputs

- Feature goal (user-facing): Portrait side panel with POS-style rolling window and tabbed views for Transcript, Decisions, and Timeline (Documents tab deferred to v0.3).
- Target screen(s): Side Panel (macapp) + Landing
- Constraints: macOS 13+, low latency streaming, offline-first, privacy-first
- Behavior change allowed: YES

---

## 1) Problem statement

- **Who is the user?**
  - **Observed**: Personas include Sarah (busy PM), David (power user), Elena (privacy advocate). (`docs/audit/USER_PERSONAS.md`)
- **What pain are we fixing?**
  - **Observed**: The floating side panel is landscape, can cover meetings and cause window juggling. (`docs/audit/USER_PERSONAS.md`)
  - **Inferred**: A portrait side panel that docks to the screen edge reduces window overlap and attention switching.
- **What does success look like?**
  - **Inferred**: The live transcript and decisions are readable in a portrait layout, and users can quickly rotate views with keyboard arrows.

## 2) User stories

1. As **Sarah (PM)**, I want a side panel that doesn’t cover my Zoom window so that I can keep focus. (**Observed persona**)
2. As **David (power user)**, I want arrow-key tab rotation so that I can stay keyboard-first. (**Observed persona**)
3. As **Elena (privacy advocate)**, I want a clear visible listening state at all times so that I can trust the app. (**Observed UX requirement**: `docs/UX.md`)
4. As a user, I want a POS-style rolling transcript so that I can scan recent lines quickly. (**Inferred**)
5. As a user, I want entities highlighted with context so that I understand why they matter. (**Inferred**)
6. As a user, I want a Documents tab for RAG uploads so that I can bring context into the meeting. (**Inferred**, deferred to v0.3)

## 3) UX flow (steps + states)

1. **Start listening**
   - Empty: Panel opens with tabs; Transcript tab active.
   - Loading: Status shows “Connecting…”
   - Success: “Streaming · Audio: Good/OK/Poor”
   - Error: “Not ready” with guidance
2. **Live transcript**
   - Success: Rolling window updates every new segment; partials are faint.
   - Disabled: No audio → banner “No audio detected”
3. **Tab rotation (Left/Right arrows)**
  - Success: Transcript → Decisions → Timeline → Transcript
   - Disabled: When text field focused, arrow keys move cursor instead
4. **Documents upload**
  - Deferred to v0.3 (not shown in v0.2 UI)

## 4) UI changes (per screen)

### Side Panel

- **Changes**:
  - Layout switches to portrait (target width ~30% of screen, full height). **Inferred**
  - Tabs replace the 3-column layout: Transcript, Decisions, Timeline. **Inferred**
  - POS-style rolling window (cap last 12–20 transcript segments). **Inferred**
  - NER highlights toggle and inline highlighting when Entities context is visible. **Inferred**
- **What stays the same**:
  - Status line (Streaming/Reconnecting/Not ready) and audio quality badge. **Observed** (`docs/UX.md`)
  - Footer actions (Copy Markdown, Export JSON, End session). **Observed** (`docs/UI.md`)
- **Keyboard/accessibility**:
  - Left/Right arrows rotate tabs; visible hint “← → to switch tabs”. **Inferred**
  - VoiceOver should announce tab changes and status line. **Unknown** (needs implementation validation)

### Landing page

- **Changes**:
  - Hero mock updated to portrait side panel with tabs and rolling transcript. **Inferred**
  - Copy updated to describe tabbed views; Documents called out as “coming soon”. **Inferred**
- **What stays the same**:
  - Waitlist CTA and privacy positioning. **Observed** (`landing/index.html`)

## 5) Error/empty/loading states (explicit)

- **Not ready**: “Backend not ready. Start the server or try again.” (existing pattern) **Observed** (`docs/UX.md`)
- **No audio**: “No audio detected. Check meeting audio or source selection.” **Observed** (`docs/UX.md` + QA checklist)
- **Docs upload failed**: Deferred (feature not in v0.2). **Inferred**
- **Entities empty**: “No entities detected yet.” **Inferred**

## 6) Diagnostics/supportability

- Logs should include tab changes, doc upload errors, and auto-scroll pause/resume. **Inferred**
- Diagnostics access: keep existing “Diagnostics” action in Summary view. **Observed** (`docs/WORKLOG_TICKETS.md` references diagnostics path)

## 7) Acceptance criteria + verification plan

- [ ] Portrait side panel opens at ~30% width and full height.
- [ ] Transcript tab shows rolling window with last 12–20 segments and auto-scrolls.
- [ ] Left/Right arrow keys rotate tabs without mouse.
- [ ] Decisions tab shows decisions with timestamps.
- [ ] Timeline tab shows timestamped items.
- [ ] Status line + audio quality remain visible on all tabs.
- [ ] Copy Markdown / Export JSON / End session remain in footer.
- [ ] Landing page hero reflects the portrait panel.

**Verification (manual + build):**

- `cd macapp/MeetingListenerApp && swift build`
- `node -c landing/app.js`

---

## Stop condition

Stop after the spec (no implementation).
