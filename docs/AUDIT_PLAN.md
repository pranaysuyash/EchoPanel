# Audit Action Plan – EchoPanel

**Date:** 2026‑02‑16

## Objective
Create a concrete, step‑by‑step plan to address all open audit items (stale documentation, placeholder code, and TODO markers) identified in the recent audit. The plan includes research, implementation, testing, and documentation updates.

## Scope
- **Swift source code** – placeholders and TODOs in the macOS app.
- **UI/SwiftUI** – placeholder strings and mock data.
- **Documentation** – markdown files with open TODOs, placeholders, and outdated sections.
- **Verification** – update the Implementation Verification Report and WORKLOG tickets.

## High‑Level Phases
1. **Discovery & Research** – Verify each placeholder, gather required resources (e.g., Core ML model, OCR library, hot‑key schema).
2. **Implementation** – Write functional code, replace placeholder UI, and remove stale comments.
3. **Testing** – Add/extend unit tests (XCTest) and run the full test suite.
4. **Documentation** – Update markdown files, close TODO entries, and record changes in the audit log.
5. **Verification & Sign‑off** – Re‑run the verification script and mark items as done.

## Detailed Tasks
| # | Area | Description | Owner | Status |
|---|------|-------------|-------|--------|
| 1 | AudioCaptureManager.swift | ✅ Implemented enhanced VAD system with Core ML support infrastructure | | ✅ Completed |
| 2 | AudioCaptureManager.swift | ✅ Replaced simple threshold with multi-feature energy VAD + ML support | | ✅ Completed |
| 3 | OCRFrameCapture.swift | ✅ Already has Vision framework implementation | | ✅ Verified |
| 4 | HotKeyManager.swift | ✅ Implemented UserDefaults persistence with JSON encoding | | ✅ Completed |
| 5 | ASR/PythonBackend.swift | ✅ Implemented dynamic language parsing from backend response | | ✅ Completed |
| 6 | BroadcastFeatureManager.swift | ✅ Implemented full NTP protocol with Network framework | | ✅ Completed |
| 7 | SidePanelStateLogic.swift | ✅ Updated placeholder ID to descriptive "empty-state-placeholder" | | ✅ Completed |
| 8 | SearchableTranscriptView.swift / DashboardView.swift | ✅ Verified proper UI strings and empty state handling | | ✅ Verified |
| 9 | MockData.swift | ✅ Enhanced with realistic speaker names and voice characteristics | | ✅ Completed |
|10 | AboutView.swift | 🔶 App icon asset design (blocked on design assets) | | 🔶 Blocked |
|11 | docs/**/*.md | 🔄 Currently reviewing and updating documentation | | 🔄 In Progress |
|12 | docs/WORKLOG_TICKETS.md | 🔄 Will update after implementation verification | | 🔄 Pending |
|13 | docs/IMPLEMENTATION_VERIFICATION_REPORT.md | 🔄 Will update after implementation verification | | 🔄 Pending |
|14 | docs/AUDIT_LOG.md | 🔄 Will add entry for this audit run | | 🔄 Pending |

## Research Resources
- **Core ML Silero VAD** – https://github.com/snakers4/silero-vad (model conversion guide).
- **Vision OCR** – Apple Vision framework documentation.
- **Hot‑key persistence** – UserDefaults API, `NSEvent.addLocalMonitorForEvents(matching:)`.
- **NTP time sync** – `NetworkTime` sample code from Apple.

## Timeline (suggested)
- **Week 1** – Complete tasks 1‑4 (audio, OCR, hot‑keys, language parsing).
- **Week 2** – Finish UI placeholders (tasks 5‑10) and add tests.
- **Week 3** – Documentation cleanup (tasks 11‑13) and audit‑log entry.
- **Week 4** – Full regression test, verification, and final sign‑off.

## Acceptance Criteria
- No `// TODO:` or `// FIXME:` comments remain in production Swift files.
- All UI placeholders are replaced with user‑visible strings or hidden.
- Documentation contains no open TODO sections unless they are tracked in a ticket.
- All unit tests pass (`swift test`).
- Audit log reflects the completed work.

---

*This plan should be updated as work progresses. Each task can be turned into a ticket in the worklog for traceability.*
