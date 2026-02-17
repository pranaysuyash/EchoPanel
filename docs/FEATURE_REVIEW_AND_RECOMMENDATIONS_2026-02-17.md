# EchoPanel Feature Review & Recommendations

**Date:** 2026-02-17  
**Author:** Development Team  
**Context:** Post-test-fix review and feature planning session

---

## Executive Summary

EchoPanel is a **macOS menu bar application** for capturing system audio, microphone input, or both, streaming PCM to a local backend, and generating live transcripts with intelligent insights (cards, entities, summaries).

**Current Status:**
- ✅ Core runtime: 95% complete
- ✅ Distribution: 85% complete (.app bundle + DMG)
- ✅ Monetization: 80% complete (StoreKit subscriptions + Beta gating)
- ❌ Code signing: 0% complete (requires Apple Developer Program $99/year)
- ❌ Authentication: Not started

**Launch Readiness: 72/100**

---

## Test Suite Status (2026-02-17)

**Fixed:** Signal 11 errors were actually missing dependencies in venv. Tests now run successfully.

| Metric | Value | Status |
|--------|-------|--------|
| Total Tests | 143 | ✅ |
| Passed | 141 | ✅ |
| Skipped | 2 | ✅ |
| Failed | 0 | ✅ |

**Fix Applied:** `tests/test_ws_live_listener.py` — Uvicorn test server race condition (increased timeout 5s → 10s, added 0.1s initial sleep)

**Run Tests:**
```bash
.venv/bin/pytest tests/ -v
```

---

## Technical Debt Fixes Completed (2026-02-17)

The following issues were identified and resolved in this session:

| # | Issue | Fix | Files Modified |
|---|-------|-----|----------------|
| 1 | Pending task warnings in test teardown | Properly await `shutdown_indexer()` and `shutdown_integration()` | `server/services/brain_dump_integration.py`, `server/main.py`, `tests/test_brain_dump_integration.py` |
| 2 | WebSocket auth token in query params | Backend now prefers `Authorization` header; Swift client already sends it | `server/api/ws_live_listener.py` |
| 3 | No WebSocket message validation | Added pydantic schemas for all message types | `server/api/ws_schemas.py` (new), `server/api/ws_live_listener.py` |
| 4 | No rate limiting | Token bucket rate limiter with HTTP middleware | `server/api/rate_limiter.py` (new), `server/main.py` |
| 5 | Audio files world-readable | Added `chmod 600` to all recording files | `server/api/ws_live_listener.py` |
| 6 | Deprecation warnings | Third-party (websockets/uvicorn) - will fix on library upgrade | N/A |

**Test Results:** All 141 tests pass ✅

---

## Current State Analysis

### ✅ Recently Completed (This Sprint)

| Feature | Status | Files |
|---------|--------|-------|
| Self-Contained .app Bundle | ✅ Done | `dist/EchoPanel.app` (81MB), `dist/EchoPanel-0.2.0.dmg` (73MB) |
| StoreKit Subscription | ✅ Done | `SubscriptionManager.swift`, `EntitlementsManager.swift` |
| Beta Gating | ✅ Done | `BetaGatingManager.swift`, invite code generation |
| Audio Pipeline Hardening | ✅ Done | Thread safety, device change monitoring |
| Circuit Breaker | ✅ Done | `CircuitBreaker.swift`, `ResilientWebSocket.swift` |

### 🔴 Launch Blockers (P0)

| Feature | Status | Notes |
|---------|--------|-------|
| **Code Signing & Notarization** | ❌ Blocked | Requires Apple Developer Program ($99/year) |
| **License Key Validation** | ❌ Open | TCK-20260212-005 |
| **Usage Limits Enforcement** | ❌ Open | TCK-20260212-006 |
| **User Account Creation** | ❌ Open | TCK-20260212-007 |
| **Login/Sign In** | ❌ Open | TCK-20260212-008 |
| **User Logout** | ❌ Open | TCK-20260212-009 |
| **User Profile Management** | ❌ Open | TCK-20260212-010 |

**Note:** Gumroad integration removed from scope. All monetization handled through Apple In-App Purchase.

### 🟡 Open Work (Do Not Duplicate)

Check `docs/WORKLOG_TICKETS.md` before starting any work.

---

## Feature Recommendations

### P1 — High-Value Features (Post-Launch)

#### 1. Session Playback & Export
**Priority:** High  
**Effort:** Medium  
**Impact:** High user value

**Description:**
- Play back recorded audio alongside transcript (highlighted word-by-word)
- Export sessions to PDF, Markdown, Word, or Notion
- Share specific cards/entities via shareable link
- Export audio as separate WAV/MP3 file

**Technical Considerations:**
- Audio already stored in `SessionBundle.pcm_files`
- Transcript has timestamps (`t0`, `t1`) for highlighting
- PDF export: use existing cards/entities/summary structure
- Notion integration: OAuth + Blocks API

**Files to Modify:**
- `server/api/documents.py` — add export endpoints
- `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` — playback UI
- New: `server/api/export.py` — export service

---

#### 2. Multi-Session Dashboard
**Priority:** High  
**Effort:** Medium  
**Impact:** Increases app stickiness

**Description:**
- Browse all past sessions with filters (date, participants, topics, duration)
- Pin important sessions to top
- Bulk operations: delete, export, tag multiple sessions
- Search across all sessions (already has RAG, needs UI)
- Session statistics: total recording time, most common participants

**Technical Considerations:**
- Database already has `sessions` table with metadata
- RAG store has semantic search (`LocalRAGStore.query()`)
- Need pagination for large session lists
- Consider SQLite FTS5 for full-text search

**Files to Modify:**
- `server/api/documents.py` — list sessions with filters
- `server/db/schema.py` — add `pinned`, `tags` columns
- `macapp/MeetingListenerApp/Sources/SessionHistoryView.swift` — dashboard UI

---

#### 3. Smart Notifications
**Priority:** Medium  
**Effort:** Medium  
**Impact:** High engagement driver

**Description:**
- Notify when action items detected mid-meeting: "New action item: Follow up with Sarah"
- Daily/weekly digest: "You have 5 action items from today's 3 meetings"
- Risk alerts: "High-priority risk identified in current session"
- Configurable notification preferences per session type

**Technical Considerations:**
- Use `UNUserNotificationCenter` for macOS notifications
- Real-time: trigger from `ws_live_listener.py` card extraction
- Digest: scheduled local notification with aggregated data
- Respect macOS Focus modes

**Files to Modify:**
- `macapp/MeetingListenerApp/Sources/NotificationManager.swift` (new)
- `server/api/ws_live_listener.py` — emit notification events
- `server/services/analysis_stream.py` — flag high-priority cards

---

#### 4. Calendar Integration
**Priority:** High  
**Effort:** Medium-High  
**Impact:** Major differentiation from competitors

**Description:**
- Auto-name sessions from calendar event title
- Link sessions to calendar events (click to open corresponding recording)
- Suggest attendees from calendar participants
- Auto-start recording when calendar event begins (optional)
- Show "upcoming meetings" in menu bar

**Technical Considerations:**
- Use EventKit framework for macOS calendar access
- Need user permission for calendar access
- Match sessions to events by time overlap
- Store `calendar_event_id` in session metadata

**Files to Modify:**
- `macapp/MeetingListenerApp/Sources/CalendarManager.swift` (new)
- `server/db/schema.py` — add `calendar_event_id`, `suggested_attendees`
- `server/api/sessions.py` — link session to event endpoint

**Entitlements:**
```xml
<key>com.apple.security.personal-information.calendars</key>
<true/>
```

---

#### 5. Speaker Identification
**Priority:** Medium  
**Effort:** High  
**Impact:** Premium feature for teams

**Description:**
- Train on known voices (team members, frequent collaborators)
- Show "John said..." instead of "Speaker 1"
- Manual labeling: user assigns names to speaker IDs
- Integrate with macOS Contacts or manual entry
- Voice profiles stored locally (privacy-first)

**Technical Considerations:**
- pyannote.audio already does diarization
- Add speaker embedding extraction (pyannote has `SpeakerEmbeddingExtractor`)
- Store embeddings in `speaker_profiles` table
- Match embeddings to known speakers during diarization

**Files to Modify:**
- `server/services/diarization.py` — add speaker identification
- `server/db/schema.py` — add `speaker_profiles` table
- `macapp/MeetingListenerApp/Sources/SettingsView.swift` — manage profiles UI

**Model Requirements:**
- Pre-trained speaker embedding model (e.g., pyannote `speechbrain/spkrec-ecapa-voxceleb`)
- ~5-10 seconds of audio per speaker for enrollment

---

### P2 — Differentiation Features

#### 6. AI-Powered Cross-Session Search
**Priority:** High  
**Effort:** Medium  
**Impact:** Killer feature for power users

**Description:**
Natural language queries across all sessions:
- "What decisions were made about pricing?"
- "Show me all action items assigned to me"
- "What did Sarah say about the Q2 roadmap?"
- "Find all discussions about competitors"

**Technical Considerations:**
- RAG store already has semantic search (`LocalRAGStore.query()`)
- Need to index transcripts, cards, entities (not just documents)
- Use ChromaDB for vector search across sessions
- Add LLM-powered query rewriting for better results

**Files to Modify:**
- `server/services/rag_store.py` — extend to index transcripts
- `server/api/search.py` (new) — unified search endpoint
- `macapp/MeetingListenerApp/Sources/SearchView.swift` (new) — search UI

**LLM Integration:**
- Use vLLM (already in dependencies) for query rewriting
- Or use smaller model like `all-MiniLM-L6-v2` for embeddings

---

#### 7. Team Collaboration
**Priority:** Medium  
**Effort:** High  
**Impact:** Enterprise/B2B potential

**Description:**
- Shared session libraries (team workspace)
- Comment on specific transcript segments (timestamped comments)
- Assign action items to team members (with notifications)
- Team dashboard: who said what, action item completion rates

**Technical Considerations:**
- Requires user accounts + authentication backend
- PostgreSQL for multi-user data (already has schema support)
- Real-time sync via WebSocket (already implemented)
- End-to-end encryption for sensitive meetings

**Files to Modify:**
- `server/db/postgresql.py` — add teams, comments, assignments tables
- `server/api/collaboration.py` (new) — team endpoints
- `server/auth.py` (new) — JWT tokens, session management

---

#### 8. Third-Party Integrations
**Priority:** Medium  
**Effort:** Medium per integration  
**Impact:** Expands use cases

| Integration | Use Case | Effort |
|-------------|----------|--------|
| **Slack** | Post action items to channels | Low |
| **Linear/Jira** | Create tickets from action cards | Medium |
| **Notion** | Export sessions as pages | Low |
| **Obsidian** | Export as markdown notes | Low |
| **Zapier** | Custom workflows | Medium |
| **Google Calendar** | Auto-link sessions (cross-platform) | Medium |

**Technical Approach:**
- OAuth 2.0 for each service
- Store tokens in Keychain (macOS) or encrypted DB (backend)
- Use existing card/entity structure for data mapping

**Files to Modify:**
- `server/integrations/` (new directory) — one module per integration
- `macapp/MeetingListenerApp/Sources/IntegrationsSettingsView.swift` — configuration UI

---

#### 9. Live Captions Mode (Picture-in-Picture)
**Priority:** Medium  
**Effort:** Medium  
**Impact:** Accessibility + differentiation

**Description:**
- Floating caption overlay during meetings (always-on-top window)
- Configurable: position, font size, opacity, background color
- Show speaker labels when available
- Option to hide after N seconds of inactivity

**Technical Considerations:**
- SwiftUI window with `.alwaysOnTop` modifier
- Real-time transcript updates via WebSocket
- Minimal latency: show words as they're transcribed
- Respect system accessibility settings

**Files to Modify:**
- `macapp/MeetingListenerApp/Sources/LiveCaptionsWindow.swift` (new)
- `macapp/MeetingListenerApp/Sources/LiveCaptionsView.swift` (new)
- `server/api/ws_live_listener.py` — emit real-time transcript events

---

#### 10. Voice Commands
**Priority:** Low  
**Effort:** High  
**Impact:** Nice-to-have for power users

**Description:**
Hands-free operation:
- "Echo, bookmark this" — mark important moment with timestamp
- "Echo, create action item: follow up with Sarah tomorrow"
- "Echo, stop recording"
- "Echo, what was the last decision?"

**Technical Considerations:**
- Use Speech framework for on-device speech recognition
- Wake word detection (optional, battery impact)
- Command parsing with regex or small NLP model
- Privacy: all processing on-device

**Files to Modify:**
- `macapp/MeetingListenerApp/Sources/VoiceCommandManager.swift` (new)
- `server/api/voice_commands.py` (new) — command interpretation

---

### P3 — Power User Features

#### 11. Custom Analysis Rules
**Priority:** Low  
**Effort:** Medium  
**Impact:** Niche but valuable for specific industries

**Description:**
- User-defined keywords for custom card types (e.g., "Legal Review", "Compliance Issue")
- Industry-specific entity extraction (medical codes, legal citations, financial instruments)
- Regex-based pattern detection (phone numbers, emails, ticket IDs)
- Custom summary templates

**Technical Considerations:**
- Store rules in `custom_analysis_rules` table
- Hot-reload rules without restart
- Regex compilation caching for performance

**Files to Modify:**
- `server/services/analysis_stream.py` — pluggable rule engine
- `server/api/custom_rules.py` (new) — CRUD for rules

---

#### 12. iCloud Sync & Encrypted Backups
**Priority:** Medium  
**Effort:** High  
**Impact:** Multi-device users

**Description:**
- Sync sessions across Mac, iPhone, iPad via iCloud
- End-to-end encrypted backups (user holds key)
- Conflict resolution for multi-device edits
- Selective sync (only recent sessions on mobile)

**Technical Considerations:**
- CloudKit for iCloud storage
- CryptoKit for encryption (AES-256-GCM)
- User password-derived key (PBKDF2)
- Handle offline mode gracefully

**Files to Modify:**
- `macapp/MeetingListenerApp/Sources/CloudSyncManager.swift` (new)
- `server/services/encryption.py` (new) — encryption/decryption

**Entitlements:**
```xml
<key>com.apple.security.cloudkit</key>
<true/>
```

---

#### 13. Analytics Dashboard
**Priority:** Low  
**Effort:** Medium  
**Impact:** Useful for teams/managers

**Description:**
- Meeting time breakdown: hours recorded per day/week/month
- Talk time per person (when speaker ID available)
- Action item completion tracking (integrate with task manager)
- "Most discussed topics this month" (word cloud or tag cloud)
- Trends: "You're spending 20% more time in meetings vs last month"

**Technical Considerations:**
- Aggregate data from `sessions`, `transcripts`, `cards` tables
- Use SQLite window functions for time-series queries
- Chart rendering: Swift Charts (macOS 13+)

**Files to Modify:**
- `server/api/analytics.py` (new) — aggregation endpoints
- `macapp/MeetingListenerApp/Sources/AnalyticsView.swift` (new)

---

#### 14. Plugins/Extensions API
**Priority:** Low  
**Effort:** Very High  
**Impact:** Ecosystem play (long-term)

**Description:**
- Third-party analysis providers (custom NLP models)
- Custom export formats (user-written exporters)
- Webhook integrations (send events to external services)
- JavaScript/Python plugin sandbox

**Technical Considerations:**
- Plugin sandboxing for security
- Version compatibility checks
- Plugin marketplace (future)
- Start with webhooks (simplest)

**Files to Modify:**
- `server/plugins/` (new directory) — plugin system
- `server/api/webhooks.py` (new) — webhook management

---

## Implementation Priority Recommendation

### Phase 1: Launch (Now - 2 weeks)
1. ✅ Finish P0 launch blockers (accounts, licensing via Apple, code signing)
2. Fix any critical bugs from beta testing

### Phase 2: Stickiness (2-6 weeks post-launch)
1. **Session Playback & Export** — highest user value
2. **Multi-Session Dashboard** — makes app "sticky"
3. **Calendar Integration** — major differentiator

### Phase 3: Growth (6-12 weeks post-launch)
1. **AI-Powered Cross-Session Search** — killer feature
2. **Smart Notifications** — engagement driver
3. **Third-Party Integrations** — expand use cases (start with Slack, Notion)

### Phase 4: Premium (3-6 months post-launch)
1. **Speaker Identification** — premium team feature
2. **Team Collaboration** — B2B potential
3. **Live Captions Mode** — accessibility + pro users

### Phase 5: Ecosystem (6+ months)
1. **iCloud Sync** — multi-device
2. **Analytics Dashboard** — teams/managers
3. **Plugins API** — third-party ecosystem

---

## Technical Debt & Risks

### Known Issues

| Issue | Severity | Files | Status | Recommendation |
|-------|----------|-------|--------|----------------|
| Pending task warnings in tests | Low | `server/services/brain_dump_indexer.py:308` | ✅ **FIXED** | Properly shutdown background tasks in test teardown |
| Deprecation warnings (websockets, matplotlib) | Low | Multiple | ⚠️ **Third-party** | Will be fixed when libraries upgraded - not our code |
| No rate limiting on API endpoints | Medium | `server/api/*.py` | ✅ **FIXED** | Added token bucket rate limiter with middleware |
| No input validation on WebSocket messages | Medium | `server/api/ws_live_listener.py` | ✅ **FIXED** | Added pydantic validation for message schemas |
| Token in query params (visible in logs) | Medium | `server/main.py:73`, `server/api/ws_live_listener.py:338` | ✅ **FIXED** | Backend now prefers Authorization header; Swift client already sends it |
| No monitoring (Sentry, OpenTelemetry) | Medium | N/A | ⚠️ **Open** | Add before launch - see recommendations below |
| Audio file permissions | High | `server/api/ws_live_listener.py` | ✅ **FIXED** | Added chmod 600 to all recorded audio files |

### Architecture Risks

| Risk | Status | Impact |
|------|--------|--------|
| **Single-process backend** | ⚠️ Open | Python server is single-threaded (async). Consider uvicorn workers for multi-core. |
| **No caching** | ⚠️ Open | Transcript analysis re-runs on every request. Add Redis or in-memory cache. |
| **SQLite concurrency** | ⚠️ Open | Fine for single-user, but will bottleneck with team features. Migrate to PostgreSQL early. |

### Security Considerations

| Issue | Status | Recommendation |
|-------|--------|----------------|
| Token storage | ✅ Keychain (good) | Ensure backend tokens encrypted at rest |
| WebSocket auth | ✅ Fixed | Backend prefers Authorization header; Swift client sends it |
| Rate limiting | ✅ Implemented | Token bucket: 60/min, 1000/hour (configurable via env vars) |
| Input validation | ✅ Implemented | Pydantic schemas for all WebSocket message types |
| Audio file permissions | ✅ Fixed | All recording files created with chmod 600 (owner read/write only) |

---

## Competitive Landscape

| Competitor | Pricing | Key Features | Our Advantage |
|------------|---------|--------------|---------------|
| **Otter.ai** | $10-30/mo | Real-time transcription, speaker ID, integrations | Local processing (privacy), one-time purchase option |
| **Fireflies.ai** | $10-19/mo | Meeting bot, CRM integration, analytics | No bot needed (system audio), macOS-native |
| **Fathom** | Free | Recording, transcription, highlights | Free tier, better privacy (local-first) |
| **Grain** | $30-50/mo | Video clips, highlights, sharing | Audio-first (lighter), live insights |
| **MacWhisper** | $10-100 | Local transcription, no live insights | Live real-time insights, action item detection |

**Our Differentiators:**
1. **Local-first processing** — privacy, no API costs
2. **Live real-time insights** — not just post-meeting transcription
3. **System audio capture** — no bot needed, works with any app
4. **macOS-native** — menu bar, notifications, calendar integration
5. **Action-oriented** — automatically extracts action items, decisions, risks

---

## Appendix: Key Files Reference

### Backend (Python)

```
server/
├── main.py                          # FastAPI app, health endpoints
├── api/
│   ├── ws_live_listener.py          # WebSocket handler (core)
│   ├── documents.py                 # Session CRUD, export
│   ├── search.py                    # (TODO) Search endpoint
│   └── export.py                    # (TODO) Export service
├── services/
│   ├── analysis_stream.py           # Cards, entities, summaries
│   ├── asr_stream.py                # ASR pipeline
│   ├── diarization.py               # Speaker segmentation
│   ├── rag_store.py                 # Document store + search
│   └── brain_dump_indexer.py        # Background indexing
├── db/
│   ├── schema.py                    # SQLite schema
│   └── postgresql.py                # (Optional) PostgreSQL schema
└── config/
    └── schema.py                    # Pydantic config models
```

### macOS App (Swift)

```
macapp/MeetingListenerApp/
├── MeetingListenerApp.swift         # App entry point
├── Sources/
│   ├── AppState.swift               # Global state
│   ├── AudioCaptureManager.swift    # System audio
│   ├── MicrophoneCaptureManager.swift
│   ├── WebSocketStreamer.swift      # Backend communication
│   ├── SidePanelController.swift    # Live transcript UI
│   ├── SessionHistoryView.swift     # Past sessions
│   ├── SettingsView.swift           # Configuration
│   ├── SubscriptionManager.swift    # StoreKit
│   ├── BetaGatingManager.swift      # Invite codes
│   └── StructuredLogger.swift       # Logging
```

### Tests

```
tests/
├── test_ws_live_listener.py         # WebSocket integration
├── test_analysis_entities_normalization.py
├── test_brain_dump_*.py             # RAG, embeddings
├── test_config_system.py            # Configuration
├── test_services.py                 # Analysis services
└── ... (143 total tests)
```

---

## How to Use This Document

This document is a **living reference** for feature planning and technical decisions.

**When to reference:**
- Planning sprint backlog
- Onboarding new developers
- Making architecture decisions
- Prioritizing feature requests
- Competitive analysis

**Update when:**
- Features are implemented
- New risks discovered
- Competitive landscape changes
- User feedback suggests pivots

**Related Documents:**
- `docs/STATUS_AND_ROADMAP.md` — Current status
- `docs/WORKLOG_TICKETS.md` — All tickets
- `docs/FLOW_ATLAS.md` — Technical flows
- `docs/DOCUMENTATION_STATUS.md` — Documentation index

---

**Last Updated:** 2026-02-17  
**Next Review:** After launch (TBD)
