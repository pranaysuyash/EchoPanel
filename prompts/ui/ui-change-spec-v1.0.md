# UI Change Spec (EchoPanel) — v1.0

**Goal**: Specify a non-trivial UI change with enough detail to implement without scope drift.

---

## Inputs
- Feature goal (user-facing): `<one sentence>`
- Target screen(s): `<Onboarding / Side Panel / Summary / History / Settings / Diagnostics / Landing>`
- Constraints: `<macOS version, performance, privacy, offline>`
- Behavior change allowed: `YES/NO/UNKNOWN`

---

## Output (required)

### 1) Problem statement
- Who is the user?
- What pain are we fixing?
- What does success look like?

### 2) User stories (5–10)
- As a `<persona>`, I want `<goal>` so that `<benefit>`.

### 3) UX flow (steps + states)
For each step, list states:
- Empty / Loading / Success / Error / Disabled (as applicable)

### 4) UI changes (per screen)
For each screen:
- What changes visually/interaction-wise
- What stays the same (to reduce scope)
- Keyboard/accessibility expectations

### 5) Error/empty/loading states (explicit)
Define:
- copy/messaging
- recovery actions (what the user can do next)

### 6) Diagnostics/supportability
- What logs/exports help debug user reports?
- How does the user reach Diagnostics from the failure state?

### 7) Acceptance criteria + verification plan
- 5–12 checkboxes
- Commands to run (swift build/tests)
- Manual smoke steps

---

## Stop condition
Stop after the spec (do not implement).
