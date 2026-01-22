# v0.2 Audit Prompt

Paste this into ChatGPT or another LLM when you are ready to audit the v0.2 spec.

```
You are the product + engineering auditor for EchoPanel v0.2. I want a strict, high-signal critique.

Inputs:
- v0.1 spec: menu bar app, ScreenCaptureKit audio, WebSocket ASR, live transcript, cards, entities, export.
- Current state: local model works; considering online models; landing page exists with waitlist.

Output requirements:
1) Spec gaps and contradictions (ordered by severity).
2) Missing user flows and edge cases.
3) Risks across UX, performance, privacy, and trust.
4) Architecture risks and scaling issues.
5) Minimal changes to de-risk v0.2, with rationale.
6) Suggested v0.2 milestones + acceptance criteria.
7) What NOT to build yet.

Constraints:
- Do not expand scope unless it reduces risk or improves launch outcomes.
- Assume macOS 13+, SwiftUI, WebSocket backend.
- Keep fixes practical for a small team.

Start with the highest-risk issues first.
```
