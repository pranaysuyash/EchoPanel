# UI/UX + Design Audit (EchoPanel) — v1.0

**Goal**: Legacy UI/UX audit prompt. Prefer `prompts/ui/ui-ux-design-audit-v1.1.0.md` for strict report structure + screenshot indexing.

Use v1.0 only for a quick pass, but keep the same evidence discipline and ticketing requirements.

## Personas (EchoPanel)
Pick 1–2 primary personas for the audit and state them explicitly in the audit artifact.

Recommended set:
- **Founder/PM (back-to-back calls):** needs “instant notes”, fast export, low setup friction.
- **Engineer/Tech Lead:** cares about accuracy, references, actionability, and speed.
- **Recruiter:** needs clear action items, names, and follow-ups; lightweight sharing.
- **Sales/CS:** needs crisp summary + next steps; high trust and low distraction.
- **Privacy-conscious user:** wants transparent consent, local processing, and clear “listening” indicators.

## Scope contract (required)
Define:
- In-scope screens/flows
- Out-of-scope
- Behavior change allowed (YES/NO)

## Checklist

### First-run onboarding
- Clear “what/why” + steps
- Permission explanations match actual OS prompts
- Recovery path if permission is denied

### During session (side panel)
- Visible listening indicator
- Streaming / reconnect / offline states are clear
- Transcript stays readable at scale (scrolling, follow mode)

### Stop → summary → export
- Finalization is reliable (no silent loss)
- Summary is shareable and readable
- Export paths are obvious and safe

### Landing page
- Clear CTA and trust section
- Keyboard focus styles
- Form error/success messaging

## Required outputs
- Audit: `docs/audit/ui-ux-<YYYYMMDD>.md`
- Tickets for each actionable P0/P1 item
