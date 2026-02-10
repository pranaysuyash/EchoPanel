# skills.sh — Relevant Agent Skills for EchoPanel

Source: https://skills.sh  
Skills are Claude Code agent skills that can be installed to enhance AI-assisted development workflows.

---

## How to install

```bash
claude skill install <source>/<skillId>
# e.g.
claude skill install avdlee/swiftui-agent-skill/swiftui-expert-skill
```

---

## Tier 1 — Directly applicable to EchoPanel

### macOS / Swift (macapp)

| Installs | Skill | Use case |
|----------|-------|----------|
| 3,107 | `avdlee/swiftui-agent-skill/swiftui-expert-skill` | SwiftUI patterns for the side panel and menu bar UI |
| 1,308 | `avdlee/swift-concurrency-agent-skill/swift-concurrency` | async/await, actors for audio capture + WebSocket streaming |
| 802 | `dimillian/skills/swiftui-liquid-glass` | Modern macOS visual effects (if targeting macOS 26+) |
| 770 | `dimillian/skills/swiftui-ui-patterns` | Reusable SwiftUI patterns (tabs, cards, lists) |
| 561 | `dimillian/skills/swiftui-performance-audit` | Profile and optimize the side panel rendering |
| 469 | `dimillian/skills/swiftui-view-refactor` | Clean up growing view files in MeetingListenerApp |

### Python / FastAPI (server)

| Installs | Skill | Use case |
|----------|-------|----------|
| 2,335 | `wshobson/agents/fastapi-templates` | Endpoint scaffolding for new API routes |
| 2,084 | `wshobson/agents/async-python-patterns` | async patterns for WebSocket + ASR streaming |
| 2,417 | `wshobson/agents/python-testing-patterns` | pytest patterns for server tests |
| 3,060 | `wshobson/agents/python-performance-optimization` | Optimize audio processing / NLP pipeline |
| 919 | `wshobson/agents/python-design-patterns` | Architecture patterns for server modules |
| 794 | `wshobson/agents/python-code-style` | Consistent style across server codebase |
| 733 | `wshobson/agents/python-error-handling` | Robust error handling in streaming paths |
| 683 | `wshobson/agents/python-type-safety` | Type annotations and mypy compliance |
| 665 | `wshobson/agents/python-configuration` | Config management (.env, settings) |
| 656 | `wshobson/agents/python-observability` | Logging and monitoring for the server |
| 642 | `wshobson/agents/python-background-jobs` | Background task patterns (analysis cadence) |
| 637 | `wshobson/agents/python-resilience` | Retry, circuit breaker for external API calls |
| 631 | `wshobson/agents/python-resource-management` | Resource cleanup for audio streams |
| 758 | `wshobson/agents/python-project-structure` | Project layout best practices |
| 491 | `jezweb/claude-skills/fastapi` | FastAPI-specific patterns and middleware |
| 424 | `jeffallan/claude-skills/fastapi-expert` | Advanced FastAPI (dependencies, lifespan) |

### Landing page

| Installs | Skill | Use case |
|----------|-------|----------|
| 84,243 | `vercel-labs/agent-skills/web-design-guidelines` | Design system and layout best practices |
| 53,851 | `anthropics/skills/frontend-design` | Frontend design patterns |
| 19,162 | `nextlevelbuilder/ui-ux-pro-max-skill/ui-ux-pro-max` | UI/UX polish and refinement |
| 1,237 | `ibelick/ui-skills/fixing-motion-performance` | Optimize anime.js and CSS animations |
| 531 | `addyosmani/web-quality-skills/core-web-vitals` | CWV audit for landing page speed |
| 818 | `addyosmani/web-quality-skills/performance` | General web performance |
| 676 | `addyosmani/web-quality-skills/seo` | SEO for echopanel.studio |
| 423 | `jezweb/claude-skills/seo-meta` | Meta tags, Open Graph, structured data |

---

## Tier 2 — Useful for project-wide workflows

### Security & auditing

| Installs | Skill | Use case |
|----------|-------|----------|
| 15,757 | `squirrelscan/skills/audit-website` | Security audit of landing page |
| 1,243 | `wshobson/agents/security-requirement-extraction` | Extract security requirements from specs |
| 1,027 | `sickn33/antigravity-awesome-skills/security-review` | Code security review |
| 692 | `sickn33/antigravity-awesome-skills/api-security-best-practices` | API endpoint hardening |
| 419 | `trailofbits/skills/audit-context-building` | Prepare codebase for security audit |

### Accessibility

| Installs | Skill | Use case |
|----------|-------|----------|
| 1,606 | `wshobson/agents/accessibility-compliance` | WCAG compliance for landing + app |
| 1,264 | `wshobson/agents/wcag-audit-patterns` | Detailed WCAG audit workflows |
| 1,169 | `ibelick/ui-skills/fixing-accessibility` | Fix a11y issues in UI |
| 627 | `addyosmani/web-quality-skills/accessibility` | Web accessibility best practices |

### Marketing & growth

| Installs | Skill | Use case |
|----------|-------|----------|
| 15,219 | `coreyhaines31/marketingskills/seo-audit` | SEO audit for echopanel.studio |
| 10,780 | `coreyhaines31/marketingskills/copywriting` | Landing page copy improvement |
| 8,272 | `coreyhaines31/marketingskills/marketing-psychology` | CTA and conversion optimization |
| 1,228 | `wshobson/agents/competitive-landscape` | Competitive analysis (Otter, Fireflies, etc.) |
| 1,280 | `wshobson/agents/startup-financial-modeling` | Financial modeling for EchoPanel |
| 1,224 | `wshobson/agents/startup-metrics-framework` | Define and track product metrics |

### Code quality

| Installs | Skill | Use case |
|----------|-------|----------|
| 1,246 | `sickn33/antigravity-awesome-skills/clean-code` | General clean code patterns |
| 1,217 | `boristane/agent-skills/logging-best-practices` | Structured logging for server |
| 493 | `addyosmani/web-quality-skills/web-quality-audit` | Full web quality audit |

---

## Recommended install order

For immediate EchoPanel development:

1. `avdlee/swift-concurrency-agent-skill/swift-concurrency` — audio streaming is core
2. `wshobson/agents/fastapi-templates` — server endpoint scaffolding
3. `wshobson/agents/async-python-patterns` — WebSocket streaming patterns
4. `avdlee/swiftui-agent-skill/swiftui-expert-skill` — side panel UI
5. `addyosmani/web-quality-skills/core-web-vitals` — landing page speed

For landing page refresh (per LANDING_INSPIRATION.md):

1. `vercel-labs/agent-skills/web-design-guidelines`
2. `ibelick/ui-skills/fixing-motion-performance`
3. `coreyhaines31/marketingskills/copywriting`
4. `coreyhaines31/marketingskills/seo-audit`
